//! Registry for routing virtual filesystems by location root.

use fm_archive::ArchiveFs;
use fm_core::VfsPath;
use fm_index::Database;
use fm_local::LocalFs;
use fm_remote::RemoteConfig;
use fm_vfs::Vfs;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use tokio::io::AsyncWriteExt;

pub struct VfsRegistry {
    db_path: RwLock<Option<String>>,
    cached: RwLock<HashMap<String, Arc<dyn Vfs>>>,
}

static INSTANCE: OnceLock<VfsRegistry> = OnceLock::new();

impl Default for VfsRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl VfsRegistry {
    pub fn global() -> &'static Self {
        INSTANCE.get_or_init(Self::new)
    }

    pub fn new() -> Self {
        Self {
            db_path: RwLock::new(None),
            cached: RwLock::new(HashMap::new()),
        }
    }

    pub fn set_database_path(&self, path: String) {
        *self.db_path.write() = Some(path);
    }

    pub fn get_database_path(&self) -> Option<String> {
        self.db_path.read().clone()
    }

    pub fn get_remote_vfs(&self, remote_id: &str) -> Result<Arc<dyn Vfs>, String> {
        let db_p = self
            .db_path
            .read()
            .clone()
            .ok_or_else(|| "database path not set for remote resolution".to_string())?;
        let db = Database::open(
            Path::new(&db_p),
            Path::new(&db_p).parent().unwrap_or(Path::new(".")),
        )
        .map_err(|e| e.to_string())?;
        let remotes = db.list_remotes().map_err(|e| e.to_string())?;
        let record = remotes
            .into_iter()
            .find(|r| r.id == remote_id)
            .ok_or_else(|| format!("remote id {remote_id} not found"))?;

        let config: RemoteConfig =
            serde_json::from_str(&record.config_json).map_err(|e| e.to_string())?;

        if config.kind == fm_core::LocationKind::Sftp && config.host_key_fingerprint.is_none() {
            // Trust on first use, persisted: connect once in the
            // background and write the observed host key fingerprint
            // into the saved config, so future launches verify the key
            // from the first packet (and this session's reconnects are
            // already pinned by the backend itself).
            let fs = Arc::new(fm_remote::SftpFs::new(&config));
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                let fs_clone = fs.clone();
                let db_path = db_p.clone();
                let remote_id = record.id.clone();
                handle.spawn(async move {
                    if fs_clone.list(&VfsPath::root()).await.is_ok() {
                        if let Some(fingerprint) = fs_clone.observed_host_key_fingerprint() {
                            pin_host_key(&db_path, &remote_id, &fingerprint);
                        }
                    }
                });
            }
            return Ok(fs as Arc<dyn Vfs>);
        }

        let boxed_vfs = config.create_vfs().map_err(|e| e.to_string())?;
        Ok(Arc::from(boxed_vfs))
    }

    pub async fn get_or_create(&self, root: &str) -> Result<Arc<dyn Vfs>, String> {
        if let Some(vfs) = self.cached.read().get(root) {
            return Ok(vfs.clone());
        }

        let vfs: Arc<dyn Vfs> = if let Some(archive_path) = root.strip_prefix("archive://") {
            let local_path = if let Some(remote_spec) = archive_path.strip_prefix("remote://") {
                let (remote_id, rel_path) = match remote_spec.find('/') {
                    Some(idx) => (&remote_spec[..idx], &remote_spec[idx + 1..]),
                    None => return Err(format!("invalid remote archive path: {remote_spec}")),
                };
                let remote_vfs = self.get_remote_vfs(remote_id)?;
                let vfs_path = VfsPath::from_slash_path(rel_path);

                let cache_dir = std::env::temp_dir().join("fm_archive_cache");
                tokio::fs::create_dir_all(&cache_dir)
                    .await
                    .map_err(|e| e.to_string())?;

                let file_name = Path::new(rel_path)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("archive.zip");
                let safe_name = format!("{}_{}_{}", remote_id, hex::encode(rel_path.as_bytes()), file_name);
                let cached_file = cache_dir.join(safe_name);

                let stat = remote_vfs.stat(&vfs_path).await;
                let need_download = match &stat {
                    Ok(entry) => {
                        if cached_file.exists() {
                            if let Ok(meta) = tokio::fs::metadata(&cached_file).await {
                                entry.size.map(|s| s != meta.len()).unwrap_or(false)
                            } else {
                                true
                            }
                        } else {
                            true
                        }
                    }
                    Err(_) => !cached_file.exists(),
                };

                if need_download {
                    let mut reader = remote_vfs.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
                    let temp_download = cache_dir.join(format!("{}.tmp", uuid::Uuid::new_v4()));
                    let mut out_file = tokio::fs::File::create(&temp_download).await.map_err(|e| e.to_string())?;
                    tokio::io::copy(&mut reader, &mut out_file).await.map_err(|e| e.to_string())?;
                    out_file.flush().await.map_err(|e| e.to_string())?;
                    drop(out_file);
                    tokio::fs::rename(&temp_download, &cached_file).await.map_err(|e| e.to_string())?;
                }

                cached_file
            } else {
                PathBuf::from(archive_path)
            };

            let archive_fs = ArchiveFs::open(local_path).map_err(|e| e.to_string())?;
            Arc::new(archive_fs)
        } else if let Some(remote_id) = root.strip_prefix("remote://") {
            self.get_remote_vfs(remote_id)?
        } else {
            Arc::new(LocalFs::new(root))
        };

        self.cached.write().insert(root.to_string(), vfs.clone());
        Ok(vfs)
    }

    pub fn invalidate(&self, root: &str) {
        self.cached.write().remove(root);
    }

    /// Bytes held by the downloaded remote-archive cache
    /// (`temp_dir/fm_archive_cache`). A missing directory counts as zero.
    pub fn archive_cache_size(&self) -> u64 {
        let dir = std::env::temp_dir().join("fm_archive_cache");
        let mut total = 0u64;
        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                if let Ok(meta) = entry.metadata() {
                    if meta.is_file() {
                        total += meta.len();
                    }
                }
            }
        }
        total
    }

    /// Deletes every cached remote archive and drops cached archive VFS
    /// instances, so the next open re-downloads instead of reading a
    /// path that no longer exists.
    pub fn clear_archive_cache(&self) {
        self.cached
            .write()
            .retain(|root, _| !root.starts_with("archive://"));
        let dir = std::env::temp_dir().join("fm_archive_cache");
        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }
}

/// Store a first-seen SFTP host key fingerprint in the remote's saved
/// config. Best-effort: any failure (db gone, record gone, a pin already
/// stored) leaves the config untouched.
fn pin_host_key(db_path: &str, remote_id: &str, fingerprint: &str) {
    let parent = Path::new(db_path).parent().unwrap_or(Path::new("."));
    let Ok(db) = Database::open(Path::new(db_path), parent) else {
        return;
    };
    let Ok(records) = db.list_remotes() else {
        return;
    };
    let Some(record) = records.into_iter().find(|r| r.id == remote_id) else {
        return;
    };
    let Ok(mut cfg) = serde_json::from_str::<RemoteConfig>(&record.config_json) else {
        return;
    };
    if cfg.host_key_fingerprint.is_some() {
        return;
    }
    cfg.host_key_fingerprint = Some(fingerprint.to_string());
    let Ok(json) = serde_json::to_string(&cfg) else {
        return;
    };
    let updated = fm_index::RemoteRecord {
        config_json: json,
        ..record
    };
    let _ = db.save_remote(&updated);
}
