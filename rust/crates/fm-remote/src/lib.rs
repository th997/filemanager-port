//! Remote protocol backends.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

pub mod crypt_backend;
pub mod ftp_backend;
pub mod multi_bucket;
pub mod opendal_backend;
pub(crate) mod pipe_writer;
pub mod sftp_backend;
pub mod smb_backend;

use fm_core::LocationKind;
use fm_vfs::{Vfs, VfsError, VfsResult};
use serde::{Deserialize, Serialize};

pub use crypt_backend::CryptFs;
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
#[derive(Clone, Serialize, Deserialize)]
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub passphrase: Option<String>,
    pub path_style: bool,
    /// Pinned SSH host key fingerprint in OpenSSH form (`SHA256:...`).
    /// When set, SFTP connections are rejected if the server presents a
    /// different key. When unset, the first key seen is pinned for the
    /// lifetime of the backend instance (trust on first use); the FFI
    /// layer persists it here so later launches verify from the start.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub host_key_fingerprint: Option<String>,
}

impl std::fmt::Debug for RemoteConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // A derived Debug would print passwords and keys in plaintext the
        // moment anyone logs a config.
        f.debug_struct("RemoteConfig")
            .field("id", &self.id)
            .field("kind", &self.kind)
            .field("display_name", &self.display_name)
            .field("endpoint", &self.endpoint)
            .field("region", &self.region)
            .field("bucket", &self.bucket)
            .field("host", &self.host)
            .field("port", &self.port)
            .field("root", &self.root)
            .field("username", &self.username)
            .field("password", &self.password.as_ref().map(|_| "<redacted>"))
            .field("key_id", &self.key_id)
            .field("key_secret", &self.key_secret.as_ref().map(|_| "<redacted>"))
            .field("private_key", &self.private_key.as_ref().map(|_| "<redacted>"))
            .field("passphrase", &self.passphrase.as_ref().map(|_| "<redacted>"))
            .field("path_style", &self.path_style)
            .field("host_key_fingerprint", &self.host_key_fingerprint)
            .finish()
    }
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
            LocationKind::Local | LocationKind::Archive | LocationKind::Crypt => None,
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

        let config = RemoteConfig {
            id: "sftp_test".into(),
            kind: LocationKind::Sftp,
            display_name: "SFTP Test".into(),
            endpoint: None,
            region: None,
            bucket: None,
            host: Some("127.0.0.1".into()),
            port: Some(22),
            root: "/".into(),
            username: Some("user".into()),
            password: Some("secret_password".into()),
            key_id: None,
            key_secret: Some("secret_key".into()),
            private_key: Some("secret_ssh_key".into()),
            passphrase: Some("secret_passphrase".into()),
            path_style: false,
            host_key_fingerprint: None,
        };
        let config_str = format!("{config:?}");
        assert!(!config_str.contains("secret_password"));
        assert!(!config_str.contains("secret_key"));
        assert!(!config_str.contains("secret_ssh_key"));
        assert!(!config_str.contains("secret_passphrase"));
        assert!(config_str.contains("<redacted>"));
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
                passphrase: None,
                path_style: false,
                host_key_fingerprint: None,
            };
            assert!(config.create_vfs().is_ok(), "create_vfs should succeed for {kind:?}");
        }
    }
}
