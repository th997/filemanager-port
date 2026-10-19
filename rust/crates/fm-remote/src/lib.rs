//! Remote protocol backends.

pub mod ftp_backend;
pub mod multi_bucket;
pub mod opendal_backend;
pub mod sftp_backend;
pub mod smb_backend;

use fm_core::LocationKind;
use fm_vfs::{Vfs, VfsError, VfsResult};
use serde::{Deserialize, Serialize};

pub use ftp_backend::FtpFs;
pub use multi_bucket::MultiBucketFs;
pub use opendal_backend::OpendalFs;
pub use sftp_backend::SftpFs;
pub use smb_backend::SmbFs;

/// Credentials are kept out of logs and Debug output.
#[derive(Clone, Serialize, Deserialize)]
pub enum Credential {
    Anonymous,
    Password { username: String, password: String },
    PrivateKey { username: String, key: String, passphrase: Option<String> },
    AccessKey { access_key_id: String, secret_access_key: String },
}

impl std::fmt::Debug for Credential {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Anonymous => f.write_str("Credential::Anonymous"),
            Self::Password { username, .. } => f
                .debug_struct("Credential::Password")
                .field("username", username)
                .field("password", &"<redacted>")
                .finish(),
            Self::PrivateKey { username, .. } => f
                .debug_struct("Credential::PrivateKey")
                .field("username", username)
                .field("key", &"<redacted>")
                .finish(),
            Self::AccessKey { access_key_id, .. } => f
                .debug_struct("Credential::AccessKey")
                .field("access_key_id", access_key_id)
                .field("secret_access_key", &"<redacted>")
                .finish(),
        }
    }
}

/// Unified configuration for remote and cloud connections.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteConfig {
    pub id: String,
    pub kind: LocationKind,
    pub display_name: String,
    pub endpoint: Option<String>,
    pub region: Option<String>,
    pub bucket: Option<String>,
    pub host: Option<String>,
    pub port: Option<u16>,
    pub root: String,
    pub username: Option<String>,
    pub password: Option<String>,
    pub key_id: Option<String>,
    pub key_secret: Option<String>,
    pub private_key: Option<String>,
    pub path_style: bool,
}

impl RemoteConfig {
    /// Default port per protocol. Unknown kinds return `None` rather than a
    /// guessed value.
    pub fn default_port(kind: LocationKind) -> Option<u16> {
        match kind {
            LocationKind::Sftp => Some(22),
            LocationKind::Ftp => Some(21),
            LocationKind::Ftps => Some(990),
            LocationKind::Smb => Some(445),
            LocationKind::WebDav | LocationKind::S3 | LocationKind::Oss => Some(443),
            LocationKind::Local | LocationKind::Archive => None,
        }
    }

    /// Construct a Vfs backend instance from this configuration.
    pub fn create_vfs(&self) -> VfsResult<Box<dyn Vfs>> {
        match self.kind {
            LocationKind::S3 => {
                let is_multi = self
                    .bucket
                    .as_deref()
                    .map(|b| b.trim().is_empty() || b.contains(',') || b.contains(' '))
                    .unwrap_or(true);
                if is_multi {
                    let fs = MultiBucketFs::new(self);
                    Ok(Box::new(fs))
                } else {
                    let fs = OpendalFs::new_s3(self)?;
                    Ok(Box::new(fs))
                }
            }
            LocationKind::Oss => {
                let is_multi = self
                    .bucket
                    .as_deref()
                    .map(|b| b.trim().is_empty() || b.contains(',') || b.contains(' '))
                    .unwrap_or(true);
                if is_multi {
                    let fs = MultiBucketFs::new(self);
                    Ok(Box::new(fs))
                } else {
                    let fs = OpendalFs::new_oss(self)?;
                    Ok(Box::new(fs))
                }
            }
            LocationKind::WebDav => {
                let fs = OpendalFs::new_webdav(self)?;
                Ok(Box::new(fs))
            }
            LocationKind::Sftp => {
                let fs = SftpFs::new(self);
                Ok(Box::new(fs))
            }
            LocationKind::Ftp | LocationKind::Ftps => {
                let fs = FtpFs::new(self);
                Ok(Box::new(fs))
            }
            LocationKind::Smb => {
                let fs = SmbFs::new(self);
                Ok(Box::new(fs))
            }
            _ => Err(VfsError::Unsupported {
                operation: "unsupported location kind",
            }),
        }
    }

    /// Test if connection can be established with the given configuration.
    pub async fn test_connection(&self) -> Result<bool, String> {
        let vfs = self.create_vfs().map_err(|e| e.to_string())?;
        match vfs.list(&fm_core::VfsPath::root()).await {
            Ok(_) => Ok(true),
            Err(VfsError::NotFound { .. }) => Ok(true),
            Err(e) => Err(e.to_string()),
        }
    }
}

#[derive(Debug, Clone)]
pub struct RemoteSpec {
    pub kind: LocationKind,
    pub host: String,
    pub port: u16,
    pub root: String,
    pub credential: Credential,
}

impl RemoteSpec {
    pub fn default_port(kind: LocationKind) -> Option<u16> {
        RemoteConfig::default_port(kind)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_redacts_secrets() {
        let credential = Credential::Password {
            username: "u".into(),
            password: "hunter2".into(),
        };
        let rendered = format!("{credential:?}");
        assert!(!rendered.contains("hunter2"));
        assert!(rendered.contains("<redacted>"));
    }

    #[test]
    fn default_ports_are_protocol_specific() {
        assert_eq!(RemoteConfig::default_port(LocationKind::Sftp), Some(22));
        assert_eq!(RemoteConfig::default_port(LocationKind::Ftp), Some(21));
        assert_eq!(RemoteConfig::default_port(LocationKind::Ftps), Some(990));
        assert_eq!(RemoteConfig::default_port(LocationKind::Smb), Some(445));
        assert_eq!(RemoteConfig::default_port(LocationKind::S3), Some(443));
        assert_eq!(RemoteConfig::default_port(LocationKind::Oss), Some(443));
        assert_eq!(RemoteConfig::default_port(LocationKind::Local), None);
    }

    #[test]
    fn create_vfs_supports_all_remote_protocols() {
        let protocols = [
            LocationKind::Sftp,
            LocationKind::Ftp,
            LocationKind::Ftps,
            LocationKind::Smb,
        ];

        for kind in protocols {
            let config = RemoteConfig {
                id: "test".into(),
                kind,
                display_name: "Test".into(),
                endpoint: None,
                region: None,
                bucket: None,
                host: Some("127.0.0.1".into()),
                port: None,
                root: "/".into(),
                username: Some("user".into()),
                password: Some("pass".into()),
                key_id: None,
                key_secret: None,
                private_key: None,
                path_style: false,
            };
            assert!(config.create_vfs().is_ok(), "create_vfs should succeed for {kind:?}");
        }
    }
}
