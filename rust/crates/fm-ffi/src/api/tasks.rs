use crate::registry::VfsRegistry;
use fm_archive::ops::{create_zip, extract_archive};
use fm_core::VfsPath;
use fm_ops::{copy_recursive, delete_recursive, total_bytes, TaskManager, TaskProgress, TaskState};
use std::path::PathBuf;
use std::sync::OnceLock;
use uuid::Uuid;

static TASK_MGR: OnceLock<TaskManager> = OnceLock::new();

fn task_mgr() -> &'static TaskManager {
    TASK_MGR.get_or_init(TaskManager::new)
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
        }
    }
}

pub async fn start_copy_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_root: String,
    dst_dir: String,
    dst_name: Option<String>,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);

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
                let mut p = progress.lock().unwrap();
                p.total = Some(total);
            }

            for src in src_paths {
                if cancel.is_cancelled() {
                    break;
                }
                let src_p = VfsPath::from_slash_path(&src);
                let file_name = dst_name
                    .clone()
                    .unwrap_or_else(|| src_p.name().unwrap_or("file").to_string());
                let dst_p = dst_base.join(file_name);
                copy_recursive(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                )
                .await
                .map_err(|e| e.to_string())?;
            }
            Ok::<(), String>(())
        };

        match run.await {
            Ok(()) => {
                let mut p = progress.lock().unwrap();
                if p.state != TaskState::Cancelled {
                    p.state = TaskState::Completed;
                }
            }
            Err(e) => {
                eprintln!("copy task {tid} failed: {e}");
                let mut p = progress.lock().unwrap();
                p.state = TaskState::Failed;
                p.error = Some(e);
            }
        }
    });

    Ok(task_id)
}

pub async fn start_move_task(
    src_root: String,
    src_paths: Vec<String>,
    dst_root: String,
    dst_dir: String,
) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
            let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
            let dst_base = VfsPath::from_slash_path(&dst_dir);

            for src in &src_paths {
                if cancel.is_cancelled() {
                    break;
                }
                let src_p = VfsPath::from_slash_path(src);
                let file_name = src_p.name().unwrap_or("file");
                let dst_p = dst_base.join(file_name);
                copy_recursive(
                    src_vfs.as_ref(),
                    &src_p,
                    dst_vfs.as_ref(),
                    &dst_p,
                    &progress,
                    &cancel,
                )
                .await
                .map_err(|e| e.to_string())?;

                delete_recursive(src_vfs.as_ref(), &src_p, &progress, &cancel)
                    .await
                    .map_err(|e| e.to_string())?;
            }
            Ok::<(), String>(())
        };

        match run.await {
            Ok(()) => {
                let mut p = progress.lock().unwrap();
                if p.state != TaskState::Cancelled {
                    p.state = TaskState::Completed;
                }
            }
            Err(e) => {
                eprintln!("move task {tid} failed: {e}");
                let mut p = progress.lock().unwrap();
                p.state = TaskState::Failed;
                p.error = Some(e);
            }
        }
    });

    Ok(task_id)
}

pub async fn start_delete_task(root: String, paths: Vec<String>) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);

    let tid = task_id.clone();
    tokio::spawn(async move {
        let run = async {
            let vfs = VfsRegistry::global().get_or_create(&root).await?;
            for p in paths {
                if cancel.is_cancelled() {
                    break;
                }
                let vfs_p = VfsPath::from_slash_path(&p);
                delete_recursive(vfs.as_ref(), &vfs_p, &progress, &cancel)
                    .await
                    .map_err(|e| e.to_string())?;
            }
            Ok::<(), String>(())
        };

        match run.await {
            Ok(()) => {
                let mut p = progress.lock().unwrap();
                if p.state != TaskState::Cancelled {
                    p.state = TaskState::Completed;
                }
            }
            Err(e) => {
                eprintln!("delete task {tid} failed: {e}");
                let mut p = progress.lock().unwrap();
                p.state = TaskState::Failed;
                p.error = Some(e);
            }
        }
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

    tokio::spawn(async move {
        if cancel.is_cancelled() {
            return;
        }
        let root = PathBuf::from(src_root);
        let items: Vec<PathBuf> = src_paths
            .into_iter()
            .map(|rel| root.join(&rel))
            .collect();

        let dst = PathBuf::from(dst_archive_path);
        let res = create_zip(&items, &dst);

        let mut p = progress.lock().unwrap();
        match res {
            Ok(()) => {
                if p.state != TaskState::Cancelled {
                    p.state = TaskState::Completed;
                }
            }
            Err(e) => {
                p.state = TaskState::Failed;
                p.error = Some(e.to_string());
            }
        }
    });

    Ok(task_id)
}

pub async fn start_extract_task(archive_path: String, dst_dir: String) -> Result<String, String> {
    let task_id = Uuid::new_v4().to_string();
    let (progress, cancel) = task_mgr().register(&task_id);

    tokio::spawn(async move {
        if cancel.is_cancelled() {
            return;
        }
        let src = PathBuf::from(archive_path);
        let dst = PathBuf::from(dst_dir);
        let res = extract_archive(&src, &dst);

        let mut p = progress.lock().unwrap();
        match res {
            Ok(()) => {
                if p.state != TaskState::Cancelled {
                    p.state = TaskState::Completed;
                }
            }
            Err(e) => {
                p.state = TaskState::Failed;
                p.error = Some(e.to_string());
            }
        }
    });

    Ok(task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn poll_task_progress(task_id: String) -> Option<TaskProgressDto> {
    task_mgr()
        .get_progress(&task_id)
        .map(|p| TaskProgressDto::from_progress(task_id, p))
}

#[flutter_rust_bridge::frb(sync)]
pub fn cancel_task(task_id: String) -> bool {
    task_mgr().cancel(&task_id)
}
