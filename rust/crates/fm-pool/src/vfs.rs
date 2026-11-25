//! `fm_vfs::Vfs` implementation (`PoolVfs`) over a [`PoolState`].

use crate::chunker::{open_pool_reader, open_pool_writer};
use crate::PoolState;
use async_trait::async_trait;
use fm_core::{Capabilities, Entry, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsResult};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};

pub struct PoolVfs {
    state: Arc<PoolState>,
}

impl PoolVfs {
    pub fn new(state: Arc<PoolState>) -> Self {
        Self { state }
    }

    pub fn state(&self) -> &Arc<PoolState> {
        &self.state
    }
}

#[async_trait]
impl Vfs for PoolVfs {
    fn capabilities(&self) -> Capabilities {
        Capabilities::READ_WRITE
    }

    /// Committing metadata only on `shutdown()` gives atomic uploads without
    /// writing temporary `.fm-part` / `.fm-resume` files to the pool tree.
    fn prefers_direct_write(&self) -> bool {
        true
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        self.state
            .meta
            .list_dir(dir)
            .map_err(|e| e.into_vfs_error(dir))
    }

    async fn list_paged_with_total(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool, Option<u32>)> {
        self.state
            .meta
            .list_dir_paged_with_total(dir, page, page_size)
            .map_err(|e| e.into_vfs_error(dir))
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        self.state
            .meta
            .stat(path)
            .map(|rec| rec.to_vfs_entry())
            .map_err(|e| e.into_vfs_error(path))
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        open_pool_reader(Arc::clone(&self.state), path, 0, None)
            .await
            .map_err(|e| e.into_vfs_error(path))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        open_pool_reader(Arc::clone(&self.state), path, offset, length)
            .await
            .map_err(|e| e.into_vfs_error(path))
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        open_pool_writer(Arc::clone(&self.state), path, mode)
            .await
            .map_err(|e| e.into_vfs_error(path))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        self.state
            .meta
            .mkdir(path)
            .map_err(|e| e.into_vfs_error(path))?;
        self.state.schedule_debounced_sync();
        Ok(())
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        self.state
            .meta
            .soft_delete(path)
            .map_err(|e| e.into_vfs_error(path))?;
        self.state.schedule_debounced_sync();
        Ok(())
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        self.state
            .meta
            .rename(from, to)
            .map_err(|e| e.into_vfs_error(from))?;
        self.state.schedule_debounced_sync();
        Ok(())
    }
}
