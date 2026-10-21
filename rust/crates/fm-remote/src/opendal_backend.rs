//! OpenDAL VFS backend supporting S3, Aliyun OSS, and WebDAV.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, LocationKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use futures_util::StreamExt;
use opendal::services::{Oss, S3, Webdav};
use opendal::{EntryMode, Operator};
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
            let scheme = if port == 443 { "https" } else { "http" };
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
                mime: None,
            });
        }

        entries.sort_by(|a, b| {
            let a_dir = a.kind == EntryKind::Dir;
            let b_dir = b.kind == EntryKind::Dir;
            b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
        });

        Ok(entries)
    }

    async fn list_paged(
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

        entries.sort_by(|a, b| {
            let a_dir = a.kind == EntryKind::Dir;
            let b_dir = b.kind == EntryKind::Dir;
            b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
        });

        Ok((entries, has_more))
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let op_path = Self::to_opendal_path(path);
        let meta = match self.operator.stat(&op_path).await {
            Ok(meta) => meta,
            Err(e) if e.kind() == opendal::ErrorKind::NotFound => {
                // Object stores have no directory inodes: a "directory" only
                // exists as a common prefix of its children. Treat a path with
                // children as a directory instead of reporting NotFound.
                let op_dir = Self::to_opendal_dir_path(path);
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
            mime: None,
        })
    }

    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
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

    async fn open_read_range(
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

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        let op_path = Self::to_opendal_path(path);
        if mode == WriteMode::Create
            && self.operator.exists(&op_path).await.unwrap_or(false) {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "file already exists",
                    ),
                });
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

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let op_dir = Self::to_opendal_dir_path(path);
        self.operator
            .create_dir(&op_dir)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let op_path = Self::to_opendal_path(path);
        self.operator
            .delete(&op_path)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let op_from = Self::to_opendal_path(from);
        let op_to = Self::to_opendal_path(to);
        match self.operator.rename(&op_from, &op_to).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == opendal::ErrorKind::Unsupported => {
                // S3 and OSS lack native rename; fallback to server-side copy + delete
                self.operator.copy(&op_from, &op_to).await.map_err(|e| VfsError::Backend {
                    path: from.clone(),
                    source: std::io::Error::other(e.to_string()),
                })?;
                self.operator.delete(&op_from).await.map_err(|e| VfsError::Backend {
                    path: from.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
            }
            Err(e) => Err(VfsError::Backend {
                path: from.clone(),
                source: std::io::Error::other(e.to_string()),
            }),
        }
    }
}
