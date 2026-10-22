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

/// Shared host key pin. Seeded from the saved configuration; when empty,
/// the first key presented is recorded into it (trust on first use) and
/// every later connection — including reconnects of a cached session —
/// must present the same key.
type HostKeyPin = Arc<std::sync::Mutex<Option<String>>>;

fn host_key_fingerprint(key: &russh::keys::PublicKeyOrCertificate) -> String {
    match key {
        russh::keys::PublicKeyOrCertificate::PublicKey { key, .. } => {
            key.fingerprint(russh::keys::HashAlg::Sha256).to_string()
        }
        russh::keys::PublicKeyOrCertificate::Certificate(cert) => cert
            .public_key()
            .fingerprint(russh::keys::HashAlg::Sha256)
            .to_string(),
    }
}

struct SshHandler {
    pin: HostKeyPin,
}

impl russh::client::Handler for SshHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &russh::keys::PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        // This used to accept every key unconditionally, so anyone able to
        // intercept the connection could harvest the password or key
        // passphrase. Now the presented key must match the pin.
        let fingerprint = host_key_fingerprint(server_public_key);
        let mut pin = self.pin.lock().unwrap_or_else(|e| e.into_inner());
        match pin.as_deref() {
            Some(expected) => Ok(expected == fingerprint),
            None => {
                *pin = Some(fingerprint);
                Ok(true)
            }
        }
    }
}

/// Whether an error means the cached session is dead and a reconnect is
/// worthwhile. russh-sftp reports both a closed transport and a closed
/// request channel as `UnexpectedBehavior("session closed")` or `SendError`.
fn is_closed_error(error: &VfsError) -> bool {
    match error {
        VfsError::Connection { .. } => true,
        VfsError::Backend { source, .. } => {
            let text = source.to_string().to_lowercase();
            text.contains("session closed")
                || text.contains("senderror")
                || text.contains("connection reset")
                || text.contains("broken pipe")
                || text.contains("not connected")
        }
        _ => false,
    }
}

/// Keeps the SSH transport handle alive alongside the SFTP subsystem.
/// Dropping the russh `Handle` closes the underlying session, which would
/// make every later SFTP operation fail with "session closed".
pub struct SftpConnection {
    handle: russh::client::Handle<SshHandler>,
    sftp: SftpSession,
}

impl SftpConnection {
    /// Whether the underlying SSH transport is still open. Once it closes,
    /// every SFTP request fails with "session closed" until reconnected.
    fn is_alive(&self) -> bool {
        !self.handle.is_closed()
    }
}

pub struct SftpFs {
    config: RemoteConfig,
    session: Mutex<Option<Arc<SftpConnection>>>,
    host_key_pin: HostKeyPin,
    capabilities: Capabilities,
}

impl SftpFs {
    pub fn new(config: &RemoteConfig) -> Self {
        Self {
            config: config.clone(),
            session: Mutex::new(None),
            host_key_pin: Arc::new(std::sync::Mutex::new(
                config.host_key_fingerprint.clone(),
            )),
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

    /// The host key fingerprint this backend trusts: the configured pin,
    /// or the key recorded on first connect. The FFI layer persists it
    /// into the saved configuration so verification survives restarts.
    pub fn observed_host_key_fingerprint(&self) -> Option<String> {
        self.host_key_pin
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    pub async fn connect_session(
        config: &RemoteConfig,
        pin: &HostKeyPin,
    ) -> Result<Arc<SftpConnection>, VfsError> {
        let host = config.host.as_deref().unwrap_or("127.0.0.1");
        let port = config.port.unwrap_or(22);

        // Keep idle sessions alive instead of timing them out: the user may
        // sit on a directory for a long time between operations.
        let ssh_config = russh::client::Config {
            inactivity_timeout: None,
            keepalive_interval: Some(std::time::Duration::from_secs(30)),
            ..Default::default()
        };

        let handler = SshHandler { pin: pin.clone() };
        let mut session = russh::client::connect(Arc::new(ssh_config), (host, port), handler)
            .await
            .map_err(|e| VfsError::Connection {
                message: format!("SSH connection to {host}:{port} failed: {e}"),
            })?;

        let username = config.username.as_deref().unwrap_or("root");
        let mut auth_ok = false;
        // Why the key attempt failed, kept for the final error message.
        // Password auth below may still succeed (the password doubles as the
        // key passphrase), so this is only reported when every method failed —
        // but then the user can tell "bad passphrase" from "server refused".
        let mut key_failure: Option<String> = None;

        if let Some(priv_key_str) = &config.private_key {
            let passphrase = config.password.as_deref();
            match russh::keys::decode_secret_key(priv_key_str, passphrase) {
                Ok(key) => {
                    let rsa_hash = session.best_supported_rsa_hash().await.ok().flatten().flatten();
                    let key_with_alg =
                        russh::keys::PrivateKeyWithHashAlg::new(Arc::new(key), rsa_hash);
                    match session.authenticate_publickey(username, key_with_alg).await {
                        Ok(res) => {
                            if res.success() {
                                auth_ok = true;
                            } else {
                                key_failure =
                                    Some("the server rejected the private key".to_string());
                            }
                        }
                        Err(e) => {
                            key_failure = Some(format!("publickey authentication error: {e}"));
                        }
                    }
                }
                Err(e) => {
                    key_failure = Some(format!(
                        "failed to decode the private key (wrong passphrase or unsupported format): {e}"
                    ));
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
            let mut message =
                format!("SSH authentication failed for user '{username}' on {host}:{port}");
            if let Some(reason) = &key_failure {
                message.push_str(&format!("; private key attempt failed: {reason}"));
            }
            return Err(VfsError::Connection { message });
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
            handle: session,
            sftp,
        }))
    }

    async fn get_session(&self) -> Result<Arc<SftpConnection>, VfsError> {
        let mut guard = self.session.lock().await;
        if let Some(s) = guard.as_ref() {
            if s.is_alive() {
                return Ok(s.clone());
            }
            // The server closed the transport (idle timeout, network drop).
            // Keeping the dead handle makes every later call fail with
            // "session closed", so drop it and reconnect.
            *guard = None;
        }

        let s = Self::connect_session(&self.config, &self.host_key_pin).await?;
        *guard = Some(s.clone());
        Ok(s)
    }

    /// Forget the cached session so the next call reconnects.
    async fn drop_session(&self) {
        *self.session.lock().await = None;
    }

    /// Run one SFTP operation, reconnecting once if the transport died
    /// between the liveness check and the request.
    async fn run<T, F, Fut>(&self, op: F) -> VfsResult<T>
    where
        F: Fn(Arc<SftpConnection>) -> Fut,
        Fut: std::future::Future<Output = VfsResult<T>>,
    {
        let session = self.get_session().await?;
        match op(session).await {
            Err(error) if is_closed_error(&error) => {
                self.drop_session().await;
                let session = self.get_session().await?;
                op(session).await
            }
            result => result,
        }
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
        let sftp_path = self.resolve_path(dir);

        let read_dir = self
            .run(|session| {
                let sftp_path = sftp_path.clone();
                async move {
                session
                    .sftp
                    .read_dir(&sftp_path)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: dir.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })
                }
            })
            .await?;

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
                is_symlink: false,
                mime: None,
            });
        }

        Ok(entries)
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let sftp_path = self.resolve_path(path);

        let meta = self
            .run(|session| {
                let sftp_path = sftp_path.clone();
                async move {
                session
                    .sftp
                    .metadata(&sftp_path)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })
                }
            })
            .await?;

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
            is_symlink: false,
            mime: None,
        })
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let sftp_path = self.resolve_path(path);

        let file = self
            .run(|session| {
                let sftp_path = sftp_path.clone();
                async move {
                session
                    .sftp
                    .open(&sftp_path)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })
                }
            })
            .await?;

        Ok(Box::new(file))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        use tokio::io::{AsyncReadExt, AsyncSeekExt};

        let sftp_path = self.resolve_path(path);

        let file = self
            .run(|session| {
                let sftp_path = sftp_path.clone();
                async move {
                let mut file =
                    session
                        .sftp
                        .open(&sftp_path)
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: path.clone(),
                            source: std::io::Error::other(e.to_string()),
                        })?;
                if offset > 0 {
                    file.seek(std::io::SeekFrom::Start(offset))
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: path.clone(),
                            source: e,
                        })?;
                }
                Ok(file)
                }
            })
            .await?;

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
        let sftp_path = self.resolve_path(path);

        let flags = match mode {
            WriteMode::Create => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::EXCLUDE,
            WriteMode::Truncate => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::TRUNCATE,
            WriteMode::Append => OpenFlags::CREATE | OpenFlags::WRITE | OpenFlags::APPEND,
        };

        let file = self
            .run(|session| {
                let sftp_path = sftp_path.clone();
                async move {
                session
                    .sftp
                    .open_with_flags(&sftp_path, flags)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })
                }
            })
            .await?;

        Ok(Box::new(file))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let sftp_path = self.resolve_path(path);
        self.run(|session| {
            let sftp_path = sftp_path.clone();
            async move {
            session
                .sftp
                .create_dir(&sftp_path)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
            }
        })
        .await
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let sftp_path = self.resolve_path(path);
        self.run(|session| {
            let sftp_path = sftp_path.clone();
            async move {
            let meta = session
                .sftp
                .metadata(&sftp_path)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            if meta.is_dir() {
                session.sftp.remove_dir(&sftp_path).await
            } else {
                session.sftp.remove_file(&sftp_path).await
            }
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })
            }
        })
        .await
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let from_p = self.resolve_path(from);
        let to_p = self.resolve_path(to);
        self.run(|session| {
            let from_p = from_p.clone();
            let to_p = to_p.clone();
            async move {
            session
                .sftp
                .rename(&from_p, &to_p)
                .await
                .map_err(|e| VfsError::Backend {
                    path: from.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
            }
        })
        .await
    }
}
