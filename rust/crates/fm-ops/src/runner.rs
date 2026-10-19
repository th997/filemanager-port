//! Task runner and cross-VFS operations engine.

use fm_core::{EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, RwLock};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

use crate::{TaskProgress, TaskState};

pub struct TaskHandle {
    pub progress: Arc<Mutex<TaskProgress>>,
    pub cancel: CancellationToken,
}

#[derive(Clone, Default)]
pub struct TaskManager {
    tasks: Arc<RwLock<HashMap<String, TaskHandle>>>,
}

impl TaskManager {
    pub fn new() -> Self {
        Self {
            tasks: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn register(&self, id: &str) -> (Arc<Mutex<TaskProgress>>, CancellationToken) {
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        let cancel = CancellationToken::new();
        let handle = TaskHandle {
            progress: progress.clone(),
            cancel: cancel.clone(),
        };
        self.tasks.write().unwrap().insert(id.to_string(), handle);
        (progress, cancel)
    }

    pub fn get_progress(&self, id: &str) -> Option<TaskProgress> {
        self.tasks
            .read()
            .unwrap()
            .get(id)
            .map(|h| h.progress.lock().unwrap().clone())
    }

    pub fn cancel(&self, id: &str) -> bool {
        if let Some(handle) = self.tasks.read().unwrap().get(id) {
            handle.cancel.cancel();
            handle.progress.lock().unwrap().state = TaskState::Cancelled;
            true
        } else {
            false
        }
    }

    pub fn list_active(&self) -> Vec<(String, TaskProgress)> {
        self.tasks
            .read()
            .unwrap()
            .iter()
            .map(|(id, h)| (id.clone(), h.progress.lock().unwrap().clone()))
            .collect()
    }
}

/// Sum the byte size of a file or directory tree, for progress totals.
pub async fn total_bytes(vfs: &dyn Vfs, path: &VfsPath) -> u64 {
    let stat = match vfs.stat(path).await {
        Ok(stat) => stat,
        Err(_) => return 0,
    };
    if stat.kind != EntryKind::Dir {
        return stat.size.unwrap_or(0);
    }
    let children = match vfs.list(path).await {
        Ok(children) => children,
        Err(_) => return 0,
    };
    let mut total = 0;
    for child in children {
        total += Box::pin(total_bytes(vfs, &child.path)).await;
    }
    total
}

/// Recursively copy a file or directory from `src_vfs` to `dst_vfs`.
pub async fn copy_recursive(
    src_vfs: &dyn Vfs,
    src_path: &VfsPath,
    dst_vfs: &dyn Vfs,
    dst_path: &VfsPath,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    if cancel.is_cancelled() {
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    let stat = src_vfs.stat(src_path).await?;
    {
        let mut p = progress.lock().unwrap();
        p.state = TaskState::Running;
        p.current = Some(src_path.clone());
    }

    if stat.kind == EntryKind::Dir {
        let _ = dst_vfs.mkdir(dst_path).await;
        let children = src_vfs.list(src_path).await?;
        for child in children {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            let child_src = child.path.clone();
            let child_dst = dst_path.join(child.name.clone());
            Box::pin(copy_recursive(
                src_vfs, &child_src, dst_vfs, &child_dst, progress, cancel,
            ))
            .await?;
        }
    } else {
        copy_single_file(src_vfs, src_path, dst_vfs, dst_path, progress, cancel).await?;
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
) -> VfsResult<()> {
    let mut reader = src_vfs.open_read(src_path).await?;
    let mut writer = dst_vfs.open_write(dst_path, WriteMode::Create).await?;

    let mut buf = [0u8; 64 * 1024];
    loop {
        if cancel.is_cancelled() {
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
                path: dst_path.clone(),
                source: e,
            })?;

        let mut p = progress.lock().unwrap();
        p.completed += n as u64;
    }
    writer.flush().await.map_err(|e| VfsError::Backend {
        path: dst_path.clone(),
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
    if cancel.is_cancelled() {
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    let stat = vfs.stat(path).await?;
    if stat.kind == EntryKind::Dir {
        let children = vfs.list(path).await?;
        for child in children {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            Box::pin(delete_recursive(vfs, &child.path, progress, cancel)).await?;
        }
    }

    vfs.remove(path).await?;
    let mut p = progress.lock().unwrap();
    p.completed += 1;
    Ok(())
}
