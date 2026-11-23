use crate::registry::VfsRegistry;
use fm_archive::ops::{
    create_zip_with_password, extract_archive_with_password,
};
use fm_core::{EntryKind, VfsPath};
use fm_ops::{
    copy_recursive_with_control, delete_recursive, total_bytes, ConflictPolicy, FailedTaskItem,
    TaskControl, TaskManager, TaskProgress, TaskState,
};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

static TASK_MGR: OnceLock<TaskManager> = OnceLock::new();

fn task_mgr() -> &'static TaskManager {
    TASK_MGR.get_or_init(|| {
        let mgr = TaskManager::new();
        if let Some(db_path) = VfsRegistry::global().get_database_path() {
            let history_path = PathBuf::from(&db_path)
                .parent()
                .unwrap_or_else(|| std::path::Path::new("."))
                .join("task_history.json");
            mgr.set_history_path(history_path);
        }
        mgr
    })
}

pub(crate) fn register_sync_task(
    label: &str,
) -> (String, Arc<Mutex<TaskProgress>>, CancellationToken, TaskControl) {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel, control) = task_mgr().register_with_control(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some(label.to_string());
    (task_id, progress, cancel, control)
}

pub(crate) fn finish_sync_task(
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    result: Result<(), String>,
) {
    finish(progress, cancel, result);
}

/// Record the terminal state of a task.
///
/// A cancellation makes the worker's operation fail; reporting that as
/// `failed` would show a scary error for an action the user chose, so the
/// cancellation wins over the error it caused. If the operation nevertheless
/// finished successfully (cancel arrived too late), report `Completed`:
/// the files really are on disk and the user must not be told otherwise.
fn finish(
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    result: Result<(), String>,
) {
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        if cancel.is_cancelled() && result.is_err() {
            p.state = TaskState::Cancelled;
            p.error = None;
        } else {
            match result {
                Ok(()) => {
                    p.state = TaskState::Completed;
                }
                Err(e) => {
                    p.state = TaskState::Failed;
                    p.error = Some(e);
                }
            }
        }
    }
    task_mgr().persist_history();
}

/// Remove a destination that this task created, after a failed or cancelled
/// copy. Only call this when the destination did not exist beforehand, so a
/// merge into an existing directory never deletes unrelated content. Cleanup
/// runs with its own token so cancellation does not skip it.
async fn discard_partial_copy(vfs: &dyn fm_vfs::Vfs, dst: &VfsPath) {
    let progress = Arc::new(Mutex::new(TaskProgress::pending()));
    let cleanup_cancel = CancellationToken::new();
    let _ = delete_recursive(vfs, dst, &progress, &cleanup_cancel).await;
}

async fn generate_copy_path(
    dst_vfs: &dyn fm_vfs::Vfs,
    dst_base: &VfsPath,
    src_vfs: &dyn fm_vfs::Vfs,
    src_p: &VfsPath,
    orig_name: &str,
) -> VfsPath {
    let is_dir = src_vfs
        .stat(src_p)
        .await
        .map(|e| e.kind == fm_core::EntryKind::Dir)
        .unwrap_or(false);

    let (stem, ext) = if !is_dir {
        if let Some(idx) = orig_name.rfind('.') {
            if idx > 0 && !orig_name.starts_with('.') {
                (&orig_name[..idx], &orig_name[idx..])
            } else {
                (orig_name, "")
            }
        } else {
            (orig_name, "")
        }
    } else {
        (orig_name, "")
    };

    let mut candidate = format!("{stem}_copy{ext}");
    let mut count = 2;
    while dst_vfs.stat(&dst_base.join(&candidate)).await.is_ok() {
        candidate = format!("{stem}_copy_{count}{ext}");
        count += 1;
        if count > 1000 {
            break;
        }
    }
    dst_base.join(candidate)
}

/// Conflict policy names as they cross the FFI boundary. Anything unknown
/// maps to `overwrite` so older Dart builds keep their historical default.
fn parse_policy(s: &str) -> ConflictPolicy {
    match s {
        "skip" => ConflictPolicy::Skip,
        "rename" => ConflictPolicy::Rename,
        _ => ConflictPolicy::Overwrite,
    }
}

/// Turn per-item failures into the task result. Batch operations used to
/// abort on the first failing item, leaving the rest unprocessed and the
/// user to figure out which files made it; now every item is attempted and
/// the failures are reported together.
fn batch_result(failures: Vec<String>, total_items: usize) -> Result<(), String> {
    if failures.is_empty() {
        return Ok(());
    }
    let shown: Vec<&str> = failures.iter().take(5).map(|f| f.as_str()).collect();
    let mut msg = format!(
        "{} of {} items failed:\n{}",
        failures.len(),
        total_items,
        shown.join("\n")
    );
    if failures.len() > shown.len() {
        msg += &format!("\n… and {} more", failures.len() - shown.len());
    }
    Err(msg)
}

#[derive(Debug, Clone)]
pub struct FailedTaskItemDto {
    pub src_root: String,
    pub src_path: String,
    pub dst_root: String,
    pub dst_path: String,
    pub is_dir: bool,
    pub error: String,
}

#[derive(Debug, Clone)]
pub struct TaskProgressDto {
    pub id: String,
    pub state: String,
    pub completed: u64,
    pub total: Option<u64>,
    pub fraction: Option<f32>,
    pub current: Option<String>,
    pub error: Option<String>,
    pub skipped: u64,
    pub label: Option<String>,
    pub failed_items: Vec<FailedTaskItemDto>,
    pub can_pause: bool,
    pub can_retry: bool,
    pub rate_limit_bps: u64,
}

fn state_str(s: TaskState) -> String {
    match s {
        TaskState::Pending => "pending",
        TaskState::Running => "running",
        TaskState::Paused => "paused",
        TaskState::Cancelled => "cancelled",
        TaskState::Failed => "failed",
        TaskState::Completed => "completed",
    }
    .to_string()
}

impl TaskProgressDto {
    fn from_progress(id: String, p: TaskProgress) -> Self {
        let can_retry = !p.failed_items.is_empty() && p.retry_kind.is_some();
        let failed_items = p
            .failed_items
            .iter()
            .map(|f| FailedTaskItemDto {
                src_root: f.src_root.clone(),
                src_path: f.src_path.clone(),
                dst_root: f.dst_root.clone(),
                dst_path: f.dst_path.clone(),
                is_dir: f.is_dir,
                error: f.error.clone(),
            })
            .collect();
        Self {
            id,
            state: state_str(p.state),
            completed: p.completed,
            total: p.total,
            fraction: p.fraction(),
            current: p.current.map(|c| c.to_slash_string()),
            error: p.error,
            skipped: p.skipped,
            label: p.label,
            failed_items,
            can_pause: p.can_pause,
            can_retry,
            rate_limit_bps: p.rate_limit_bps,
        }
    }
}

pub async fn start_copy_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_root: String,
    dst_dir: String,
    dst_name: Option<String>,
    conflict_policy: String,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel, control) = task_mgr().register_with_control(&task_id);
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.label = Some("Copy".to_string());
        p.can_pause = true;
        p.retry_kind = Some("copy".to_string());
        p.conflict_policy = Some(conflict_policy.clone());
    }

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
            let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
            let dst_base = VfsPath::from_slash_path(&dst_dir);

            // Totals let the UI show a real progress bar instead of a spinner.
            let mut total = 0u64;
            for src in &src_paths {
                total += total_bytes(src_vfs.as_ref(), &VfsPath::from_slash_path(src)).await;
            }
            {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.total = Some(total);
            }

            let policy = parse_policy(&conflict_policy);
            let total_items = src_paths.len();
            let is_batch = total_items > 1;
            let mut failures: Vec<String> = Vec::new();
            for src in src_paths {
                if cancel.is_cancelled() {
                    return Err("operation cancelled".to_string());
                }
                let src_p = VfsPath::from_slash_path(&src);
                let file_name = if is_batch {
                    src_p.name().unwrap_or("file").to_string()
                } else {
                    dst_name
                        .clone()
                        .unwrap_or_else(|| src_p.name().unwrap_or("file").to_string())
                };
                let mut dst_p = dst_base.join(&file_name);
                if src_root.trim_end_matches('/') == dst_root.trim_end_matches('/') {
                    // Copying a file onto itself generates a copy name instead of truncating.
                    // Copying a directory into itself recurses forever.
                    if dst_p == src_p {
                        dst_p = generate_copy_path(
                            dst_vfs.as_ref(),
                            &dst_base,
                            src_vfs.as_ref(),
                            &src_p,
                            &file_name,
                        )
                        .await;
                    } else if dst_p.starts_with(&src_p) {
                        failures.push(format!(
                            "{file_name}: cannot copy a folder into itself"
                        ));
                        continue;
                    }
                }
                // A destination that existed before the copy is not ours to
                // remove if the copy fails.
                let created = dst_vfs.stat(&dst_p).await.is_err();
                if let Err(e) = copy_recursive_with_control(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                    &control,
                    policy,
                )
                .await
                {
                    let is_dir = dst_vfs.stat(&dst_p).await.map(|s| s.kind == EntryKind::Dir).unwrap_or(false);
                    if created && !is_dir {
                        discard_partial_copy(dst_vfs.as_ref(), &dst_p).await;
                    }
                    let err_str = e.to_string();
                    failures.push(format!("{file_name}: {err_str}"));
                    progress.lock().unwrap_or_else(|e| e.into_inner()).failed_items.push(
                        FailedTaskItem {
                            src_root: src_root.clone(),
                            src_path: src.clone(),
                            dst_root: dst_root.clone(),
                            dst_path: dst_p.to_slash_string(),
                            is_dir,
                            error: err_str,
                        },
                    );
                }
            }
            batch_result(failures, total_items)
        };

        let result = run.await;
        super::file_manager::invalidate_dir_cache(&dst_root);
        if let Err(e) = &result {
            eprintln!("copy task {tid} failed: {e}");
        }
        finish(&progress, &cancel, result);
    });

    Ok(task_id)
}

pub async fn start_move_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_root: String,
    dst_dir: String,
    conflict_policy: String,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel, control) = task_mgr().register_with_control(&task_id);
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.label = Some("Move".to_string());
        p.can_pause = true;
        p.retry_kind = Some("move".to_string());
        p.conflict_policy = Some(conflict_policy.clone());
    }

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
            let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
            let dst_base = VfsPath::from_slash_path(&dst_dir);

            let policy = parse_policy(&conflict_policy);
            let total_items = src_paths.len();
            let is_same_fs = src_root.trim_end_matches('/') == dst_root.trim_end_matches('/')
                && src_vfs.capabilities().rename;

            if !is_same_fs {
                let mut total = 0u64;
                for src in &src_paths {
                    total += total_bytes(src_vfs.as_ref(), &VfsPath::from_slash_path(src)).await;
                }
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.total = Some(total);
            } else {
                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                p.total = Some(total_items as u64);
            }

            let mut failures: Vec<String> = Vec::new();
            for src in &src_paths {
                if cancel.is_cancelled() {
                    return Err("operation cancelled".to_string());
                }
                let src_p = VfsPath::from_slash_path(src);
                let file_name = src_p.name().unwrap_or("file");
                let dst_p = dst_base.join(file_name);
                let mut fallback_dst = dst_p.clone();
                let mut overwrite_backup: Option<VfsPath> = None;
                if is_same_fs {
                    if dst_p == src_p {
                        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                        p.completed += 1;
                        continue;
                    }
                    if dst_p.starts_with(&src_p) {
                        failures.push(format!(
                            "{file_name}: cannot move a folder into itself"
                        ));
                        continue;
                    }
                    // The rename fast path must honour the conflict policy:
                    let dst_taken = dst_vfs.stat(&dst_p).await.is_ok();
                    let target_p = match policy {
                        ConflictPolicy::Skip => {
                            if dst_taken {
                                let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                                p.skipped += 1;
                                p.completed += 1;
                                continue;
                            }
                            dst_p.clone()
                        }
                        ConflictPolicy::Overwrite => {
                            if dst_taken {
                                let dst_is_dir = dst_vfs
                                    .stat(&dst_p)
                                    .await
                                    .map(|s| s.kind == EntryKind::Dir)
                                    .unwrap_or(false);
                                let src_is_dir = src_vfs
                                    .stat(&src_p)
                                    .await
                                    .map(|s| s.kind == EntryKind::Dir)
                                    .unwrap_or(false);
                                if dst_is_dir && !src_is_dir {
                                    failures.push(format!("{file_name}: destination is a directory"));
                                    continue;
                                }
                                if !dst_is_dir && src_is_dir {
                                    // rename() cannot replace a file with a tree; park the
                                    // existing file aside so it can be restored if rename/copy fails.
                                    let bak_name = format!(
                                        "{file_name}.{}.fm-old",
                                        Uuid::new_v4().simple()
                                    );
                                    let bak_p = dst_base.join(bak_name);
                                    if dst_vfs.rename(&dst_p, &bak_p).await.is_ok() {
                                        overwrite_backup = Some(bak_p);
                                    } else {
                                        failures.push(format!("{file_name}: could not replace existing file with folder"));
                                        continue;
                                    }
                                }
                            }
                            dst_p.clone()
                        }
                        ConflictPolicy::Rename => {
                            if dst_taken {
                                generate_copy_path(
                                    dst_vfs.as_ref(),
                                    &dst_base,
                                    src_vfs.as_ref(),
                                    &src_p,
                                    file_name,
                                )
                                .await
                            } else {
                                dst_p.clone()
                            }
                        }
                    };
                    fallback_dst = target_p.clone();

                    if src_vfs.rename(&src_p, &target_p).await.is_ok() {
                        if let Some(bak) = overwrite_backup.take() {
                            let _ = dst_vfs.remove(&bak).await;
                        }
                        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                        p.completed += 1;
                        continue;
                    }
                }
                let created = dst_vfs.stat(&fallback_dst).await.is_err();
                let skipped_before = progress
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .skipped;
                if let Err(e) = copy_recursive_with_control(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &fallback_dst,
                    &progress,
                    &cancel,
                    &control,
                    policy,
                )
                .await
                {
                    let is_dir = dst_vfs.stat(&fallback_dst).await.map(|s| s.kind == EntryKind::Dir).unwrap_or(false);
                    if created && !is_dir {
                        discard_partial_copy(dst_vfs.as_ref(), &fallback_dst).await;
                    }
                    if let Some(bak) = overwrite_backup.take() {
                        if dst_vfs.stat(&dst_p).await.is_err() {
                            let _ = dst_vfs.rename(&bak, &dst_p).await;
                        }
                    }
                    let err_str = e.to_string();
                    failures.push(format!("{file_name}: {err_str}"));
                    progress.lock().unwrap_or_else(|e| e.into_inner()).failed_items.push(
                        FailedTaskItem {
                            src_root: src_root.clone(),
                            src_path: src.clone(),
                            dst_root: dst_root.clone(),
                            dst_path: fallback_dst.to_slash_string(),
                            is_dir,
                            error: err_str,
                        },
                    );
                    continue;
                }
                if let Some(bak) = overwrite_backup.take() {
                    let _ = dst_vfs.remove(&bak).await;
                }

                // If anything inside the source tree was skipped (Skip policy,
                // symlinks, or special files), leave the source intact so
                // uncopied items are never destroyed.
                let skipped_now = progress
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .skipped;
                if skipped_now > skipped_before {
                    continue;
                }

                if let Err(e) =
                    delete_recursive(src_vfs.as_ref(), &src_p, &progress, &cancel).await
                {
                    // Keep the completed destination copy intact; removing it
                    // would contradict the error message and risk data loss.
                    failures.push(format!("{file_name}: copied but source not removed: {e}"));
                }
            }
            batch_result(failures, total_items)
        };

        let result = run.await;
        super::file_manager::invalidate_dir_cache(&src_root);
        super::file_manager::invalidate_dir_cache(&dst_root);
        if let Err(e) = &result {
            eprintln!("move task {tid} failed: {e}");
        }
        finish(&progress, &cancel, result);
    });

    Ok(task_id)
}

pub async fn start_delete_task(root: String, paths: Vec<String>) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Delete".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let vfs = VfsRegistry::global().get_or_create(&root).await?;
            let total_items = paths.len();
            let mut failures: Vec<String> = Vec::new();
            for p in paths {
                if cancel.is_cancelled() {
                    return Err("operation cancelled".to_string());
                }
                let vfs_p = VfsPath::from_slash_path(&p);
                if let Err(e) =
                    delete_recursive(vfs.as_ref(), &vfs_p, &progress, &cancel).await
                {
                    let name = vfs_p.name().unwrap_or("item");
                    failures.push(format!("{name}: {e}"));
                }
            }
            batch_result(failures, total_items)
        };

        let result = run.await;
        super::file_manager::invalidate_dir_cache(&root);
        if let Err(e) = &result {
            eprintln!("delete task {tid} failed: {e}");
        }
        finish(&progress, &cancel, result);
    });

    Ok(task_id)
}

pub async fn start_compress_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_archive_path: String,
) -> Result<String, String> {
    start_compress_with_password_task(src_root, src_paths, dst_archive_path, None).await
}

pub async fn start_compress_with_password_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_archive_path: String,
    password: Option<String>,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Compress".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        if cancel.is_cancelled() {
            finish(&progress, &cancel, Err("cancelled".into()));
            return;
        }
        let root = PathBuf::from(&src_root);
        let mut items: Vec<PathBuf> = Vec::with_capacity(src_paths.len());
        for rel in src_paths {
            let p = PathBuf::from(&rel);
            if p.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
                finish(&progress, &cancel, Err(format!("invalid path: {rel}")));
                return;
            }
            if p.is_absolute() && p.starts_with(&root) {
                items.push(p);
            } else {
                let trimmed = rel.trim_start_matches(['/', '\\']);
                items.push(root.join(trimmed));
            }
        }

        let dst = PathBuf::from(dst_archive_path);
        let cancel_bg = cancel.clone();
        let res = tokio::task::spawn_blocking(move || {
            create_zip_with_password(&items, &dst, password.as_deref(), &cancel_bg)
        })
        .await
        .unwrap_or_else(|e| {
            Err(fm_vfs::VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::other(e.to_string()),
            })
        });

        let result = res.map_err(|e| e.to_string());
        if let Err(e) = &result {
            eprintln!("compress task {tid} failed: {e}");
        }
        finish(&progress, &cancel, result);
    });

    Ok(task_id)
}

pub async fn start_extract_task(archive_path: String, dst_dir: String) -> Result<String, String> {
    start_extract_with_password_task(archive_path, dst_dir, None).await
}

pub async fn start_extract_with_password_task(
    archive_path: String,
    dst_dir: String,
    password: Option<String>,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Extract".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        if cancel.is_cancelled() {
            finish(&progress, &cancel, Err("cancelled".into()));
            return;
        }
        let src = PathBuf::from(archive_path);
        let dst = PathBuf::from(dst_dir);
        let cancel_bg = cancel.clone();
        let res = tokio::task::spawn_blocking(move || {
            extract_archive_with_password(&src, &dst, password.as_deref(), &cancel_bg)
        })
        .await
        .unwrap_or_else(|e| {
            Err(fm_vfs::VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::other(e.to_string()),
            })
        });

        let result = res.map_err(|e| e.to_string());
        if let Err(e) = &result {
            eprintln!("extract task {tid} failed: {e}");
        }
        finish(&progress, &cancel, result);
    });

    Ok(task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn pause_task(task_id: String) -> bool {
    task_mgr().pause(&task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn resume_task(task_id: String) -> bool {
    task_mgr().resume(&task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn set_task_rate_limit(task_id: String, bytes_per_sec: u64) -> bool {
    task_mgr().set_rate_limit(&task_id, bytes_per_sec)
}

/// Retry only the failed items of a previous copy/move/sync task without
/// re-running already succeeded files.
pub async fn retry_failed_task_items(task_id: String) -> Result<String, String> {
    let Some(prev) = task_mgr().get_progress(&task_id) else {
        return Err("task not found".to_string());
    };
    if prev.failed_items.is_empty() {
        return Err("task has no failed items to retry".to_string());
    }
    let retry_kind = prev.retry_kind.clone().unwrap_or_else(|| "copy".to_string());
    let policy_str = prev
        .conflict_policy
        .clone()
        .unwrap_or_else(|| "overwrite".to_string());
    let policy = parse_policy(&policy_str);
    let items = prev.failed_items.clone();

    let new_id = Uuid::new_v4().to_string();
    let (progress, cancel, control) = task_mgr().register_with_control(&new_id);
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.label = Some(format!(
            "Retry {}",
            prev.label.as_deref().unwrap_or("Transfer")
        ));
        p.can_pause = true;
        p.retry_kind = Some(retry_kind.clone());
        p.conflict_policy = Some(policy_str);
    }

    tokio::spawn(async move {
        let run = async {
            let total_items = items.len();
            let mut total = 0u64;
            for it in &items {
                if let Ok(vfs) = VfsRegistry::global().get_or_create(&it.src_root).await {
                    total += total_bytes(vfs.as_ref(), &VfsPath::from_slash_path(&it.src_path)).await;
                }
            }
            progress.lock().unwrap_or_else(|e| e.into_inner()).total = Some(total);

            let mut failures_msg: Vec<String> = Vec::new();
            for it in items {
                if cancel.is_cancelled() {
                    return Err("operation cancelled".to_string());
                }
                let src_vfs = match VfsRegistry::global().get_or_create(&it.src_root).await {
                    Ok(v) => v,
                    Err(e) => {
                        failures_msg.push(format!("{}: {e}", it.src_path));
                        progress.lock().unwrap_or_else(|e| e.into_inner()).failed_items.push(
                            FailedTaskItem { error: e, ..it },
                        );
                        continue;
                    }
                };
                let dst_vfs = match VfsRegistry::global().get_or_create(&it.dst_root).await {
                    Ok(v) => v,
                    Err(e) => {
                        failures_msg.push(format!("{}: {e}", it.src_path));
                        progress.lock().unwrap_or_else(|e| e.into_inner()).failed_items.push(
                            FailedTaskItem { error: e, ..it },
                        );
                        continue;
                    }
                };
                let src_p = VfsPath::from_slash_path(&it.src_path);
                let dst_p = VfsPath::from_slash_path(&it.dst_path);
                if let Err(e) = copy_recursive_with_control(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                    &control,
                    policy,
                )
                .await
                {
                    let err_str = e.to_string();
                    failures_msg.push(format!("{}: {err_str}", it.src_path));
                    progress.lock().unwrap_or_else(|e| e.into_inner()).failed_items.push(
                        FailedTaskItem { error: err_str, ..it },
                    );
                } else {
                    if retry_kind == "move" {
                        let _ = delete_recursive(src_vfs.as_ref(), &src_p, &progress, &cancel).await;
                        super::file_manager::invalidate_dir_cache(&it.src_root);
                    }
                    super::file_manager::invalidate_dir_cache(&it.dst_root);
                }
            }
            batch_result(failures_msg, total_items)
        };
        let res = run.await;
        finish(&progress, &cancel, res);
    });

    Ok(new_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn poll_task_progress(task_id: String) -> Option<TaskProgressDto> {
    task_mgr()
        .get_progress(&task_id)
        .map(|p| TaskProgressDto::from_progress(task_id, p))
}

/// Every registered task, oldest first, finished ones included (until
/// dismissed or pruned). Backs the task centre: until this existed the only
/// way to see a task was the modal progress dialog it was started from.
#[flutter_rust_bridge::frb(sync)]
pub fn list_tasks() -> Vec<TaskProgressDto> {
    task_mgr()
        .list_active()
        .into_iter()
        .map(|(id, p)| TaskProgressDto::from_progress(id, p))
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_task(task_id: String) -> bool {
    task_mgr().cancel(&task_id)
}

/// Remove a task from the registry (task centre dismiss). Running tasks
/// are unaffected — this only drops the record.
#[flutter_rust_bridge::frb(sync)]
pub fn dismiss_task(task_id: String) -> bool {
    task_mgr().remove(&task_id)
}
