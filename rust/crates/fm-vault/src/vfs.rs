use crate::crypto::{
    decrypt_blob, encrypt_blob, open_fpv1_range_stream, Fpv1SyncWriter, VaultCipher, CHUNK_SIZE,
};
use crate::error::{VaultError, VaultResult};
use crate::index::{dir_file_path, walk_live_tree, DirIndexCache, DIRS_DIR};
use async_trait::async_trait;
use fm_core::{Capabilities, Entry, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use parking_lot::{Mutex, RwLock};
use std::collections::HashSet;
use std::future::Future;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::{Duration, SystemTime};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncSeekExt, AsyncWrite};
use zeroize::Zeroizing;

pub const OBJECTS_DIR: &str = "objects";
pub const THUMBS_DIR: &str = "thumbs";

#[derive(Debug, Clone, Default)]
pub struct VaultStats {
    pub file_count: u64,
    pub dir_count: u64,
    pub total_plain_bytes: u64,
    pub disk_bytes: u64,
    pub orphan_count: u64,
    pub orphan_bytes: u64,
}

#[derive(Debug, Clone, Default)]
pub struct VaultGcResult {
    pub removed_files: u64,
    pub freed_bytes: u64,
}

fn bucket_ext(cipher: VaultCipher) -> &'static str {
    if cipher.is_encrypted() {
        "enc"
    } else {
        "raw"
    }
}

fn sharded_blob_path(vault_dir: &Path, bucket: &str, id: &str, ext: &str) -> PathBuf {
    let base = vault_dir.join(bucket);
    match shard_prefix(id) {
        Some(prefix) => base.join(prefix).join(format!("{id}.{ext}")),
        None => base.join(format!("{id}.{ext}")),
    }
}

fn legacy_blob_path(vault_dir: &Path, bucket: &str, id: &str, ext: &str) -> PathBuf {
    vault_dir.join(bucket).join(format!("{id}.{ext}"))
}

fn delete_orphaned_files_sync(
    vault_dir: &Path,
    cipher: VaultCipher,
    obj_ids: &[String],
    thumb_ids: &[String],
    dir_ids: &[String],
) {
    let ext = bucket_ext(cipher);
    for oid in obj_ids {
        let _ = std::fs::remove_file(sharded_blob_path(vault_dir, OBJECTS_DIR, oid, ext));
        let _ = std::fs::remove_file(legacy_blob_path(vault_dir, OBJECTS_DIR, oid, ext));
    }
    for tid in thumb_ids {
        let _ = std::fs::remove_file(sharded_blob_path(vault_dir, THUMBS_DIR, tid, ext));
        let _ = std::fs::remove_file(legacy_blob_path(vault_dir, THUMBS_DIR, tid, ext));
    }
    for did in dir_ids {
        let _ = std::fs::remove_file(dir_file_path(vault_dir, did, cipher));
    }
}

fn is_older_than(meta: &std::fs::Metadata, min_age: Duration) -> bool {
    if min_age.is_zero() {
        return true;
    }
    let Ok(modified) = meta.modified() else {
        return false;
    };
    SystemTime::now()
        .duration_since(modified)
        .map(|d| d >= min_age)
        .unwrap_or(false)
}

pub fn sweep_stale_tmp_files(vault_dir: &Path, min_age: Duration) -> (u64, u64) {
    fn walk(dir: &Path, depth: usize, min_age: Duration, removed: &mut u64, freed: &mut u64) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = std::fs::symlink_metadata(&path) else {
                continue;
            };
            let ft = meta.file_type();
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                if depth < 2 {
                    walk(&path, depth + 1, min_age, removed, freed);
                }
                continue;
            }
            if !ft.is_file() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            if name.ends_with(".tmp") && is_older_than(&meta, min_age) {
                let len = meta.len();
                if std::fs::remove_file(&path).is_ok() {
                    *removed = removed.saturating_add(1);
                    *freed = freed.saturating_add(len);
                }
            }
        }
    }

    let mut removed = 0u64;
    let mut freed = 0u64;
    for sub in [OBJECTS_DIR, THUMBS_DIR, DIRS_DIR] {
        let dir = vault_dir.join(sub);
        if dir.exists() {
            walk(&dir, 0, min_age, &mut removed, &mut freed);
        }
    }
    (removed, freed)
}

fn scan_bucket_for_stats_and_gc(
    bucket_dir: &Path,
    expected_ext_with_dot: &str,
    live_ids: &HashSet<String>,
    min_orphan_age: Duration,
    do_delete: bool,
    disk_bytes: &mut u64,
    orphan_count: &mut u64,
    orphan_bytes: &mut u64,
) {
    fn visit(
        dir: &Path,
        depth: usize,
        expected_ext_with_dot: &str,
        live_ids: &HashSet<String>,
        min_orphan_age: Duration,
        do_delete: bool,
        disk_bytes: &mut u64,
        orphan_count: &mut u64,
        orphan_bytes: &mut u64,
    ) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = std::fs::symlink_metadata(&path) else {
                continue;
            };
            let ft = meta.file_type();
            if ft.is_symlink() {
                continue;
            }
            if ft.is_dir() {
                if depth < 2 {
                    visit(
                        &path,
                        depth + 1,
                        expected_ext_with_dot,
                        live_ids,
                        min_orphan_age,
                        do_delete,
                        disk_bytes,
                        orphan_count,
                        orphan_bytes,
                    );
                }
                continue;
            }
            if !ft.is_file() {
                continue;
            }
            let len = meta.len();
            *disk_bytes = disk_bytes.saturating_add(len);
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let is_orphan = if name.ends_with(".tmp") || name.ends_with(".bak") {
                is_older_than(&meta, min_orphan_age)
            } else if let Some(id) = name.strip_suffix(expected_ext_with_dot) {
                !live_ids.contains(id) && is_older_than(&meta, min_orphan_age)
            } else {
                false
            };
            if is_orphan {
                if do_delete {
                    if std::fs::remove_file(&path).is_ok() {
                        *orphan_count = orphan_count.saturating_add(1);
                        *orphan_bytes = orphan_bytes.saturating_add(len);
                    }
                } else {
                    *orphan_count = orphan_count.saturating_add(1);
                    *orphan_bytes = orphan_bytes.saturating_add(len);
                }
            }
        }
    }

    if bucket_dir.exists() {
        visit(
            bucket_dir,
            0,
            expected_ext_with_dot,
            live_ids,
            min_orphan_age,
            do_delete,
            disk_bytes,
            orphan_count,
            orphan_bytes,
        );
    }
}

pub(crate) fn shard_prefix(id: &str) -> Option<String> {
    let bytes = id.as_bytes();
    if bytes.len() >= 2 && bytes[0].is_ascii_hexdigit() && bytes[1].is_ascii_hexdigit() {
        Some(id[..2].to_ascii_lowercase())
    } else {
        None
    }
}

pub(crate) fn ensure_private_bucket_dir(dir: &Path) -> VaultResult<()> {
    std::fs::create_dir_all(dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700));
    }
    Ok(())
}

pub struct VaultState {
    pub vault_id: String,
    pub root_dir_id: String,
    pub vault_dir: PathBuf,
    pub cipher: VaultCipher,
    dek: RwLock<Zeroizing<[u8; 32]>>,
    dir_tree: Arc<Mutex<DirIndexCache>>,
    write_lock: tokio::sync::Mutex<()>,
    locked: AtomicBool,
}

impl VaultState {
    pub fn open(
        vault_id: String,
        root_dir_id: String,
        vault_dir: PathBuf,
        cipher: VaultCipher,
        dek: Zeroizing<[u8; 32]>,
    ) -> VaultResult<Arc<Self>> {
        std::fs::create_dir_all(vault_dir.join(OBJECTS_DIR))?;
        std::fs::create_dir_all(vault_dir.join(THUMBS_DIR))?;
        std::fs::create_dir_all(vault_dir.join(DIRS_DIR))?;
        let mut dir_tree = DirIndexCache::new(
            vault_dir.clone(),
            vault_id.clone(),
            root_dir_id.clone(),
            cipher,
        );
        // Unlock verifies only the root directory index; subdirectories load lazily on demand.
        let _ = dir_tree.load_dir(&root_dir_id, &dek)?;
        Ok(Arc::new(Self {
            vault_id,
            root_dir_id,
            vault_dir,
            cipher,
            dek: RwLock::new(dek),
            dir_tree: Arc::new(Mutex::new(dir_tree)),
            write_lock: tokio::sync::Mutex::new(()),
            locked: AtomicBool::new(false),
        }))
    }

    pub fn is_locked(&self) -> bool {
        self.locked.load(Ordering::SeqCst)
    }

    pub fn lock_and_zeroize(&self) {
        self.locked.store(true, Ordering::SeqCst);
        *self.dek.write() = Zeroizing::new([0u8; 32]);
        self.dir_tree.lock().clear();
    }

    fn current_dek(&self, path: &VfsPath) -> VfsResult<Zeroizing<[u8; 32]>> {
        if self.is_locked() {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        Ok(self.dek.read().clone())
    }

    fn legacy_obj_path(&self, obj_id: &str) -> PathBuf {
        let ext = if self.cipher.is_encrypted() {
            "enc"
        } else {
            "raw"
        };
        self.vault_dir.join(OBJECTS_DIR).join(format!("{obj_id}.{ext}"))
    }

    pub fn obj_path(&self, obj_id: &str) -> PathBuf {
        let ext = if self.cipher.is_encrypted() {
            "enc"
        } else {
            "raw"
        };
        let base = self.vault_dir.join(OBJECTS_DIR);
        match shard_prefix(obj_id) {
            Some(prefix) => base.join(prefix).join(format!("{obj_id}.{ext}")),
            None => base.join(format!("{obj_id}.{ext}")),
        }
    }

    pub fn resolve_existing_obj_path(&self, obj_id: &str) -> PathBuf {
        let sharded = self.obj_path(obj_id);
        if sharded.exists() {
            return sharded;
        }
        let legacy = self.legacy_obj_path(obj_id);
        if legacy.exists() {
            return legacy;
        }
        sharded
    }

    fn legacy_thumb_path(&self, thumb_id: &str) -> PathBuf {
        let ext = if self.cipher.is_encrypted() {
            "enc"
        } else {
            "raw"
        };
        self.vault_dir.join(THUMBS_DIR).join(format!("{thumb_id}.{ext}"))
    }

    pub fn thumb_path(&self, thumb_id: &str) -> PathBuf {
        let ext = if self.cipher.is_encrypted() {
            "enc"
        } else {
            "raw"
        };
        let base = self.vault_dir.join(THUMBS_DIR);
        match shard_prefix(thumb_id) {
            Some(prefix) => base.join(prefix).join(format!("{thumb_id}.{ext}")),
            None => base.join(format!("{thumb_id}.{ext}")),
        }
    }

    pub fn resolve_existing_thumb_path(&self, thumb_id: &str) -> PathBuf {
        let sharded = self.thumb_path(thumb_id);
        if sharded.exists() {
            return sharded;
        }
        let legacy = self.legacy_thumb_path(thumb_id);
        if legacy.exists() {
            return legacy;
        }
        sharded
    }

    async fn delete_orphaned_blobs_async(
        &self,
        obj_ids: Vec<String>,
        thumb_ids: Vec<String>,
        dir_ids: Vec<String>,
    ) {
        if obj_ids.is_empty() && thumb_ids.is_empty() && dir_ids.is_empty() {
            return;
        }
        let vault_dir = self.vault_dir.clone();
        let cipher = self.cipher;
        let _ = tokio::task::spawn_blocking(move || {
            delete_orphaned_files_sync(&vault_dir, cipher, &obj_ids, &thumb_ids, &dir_ids);
        })
        .await;
    }

    pub fn compute_stats(&self, min_orphan_age: Duration) -> VaultResult<VaultStats> {
        if self.is_locked() {
            return Err(VaultError::Locked(self.vault_id.clone()));
        }
        let dek = self.dek.read().clone();
        let _dir_guard = self.dir_tree.lock();
        let snap = walk_live_tree(
            &self.vault_dir,
            &self.vault_id,
            &self.root_dir_id,
            self.cipher,
            &dek,
        )?;

        let mut disk_bytes = 0u64;
        if let Ok(entries) = std::fs::read_dir(&self.vault_dir) {
            for entry in entries.flatten() {
                if let Ok(m) = entry.metadata() {
                    if m.is_file() {
                        disk_bytes = disk_bytes.saturating_add(m.len());
                    }
                }
            }
        }
        let mut orphan_count = 0u64;
        let mut orphan_bytes = 0u64;
        let blob_ext = if self.cipher.is_encrypted() {
            ".enc"
        } else {
            ".raw"
        };
        let dir_ext = if self.cipher.is_encrypted() {
            ".enc"
        } else {
            ".json"
        };
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(OBJECTS_DIR),
            blob_ext,
            &snap.live_obj_ids,
            min_orphan_age,
            false,
            &mut disk_bytes,
            &mut orphan_count,
            &mut orphan_bytes,
        );
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(THUMBS_DIR),
            blob_ext,
            &snap.live_thumb_ids,
            min_orphan_age,
            false,
            &mut disk_bytes,
            &mut orphan_count,
            &mut orphan_bytes,
        );
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(DIRS_DIR),
            dir_ext,
            &snap.live_dir_ids,
            min_orphan_age,
            false,
            &mut disk_bytes,
            &mut orphan_count,
            &mut orphan_bytes,
        );

        Ok(VaultStats {
            file_count: snap.file_count,
            dir_count: snap.dir_count,
            total_plain_bytes: snap.total_plain_bytes,
            disk_bytes,
            orphan_count,
            orphan_bytes,
        })
    }

    pub fn gc_orphaned_files(&self, min_orphan_age: Duration) -> VaultResult<VaultGcResult> {
        if self.is_locked() {
            return Err(VaultError::Locked(self.vault_id.clone()));
        }
        let dek = self.dek.read().clone();
        let _dir_guard = self.dir_tree.lock();
        let snap = walk_live_tree(
            &self.vault_dir,
            &self.vault_id,
            &self.root_dir_id,
            self.cipher,
            &dek,
        )?;
        let mut disk_bytes = 0u64;
        let mut removed_files = 0u64;
        let mut freed_bytes = 0u64;
        let blob_ext = if self.cipher.is_encrypted() {
            ".enc"
        } else {
            ".raw"
        };
        let dir_ext = if self.cipher.is_encrypted() {
            ".enc"
        } else {
            ".json"
        };
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(OBJECTS_DIR),
            blob_ext,
            &snap.live_obj_ids,
            min_orphan_age,
            true,
            &mut disk_bytes,
            &mut removed_files,
            &mut freed_bytes,
        );
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(THUMBS_DIR),
            blob_ext,
            &snap.live_thumb_ids,
            min_orphan_age,
            true,
            &mut disk_bytes,
            &mut removed_files,
            &mut freed_bytes,
        );
        scan_bucket_for_stats_and_gc(
            &self.vault_dir.join(DIRS_DIR),
            dir_ext,
            &snap.live_dir_ids,
            min_orphan_age,
            true,
            &mut disk_bytes,
            &mut removed_files,
            &mut freed_bytes,
        );
        Ok(VaultGcResult {
            removed_files,
            freed_bytes,
        })
    }

    pub async fn gc_orphaned_files_async(
        self: &Arc<Self>,
        min_orphan_age: Duration,
    ) -> VaultResult<VaultGcResult> {
        let _guard = self.write_lock.lock().await;
        let me = Arc::clone(self);
        tokio::task::spawn_blocking(move || me.gc_orphaned_files(min_orphan_age))
            .await
            .map_err(|e| VaultError::Io(io::Error::other(e)))?
    }

    pub async fn commit_file_entry(
        &self,
        path: &VfsPath,
        obj_id: String,
        plain_len: u64,
        fail_if_exists: bool,
    ) -> VaultResult<()> {
        let _guard = self.write_lock.lock().await;
        if self.is_locked() {
            self.delete_orphaned_blobs_async(vec![obj_id], Vec::new(), Vec::new())
                .await;
            return Err(VaultError::Locked(self.vault_id.clone()));
        }
        let dek = self.dek.read().clone();
        let dir_tree = self.dir_tree.clone();
        let path_clone = path.clone();
        let obj_id_clone = obj_id.clone();

        let res = tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.upsert_file(&path_clone, obj_id_clone, plain_len, fail_if_exists, &dek)
        })
        .await
        .map_err(|e| VaultError::Io(io::Error::other(e)))?;

        let (old_obj, old_thumb) = match res {
            Ok(prev) => prev,
            Err(e) => {
                self.delete_orphaned_blobs_async(vec![obj_id], Vec::new(), Vec::new())
                    .await;
                return Err(VaultError::Vfs(e));
            }
        };

        let objs: Vec<String> = old_obj.into_iter().collect();
        let thumbs: Vec<String> = old_thumb.into_iter().collect();
        self.delete_orphaned_blobs_async(objs, thumbs, Vec::new())
            .await;
        Ok(())
    }

    pub async fn read_thumbnail(&self, path: &VfsPath) -> VaultResult<Option<Vec<u8>>> {
        if self.is_locked() {
            return Err(VaultError::Locked(self.vault_id.clone()));
        }
        let dek = self.dek.read().clone();
        let dir_tree = self.dir_tree.clone();
        let path_clone = path.clone();
        let thumb_id = tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard
                .get_child(&path_clone, &dek)
                .map(|opt| opt.and_then(|c| c.thumb_id))
        })
        .await
        .map_err(|e| VaultError::Io(io::Error::other(e)))??;

        let Some(tid) = thumb_id else {
            return Ok(None);
        };
        let tpath = self.resolve_existing_thumb_path(&tid);
        if !tpath.exists() {
            return Ok(None);
        }
        let dek = self.dek.read().clone();
        let cipher = self.cipher;
        let aad = format!("fm-vault-thumb-v1:{}:{tid}", self.vault_id).into_bytes();
        tokio::task::spawn_blocking(move || {
            let raw = std::fs::read(&tpath)?;
            let plain = if cipher.is_encrypted() {
                decrypt_blob(&dek, cipher, &aad, &raw)?
            } else {
                raw
            };
            Ok(Some(plain))
        })
        .await
        .map_err(|e| VaultError::Io(io::Error::other(e)))?
    }

    pub async fn save_thumbnail(&self, path: &VfsPath, bytes: Vec<u8>) -> VaultResult<()> {
        let _guard = self.write_lock.lock().await;
        if self.is_locked() {
            return Err(VaultError::Locked(self.vault_id.clone()));
        }
        let dek = self.dek.read().clone();
        let tid = uuid::Uuid::new_v4().simple().to_string();
        let tpath = self.thumb_path(&tid);
        let cipher = self.cipher;
        let vault_id = self.vault_id.clone();
        let dir_tree = self.dir_tree.clone();
        let path_clone = path.clone();

        let old_tid = tokio::task::spawn_blocking(move || -> VaultResult<Option<String>> {
            if let Some(parent) = tpath.parent() {
                ensure_private_bucket_dir(parent)?;
            }
            let aad = format!("fm-vault-thumb-v1:{vault_id}:{tid}").into_bytes();
            let data = if cipher.is_encrypted() {
                encrypt_blob(&dek, cipher, &aad, &bytes)?
            } else {
                bytes
            };
            crate::meta::atomic_write_bytes(&tpath, &data)?;

            let res = {
                let mut guard = dir_tree.lock();
                guard.set_thumb_id(&path_clone, tid, &dek)
            };
            match res {
                Ok(old) => Ok(old),
                Err(e) => {
                    let _ = std::fs::remove_file(&tpath);
                    Err(e)
                }
            }
        })
        .await
        .map_err(|e| VaultError::Io(io::Error::other(e)))??;

        if let Some(old) = old_tid {
            self.delete_orphaned_blobs_async(Vec::new(), vec![old], Vec::new())
                .await;
        }
        Ok(())
    }
}

pub struct VaultFs {
    state: Arc<VaultState>,
}

impl VaultFs {
    pub fn new(state: Arc<VaultState>) -> Self {
        Self { state }
    }

    pub fn state(&self) -> &Arc<VaultState> {
        &self.state
    }
}

enum BackendSyncWriter {
    Encrypted(Fpv1SyncWriter),
    Plain { file: std::fs::File, written: u64 },
}

struct WriterCore {
    backend: Option<BackendSyncWriter>,
    pending_plain: Vec<u8>,
}

impl WriterCore {
    fn write_non_final_chunk(&mut self, chunk: &[u8]) -> io::Result<()> {
        match self.backend.as_mut() {
            Some(BackendSyncWriter::Encrypted(w)) => w
                .write_chunk(chunk, false)
                .map_err(|e| io::Error::other(e.to_string())),
            Some(BackendSyncWriter::Plain { file, written }) => {
                file.write_all(chunk)?;
                *written = written.saturating_add(chunk.len() as u64);
                Ok(())
            }
            None => Err(io::Error::other("writer finalized")),
        }
    }

    fn finalize_to_file(&mut self, tmp_path: &Path, obj_path: &Path) -> io::Result<u64> {
        let mut backend = self
            .backend
            .take()
            .ok_or_else(|| io::Error::other("writer finalized"))?;

        if self.pending_plain.len() > CHUNK_SIZE {
            let head: Vec<u8> = self.pending_plain.drain(..CHUNK_SIZE).collect();
            match &mut backend {
                BackendSyncWriter::Encrypted(w) => w
                    .write_chunk(&head, false)
                    .map_err(|e| io::Error::other(e.to_string()))?,
                BackendSyncWriter::Plain { file, written } => {
                    file.write_all(&head)?;
                    *written = written.saturating_add(head.len() as u64);
                }
            }
        }

        let tail = std::mem::take(&mut self.pending_plain);
        let plain_len = match backend {
            BackendSyncWriter::Encrypted(mut w) => {
                w.write_chunk(&tail, true)
                    .map_err(|e| io::Error::other(e.to_string()))?;
                w.finalize().map_err(|e| io::Error::other(e.to_string()))?
            }
            BackendSyncWriter::Plain { mut file, written } => {
                if !tail.is_empty() {
                    file.write_all(&tail)?;
                }
                file.flush()?;
                file.sync_data()?;
                written.saturating_add(tail.len() as u64)
            }
        };

        std::fs::rename(tmp_path, obj_path)?;
        Ok(plain_len)
    }
}

type BoxFuture<T> = Pin<Box<dyn Future<Output = T> + Send>>;

enum WriterPhase {
    Ready(Option<WriterCore>),
    Busy(BoxFuture<io::Result<WriterCore>>),
    Committing(BoxFuture<io::Result<()>>),
    Done,
    Poisoned,
}

struct VaultFileWriter {
    state: Arc<VaultState>,
    target_path: VfsPath,
    mode: WriteMode,
    obj_id: String,
    obj_path: PathBuf,
    tmp_path: PathBuf,
    committed: Arc<AtomicBool>,
    phase: WriterPhase,
}

impl Drop for VaultFileWriter {
    fn drop(&mut self) {
        if !self.committed.load(Ordering::Acquire) {
            let _ = std::fs::remove_file(&self.tmp_path);
        }
    }
}

impl AsyncWrite for VaultFileWriter {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        loop {
            match &mut self.phase {
                WriterPhase::Ready(opt_core) => {
                    let mut core = opt_core
                        .take()
                        .ok_or_else(|| io::Error::other("missing writer state"))?;
                    if core.pending_plain.len() > CHUNK_SIZE {
                        let chunk: Vec<u8> = core.pending_plain.drain(..CHUNK_SIZE).collect();
                        let fut = Box::pin(async move {
                            tokio::task::spawn_blocking(move || {
                                core.write_non_final_chunk(&chunk)?;
                                Ok(core)
                            })
                            .await
                            .map_err(io::Error::other)?
                        });
                        self.phase = WriterPhase::Busy(fut);
                        continue;
                    }
                    let space = (CHUNK_SIZE + 1).saturating_sub(core.pending_plain.len());
                    let take = buf.len().min(space);
                    core.pending_plain.extend_from_slice(&buf[..take]);
                    *opt_core = Some(core);
                    return Poll::Ready(Ok(take));
                }
                WriterPhase::Busy(fut) => match fut.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(core)) => {
                        self.phase = WriterPhase::Ready(Some(core));
                    }
                    Poll::Ready(Err(e)) => {
                        self.phase = WriterPhase::Poisoned;
                        return Poll::Ready(Err(e));
                    }
                },
                WriterPhase::Committing(_) | WriterPhase::Done => {
                    return Poll::Ready(Err(io::Error::other("write after shutdown")));
                }
                WriterPhase::Poisoned => {
                    return Poll::Ready(Err(io::Error::other("writer poisoned")));
                }
            }
        }
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        loop {
            match &mut self.phase {
                WriterPhase::Busy(fut) => match fut.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(core)) => {
                        self.phase = WriterPhase::Ready(Some(core));
                    }
                    Poll::Ready(Err(e)) => {
                        self.phase = WriterPhase::Poisoned;
                        return Poll::Ready(Err(e));
                    }
                },
                WriterPhase::Ready(_) | WriterPhase::Done => return Poll::Ready(Ok(())),
                WriterPhase::Committing(fut) => match fut.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(())) => {
                        self.phase = WriterPhase::Done;
                        return Poll::Ready(Ok(()));
                    }
                    Poll::Ready(Err(e)) => {
                        self.phase = WriterPhase::Poisoned;
                        return Poll::Ready(Err(e));
                    }
                },
                WriterPhase::Poisoned => {
                    return Poll::Ready(Err(io::Error::other("writer poisoned")));
                }
            }
        }
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        loop {
            match &mut self.phase {
                WriterPhase::Busy(fut) => match fut.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(core)) => {
                        self.phase = WriterPhase::Ready(Some(core));
                    }
                    Poll::Ready(Err(e)) => {
                        self.phase = WriterPhase::Poisoned;
                        return Poll::Ready(Err(e));
                    }
                },
                WriterPhase::Ready(opt_core) => {
                    let Some(mut core) = opt_core.take() else {
                        self.phase = WriterPhase::Done;
                        return Poll::Ready(Ok(()));
                    };
                    let state = self.state.clone();
                    let target_path = self.target_path.clone();
                    let obj_id = self.obj_id.clone();
                    let obj_path = self.obj_path.clone();
                    let tmp_path = self.tmp_path.clone();
                    let committed = self.committed.clone();
                    let fail_if_exists = self.mode == WriteMode::Create;

                    let fut = Box::pin(async move {
                        let plain_len = tokio::task::spawn_blocking(move || {
                            core.finalize_to_file(&tmp_path, &obj_path)
                        })
                        .await
                        .map_err(io::Error::other)??;
                        committed.store(true, Ordering::Release);
                        if let Err(e) = state
                            .commit_file_entry(&target_path, obj_id, plain_len, fail_if_exists)
                            .await
                        {
                            if matches!(e, VaultError::Vfs(VfsError::Backend { ref source, .. }) if source.kind() == io::ErrorKind::AlreadyExists)
                            {
                                return Err(io::Error::new(
                                    io::ErrorKind::AlreadyExists,
                                    "file already exists",
                                ));
                            }
                            return Err(io::Error::other(e.to_string()));
                        }
                        Ok(())
                    });
                    self.phase = WriterPhase::Committing(fut);
                }
                WriterPhase::Committing(fut) => match fut.as_mut().poll(cx) {
                    Poll::Pending => return Poll::Pending,
                    Poll::Ready(Ok(())) => {
                        self.phase = WriterPhase::Done;
                        return Poll::Ready(Ok(()));
                    }
                    Poll::Ready(Err(e)) => {
                        self.phase = WriterPhase::Poisoned;
                        return Poll::Ready(Err(e));
                    }
                },
                WriterPhase::Done => return Poll::Ready(Ok(())),
                WriterPhase::Poisoned => {
                    return Poll::Ready(Err(io::Error::other("writer poisoned")));
                }
            }
        }
    }
}

#[async_trait]
impl Vfs for VaultFs {
    fn capabilities(&self) -> Capabilities {
        Capabilities::READ_WRITE
    }

    fn prefers_direct_write(&self) -> bool {
        true
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let dek = self.state.current_dek(dir)?;
        let dir_tree = self.state.dir_tree.clone();
        let dir_clone = dir.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.list(&dir_clone, &dek)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: dir.clone(),
            source: io::Error::other(e),
        })?
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let dek = self.state.current_dek(path)?;
        let dir_tree = self.state.dir_tree.clone();
        let path_clone = path.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.stat(&path_clone, &dek)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })?
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        self.open_read_range(path, 0, None).await
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let dek = self.state.current_dek(path)?;
        let dir_tree = self.state.dir_tree.clone();
        let path_clone = path.clone();
        let dek_lookup = dek.clone();
        let child = tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.get_child(&path_clone, &dek_lookup)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })??
        .ok_or_else(|| VfsError::NotFound { path: path.clone() })?;

        if child.is_dir {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        let obj_id = child
            .obj_id
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })?;
        let obj_path = self.state.resolve_existing_obj_path(&obj_id);
        if !obj_path.exists() {
            return Err(VfsError::NotFound { path: path.clone() });
        }

        if !self.state.cipher.is_encrypted() {
            let mut f = tokio::fs::File::open(&obj_path)
                .await
                .map_err(|source| VfsError::Backend {
                    path: path.clone(),
                    source,
                })?;
            if offset > 0 {
                f.seek(std::io::SeekFrom::Start(offset))
                    .await
                    .map_err(|source| VfsError::Backend {
                        path: path.clone(),
                        source,
                    })?;
            }
            return Ok(match length {
                Some(len) => Box::new(f.take(len)),
                None => Box::new(f),
            });
        }

        Ok(open_fpv1_range_stream(
            obj_path,
            self.state.vault_id.clone(),
            dek,
            offset,
            length,
        ))
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        if path.is_root() {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        let dek = self.state.current_dek(path)?;
        let dir_tree = self.state.dir_tree.clone();
        let path_clone = path.clone();
        let dek_lookup = dek.clone();
        let (existing_obj, is_dir) = tokio::task::spawn_blocking(move || -> VfsResult<_> {
            let mut guard = dir_tree.lock();
            guard.ensure_parent_dir(&path_clone, &dek_lookup)?;
            match guard.get_child(&path_clone, &dek_lookup)? {
                Some(ch) => Ok((ch.obj_id, ch.is_dir)),
                None => Ok((None, false)),
            }
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })??;

        if is_dir {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::AlreadyExists, "destination is a directory"),
            });
        }
        if mode == WriteMode::Create && existing_obj.is_some() {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::AlreadyExists, "file already exists"),
            });
        }

        let obj_id = uuid::Uuid::new_v4().simple().to_string();
        let obj_path = self.state.obj_path(&obj_id);
        let tmp_path = obj_path.with_extension(format!(
            "{}.tmp",
            obj_path
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("part")
        ));

        let existing_path = if mode == WriteMode::Append {
            existing_obj.map(|id| self.state.resolve_existing_obj_path(&id))
        } else {
            None
        };

        let vault_id = self.state.vault_id.clone();
        let cipher = self.state.cipher;
        let tmp_for_block = tmp_path.clone();
        let core = tokio::task::spawn_blocking(move || -> VaultResult<WriterCore> {
            if let Some(parent) = tmp_for_block.parent() {
                ensure_private_bucket_dir(parent)?;
            }
            let init_res: VaultResult<WriterCore> = (|| {
                let mut core = if cipher.is_encrypted() {
                    let w = Fpv1SyncWriter::create(&tmp_for_block, &vault_id, &dek, cipher)?;
                    WriterCore {
                        backend: Some(BackendSyncWriter::Encrypted(w)),
                        pending_plain: Vec::new(),
                    }
                } else {
                    let mut opts = std::fs::OpenOptions::new();
                    opts.write(true).create(true).truncate(true);
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::OpenOptionsExt;
                        opts.mode(0o600);
                    }
                    let file = opts.open(&tmp_for_block)?;
                    WriterCore {
                        backend: Some(BackendSyncWriter::Plain { file, written: 0 }),
                        pending_plain: Vec::new(),
                    }
                };

                // Stream existing data chunk-by-chunk when appending (constant memory).
                if let Some(prev_path) = existing_path {
                    if prev_path.exists() {
                        let mut f = std::fs::File::open(&prev_path)?;
                        if cipher.is_encrypted() {
                            crate::crypto::stream_fpv1_to_writer(&mut f, &vault_id, &dek, |chunk| {
                                core.pending_plain.extend_from_slice(chunk);
                                while core.pending_plain.len() > CHUNK_SIZE {
                                    let head: Vec<u8> = core.pending_plain.drain(..CHUNK_SIZE).collect();
                                    core.write_non_final_chunk(&head)?;
                                }
                                Ok(())
                            })?;
                        } else {
                            let mut buf = vec![0u8; CHUNK_SIZE];
                            loop {
                                let n = f.read(&mut buf)?;
                                if n == 0 {
                                    break;
                                }
                                core.pending_plain.extend_from_slice(&buf[..n]);
                                while core.pending_plain.len() > CHUNK_SIZE {
                                    let head: Vec<u8> = core.pending_plain.drain(..CHUNK_SIZE).collect();
                                    core.write_non_final_chunk(&head)?;
                                }
                            }
                        }
                    }
                }
                Ok(core)
            })();
            if init_res.is_err() {
                let _ = std::fs::remove_file(&tmp_for_block);
            }
            init_res
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })?
        .map_err(|e| e.into_vfs(path))?;

        Ok(Box::new(VaultFileWriter {
            state: self.state.clone(),
            target_path: path.clone(),
            mode,
            obj_id,
            obj_path,
            tmp_path,
            committed: Arc::new(AtomicBool::new(false)),
            phase: WriterPhase::Ready(Some(core)),
        }))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        let _guard = self.state.write_lock.lock().await;
        let dek = self.state.current_dek(path)?;
        let dir_tree = self.state.dir_tree.clone();
        let path_clone = path.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.mkdir(&path_clone, &dek)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })?
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let _guard = self.state.write_lock.lock().await;
        let dek = self.state.current_dek(path)?;
        let dir_tree = self.state.dir_tree.clone();
        let path_clone = path.clone();
        let (objs, thumbs, dirs) = tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.remove(&path_clone, &dek)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: path.clone(),
            source: io::Error::other(e),
        })??;

        self.state
            .delete_orphaned_blobs_async(objs, thumbs, dirs)
            .await;
        Ok(())
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let _guard = self.state.write_lock.lock().await;
        let dek = self.state.current_dek(from)?;
        let dir_tree = self.state.dir_tree.clone();
        let from_clone = from.clone();
        let to_clone = to.clone();
        let (old_obj, old_thumb) = tokio::task::spawn_blocking(move || {
            let mut guard = dir_tree.lock();
            guard.rename(&from_clone, &to_clone, &dek)
        })
        .await
        .map_err(|e| VfsError::Backend {
            path: from.clone(),
            source: io::Error::other(e),
        })??;

        let objs: Vec<String> = old_obj.into_iter().collect();
        let thumbs: Vec<String> = old_thumb.into_iter().collect();
        self.state
            .delete_orphaned_blobs_async(objs, thumbs, Vec::new())
            .await;
        Ok(())
    }
}
