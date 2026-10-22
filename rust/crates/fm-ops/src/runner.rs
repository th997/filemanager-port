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
        self.tasks.write().unwrap_or_else(|e| e.into_inner()).insert(id.to_string(), handle);
        (progress, cancel)
    }

    pub fn get_progress(&self, id: &str) -> Option<TaskProgress> {
        self.tasks
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .get(id)
            .map(|h| h.progress.lock().unwrap_or_else(|e| e.into_inner()).clone())
    }

    pub fn cancel(&self, id: &str) -> bool {
        if let Some(handle) = self.tasks.read().unwrap_or_else(|e| e.into_inner()).get(id) {
            handle.cancel.cancel();
            handle.progress.lock().unwrap_or_else(|e| e.into_inner()).state = TaskState::Cancelled;
            true
        } else {
            false
        }
    }

    pub fn list_active(&self) -> Vec<(String, TaskProgress)> {
        self.tasks
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(id, h)| (id.clone(), h.progress.lock().unwrap_or_else(|e| e.into_inner()).clone()))
            .collect()
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
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.state = TaskState::Running;
        p.current = Some(src_path.clone());
    }

    if stat.is_symlink && stat.kind == EntryKind::Dir {
        // Never recurse through a symlink: the target may live outside the
        // tree being copied or point back into it, nesting without bound.
        // There is no cross-VFS primitive to reproduce the link itself, so
        // the linked tree is skipped.
        return Ok(());
    }

    if stat.kind == EntryKind::Dir {
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
    // Stream into a sibling temp file and rename it over the destination
    // only once the copy is complete. Writing in place with Truncate meant
    // a cancelled or failed copy both destroyed the previous version and
    // left a truncated file behind.
    let dst_name = dst_path.name().unwrap_or("file");
    let tmp_path = dst_path
        .parent()
        .unwrap_or_else(VfsPath::root)
        .join(format!(".{dst_name}.fm-part"));

    if let Err(e) =
        stream_into(src_vfs, src_path, dst_vfs, &tmp_path, progress, cancel).await
    {
        let _ = dst_vfs.remove(&tmp_path).await;
        return Err(e);
    }

    match dst_vfs.rename(&tmp_path, dst_path).await {
        Ok(()) => Ok(()),
        Err(first_err) => {
            // Some backends refuse to rename onto an existing file; retry
            // once after removing it — but never remove a directory to
            // make room for a file.
            let dst_is_file = dst_vfs
                .stat(dst_path)
                .await
                .map(|s| s.kind != EntryKind::Dir)
                .unwrap_or(false);
            if !dst_is_file {
                let _ = dst_vfs.remove(&tmp_path).await;
                return Err(first_err);
            }
            let _ = dst_vfs.remove(dst_path).await;
            if dst_vfs.rename(&tmp_path, dst_path).await.is_err() {
                let _ = dst_vfs.remove(&tmp_path).await;
                return Err(first_err);
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
                path: tmp_path.clone(),
                source: e,
            })?;

        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.completed += n as u64;
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
    if cancel.is_cancelled() {
        return Err(VfsError::Unsupported { operation: "cancelled" });
    }

    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.state = TaskState::Running;
        p.current = Some(path.clone());
    }

    let stat = vfs.stat(path).await?;
    // A symlinked directory is removed as a link, never traversed: the
    // entries under it belong to the link target, which may be anywhere —
    // including outside the tree the user selected for deletion.
    if stat.kind == EntryKind::Dir && !stat.is_symlink {
        let children = vfs.list(path).await?;
        for child in children {
            if cancel.is_cancelled() {
                return Err(VfsError::Unsupported { operation: "cancelled" });
            }
            Box::pin(delete_recursive(vfs, &child.path, progress, cancel)).await?;
        }
    }

    vfs.remove(path).await?;
    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
    p.completed += 1;
    Ok(())
}
