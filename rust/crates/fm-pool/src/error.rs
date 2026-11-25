use fm_core::VfsPath;
use fm_vfs::VfsError;
use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PoolError {
    #[error("pool not found: {0}")]
    NotFound(String),
    #[error("path not found: {0}")]
    PathNotFound(String),
    #[error("path already exists: {0}")]
    AlreadyExists(String),
    #[error("invalid path: {0}")]
    InvalidPath(String),
    #[error("invalid argument: {0}")]
    InvalidArgument(String),
    #[error("pool is read-only or has no writable nodes")]
    NoWritableNodes,
    #[error("all replicas failed for chunk {chunk_hash}: {details}")]
    AllReplicasFailed { chunk_hash: String, details: String },
    #[error("encryption error: {0}")]
    Crypto(String),
    #[error("metadata database error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("io error: {0}")]
    Io(#[from] io::Error),
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("sync error: {0}")]
    Sync(String),
    #[error("backend error: {0}")]
    Backend(String),
    #[error("operation cancelled")]
    Cancelled,
}

pub type PoolResult<T> = Result<T, PoolError>;

impl PoolError {
    pub fn into_vfs_error(self, path: &VfsPath) -> VfsError {
        match self {
            PoolError::PathNotFound(_) | PoolError::NotFound(_) => {
                VfsError::NotFound { path: path.clone() }
            }
            PoolError::AlreadyExists(msg) => VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::AlreadyExists, msg),
            },
            PoolError::InvalidPath(msg) | PoolError::InvalidArgument(msg) => VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::InvalidInput, msg),
            },
            PoolError::NoWritableNodes => VfsError::PermissionDenied { path: path.clone() },
            PoolError::Cancelled => VfsError::Unsupported {
                operation: "cancelled",
            },
            other => VfsError::Backend {
                path: path.clone(),
                source: io::Error::other(other.to_string()),
            },
        }
    }
}

impl From<fm_vault::VaultError> for PoolError {
    fn from(err: fm_vault::VaultError) -> Self {
        PoolError::Crypto(err.to_string())
    }
}
