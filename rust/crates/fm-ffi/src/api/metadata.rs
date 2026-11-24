use crate::registry::VfsRegistry;
use fm_core::{LocationId, VfsPath};
use fm_index::{Bookmark, Database, HistoryEntry, RecycleItem};
use std::path::{Path, PathBuf};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct BookmarkDto {
    pub id: String,
    pub name: String,
    pub root: String,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct HistoryDto {
    pub id: String,
    pub root: String,
    pub path: String,
    pub visited_millis: i64,
}

#[derive(Debug, Clone)]
pub struct TrashItemDto {
    pub id: String,
    pub original_path: String,
    pub deleted_millis: i64,
    pub size: u64,
    pub is_dir: bool,
}

fn open_db(db_path: &str) -> Result<Database, String> {
    crate::registry::VfsRegistry::global().open_database(db_path)
}

pub async fn add_bookmark(
    db_path: String,
    name: String,
    root: String,
    path: String,
) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let bm = Bookmark {
        location: LocationId(root),
        path: VfsPath::from_slash_path(&path),
        display_name: name,
    };
    db.add_bookmark(&bm).map_err(|e| e.to_string())
}

pub async fn list_bookmarks(db_path: String) -> Result<Vec<BookmarkDto>, String> {
    let db = open_db(&db_path)?;
    let list = db.list_bookmarks().map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|b| BookmarkDto {
            id: format!("{}:{}", b.location.0, b.path.to_slash_string()),
            name: b.display_name,
            root: b.location.0,
            path: b.path.to_slash_string(),
        })
        .collect())
}

pub async fn delete_bookmark(db_path: String, id: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    // id is `{root}:{path}` and the path always starts with '/', so the last
    // ":/" is the separator. Splitting on the first ':' would break roots that
    // contain one (`remote://id`, `C:\Users`).
    if let Some((root, path)) = id.rsplit_once(":/") {
        db.remove_bookmark(root, &format!("/{path}"))
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub async fn record_history(db_path: String, root: String, path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let entry = HistoryEntry {
        location: LocationId(root),
        path: VfsPath::from_slash_path(&path),
        visited_at_millis: now,
    };
    db.record_history(&entry).map_err(|e| e.to_string())
}

pub async fn list_history(db_path: String) -> Result<Vec<HistoryDto>, String> {
    let db = open_db(&db_path)?;
    let list = db.list_history(100).map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|h| HistoryDto {
            id: format!("{}:{}", h.location.0, h.path.to_slash_string()),
            root: h.location.0,
            path: h.path.to_slash_string(),
            visited_millis: h.visited_at_millis,
        })
        .collect())
}

pub async fn clear_history(db_path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    db.clear_history().map_err(|e| e.to_string())
}

pub async fn remove_history(db_path: String, root: String, path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    db.remove_history(&root, &path).map_err(|e| e.to_string())
}

pub async fn move_to_trash(db_path: String, source_path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let src = PathBuf::from(&source_path);
    // A cross-device move degrades to a recursive copy and can move GBs;
    // it must not block a tokio worker.
    let meta = tokio::task::spawn_blocking({
        let src = src.clone();
        move || std::fs::symlink_metadata(&src).map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())??;
    let is_dir = meta.is_dir();
    let size = meta.len();

    let trash_dir = Path::new(&db_path)
        .parent()
        .unwrap_or(Path::new("."))
        .join("trash");
    std::fs::create_dir_all(&trash_dir).map_err(|e| e.to_string())?;

    let unique_name = Uuid::new_v4().to_string();
    let stored_dest = trash_dir.join(&unique_name);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    let item = RecycleItem {
        location: LocationId(source_path.clone()),
        original_path: source_path.clone(),
        stored_path: stored_dest.to_string_lossy().into_owned(),
        deleted_at_millis: now,
    };

    // Record first, move second: a failed insert after the move left the
    // file stranded in the trash dir with no row pointing at it, i.e. the
    // user's file silently vanished. On a failed move, drop the row again.
    let id = db.add_trash_item(&item, size).map_err(|e| e.to_string())?;
    let move_result = tokio::task::spawn_blocking({
        let src = src.clone();
        let stored_dest = stored_dest.clone();
        move || move_path(&src, &stored_dest)
    })
    .await
    .map_err(|e| e.to_string())?;
    if let Err(e) = move_result {
        let _ = db.remove_trash_item(id);
        return Err(e.to_string());
    }
    super::file_manager::invalidate_local_dir_caches();
    let _ = is_dir;
    Ok(())
}

pub async fn list_trash(db_path: String) -> Result<Vec<TrashItemDto>, String> {
    let db = open_db(&db_path)?;
    let list = db.list_trash().map_err(|e| e.to_string())?;
    Ok(list
        .into_iter()
        .map(|(id, item, size)| {
            let stored = PathBuf::from(&item.stored_path);
            let is_dir = stored.is_dir();
            TrashItemDto {
                id: id.to_string(),
                original_path: item.original_path,
                deleted_millis: item.deleted_at_millis,
                size,
                is_dir,
            }
        })
        .collect())
}

pub async fn restore_trash_item(db_path: String, id: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let numeric_id: i64 = id.parse().map_err(|_| "invalid trash id".to_string())?;
    let list = db.list_trash().map_err(|e| e.to_string())?;
    if let Some((_, item, _)) = list.into_iter().find(|(item_id, _, _)| *item_id == numeric_id) {
        let stored = PathBuf::from(&item.stored_path);
        let original = PathBuf::from(&item.original_path);

        if std::fs::symlink_metadata(&original).is_ok() {
            return Err(format!(
                "destination already exists: {}",
                original.display()
            ));
        }

        if let Some(parent) = original.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        tokio::task::spawn_blocking({
            let stored = stored.clone();
            let original = original.clone();
            move || move_path(&stored, &original)
        })
        .await
        .map_err(|e| e.to_string())?
        .map_err(|e| e.to_string())?;
        db.remove_trash_item(numeric_id).map_err(|e| e.to_string())?;
        super::file_manager::invalidate_local_dir_caches();
    }
    Ok(())
}

fn move_path(src: &Path, dst: &Path) -> std::io::Result<()> {
    if std::fs::rename(src, dst).is_ok() {
        return Ok(());
    }
    let meta = std::fs::symlink_metadata(src)?;
    if meta.file_type().is_symlink() {
        #[cfg(unix)]
        {
            let target = std::fs::read_link(src)?;
            std::os::unix::fs::symlink(target, dst)?;
            std::fs::remove_file(src)?;
        }
        #[cfg(windows)]
        {
            use std::os::windows::fs::FileTypeExt;
            let target = std::fs::read_link(src)?;
            if meta.file_type().is_symlink_dir() {
                std::os::windows::fs::symlink_dir(target, dst)?;
                std::fs::remove_dir(src)?;
            } else {
                std::os::windows::fs::symlink_file(target, dst)?;
                std::fs::remove_file(src)?;
            }
        }
    } else if meta.is_dir() {
        if let Err(e) = copy_dir_recursive(src, dst) {
            let _ = std::fs::remove_dir_all(dst);
            return Err(e);
        }
        std::fs::remove_dir_all(src)?;
    } else {
        if let Err(e) = std::fs::copy(src, dst) {
            let _ = std::fs::remove_file(dst);
            return Err(e);
        }
        std::fs::remove_file(src)?;
    }
    Ok(())
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let src_child = entry.path();
        let dst_child = dst.join(entry.file_name());
        let meta = std::fs::symlink_metadata(&src_child)?;
        if meta.file_type().is_symlink() {
            #[cfg(unix)]
            {
                let target = std::fs::read_link(&src_child)?;
                std::os::unix::fs::symlink(target, &dst_child)?;
            }
            #[cfg(windows)]
            {
                use std::os::windows::fs::FileTypeExt;
                let target = std::fs::read_link(&src_child)?;
                if meta.file_type().is_symlink_dir() {
                    let _ = std::os::windows::fs::symlink_dir(target, &dst_child);
                } else {
                    let _ = std::os::windows::fs::symlink_file(target, &dst_child);
                }
            }
        } else if meta.is_dir() {
            copy_dir_recursive(&src_child, &dst_child)?;
        } else if meta.is_file() {
            std::fs::copy(&src_child, &dst_child)?;
        }
    }
    Ok(())
}

/// Deletes the stored payload of a trash entry.
///
/// A payload that is already gone counts as success; any other failure is
/// returned so the entry stays in the bin instead of silently vanishing from
/// the list while its bytes remain on disk.
fn remove_stored(stored: &Path) -> Result<(), String> {
    // symlink_metadata: `is_dir()` follows links, so a symlink pointing at
    // a directory took the remove_dir_all path, failed, and the entry could
    // never be deleted.
    let is_real_dir = std::fs::symlink_metadata(stored)
        .map(|m| m.is_dir())
        .unwrap_or(false);
    let result = if is_real_dir {
        std::fs::remove_dir_all(stored)
    } else {
        std::fs::remove_file(stored)
    };
    match result {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("cannot delete {}: {e}", stored.display())),
    }
}

pub async fn delete_trash_item(db_path: String, id: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let numeric_id: i64 = id.parse().map_err(|_| "invalid trash id".to_string())?;
    // Delete the payload first: the row is only dropped once the bytes are
    // gone, so a failed delete leaves the item visible and retryable.
    let list = db.list_trash().map_err(|e| e.to_string())?;
    if let Some((_, item, _)) = list.into_iter().find(|(item_id, _, _)| *item_id == numeric_id) {
        remove_stored(Path::new(&item.stored_path))?;
    }
    db.remove_trash_item(numeric_id).map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn clear_trash(db_path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let list = db.list_trash().map_err(|e| e.to_string())?;
    let mut failures = Vec::new();
    for (id, item, _) in list {
        let stored = PathBuf::from(&item.stored_path);
        match remove_stored(&stored) {
            Ok(()) => {
                let _ = db.remove_trash_item(id);
            }
            Err(e) => failures.push(e),
        }
    }
    if failures.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "{} item(s) could not be deleted: {}",
            failures.len(),
            failures.join("; ")
        ))
    }
}

#[derive(Debug, Clone)]
pub struct PinnedFileDto {
    pub id: i64,
    pub remote_root: String,
    pub remote_path: String,
    pub display_name: String,
    pub local_cache_path: String,
    pub size: u64,
    pub modified_millis: Option<i64>,
    pub pinned_at: i64,
    pub last_accessed_at: i64,
    pub local_exists: bool,
}

impl From<fm_index::PinnedFileRecord> for PinnedFileDto {
    fn from(r: fm_index::PinnedFileRecord) -> Self {
        let local_exists = Path::new(&r.local_cache_path).is_file();
        Self {
            id: r.id,
            remote_root: r.remote_root,
            remote_path: r.remote_path,
            display_name: r.display_name,
            local_cache_path: r.local_cache_path,
            size: r.size,
            modified_millis: r.modified_millis,
            pinned_at: r.pinned_at,
            last_accessed_at: r.last_accessed_at,
            local_exists,
        }
    }
}

/// List all remote files pinned for offline access.
#[flutter_rust_bridge::frb(sync)]
pub fn list_pinned_files(db_path: String) -> Result<Vec<PinnedFileDto>, String> {
    let db = open_db(&db_path)?;
    let list = db.list_pinned_files().map_err(|e| e.to_string())?;
    Ok(list.into_iter().map(PinnedFileDto::from).collect())
}

/// Download/sync a remote file into the managed offline cache and record it as
/// pinned. Optionally enforces an LRU size budget (`max_cache_bytes`).
pub async fn pin_remote_file(
    db_path: String,
    remote_root: String,
    remote_path: String,
    max_cache_bytes: Option<u64>,
) -> Result<PinnedFileDto, String> {
    if remote_root.starts_with("vault://") || remote_root.starts_with("archive://vault://") {
        return Err("privacy vault files cannot be cached plaintext for offline pin".to_string());
    }
    let db = open_db(&db_path)?;
    let backend = VfsRegistry::global().get_or_create(&remote_root).await?;
    let vfs_path = VfsPath::from_slash_path(&remote_path);
    let stat = backend.stat(&vfs_path).await.map_err(|e| e.to_string())?;
    let display_name = stat.name.clone();
    let modified_millis = stat
        .modified
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64);

    // Deterministic hashed filename inside offline_cache/ preserving extension.
    let cache_dir = db.offline_cache_dir();
    let mut hasher = sha2::Sha256::new();
    use sha2::Digest as _;
    hasher.update(remote_root.as_bytes());
    hasher.update(b"::");
    hasher.update(remote_path.as_bytes());
    let key = hex::encode(&hasher.finalize()[..12]);
    let ext = Path::new(&display_name)
        .extension()
        .and_then(|e| e.to_str())
        .filter(|e| e.len() <= 12 && e.chars().all(|c| c.is_ascii_alphanumeric()))
        .map(|e| format!(".{e}"))
        .unwrap_or_default();
    let local_path = cache_dir.join(format!("{key}{ext}"));
    let tmp_path = cache_dir.join(format!(".{key}.{}.part", uuid::Uuid::new_v4()));

    let mut reader = backend.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
    let mut out = tokio::fs::File::create(&tmp_path)
        .await
        .map_err(|e| e.to_string())?;
    let copied = tokio::io::copy(&mut reader, &mut out)
        .await
        .map_err(|e| {
            let _ = std::fs::remove_file(&tmp_path);
            e.to_string()
        })?;
    tokio::io::AsyncWriteExt::flush(&mut out)
        .await
        .map_err(|e| e.to_string())?;
    drop(out);
    if tokio::fs::try_exists(&local_path).await.unwrap_or(false) {
        let _ = tokio::fs::remove_file(&local_path).await;
    }
    tokio::fs::rename(&tmp_path, &local_path)
        .await
        .map_err(|e| {
            let _ = std::fs::remove_file(&tmp_path);
            e.to_string()
        })?;

    let local_str = local_path.to_string_lossy().to_string();
    if let Some(limit) = max_cache_bytes {
        if limit > 0 {
            let budget_for_existing = limit.saturating_sub(copied);
            if let Ok(evicted) = db.evict_pinned_lru(budget_for_existing) {
                for p in evicted {
                    if p != local_str {
                        let _ = std::fs::remove_file(p);
                    }
                }
            }
        }
    }

    db.upsert_pinned_file(
        &remote_root,
        &remote_path,
        &display_name,
        &local_str,
        copied,
        modified_millis,
    )
    .map_err(|e| e.to_string())?;

    let record = db
        .touch_pinned_file(&remote_root, &remote_path)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "failed to read back pinned file".to_string())?;
    Ok(PinnedFileDto::from(record))
}

/// Remove a file from offline pins and delete its local cached copy.
#[flutter_rust_bridge::frb(sync)]
pub fn unpin_remote_file(
    db_path: String,
    remote_root: String,
    remote_path: String,
) -> Result<bool, String> {
    let db = open_db(&db_path)?;
    if let Some(local_path) = db
        .remove_pinned_file(&remote_root, &remote_path)
        .map_err(|e| e.to_string())?
    {
        let _ = std::fs::remove_file(local_path);
        Ok(true)
    } else {
        Ok(false)
    }
}

/// Touch a pinned file (updating LRU timestamp) and return its local path if cached.
#[flutter_rust_bridge::frb(sync)]
pub fn get_pinned_local_path(
    db_path: String,
    remote_root: String,
    remote_path: String,
) -> Result<Option<String>, String> {
    let db = open_db(&db_path)?;
    if let Some(rec) = db
        .touch_pinned_file(&remote_root, &remote_path)
        .map_err(|e| e.to_string())?
    {
        if Path::new(&rec.local_cache_path).is_file() {
            return Ok(Some(rec.local_cache_path));
        }
    }
    Ok(None)
}

/// Evict least-recently-used offline pinned files until total size <= `max_bytes`.
#[flutter_rust_bridge::frb(sync)]
pub fn evict_pinned_cache(db_path: String, max_bytes: u64) -> Result<u32, String> {
    let db = open_db(&db_path)?;
    let evicted = db.evict_pinned_lru(max_bytes).map_err(|e| e.to_string())?;
    let count = evicted.len() as u32;
    for path in evicted {
        let _ = std::fs::remove_file(path);
    }
    Ok(count)
}

/// Reports whether at-rest credential encryption in SQLite (`fm-index`) is backed
/// by an active keyring or persisted master key rather than plaintext fallback.
#[flutter_rust_bridge::frb(sync)]
pub fn is_secret_encryption_active(db_path: String) -> bool {
    let data_dir = Path::new(&db_path)
        .parent()
        .unwrap_or_else(|| Path::new("."));
    fm_index::secret::is_encryption_active_for_dir(data_dir)
}

#[derive(Debug, Clone)]
pub struct PinnedSyncStatusDto {
    /// `"synced"`, `"remote_newer"`, `"local_modified"`, `"conflict"`,
    /// `"missing_local"`, or `"remote_error"`.
    pub status: String,
    pub remote_size: Option<u64>,
    pub remote_modified_millis: Option<i64>,
    pub local_size: Option<u64>,
    pub local_modified_millis: Option<i64>,
    pub detail: Option<String>,
}

/// Compare an offline-pinned file's local cached copy against its remote source.
pub async fn check_pinned_file_status(
    db_path: String,
    remote_root: String,
    remote_path: String,
) -> Result<PinnedSyncStatusDto, String> {
    let db = open_db(&db_path)?;
    let rec = db
        .list_pinned_files()
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|r| r.remote_root == remote_root && r.remote_path == remote_path)
        .ok_or_else(|| "pinned record not found".to_string())?;

    let local_meta = tokio::fs::metadata(&rec.local_cache_path).await.ok();
    let Some(local_meta) = local_meta else {
        return Ok(PinnedSyncStatusDto {
            status: "missing_local".to_string(),
            remote_size: Some(rec.size),
            remote_modified_millis: rec.modified_millis,
            local_size: None,
            local_modified_millis: None,
            detail: None,
        });
    };

    let local_size = local_meta.len();
    let local_mtime = local_meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64);
    let local_changed = local_size != rec.size
        || local_mtime
            .map(|m| m > rec.pinned_at.saturating_add(2000))
            .unwrap_or(false);

    let backend = match VfsRegistry::global().get_or_create(&remote_root).await {
        Ok(b) => b,
        Err(e) => {
            return Ok(PinnedSyncStatusDto {
                status: "remote_error".to_string(),
                remote_size: Some(rec.size),
                remote_modified_millis: rec.modified_millis,
                local_size: Some(local_size),
                local_modified_millis: local_mtime,
                detail: Some(e),
            });
        }
    };
    let vfs_path = VfsPath::from_slash_path(&remote_path);
    let remote_stat = match backend.stat(&vfs_path).await {
        Ok(s) => s,
        Err(e) => {
            return Ok(PinnedSyncStatusDto {
                status: "remote_error".to_string(),
                remote_size: Some(rec.size),
                remote_modified_millis: rec.modified_millis,
                local_size: Some(local_size),
                local_modified_millis: local_mtime,
                detail: Some(e.to_string()),
            });
        }
    };

    let remote_size = remote_stat.size;
    let remote_mtime = remote_stat
        .modified
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64);
    let remote_changed = remote_size.map(|sz| sz != rec.size).unwrap_or(false)
        || match (remote_mtime, rec.modified_millis) {
            (Some(rm), Some(pinned_rm)) => (rm - pinned_rm).abs() > 2000,
            _ => false,
        };

    let status = match (local_changed, remote_changed) {
        (true, true) => "conflict",
        (true, false) => "local_modified",
        (false, true) => "remote_newer",
        (false, false) => "synced",
    };

    Ok(PinnedSyncStatusDto {
        status: status.to_string(),
        remote_size,
        remote_modified_millis: remote_mtime,
        local_size: Some(local_size),
        local_modified_millis: local_mtime,
        detail: None,
    })
}

/// Write a locally edited offline-pinned copy back to the remote location and
/// refresh the pinned baseline metadata.
pub async fn push_pinned_file(
    db_path: String,
    remote_root: String,
    remote_path: String,
) -> Result<PinnedFileDto, String> {
    let db = open_db(&db_path)?;
    let rec = db
        .list_pinned_files()
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|r| r.remote_root == remote_root && r.remote_path == remote_path)
        .ok_or_else(|| "pinned record not found".to_string())?;

    let backend = VfsRegistry::global().get_or_create(&remote_root).await?;
    let vfs_path = VfsPath::from_slash_path(&remote_path);
    let mut reader = tokio::fs::File::open(&rec.local_cache_path)
        .await
        .map_err(|e| e.to_string())?;
    let mut writer = backend
        .open_write(&vfs_path, fm_core::WriteMode::Truncate)
        .await
        .map_err(|e| e.to_string())?;
    let written = tokio::io::copy(&mut reader, &mut writer)
        .await
        .map_err(|e| e.to_string())?;
    tokio::io::AsyncWriteExt::shutdown(&mut writer)
        .await
        .map_err(|e| e.to_string())?;

    let remote_mtime = backend
        .stat(&vfs_path)
        .await
        .ok()
        .and_then(|s| s.modified)
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64);

    db.upsert_pinned_file(
        &remote_root,
        &remote_path,
        &rec.display_name,
        &rec.local_cache_path,
        written,
        remote_mtime,
    )
    .map_err(|e| e.to_string())?;

    crate::api::file_manager::invalidate_dir_cache(&remote_root);
    let updated = db
        .touch_pinned_file(&remote_root, &remote_path)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "failed to read back pushed pinned file".to_string())?;
    Ok(PinnedFileDto::from(updated))
}

/// Encrypt a cross-device migration JSON bundle (remote connections, bookmarks,
/// preferences) with Argon2id + AES-256-GCM.
#[flutter_rust_bridge::frb(sync)]
pub fn encrypt_migration_bundle(plaintext_json: String, password: String) -> Result<String, String> {
    let (salt_b64, nonce_b64, ct_b64) =
        fm_vault::crypto::encrypt_portable_secret(plaintext_json.as_bytes(), &password)
            .map_err(|e| e.to_string())?;
    let envelope = serde_json::json!({
        "format": "fp-migration-v1",
        "salt": salt_b64,
        "nonce": nonce_b64,
        "ciphertext": ct_b64,
    });
    serde_json::to_string_pretty(&envelope).map_err(|e| e.to_string())
}

/// Decrypt an encrypted cross-device migration bundle produced by
/// [`encrypt_migration_bundle`].
#[flutter_rust_bridge::frb(sync)]
pub fn decrypt_migration_bundle(envelope_json: String, password: String) -> Result<String, String> {
    let val: serde_json::Value =
        serde_json::from_str(&envelope_json).map_err(|e| format!("invalid migration JSON: {e}"))?;
    let fmt = val.get("format").and_then(|v| v.as_str()).unwrap_or("");
    if fmt != "fp-migration-v1" {
        return Err("unsupported migration bundle format".to_string());
    }
    let salt_b64 = val
        .get("salt")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "missing migration salt".to_string())?;
    let nonce_b64 = val
        .get("nonce")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "missing migration nonce".to_string())?;
    let ct_b64 = val
        .get("ciphertext")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "missing migration ciphertext".to_string())?;
    let pt = fm_vault::crypto::decrypt_portable_secret(salt_b64, nonce_b64, ct_b64, &password)
        .map_err(|_| "incorrect password or corrupted migration bundle".to_string())?;
    String::from_utf8(pt).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migration_bundle_encrypts_decrypts_and_rejects_wrong_password() {
        let payload = r#"{"version":2,"remotes":[{"id":"r1","password":"secret"}],"bookmarks":[]}"#;
        let envelope = encrypt_migration_bundle(payload.to_string(), "correct-horse-99".into())
            .expect("encrypt migration bundle");
        assert!(!envelope.contains("secret"));
        assert!(envelope.contains("fp-migration-v1"));

        let decrypted =
            decrypt_migration_bundle(envelope.clone(), "correct-horse-99".into()).expect("decrypt");
        assert_eq!(decrypted, payload);

        let err = decrypt_migration_bundle(envelope, "wrong-password".into()).unwrap_err();
        assert!(err.contains("incorrect password"), "{err}");
    }
}
