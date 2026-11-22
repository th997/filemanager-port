//! Registry for routing virtual filesystems by location root.

use fm_archive::ArchiveFs;
use fm_core::VfsPath;
use fm_index::Database;
use fm_local::LocalFs;
use fm_remote::RemoteConfig;
use fm_vfs::Vfs;
use parking_lot::{Mutex, RwLock};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use tokio::io::AsyncWriteExt;

pub struct VfsRegistry {
    db_path: RwLock<Option<String>>,
    dbs: Mutex<HashMap<PathBuf, Database>>,
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
            dbs: Mutex::new(HashMap::new()),
            cached: RwLock::new(HashMap::new()),
        }
    }

    pub fn set_database_path(&self, path: String) {
        *self.db_path.write() = Some(path.clone());
        let _ = self.open_database(&path);
    }

    pub fn open_database(&self, db_path: &str) -> Result<Database, String> {
        let key = PathBuf::from(db_path);
        let mut guard = self.dbs.lock();
        if let Some(db) = guard.get(&key) {
            return Ok(db.clone());
        }
        let trash_dir = key.parent().unwrap_or(Path::new(".")).join("trash");
        let db = Database::open(&key, &trash_dir).map_err(|e| e.to_string())?;
        guard.insert(key, db.clone());
        Ok(db)
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
        let db = self.open_database(&db_p)?;
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
        if let Some(vault_id) = root.strip_prefix("vault://") {
            return fm_vault::VaultManager::global()
                .get_vfs(vault_id)
                .map_err(|e| e.to_string());
        }

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
                cache_vfs_archive(remote_vfs.as_ref(), "remote", remote_id, rel_path).await?
            } else if let Some(vault_spec) = archive_path.strip_prefix("vault://") {
                let (vault_id, rel_path) = match vault_spec.find('/') {
                    Some(idx) => (&vault_spec[..idx], &vault_spec[idx + 1..]),
                    None => return Err(format!("invalid vault archive path: {vault_spec}")),
                };
                let vault_vfs = fm_vault::VaultManager::global()
                    .get_vfs(vault_id)
                    .map_err(|e| e.to_string())?;
                cache_vfs_archive(vault_vfs.as_ref(), &format!("vault_{vault_id}"), vault_id, rel_path)
                    .await?
            } else {
                PathBuf::from(archive_path)
            };

            // Opening an archive builds a full entry index (decompresses
            // tar.gz streams); keep that off the tokio worker threads.
            let archive_fs = tokio::task::spawn_blocking(move || ArchiveFs::open(local_path))
                .await
                .map_err(|e| e.to_string())?
                .map_err(|e| e.to_string())?;
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

    pub fn invalidate_vault(&self, vault_id: &str) {
        let vault_root = format!("vault://{vault_id}");
        let archive_prefix = format!("archive://vault://{vault_id}/");
        self.cached.write().retain(|root, _| {
            root != &vault_root
                && !root.starts_with(&archive_prefix)
                && root != &format!("archive://{vault_root}")
        });
        let file_prefix = format!("vault_{vault_id}_");
        let dir = std::env::temp_dir().join("fm_archive_cache");
        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                if entry
                    .file_name()
                    .to_str()
                    .map(|n| n.starts_with(&file_prefix))
                    .unwrap_or(false)
                {
                    let _ = std::fs::remove_file(entry.path());
                }
            }
        }
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

    pub fn clear_all_vault_archive_caches(&self) {
        self.cached
            .write()
            .retain(|root, _| !root.starts_with("archive://vault://"));
        let dir = std::env::temp_dir().join("fm_archive_cache");
        if let Ok(entries) = std::fs::read_dir(&dir) {
            for entry in entries.flatten() {
                if entry
                    .file_name()
                    .to_str()
                    .map(|n| n.starts_with("vault_"))
                    .unwrap_or(false)
                {
                    let _ = std::fs::remove_file(entry.path());
                }
            }
        }
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
    let Ok(db) = VfsRegistry::global().open_database(db_path) else {
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

async fn cache_vfs_archive(
    vfs: &dyn Vfs,
    file_prefix: &str,
    scope_id: &str,
    rel_path: &str,
) -> Result<PathBuf, String> {
    let vfs_path = VfsPath::from_slash_path(rel_path);
    let cache_dir = std::env::temp_dir().join("fm_archive_cache");
    tokio::fs::create_dir_all(&cache_dir)
        .await
        .map_err(|e| e.to_string())?;

    let file_name = Path::new(rel_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("archive.zip");
    let lower_name = file_name.to_ascii_lowercase();
    let ext = if lower_name.ends_with(".tar.gz") {
        ".tar.gz"
    } else if lower_name.ends_with(".tgz") {
        ".tgz"
    } else if lower_name.ends_with(".tar") {
        ".tar"
    } else if lower_name.ends_with(".7z") {
        ".7z"
    } else if lower_name.ends_with(".epub") {
        ".epub"
    } else {
        ".zip"
    };

    let mut h1: u64 = 0xcbf29ce484222325;
    let mut h2: u64 = 0x84222325cbf29ce4;
    for &b in scope_id
        .as_bytes()
        .iter()
        .chain(std::iter::once(&0u8))
        .chain(rel_path.as_bytes().iter())
    {
        h1 ^= b as u64;
        h1 = h1.wrapping_mul(0x100000001b3);
        h2 = h2.wrapping_mul(0x100000001b3);
        h2 ^= b as u64;
    }
    let safe_prefix: String = file_prefix
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
        .collect();
    let safe_name = if safe_prefix.is_empty() || safe_prefix == "remote" {
        format!("{h1:016x}{h2:016x}{ext}")
    } else {
        format!("{safe_prefix}_{h1:016x}{h2:016x}{ext}")
    };
    let cached_file = cache_dir.join(safe_name);

    let stat = vfs.stat(&vfs_path).await;
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
        let temp_download = cache_dir.join(format!("{}.tmp", uuid::Uuid::new_v4()));
        let download_res: Result<(), String> = async {
            let mut reader = vfs.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
            let mut out_file = tokio::fs::File::create(&temp_download)
                .await
                .map_err(|e| e.to_string())?;
            tokio::io::copy(&mut reader, &mut out_file)
                .await
                .map_err(|e| e.to_string())?;
            out_file.flush().await.map_err(|e| e.to_string())?;
            drop(out_file);
            if let Err(err) = tokio::fs::rename(&temp_download, &cached_file).await {
                if cached_file.exists() {
                    let _ = tokio::fs::remove_file(&cached_file).await;
                    tokio::fs::rename(&temp_download, &cached_file)
                        .await
                        .map_err(|e| e.to_string())?;
                } else {
                    return Err(err.to_string());
                }
            }
            Ok(())
        }
        .await;
        if let Err(e) = download_res {
            let _ = tokio::fs::remove_file(&temp_download).await;
            return Err(e);
        }
    }

    Ok(cached_file)
}

#[cfg(test)]
mod tests {
    use super::*;
    use fm_core::{LocationId, VfsPath};
    use fm_index::Bookmark;
    use std::sync::Barrier;

    #[test]
    fn open_database_reuses_shared_instance_under_concurrency() {
        let dir = std::env::temp_dir().join(format!("fm-ffi-reg-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("filemanager.db").to_string_lossy().into_owned();
        let registry = Arc::new(VfsRegistry::new());
        let threads = 12;
        let barrier = Arc::new(Barrier::new(threads));

        let mut handles = Vec::with_capacity(threads);
        for i in 0..threads {
            let reg = registry.clone();
            let path = db_path.clone();
            let b = barrier.clone();
            handles.push(std::thread::spawn(move || {
                b.wait();
                let db = reg.open_database(&path).unwrap();
                db.add_bookmark(&Bookmark {
                    location: LocationId(format!("loc-{i}")),
                    path: VfsPath::from_slash_path("/shared"),
                    display_name: format!("Bookmark {i}"),
                })
                .unwrap();
                let _ = db.list_remotes().unwrap();
                let _ = db.list_bookmarks().unwrap();
                let _ = db.list_history(50).unwrap();
                let _ = db.list_trash().unwrap();
            }));
        }

        for h in handles {
            h.join().unwrap();
        }

        let db = registry.open_database(&db_path).unwrap();
        assert_eq!(db.list_bookmarks().unwrap().len(), threads);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
