//! Registry for routing virtual filesystems by location root.

use fm_archive::ArchiveFs;
use fm_index::Database;
use fm_local::LocalFs;
use fm_remote::RemoteConfig;
use fm_vfs::Vfs;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};

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

    pub fn get_or_create(&self, root: &str) -> Result<Arc<dyn Vfs>, String> {
        if let Some(vfs) = self.cached.read().get(root) {
            return Ok(vfs.clone());
        }

        let vfs: Arc<dyn Vfs> = if let Some(archive_path) = root.strip_prefix("archive://") {
            let path = PathBuf::from(archive_path);
            let archive_fs = ArchiveFs::open(path).map_err(|e| e.to_string())?;
            Arc::new(archive_fs)
        } else if let Some(remote_id) = root.strip_prefix("remote://") {
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
            let boxed_vfs = config.create_vfs().map_err(|e| e.to_string())?;
            Arc::from(boxed_vfs)
        } else {
            Arc::new(LocalFs::new(root))
        };

        self.cached.write().insert(root.to_string(), vfs.clone());
        Ok(vfs)
    }

    pub fn invalidate(&self, root: &str) {
        self.cached.write().remove(root);
    }
}
