//! Pure-Rust SFTP backend using russh and russh-sftp.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::OpenFlags;
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::Mutex;

use crate::RemoteConfig;

struct SshHandler;

impl russh::client::Handler for SshHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &russh::keys::PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

/// Keeps the SSH transport handle alive alongside the SFTP subsystem.
/// Dropping the russh `Handle` closes the underlying session, which would
/// make every later SFTP operation fail with "session closed".
pub struct SftpConnection {
    _handle: russh::client::Handle<SshHandler>,
    sftp: SftpSession,
}

pub struct SftpFs {
    config: RemoteConfig,
    session: Mutex<Option<Arc<SftpConnection>>>,
    capabilities: Capabilities,
}

impl SftpFs {
    pub fn new(config: &RemoteConfig) -> Self {
        Self {
            config: config.clone(),
            session: Mutex::new(None),
            capabilities: Capabilities {
                read: true,
                write: true,
                rename: true,
                copy: true,
                mkdir: true,
                remove: true,
                serve_http: false,
                serve_ftp: false,
            },
        }
    }

    pub async fn connect_session(config: &RemoteConfig) -> Result<Arc<SftpConnection>, VfsError> {
        let host = config.host.as_deref().unwrap_or("127.0.0.1");
        let port = config.port.unwrap_or(22);

        let mut ssh_config = russh::client::Config::default();
        // Keep idle sessions alive instead of timing them out: the user may
        // sit on a directory for a long time between operations.
        ssh_config.inactivity_timeout = None;
        ssh_config.keepalive_interval = Some(std::time::Duration::from_secs(30));

        let handler = SshHandler;
        let mut session = russh::client::connect(Arc::new(ssh_config), (host, port), handler)
            .await
            .map_err(|e| VfsError::Connection {
                message: format!("SSH connection to {host}:{port} failed: {e}"),
            })?;

        let username = config.username.as_deref().unwrap_or("root");
        let mut auth_ok = false;

        if let Some(priv_key_str) = &config.private_key {
            let passphrase = config.password.as_deref();
            if let Ok(key) = russh::keys::decode_secret_key(priv_key_str, passphrase) {
                let rsa_hash = session.best_supported_rsa_hash().await.ok().flatten().flatten();
                let key_with_alg = russh::keys::PrivateKeyWithHashAlg::new(Arc::new(key), rsa_hash);
                if let Ok(res) = session.authenticate_publickey(username, key_with_alg).await {
                    if res.success() {
                        auth_ok = true;
                    }
                }
            }
        }

        if !auth_ok {
            if let Some(password) = &config.password {
                let res = session
                    .authenticate_password(username, password)
                    .await
                    .map_err(|e| VfsError::Connection {
                        message: format!("SSH password authentication error: {e}"),
                    })?;
                if res.success() {
                    auth_ok = true;
                }
            }
        }

        if !auth_ok {
            return Err(VfsError::Connection {
                message: format!("SSH authentication failed for user '{username}' on {host}:{port}"),
            });
        }

        let channel = session.channel_open_session().await.map_err(|e| VfsError::Connection {
            message: format!("Failed to open SSH channel: {e}"),
        })?;
        channel
            .request_subsystem(true, "sftp")
            .await
            .map_err(|e| VfsError::Connection {
                message: format!("Failed to request SFTP subsystem: {e}"),
            })?;

        let sftp = SftpSession::new(channel.into_stream())
            .await
            .map_err(|e| VfsError::Connection {
                message: format!("Failed to initialize SFTP session: {e}"),
            })?;

        Ok(Arc::new(SftpConnection {
            _handle: session,
            sftp,
        }))
    }

    async fn get_session(&self) -> Result<Arc<SftpConnection>, VfsError> {
        let mut guard = self.session.lock().await;
        if let Some(s) = guard.as_ref() {
            return Ok(s.clone());
        }

        let s = Self::connect_session(&self.config).await?;
        *guard = Some(s.clone());
        Ok(s)
    }

    fn resolve_path(&self, path: &VfsPath) -> String {
        let root = self.config.root.trim_end_matches('/');
        let mut out = root.to_string();
        for segment in path.segments() {
            out.push('/');
            out.push_str(segment);
        }
        if out.is_empty() {
            "/".to_string()
        } else {
            out
        }
    }
}

#[async_trait]
impl Vfs for SftpFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(dir);

        let read_dir = session.sftp.read_dir(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: dir.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;

        let mut entries = Vec::new();
        for item in read_dir {
            let name = item.file_name();
            let is_dir = item.file_type().is_dir();
            let child_path = dir.join(&name);
            let meta = item.metadata();
            let size = if is_dir { None } else { Some(meta.len()) };
            let modified = meta.modified().ok();

            entries.push(Entry {
                name: name.clone(),
                path: child_path,
                kind: if is_dir { EntryKind::Dir } else { EntryKind::File },
                size,
                modified,
                mode: None,
                hidden: name.starts_with('.'),
                mime: None,
            });
        }

        Ok(entries)
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);

        let meta = session.sftp.metadata(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;

        let is_dir = meta.is_dir();
        let name = path.name().unwrap_or("").to_string();

        Ok(Entry {
            name,
            path: path.clone(),
            kind: if is_dir { EntryKind::Dir } else { EntryKind::File },
            size: if is_dir { None } else { Some(meta.len()) },
            modified: meta.modified().ok(),
            mode: None,
            hidden: path.name().map(|n| n.starts_with('.')).unwrap_or(false),
            mime: None,
        })
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);

        let file = session.sftp.open(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;

        Ok(Box::new(file))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        use tokio::io::{AsyncReadExt, AsyncSeekExt};

        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);

        let mut file = session.sftp.open(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;
        if offset > 0 {
            file.seek(std::io::SeekFrom::Start(offset))
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
        }

        Ok(match length {
            Some(len) => Box::new(file.take(len)),
            None => Box::new(file),
        })
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);

        let flags = match mode {
            WriteMode::Create => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::EXCLUDE,
            WriteMode::Truncate => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::TRUNCATE,
            WriteMode::Append => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::APPEND,
        };

        let file = session
            .sftp
            .open_with_flags(&sftp_path, flags)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
            })?;

        Ok(Box::new(file))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);
        session.sftp.create_dir(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let session = self.get_session().await?;
        let sftp_path = self.resolve_path(path);
        let meta = session.sftp.metadata(&sftp_path).await.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;
        if meta.is_dir() {
            session.sftp.remove_dir(&sftp_path).await
        } else {
            session.sftp.remove_file(&sftp_path).await
        }
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })?;
        Ok(())
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let session = self.get_session().await?;
        let from_p = self.resolve_path(from);
        let to_p = self.resolve_path(to);
        session.sftp.rename(&from_p, &to_p).await.map_err(|e| VfsError::Backend {
            path: from.clone(),
            source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
        })
    }
}
