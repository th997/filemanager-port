//! Task runner and cross-VFS operations engine.

use fm_core::{EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::sync::{Arc, Mutex, RwLock};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

use crate::{ConflictPolicy, TaskProgress, TaskState};

pub struct TaskHandle {
    pub progress: Arc<Mutex<TaskProgress>>,
    pub cancel: CancellationToken,
}

/// Finished tasks stay in the registry so a task centre can show recent
/// history; keep at most this many terminal entries so a long session
/// cannot grow the list without bound.
const MAX_TERMINAL_TASKS_KEPT: usize = 50;

#[derive(Clone, Default)]
pub struct TaskManager {
    // Insertion-ordered: a task list reads oldest → newest.
    tasks: Arc<RwLock<Vec<(String, TaskHandle)>>>,
}

impl TaskManager {
    pub fn new() -> Self {
        Self {
            tasks: Arc::new(RwLock::new(Vec::new())),
        }
    }

    pub fn register(&self, id: &str) -> (Arc<Mutex<TaskProgress>>, CancellationToken) {
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        let cancel = CancellationToken::new();
        let handle = TaskHandle {
            progress: progress.clone(),
            cancel: cancel.clone(),
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
        (progress, cancel)
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
            })
    }

    pub fn get_progress(&self, id: &str) -> Option<TaskProgress> {
        self.find(id)
            .map(|h| h.progress.lock().unwrap_or_else(|e| e.into_inner()).clone())
    }

    pub fn cancel(&self, id: &str) -> bool {
        if let Some(handle) = self.find(id) {
            handle.cancel.cancel();
            handle.progress.lock().unwrap_or_else(|e| e.into_inner()).state = TaskState::Cancelled;
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
                handle.cancel.cancel();
            }
        }
        let mut tasks = self.tasks.write().unwrap_or_else(|e| e.into_inner());
        let before = tasks.len();
        tasks.retain(|(existing, _)| existing != id);
        tasks.len() != before
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
        src_vfs, src_path, None, dst_vfs, dst_path, progress, cancel, policy,
    )
    .await
}

async fn copy_recursive_impl(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    known_stat: Option<(EntryKind, bool)>,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    policy: ConflictPolicy,
) -> VfsResult<()> {
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
        p.state = TaskState::Running;
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
                policy,
            ))
            .await?;
        }
    } else {
        copy_single_file(src_vfs, src_path, dst_vfs, dst_path, progress, cancel, policy).await?;
    }

    Ok(())
}

async fn copy_single_file(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    policy: ConflictPolicy,
) -> VfsResult<()> {
    // Resolve a name clash before moving any bytes. Until the policy
    // existed, an existing destination file was silently replaced.
    let mut target = dst_path.clone();
    if let Ok(existing) = dst_vfs.stat(dst_path).await {
        match policy {
            ConflictPolicy::Skip => {
                progress.lock().unwrap_or_else(|e| e.into_inner()).skipped += 1;
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
            }
        }
    }

    // Stream into a sibling temp file and rename it over the destination
    // only once the copy is complete. Writing in place with Truncate meant
    // a cancelled or failed copy both destroyed the previous version and
    // left a truncated file behind.
    let dst_name = target.name().unwrap_or("file");
    let tmp_path = target
        .parent()
        .unwrap_or_else(VfsPath::root)
        .join(format!("{dst_name}.fm-part"));

    if let Err(e) =
        stream_into(src_vfs, src_path, dst_vfs, &tmp_path, progress, cancel).await
    {
        let _ = dst_vfs.remove(&tmp_path).await;
        return Err(e);
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
            let _ = dst_vfs.remove(&target).await;
            if dst_vfs.rename(&tmp_path, &target).await.is_err() {
                let _ = dst_vfs.remove(&tmp_path).await;
                // If rename still failed (e.g. backend lacks rename capability or refuses temp file rename),
                // fallback to streaming directly into target.
                return stream_into(src_vfs, src_path, dst_vfs, &target, progress, cancel).await;
            }
            Ok(())
        }
    }
}

async fn stream_into(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    tmp_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    let mut reader = src_vfs.open_read(src_path).await?;
    let mut writer = dst_vfs.open_write(tmp_path, WriteMode::Truncate).await?;

    let mut buf = vec![0u8; 256 * 1024];
    let mut unreported: u64 = 0;
    const PROGRESS_BATCH: u64 = 256 * 1024;
    loop {
        if cancel.is_cancelled() {
            if unreported > 0 {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.completed += unreported;
            }
            return Err(VfsError::Unsupported { operation: "cancelled" });
        }
        let n = reader.read(&mut buf).await.map_err(|e| VfsError::Backend {
            path: src_path.clone(),
            source: e,
        })?;
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
        p.state = TaskState::Running;
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
