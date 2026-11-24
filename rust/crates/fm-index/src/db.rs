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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PinnedFileRecord {
    pub id: i64,
    pub remote_root: String,
    pub remote_path: String,
    pub display_name: String,
    pub local_cache_path: String,
    pub size: u64,
    pub modified_millis: Option<i64>,
    pub pinned_at: i64,
    pub last_accessed_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IndexedFileRecord {
    pub root: String,
    pub path: String,
    pub name: String,
    pub ext: String,
    pub category: String,
    pub is_dir: bool,
    pub size: u64,
    pub modified_millis: Option<i64>,
    pub hidden: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IndexStatsRecord {
    pub root: String,
    pub entry_count: u64,
    pub updated_at_millis: i64,
}

fn current_epoch_millis() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Convert raw query text into an FTS5 `MATCH` expression of quoted prefix tokens.
/// Returns `None` if no searchable alphanumeric tokens exist.
fn build_fts5_match_expr(query: &str) -> Option<String> {
    let mut parts = Vec::new();
    for token in query.split(|c: char| !c.is_alphanumeric()) {
        let trimmed = token.trim();
        if trimmed.is_empty() {
            continue;
        }
        let escaped = trimmed.replace('"', "\"\"");
        parts.push(format!("\"{escaped}\"*"));
        if parts.len() >= 16 {
            break;
        }
    }
    if parts.is_empty() {
        None
    } else {
        Some(parts.join(" AND "))
    }
}

fn escape_sql_like(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '\\' | '%' | '_' => {
                out.push('\\');
                out.push(ch);
            }
            other => out.push(other),
        }
    }
    out
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
            return VfsPath::new(segments);
        }
    }
    VfsPath::from_slash_path(stored)
}

fn is_sqlite_busy(err: &rusqlite::Error) -> bool {
    matches!(
        err,
        rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error {
                code: rusqlite::ErrorCode::DatabaseBusy | rusqlite::ErrorCode::DatabaseLocked,
                ..
            },
            _
        )
    )
}

#[derive(Clone)]
pub struct Database {
    conn: Arc<Mutex<Connection>>,
    trash_dir: PathBuf,
    /// Directory holding the database file; the credential master key
    /// fallback file lives here too.
    data_dir: PathBuf,
}

impl Database {
    pub fn open(db_path: impl AsRef<Path>, trash_dir: impl AsRef<Path>) -> Result<Self, rusqlite::Error> {
        let db_path = db_path.as_ref();
        if let Some(parent) = db_path.parent() {
            if !parent.as_os_str().is_empty() {
                let _ = std::fs::create_dir_all(parent);
            }
        }
        let conn = Connection::open(db_path)?;
        conn.busy_timeout(std::time::Duration::from_secs(10))?;
        let trash_path = trash_dir.as_ref().to_path_buf();
        let _ = std::fs::create_dir_all(&trash_path);
        let data_dir = db_path
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from("."));

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            trash_dir: trash_path,
            data_dir,
        };
        db.init_tables(true)?;
        Ok(db)
    }

    pub fn in_memory(trash_dir: impl AsRef<Path>) -> Result<Self, rusqlite::Error> {
        let conn = Connection::open_in_memory()?;
        let trash_path = trash_dir.as_ref().to_path_buf();
        let _ = std::fs::create_dir_all(&trash_path);

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            data_dir: trash_path.clone(),
            trash_dir: trash_path,
        };
        db.init_tables(false)?;
        Ok(db)
    }

    pub fn trash_dir(&self) -> &Path {
        &self.trash_dir
    }

    fn init_tables(&self, enable_wal: bool) -> Result<(), rusqlite::Error> {
        const MAX_ATTEMPTS: usize = 20;
        for attempt in 0..MAX_ATTEMPTS {
            let res = {
                let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
                let mut inner_res = Ok(());
                if enable_wal {
                    let current_mode: Result<String, _> =
                        conn.query_row("PRAGMA journal_mode;", [], |row| row.get(0));
                    match current_mode {
                        Ok(mode) if mode.eq_ignore_ascii_case("wal") => {}
                        Ok(_) => {
                            if let Err(e) = conn.execute_batch("PRAGMA journal_mode = WAL;") {
                                inner_res = Err(e);
                            }
                        }
                        Err(e) => {
                            inner_res = Err(e);
                        }
                    }
                }
                if inner_res.is_ok() {
                    inner_res = conn.execute_batch(
                        "
                        PRAGMA synchronous = NORMAL;
                        PRAGMA cache_size = -2000;
                        PRAGMA temp_store = MEMORY;

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

                        CREATE TABLE IF NOT EXISTS pinned_files (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            remote_root TEXT NOT NULL,
                            remote_path TEXT NOT NULL,
                            display_name TEXT NOT NULL,
                            local_cache_path TEXT NOT NULL,
                            size INTEGER NOT NULL,
                            modified_millis INTEGER,
                            pinned_at INTEGER NOT NULL,
                            last_accessed_at INTEGER NOT NULL,
                            UNIQUE(remote_root, remote_path)
                        );

                        CREATE INDEX IF NOT EXISTS idx_history_loc_path ON history(location, path);
                        CREATE INDEX IF NOT EXISTS idx_history_visited ON history(visited_at);
                        CREATE INDEX IF NOT EXISTS idx_bookmarks_loc_path ON bookmarks(location, path);
                        CREATE INDEX IF NOT EXISTS idx_recycle_bin_deleted ON recycle_bin(deleted_at);
                        CREATE INDEX IF NOT EXISTS idx_pinned_lru ON pinned_files(last_accessed_at);

                        CREATE TABLE IF NOT EXISTS indexed_roots (
                            root TEXT PRIMARY KEY,
                            entry_count INTEGER NOT NULL,
                            updated_at INTEGER NOT NULL
                        );

                        CREATE VIRTUAL TABLE IF NOT EXISTS file_index_fts USING fts5(
                            root UNINDEXED,
                            path,
                            name,
                            ext UNINDEXED,
                            category UNINDEXED,
                            is_dir UNINDEXED,
                            size UNINDEXED,
                            modified_millis UNINDEXED,
                            hidden UNINDEXED,
                            tokenize='unicode61'
                        );
                        ",
                    );
                }
                inner_res
            };

            match res {
                Ok(()) => return Ok(()),
                Err(e) if is_sqlite_busy(&e) && attempt + 1 < MAX_ATTEMPTS => {
                    let delay_ms = ((attempt as u64 + 1) * 25).min(100);
                    std::thread::sleep(std::time::Duration::from_millis(delay_ms));
                }
                Err(e) => return Err(e),
            }
        }
        unreachable!()
    }

    // Remotes CRUD
    pub fn save_remote(&self, remote: &RemoteRecord) -> Result<(), rusqlite::Error> {
        // Configs carry credentials: never write them to disk in plain
        // text (see crate::secret). Legacy rows are upgraded here too —
        // any save rewrites the row encrypted.
        let stored = crate::secret::encrypt_config(&remote.config_json, &self.data_dir);
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "INSERT OR REPLACE INTO remotes (id, kind, display_name, config_json, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                remote.id,
                remote.kind,
                remote.display_name,
                stored,
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
            let mut record = r?;
            record.config_json =
                crate::secret::decrypt_config(&record.config_json, &self.data_dir);
            remotes.push(record);
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
        let mut conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let tx = conn.transaction()?;
        // Revisiting a folder moves its existing row instead of appending a
        // duplicate, so Recent shows each location once, most recent first.
        tx.execute(
            "DELETE FROM history WHERE location = ?1 AND (path = ?2 OR path = ?3)",
            params![
                entry.location.0,
                entry.path.to_slash_string(),
                encode_path(&entry.path)
            ],
        )?;
        tx.execute(
            "INSERT INTO history (location, path, visited_at) VALUES (?1, ?2, ?3)",
            params![
                entry.location.0,
                encode_path(&entry.path),
                entry.visited_at_millis
            ],
        )?;

        // Keep LRU max 100 entries via single index-backed subquery
        tx.execute(
            "DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited_at DESC LIMIT 100)",
            [],
        )?;

        tx.commit()?;
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

    // Offline Pinned Files CRUD & LRU eviction
    pub fn offline_cache_dir(&self) -> PathBuf {
        let dir = self.data_dir.join("offline_cache");
        let _ = std::fs::create_dir_all(&dir);
        dir
    }

    pub fn upsert_pinned_file(
        &self,
        remote_root: &str,
        remote_path: &str,
        display_name: &str,
        local_cache_path: &str,
        size: u64,
        modified_millis: Option<i64>,
    ) -> Result<(), rusqlite::Error> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "INSERT INTO pinned_files
                (remote_root, remote_path, display_name, local_cache_path, size, modified_millis, pinned_at, last_accessed_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
             ON CONFLICT(remote_root, remote_path) DO UPDATE SET
                display_name = excluded.display_name,
                local_cache_path = excluded.local_cache_path,
                size = excluded.size,
                modified_millis = excluded.modified_millis,
                pinned_at = excluded.pinned_at,
                last_accessed_at = excluded.last_accessed_at",
            params![
                remote_root,
                remote_path,
                display_name,
                local_cache_path,
                size as i64,
                modified_millis,
                now
            ],
        )?;
        Ok(())
    }

    pub fn list_pinned_files(&self) -> Result<Vec<PinnedFileRecord>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT id, remote_root, remote_path, display_name, local_cache_path, size, modified_millis, pinned_at, last_accessed_at
             FROM pinned_files ORDER BY last_accessed_at DESC",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(PinnedFileRecord {
                id: r.get(0)?,
                remote_root: r.get(1)?,
                remote_path: r.get(2)?,
                display_name: r.get(3)?,
                local_cache_path: r.get(4)?,
                size: r.get::<_, i64>(5)?.max(0) as u64,
                modified_millis: r.get(6)?,
                pinned_at: r.get(7)?,
                last_accessed_at: r.get(8)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    pub fn touch_pinned_file(
        &self,
        remote_root: &str,
        remote_path: &str,
    ) -> Result<Option<PinnedFileRecord>, rusqlite::Error> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        conn.execute(
            "UPDATE pinned_files SET last_accessed_at = ?1 WHERE remote_root = ?2 AND remote_path = ?3",
            params![now, remote_root, remote_path],
        )?;
        let res = conn
            .query_row(
                "SELECT id, remote_root, remote_path, display_name, local_cache_path, size, modified_millis, pinned_at, last_accessed_at
                 FROM pinned_files WHERE remote_root = ?1 AND remote_path = ?2",
                params![remote_root, remote_path],
                |r| {
                    Ok(PinnedFileRecord {
                        id: r.get(0)?,
                        remote_root: r.get(1)?,
                        remote_path: r.get(2)?,
                        display_name: r.get(3)?,
                        local_cache_path: r.get(4)?,
                        size: r.get::<_, i64>(5)?.max(0) as u64,
                        modified_millis: r.get(6)?,
                        pinned_at: r.get(7)?,
                        last_accessed_at: r.get(8)?,
                    })
                },
            )
            .ok();
        Ok(res)
    }

    pub fn remove_pinned_file(
        &self,
        remote_root: &str,
        remote_path: &str,
    ) -> Result<Option<String>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let local_path: Option<String> = conn
            .query_row(
                "SELECT local_cache_path FROM pinned_files WHERE remote_root = ?1 AND remote_path = ?2",
                params![remote_root, remote_path],
                |r| r.get(0),
            )
            .ok();
        conn.execute(
            "DELETE FROM pinned_files WHERE remote_root = ?1 AND remote_path = ?2",
            params![remote_root, remote_path],
        )?;
        Ok(local_path)
    }

    /// Evict least-recently-used pinned cache entries until total cached size <= `max_bytes`.
    /// Returns the list of local file paths evicted.
    pub fn evict_pinned_lru(&self, max_bytes: u64) -> Result<Vec<String>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(
            "SELECT id, local_cache_path, size FROM pinned_files ORDER BY last_accessed_at ASC",
        )?;
        let rows: Vec<(i64, String, u64)> = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, i64>(2)?.max(0) as u64,
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        drop(stmt);

        let mut total: u64 = rows.iter().map(|(_, _, s)| *s).sum();
        let mut evicted_paths = Vec::new();
        for (id, local_path, size) in rows {
            if total <= max_bytes {
                break;
            }
            conn.execute("DELETE FROM pinned_files WHERE id = ?1", params![id])?;
            total = total.saturating_sub(size);
            evicted_paths.push(local_path);
        }
        Ok(evicted_paths)
    }

    // -------------------------------------------------------------------------
    // Full-text (FTS5) file index CRUD
    // -------------------------------------------------------------------------

    /// Atomically replace the indexed entries for `root` inside one SQLite transaction.
    pub fn replace_root_index(
        &self,
        root: &str,
        records: &[IndexedFileRecord],
    ) -> Result<IndexStatsRecord, rusqlite::Error> {
        let mut conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM file_index_fts WHERE root = ?1", params![root])?;
        {
            let mut stmt = tx.prepare_cached(
                "INSERT INTO file_index_fts (root, path, name, ext, category, is_dir, size, modified_millis, hidden)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            )?;
            for rec in records {
                stmt.execute(params![
                    root,
                    rec.path,
                    rec.name,
                    rec.ext,
                    rec.category,
                    if rec.is_dir { 1i64 } else { 0i64 },
                    rec.size.min(i64::MAX as u64) as i64,
                    rec.modified_millis,
                    if rec.hidden { 1i64 } else { 0i64 },
                ])?;
            }
        }
        let updated_at_millis = current_epoch_millis();
        let entry_count = records.len() as u64;
        tx.execute(
            "INSERT OR REPLACE INTO indexed_roots (root, entry_count, updated_at)
             VALUES (?1, ?2, ?3)",
            params![root, entry_count as i64, updated_at_millis],
        )?;
        tx.commit()?;
        Ok(IndexStatsRecord {
            root: root.to_string(),
            entry_count,
            updated_at_millis,
        })
    }

    pub fn clear_root_index(&self, root: &str) -> Result<bool, rusqlite::Error> {
        let mut conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let tx = conn.transaction()?;
        let deleted = tx.execute("DELETE FROM indexed_roots WHERE root = ?1", params![root])?;
        tx.execute("DELETE FROM file_index_fts WHERE root = ?1", params![root])?;
        tx.commit()?;
        Ok(deleted > 0)
    }

    pub fn get_index_stats(&self, root: Option<&str>) -> Result<Vec<IndexStatsRecord>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut out = Vec::new();
        if let Some(r) = root.filter(|s| !s.is_empty()) {
            let mut stmt = conn.prepare(
                "SELECT root, entry_count, updated_at FROM indexed_roots WHERE root = ?1",
            )?;
            let rows = stmt.query_map(params![r], |row| {
                Ok(IndexStatsRecord {
                    root: row.get(0)?,
                    entry_count: row.get::<_, i64>(1)?.max(0) as u64,
                    updated_at_millis: row.get(2)?,
                })
            })?;
            for item in rows {
                out.push(item?);
            }
        } else {
            let mut stmt = conn.prepare(
                "SELECT root, entry_count, updated_at FROM indexed_roots ORDER BY updated_at DESC",
            )?;
            let rows = stmt.query_map([], |row| {
                Ok(IndexStatsRecord {
                    root: row.get(0)?,
                    entry_count: row.get::<_, i64>(1)?.max(0) as u64,
                    updated_at_millis: row.get(2)?,
                })
            })?;
            for item in rows {
                out.push(item?);
            }
        }
        Ok(out)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn query_fts_index(
        &self,
        root: Option<&str>,
        query: &str,
        category: Option<&str>,
        min_size: Option<u64>,
        max_size: Option<u64>,
        modified_after_millis: Option<i64>,
        modified_before_millis: Option<i64>,
        include_hidden: bool,
        limit: u32,
    ) -> Result<Vec<IndexedFileRecord>, rusqlite::Error> {
        let limit = limit.clamp(1, 2000) as i64;
        let raw_trimmed = query.trim();
        let fts_expr = build_fts5_match_expr(raw_trimmed);
        let hits = if raw_trimmed.is_empty() || fts_expr.is_some() {
            self.run_fts_query_internal(
                root,
                fts_expr.as_deref(),
                None,
                category,
                min_size,
                max_size,
                modified_after_millis,
                modified_before_millis,
                include_hidden,
                limit,
            )?
        } else {
            Vec::new()
        };
        if hits.is_empty() && !raw_trimmed.is_empty() {
            let like_pattern = format!("%{}%", escape_sql_like(&raw_trimmed.to_lowercase()));
            return self.run_fts_query_internal(
                root,
                None,
                Some(&like_pattern),
                category,
                min_size,
                max_size,
                modified_after_millis,
                modified_before_millis,
                include_hidden,
                limit,
            );
        }
        Ok(hits)
    }

    #[allow(clippy::too_many_arguments)]
    fn run_fts_query_internal(
        &self,
        root: Option<&str>,
        fts_match: Option<&str>,
        like_lower_pattern: Option<&str>,
        category: Option<&str>,
        min_size: Option<u64>,
        max_size: Option<u64>,
        modified_after_millis: Option<i64>,
        modified_before_millis: Option<i64>,
        include_hidden: bool,
        limit: i64,
    ) -> Result<Vec<IndexedFileRecord>, rusqlite::Error> {
        use rusqlite::types::Value;

        let mut sql = String::from(
            "SELECT root, path, name, ext, category, is_dir, size, modified_millis, hidden
             FROM file_index_fts WHERE 1=1",
        );
        let mut bind_values: Vec<Value> = Vec::new();

        if let Some(expr) = fts_match {
            sql.push_str(" AND file_index_fts MATCH ?");
            bind_values.push(Value::Text(expr.to_string()));
        }
        if let Some(pat) = like_lower_pattern {
            sql.push_str(" AND (LOWER(name) LIKE ? ESCAPE '\\' OR LOWER(path) LIKE ? ESCAPE '\\')");
            bind_values.push(Value::Text(pat.to_string()));
            bind_values.push(Value::Text(pat.to_string()));
        }
        if let Some(r) = root.filter(|s| !s.is_empty()) {
            sql.push_str(" AND root = ?");
            bind_values.push(Value::Text(r.to_string()));
        }
        if let Some(cat) = category
            .map(|c| c.trim().to_ascii_lowercase())
            .filter(|c| !c.is_empty() && c != "all")
        {
            sql.push_str(" AND category = ?");
            bind_values.push(Value::Text(cat));
        }
        if !include_hidden {
            sql.push_str(" AND hidden = 0");
        }
        if let Some(min_sz) = min_size {
            sql.push_str(" AND is_dir = 0 AND size >= ?");
            bind_values.push(Value::Integer(min_sz.min(i64::MAX as u64) as i64));
        }
        if let Some(max_sz) = max_size {
            sql.push_str(" AND is_dir = 0 AND size <= ?");
            bind_values.push(Value::Integer(max_sz.min(i64::MAX as u64) as i64));
        }
        if let Some(after) = modified_after_millis {
            sql.push_str(" AND modified_millis IS NOT NULL AND modified_millis >= ?");
            bind_values.push(Value::Integer(after));
        }
        if let Some(before) = modified_before_millis {
            sql.push_str(" AND modified_millis IS NOT NULL AND modified_millis <= ?");
            bind_values.push(Value::Integer(before));
        }

        if fts_match.is_some() {
            sql.push_str(" ORDER BY bm25(file_index_fts), name COLLATE NOCASE LIMIT ?");
        } else {
            sql.push_str(" ORDER BY is_dir DESC, name COLLATE NOCASE LIMIT ?");
        }
        bind_values.push(Value::Integer(limit));

        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(bind_values), |row| {
            Ok(IndexedFileRecord {
                root: row.get(0)?,
                path: row.get(1)?,
                name: row.get(2)?,
                ext: row.get(3)?,
                category: row.get(4)?,
                is_dir: row.get::<_, i64>(5)? != 0,
                size: row.get::<_, i64>(6)?.max(0) as u64,
                modified_millis: row.get(7)?,
                hidden: row.get::<_, i64>(8)? != 0,
            })
        })?;
        rows.collect()
    }
}
