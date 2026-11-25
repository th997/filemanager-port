//! The backend VFS contract and error model shared across local, remote,
//! archive, and encrypted privacy-vault implementations.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, SpaceInfo, VfsPath, WriteMode};
use std::io;
use thiserror::Error;

/// Failure from a backend operation. `path` is retained so the UI can name the
/// item that failed.
#[derive(Debug, Error)]
pub enum VfsError {
    #[error("path not found: {path}")]
    NotFound { path: VfsPath },
    #[error("permission denied: {path}")]
    PermissionDenied { path: VfsPath },
    #[error("unsupported operation: {operation}")]
    Unsupported { operation: &'static str },
    #[error("backend failed: {path}: {source}")]
    Backend {
        path: VfsPath,
        #[source]
        source: io::Error,
    },
    #[error("connection failed: {message}")]
    Connection { message: String },
}

pub type VfsResult<T> = Result<T, VfsError>;

/// A browsable filesystem backend.
///
/// Implementations must keep `path` interpretation local: a `VfsPath` from one
/// backend is not meaningful in another.
#[async_trait]
pub trait Vfs: Send + Sync {
    fn capabilities(&self) -> Capabilities;

    /// Whether this VFS prefers writing directly to the target path rather than
    /// streaming into a `.fm-part` temporary file followed by a rename.
    ///
    /// Object storage backends (S3, OSS) lack atomic rename (requiring an expensive
    /// server-side copy of the entire object) and already provide atomic writes
    /// via multipart upload / PUT.
    fn prefers_direct_write(&self) -> bool {
        false
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>>;

    /// Paginated directory listing. Backends with native pagination or streaming
    /// override this to avoid materializing all entries.
    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        let mut all = self.list(dir).await?;
        all.sort_unstable_by(|a, b| {
            fm_core::compare_dir_and_name(
                a.kind == fm_core::EntryKind::Dir,
                &a.name,
                b.kind == fm_core::EntryKind::Dir,
                &b.name,
                true,
            )
        });
        let page = page.max(1);
        let page_size = page_size.max(1);
        let skip = ((page - 1) as usize).saturating_mul(page_size as usize);
        let total = all.len();
        let has_more = skip + (page_size as usize) < total;
        let entries = all.into_iter().skip(skip).take(page_size as usize).collect();
        Ok((entries, has_more))
    }

    /// Paginated directory listing returning an optional exact total entry count
    /// when the backend can determine it without per-entry network/stat I/O.
    async fn list_paged_with_total(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool, Option<u32>)> {
        let (entries, has_more) = self.list_paged(dir, page, page_size).await?;
        Ok((entries, has_more, None))
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry>;

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn tokio::io::AsyncRead + Send + Unpin>>;

    /// Open a byte range for media streaming.
    ///
    /// `length` is `None` when the caller wants everything from `offset` to the
    /// end. The default implementation skips bytes by reading them, which is
    /// correct but wasteful; backends with native range support override it.
    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn tokio::io::AsyncRead + Send + Unpin>> {
        use tokio::io::AsyncReadExt;

        let mut reader = self.open_read(path).await?;
        let mut remaining = offset;
        let mut scratch = [0u8; 16 * 1024];
        while remaining > 0 {
            let want = remaining.min(scratch.len() as u64) as usize;
            let read = reader
                .read(&mut scratch[..want])
                .await
                .map_err(|source| VfsError::Backend {
                    path: path.clone(),
                    source,
                })?;
            if read == 0 {
                return Ok(Box::new(tokio::io::empty()));
            }
            remaining -= read as u64;
        }

        Ok(match length {
            Some(len) => Box::new(reader.take(len)),
            None => Box::new(reader),
        })
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn tokio::io::AsyncWrite + Send + Unpin>>;

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()>;

    async fn remove(&self, path: &VfsPath) -> VfsResult<()>;

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()>;

    /// Update Unix permission bits (e.g. `0o755`) on backends that support chmod
    /// (Unix local filesystem and SFTP).
    async fn set_mode(&self, _path: &VfsPath, _mode: u32) -> VfsResult<()> {
        Err(VfsError::Unsupported { operation: "chmod" })
    }

    /// Query total and remaining free bytes for the storage volume or quota
    /// backing `path`, when the backend supports reporting it.
    fn supports_space_info(&self) -> bool {
        false
    }

    /// Query total and remaining free bytes for the storage volume or quota
    /// backing `path`, when the backend supports reporting it.
    async fn space_info(&self, _path: &VfsPath) -> VfsResult<Option<SpaceInfo>> {
        Ok(None)
    }
}
