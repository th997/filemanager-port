use crate::registry::VfsRegistry;
use fm_archive::ops::{create_zip, extract_archive};
use fm_core::{EntryKind, VfsPath};
use fm_ops::{
    copy_recursive, delete_recursive, total_bytes, ConflictPolicy, TaskManager, TaskProgress,
    TaskState,
};
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

static TASK_MGR: OnceLock<TaskManager> = OnceLock::new();

fn task_mgr() -> &'static TaskManager {
    TASK_MGR.get_or_init(TaskManager::new)
}

/// Record the terminal state of a task.
///
/// A cancellation makes the worker's operation fail; reporting that as
/// `failed` would show a scary error for an action the user chose, so the
/// cancellation wins over the error it caused.
fn finish(
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    result: Result<(), String>,
) {
    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
    match result {
        Ok(()) => {
            if p.state != TaskState::Cancelled {
                p.state = TaskState::Completed;
            }
        }
        Err(_) if cancel.is_cancelled() => {
            p.state = TaskState::Cancelled;
            p.error = None;
        }
        Err(e) => {
            p.state = TaskState::Failed;
            p.error = Some(e);
        }
    }
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
}

fn state_str(s: TaskState) -> String {
    match s {
        TaskState::Pending => "pending",
        TaskState::Running => "running",
        TaskState::Cancelled => "cancelled",
        TaskState::Failed => "failed",
        TaskState::Completed => "completed",
    }
    .to_string()
}

impl TaskProgressDto {
    fn from_progress(id: String, p: TaskProgress) -> Self {
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
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Copy".to_string());

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
                    break;
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
                if let Err(e) = copy_recursive(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                    policy,
                )
                .await
                {
                    let is_dir = dst_vfs.stat(&dst_p).await.map(|s| s.kind == EntryKind::Dir).unwrap_or(false);
                    if created && !is_dir {
                        discard_partial_copy(dst_vfs.as_ref(), &dst_p).await;
                    }
                    failures.push(format!("{file_name}: {e}"));
                }
            }
            batch_result(failures, total_items)
        };

        let result = run.await;
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
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Move".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
            let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
            let dst_base = VfsPath::from_slash_path(&dst_dir);

            let policy = parse_policy(&conflict_policy);
            let total_items = src_paths.len();
            let mut failures: Vec<String> = Vec::new();
            for src in &src_paths {
                if cancel.is_cancelled() {
                    break;
                }
                let src_p = VfsPath::from_slash_path(src);
                let file_name = src_p.name().unwrap_or("file");
                let dst_p = dst_base.join(file_name);
                if src_root.trim_end_matches('/') == dst_root.trim_end_matches('/') {
                    if dst_p == src_p {
                        continue;
                    }
                    if dst_p.starts_with(&src_p) {
                        failures.push(format!(
                            "{file_name}: cannot move a folder into itself"
                        ));
                        continue;
                    }
                    // The rename fast path must honour the conflict policy:
                    // renaming onto an existing name would silently replace
                    // it on most backends, so only take the shortcut when
                    // overwriting is allowed or the name is free.
                    let dst_taken = dst_vfs.stat(&dst_p).await.is_ok();
                    if (!dst_taken || policy == ConflictPolicy::Overwrite)
                        && src_vfs.capabilities().rename
                        && src_vfs.rename(&src_p, &dst_p).await.is_ok()
                    {
                        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                        p.completed += 1;
                        continue;
                    }
                }
                let created = dst_vfs.stat(&dst_p).await.is_err();
                let skipped_before = progress
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .skipped;
                if let Err(e) = copy_recursive(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                    policy,
                )
                .await
                {
                    let is_dir = dst_vfs.stat(&dst_p).await.map(|s| s.kind == EntryKind::Dir).unwrap_or(false);
                    if created && !is_dir {
                        discard_partial_copy(dst_vfs.as_ref(), &dst_p).await;
                    }
                    failures.push(format!("{file_name}: {e}"));
                    continue;
                }

                // Under the Skip policy a skipped file was never copied, so
                // its source must stay exactly where it is — deleting it
                // here would destroy the only copy.
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
                    if created {
                        discard_partial_copy(dst_vfs.as_ref(), &dst_p).await;
                    }
                    failures.push(format!("{file_name}: copied but source not removed: {e}"));
                }
            }
            batch_result(failures, total_items)
        };

        let result = run.await;
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
                    break;
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
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Compress".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        if cancel.is_cancelled() {
            finish(&progress, &cancel, Ok(()));
            return;
        }
        let root = PathBuf::from(src_root);
        let items: Vec<PathBuf> = src_paths
            .into_iter()
            .map(|rel| {
                let p = PathBuf::from(&rel);
                if p.is_absolute() && p.starts_with(&root) {
                    p
                } else {
                    let trimmed = rel.trim_start_matches(['/', '\\']);
                    root.join(trimmed)
                }
            })
            .collect();

        let dst = PathBuf::from(dst_archive_path);
        // Archiving blocks on the filesystem; keep the async worker free.
        let res = tokio::task::spawn_blocking(move || create_zip(&items, &dst))
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
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);
    progress.lock().unwrap_or_else(|e| e.into_inner()).label = Some("Extract".to_string());

    let tid = task_id.clone();
    tokio::spawn(async move {
        if cancel.is_cancelled() {
            finish(&progress, &cancel, Ok(()));
            return;
        }
        let src = PathBuf::from(archive_path);
        let dst = PathBuf::from(dst_dir);
        // Extraction blocks on the filesystem; keep the async worker free.
        let res = tokio::task::spawn_blocking(move || extract_archive(&src, &dst))
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
