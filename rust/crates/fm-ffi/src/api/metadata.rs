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
    let t_dir = Path::new(db_path)
        .parent()
        .unwrap_or(Path::new("."))
        .join("trash");
    Database::open(Path::new(db_path), &t_dir).map_err(|e| e.to_string())
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

pub async fn move_to_trash(db_path: String, source_path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let src = PathBuf::from(&source_path);
    let meta = std::fs::symlink_metadata(&src).map_err(|e| e.to_string())?;
    let is_dir = meta.is_dir();
    let size = meta.len();

    let trash_dir = Path::new(&db_path)
        .parent()
        .unwrap_or(Path::new("."))
        .join("trash");
    std::fs::create_dir_all(&trash_dir).map_err(|e| e.to_string())?;

    let unique_name = Uuid::new_v4().to_string();
    let stored_dest = trash_dir.join(&unique_name);
    move_path(&src, &stored_dest).map_err(|e| e.to_string())?;

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

    db.add_trash_item(&item, size).map_err(|e| e.to_string())?;
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

        if original.exists() {
            return Err(format!(
                "destination already exists: {}",
                original.display()
            ));
        }

        if let Some(parent) = original.parent() {
            let _ = std::fs::create_dir_all(parent);
        }

        move_path(&stored, &original).map_err(|e| e.to_string())?;
        db.remove_trash_item(numeric_id).map_err(|e| e.to_string())?;
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
            let target = std::fs::read_link(src)?;
            if meta.is_dir() {
                std::os::windows::fs::symlink_dir(target, dst)?;
                std::fs::remove_dir(src)?;
            } else {
                std::os::windows::fs::symlink_file(target, dst)?;
                std::fs::remove_file(src)?;
            }
        }
    } else if meta.is_dir() {
        copy_dir_recursive(src, dst)?;
        std::fs::remove_dir_all(src)?;
    } else {
        std::fs::copy(src, dst)?;
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
                let target = std::fs::read_link(&src_child)?;
                if meta.is_dir() {
                    let _ = std::os::windows::fs::symlink_dir(target, &dst_child);
                } else {
                    let _ = std::os::windows::fs::symlink_file(target, &dst_child);
                }
            }
        } else if meta.is_dir() {
            copy_dir_recursive(&src_child, &dst_child)?;
        } else {
            std::fs::copy(&src_child, &dst_child)?;
        }
    }
    Ok(())
}

pub async fn delete_trash_item(db_path: String, id: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let numeric_id: i64 = id.parse().map_err(|_| "invalid trash id".to_string())?;
    if let Ok(Some(stored_path)) = db.remove_trash_item(numeric_id) {
        let stored = PathBuf::from(stored_path);
        if stored.is_dir() {
            let _ = std::fs::remove_dir_all(&stored);
        } else {
            let _ = std::fs::remove_file(&stored);
        }
    }
    Ok(())
}

pub async fn clear_trash(db_path: String) -> Result<(), String> {
    let db = open_db(&db_path)?;
    let list = db.list_trash().map_err(|e| e.to_string())?;
    for (id, item, _) in list {
        let stored = PathBuf::from(&item.stored_path);
        if stored.is_dir() {
            let _ = std::fs::remove_dir_all(&stored);
        } else {
            let _ = std::fs::remove_file(&stored);
        }
        let _ = db.remove_trash_item(id);
    }
    Ok(())
}
