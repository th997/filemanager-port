//! Task runner and cross-VFS operations engine.

use fm_core::{EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use crate::{ConflictPolicy, TaskHistoryRecord, TaskProgress, TaskState};

/// Cooperative pause and bandwidth-throttling control shared between
/// `TaskManager` and a running transfer worker.
#[derive(Clone)]
pub struct TaskControl {
    paused: Arc<AtomicBool>,
    notify: Arc<Notify>,
    rate_limit_bps: Arc<AtomicU64>,
    resumable: Arc<AtomicBool>,
}

impl Default for TaskControl {
    fn default() -> Self {
        Self::new()
    }
}

impl TaskControl {
    pub fn new() -> Self {
        Self {
            paused: Arc::new(AtomicBool::new(false)),
            notify: Arc::new(Notify::new()),
            rate_limit_bps: Arc::new(AtomicU64::new(0)),
            resumable: Arc::new(AtomicBool::new(true)),
        }
    }

    pub fn set_paused(&self, paused: bool) {
        self.paused.store(paused, Ordering::SeqCst);
        if !paused {
            self.notify.notify_waiters();
        }
    }

    pub fn is_paused(&self) -> bool {
        self.paused.load(Ordering::SeqCst)
    }

    pub fn set_rate_limit(&self, bps: u64) {
        self.rate_limit_bps.store(bps, Ordering::Relaxed);
    }

    pub fn rate_limit(&self) -> u64 {
        self.rate_limit_bps.load(Ordering::Relaxed)
    }

    pub fn set_resumable(&self, resumable: bool) {
        self.resumable.store(resumable, Ordering::Relaxed);
    }

    pub fn is_resumable(&self) -> bool {
        self.resumable.load(Ordering::Relaxed)
    }

    /// Blocks while paused until either resumed or cancelled.
    pub async fn wait_if_paused(
        &self,
        progress: &Arc<Mutex<TaskProgress>>,
        cancel: &CancellationToken,
    ) -> VfsResult<()> {
        while self.paused.load(Ordering::SeqCst) {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported {
                    operation: "cancelled",
                });
            }
            {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                if !p.is_terminal() {
                    p.state = TaskState::Paused;
                }
            }
            let notified = self.notify.notified();
            if !self.paused.load(Ordering::SeqCst) {
                break;
            }
            tokio::select! {
                _ = cancel.cancelled() => {
                    return Err(VfsError::Unsupported { operation: "cancelled" });
                }
                _ = notified => {}
            }
        }
        if cancel.is_cancelled() {
            return Err(VfsError::Unsupported {
                operation: "cancelled",
            });
        }
        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            if p.state == TaskState::Paused {
                p.state = TaskState::Running;
            }
        }
        Ok(())
    }

    /// Sleeps proportionally when a rate limit is configured.
    pub async fn throttle(
        &self,
        bytes: u64,
        elapsed: Duration,
        cancel: &CancellationToken,
    ) -> VfsResult<()> {
        let limit = self.rate_limit_bps.load(Ordering::Relaxed);
        if limit == 0 || bytes == 0 {
            return Ok(());
        }
        let expected_secs = (bytes as f64) / (limit as f64);
        let expected = Duration::from_secs_f64(expected_secs.min(5.0));
        if expected > elapsed {
            let sleep_dur = expected - elapsed;
            tokio::select! {
                _ = cancel.cancelled() => {
                    return Err(VfsError::Unsupported { operation: "cancelled" });
                }
                _ = tokio::time::sleep(sleep_dur) => {}
            }
        }
        Ok(())
    }
}

pub struct TaskHandle {
    pub progress: Arc<Mutex<TaskProgress>>,
    pub cancel: CancellationToken,
    pub control: TaskControl,
}

/// Finished tasks stay in the registry so a task centre can show recent
/// history; keep at most this many terminal entries so a long session
/// cannot grow the list without bound.
const MAX_TERMINAL_TASKS_KEPT: usize = 50;

#[derive(Clone, Default)]
pub struct TaskManager {
    // Insertion-ordered: a task list reads oldest → newest.
    tasks: Arc<RwLock<Vec<(String, TaskHandle)>>>,
    history_path: Arc<RwLock<Option<PathBuf>>>,
}

impl TaskManager {
    pub fn new() -> Self {
        Self {
            tasks: Arc::new(RwLock::new(Vec::new())),
            history_path: Arc::new(RwLock::new(None)),
        }
    }

    /// Configure a JSON file path for persisting task history across restarts
    /// and immediately hydrate any saved history entries.
    pub fn set_history_path(&self, path: PathBuf) {
        let already_same = self
            .history_path
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            == Some(&path);
        if already_same {
            return;
        }
        *self.history_path.write().unwrap_or_else(|e| e.into_inner()) = Some(path.clone());
        let _ = self.load_history_from(&path);
    }

    pub fn load_history_from(&self, path: &Path) -> std::io::Result<usize> {
        if !path.exists() {
            return Ok(0);
        }
        let raw = std::fs::read_to_string(path)?;
        let records: Vec<TaskHistoryRecord> =
            serde_json::from_str(&raw).unwrap_or_default();
        let count = records.len();
        self.restore_history(records);
        Ok(count)
    }

    pub fn restore_history(&self, records: Vec<TaskHistoryRecord>) {
        let mut tasks = self.tasks.write().unwrap_or_else(|e| e.into_inner());
        for record in records.into_iter().take(MAX_TERMINAL_TASKS_KEPT) {
            if tasks.iter().any(|(id, _)| id == &record.id) {
                continue;
            }
            let progress = Arc::new(Mutex::new(TaskProgress::from_history(&record)));
            let cancel = CancellationToken::new();
            cancel.cancel();
            tasks.push((
                record.id,
                TaskHandle {
                    progress,
                    cancel,
                    control: TaskControl::new(),
                },
            ));
        }
    }

    pub fn export_history(&self) -> Vec<TaskHistoryRecord> {
        self.tasks
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .filter_map(|(id, h)| {
                let p = h.progress.lock().unwrap_or_else(|e| e.into_inner());
                if p.is_terminal() {
                    Some(p.to_history(id))
                } else {
                    None
                }
            })
            .collect()
    }

    pub fn persist_history(&self) {
        let path = self
            .history_path
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let Some(path) = path else {
            return;
        };
        let records = self.export_history();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(&records) {
            let _ = std::fs::write(&path, json);
        }
    }

    pub fn register(&self, id: &str) -> (Arc<Mutex<TaskProgress>>, CancellationToken) {
        let (progress, cancel, _control) = self.register_with_control(id);
        (progress, cancel)
    }

    pub fn register_with_control(
        &self,
        id: &str,
    ) -> (Arc<Mutex<TaskProgress>>, CancellationToken, TaskControl) {
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        let cancel = CancellationToken::new();
        let control = TaskControl::new();
        let handle = TaskHandle {
            progress: progress.clone(),
            cancel: cancel.clone(),
            control: control.clone(),
        };
        let mut tasks = self.tasks.write().unwrap_or_else(|e| e.into_inner());
        tasks.retain(|(existing, _)| existing != id);
        // Prune the oldest finished tasks beyond the history cap.
        let mut terminal = tasks
            .iter()
            .filter(|(_, h)| {
                h.progress.lock().unwrap_or_else(|e| e.into_inner()).is_terminal()
            })
            .count();
        while terminal > MAX_TERMINAL_TASKS_KEPT {
            let Some(pos) = tasks.iter().position(|(_, h)| {
                h.progress.lock().unwrap_or_else(|e| e.into_inner()).is_terminal()
            }) else {
                break;
            };
            tasks.remove(pos);
            terminal -= 1;
        }
        tasks.push((id.to_string(), handle));
        (progress, cancel, control)
    }

    fn find(&self, id: &str) -> Option<TaskHandle> {
        self.tasks
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .find(|(existing, _)| existing == id)
            .map(|(_, h)| TaskHandle {
                progress: h.progress.clone(),
                cancel: h.cancel.clone(),
                control: h.control.clone(),
            })
    }

    pub fn get_progress(&self, id: &str) -> Option<TaskProgress> {
        self.find(id)
            .map(|h| h.progress.lock().unwrap_or_else(|e| e.into_inner()).clone())
    }

    pub fn pause(&self, id: &str) -> bool {
        if let Some(handle) = self.find(id) {
            let mut p = handle.progress.lock().unwrap_or_else(|e| e.into_inner());
            if !matches!(p.state, TaskState::Pending | TaskState::Running) {
                return false;
            }
            handle.control.set_paused(true);
            p.state = TaskState::Paused;
            true
        } else {
            false
        }
    }

    pub fn resume(&self, id: &str) -> bool {
        if let Some(handle) = self.find(id) {
            let mut p = handle.progress.lock().unwrap_or_else(|e| e.into_inner());
            if p.state != TaskState::Paused {
                return false;
            }
            handle.control.set_paused(false);
            p.state = TaskState::Running;
            true
        } else {
            false
        }
    }

    pub fn set_rate_limit(&self, id: &str, bytes_per_sec: u64) -> bool {
        if let Some(handle) = self.find(id) {
            handle.control.set_rate_limit(bytes_per_sec);
            let mut p = handle.progress.lock().unwrap_or_else(|e| e.into_inner());
            p.rate_limit_bps = bytes_per_sec;
            true
        } else {
            false
        }
    }

    pub fn cancel(&self, id: &str) -> bool {
        if let Some(handle) = self.find(id) {
            let mut p = handle.progress.lock().unwrap_or_else(|e| e.into_inner());
            // A finished task must not be rewritten as cancelled: the row
            // would claim the work was aborted after it actually completed.
            if matches!(
                p.state,
                TaskState::Completed | TaskState::Failed | TaskState::Cancelled
            ) {
                return false;
            }
            handle.control.set_paused(false);
            handle.cancel.cancel();
            p.state = TaskState::Cancelled;
            drop(p);
            self.persist_history();
            true
        } else {
            false
        }
    }

    /// All registered tasks in insertion order, finished ones included.
    pub fn list_active(&self) -> Vec<(String, TaskProgress)> {
        self.tasks
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(id, h)| (id.clone(), h.progress.lock().unwrap_or_else(|e| e.into_inner()).clone()))
            .collect()
    }

    /// Drop a task from the registry (the task centre's dismiss action).
    pub fn remove(&self, id: &str) -> bool {
        // Dismissing a task that is still running cancels it first:
        // otherwise the worker keeps going invisibly after its
        // progress UI is gone, holding connections and file handles.
        if let Some(handle) = self.find(id) {
            let terminal = handle
                .progress
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .is_terminal();
            if !terminal {
                handle.control.set_paused(false);
                handle.cancel.cancel();
            }
        }
        let mut tasks = self.tasks.write().unwrap_or_else(|e| e.into_inner());
        let before = tasks.len();
        tasks.retain(|(existing, _)| existing != id);
        let removed = tasks.len() != before;
        drop(tasks);
        if removed {
            self.persist_history();
        }
        removed
    }
}

/// Sum the byte size of a file or directory tree, for progress totals.
pub async fn total_bytes(vfs: &dyn Vfs, path: &VfsPath) -> u64 {
    let stat = match vfs.stat(path).await {
        Ok(stat) => stat,
        Err(_) => return 0,
    };
    if stat.kind != EntryKind::Dir || stat.is_symlink {
        // A symlinked directory is a leaf for sizing: following it would
        // count the target tree as well — possibly the same tree again when
        // the link points back into an ancestor.
        return stat.size.unwrap_or(0);
    }
    let children = match vfs.list(path).await {
        Ok(children) => children,
        Err(_) => return 0,
    };
    let mut total = 0;
    for child in children {
        if child.kind == EntryKind::Dir && !child.is_symlink {
            total += Box::pin(total_bytes(vfs, &child.path)).await;
        } else {
            total += child.size.unwrap_or(0);
        }
    }
    total
}

/// Pick a free sibling name for `dst_path` using the app's `_copy` scheme
/// (`name_copy.ext`, then `name_copy_2.ext`, ...). Used by the `Rename`
/// conflict policy so an incoming file never has to destroy an existing one.
async fn free_copy_path(dst_vfs: &dyn Vfs, dst_path: &VfsPath) -> VfsPath {
    let name = dst_path.name().unwrap_or("file");
    let (stem, ext) = match name.rfind('.') {
        Some(idx) if idx > 0 => (&name[..idx], &name[idx..]),
        _ => (name, ""),
    };
    let parent = dst_path.parent().unwrap_or_else(VfsPath::root);
    let mut candidate = format!("{stem}_copy{ext}");
    let mut count = 2;
    while dst_vfs.stat(&parent.join(&candidate)).await.is_ok() {
        candidate = format!("{stem}_copy_{count}{ext}");
        count += 1;
        if count > 1000 {
            break;
        }
    }
    parent.join(candidate)
}

/// Recursively copy a file or directory from `src_vfs` to `dst_vfs`.
///
/// `policy` decides what happens when a file's destination already exists;
/// directories always merge (their contents are decided per file).
pub async fn copy_recursive(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    policy: ConflictPolicy,
) -> VfsResult<()> {
    copy_recursive_impl(
        src_vfs, src_path, None, dst_vfs, dst_path, progress, cancel, None, policy,
    )
    .await
}

/// Like [`copy_recursive`], with pause/resume, bandwidth throttling, and
/// partial-file resume support.
#[allow(clippy::too_many_arguments)]
pub async fn copy_recursive_with_control(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: &TaskControl,
    policy: ConflictPolicy,
) -> VfsResult<()> {
    copy_recursive_impl(
        src_vfs,
        src_path,
        None,
        dst_vfs,
        dst_path,
        progress,
        cancel,
        Some(control),
        policy,
    )
    .await
}

// All values are threaded through the recursive copy without being
// repacked into a context struct; splitting them would only add indirection.
#[allow(clippy::too_many_arguments)]
async fn copy_recursive_impl(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    known_stat: Option<(EntryKind, bool)>,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: Option<&TaskControl>,
    policy: ConflictPolicy,
) -> VfsResult<()> {
    if let Some(ctrl) = control {
        ctrl.wait_if_paused(progress, cancel).await?;
    }
    if cancel.is_cancelled() {
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    let (kind, is_symlink) = match known_stat {
        Some(s) => s,
        None => {
            let stat = src_vfs.stat(src_path).await?;
            (stat.kind, stat.is_symlink)
        }
    };
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        if p.state != TaskState::Cancelled {
            p.state = TaskState::Running;
        }
        p.current = Some(src_path.clone());
    }

    if is_symlink && (kind == EntryKind::Dir || kind == EntryKind::Symlink) {
        // Never recurse through a directory symlink: the target may live outside the
        // tree being copied or point back into it, nesting without bound.
        // Also skip broken symlinks which cannot be read as regular files.
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.skipped += 1;
        return Ok(());
    }

    if kind == EntryKind::Other {
        // Unix domain sockets, FIFOs, special device nodes cannot be streamed.
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.skipped += 1;
        return Ok(());
    }

    if kind == EntryKind::Dir {
        if let Err(e) = dst_vfs.mkdir(dst_path).await {
            // An already-existing directory is fine; any other failure
            // (permission, read-only backend, a file in the way) is real
            // and must surface instead of burying itself under a stream
            // of misleading per-file errors.
            let already_dir = dst_vfs
                .stat(dst_path)
                .await
                .map(|s| s.kind == EntryKind::Dir)
                .unwrap_or(false);
            if !already_dir {
                return Err(e);
            }
        }
        let children = src_vfs.list(src_path).await?;
        for child in children {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            let child_src = child.path.clone();
            let child_dst = dst_path.join(child.name.clone());
            Box::pin(copy_recursive_impl(
                src_vfs,
                &child_src,
                Some((child.kind, child.is_symlink)),
                dst_vfs,
                &child_dst,
                progress,
                cancel,
                control,
                policy,
            ))
            .await?;
        }
    } else {
        copy_single_file(
            src_vfs, src_path, dst_vfs, dst_path, progress, cancel, control, policy,
        )
        .await?;
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn copy_single_file(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: Option<&TaskControl>,
    policy: ConflictPolicy,
) -> VfsResult<()> {
    // Resolve a name clash before moving any bytes. Until the policy
    // existed, an existing destination file was silently replaced.
    let mut target = dst_path.clone();
    let mut existed_before = false;
    if let Ok(existing) = dst_vfs.stat(dst_path).await {
        match policy {
            ConflictPolicy::Skip => {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.skipped += 1;
                p.policy_skips += 1;
                return Ok(());
            }
            ConflictPolicy::Rename => {
                target = free_copy_path(dst_vfs, dst_path).await;
            }
            ConflictPolicy::Overwrite => {
                if existing.kind == EntryKind::Dir {
                    return Err(VfsError::Backend {
                        path: dst_path.clone(),
                        source: std::io::Error::new(
                            std::io::ErrorKind::AlreadyExists,
                            "destination is a directory",
                        ),
                    });
                }
                existed_before = true;
            }
        }
    }

    // For backends that prefer direct write (such as object storage S3/OSS which lacks
    // atomic rename and already provides atomic uploads natively via multipart):
    // stream directly into target. This avoids expensive server-side copies and 100% hangs.
    if dst_vfs.prefers_direct_write() {
        if let Err(e) =
            stream_into(src_vfs, src_path, dst_vfs, &target, progress, cancel, control, false).await
        {
            // Object-storage uploads are atomic until shutdown(), so a failed or cancelled
            // overwrite leaves the prior object intact — do not delete it.
            if !existed_before {
                let _ = dst_vfs.remove(&target).await;
            }
            return Err(e);
        }
        return Ok(());
    }

    // Stream into a sibling temp file and rename it over the destination
    // only once the copy is complete. When resumable transfer is enabled, a
    // deterministic `.fm-resume` temp name allows a subsequent retry to append
    // from the already-written byte offset via `open_read_range`.
    let dst_name = target.name().unwrap_or("file");
    let use_resume = control.map(|c| c.is_resumable()).unwrap_or(false);
    let tmp_name = if use_resume {
        format!(".{dst_name}.fm-resume")
    } else {
        format!(
            "{dst_name}.{}.fm-part",
            uuid::Uuid::new_v4().simple()
        )
    };
    let tmp_path = target
        .parent()
        .unwrap_or_else(VfsPath::root)
        .join(tmp_name);

    if let Err(e) =
        stream_into(src_vfs, src_path, dst_vfs, &tmp_path, progress, cancel, control, use_resume)
            .await
    {
        // Keep the `.fm-resume` partial file on transient network/IO errors so
        // a retry can resume from the last written byte; remove it on explicit cancel.
        if !use_resume || cancel.is_cancelled() {
            let _ = dst_vfs.remove(&tmp_path).await;
        }
        return Err(e);
    }
    // The bytes may all be in the temp file already when cancel arrives;
    // publishing it then would silently complete a cancelled copy.
    if cancel.is_cancelled() {
        let _ = dst_vfs.remove(&tmp_path).await;
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    match dst_vfs.rename(&tmp_path, &target).await {
        Ok(()) => Ok(()),
        Err(first_err) => {
            // Some backends refuse to rename onto an existing file; retry
            // once after removing it — but never remove a directory to
            // make room for a file.
            let dst_is_dir = dst_vfs
                .stat(&target)
                .await
                .map(|s| s.kind == EntryKind::Dir)
                .unwrap_or(false);
            if dst_is_dir {
                let _ = dst_vfs.remove(&tmp_path).await;
                return Err(first_err);
            }
            // Move the old file aside instead of deleting it: if the second
            // rename fails too, the previous version is still recoverable.
            let backup_path = target
                .parent()
                .unwrap_or_else(VfsPath::root)
                .join(format!(
                    "{dst_name}.{}.fm-old",
                    uuid::Uuid::new_v4().simple()
                ));
            let had_backup = dst_vfs.rename(&target, &backup_path).await.is_ok();
            if dst_vfs.rename(&tmp_path, &target).await.is_err() {
                if had_backup {
                    let _ = dst_vfs.rename(&backup_path, &target).await;
                }
                let _ = dst_vfs.remove(&tmp_path).await;
                // If rename still failed (e.g. backend lacks rename capability or refuses temp file rename),
                // rollback progress before streaming directly into target so progress doesn't stick at 100%.
                let file_len = src_vfs.stat(src_path).await.map(|s| s.size.unwrap_or(0)).unwrap_or(0);
                if file_len > 0 {
                    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                    p.completed = p.completed.saturating_sub(file_len);
                }
                return stream_into(
                    src_vfs, src_path, dst_vfs, &target, progress, cancel, control, false,
                )
                .await;
            }
            if had_backup {
                let _ = dst_vfs.remove(&backup_path).await;
            }
            Ok(())
        }
    }
}

#[allow(clippy::too_many_arguments)]
async fn stream_into(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    tmp_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: Option<&TaskControl>,
    try_resume: bool,
) -> VfsResult<()> {
    // Check if an existing partial file can be resumed via byte-range read + Append.
    let mut resume_offset = 0u64;
    if try_resume {
        if let (Ok(src_stat), Ok(part_stat)) =
            (src_vfs.stat(src_path).await, dst_vfs.stat(tmp_path).await)
        {
            let src_len = src_stat.size.unwrap_or(0);
            let part_len = part_stat.size.unwrap_or(0);
            if part_stat.kind == EntryKind::File && part_len > 0 && part_len < src_len {
                resume_offset = part_len;
            }
        }
    }

    let (mut reader, mut writer) = if resume_offset > 0 {
        match (
            src_vfs.open_read_range(src_path, resume_offset, None).await,
            dst_vfs.open_write(tmp_path, WriteMode::Append).await,
        ) {
            (Ok(r), Ok(w)) => {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.completed += resume_offset;
                (r, w)
            }
            _ => {
                let r = src_vfs.open_read(src_path).await?;
                let w = dst_vfs.open_write(tmp_path, WriteMode::Truncate).await?;
                (r, w)
            }
        }
    } else {
        let r = src_vfs.open_read(src_path).await?;
        let w = dst_vfs.open_write(tmp_path, WriteMode::Truncate).await?;
        (r, w)
    };

    let mut buf = vec![0u8; 256 * 1024];
    let mut unreported: u64 = 0;
    const PROGRESS_BATCH: u64 = 256 * 1024;
    loop {
        if let Some(ctrl) = control {
            ctrl.wait_if_paused(progress, cancel).await?;
        }
        if cancel.is_cancelled() {
            if unreported > 0 {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.completed += unreported;
            }
            return Err(VfsError::Unsupported { operation: "cancelled" });
        }
        let chunk_start = Instant::now();
        let n = tokio::select! {
            _ = cancel.cancelled() => {
                if unreported > 0 {
                    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                    p.completed += unreported;
                }
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            res = reader.read(&mut buf) => res.map_err(|e| VfsError::Backend {
                path: src_path.clone(),
                source: e,
            })?,
        };
        if n == 0 {
            break;
        }
        writer
            .write_all(&buf[..n])
            .await
            .map_err(|e| VfsError::Backend {
                path: tmp_path.clone(),
                source: e,
            })?;

        if let Some(ctrl) = control {
            ctrl.throttle(n as u64, chunk_start.elapsed(), cancel).await?;
        }

        unreported += n as u64;
        if unreported >= PROGRESS_BATCH {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed += unreported;
            unreported = 0;
        }
    }
    if unreported > 0 {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.completed += unreported;
    }
    writer.flush().await.map_err(|e| VfsError::Backend {
        path: tmp_path.clone(),
        source: e,
    })?;
    // Propagate shutdown errors: remote upload writers report their final
    // result here, and ignoring it could publish an incomplete file.
    writer.shutdown().await.map_err(|e| VfsError::Backend {
        path: tmp_path.clone(),
        source: e,
    })?;

    Ok(())
}

/// Recursively delete a file or directory.
pub async fn delete_recursive(
    vfs: &dyn Vfs,
    path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    delete_recursive_impl(vfs, path, None, progress, cancel).await
}

async fn delete_recursive_impl(
    vfs: &dyn Vfs,
    path: &VfsPath,
    known_stat: Option<(EntryKind, bool)>,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    if cancel.is_cancelled() {
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        if p.state != TaskState::Cancelled {
            p.state = TaskState::Running;
        }
        p.current = Some(path.clone());
    }

    let (kind, is_symlink) = match known_stat {
        Some(s) => s,
        None => {
            let stat = vfs.stat(path).await?;
            (stat.kind, stat.is_symlink)
        }
    };
    // A symlinked directory is removed as a link, never traversed: the
    // entries under it belong to the link target, which may be anywhere —
    // including outside the tree the user selected for deletion.
    if kind == EntryKind::Dir && !is_symlink {
        let children = vfs.list(path).await?;
        for child in children {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            Box::pin(delete_recursive_impl(
                vfs,
                &child.path,
                Some((child.kind, child.is_symlink)),
                progress,
                cancel,
            ))
            .await?;
        }
    }

    vfs.remove(path).await?;
    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
    p.completed += 1;
    Ok(())
}
