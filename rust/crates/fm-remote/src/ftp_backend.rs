//! Pure-Rust FTP and FTPS backend using suppaftp.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, LocationKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use suppaftp::list::ListParser;
use suppaftp::tokio::{
    AsyncFtpStream, AsyncRustlsConnector, AsyncRustlsFtpStream, ImplAsyncFtpStream,
    TokioTlsStream, TransferStream,
};
use suppaftp::tokio_rustls::rustls::{ClientConfig, RootCertStore};
use suppaftp::tokio_rustls::TlsConnector as RustlsTlsConnector;
use suppaftp::types::FileType;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::Mutex;

use crate::pipe_writer::{drain_pipe, pipe_writer, signaling_reader};
use crate::RemoteConfig;

/// Bound on connecting and on every control-channel operation. Nothing in
/// this backend set a timeout before, so a server that accepted the TCP
/// connection and then went silent parked the caller (and the client
/// mutex) forever.
const FTP_TIMEOUT: Duration = Duration::from_secs(30);

/// Whether an FTP failure means the control connection itself is dead
/// (as opposed to the server refusing a command). Only these justify
/// discarding the cached connection and retrying on a fresh one.
fn is_connection_error(e: &suppaftp::FtpError) -> bool {
    matches!(e, suppaftp::FtpError::ConnectionError(_))
}

pub enum FtpClient {
    Plain(AsyncFtpStream),
    Tls(AsyncRustlsFtpStream),
}

pub struct FtpFs {
    config: RemoteConfig,
    client: Mutex<Option<FtpClient>>,
    capabilities: Capabilities,
}

macro_rules! with_client {
    ($client:expr, $ftp:ident => $body:expr) => {
        match $client {
            FtpClient::Plain(ref mut $ftp) => $body,
            FtpClient::Tls(ref mut $ftp) => $body,
        }
    };
}

/// Run a control-channel operation against the cached client under a
/// timeout, as a `Result<_, suppaftp::FtpError>`.
///
/// The body is a future expression over `$ftp` (no `.await`): the timeout
/// is applied inside each match arm because the plain and TLS streams
/// produce different future types. On a connection-class failure or a
/// timeout the cached client is discarded and the operation retried
/// exactly once on a fresh connection: FTP servers routinely drop idle
/// control connections, and the previous behaviour reused the dead
/// connection forever, so one server-side idle timeout broke the remote
/// until app restart. The caller guarantees the guard already holds a
/// connected client.
macro_rules! cached_op {
    ($guard:expr, $config:expr, $ftp:ident => $body:expr) => {{
        let mut retried = false;
        loop {
            let attempt = {
                let client = $guard
                    .as_mut()
                    .expect("cached operation requires an established connection");
                match client {
                    FtpClient::Plain(ref mut $ftp) => {
                        tokio::time::timeout(FTP_TIMEOUT, $body).await
                    }
                    FtpClient::Tls(ref mut $ftp) => {
                        tokio::time::timeout(FTP_TIMEOUT, $body).await
                    }
                }
            };
            match attempt {
                Ok(Ok(value)) => break Ok::<_, suppaftp::FtpError>(value),
                Ok(Err(e)) => {
                    if retried || !is_connection_error(&e) {
                        break Err(e);
                    }
                }
                Err(_) => {
                    if retried {
                        break Err(suppaftp::FtpError::ConnectionError(
                            std::io::Error::new(
                                std::io::ErrorKind::TimedOut,
                                "FTP operation timed out",
                            ),
                        ));
                    }
                }
            }
            retried = true;
            *$guard = None;
            match FtpFs::connect_client($config).await {
                Ok(client) => *$guard = Some(client),
                Err(e) => {
                    break Err(suppaftp::FtpError::ConnectionError(
                        std::io::Error::other(e.to_string()),
                    ));
                }
            }
        }
    }};
}

impl FtpFs {
    pub fn new(config: &RemoteConfig) -> Self {
        Self {
            config: config.clone(),
            client: Mutex::new(None),
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

    pub async fn connect_client(config: &RemoteConfig) -> Result<FtpClient, VfsError> {
        tokio::time::timeout(FTP_TIMEOUT, Self::connect_client_inner(config))
            .await
            .map_err(|_| VfsError::Connection {
                message: format!(
                    "FTP connection to {}:{} timed out",
                    config.host.as_deref().unwrap_or("127.0.0.1"),
                    config.port.unwrap_or(21)
                ),
            })?
    }

    async fn connect_client_inner(config: &RemoteConfig) -> Result<FtpClient, VfsError> {
        let host = config.host.as_deref().unwrap_or("127.0.0.1");
        let port = config.port.unwrap_or(21);
        let addr = format!("{host}:{port}");

        let user = config.username.as_deref().unwrap_or("anonymous");
        let pass = config.password.as_deref().unwrap_or("anonymous@example.com");

        let connect_error = |e: suppaftp::FtpError| VfsError::Connection {
            message: format!("FTP connection to {addr} failed: {e}"),
        };

        if config.kind == LocationKind::Ftps {
            let mut roots = RootCertStore::empty();
            roots.add_parsable_certificates(
                webpki_root_certs::TLS_SERVER_ROOT_CERTS.iter().cloned(),
            );
            let tls = ClientConfig::builder()
                .with_root_certificates(roots)
                .with_no_client_auth();
            let connector = AsyncRustlsConnector::from(RustlsTlsConnector::from(Arc::new(tls)));

            // Port 990 is implicit FTPS (TLS from the first byte); other ports
            // use explicit FTPS (AUTH TLS after the greeting).
            let mut ftp = if port == 990 {
                AsyncRustlsFtpStream::connect_secure_implicit(&addr, connector, host)
                    .await
                    .map_err(connect_error)?
            } else {
                AsyncRustlsFtpStream::connect(&addr)
                    .await
                    .map_err(connect_error)?
                    .into_secure(connector, host)
                    .await
                    .map_err(connect_error)?
            };

            ftp.login(user, pass)
                .await
                .map_err(|e| VfsError::Connection {
                    message: format!("FTPS login failed for '{user}' on {addr}: {e}"),
                })?;
            return Ok(FtpClient::Tls(ftp));
        }

        let mut ftp = AsyncFtpStream::connect(&addr)
            .await
            .map_err(connect_error)?;
        ftp.login(user, pass)
            .await
            .map_err(|e| VfsError::Connection {
                message: format!("FTP login failed for '{user}' on {addr}: {e}"),
            })?;

        Ok(FtpClient::Plain(ftp))
    }

    /// Start a ranged download on its own connection and stream it through an
    /// in-memory pipe.
    ///
    /// A dedicated connection avoids racing the completion reply of an earlier
    /// transfer on the shared control channel, and `REST`/`RETR` are per
    /// connection anyway. The spawned task owns both the client and the
    /// transfer stream, so nothing borrows `FtpFs` and a dropped reader stops
    /// the copy at the next write.
    async fn spawn_reader(
        config: &RemoteConfig,
        ftp_path: String,
        offset: u64,
        length: Option<u64>,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let client = Self::connect_client(config).await?;

        // Issue REST/RETR before returning so the caller sees connection
        // failures; the body of the transfer then runs in the background.
        // The signaling reader surfaces a mid-transfer read failure as a
        // read error on the caller's side instead of a clean EOF.
        let out = match client {
            FtpClient::Plain(mut ftp) => {
                let stream = start_download(&mut ftp, &ftp_path, offset, path).await?;
                signaling_reader(move |writer| pump_download(ftp, stream, length, writer))
            }
            FtpClient::Tls(mut ftp) => {
                let stream = start_download(&mut ftp, &ftp_path, offset, path).await?;
                signaling_reader(move |writer| pump_download(ftp, stream, length, writer))
            }
        };

        Ok(out)
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

    fn ftp_error(path: &VfsPath, e: impl std::fmt::Display) -> VfsError {
        VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::other(e.to_string()),
        }
    }
}

/// Put `REST`/`RETR` on the wire and hand back the data stream.
async fn start_download<T>(
    ftp: &mut ImplAsyncFtpStream<T>,
    ftp_path: &str,
    offset: u64,
    path: &VfsPath,
) -> VfsResult<TransferStream<T>>
where
    T: TokioTlsStream + Send,
{
    ftp.transfer_type(FileType::Binary)
        .await
        .map_err(|e| FtpFs::ftp_error(path, e))?;
    if offset > 0 {
        ftp.resume_transfer(offset as usize)
            .await
            .map_err(|e| FtpFs::ftp_error(path, e))?;
    }
    ftp.retr_as_stream(ftp_path)
        .await
        .map_err(|e| FtpFs::ftp_error(path, e))
}

/// Copy at most `length` bytes of the download into `writer`, then finalize.
///
/// A failed read is returned as `Err` so the signaling reader can report
/// it; the previous version broke the loop on any error and shut the pipe
/// down cleanly, so a truncated download looked complete to the caller.
async fn pump_download<T>(
    ftp: ImplAsyncFtpStream<T>,
    mut stream: TransferStream<T>,
    length: Option<u64>,
    mut writer: tokio::io::DuplexStream,
) -> Result<(), String>
where
    T: TokioTlsStream + Send + 'static,
{
    // Keep the control connection alive until the transfer finishes.
    let _ftp = ftp;
    let mut left = length.unwrap_or(u64::MAX);
    let mut buf = vec![0u8; 64 * 1024];
    let mut failure: Option<String> = None;
    while left > 0 {
        let want = left.min(buf.len() as u64) as usize;
        match stream.read(&mut buf[..want]).await {
            Ok(0) => break,
            Ok(n) => {
                if writer.write_all(&buf[..n]).await.is_err() {
                    // Reader went away (seek, close); stop downloading.
                    break;
                }
                left -= n as u64;
            }
            Err(e) => {
                failure = Some(format!("FTP download failed mid-transfer: {e}"));
                break;
            }
        }
    }
    let _ = stream.finish().await;
    let _ = writer.shutdown().await;
    match failure {
        Some(msg) => Err(msg),
        None => Ok(()),
    }
}

async fn upload(
    config: &RemoteConfig,
    ftp_path: String,
    mode: WriteMode,
    mut rx: tokio::io::DuplexStream,
) -> Result<(), String> {
    let mut client = FtpFs::connect_client(config)
        .await
        .map_err(|e| e.to_string())?;

    macro_rules! send {
        ($ftp:expr) => {{
            $ftp.transfer_type(FileType::Binary)
                .await
                .map_err(|e| e.to_string())?;
            let mut stream = if mode == WriteMode::Append {
                $ftp.append_with_stream(&ftp_path).await
            } else {
                $ftp.put_with_stream(&ftp_path).await
            }
            .map_err(|e| e.to_string())?;
            drain_pipe(&mut rx, &mut stream).await?;
            stream.finish().await.map_err(|e| e.to_string())?;
        }};
    }

    with_client!(client, ftp => send!(ftp));
    Ok(())
}

#[async_trait]
impl Vfs for FtpFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let mut guard = self.client.lock().await;
        if guard.is_none() {
            *guard = Some(Self::connect_client(&self.config).await?);
        }

        let ftp_path = self.resolve_path(dir);
        let lines = cached_op!(guard, &self.config, ftp => ftp.list(Some(&ftp_path)))
            .map_err(|e| Self::ftp_error(dir, e))?;

        let mut entries = Vec::new();
        for line in lines {
            if let Ok(f) = ListParser::parse_posix(&line).or_else(|_| ListParser::parse_dos(&line)) {
                let name = f.name().to_string();
                if name == "." || name == ".." {
                    continue;
                }
                let is_dir = f.is_directory();
                let child_path = dir.join(&name);
                entries.push(Entry {
                    name: name.clone(),
                    path: child_path,
                    kind: if is_dir { EntryKind::Dir } else { EntryKind::File },
                    size: if is_dir { None } else { Some(f.size() as u64) },
                    modified: Some(f.modified()),
                    mode: None,
                    hidden: name.starts_with('.'),
                    is_symlink: false,
                    mime: None,
                });
            }
        }

        Ok(entries)
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let mut guard = self.client.lock().await;
        if guard.is_none() {
            *guard = Some(Self::connect_client(&self.config).await?);
        }

        let ftp_path = self.resolve_path(path);
        let name = path.name().unwrap_or("").to_string();
        let mut size = cached_op!(guard, &self.config, ftp => ftp.size(&ftp_path))
            .ok()
            .map(|s| s as u64);

        // Some servers reject SIZE; fall back to the parent listing before
        // concluding this is a directory.
        if size.is_none() {
            let parent = ftp_path.rsplit_once('/').map(|(p, _)| p).unwrap_or("");
            let parent = if parent.is_empty() { "/" } else { parent };
            let lines = cached_op!(guard, &self.config, ftp => ftp.list(Some(parent)));
            if let Ok(lines) = lines {
                for line in lines {
                    if let Ok(f) = ListParser::parse_posix(&line)
                        .or_else(|_| ListParser::parse_dos(&line))
                    {
                        if f.name() == name && !f.is_directory() {
                            size = Some(f.size() as u64);
                            break;
                        }
                    }
                }
            }
        }

        Ok(Entry {
            name,
            path: path.clone(),
            kind: if size.is_some() { EntryKind::File } else { EntryKind::Dir },
            size,
            modified: None,
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
        let ftp_path = self.resolve_path(path);
        Self::spawn_reader(&self.config, ftp_path, 0, None, path).await
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let ftp_path = self.resolve_path(path);
        Self::spawn_reader(&self.config, ftp_path, offset, length, path).await
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        if !self.capabilities.write {
            return Err(VfsError::Unsupported { operation: "write" });
        }
        let ftp_path = self.resolve_path(path);
        let config = self.config.clone();
        Ok(pipe_writer(move |rx| async move {
            upload(&config, ftp_path, mode, rx).await
        }))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let mut guard = self.client.lock().await;
        if guard.is_none() {
            *guard = Some(Self::connect_client(&self.config).await?);
        }

        let ftp_path = self.resolve_path(path);
        cached_op!(guard, &self.config, ftp => ftp.mkdir(&ftp_path))
            .map_err(|e| Self::ftp_error(path, e))?;
        Ok(())
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let mut guard = self.client.lock().await;
        if guard.is_none() {
            *guard = Some(Self::connect_client(&self.config).await?);
        }

        let ftp_path = self.resolve_path(path);
        let removed = cached_op!(guard, &self.config, ftp => async {
            if ftp.rm(&ftp_path).await.is_err() {
                ftp.rmdir(&ftp_path).await
            } else {
                Ok(())
            }
        });
        removed.map_err(|e| Self::ftp_error(path, e))?;
        Ok(())
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let mut guard = self.client.lock().await;
        if guard.is_none() {
            *guard = Some(Self::connect_client(&self.config).await?);
        }

        let from_p = self.resolve_path(from);
        let to_p = self.resolve_path(to);
        cached_op!(guard, &self.config, ftp => ftp.rename(&from_p, &to_p))
            .map_err(|e| Self::ftp_error(from, e))?;
        Ok(())
    }
}
