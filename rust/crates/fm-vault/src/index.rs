use crate::crypto::{decrypt_blob, encrypt_blob, VaultCipher};
use crate::error::{VaultError, VaultResult};
use crate::meta::{atomic_write_bytes, now_millis, VaultMeta};
use fm_core::{Entry, EntryKind, VfsPath};
use fm_vfs::{VfsError, VfsResult};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};

pub const INDEX_ENC_FILE: &str = "index.enc";
pub const INDEX_JSON_FILE: &str = "index.json";
pub const DIRS_DIR: &str = "dirs";
pub const DIR_CACHE_CAPACITY: usize = 256;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultNode {
    pub segments: Vec<String>,
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_ms: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub obj_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thumb_id: Option<String>,
}

impl VaultNode {
    pub fn to_entry(&self) -> Entry {
        let modified = if self.modified_ms >= 0 {
            Some(UNIX_EPOCH + Duration::from_millis(self.modified_ms as u64))
        } else {
            None
        };
        Entry {
            name: self.name.clone(),
            path: VfsPath::new(self.segments.iter().cloned()),
            kind: if self.is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            },
            size: if self.is_dir { None } else { Some(self.size) },
            modified,
            mode: None,
            hidden: self.name.starts_with('.'),
            is_symlink: false,
            mime: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultIndex {
    pub version: u32,
    pub nodes: BTreeMap<String, VaultNode>,
}

impl Default for VaultIndex {
    fn default() -> Self {
        Self {
            version: 1,
            nodes: BTreeMap::new(),
        }
    }
}

pub fn index_file_path(vault_dir: &Path, cipher: VaultCipher) -> PathBuf {
    if cipher.is_encrypted() {
        vault_dir.join(INDEX_ENC_FILE)
    } else {
        vault_dir.join(INDEX_JSON_FILE)
    }
}

fn validate_segments(path: &VfsPath) -> VfsResult<()> {
    if path.has_traversal_segment() {
        return Err(VfsError::PermissionDenied { path: path.clone() });
    }
    for seg in path.segments() {
        if seg.is_empty() || seg.contains('/') || seg.contains('\0') {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
    }
    Ok(())
}

fn path_key(path: &VfsPath) -> String {
    serde_json::to_string(path.segments()).unwrap_or_else(|_| path.to_slash_string())
}

fn index_aad(vault_id: &str) -> Vec<u8> {
    format!("fm-vault-index-v1:{vault_id}").into_bytes()
}

impl VaultIndex {
    pub fn load(vault_dir: &Path, vault_id: &str, cipher: VaultCipher, dek: &[u8; 32]) -> VaultResult<Self> {
        let p = index_file_path(vault_dir, cipher);
        let raw = std::fs::read(&p)?;
        let plain = if cipher.is_encrypted() {
            decrypt_blob(dek, cipher, &index_aad(vault_id), &raw)?
        } else {
            raw
        };
        Ok(serde_json::from_slice(&plain)?)
    }

    pub fn save(&self, vault_dir: &Path, vault_id: &str, cipher: VaultCipher, dek: &[u8; 32]) -> VaultResult<()> {
        let plain = serde_json::to_vec(self)?;
        let bytes = if cipher.is_encrypted() {
            encrypt_blob(dek, cipher, &index_aad(vault_id), &plain)?
        } else {
            plain
        };
        atomic_write_bytes(&index_file_path(vault_dir, cipher), &bytes)
    }

    pub fn ensure_parent_dir(&self, path: &VfsPath) -> VfsResult<()> {
        validate_segments(path)?;
        let Some(parent) = path.parent() else {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        };
        if parent.is_root() {
            return Ok(());
        }
        let key = path_key(&parent);
        match self.nodes.get(&key) {
            Some(node) if node.is_dir => Ok(()),
            Some(_) => Err(VfsError::PermissionDenied { path: path.clone() }),
            None => Err(VfsError::NotFound { path: parent }),
        }
    }

    pub fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        validate_segments(path)?;
        if path.is_root() {
            return Ok(Entry {
                name: String::new(),
                path: VfsPath::root(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                is_symlink: false,
                mime: None,
            });
        }
        self.nodes
            .get(&path_key(path))
            .map(VaultNode::to_entry)
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })
    }

    pub fn get_node(&self, path: &VfsPath) -> Option<&VaultNode> {
        self.nodes.get(&path_key(path))
    }

    pub fn get_node_mut(&mut self, path: &VfsPath) -> Option<&mut VaultNode> {
        self.nodes.get_mut(&path_key(path))
    }

    pub fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        validate_segments(dir)?;
        if !dir.is_root() {
            match self.nodes.get(&path_key(dir)) {
                Some(n) if n.is_dir => {}
                Some(_) => return Err(VfsError::PermissionDenied { path: dir.clone() }),
                None => return Err(VfsError::NotFound { path: dir.clone() }),
            }
        }
        let target_segs = dir.segments();
        let target_depth = target_segs.len();
        let entries = self
            .nodes
            .values()
            .filter(|n| {
                n.segments.len() == target_depth + 1
                    && &n.segments[..target_depth] == target_segs
            })
            .map(VaultNode::to_entry)
            .collect();
        Ok(entries)
    }

    pub fn mkdir(&mut self, path: &VfsPath) -> VfsResult<()> {
        validate_segments(path)?;
        if path.is_root() {
            return Ok(());
        }
        self.ensure_parent_dir(path)?;
        let key = path_key(path);
        if self.nodes.contains_key(&key) {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(
                    std::io::ErrorKind::AlreadyExists,
                    "directory already exists",
                ),
            });
        }
        let name = path
            .name()
            .ok_or_else(|| VfsError::PermissionDenied { path: path.clone() })?
            .to_string();
        self.nodes.insert(
            key,
            VaultNode {
                segments: path.segments().to_vec(),
                name,
                is_dir: true,
                size: 0,
                modified_ms: now_millis(),
                obj_id: None,
                thumb_id: None,
            },
        );
        Ok(())
    }

    /// Upserts a file node and returns `(old_obj_id, old_thumb_id)` if replaced.
    pub fn upsert_file(
        &mut self,
        path: &VfsPath,
        obj_id: String,
        size: u64,
    ) -> VfsResult<(Option<String>, Option<String>)> {
        validate_segments(path)?;
        self.ensure_parent_dir(path)?;
        let key = path_key(path);
        if let Some(existing) = self.nodes.get(&key) {
            if existing.is_dir {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "destination is a directory",
                    ),
                });
            }
        }
        let name = path
            .name()
            .ok_or_else(|| VfsError::PermissionDenied { path: path.clone() })?
            .to_string();
        let prev = self.nodes.insert(
            key,
            VaultNode {
                segments: path.segments().to_vec(),
                name,
                is_dir: false,
                size,
                modified_ms: now_millis(),
                obj_id: Some(obj_id),
                thumb_id: None,
            },
        );
        Ok(match prev {
            Some(old) => (old.obj_id, old.thumb_id),
            None => (None, None),
        })
    }

    /// Removes a file or directory tree, returning orphaned `(obj_ids, thumb_ids)`.
    pub fn remove(&mut self, path: &VfsPath) -> VfsResult<(Vec<String>, Vec<String>)> {
        validate_segments(path)?;
        if path.is_root() {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        let target_key = path_key(path);
        if !self.nodes.contains_key(&target_key) {
            return Err(VfsError::NotFound { path: path.clone() });
        }

        let keys_to_remove: Vec<String> = self
            .nodes
            .iter()
            .filter(|(_, node)| {
                let np = VfsPath::new(node.segments.iter().cloned());
                np.starts_with(path)
            })
            .map(|(k, _)| k.clone())
            .collect();

        let mut obj_ids = Vec::new();
        let mut thumb_ids = Vec::new();
        for k in keys_to_remove {
            if let Some(node) = self.nodes.remove(&k) {
                if let Some(id) = node.obj_id {
                    obj_ids.push(id);
                }
                if let Some(tid) = node.thumb_id {
                    thumb_ids.push(tid);
                }
            }
        }
        Ok((obj_ids, thumb_ids))
    }

    /// Renames or moves a file or directory tree.
    /// If overwriting an existing file at `to`, returns its `(old_obj_id, old_thumb_id)`.
    pub fn rename(
        &mut self,
        from: &VfsPath,
        to: &VfsPath,
    ) -> VfsResult<(Option<String>, Option<String>)> {
        validate_segments(from)?;
        validate_segments(to)?;
        if from.is_root() || to.is_root() {
            return Err(VfsError::PermissionDenied { path: from.clone() });
        }
        if from == to {
            return Ok((None, None));
        }
        let from_key = path_key(from);
        let src_is_dir = self
            .nodes
            .get(&from_key)
            .ok_or_else(|| VfsError::NotFound { path: from.clone() })?
            .is_dir;

        if src_is_dir && to.starts_with(from) {
            return Err(VfsError::PermissionDenied { path: to.clone() });
        }
        self.ensure_parent_dir(to)?;

        let to_key = path_key(to);
        let mut replaced = (None, None);
        if let Some(existing) = self.nodes.get(&to_key) {
            if existing.is_dir || src_is_dir {
                return Err(VfsError::Backend {
                    path: to.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "destination already exists",
                    ),
                });
            }
            if let Some(old) = self.nodes.remove(&to_key) {
                replaced = (old.obj_id, old.thumb_id);
            }
        }

        let to_segs = to.segments().to_vec();
        let from_len = from.segments().len();
        let keys_to_move: Vec<String> = self
            .nodes
            .iter()
            .filter(|(_, node)| {
                let np = VfsPath::new(node.segments.iter().cloned());
                np.starts_with(from)
            })
            .map(|(k, _)| k.clone())
            .collect();

        let mut moved = Vec::with_capacity(keys_to_move.len());
        for k in keys_to_move {
            if let Some(mut node) = self.nodes.remove(&k) {
                let mut new_segs = to_segs.clone();
                new_segs.extend_from_slice(&node.segments[from_len..]);
                node.name = new_segs
                    .last()
                    .cloned()
                    .ok_or_else(|| VfsError::PermissionDenied { path: to.clone() })?;
                node.segments = new_segs;
                if node.segments == to_segs {
                    node.modified_ms = now_millis();
                }
                let new_key = path_key(&VfsPath::new(node.segments.iter().cloned()));
                moved.push((new_key, node));
            }
        }
        for (new_key, node) in moved {
            self.nodes.insert(new_key, node);
        }
        Ok(replaced)
    }

    pub fn set_thumb_id(&mut self, path: &VfsPath, thumb_id: String) -> VaultResult<Option<String>> {
        let key = path_key(path);
        let node = self
            .nodes
            .get_mut(&key)
            .ok_or_else(|| VaultError::NotFound(path.to_slash_string()))?;
        if node.is_dir {
            return Err(VaultError::Unsupported("directories have no thumbnail".to_string()));
        }
        let old = node.thumb_id.replace(thumb_id);
        Ok(old)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirChild {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_ms: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dir_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub obj_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thumb_id: Option<String>,
}

impl DirChild {
    pub fn to_entry(&self, path: VfsPath) -> Entry {
        let modified = if self.modified_ms >= 0 {
            Some(UNIX_EPOCH + Duration::from_millis(self.modified_ms as u64))
        } else {
            None
        };
        Entry {
            name: self.name.clone(),
            path,
            kind: if self.is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            },
            size: if self.is_dir { None } else { Some(self.size) },
            modified,
            mode: None,
            hidden: self.name.starts_with('.'),
            is_symlink: false,
            mime: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultDirFile {
    pub version: u32,
    pub children: BTreeMap<String, DirChild>,
}

impl Default for VaultDirFile {
    fn default() -> Self {
        Self {
            version: 2,
            children: BTreeMap::new(),
        }
    }
}

pub fn dir_file_path(vault_dir: &Path, dir_id: &str, cipher: VaultCipher) -> PathBuf {
    let ext = if cipher.is_encrypted() { "enc" } else { "json" };
    let base = vault_dir.join(DIRS_DIR);
    match crate::vfs::shard_prefix(dir_id) {
        Some(prefix) => base.join(prefix).join(format!("{dir_id}.{ext}")),
        None => base.join(format!("{dir_id}.{ext}")),
    }
}

fn dir_aad(vault_id: &str, dir_id: &str) -> Vec<u8> {
    format!("fm-vault-dir-v2:{vault_id}:{dir_id}").into_bytes()
}

impl VaultDirFile {
    pub fn load(
        vault_dir: &Path,
        vault_id: &str,
        dir_id: &str,
        cipher: VaultCipher,
        dek: &[u8; 32],
    ) -> VaultResult<Self> {
        let p = dir_file_path(vault_dir, dir_id, cipher);
        let raw = std::fs::read(&p)?;
        let plain = if cipher.is_encrypted() {
            decrypt_blob(dek, cipher, &dir_aad(vault_id, dir_id), &raw)?
        } else {
            raw
        };
        Ok(serde_json::from_slice(&plain)?)
    }

    pub fn save(
        &self,
        vault_dir: &Path,
        vault_id: &str,
        dir_id: &str,
        cipher: VaultCipher,
        dek: &[u8; 32],
    ) -> VaultResult<()> {
        let p = dir_file_path(vault_dir, dir_id, cipher);
        if let Some(parent) = p.parent() {
            crate::vfs::ensure_private_bucket_dir(parent)?;
        }
        let plain = serde_json::to_vec(self)?;
        let bytes = if cipher.is_encrypted() {
            encrypt_blob(dek, cipher, &dir_aad(vault_id, dir_id), &plain)?
        } else {
            plain
        };
        atomic_write_bytes(&p, &bytes)
    }
}

pub struct DirIndexCache {
    vault_dir: PathBuf,
    vault_id: String,
    root_dir_id: String,
    cipher: VaultCipher,
    cache: HashMap<String, VaultDirFile>,
    lru: VecDeque<String>,
}

impl DirIndexCache {
    pub fn new(
        vault_dir: PathBuf,
        vault_id: String,
        root_dir_id: String,
        cipher: VaultCipher,
    ) -> Self {
        Self {
            vault_dir,
            vault_id,
            root_dir_id,
            cipher,
            cache: HashMap::new(),
            lru: VecDeque::new(),
        }
    }

    pub fn clear(&mut self) {
        self.cache.clear();
        self.lru.clear();
    }

    fn touch_lru(&mut self, dir_id: &str) {
        if let Some(pos) = self.lru.iter().position(|id| id == dir_id) {
            self.lru.remove(pos);
        }
        self.lru.push_back(dir_id.to_string());
        while self.cache.len() > DIR_CACHE_CAPACITY {
            if let Some(evict_id) = self.lru.pop_front() {
                self.cache.remove(&evict_id);
            } else {
                break;
            }
        }
    }

    fn put_cached(&mut self, dir_id: String, df: VaultDirFile) {
        self.cache.insert(dir_id.clone(), df);
        self.touch_lru(&dir_id);
    }

    fn evict_id(&mut self, dir_id: &str) {
        self.cache.remove(dir_id);
        if let Some(pos) = self.lru.iter().position(|id| id == dir_id) {
            self.lru.remove(pos);
        }
    }

    pub fn load_dir(&mut self, dir_id: &str, dek: &[u8; 32]) -> VaultResult<VaultDirFile> {
        if let Some(cached) = self.cache.get(dir_id).cloned() {
            self.touch_lru(dir_id);
            return Ok(cached);
        }
        let loaded = VaultDirFile::load(&self.vault_dir, &self.vault_id, dir_id, self.cipher, dek)?;
        self.put_cached(dir_id.to_string(), loaded.clone());
        Ok(loaded)
    }

    fn save_dir(&self, dir_id: &str, df: &VaultDirFile, dek: &[u8; 32]) -> VaultResult<()> {
        df.save(&self.vault_dir, &self.vault_id, dir_id, self.cipher, dek)
    }

    fn load_dir_vfs(
        &mut self,
        dir_id: &str,
        err_path: &VfsPath,
        dek: &[u8; 32],
    ) -> VfsResult<VaultDirFile> {
        self.load_dir(dir_id, dek).map_err(|e| e.into_vfs(err_path))
    }

    fn save_dir_vfs(
        &self,
        dir_id: &str,
        df: &VaultDirFile,
        err_path: &VfsPath,
        dek: &[u8; 32],
    ) -> VfsResult<()> {
        self.save_dir(dir_id, df, dek)
            .map_err(|e| e.into_vfs(err_path))
    }

    fn resolve_dir_id(&mut self, dir_path: &VfsPath, dek: &[u8; 32]) -> VfsResult<String> {
        validate_segments(dir_path)?;
        let mut cur_id = self.root_dir_id.clone();
        let segs = dir_path.segments();
        for (i, seg) in segs.iter().enumerate() {
            let step_path = VfsPath::new(segs[..=i].iter().cloned());
            let df = self.load_dir_vfs(&cur_id, &step_path, dek)?;
            match df.children.get(seg) {
                Some(child) if child.is_dir => {
                    cur_id = child.dir_id.clone().ok_or_else(|| VfsError::Backend {
                        path: step_path.clone(),
                        source: std::io::Error::other("directory entry missing dir_id"),
                    })?;
                }
                Some(_) => {
                    return Err(VfsError::PermissionDenied { path: step_path });
                }
                None => {
                    return Err(VfsError::NotFound { path: step_path });
                }
            }
        }
        Ok(cur_id)
    }

    fn resolve_parent(&mut self, path: &VfsPath, dek: &[u8; 32]) -> VfsResult<(String, String)> {
        validate_segments(path)?;
        let Some(parent) = path.parent() else {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        };
        let leaf = path
            .name()
            .ok_or_else(|| VfsError::PermissionDenied { path: path.clone() })?
            .to_string();
        let parent_id = self.resolve_dir_id(&parent, dek)?;
        Ok((parent_id, leaf))
    }

    pub fn list(&mut self, dir: &VfsPath, dek: &[u8; 32]) -> VfsResult<Vec<Entry>> {
        let dir_id = self.resolve_dir_id(dir, dek)?;
        let df = self.load_dir_vfs(&dir_id, dir, dek)?;
        Ok(df
            .children
            .values()
            .map(|c| c.to_entry(dir.join(&c.name)))
            .collect())
    }

    pub fn list_paged(
        &mut self,
        dir: &VfsPath,
        dek: &[u8; 32],
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool, u32)> {
        let dir_id = self.resolve_dir_id(dir, dek)?;
        let df = self.load_dir_vfs(&dir_id, dir, dek)?;
        let mut refs: Vec<_> = df.children.values().collect();
        refs.sort_unstable_by(|a, b| {
            fm_core::compare_dir_and_name(a.is_dir, &a.name, b.is_dir, &b.name, true)
        });
        let total = refs.len();
        let page = page.max(1) as usize;
        let page_size = page_size.max(1) as usize;
        let skip = (page - 1).saturating_mul(page_size);
        let has_more = skip.saturating_add(page_size) < total;
        let entries = refs
            .into_iter()
            .skip(skip)
            .take(page_size)
            .map(|c| c.to_entry(dir.join(&c.name)))
            .collect();
        Ok((entries, has_more, total as u32))
    }

    pub fn stat(&mut self, path: &VfsPath, dek: &[u8; 32]) -> VfsResult<Entry> {
        validate_segments(path)?;
        if path.is_root() {
            let root_id = self.root_dir_id.clone();
            let _ = self.load_dir_vfs(&root_id, path, dek)?;
            return Ok(Entry {
                name: String::new(),
                path: VfsPath::root(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                is_symlink: false,
                mime: None,
            });
        }
        let (parent_id, leaf) = self.resolve_parent(path, dek)?;
        let df = self.load_dir_vfs(&parent_id, path, dek)?;
        df.children
            .get(&leaf)
            .map(|c| c.to_entry(path.clone()))
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })
    }

    pub fn get_child(&mut self, path: &VfsPath, dek: &[u8; 32]) -> VfsResult<Option<DirChild>> {
        validate_segments(path)?;
        if path.is_root() {
            return Ok(None);
        }
        let (parent_id, leaf) = self.resolve_parent(path, dek)?;
        let df = self.load_dir_vfs(&parent_id, path, dek)?;
        Ok(df.children.get(&leaf).cloned())
    }

    pub fn ensure_parent_dir(&mut self, path: &VfsPath, dek: &[u8; 32]) -> VfsResult<()> {
        let _ = self.resolve_parent(path, dek)?;
        Ok(())
    }

    pub fn mkdir(&mut self, path: &VfsPath, dek: &[u8; 32]) -> VfsResult<()> {
        validate_segments(path)?;
        if path.is_root() {
            return Ok(());
        }
        let (parent_id, leaf) = self.resolve_parent(path, dek)?;
        let mut parent_df = self.load_dir_vfs(&parent_id, path, dek)?;
        if parent_df.children.contains_key(&leaf) {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(
                    std::io::ErrorKind::AlreadyExists,
                    "directory already exists",
                ),
            });
        }

        let child_dir_id = uuid::Uuid::new_v4().simple().to_string();
        let child_df = VaultDirFile::default();
        self.save_dir_vfs(&child_dir_id, &child_df, path, dek)?;

        parent_df.children.insert(
            leaf.clone(),
            DirChild {
                name: leaf,
                is_dir: true,
                size: 0,
                modified_ms: now_millis(),
                dir_id: Some(child_dir_id.clone()),
                obj_id: None,
                thumb_id: None,
            },
        );
        if let Err(e) = self.save_dir_vfs(&parent_id, &parent_df, path, dek) {
            let _ = std::fs::remove_file(dir_file_path(&self.vault_dir, &child_dir_id, self.cipher));
            return Err(e);
        }

        self.put_cached(child_dir_id, child_df);
        self.put_cached(parent_id, parent_df);
        Ok(())
    }

    pub fn upsert_file(
        &mut self,
        path: &VfsPath,
        obj_id: String,
        size: u64,
        fail_if_exists: bool,
        dek: &[u8; 32],
    ) -> VfsResult<(Option<String>, Option<String>)> {
        let (parent_id, leaf) = self.resolve_parent(path, dek)?;
        let mut parent_df = self.load_dir_vfs(&parent_id, path, dek)?;
        if let Some(existing) = parent_df.children.get(&leaf) {
            if existing.is_dir {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "destination is a directory",
                    ),
                });
            }
            if fail_if_exists {
                return Err(VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "file already exists",
                    ),
                });
            }
        }
        let prev = parent_df.children.insert(
            leaf.clone(),
            DirChild {
                name: leaf,
                is_dir: false,
                size,
                modified_ms: now_millis(),
                dir_id: None,
                obj_id: Some(obj_id),
                thumb_id: None,
            },
        );
        self.save_dir_vfs(&parent_id, &parent_df, path, dek)?;
        self.put_cached(parent_id, parent_df);
        Ok(match prev {
            Some(old) => (old.obj_id, old.thumb_id),
            None => (None, None),
        })
    }

    pub fn set_thumb_id(
        &mut self,
        path: &VfsPath,
        thumb_id: String,
        dek: &[u8; 32],
    ) -> VaultResult<Option<String>> {
        if validate_segments(path).is_err() || path.is_root() {
            return Err(VaultError::NotFound(path.to_slash_string()));
        }
        let parent = path
            .parent()
            .ok_or_else(|| VaultError::NotFound(path.to_slash_string()))?;
        let leaf = path
            .name()
            .ok_or_else(|| VaultError::NotFound(path.to_slash_string()))?
            .to_string();

        let mut cur_id = self.root_dir_id.clone();
        for seg in parent.segments() {
            let df = self.load_dir(&cur_id, dek)?;
            let Some(ch) = df.children.get(seg) else {
                return Err(VaultError::NotFound(path.to_slash_string()));
            };
            if !ch.is_dir {
                return Err(VaultError::NotFound(path.to_slash_string()));
            }
            cur_id = ch
                .dir_id
                .clone()
                .ok_or_else(|| VaultError::NotFound(path.to_slash_string()))?;
        }

        let mut parent_df = self.load_dir(&cur_id, dek)?;
        let Some(child) = parent_df.children.get_mut(&leaf) else {
            return Err(VaultError::NotFound(path.to_slash_string()));
        };
        if child.is_dir {
            return Err(VaultError::Unsupported(
                "directories have no thumbnail".to_string(),
            ));
        }
        let old = child.thumb_id.replace(thumb_id);
        self.save_dir(&cur_id, &parent_df, dek)?;
        self.put_cached(cur_id, parent_df);
        Ok(old)
    }

    pub fn remove(
        &mut self,
        path: &VfsPath,
        dek: &[u8; 32],
    ) -> VfsResult<(Vec<String>, Vec<String>, Vec<String>)> {
        validate_segments(path)?;
        if path.is_root() {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        let (parent_id, leaf) = self.resolve_parent(path, dek)?;
        let mut parent_df = self.load_dir_vfs(&parent_id, path, dek)?;
        let Some(removed) = parent_df.children.remove(&leaf) else {
            return Err(VfsError::NotFound { path: path.clone() });
        };

        let mut obj_ids = Vec::new();
        let mut thumb_ids = Vec::new();
        let mut dir_ids = Vec::new();

        if !removed.is_dir {
            if let Some(oid) = removed.obj_id {
                obj_ids.push(oid);
            }
            if let Some(tid) = removed.thumb_id {
                thumb_ids.push(tid);
            }
        } else if let Some(root_sub_id) = removed.dir_id {
            let mut stack = vec![root_sub_id];
            while let Some(did) = stack.pop() {
                dir_ids.push(did.clone());
                if let Ok(df) = self.load_dir(&did, dek) {
                    for ch in df.children.values() {
                        if ch.is_dir {
                            if let Some(ref sub_id) = ch.dir_id {
                                stack.push(sub_id.clone());
                            }
                        } else {
                            if let Some(ref oid) = ch.obj_id {
                                obj_ids.push(oid.clone());
                            }
                            if let Some(ref tid) = ch.thumb_id {
                                thumb_ids.push(tid.clone());
                            }
                        }
                    }
                }
            }
        }

        self.save_dir_vfs(&parent_id, &parent_df, path, dek)?;
        self.put_cached(parent_id, parent_df);
        for did in &dir_ids {
            self.evict_id(did);
        }
        Ok((obj_ids, thumb_ids, dir_ids))
    }

    pub fn rename(
        &mut self,
        from: &VfsPath,
        to: &VfsPath,
        dek: &[u8; 32],
    ) -> VfsResult<(Option<String>, Option<String>)> {
        validate_segments(from)?;
        validate_segments(to)?;
        if from.is_root() || to.is_root() {
            return Err(VfsError::PermissionDenied { path: from.clone() });
        }
        if from == to {
            return Ok((None, None));
        }

        let (src_parent_id, src_leaf) = self.resolve_parent(from, dek)?;
        let mut src_df = self.load_dir_vfs(&src_parent_id, from, dek)?;
        let Some(mut src_child) = src_df.children.get(&src_leaf).cloned() else {
            return Err(VfsError::NotFound { path: from.clone() });
        };

        if src_child.is_dir && to.starts_with(from) {
            return Err(VfsError::PermissionDenied { path: to.clone() });
        }

        let (dst_parent_id, dst_leaf) = self.resolve_parent(to, dek)?;
        if src_parent_id == dst_parent_id {
            let mut replaced = (None, None);
            if let Some(existing) = src_df.children.get(&dst_leaf) {
                if existing.is_dir || src_child.is_dir {
                    return Err(VfsError::Backend {
                        path: to.clone(),
                        source: std::io::Error::new(
                            std::io::ErrorKind::AlreadyExists,
                            "destination already exists",
                        ),
                    });
                }
                if let Some(old) = src_df.children.remove(&dst_leaf) {
                    replaced = (old.obj_id, old.thumb_id);
                }
            }
            src_df.children.remove(&src_leaf);
            src_child.name = dst_leaf.clone();
            src_child.modified_ms = now_millis();
            src_df.children.insert(dst_leaf, src_child);
            self.save_dir_vfs(&src_parent_id, &src_df, to, dek)?;
            self.put_cached(src_parent_id, src_df);
            return Ok(replaced);
        }

        let mut dst_df = self.load_dir_vfs(&dst_parent_id, to, dek)?;
        let old_dst_df = dst_df.clone();
        let mut replaced = (None, None);
        if let Some(existing) = dst_df.children.get(&dst_leaf) {
            if existing.is_dir || src_child.is_dir {
                return Err(VfsError::Backend {
                    path: to.clone(),
                    source: std::io::Error::new(
                        std::io::ErrorKind::AlreadyExists,
                        "destination already exists",
                    ),
                });
            }
            if let Some(old) = dst_df.children.remove(&dst_leaf) {
                replaced = (old.obj_id, old.thumb_id);
            }
        }

        src_df.children.remove(&src_leaf);
        src_child.name = dst_leaf.clone();
        src_child.modified_ms = now_millis();
        dst_df.children.insert(dst_leaf, src_child);

        self.save_dir_vfs(&dst_parent_id, &dst_df, to, dek)?;
        if let Err(e) = self.save_dir_vfs(&src_parent_id, &src_df, from, dek) {
            let _ = self.save_dir(&dst_parent_id, &old_dst_df, dek);
            return Err(e);
        }

        self.put_cached(dst_parent_id, dst_df);
        self.put_cached(src_parent_id, src_df);
        Ok(replaced)
    }
}

#[derive(Debug, Default)]
pub struct LiveTreeSnapshot {
    pub file_count: u64,
    pub dir_count: u64,
    pub total_plain_bytes: u64,
    pub live_obj_ids: HashSet<String>,
    pub live_thumb_ids: HashSet<String>,
    pub live_dir_ids: HashSet<String>,
}

pub fn walk_live_tree(
    vault_dir: &Path,
    vault_id: &str,
    root_dir_id: &str,
    cipher: VaultCipher,
    dek: &[u8; 32],
) -> VaultResult<LiveTreeSnapshot> {
    let mut snap = LiveTreeSnapshot::default();
    let mut stack = vec![root_dir_id.to_string()];
    while let Some(did) = stack.pop() {
        if !snap.live_dir_ids.insert(did.clone()) {
            continue;
        }
        let df = VaultDirFile::load(vault_dir, vault_id, &did, cipher, dek)?;
        for ch in df.children.values() {
            if ch.is_dir {
                snap.dir_count = snap.dir_count.saturating_add(1);
                if let Some(ref sub_id) = ch.dir_id {
                    stack.push(sub_id.clone());
                }
            } else {
                snap.file_count = snap.file_count.saturating_add(1);
                snap.total_plain_bytes = snap.total_plain_bytes.saturating_add(ch.size);
                if let Some(ref oid) = ch.obj_id {
                    snap.live_obj_ids.insert(oid.clone());
                }
                if let Some(ref tid) = ch.thumb_id {
                    snap.live_thumb_ids.insert(tid.clone());
                }
            }
        }
    }
    Ok(snap)
}

fn ensure_migrated_dir_chain(
    dir_files: &mut HashMap<String, VaultDirFile>,
    dir_ids_by_path: &mut HashMap<Vec<String>, String>,
    segs: &[String],
) -> String {
    if let Some(existing) = dir_ids_by_path.get(segs) {
        return existing.clone();
    }
    let mut cur_path = Vec::with_capacity(segs.len());
    let mut parent_id = dir_ids_by_path
        .get(&cur_path)
        .cloned()
        .expect("root_dir_id always seeded");

    for seg in segs {
        cur_path.push(seg.clone());
        if let Some(existing_id) = dir_ids_by_path.get(&cur_path) {
            parent_id = existing_id.clone();
            continue;
        }
        let new_id = uuid::Uuid::new_v4().simple().to_string();
        dir_files.insert(new_id.clone(), VaultDirFile::default());
        dir_ids_by_path.insert(cur_path.clone(), new_id.clone());
        if let Some(parent_df) = dir_files.get_mut(&parent_id) {
            parent_df.children.insert(
                seg.clone(),
                DirChild {
                    name: seg.clone(),
                    is_dir: true,
                    size: 0,
                    modified_ms: now_millis(),
                    dir_id: Some(new_id.clone()),
                    obj_id: None,
                    thumb_id: None,
                },
            );
        }
        parent_id = new_id;
    }
    parent_id
}

pub fn migrate_legacy_index_to_dirs(
    vault_dir: &Path,
    meta: &mut VaultMeta,
    dek: &[u8; 32],
) -> VaultResult<String> {
    if let Some(ref existing_root) = meta.root_dir_id {
        if dir_file_path(vault_dir, existing_root, meta.cipher).exists() {
            return Ok(existing_root.clone());
        }
    }

    let legacy = VaultIndex::load(vault_dir, &meta.vault_id, meta.cipher, dek)?;
    let root_dir_id = meta
        .root_dir_id
        .clone()
        .unwrap_or_else(|| uuid::Uuid::new_v4().simple().to_string());

    let mut dir_files: HashMap<String, VaultDirFile> = HashMap::new();
    let mut dir_ids_by_path: HashMap<Vec<String>, String> = HashMap::new();
    dir_files.insert(root_dir_id.clone(), VaultDirFile::default());
    dir_ids_by_path.insert(Vec::new(), root_dir_id.clone());

    let mut nodes: Vec<VaultNode> = legacy.nodes.into_values().collect();
    nodes.sort_by(|a, b| {
        a.segments
            .len()
            .cmp(&b.segments.len())
            .then_with(|| (!a.is_dir).cmp(&(!b.is_dir)))
            .then_with(|| a.segments.cmp(&b.segments))
    });

    for node in nodes {
        if node.segments.is_empty() {
            continue;
        }
        let parent_segs = &node.segments[..node.segments.len() - 1];
        let leaf = node.segments.last().cloned().unwrap_or(node.name.clone());
        let parent_id = ensure_migrated_dir_chain(&mut dir_files, &mut dir_ids_by_path, parent_segs);

        if node.is_dir {
            let child_dir_id = dir_ids_by_path
                .get(&node.segments)
                .cloned()
                .unwrap_or_else(|| uuid::Uuid::new_v4().simple().to_string());
            dir_files
                .entry(child_dir_id.clone())
                .or_insert_with(VaultDirFile::default);
            dir_ids_by_path.insert(node.segments.clone(), child_dir_id.clone());
            if let Some(parent_df) = dir_files.get_mut(&parent_id) {
                parent_df.children.insert(
                    leaf,
                    DirChild {
                        name: node.name,
                        is_dir: true,
                        size: 0,
                        modified_ms: node.modified_ms,
                        dir_id: Some(child_dir_id),
                        obj_id: None,
                        thumb_id: None,
                    },
                );
            }
        } else if let Some(parent_df) = dir_files.get_mut(&parent_id) {
            parent_df.children.insert(
                leaf,
                DirChild {
                    name: node.name,
                    is_dir: false,
                    size: node.size,
                    modified_ms: node.modified_ms,
                    dir_id: None,
                    obj_id: node.obj_id,
                    thumb_id: node.thumb_id,
                },
            );
        }
    }

    std::fs::create_dir_all(vault_dir.join(DIRS_DIR))?;
    for (dir_id, df) in &dir_files {
        df.save(vault_dir, &meta.vault_id, dir_id, meta.cipher, dek)?;
    }

    meta.root_dir_id = Some(root_dir_id.clone());
    meta.save(vault_dir)?;

    let legacy_path = index_file_path(vault_dir, meta.cipher);
    let _ = std::fs::remove_file(legacy_path);
    Ok(root_dir_id)
}
