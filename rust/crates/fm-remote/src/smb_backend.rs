//! Pure-Rust SMB2/3 backend using smb2 crate.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use smb2::client::stream::FileReader;
use smb2::client::{ClientConfig, SmbClient, Tree};
use std::collections::HashMap;
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite};
use tokio::sync::Mutex;

use crate::pipe_writer::{pipe_writer, signaling_reader};
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
        let root_trimmed = self.config.root.trim_matches('/');
        let root_parts: Vec<&str> = if root_trimmed.is_empty() {
            Vec::new()
        } else {
            root_trimmed.split('/').filter(|s| !s.is_empty()).collect()
        };

        let path_segments = path.segments();

        if let Some((&share, prefix_parts)) = root_parts.split_first() {
            // Root config specifies a share (and optional subfolder)
            let mut sub_parts: Vec<&str> = prefix_parts.to_vec();
            for seg in path_segments {
                sub_parts.push(seg.as_str());
            }
            (Some(share.to_string()), sub_parts.join("/"))
        } else {
            // Root config is empty / "/": top-level represents share list
            if let Some((share, rel_parts)) = path_segments.split_first() {
                (Some(share.clone()), rel_parts.join("/"))
            } else {
                (None, String::new())
            }
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

        // The signaling reader turns a mid-transfer read failure into a
        // read error on the caller's side; the old loop broke on any error
        // and shut the pipe down cleanly, so a truncated download looked
        // exactly like a complete one.
        signaling_reader(move |mut writer| async move {
            let mut pos = offset;
            let mut left = remaining;
            let mut failure: Option<String> = None;
            while left > 0 {
                let want = left.min(256 * 1024);
                match reader.read_at(pos, want).await {
                    Ok(chunk) if !chunk.is_empty() => {
                        if writer.write_all(&chunk).await.is_err() {
                            // Reader went away; not a transfer failure.
                            break;
                        }
                        let n = chunk.len() as u64;
                        pos += n;
                        left -= n;
                    }
                    Ok(_) => break, // empty chunk: end of file
                    Err(e) => {
                        failure = Some(format!("SMB read failed mid-transfer: {e}"));
                        break;
                    }
                }
            }
            let _ = reader.close().await;
            let _ = writer.shutdown().await;
            match failure {
                Some(msg) => Err(msg),
                None => Ok(()),
            }
        })
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

/// Whether an error indicates the cached SMB session or TCP transport died
/// and an auto-reconnect should be attempted.
fn is_closed_error(error: &VfsError) -> bool {
    match error {
        VfsError::Connection { .. } => true,
        VfsError::Backend { source, .. } => {
            let text = source.to_string().to_lowercase();
            text.contains("session closed")
                || text.contains("connection reset")
                || text.contains("broken pipe")
                || text.contains("not connected")
                || text.contains("connection closed")
                || text.contains("transport endpoint")
                || text.contains("eof")
                || text.contains("timed out")
                || text.contains("timeout")
        }
        _ => false,
    }
}

macro_rules! run_smb {
    ($self:expr, $session:ident => $body:expr) => {{
        let mut guard = $self.session.lock().await;
        if guard.is_none() {
            let client = Self::connect_client(&$self.config).await?;
            *guard = Some(SmbSession {
                client,
                trees: HashMap::new(),
            });
        }
        let res = {
            let $session = guard.as_mut().unwrap();
            $body.await
        };
        match res {
            Err(ref err) if is_closed_error(err) => {
                *guard = None;
                let client = Self::connect_client(&$self.config).await?;
                *guard = Some(SmbSession {
                    client,
                    trees: HashMap::new(),
                });
                let $session = guard.as_mut().unwrap();
                $body.await
            }
            other => other,
        }
    }};
}

#[async_trait]
impl Vfs for SmbFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let (share_opt, subpath) = self.split_path(dir);

        run_smb!(self, session => async {
            match &share_opt {
                None => {
                    // List root shares
                    let shares = session
                        .client
                        .list_shares()
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: dir.clone(),
                            source: std::io::Error::other(e.to_string()),
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
                            is_symlink: false,
                            mime: None,
                        })
                        .collect();

                    Ok(entries)
                }
                Some(share) => {
                    let mut tree = Self::get_share_tree(session, share).await?;
                    let list = session
                        .client
                        .list_directory(&mut tree, &subpath)
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: dir.clone(),
                            source: std::io::Error::other(e.to_string()),
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
                            is_symlink: false,
                            mime: None,
                        });
                    }

                    Ok(entries)
                }
            }
        })
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
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
                is_symlink: false,
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
                        is_symlink: false,
                        mime: None,
                    });
                }

                run_smb!(self, session => async {
                    let mut tree = Self::get_share_tree(session, &share).await?;
                    let info = session
                        .client
                        .stat(&mut tree, &subpath)
                        .await
                        .map_err(|e| VfsError::Backend {
                            path: path.clone(),
                            source: std::io::Error::other(e.to_string()),
                        })?;

                    Ok(Entry {
                        name: name.clone(),
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
                        is_symlink: false,
                        mime: None,
                    })
                })
            }
        }
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let reader = run_smb!(self, session => async {
            let tree = Self::get_share_tree(session, &share).await?;
            session
                .client
                .open_file_reader(&tree, &subpath)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
        })?;

        Ok(Self::spawn_range_reader(reader, 0, None))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let reader = run_smb!(self, session => async {
            let tree = Self::get_share_tree(session, &share).await?;
            session
                .client
                .open_file_reader(&tree, &subpath)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
        })?;

        Ok(Self::spawn_range_reader(reader, offset, length))
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        if !self.capabilities.write {
            return Err(VfsError::Unsupported { operation: "write" });
        }

        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        let mut writer = run_smb!(self, session => async {
            let mut tree = Self::get_share_tree(session, &share).await?;

            let writer_res = match mode {
                WriteMode::Create => {
                    session
                        .client
                        .create_file_writer_exclusive(&tree, &subpath)
                        .await
                }
                WriteMode::Append => {
                    let offset = match session.client.stat(&mut tree, &subpath).await {
                        Ok(s) => s.size,
                        Err(e) if e.kind() == smb2::ErrorKind::NotFound => 0,
                        Err(e) => {
                            return Err(VfsError::Backend {
                                path: path.clone(),
                                source: std::io::Error::other(e.to_string()),
                            })
                        }
                    };
                    session
                        .client
                        .create_file_writer_at(&tree, &subpath, offset)
                        .await
                }
                WriteMode::Truncate => {
                    session
                        .client
                        .create_file_writer(&tree, &subpath)
                        .await
                }
            };

            writer_res.map_err(|e| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(e.to_string()),
            })
        })?;

        Ok(pipe_writer(move |mut rx| async move {
            let mut buf = vec![0u8; 64 * 1024];
            loop {
                match rx.read(&mut buf).await {
                    Ok(0) => break,
                    Ok(n) => {
                        if let Err(e) = writer.write_chunk(&buf[..n]).await {
                            let _ = writer.abort().await;
                            return Err(e.to_string());
                        }
                    }
                    Err(e) => {
                        let _ = writer.abort().await;
                        return Err(e.to_string());
                    }
                }
            }
            writer.finish().await.map_err(|e| e.to_string())?;
            Ok(())
        }))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        run_smb!(self, session => async {
            let tree = Self::get_share_tree(session, &share).await?;
            session
                .client
                .create_directory(&tree, &subpath)
                .await
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
        })
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let (share_opt, subpath) = self.split_path(path);
        let share = share_opt.ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;

        run_smb!(self, session => async {
            let tree = Self::get_share_tree(session, &share).await?;
            if session.client.delete_file(&tree, &subpath).await.is_err() {
                session
                    .client
                    .delete_directory(&tree, &subpath)
                    .await
                    .map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: std::io::Error::other(e.to_string()),
                    })?;
            }
            Ok(())
        })
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
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

        run_smb!(self, session => async {
            let tree = Self::get_share_tree(session, &share).await?;
            session
                .client
                .rename(&tree, &sub_from, &sub_to)
                .await
                .map_err(|e| VfsError::Backend {
                    path: from.clone(),
                    source: std::io::Error::other(e.to_string()),
                })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fm_core::LocationKind;

    fn make_fs(root: &str) -> SmbFs {
        SmbFs::new(&RemoteConfig {
            id: "test".into(),
            kind: LocationKind::Smb,
            display_name: "Test".into(),
            endpoint: None,
            region: None,
            bucket: None,
            host: Some("127.0.0.1".into()),
            port: None,
            root: root.into(),
            username: None,
            password: None,
            key_id: None,
            key_secret: None,
            private_key: None,
            path_style: false,
            host_key_fingerprint: None,
        })
    }

    #[test]
    fn split_path_default_root() {
        let fs = make_fs("/");
        assert_eq!(fs.split_path(&VfsPath::root()), (None, "".to_string()));
        assert_eq!(
            fs.split_path(&VfsPath::from_slash_path("/share1")),
            (Some("share1".to_string()), "".to_string())
        );
        assert_eq!(
            fs.split_path(&VfsPath::from_slash_path("/share1/dir/file.txt")),
            (Some("share1".to_string()), "dir/file.txt".to_string())
        );
    }

    #[test]
    fn split_path_with_share_root() {
        let fs = make_fs("/my_share");
        assert_eq!(
            fs.split_path(&VfsPath::root()),
            (Some("my_share".to_string()), "".to_string())
        );
        assert_eq!(
            fs.split_path(&VfsPath::from_slash_path("/dir/file.txt")),
            (Some("my_share".to_string()), "dir/file.txt".to_string())
        );
    }

    #[test]
    fn split_path_with_subfolder_root() {
        let fs = make_fs("/my_share/sub");
        assert_eq!(
            fs.split_path(&VfsPath::root()),
            (Some("my_share".to_string()), "sub".to_string())
        );
        assert_eq!(
            fs.split_path(&VfsPath::from_slash_path("/dir/file.txt")),
            (Some("my_share".to_string()), "sub/dir/file.txt".to_string())
        );
    }
}
