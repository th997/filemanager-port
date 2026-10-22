//! SQLite storage engine for persistent metadata.

use fm_core::{LocationId, VfsPath};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::{Bookmark, HistoryEntry, RecycleItem};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteRecord {
    pub id: String,
    pub kind: String,
    pub display_name: String,
    pub config_json: String,
    pub created_at: i64,
}

/// Serialize a path for the bookmarks/history tables.
///
/// The segments are stored as a JSON array. The previous format — the
/// flattened slash string — cannot be parsed back unambiguously: fm-core
/// deliberately allows '/', '\\' and ':' inside a single file name, so a
/// name like "a/b" came back as two segments and the stored entry
/// silently pointed at a different path.
fn encode_path(path: &VfsPath) -> String {
    serde_json::to_string(path.segments()).unwrap_or_else(|_| path.to_slash_string())
}

/// Inverse of [`encode_path`], with a fallback for rows written in the
/// old slash format (only the JSON form starts with '[').
fn decode_path(stored: &str) -> VfsPath {
    if stored.starts_with('[') {
        if let Ok(segments) = serde_json::from_str::<Vec<String>>(stored) {
            return segments
                .iter()
                .fold(VfsPath::root(), |p, s| p.join(s.clone()));
        }
    }
    VfsPath::from_slash_path(stored)
}

#[derive(Clone)]
pub struct Database {
    conn: Arc<Mutex<Connection>>,
    trash_dir: PathBuf,
}

impl Database {
    pub fn open(db_path: impl AsRef<Path>, trash_dir: impl AsRef<Path>) -> Result<Self, rusqlite::Error> {
        let conn = Connection::open(db_path.as_ref())?;
        let trash_path = trash_dir.as_ref().to_path_buf();
        let _ = std::fs::create_dir_all(&trash_path);

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            trash_dir: trash_path,
        };
        db.init_tables()?;
        Ok(db)
    }

    pub fn in_memory(trash_dir: impl AsRef<Path>) -> Result<Self, rusqlite::Error> {
        let conn = Connection::open_in_memory()?;
        let trash_path = trash_dir.as_ref().to_path_buf();
        let _ = std::fs::create_dir_all(&trash_path);

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            trash_dir: trash_path,
        };
        db.init_tables()?;
        Ok(db)
    }

    pub fn trash_dir(&self) -> &Path {
        &self.trash_dir
    }

    fn init_tables(&self) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS remotes (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                display_name TEXT NOT NULL,
                config_json TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS bookmarks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location TEXT NOT NULL,
                path TEXT NOT NULL,
                display_name TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                UNIQUE(location, path)
            );

            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location TEXT NOT NULL,
                path TEXT NOT NULL,
                visited_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS recycle_bin (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location TEXT NOT NULL,
                original_path TEXT NOT NULL,
                stored_path TEXT NOT NULL,
                size INTEGER NOT NULL,
                deleted_at INTEGER NOT NULL
            );
            ",
        )?;
        Ok(())
    }

    // Remotes CRUD
    pub fn save_remote(&self, remote: &RemoteRecord) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "INSERT OR REPLACE INTO remotes (id, kind, display_name, config_json, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                remote.id,
                remote.kind,
                remote.display_name,
                remote.config_json,
                remote.created_at
            ],
        )?;
        Ok(())
    }

    pub fn list_remotes(&self) -> Result<Vec<RemoteRecord>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT id, kind, display_name, config_json, created_at FROM remotes ORDER BY created_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(RemoteRecord {
                id: row.get(0)?,
                kind: row.get(1)?,
                display_name: row.get(2)?,
                config_json: row.get(3)?,
                created_at: row.get(4)?,
            })
        })?;

        let mut remotes = Vec::new();
        for r in rows {
            remotes.push(r?);
        }
        Ok(remotes)
    }

    pub fn delete_remote(&self, id: &str) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute("DELETE FROM remotes WHERE id = ?1", params![id])?;
        Ok(())
    }

    // Bookmarks CRUD
    pub fn add_bookmark(&self, bookmark: &Bookmark) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;

        conn.execute(
            "INSERT OR REPLACE INTO bookmarks (location, path, display_name, created_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![
                bookmark.location.0,
                encode_path(&bookmark.path),
                bookmark.display_name,
                now
            ],
        )?;
        Ok(())
    }

    pub fn list_bookmarks(&self) -> Result<Vec<Bookmark>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT location, path, display_name FROM bookmarks ORDER BY created_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            let loc: String = row.get(0)?;
            let p: String = row.get(1)?;
            let name: String = row.get(2)?;
            Ok(Bookmark {
                location: LocationId(loc),
                path: decode_path(&p),
                display_name: name,
            })
        })?;

        let mut list = Vec::new();
        for item in rows {
            list.push(item?);
        }
        Ok(list)
    }

    pub fn remove_bookmark(&self, location: &str, path: &str) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        // Callers identify the row by its slash form; match both the old
        // slash representation and the current JSON one.
        conn.execute(
            "DELETE FROM bookmarks WHERE location = ?1 AND (path = ?2 OR path = ?3)",
            params![location, path, encode_path(&VfsPath::from_slash_path(path))],
        )?;
        Ok(())
    }

    // History
    pub fn record_history(&self, entry: &HistoryEntry) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        // Revisiting a folder moves its existing row instead of appending a
        // duplicate, so Recent shows each location once, most recent first.
        conn.execute(
            "DELETE FROM history WHERE location = ?1 AND (path = ?2 OR path = ?3)",
            params![
                entry.location.0,
                entry.path.to_slash_string(),
                encode_path(&entry.path)
            ],
        )?;
        conn.execute(
            "INSERT INTO history (location, path, visited_at) VALUES (?1, ?2, ?3)",
            params![
                entry.location.0,
                encode_path(&entry.path),
                entry.visited_at_millis
            ],
        )?;

        // Keep LRU max 100 entries
        let count: i64 = conn.query_row("SELECT COUNT(*) FROM history", [], |r| r.get(0))?;
        if count > 100 {
            conn.execute(
                "DELETE FROM history WHERE id IN (SELECT id FROM history ORDER BY visited_at ASC LIMIT ?1)",
                params![count - 100],
            )?;
        }

        Ok(())
    }

    pub fn list_history(&self, limit: usize) -> Result<Vec<HistoryEntry>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT location, path, visited_at FROM history ORDER BY visited_at DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map(params![limit as i64], |row| {
            let loc: String = row.get(0)?;
            let p: String = row.get(1)?;
            let time: i64 = row.get(2)?;
            Ok(HistoryEntry {
                location: LocationId(loc),
                path: decode_path(&p),
                visited_at_millis: time,
            })
        })?;

        let mut list = Vec::new();
        for item in rows {
            list.push(item?);
        }
        Ok(list)
    }

    /// Drops one history row, so a stale entry can be removed without
    /// clearing everything else.
    pub fn remove_history(&self, location: &str, path: &str) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "DELETE FROM history WHERE location = ?1 AND (path = ?2 OR path = ?3)",
            params![location, path, encode_path(&VfsPath::from_slash_path(path))],
        )?;
        Ok(())
    }

    pub fn clear_history(&self) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute("DELETE FROM history", [])?;
        Ok(())
    }

    // Recycle bin
    pub fn add_trash_item(&self, item: &RecycleItem, size: u64) -> Result<i64, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "INSERT INTO recycle_bin (location, original_path, stored_path, size, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                item.location.0,
                item.original_path,
                item.stored_path,
                size as i64,
                item.deleted_at_millis
            ],
        )?;
        Ok(conn.last_insert_rowid())
    }

    pub fn list_trash(&self) -> Result<Vec<(i64, RecycleItem, u64)>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT id, location, original_path, stored_path, size, deleted_at FROM recycle_bin ORDER BY deleted_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            let id: i64 = row.get(0)?;
            let loc: String = row.get(1)?;
            let orig: String = row.get(2)?;
            let stored: String = row.get(3)?;
            let size: i64 = row.get(4)?;
            let deleted: i64 = row.get(5)?;

            Ok((
                id,
                RecycleItem {
                    location: LocationId(loc),
                    original_path: orig,
                    stored_path: stored,
                    deleted_at_millis: deleted,
                },
                size as u64,
            ))
        })?;

        let mut list = Vec::new();
        for item in rows {
            list.push(item?);
        }
        Ok(list)
    }

    pub fn remove_trash_item(&self, id: i64) -> Result<Option<String>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let stored_path: Option<String> = conn
            .query_row(
                "SELECT stored_path FROM recycle_bin WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )
            .ok();

        conn.execute("DELETE FROM recycle_bin WHERE id = ?1", params![id])?;
        Ok(stored_path)
    }

    pub fn clear_trash(&self) -> Result<Vec<String>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare("SELECT stored_path FROM recycle_bin")?;
        let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
        let mut paths = Vec::new();
        for p in rows {
            paths.push(p?);
        }
        conn.execute("DELETE FROM recycle_bin", [])?;
        Ok(paths)
    }
}
