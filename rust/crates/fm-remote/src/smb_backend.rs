//! Pure-Rust SMB2/3 backend using smb2 crate.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use smb2::client::stream::FileReader;
use smb2::client::{ClientConfig, SmbClient, Tree};
use std::collections::HashMap;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::Mutex;

use crate::RemoteConfig;

struct SmbSession {
    client: SmbClient,
    trees: HashMap<String, Tree>,
}

pub struct SmbFs {
    config: RemoteConfig,
    session: Mutex<Option<SmbSession>>,
    capabilities: Capabilities,
}

impl SmbFs {
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

    pub async fn connect_client(config: &RemoteConfig) -> Result<SmbClient, VfsError> {
        let host = config.host.as_deref().unwrap_or("127.0.0.1");
        let port = config.port.unwrap_or(445);
        let addr = format!("{host}:{port}");

        let smb_config = ClientConfig {
            addr,
            timeout: Duration::from_secs(10),
            username: config.username.clone().unwrap_or_default(),
            password: config.password.clone().unwrap_or_default(),
            domain: String::new(),
            auto_reconnect: true,
            compression: false,
            dfs_enabled: true,
            dfs_target_overrides: HashMap::new(),
            connect_options: None,
            response_timeout: Some(Duration::from_secs(10)),
        };

        SmbClient::connect(smb_config).await.map_err(|e| VfsError::Connection {
            message: format!("SMB connection error: {e}"),
        })
    }

    fn split_path(&self, path: &VfsPath) -> (Option<String>, String) {
        let root = self.config.root.trim_matches('/');
        let rel = path.to_slash_string();

        if !root.is_empty() {
            let mut parts = root.splitn(2, '/');
            let share = parts.next().unwrap_or("").to_string();
            let prefix = parts.next().unwrap_or("");
            let full_sub = if prefix.is_empty() {
                rel
            } else if rel.is_empty() {
                prefix.to_string()
            } else {
                format!("{prefix}/{rel}")
            };
            (Some(share), full_sub)
        } else if rel.is_empty() {
            (None, String::new())
        } else {
            let mut parts = rel.splitn(2, '/');
            let share = parts.next().unwrap_or("").to_string();
            let sub = parts.next().unwrap_or("").to_string();
            (Some(share), sub)
        }
    }

    /// Stream positioned reads through an in-memory pipe.
    ///
    /// SMB has no seekable read handle, only `read_at`, so the spawn loop is
    /// what keeps the caller from buffering the whole file.
    fn spawn_range_reader(
        reader: FileReader,
        offset: u64,
        length: Option<u64>,
    ) -> Box<dyn AsyncRead + Send + Unpin> {
        use tokio::io::AsyncWriteExt;

        let size = reader.size();
        let remaining = match length {
            Some(len) => len.min(size.saturating_sub(offset)),
            None => size.saturating_sub(offset),
        };

        let (mut writer, out) = tokio::io::duplex(256 * 1024);
        tokio::spawn(async move {
            let mut pos = offset;
            let mut left = remaining;
            while left > 0 {
                let want = left.min(256 * 1024);
                match reader.read_at(pos, want).await {
                    Ok(chunk) if !chunk.is_empty() => {
                        if writer.write_all(&chunk).await.is_err() {
                            break;
                        }
                        let n = chunk.len() as u64;
                        pos += n;
                        left -= n;
                    }
                    _ => break,
                }
            }
            let _ = reader.close().await;
            let _ = writer.shutdown().await;
        });

        Box::new(out)
    }

    async fn get_share_tree(
        session: &mut SmbSession,
        share: &str,
    ) -> Result<Tree, VfsError> {
        if !session.trees.contains_key(share) {
            let tree = session
                .client
                .connect_share(share)
                .await
                .map_err(|e| VfsError::Connection {
                    message: format!("Failed to connect to SMB share '{share}': {e}"),
                })?;
            session.trees.insert(share.to_string(), tree);
        }
        Ok(session.trees.get(share).unwrap().clone())
    }
}

#[async_trait]
impl Vfs for SmbFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(dir);

        match share_opt {
            None => {
                // List root shares
                let shares = session
                    .client
                    .list_shares()
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: dir.clone(),
                        source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                    })?;

                let entries = shares
                    .into_iter()
                    .map(|s| Entry {
                        name: s.name.clone(),
                        path: dir.join(&s.name),
                        kind: EntryKind::Dir,
                        size: None,
                        modified: None,
                        mode: None,
                        hidden: s.name.ends_with('$'),
                        mime: None,
                    })
                    .collect();

                Ok(entries)
            }
            Some(share) => {
                let mut tree = Self::get_share_tree(session, &share).await?;
                let list = session
                    .client
                    .list_directory(&mut tree, &subpath)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: dir.clone(),
                        source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                    })?;

                let mut entries = Vec::new();
                for item in list {
                    if item.name == "." || item.name == ".." {
                        continue;
                    }
                    let child_path = dir.join(&item.name);
                    entries.push(Entry {
                        name: item.name.clone(),
                        path: child_path,
                        kind: if item.is_directory {
                            EntryKind::Dir
                        } else {
                            EntryKind::File
                        },
                        size: if item.is_directory {
                            None
                        } else {
                            Some(item.size)
                        },
                        modified: item.modified.to_system_time(),
                        mode: None,
                        hidden: item.name.starts_with('.'),
                        mime: None,
                    });
                }

                Ok(entries)
            }
        }
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(path);
        let name = path.name().unwrap_or("").to_string();

        match share_opt {
            None => Ok(Entry {
                name,
                path: path.clone(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                mime: None,
            }),
            Some(share) => {
                if subpath.is_empty() {
                    return Ok(Entry {
                        name,
                        path: path.clone(),
                        kind: EntryKind::Dir,
                        size: None,
                        modified: None,
                        mode: None,
                        hidden: false,
                        mime: None,
                    });
                }

                let mut tree = Self::get_share_tree(session, &share).await?;
                let info = session
                    .client
                    .stat(&mut tree, &subpath)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                    })?;

                Ok(Entry {
                    name,
                    path: path.clone(),
                    kind: if info.is_directory {
                        EntryKind::Dir
                    } else {
                        EntryKind::File
                    },
                    size: if info.is_directory {
                        None
                    } else {
                        Some(info.size)
                    },
                    modified: info.modified.to_system_time(),
                    mode: None,
                    hidden: path.name().map(|n| n.starts_with('.')).unwrap_or(false),
                    mime: None,
                })
            }
        }
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let tree = Self::get_share_tree(session, &share).await?;
        let reader = session
            .client
            .open_file_reader(&tree, &subpath)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
            })?;

        Ok(Self::spawn_range_reader(reader, 0, None))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let tree = Self::get_share_tree(session, &share).await?;
        let reader = session
            .client
            .open_file_reader(&tree, &subpath)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
            })?;
        drop(guard);

        Ok(Self::spawn_range_reader(reader, offset, length))
    }

    async fn open_write(
        &self,
        _path: &VfsPath,
        _mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        Err(VfsError::Unsupported {
            operation: "smb stream write",
        })
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let tree = Self::get_share_tree(session, &share).await?;
        session
            .client
            .create_directory(&tree, &subpath)
            .await
            .map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
            })?;

        Ok(())
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let tree = Self::get_share_tree(session, &share).await?;
        if session.client.delete_file(&tree, &subpath).await.is_err() {
            session
                .client
                .delete_directory(&tree, &subpath)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                })?;
        }

        Ok(())
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let mut guard = self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let session = guard.as_mut().unwrap();

        let (share_from, sub_from) = self.split_path(from);
        let (share_to, sub_to) = self.split_path(to);

        let share = share_from.ok_or_else(|| VfsError::NotFound {
            path: from.clone(),
        })?;

        if Some(&share) != share_to.as_ref() {
            return Err(VfsError::Unsupported {
                operation: "cross-share rename in SMB",
            });
        }

        let tree = Self::get_share_tree(session, &share).await?;
        session
            .client
            .rename(&tree, &sub_from, &sub_to)
            .await
            .map_err(|e| VfsError::Backend {
                path: from.clone(),
                source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
            })?;

        Ok(())
    }
}
