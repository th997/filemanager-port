use fm_core::VfsPath;
use fm_vfs::VfsError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("privacy folder does not exist: {0}")]
    NotFound(String),
    #[error("privacy folder already exists: {0}")]
    AlreadyExists(String),
    #[error("privacy folder is locked: {0}")]
    Locked(String),
    #[error("invalid password: {0}")]
    InvalidPassword(String),
    #[error("privacy folder name is required")]
    NameRequired,
    #[error("incorrect password or credential")]
    WrongCredential,
    #[error("too many failed attempts, retry in {0} seconds")]
    CooldownActive(u64),
    #[error("unsupported operation: {0}")]
    Unsupported(String),
    #[error("cryptographic error: {0}")]
    Crypto(String),
    #[error("backup error: {0}")]
    Backup(String),
    #[error("operation cancelled")]
    Cancelled,
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("vfs error: {0}")]
    Vfs(#[from] VfsError),
}

pub type VaultResult<T> = Result<T, VaultError>;

impl VaultError {
    pub fn into_vfs(self, path: &VfsPath) -> VfsError {
        match self {
            VaultError::Vfs(e) => e,
            VaultError::NotFound(_) => VfsError::NotFound { path: path.clone() },
            VaultError::Locked(_) | VaultError::WrongCredential => {
                VfsError::PermissionDenied { path: path.clone() }
            }
            VaultError::Unsupported(_) => VfsError::Unsupported {
                operation: "vault operation",
            },
            VaultError::Io(source) => VfsError::Backend {
                path: path.clone(),
                source,
            },
            other => VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, other.to_string()),
            },
        }
    }
}
