//! The backend contract and the granted-root model.
//!
//! Every platform that restricts filesystem access (iOS, macOS sandbox,
//! Android SAF, Flatpak portals) grants access to a *root*, not to the whole
//! filesystem. Backends expose that root explicitly so the same abstraction
//! serves all of them.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, LocationId, VfsPath, WriteMode};
use std::io;
use thiserror::Error;

/// A root the host has granted access to.
///
/// `grant` is opaque backend data: a security-scoped bookmark on Apple
/// platforms, a persisted SAF URI on Android, or a plain path elsewhere. The
/// backend, not the UI, interprets it.
#[derive(Debug, Clone)]
pub struct GrantedRoot {
    pub location: LocationId,
    pub grant: Grant,
}

#[derive(Debug, Clone)]
pub enum Grant {
    /// Unrestricted native path. Linux, Windows, and unsandboxed macOS.
    NativePath(std::path::PathBuf),
    /// Apple security-scoped bookmark bytes.
    AppleBookmark(Vec<u8>),
    /// Android SAF tree URI granted with persistable permission.
    AndroidTreeUri(String),
}

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

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>>;

    /// Paginated directory listing. Backends with native pagination or streaming
    /// override this to avoid materializing all entries.
    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        let all = self.list(dir).await?;
        let page = page.max(1);
        let page_size = page_size.max(1);
        let skip = ((page - 1) as usize).saturating_mul(page_size as usize);
        let total = all.len();
        let has_more = skip + (page_size as usize) < total;
        let entries = all.into_iter().skip(skip).take(page_size as usize).collect();
        Ok((entries, has_more))
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
}
