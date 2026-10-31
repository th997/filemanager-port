//! OpenDAL VFS backend supporting S3, Aliyun OSS, and WebDAV.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, LocationKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use futures_util::StreamExt;
use opendal::services::{Oss, S3, Webdav};
use opendal::{EntryMode, Operator};
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::SystemTime;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_util::compat::{FuturesAsyncReadCompatExt, FuturesAsyncWriteCompatExt};

use crate::RemoteConfig;

/// The facade crate has `auto-register-services` disabled, so the process-wide
/// HTTP transport has to be installed before the first operator runs.
fn ensure_http_transport() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(opendal::install_default);
}


/// Ceiling for one OpenDAL operation. The operator is built without a
/// timeout layer, and the reqwest transport underneath has no default
/// request deadline: a WebDAV/S3 server that accepts the connection
/// but never answers would hang the operation (and the UI waiting on
/// it) forever. Other backends all have timeouts — FTP wraps every
/// call, SMB sets a response timeout — this closes the same hole here.
const OP_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

async fn timed<T>(
    op_name: &'static str,
    fut: impl std::future::Future<Output = VfsResult<T>>,
) -> VfsResult<T> {
    tokio::time::timeout(OP_TIMEOUT, fut).await.map_err(|_| {
        VfsError::Connection {
            message: format!(
                "{op_name} timed out after {}s — the server stopped responding",
                OP_TIMEOUT.as_secs()
            ),
        }
    })?
}

pub struct OpendalFs {
    operator: Operator,
    kind: LocationKind,
    capabilities: Capabilities,
}

impl OpendalFs {
    pub fn new_s3(config: &RemoteConfig) -> Result<Self, VfsError> {
        ensure_http_transport();
        let mut builder = S3::default();
        if let Some(bucket) = &config.bucket {
            builder = builder.bucket(bucket);
        }
        if let Some(endpoint) = &config.endpoint {
            builder = builder.endpoint(endpoint);
        }
        if let Some(region) = &config.region {
            builder = builder.region(region);
        }
        if let Some(key_id) = &config.key_id {
            builder = builder.access_key_id(key_id);
        }
        if let Some(key_secret) = &config.key_secret {
            builder = builder.secret_access_key(key_secret);
        }
        if !config.root.is_empty() && config.root != "/" {
            builder = builder.root(&config.root);
        }
        let is_custom_endpoint = config
            .endpoint
            .as_deref()
            .map(|ep| !ep.contains(".amazonaws.com"))
            .unwrap_or(false);
        if !config.path_style && !is_custom_endpoint {
            builder = builder.enable_virtual_host_style();
        }

        let op = Operator::new(builder).map_err(|e| VfsError::Connection {
            message: format!("failed to initialize S3 operator: {e}"),
        })?;

        Ok(Self {
            operator: op,
            kind: LocationKind::S3,
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
        })
    }

    pub fn new_oss(config: &RemoteConfig) -> Result<Self, VfsError> {
        ensure_http_transport();
        let mut builder = Oss::default();
        if let Some(bucket) = &config.bucket {
            builder = builder.bucket(bucket);
        }
        if let Some(endpoint) = &config.endpoint {
            builder = builder.endpoint(endpoint);
        }
        if let Some(key_id) = &config.key_id {
            builder = builder.access_key_id(key_id);
        }
        if let Some(key_secret) = &config.key_secret {
            builder = builder.access_key_secret(key_secret);
        }
        if !config.root.is_empty() && config.root != "/" {
            builder = builder.root(&config.root);
        }

        let op = Operator::new(builder).map_err(|e| VfsError::Connection {
            message: format!("failed to initialize OSS operator: {e}"),
        })?;

        Ok(Self {
            operator: op,
            kind: LocationKind::Oss,
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
        })
    }

    pub fn new_webdav(config: &RemoteConfig) -> Result<Self, VfsError> {
        ensure_http_transport();
        let mut builder = Webdav::default();
        if let Some(endpoint) = &config.endpoint {
            builder = builder.endpoint(endpoint);
        } else if let Some(host) = &config.host {
            let port = config.port.unwrap_or(443);
            // Only the standard plain-HTTP port implies http. Every other
            // port defaults to https: inferring http from "not 443" silently
            // downgraded TLS servers on custom ports (8443 etc.) to plaintext,
            // credentials included. Plain HTTP on a nonstandard port can still
            // be configured through the full `endpoint` URL.
            let scheme = if port == 80 { "http" } else { "https" };
            builder = builder.endpoint(&format!("{scheme}://{host}:{port}"));
        }
        if let Some(user) = &config.username {
            builder = builder.username(user);
        }
        if let Some(pass) = &config.password {
            builder = builder.password(pass);
        }
        if !config.root.is_empty() && config.root != "/" {
            builder = builder.root(&config.root);
        }

        let op = Operator::new(builder).map_err(|e| VfsError::Connection {
            message: format!("failed to initialize WebDAV operator: {e}"),
        })?;

        Ok(Self {
            operator: op,
            kind: LocationKind::WebDav,
            capabilities: Capabilities::READ_WRITE,
        })
    }

    pub fn kind(&self) -> LocationKind {
        self.kind
    }

    fn to_opendal_path(path: &VfsPath) -> String {
        let segs = path.segments();
        if segs.is_empty() {
            String::new()
        } else {
            segs.join("/")
        }
    }

    fn to_opendal_dir_path(path: &VfsPath) -> String {
        let mut p = Self::to_opendal_path(path);
        if !p.is_empty() && !p.ends_with('/') {
            p.push('/');
        }
        p
    }
}

#[async_trait]
impl Vfs for OpendalFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        timed("list", self.list_impl(dir)).await
    }

    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        timed("list", self.list_paged_impl(dir, page, page_size)).await
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        timed("stat", self.stat_impl(path)).await
    }

    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        timed("open", self.open_read_impl(path)).await
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        timed("open", self.open_read_range_impl(path, offset, length)).await
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        timed("open for writing", self.open_write_impl(path, mode)).await
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        timed("create directory", self.mkdir_impl(path)).await
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        timed("delete", self.remove_impl(path)).await
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        timed("rename", self.rename_impl(from, to)).await
    }

}

impl OpendalFs {
    async fn list_impl(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let op_dir = Self::to_opendal_dir_path(dir);
        let mut lister = self
            .operator
            .lister(&op_dir)
            .await
            .map_err(|e| VfsError::Backend {
                path: dir.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        // Opendal listers yield the prefix entry itself when it exists; skip it
        // so a directory listing never contains a self-referencing child.
        let prefix = op_dir.trim_end_matches('/');

        let mut entries = Vec::new();
        while let Some(item_res) = lister.next().await {
            let item = item_res.map_err(|e| VfsError::Backend {
                path: dir.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

            let raw_path = item.path().trim_end_matches('/');
            if !prefix.is_empty() && raw_path == prefix {
                continue;
            }
            let name = match raw_path.rsplit('/').next() {
                Some(n) if !n.is_empty() => n.to_string(),
                _ => continue,
            };

            let meta = item.metadata();
            let is_dir = meta.mode() == EntryMode::DIR || item.path().ends_with('/');
            let kind = if is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            };

            let child_path = dir.join(&name);
            let size = if is_dir {
                None
            } else {
                Some(meta.content_length())
            };
            let modified = meta.last_modified().map(SystemTime::from);
            let hidden = name.starts_with('.');

            entries.push(Entry {
                name,
                path: child_path,
                kind,
                size,
                modified,
                mode: None,
                hidden,
                is_symlink: false,
                mime: None,
            });
        }

        entries.sort_unstable_by(|a, b| {
            let a_dir = a.kind == EntryKind::Dir;
            let b_dir = b.kind == EntryKind::Dir;
            b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
        });

        Ok(entries)
    }

    async fn list_paged_impl(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        let op_dir = Self::to_opendal_dir_path(dir);
        let mut lister = self
            .operator
            .lister(&op_dir)
            .await
            .map_err(|e| VfsError::Backend {
                path: dir.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        // Opendal listers yield the prefix entry itself; it must not consume a
        // page slot or appear as a child of its own directory.
        let prefix = op_dir.trim_end_matches('/');

        let page = page.max(1);
        let page_size = page_size.max(1);
        let skip = ((page - 1) as usize).saturating_mul(page_size as usize);

        let mut skipped = 0usize;
        while skipped < skip {
            match lister.next().await {
                Some(Ok(item)) => {
                    let raw_path = item.path().trim_end_matches('/');
                    if !prefix.is_empty() && raw_path == prefix {
                        continue;
                    }
                    skipped += 1;
                }
                Some(Err(e)) => {
                    return Err(VfsError::Backend {
                        path: dir.clone(),
                        source: std::io::Error::other(e.to_string()),
                    });
                }
                None => return Ok((Vec::new(), false)),
            }
        }

        let mut entries = Vec::with_capacity(page_size as usize);
        while entries.len() < page_size as usize {
            match lister.next().await {
                Some(Ok(item)) => {
                    let raw_path = item.path().trim_end_matches('/');
                    if !prefix.is_empty() && raw_path == prefix {
                        continue;
                    }
                    let name = match raw_path.rsplit('/').next() {
                        Some(n) if !n.is_empty() => n.to_string(),
                        _ => continue,
                    };

                    let meta = item.metadata();
                    let is_dir = meta.mode() == EntryMode::DIR || item.path().ends_with('/');
                    let kind = if is_dir {
                        EntryKind::Dir
                    } else {
                        EntryKind::File
                    };

                    let child_path = dir.join(&name);
                    let size = if is_dir {
                        None
                    } else {
                        Some(meta.content_length())
                    };
                    let modified = meta.last_modified().map(SystemTime::from);
                    let hidden = name.starts_with('.');

                    entries.push(Entry {
                        name,
                        path: child_path,
                        kind,
                        size,
                        modified,
                        mode: None,
                        hidden,
                        is_symlink: false,
                        mime: None,
                    });
                }
                Some(Err(e)) => {
                    return Err(VfsError::Backend {
                        path: dir.clone(),
                        source: std::io::Error::other(e.to_string()),
                    });
                }
                None => break,
            }
        }

        let has_more = lister.next().await.is_some();

        entries.sort_unstable_by(|a, b| {
            let a_dir = a.kind == EntryKind::Dir;
            let b_dir = b.kind == EntryKind::Dir;
            b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
        });

        Ok((entries, has_more))
    }

    async fn stat_impl(&self, path: &VfsPath) -> VfsResult<Entry> {
        let op_path = Self::to_opendal_path(path);
        let meta = match self.operator.stat(&op_path).await {
            Ok(meta) => meta,
            Err(e) if e.kind() == opendal::ErrorKind::NotFound => {
                let op_dir = Self::to_opendal_dir_path(path);
                // For WebDAV collections and directories with trailing slash
                if let Ok(dir_meta) = self.operator.stat(&op_dir).await {
                    let name = path.name().unwrap_or("").to_string();
                    let modified = dir_meta.last_modified().map(SystemTime::from);
                    return Ok(Entry {
                        name: name.clone(),
                        path: path.clone(),
                        kind: EntryKind::Dir,
                        size: None,
                        modified,
                        mode: None,
                        hidden: name.starts_with('.'),
                        is_symlink: false,
                        mime: None,
                    });
                }
                // Object stores have no directory inodes: a "directory" only
                // exists as a common prefix of its children. Treat a path with
                // children as a directory instead of reporting NotFound.
                let mut lister = self.operator.lister(&op_dir).await.map_err(|e| {
                    VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    }
                })?;
                let mut has_children = false;
                while let Some(item) = lister.next().await {
                    let item = item.map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })?;
                    if item.path().trim_end_matches('/') != op_dir.trim_end_matches('/') {
                        has_children = true;
                        break;
                    }
                }
                if !has_children {
                    return Err(VfsError::NotFound { path: path.clone() });
                }
                let name = path.name().unwrap_or("").to_string();
                return Ok(Entry {
                    name: name.clone(),
                    path: path.clone(),
                    kind: EntryKind::Dir,
                    size: None,
                    modified: None,
                    mode: None,
                    hidden: name.starts_with('.'),
                    is_symlink: false,
                    mime: None,
                });
            }
            Err(e) if e.kind() == opendal::ErrorKind::PermissionDenied => {
                return Err(VfsError::PermissionDenied { path: path.clone() });
            }
            Err(e) => {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
            }
        };

        let is_dir = meta.mode() == EntryMode::DIR;
        let kind = if is_dir {
            EntryKind::Dir
        } else {
            EntryKind::File
        };
        let name = path.name().unwrap_or("").to_string();
        let size = if is_dir {
            None
        } else {
            Some(meta.content_length())
        };
        let modified = meta.last_modified().map(SystemTime::from);
        let hidden = name.starts_with('.');

        Ok(Entry {
            name,
            path: path.clone(),
            kind,
            size,
            modified,
            mode: None,
            hidden,
            is_symlink: false,
            mime: None,
        })
    }

    async fn open_read_impl(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let op_path = Self::to_opendal_path(path);
        let reader = self
            .operator
            .reader(&op_path)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        let futures_reader = reader
            .into_futures_async_read(..)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        Ok(Box::new(futures_reader.compat()))
    }

    async fn open_read_range_impl(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        use opendal::BytesRange;

        let op_path = Self::to_opendal_path(path);
        let reader = self
            .operator
            .reader(&op_path)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        let futures_reader = reader
            .into_futures_async_read(BytesRange::new(offset, length))
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })?;

        Ok(Box::new(futures_reader.compat()))
    }

    async fn open_write_impl(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        let op_path = Self::to_opendal_path(path);
        if mode == WriteMode::Create {
            // A failed existence check must not degrade to "does not exist":
            // exclusive create would then overwrite a live object whenever
            // the check itself fails (network error, missing permission).
            let exists = self.operator.exists(&op_path).await.map_err(|e| {
                VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                }
            })?;
            if exists {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "file already exists",
                    ),
                });
            }
        }
        if self.kind == LocationKind::WebDav {
            // OpenDAL's WebDAV writer is a OneShotWriter that rejects multiple incremental writes.
            // Spool incoming writes into a buffer / temporary file and write all at once upon shutdown.
            return Ok(Box::new(WebdavSpoolWriter::new(
                self.operator.clone(),
                op_path,
                path.clone(),
            )));
        }

        let writer = if mode == WriteMode::Append {
            self.operator.writer_with(&op_path).append(true).await
        } else {
            self.operator.writer(&op_path).await
        }
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::other(e.to_string()),
        })?;

        let futures_writer = writer.into_futures_async_write();
        Ok(Box::new(futures_writer.compat_write()))
    }

    async fn mkdir_impl(&self, path: &VfsPath) -> VfsResult<()> {
        let op_dir = Self::to_opendal_dir_path(path);
        self.operator
            .create_dir(&op_dir)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })
    }

    async fn remove_impl(&self, path: &VfsPath) -> VfsResult<()> {
        let op_path = Self::to_opendal_path(path);
        let op_dir = Self::to_opendal_dir_path(path);

        let res = self.operator.delete(&op_path).await;
        if !op_dir.is_empty() && op_dir != op_path {
            let dir_res = self.operator.delete(&op_dir).await;
            if res.is_err() && dir_res.is_ok() {
                return Ok(());
            }
        }
        res.map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: std::io::Error::other(e.to_string()),
        })
    }

    async fn rename_impl(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let op_from = Self::to_opendal_path(from);
        let op_to = Self::to_opendal_path(to);
        match self.operator.rename(&op_from, &op_to).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == opendal::ErrorKind::Unsupported => {
                // S3 and OSS lack native rename; fallback to server-side copy + delete
                // Check if this is a directory rename
                let from_dir = Self::to_opendal_dir_path(from);
                let to_dir = Self::to_opendal_dir_path(to);
                let is_dir = if let Ok(meta) = self.operator.stat(&from_dir).await {
                    meta.mode() == opendal::EntryMode::DIR
                } else {
                    false
                };

                if is_dir {
                    // Copy all objects under from_dir to to_dir
                    let mut lister = self
                        .operator
                        .lister_with(&from_dir)
                        .recursive(true)
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: from.clone(),
                            source: std::io::Error::other(e.to_string()),
                        })?;

                    let mut to_delete = Vec::new();
                    while let Some(item_res) = lister.next().await {
                        let item = item_res.map_err(|e| VfsError::Backend {
                            path: from.clone(),
                            source: std::io::Error::other(e.to_string()),
                        })?;
                        let item_path = item.path().to_string();
                        if let Some(rel) = item_path.strip_prefix(&from_dir) {
                            let dst_item = format!("{to_dir}{rel}");
                            if item.metadata().mode() == opendal::EntryMode::DIR {
                                let _ = self.operator.create_dir(&dst_item).await;
                            } else {
                                self.operator.copy(&item_path, &dst_item).await.map_err(|e| {
                                    VfsError::Backend {
                                        path: from.clone(),
                                        source: std::io::Error::other(e.to_string()),
                                    }
                                })?;
                            }
                            to_delete.push(item_path);
                        }
                    }

                    // Also create destination directory marker if needed
                    let _ = self.operator.create_dir(&to_dir).await;
                    to_delete.push(from_dir.clone());
                    to_delete.push(op_from.clone());

                    for p in to_delete {
                        let _ = self.operator.delete(&p).await;
                    }
                    Ok(())
                } else {
                    self.operator.copy(&op_from, &op_to).await.map_err(|e| VfsError::Backend {
                        path: from.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })?;
                    self.operator.delete(&op_from).await.map_err(|e| VfsError::Backend {
                        path: from.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })
                }
            }
            Err(e) => Err(VfsError::Backend {
                path: from.clone(),
                source: std::io::Error::other(e.to_string()),
            }),
        }
    }
}

/// A spooling writer for WebDAV to bridge tokio `AsyncWrite` chunked streams
/// into OpenDAL's `OneShotWriter` which requires all content at once.
struct WebdavSpoolWriter {
    operator: Operator,
    op_path: String,
    path: VfsPath,
    mem_buf: Vec<u8>,
    temp_file: Option<tempfile::NamedTempFile>,
    shutdown_fut: Option<Pin<Box<dyn Future<Output = std::io::Result<()>> + Send>>>,
}

impl WebdavSpoolWriter {
    fn new(operator: Operator, op_path: String, path: VfsPath) -> Self {
        Self {
            operator,
            op_path,
            path,
            mem_buf: Vec::with_capacity(256 * 1024),
            temp_file: None,
            shutdown_fut: None,
        }
    }
}

const MEM_SPOOL_LIMIT: usize = 16 * 1024 * 1024; // 16 MB in-memory buffer before spilling to disk

impl AsyncWrite for WebdavSpoolWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        use std::io::Write;
        let this = self.as_mut().get_mut();
        if let Some(file) = &mut this.temp_file {
            let n = file.write(buf)?;
            return Poll::Ready(Ok(n));
        }

        if this.mem_buf.len() + buf.len() > MEM_SPOOL_LIMIT {
            let mut file = tempfile::NamedTempFile::new()?;
            file.write_all(&this.mem_buf)?;
            this.mem_buf.clear();
            this.mem_buf.shrink_to_fit();
            let n = file.write(buf)?;
            this.temp_file = Some(file);
            return Poll::Ready(Ok(n));
        }

        this.mem_buf.extend_from_slice(buf);
        Poll::Ready(Ok(buf.len()))
    }

    fn poll_flush(
        mut self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
    ) -> Poll<std::io::Result<()>> {
        use std::io::Write;
        let this = self.as_mut().get_mut();
        if let Some(file) = &mut this.temp_file {
            file.flush()?;
        }
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<std::io::Result<()>> {
        let this = self.as_mut().get_mut();
        if this.shutdown_fut.is_none() {
            let op = this.operator.clone();
            let op_path = this.op_path.clone();
            let path = this.path.clone();

            let load_data: std::io::Result<Vec<u8>> = if let Some(mut file) = this.temp_file.take() {
                use std::io::{Read, Seek, SeekFrom};
                file.seek(SeekFrom::Start(0))?;
                let mut v = Vec::new();
                file.read_to_end(&mut v)?;
                Ok(v)
            } else {
                Ok(std::mem::take(&mut this.mem_buf))
            };

            this.shutdown_fut = Some(Box::pin(async move {
                let data = load_data?;
                op.write(&op_path, data).await.map_err(|e| {
                    std::io::Error::other(format!("WebDAV write to {path} failed: {e}"))
                })?;
                Ok(())
            }));
        }

        this.shutdown_fut.as_mut().unwrap().as_mut().poll(cx)
    }
}
