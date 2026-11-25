//! Per-pool SQLite metadata database (entries, file chunks, replicas, GC queue,
//! snapshot export, fast replace, and 3-way conflict-preserving merge).

use crate::error::{PoolError, PoolResult};
use crate::scheduler::{NodePlacementInfo, NodeRole, ReplicaLocation};
use fm_core::{Entry, EntryKind, VfsPath};
use parking_lot::Mutex;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn millis_to_system_time(ms: i64) -> SystemTime {
    if ms >= 0 {
        UNIX_EPOCH + Duration::from_millis(ms as u64)
    } else {
        UNIX_EPOCH
    }
}

/// Normalize a `VfsPath` into `(parent_path, full_path, name)`.
///
/// Root `/` -> `("", "", "")`
/// `/movies` -> `("", "movies", "movies")`
/// `/movies/demo.mp4` -> `("movies", "movies/demo.mp4", "demo.mp4")`
pub fn normalize_vfs_path(path: &VfsPath) -> PoolResult<(String, String, String)> {
    if path.has_traversal_segment() {
        return Err(PoolError::InvalidPath(format!(
            "traversal segment not allowed: {path}"
        )));
    }
    let segs = path.segments();
    if segs.is_empty() {
        return Ok((String::new(), String::new(), String::new()));
    }
    for seg in segs {
        if seg.is_empty() || seg.contains('\0') {
            return Err(PoolError::InvalidPath(format!(
                "invalid path segment in: {path}"
            )));
        }
    }
    let name = segs[segs.len() - 1].clone();
    let full = segs.join("/");
    let parent = if segs.len() <= 1 {
        String::new()
    } else {
        segs[..segs.len() - 1].join("/")
    };
    Ok((parent, full, name))
}

pub fn vfs_path_from_norm(norm: &str) -> VfsPath {
    if norm.is_empty() {
        VfsPath::root()
    } else {
        VfsPath::new(norm.split('/'))
    }
}

fn next_prefix_bound(prefix_with_slash: &str) -> String {
    let mut bytes = prefix_with_slash.as_bytes().to_vec();
    // '/' is ASCII 47; changing the trailing '/' to '0' (ASCII 48) creates an
    // exact exclusive upper bound for range queries `path >= "foo/" AND path < "foo0"`.
    if let Some(last) = bytes.last_mut() {
        *last = b'0';
    }
    String::from_utf8(bytes).unwrap_or_else(|_| format!("{prefix_with_slash}\u{10FFFF}"))
}

#[derive(Debug, Clone)]
pub struct PoolEntryRecord {
    pub id: i64,
    pub parent_path: String,
    pub path: String,
    pub name: String,
    pub kind: String,
    pub size_bytes: u64,
    pub mtime_ms: i64,
    pub chunk_size: u32,
    pub content_hash: Option<String>,
    pub version: i64,
    pub updated_meta_ver: i64,
    pub deleted_at: Option<i64>,
}

impl PoolEntryRecord {
    pub fn to_vfs_entry(&self) -> Entry {
        let kind = if self.kind == "dir" {
            EntryKind::Dir
        } else {
            EntryKind::File
        };
        Entry {
            name: self.name.clone(),
            path: vfs_path_from_norm(&self.path),
            kind,
            size: if kind == EntryKind::Dir {
                None
            } else {
                Some(self.size_bytes)
            },
            modified: Some(millis_to_system_time(self.mtime_ms)),
            mode: None,
            hidden: self.name.starts_with('.'),
            is_symlink: false,
            mime: None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct FileChunkRecord {
    pub chunk_index: u32,
    pub chunk_hash: String,
    pub plain_size: u64,
    pub stored_size: u64,
    pub encrypted: bool,
}

#[derive(Debug, Clone)]
pub struct GcQueueItem {
    pub chunk_hash: String,
    pub node_id: String,
    pub remote_relpath: String,
    pub queued_at: i64,
    pub retry_count: u32,
}

#[derive(Debug, Clone)]
pub struct WriteChunkInput {
    pub chunk_index: u32,
    pub chunk_hash: String,
    pub plain_size: u64,
    pub stored_size: u64,
    pub encrypted: bool,
    /// `(node_id, remote_relpath)` replicas written for this chunk.
    pub new_replicas: Vec<(String, String)>,
}

#[derive(Debug, Clone)]
pub struct UnderReplicatedChunk {
    pub chunk_hash: String,
    pub plain_size: u64,
    pub stored_size: u64,
    pub encrypted: bool,
    pub ok_count: usize,
}

#[derive(Debug, Clone)]
pub struct PoolDbStats {
    pub total_physical_quota: u64,
    pub effective_logical_capacity: u64,
    pub total_physical_used: u64,
    pub logical_used_bytes: u64,
    pub file_count: u64,
    pub dir_count: u64,
    pub degraded_chunks: u64,
    pub pending_gc_count: u64,
    pub meta_version: u64,
    pub last_synced_version: u64,
    pub dirty: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolNodeSyncState {
    pub node_id: String,
    pub remote_id: String,
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    pub role: NodeRole,
    pub is_meta_backup: bool,
}

#[derive(Clone)]
pub struct PoolMetaDb {
    conn: Arc<Mutex<Connection>>,
    db_path: PathBuf,
}

impl PoolMetaDb {
    pub fn open(db_path: impl AsRef<Path>, pool_id: &str, device_id: &str) -> PoolResult<Self> {
        let db_path = db_path.as_ref().to_path_buf();
        if let Some(parent) = db_path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent)?;
            }
        }
        let conn = open_configured_connection(&db_path, true)?;
        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            db_path,
        };
        db.init_schema(pool_id, device_id)?;
        Ok(db)
    }

    pub fn db_path(&self) -> &Path {
        &self.db_path
    }

    fn init_schema(&self, pool_id: &str, device_id: &str) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS pool_meta (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS pool_nodes (
                node_id            TEXT PRIMARY KEY,
                remote_id          TEXT NOT NULL,
                base_prefix        TEXT NOT NULL DEFAULT 'fm_pool',
                failure_domain     TEXT NOT NULL,
                quota_bytes        INTEGER NOT NULL,
                used_bytes         INTEGER NOT NULL DEFAULT 0,
                remote_free_bytes  INTEGER,
                remote_total_bytes INTEGER,
                role               TEXT NOT NULL DEFAULT 'rw',
                is_meta_backup     INTEGER NOT NULL DEFAULT 0,
                health_score       REAL NOT NULL DEFAULT 1.0,
                avg_latency_ms     INTEGER NOT NULL DEFAULT 200,
                last_checked       INTEGER
            );

            CREATE TABLE IF NOT EXISTS entries (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                parent_path      TEXT NOT NULL,
                path             TEXT NOT NULL,
                name             TEXT NOT NULL,
                kind             TEXT NOT NULL,
                size_bytes       INTEGER NOT NULL DEFAULT 0,
                mtime_ms         INTEGER NOT NULL,
                chunk_size       INTEGER NOT NULL DEFAULT 16777216,
                content_hash     TEXT,
                version          INTEGER NOT NULL DEFAULT 1,
                updated_meta_ver INTEGER NOT NULL DEFAULT 0,
                deleted_at       INTEGER
            );

            CREATE UNIQUE INDEX IF NOT EXISTS idx_entries_active_path
                ON entries(path) WHERE deleted_at IS NULL;
            CREATE INDEX IF NOT EXISTS idx_entries_parent
                ON entries(parent_path, deleted_at);
            CREATE INDEX IF NOT EXISTS idx_entries_path_all
                ON entries(path);

            CREATE TABLE IF NOT EXISTS file_chunks (
                entry_id    INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
                chunk_index INTEGER NOT NULL,
                chunk_hash  TEXT NOT NULL,
                plain_size  INTEGER NOT NULL,
                stored_size INTEGER NOT NULL,
                encrypted   INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (entry_id, chunk_index)
            );
            CREATE INDEX IF NOT EXISTS idx_file_chunks_hash
                ON file_chunks(chunk_hash);

            CREATE TABLE IF NOT EXISTS chunk_replicas (
                chunk_hash     TEXT NOT NULL,
                node_id        TEXT NOT NULL REFERENCES pool_nodes(node_id) ON DELETE CASCADE,
                remote_relpath TEXT NOT NULL,
                status         TEXT NOT NULL DEFAULT 'ok',
                verified_at    INTEGER NOT NULL,
                PRIMARY KEY (chunk_hash, node_id)
            );
            CREATE INDEX IF NOT EXISTS idx_replicas_node
                ON chunk_replicas(node_id);

            CREATE TABLE IF NOT EXISTS gc_queue (
                chunk_hash     TEXT NOT NULL,
                node_id        TEXT NOT NULL,
                remote_relpath TEXT NOT NULL,
                queued_at      INTEGER NOT NULL,
                retry_count    INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (chunk_hash, node_id)
            );
            ",
        )?;

        set_meta_default(&conn, "pool_id", pool_id)?;
        set_meta_default(&conn, "device_id", device_id)?;
        set_meta_default(&conn, "meta_version", "0")?;
        set_meta_default(&conn, "last_synced_version", "0")?;
        set_meta_default(&conn, "dirty", "0")?;

        // Idempotent migration for pools created before remote disk space tracking.
        {
            let mut has_free = false;
            let mut has_total = false;
            let mut stmt = conn.prepare("PRAGMA table_info(pool_nodes)")?;
            let cols = stmt.query_map([], |r| r.get::<_, String>(1))?;
            for col in cols {
                match col?.as_str() {
                    "remote_free_bytes" => has_free = true,
                    "remote_total_bytes" => has_total = true,
                    _ => {}
                }
            }
            drop(stmt);
            if !has_free {
                conn.execute(
                    "ALTER TABLE pool_nodes ADD COLUMN remote_free_bytes INTEGER",
                    [],
                )?;
            }
            if !has_total {
                conn.execute(
                    "ALTER TABLE pool_nodes ADD COLUMN remote_total_bytes INTEGER",
                    [],
                )?;
            }
        }

        Ok(())
    }

    pub fn get_meta_u64(&self, key: &str) -> PoolResult<u64> {
        let conn = self.conn.lock();
        get_meta_u64_conn(&conn, key)
    }

    pub fn is_dirty(&self) -> PoolResult<bool> {
        Ok(self.get_meta_u64("dirty")? != 0)
    }

    pub fn set_meta_sync_state(&self, version: u64, dirty: bool) -> PoolResult<()> {
        let conn = self.conn.lock();
        set_meta_conn(&conn, "meta_version", &version.to_string())?;
        set_meta_conn(&conn, "last_synced_version", &version.to_string())?;
        set_meta_conn(&conn, "dirty", if dirty { "1" } else { "0" })?;
        Ok(())
    }

    /// Synchronize configured pool nodes into `pool_nodes`, removing nodes no
    /// longer present only if they carry no active replicas (otherwise marking
    /// them `offline` so existing data remains trackable until drained/GC'd).
    pub fn sync_nodes(&self, configured: &[PoolNodeSyncState]) -> PoolResult<()> {
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;

        let configured_ids: HashSet<&str> = configured.iter().map(|n| n.node_id.as_str()).collect();
        for node in configured {
            tx.execute(
                "INSERT INTO pool_nodes
                    (node_id, remote_id, base_prefix, failure_domain, quota_bytes, role, is_meta_backup)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(node_id) DO UPDATE SET
                    remote_id = excluded.remote_id,
                    base_prefix = excluded.base_prefix,
                    failure_domain = excluded.failure_domain,
                    quota_bytes = excluded.quota_bytes,
                    role = excluded.role,
                    is_meta_backup = excluded.is_meta_backup",
                params![
                    node.node_id,
                    node.remote_id,
                    node.base_prefix,
                    node.failure_domain,
                    node.quota_bytes.min(i64::MAX as u64) as i64,
                    node.role.as_str(),
                    if node.is_meta_backup { 1i64 } else { 0i64 },
                ],
            )?;
        }

        let existing_ids: Vec<String> = {
            let mut stmt = tx.prepare("SELECT node_id FROM pool_nodes")?;
            let rows = stmt.query_map([], |r| r.get::<_, String>(0))?;
            rows.collect::<Result<Vec<_>, _>>()?
        };

        for old_id in existing_ids {
            if !configured_ids.contains(old_id.as_str()) {
                let rep_count: i64 = tx.query_row(
                    "SELECT COUNT(*) FROM chunk_replicas WHERE node_id = ?1",
                    params![old_id],
                    |r| r.get(0),
                )?;
                if rep_count == 0 {
                    tx.execute("DELETE FROM pool_nodes WHERE node_id = ?1", params![old_id])?;
                } else {
                    tx.execute(
                        "UPDATE pool_nodes SET role = 'offline', is_meta_backup = 0 WHERE node_id = ?1",
                        params![old_id],
                    )?;
                }
            }
        }

        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(())
    }

    pub fn list_nodes(&self) -> PoolResult<Vec<NodePlacementInfo>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT node_id, remote_id, base_prefix, failure_domain, quota_bytes, used_bytes,
                    role, is_meta_backup, health_score, avg_latency_ms,
                    remote_free_bytes, remote_total_bytes
             FROM pool_nodes ORDER BY node_id ASC",
        )?;
        let rows = stmt.query_map([], |row| {
            let role_str: String = row.get(6)?;
            Ok(NodePlacementInfo {
                node_id: row.get(0)?,
                remote_id: row.get(1)?,
                base_prefix: row.get(2)?,
                failure_domain: row.get(3)?,
                quota_bytes: row.get::<_, i64>(4)?.max(0) as u64,
                used_bytes: row.get::<_, i64>(5)?.max(0) as u64,
                remote_free_bytes: row.get::<_, Option<i64>>(10)?.map(|v| v.max(0) as u64),
                remote_total_bytes: row.get::<_, Option<i64>>(11)?.map(|v| v.max(0) as u64),
                role: NodeRole::parse(&role_str),
                is_meta_backup: row.get::<_, i64>(7)? != 0,
                db_health_score: row.get(8)?,
                db_avg_latency_ms: row.get::<_, i64>(9)?.max(1) as u64,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn update_node_space_db(
        &self,
        node_id: &str,
        free_bytes: Option<u64>,
        total_bytes: Option<u64>,
    ) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "UPDATE pool_nodes SET remote_free_bytes = ?1, remote_total_bytes = ?2
             WHERE node_id = ?3",
            params![
                free_bytes.map(|v| v.min(i64::MAX as u64) as i64),
                total_bytes.map(|v| v.min(i64::MAX as u64) as i64),
                node_id
            ],
        )?;
        Ok(())
    }

    pub fn update_node_health_db(
        &self,
        node_id: &str,
        health_score: f64,
        avg_latency_ms: u64,
        last_checked_ms: i64,
    ) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "UPDATE pool_nodes SET health_score = ?1, avg_latency_ms = ?2, last_checked = ?3
             WHERE node_id = ?4",
            params![
                health_score,
                avg_latency_ms.min(i64::MAX as u64) as i64,
                last_checked_ms,
                node_id
            ],
        )?;
        Ok(())
    }

    pub fn set_node_role(&self, node_id: &str, role: NodeRole) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "UPDATE pool_nodes SET role = ?1 WHERE node_id = ?2",
            params![role.as_str(), node_id],
        )?;
        Ok(())
    }

    pub fn stat(&self, path: &VfsPath) -> PoolResult<PoolEntryRecord> {
        let (_, norm, _) = normalize_vfs_path(path)?;
        if norm.is_empty() {
            return Ok(PoolEntryRecord {
                id: 0,
                parent_path: String::new(),
                path: String::new(),
                name: String::new(),
                kind: "dir".to_string(),
                size_bytes: 0,
                mtime_ms: 0,
                chunk_size: 0,
                content_hash: None,
                version: 1,
                updated_meta_ver: 0,
                deleted_at: None,
            });
        }
        let conn = self.conn.lock();
        query_active_entry(&conn, &norm)?
            .ok_or_else(|| PoolError::PathNotFound(path.to_slash_string()))
    }

    pub fn list_dir(&self, dir: &VfsPath) -> PoolResult<Vec<Entry>> {
        let (_, norm, _) = normalize_vfs_path(dir)?;
        let conn = self.conn.lock();
        if !norm.is_empty() {
            let parent = query_active_entry(&conn, &norm)?
                .ok_or_else(|| PoolError::PathNotFound(dir.to_slash_string()))?;
            if parent.kind != "dir" {
                return Err(PoolError::InvalidPath(format!(
                    "not a directory: {dir}"
                )));
            }
        }

        let mut stmt = conn.prepare(
            "SELECT id, parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size,
                    content_hash, version, updated_meta_ver, deleted_at
             FROM entries
             WHERE parent_path = ?1 AND deleted_at IS NULL",
        )?;
        let rows = stmt.query_map(params![norm], row_to_entry_record)?;
        let mut entries: Vec<Entry> = rows
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .map(|r| r.to_vfs_entry())
            .collect();
        entries.sort_unstable_by(|a, b| {
            fm_core::compare_dir_and_name(
                a.kind == EntryKind::Dir,
                &a.name,
                b.kind == EntryKind::Dir,
                &b.name,
                true,
            )
        });
        Ok(entries)
    }

    pub fn list_dir_paged_with_total(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> PoolResult<(Vec<Entry>, bool, Option<u32>)> {
        let all = self.list_dir(dir)?;
        let total = all.len() as u32;
        let page = page.max(1);
        let page_size = page_size.max(1);
        let skip = ((page - 1) as usize).saturating_mul(page_size as usize);
        let has_more = skip.saturating_add(page_size as usize) < all.len();
        let slice = all.into_iter().skip(skip).take(page_size as usize).collect();
        Ok((slice, has_more, Some(total)))
    }

    pub fn mkdir(&self, path: &VfsPath) -> PoolResult<()> {
        let (_, norm, _) = normalize_vfs_path(path)?;
        if norm.is_empty() {
            return Ok(());
        }
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;

        if let Some(existing) = query_active_entry(&tx, &norm)? {
            if existing.kind == "dir" {
                return Ok(());
            }
            return Err(PoolError::AlreadyExists(path.to_slash_string()));
        }

        let now = now_millis();
        let next_ver = bump_meta_version_tx(&tx)?;
        ensure_parent_dirs_tx(&tx, &norm, now, next_ver)?;
        let (parent, _, name) = normalize_vfs_path(path)?;
        tx.execute(
            "INSERT INTO entries
                (parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size, version, updated_meta_ver, deleted_at)
             VALUES (?1, ?2, ?3, 'dir', 0, ?4, 0, 1, ?5, NULL)",
            params![parent, norm, name, now, next_ver as i64],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub fn commit_file_write(
        &self,
        path: &VfsPath,
        size_bytes: u64,
        chunk_size: u32,
        content_hash: Option<&str>,
        chunks: &[WriteChunkInput],
        create_only: bool,
    ) -> PoolResult<()> {
        let (parent, norm, name) = normalize_vfs_path(path)?;
        if norm.is_empty() {
            return Err(PoolError::InvalidPath("cannot overwrite root".to_string()));
        }
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;

        let now = now_millis();
        let next_ver = bump_meta_version_tx(&tx)?;

        if let Some(existing) = query_active_entry(&tx, &norm)? {
            if create_only {
                return Err(PoolError::AlreadyExists(path.to_slash_string()));
            }
            if existing.kind == "dir" {
                return Err(PoolError::AlreadyExists(format!(
                    "destination is a directory: {path}"
                )));
            }
            tx.execute(
                "UPDATE entries SET deleted_at = ?1, updated_meta_ver = ?2 WHERE id = ?3",
                params![now, next_ver as i64, existing.id],
            )?;
        }

        ensure_parent_dirs_tx(&tx, &norm, now, next_ver)?;

        tx.execute(
            "INSERT INTO entries
                (parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size, content_hash, version, updated_meta_ver, deleted_at)
             VALUES (?1, ?2, ?3, 'file', ?4, ?5, ?6, ?7, 1, ?8, NULL)",
            params![
                parent,
                norm,
                name,
                size_bytes.min(i64::MAX as u64) as i64,
                now,
                chunk_size as i64,
                content_hash,
                next_ver as i64,
            ],
        )?;
        let entry_id = tx.last_insert_rowid();

        {
            let mut fc_stmt = tx.prepare_cached(
                "INSERT INTO file_chunks (entry_id, chunk_index, chunk_hash, plain_size, stored_size, encrypted)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            )?;
            let mut rep_stmt = tx.prepare_cached(
                "INSERT INTO chunk_replicas (chunk_hash, node_id, remote_relpath, status, verified_at)
                 VALUES (?1, ?2, ?3, 'ok', ?4)
                 ON CONFLICT(chunk_hash, node_id) DO UPDATE SET
                    remote_relpath = excluded.remote_relpath,
                    status = 'ok',
                    verified_at = excluded.verified_at",
            )?;

            for ch in chunks {
                fc_stmt.execute(params![
                    entry_id,
                    ch.chunk_index as i64,
                    ch.chunk_hash,
                    ch.plain_size.min(i64::MAX as u64) as i64,
                    ch.stored_size.min(i64::MAX as u64) as i64,
                    if ch.encrypted { 1i64 } else { 0i64 },
                ])?;
                for (node_id, relpath) in &ch.new_replicas {
                    rep_stmt.execute(params![ch.chunk_hash, node_id, relpath, now])?;
                }
            }
        }

        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(())
    }

    pub fn rename(&self, from: &VfsPath, to: &VfsPath) -> PoolResult<()> {
        let (_, from_norm, _) = normalize_vfs_path(from)?;
        let (to_parent, to_norm, to_name) = normalize_vfs_path(to)?;
        if from_norm.is_empty() || to_norm.is_empty() {
            return Err(PoolError::InvalidPath("cannot rename root".to_string()));
        }
        if from_norm == to_norm {
            return Ok(());
        }
        if to_norm.starts_with(&format!("{from_norm}/")) {
            return Err(PoolError::InvalidPath(
                "cannot move a directory into itself".to_string(),
            ));
        }

        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;

        let src = query_active_entry(&tx, &from_norm)?
            .ok_or_else(|| PoolError::PathNotFound(from.to_slash_string()))?;

        let now = now_millis();
        let next_ver = bump_meta_version_tx(&tx)?;

        if let Some(dst_existing) = query_active_entry(&tx, &to_norm)? {
            if dst_existing.kind == "dir" {
                return Err(PoolError::AlreadyExists(format!(
                    "destination is a directory: {to}"
                )));
            }
            if src.kind == "dir" {
                return Err(PoolError::AlreadyExists(format!(
                    "cannot replace file with directory: {to}"
                )));
            }
            tx.execute(
                "UPDATE entries SET deleted_at = ?1, updated_meta_ver = ?2 WHERE id = ?3",
                params![now, next_ver as i64, dst_existing.id],
            )?;
        }

        ensure_parent_dirs_tx(&tx, &to_norm, now, next_ver)?;

        tx.execute(
            "UPDATE entries
             SET parent_path = ?1, path = ?2, name = ?3, version = version + 1, updated_meta_ver = ?4
             WHERE id = ?5",
            params![to_parent, to_norm, to_name, next_ver as i64, src.id],
        )?;

        if src.kind == "dir" {
            let old_prefix = format!("{from_norm}/");
            let upper = next_prefix_bound(&old_prefix);
            let descendants: Vec<(i64, String, String)> = {
                let mut stmt = tx.prepare(
                    "SELECT id, parent_path, path FROM entries
                     WHERE deleted_at IS NULL AND path >= ?1 AND path < ?2",
                )?;
                let rows = stmt.query_map(params![old_prefix, upper], |r| {
                    Ok((r.get(0)?, r.get(1)?, r.get(2)?))
                })?;
                rows.collect::<Result<Vec<_>, _>>()?
            };

            let mut upd = tx.prepare_cached(
                "UPDATE entries SET parent_path = ?1, path = ?2, updated_meta_ver = ?3 WHERE id = ?4",
            )?;
            for (desc_id, desc_parent, desc_path) in descendants {
                let suffix = desc_path.strip_prefix(&from_norm).unwrap_or("");
                let new_path = format!("{to_norm}{suffix}");
                let new_parent = if desc_parent == from_norm {
                    to_norm.clone()
                } else {
                    let parent_suffix = desc_parent.strip_prefix(&from_norm).unwrap_or("");
                    format!("{to_norm}{parent_suffix}")
                };
                upd.execute(params![new_parent, new_path, next_ver as i64, desc_id])?;
            }
        }

        tx.commit()?;
        Ok(())
    }

    pub fn soft_delete(&self, path: &VfsPath) -> PoolResult<()> {
        let (_, norm, _) = normalize_vfs_path(path)?;
        if norm.is_empty() {
            return Err(PoolError::InvalidPath("cannot delete root".to_string()));
        }
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;
        let target = query_active_entry(&tx, &norm)?
            .ok_or_else(|| PoolError::PathNotFound(path.to_slash_string()))?;

        let now = now_millis();
        let next_ver = bump_meta_version_tx(&tx)?;
        tx.execute(
            "UPDATE entries SET deleted_at = ?1, updated_meta_ver = ?2 WHERE id = ?3",
            params![now, next_ver as i64, target.id],
        )?;
        if target.kind == "dir" {
            let prefix = format!("{norm}/");
            let upper = next_prefix_bound(&prefix);
            tx.execute(
                "UPDATE entries SET deleted_at = ?1, updated_meta_ver = ?2
                 WHERE deleted_at IS NULL AND path >= ?3 AND path < ?4",
                params![now, next_ver as i64, prefix, upper],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn get_file_chunks(&self, entry_id: i64) -> PoolResult<Vec<FileChunkRecord>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT chunk_index, chunk_hash, plain_size, stored_size, encrypted
             FROM file_chunks WHERE entry_id = ?1 ORDER BY chunk_index ASC",
        )?;
        let rows = stmt.query_map(params![entry_id], |r| {
            Ok(FileChunkRecord {
                chunk_index: r.get::<_, i64>(0)?.max(0) as u32,
                chunk_hash: r.get(1)?,
                plain_size: r.get::<_, i64>(2)?.max(0) as u64,
                stored_size: r.get::<_, i64>(3)?.max(0) as u64,
                encrypted: r.get::<_, i64>(4)? != 0,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn get_chunk_replicas(&self, chunk_hash: &str) -> PoolResult<Vec<ReplicaLocation>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT chunk_hash, node_id, remote_relpath, status, verified_at
             FROM chunk_replicas WHERE chunk_hash = ?1",
        )?;
        let rows = stmt.query_map(params![chunk_hash], |r| {
            Ok(ReplicaLocation {
                chunk_hash: r.get(0)?,
                node_id: r.get(1)?,
                remote_relpath: r.get(2)?,
                status: r.get(3)?,
                verified_at: r.get(4)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn get_ok_replicas_for_chunk(&self, chunk_hash: &str) -> PoolResult<Vec<ReplicaLocation>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT r.chunk_hash, r.node_id, r.remote_relpath, r.status, r.verified_at
             FROM chunk_replicas r
             JOIN pool_nodes n ON n.node_id = r.node_id
             WHERE r.chunk_hash = ?1 AND r.status = 'ok' AND n.role != 'offline'",
        )?;
        let rows = stmt.query_map(params![chunk_hash], |r| {
            Ok(ReplicaLocation {
                chunk_hash: r.get(0)?,
                node_id: r.get(1)?,
                remote_relpath: r.get(2)?,
                status: r.get(3)?,
                verified_at: r.get(4)?,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn mark_replica_status(
        &self,
        chunk_hash: &str,
        node_id: &str,
        status: &str,
    ) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "UPDATE chunk_replicas SET status = ?1, verified_at = ?2
             WHERE chunk_hash = ?3 AND node_id = ?4",
            params![status, now_millis(), chunk_hash, node_id],
        )?;
        Ok(())
    }

    pub fn add_replica(&self, chunk_hash: &str, node_id: &str, relpath: &str) -> PoolResult<()> {
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO chunk_replicas (chunk_hash, node_id, remote_relpath, status, verified_at)
             VALUES (?1, ?2, ?3, 'ok', ?4)
             ON CONFLICT(chunk_hash, node_id) DO UPDATE SET
                remote_relpath = excluded.remote_relpath,
                status = 'ok',
                verified_at = excluded.verified_at",
            params![chunk_hash, node_id, relpath, now_millis()],
        )?;
        let _ = bump_meta_version_tx(&tx)?;
        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(())
    }

    pub fn remove_replica_and_maybe_queue_gc(
        &self,
        chunk_hash: &str,
        node_id: &str,
        relpath: &str,
        queue_gc: bool,
    ) -> PoolResult<()> {
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;
        tx.execute(
            "DELETE FROM chunk_replicas WHERE chunk_hash = ?1 AND node_id = ?2",
            params![chunk_hash, node_id],
        )?;
        if queue_gc {
            tx.execute(
                "INSERT OR IGNORE INTO gc_queue (chunk_hash, node_id, remote_relpath, queued_at, retry_count)
                 VALUES (?1, ?2, ?3, ?4, 0)",
                params![chunk_hash, node_id, relpath, now_millis()],
            )?;
        }
        let _ = bump_meta_version_tx(&tx)?;
        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(())
    }

    pub fn list_under_replicated_chunks(
        &self,
        target_replicas: usize,
    ) -> PoolResult<Vec<UnderReplicatedChunk>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT fc.chunk_hash,
                    MAX(fc.plain_size),
                    MAX(fc.stored_size),
                    MAX(fc.encrypted),
                    COUNT(CASE WHEN cr.status = 'ok' AND pn.role IN ('rw', 'ro') THEN 1 END) AS ok_cnt
             FROM file_chunks fc
             JOIN entries e ON e.id = fc.entry_id
             LEFT JOIN chunk_replicas cr ON cr.chunk_hash = fc.chunk_hash
             LEFT JOIN pool_nodes pn ON pn.node_id = cr.node_id
             WHERE e.deleted_at IS NULL
             GROUP BY fc.chunk_hash
             HAVING ok_cnt < ?1",
        )?;
        let rows = stmt.query_map(params![target_replicas as i64], |r| {
            Ok(UnderReplicatedChunk {
                chunk_hash: r.get(0)?,
                plain_size: r.get::<_, i64>(1)?.max(0) as u64,
                stored_size: r.get::<_, i64>(2)?.max(0) as u64,
                encrypted: r.get::<_, i64>(3)? != 0,
                ok_count: r.get::<_, i64>(4)?.max(0) as usize,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn list_chunks_on_node(&self, node_id: &str) -> PoolResult<Vec<UnderReplicatedChunk>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT cr.chunk_hash,
                    COALESCE(MAX(fc.plain_size), 0),
                    COALESCE(MAX(fc.stored_size), 0),
                    COALESCE(MAX(fc.encrypted), 0),
                    (SELECT COUNT(*) FROM chunk_replicas cr2
                     JOIN pool_nodes pn2 ON pn2.node_id = cr2.node_id
                     WHERE cr2.chunk_hash = cr.chunk_hash
                       AND cr2.status = 'ok'
                       AND pn2.node_id != ?1
                       AND pn2.role IN ('rw', 'ro')) AS other_ok_cnt
             FROM chunk_replicas cr
             LEFT JOIN file_chunks fc ON fc.chunk_hash = cr.chunk_hash
             WHERE cr.node_id = ?1
             GROUP BY cr.chunk_hash",
        )?;
        let rows = stmt.query_map(params![node_id], |r| {
            Ok(UnderReplicatedChunk {
                chunk_hash: r.get(0)?,
                plain_size: r.get::<_, i64>(1)?.max(0) as u64,
                stored_size: r.get::<_, i64>(2)?.max(0) as u64,
                encrypted: r.get::<_, i64>(3)? != 0,
                ok_count: r.get::<_, i64>(4)?.max(0) as usize,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn get_replica_relpath(&self, chunk_hash: &str, node_id: &str) -> PoolResult<Option<String>> {
        let conn = self.conn.lock();
        let res = conn
            .query_row(
                "SELECT remote_relpath FROM chunk_replicas WHERE chunk_hash = ?1 AND node_id = ?2",
                params![chunk_hash, node_id],
                |r| r.get::<_, String>(0),
            )
            .optional()?;
        Ok(res)
    }

    /// Purge soft-deleted entries older than `cutoff_ms`, remove zero-ref
    /// chunks from `chunk_replicas`, and enqueue their remote paths into `gc_queue`.
    pub fn sweep_expired_soft_deletes(&self, cutoff_ms: i64) -> PoolResult<u64> {
        let mut conn = self.conn.lock();
        let tx = conn.transaction()?;

        let purged = tx.execute(
            "DELETE FROM entries WHERE deleted_at IS NOT NULL AND deleted_at <= ?1",
            params![cutoff_ms],
        )? as u64;

        let now = now_millis();
        // Any replica whose chunk_hash no longer appears in `file_chunks` is
        // an orphan and can be reclaimed.
        tx.execute(
            "INSERT OR IGNORE INTO gc_queue (chunk_hash, node_id, remote_relpath, queued_at, retry_count)
             SELECT cr.chunk_hash, cr.node_id, cr.remote_relpath, ?1, 0
             FROM chunk_replicas cr
             WHERE NOT EXISTS (
                 SELECT 1 FROM file_chunks fc WHERE fc.chunk_hash = cr.chunk_hash
             )",
            params![now],
        )?;
        tx.execute(
            "DELETE FROM chunk_replicas
             WHERE NOT EXISTS (
                 SELECT 1 FROM file_chunks fc WHERE fc.chunk_hash = chunk_replicas.chunk_hash
             )",
            [],
        )?;

        if purged > 0 {
            let _ = bump_meta_version_tx(&tx)?;
        }
        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(purged)
    }

    pub fn list_gc_queue(&self) -> PoolResult<Vec<GcQueueItem>> {
        let conn = self.conn.lock();
        let mut stmt = conn.prepare(
            "SELECT chunk_hash, node_id, remote_relpath, queued_at, retry_count
             FROM gc_queue ORDER BY queued_at ASC",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(GcQueueItem {
                chunk_hash: r.get(0)?,
                node_id: r.get(1)?,
                remote_relpath: r.get(2)?,
                queued_at: r.get(3)?,
                retry_count: r.get::<_, i64>(4)?.max(0) as u32,
            })
        })?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn remove_gc_item(&self, chunk_hash: &str, node_id: &str) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "DELETE FROM gc_queue WHERE chunk_hash = ?1 AND node_id = ?2",
            params![chunk_hash, node_id],
        )?;
        Ok(())
    }

    pub fn increment_gc_retry(&self, chunk_hash: &str, node_id: &str) -> PoolResult<()> {
        let conn = self.conn.lock();
        conn.execute(
            "UPDATE gc_queue SET retry_count = retry_count + 1
             WHERE chunk_hash = ?1 AND node_id = ?2",
            params![chunk_hash, node_id],
        )?;
        Ok(())
    }

    pub fn compute_stats(&self, replication_factor: usize) -> PoolResult<PoolDbStats> {
        let conn = self.conn.lock();
        let mut domain_quotas: HashMap<String, u64> = HashMap::new();
        let mut total_physical_quota = 0u64;
        let mut total_physical_used = 0u64;

        {
            let mut stmt = conn.prepare(
                "SELECT failure_domain, quota_bytes, used_bytes, role FROM pool_nodes",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, i64>(1)?.max(0) as u64,
                    r.get::<_, i64>(2)?.max(0) as u64,
                    r.get::<_, String>(3)?,
                ))
            })?;
            for row in rows {
                let (domain, quota, used, role) = row?;
                total_physical_used = total_physical_used.saturating_add(used);
                if role != "offline" {
                    total_physical_quota = total_physical_quota.saturating_add(quota);
                    *domain_quotas.entry(domain).or_default() += quota;
                }
            }
        }

        let effective_logical_capacity = if replication_factor <= 1 || domain_quotas.len() <= 1 {
            total_physical_quota / (replication_factor.max(1) as u64)
        } else {
            let max_domain = domain_quotas.values().copied().max().unwrap_or(0);
            let per_replica = total_physical_quota / (replication_factor as u64);
            let capped_by_largest_domain = total_physical_quota.saturating_sub(max_domain)
                / ((replication_factor - 1).max(1) as u64);
            per_replica.min(capped_by_largest_domain)
        };

        let (file_count, dir_count, logical_used_bytes): (u64, u64, u64) = conn.query_row(
            "SELECT
                COALESCE(SUM(CASE WHEN kind = 'file' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'dir' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN kind = 'file' THEN size_bytes ELSE 0 END), 0)
             FROM entries WHERE deleted_at IS NULL",
            [],
            |r| {
                Ok((
                    r.get::<_, i64>(0)?.max(0) as u64,
                    r.get::<_, i64>(1)?.max(0) as u64,
                    r.get::<_, i64>(2)?.max(0) as u64,
                ))
            },
        )?;

        let degraded_chunks: u64 = conn.query_row(
            "SELECT COUNT(*) FROM (
                SELECT fc.chunk_hash
                FROM file_chunks fc
                JOIN entries e ON e.id = fc.entry_id
                LEFT JOIN chunk_replicas cr ON cr.chunk_hash = fc.chunk_hash AND cr.status = 'ok'
                LEFT JOIN pool_nodes pn ON pn.node_id = cr.node_id AND pn.role IN ('rw', 'ro')
                WHERE e.deleted_at IS NULL
                GROUP BY fc.chunk_hash
                HAVING COUNT(pn.node_id) < ?1
            )",
            params![replication_factor as i64],
            |r| Ok(r.get::<_, i64>(0)?.max(0) as u64),
        )?;

        let pending_gc_count: u64 = conn.query_row(
            "SELECT COUNT(*) FROM gc_queue",
            [],
            |r| Ok(r.get::<_, i64>(0)?.max(0) as u64),
        )?;

        let meta_version = get_meta_u64_conn(&conn, "meta_version")?;
        let last_synced_version = get_meta_u64_conn(&conn, "last_synced_version")?;
        let dirty = get_meta_u64_conn(&conn, "dirty")? != 0;

        Ok(PoolDbStats {
            total_physical_quota,
            effective_logical_capacity,
            total_physical_used,
            logical_used_bytes,
            file_count,
            dir_count,
            degraded_chunks,
            pending_gc_count,
            meta_version,
            last_synced_version,
            dirty,
        })
    }

    /// Export a self-contained SQLite snapshot via `VACUUM INTO`.
    pub fn export_vacuum_snapshot(&self, dest: &Path) -> PoolResult<()> {
        if dest.exists() {
            std::fs::remove_file(dest)?;
        }
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let conn = self.conn.lock();
        let dest_str = dest.to_string_lossy().into_owned();
        conn.execute("VACUUM INTO ?1", params![dest_str])?;
        Ok(())
    }

    /// Fast-path snapshot replacement when the local DB has no unsynced local changes.
    /// Preserves local `pool_nodes.remote_id` mappings (in case remote IDs differ per device)
    /// and sets `meta_version = remote_version`, `dirty = 0`.
    pub fn replace_from_snapshot(&self, snapshot_path: &Path, remote_version: u64) -> PoolResult<()> {
        let remote_conn = open_configured_connection(snapshot_path, false)?;
        let mut conn = self.conn.lock();

        // Capture local node remote_id overrides so device-local remote bindings survive.
        let local_remote_ids: HashMap<String, String> = {
            let mut stmt = conn.prepare("SELECT node_id, remote_id FROM pool_nodes")?;
            let rows = stmt.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
            rows.collect::<Result<HashMap<_, _>, _>>()?
        };

        let remote_entries = load_all_entries(&remote_conn)?;
        let remote_chunks = load_all_chunks(&remote_conn)?;
        let remote_replicas = load_all_replicas(&remote_conn)?;
        let remote_nodes = load_all_nodes(&remote_conn)?;
        let remote_gc = load_all_gc(&remote_conn)?;

        let tx = conn.transaction()?;
        tx.execute("DELETE FROM gc_queue", [])?;
        tx.execute("DELETE FROM chunk_replicas", [])?;
        tx.execute("DELETE FROM file_chunks", [])?;
        tx.execute("DELETE FROM entries", [])?;

        for node in remote_nodes {
            let mapped_remote = local_remote_ids
                .get(&node.node_id)
                .cloned()
                .unwrap_or(node.remote_id);
            tx.execute(
                "INSERT INTO pool_nodes
                    (node_id, remote_id, base_prefix, failure_domain, quota_bytes, used_bytes,
                     role, is_meta_backup, health_score, avg_latency_ms, last_checked)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
                 ON CONFLICT(node_id) DO UPDATE SET
                    base_prefix = excluded.base_prefix,
                    failure_domain = excluded.failure_domain,
                    quota_bytes = excluded.quota_bytes,
                    role = excluded.role,
                    is_meta_backup = excluded.is_meta_backup",
                params![
                    node.node_id,
                    mapped_remote,
                    node.base_prefix,
                    node.failure_domain,
                    node.quota_bytes,
                    node.used_bytes,
                    node.role,
                    node.is_meta_backup,
                    node.health_score,
                    node.avg_latency_ms,
                    node.last_checked,
                ],
            )?;
        }

        let mut id_map: HashMap<i64, i64> = HashMap::new();
        for e in remote_entries {
            let new_id = insert_snapshot_entry(&tx, &e)?;
            id_map.insert(e.id, new_id);
        }
        for c in remote_chunks {
            if let Some(&new_entry_id) = id_map.get(&c.entry_id) {
                tx.execute(
                    "INSERT INTO file_chunks (entry_id, chunk_index, chunk_hash, plain_size, stored_size, encrypted)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![
                        new_entry_id,
                        c.chunk_index,
                        c.chunk_hash,
                        c.plain_size,
                        c.stored_size,
                        c.encrypted
                    ],
                )?;
            }
        }
        for r in remote_replicas {
            tx.execute(
                "INSERT OR IGNORE INTO chunk_replicas (chunk_hash, node_id, remote_relpath, status, verified_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![r.chunk_hash, r.node_id, r.remote_relpath, r.status, r.verified_at],
            )?;
        }
        for g in remote_gc {
            tx.execute(
                "INSERT OR IGNORE INTO gc_queue (chunk_hash, node_id, remote_relpath, queued_at, retry_count)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![g.chunk_hash, g.node_id, g.remote_relpath, g.queued_at, g.retry_count],
            )?;
        }

        set_meta_conn(&tx, "meta_version", &remote_version.to_string())?;
        set_meta_conn(&tx, "last_synced_version", &remote_version.to_string())?;
        set_meta_conn(&tx, "dirty", "0")?;
        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(())
    }

    /// Three-way path-level merge between local SQLite state and a remote
    /// snapshot (`remote_version`).
    ///
    /// Rules:
    /// - Entries present only on one side are kept (unless tombstone is newer than
    ///   last_synced).
    /// - Same active path modified on both sides with different content/kind:
    ///   newer `mtime_ms` wins the original path, and the other file is kept as
    ///   `<stem> (conflict <short_device>).<ext>`.
    /// - Replica rows are unioned (latest `verified_at` wins status).
    /// - Returns the number of conflict copies created.
    pub fn merge_from_snapshot(
        &self,
        snapshot_path: &Path,
        remote_version: u64,
        local_device_id: &str,
    ) -> PoolResult<u32> {
        let remote_conn = open_configured_connection(snapshot_path, false)?;
        let mut conn = self.conn.lock();

        let local_entries = load_all_entries(&conn)?;
        let local_chunks = load_all_chunks(&conn)?;
        let local_replicas = load_all_replicas(&conn)?;
        let local_gc = load_all_gc(&conn)?;

        let remote_entries = load_all_entries(&remote_conn)?;
        let remote_chunks = load_all_chunks(&remote_conn)?;
        let remote_replicas = load_all_replicas(&remote_conn)?;
        let remote_nodes = load_all_nodes(&remote_conn)?;
        let remote_gc = load_all_gc(&remote_conn)?;
        let remote_device_id: String = remote_conn
            .query_row(
                "SELECT value FROM pool_meta WHERE key = 'device_id'",
                [],
                |r| r.get(0),
            )
            .unwrap_or_else(|_| "remote".to_string());

        let local_chunks_by_entry = group_chunks_by_entry(local_chunks);
        let remote_chunks_by_entry = group_chunks_by_entry(remote_chunks);

        let local_last_synced = get_meta_u64_conn(&conn, "last_synced_version")?;
        let local_meta_ver = get_meta_u64_conn(&conn, "meta_version")?;
        let next_ver = local_meta_ver.max(remote_version) + 1;

        let local_by_path = latest_entries_by_path(&local_entries);
        let remote_by_path = latest_entries_by_path(&remote_entries);

        let mut all_paths: HashSet<String> = HashSet::new();
        all_paths.extend(local_by_path.keys().cloned());
        all_paths.extend(remote_by_path.keys().cloned());
        let mut sorted_paths: Vec<String> = all_paths.into_iter().collect();
        sorted_paths.sort();

        #[derive(Clone)]
        struct MergedItem {
            entry: PoolEntryRecord,
            chunks: Vec<SnapshotChunk>,
        }

        let mut merged: BTreeMap<String, MergedItem> = BTreeMap::new();
        let mut conflicts_created = 0u32;

        for path in sorted_paths {
            let loc = local_by_path.get(&path);
            let rem = remote_by_path.get(&path);
            match (loc, rem) {
                (Some(l), None) => {
                    let cs = local_chunks_by_entry.get(&l.id).cloned().unwrap_or_default();
                    merged.insert(
                        path,
                        MergedItem {
                            entry: (*l).clone(),
                            chunks: cs,
                        },
                    );
                }
                (None, Some(r)) => {
                    let cs = remote_chunks_by_entry.get(&r.id).cloned().unwrap_or_default();
                    merged.insert(
                        path,
                        MergedItem {
                            entry: (*r).clone(),
                            chunks: cs,
                        },
                    );
                }
                (Some(l), Some(r)) => {
                    let l_chunks = local_chunks_by_entry.get(&l.id).cloned().unwrap_or_default();
                    let r_chunks = remote_chunks_by_entry.get(&r.id).cloned().unwrap_or_default();
                    let l_dirty = l.updated_meta_ver as u64 > local_last_synced;
                    let r_newer = r.updated_meta_ver as u64 > local_last_synced;

                    match (l.deleted_at, r.deleted_at) {
                        (Some(ld), Some(rd)) => {
                            let winner = if rd >= ld { (*r).clone() } else { (*l).clone() };
                            merged.insert(
                                path,
                                MergedItem {
                                    entry: winner,
                                    chunks: Vec::new(),
                                },
                            );
                        }
                        (Some(_), None) => {
                            // Local deleted vs remote. If local was modified after last_synced and remote wasn't, local tombstone wins;
                            // if remote has a newer active write, remote wins.
                            if !l_dirty || (r_newer && r.mtime_ms > l.deleted_at.unwrap_or(0)) {
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: (*r).clone(),
                                        chunks: r_chunks,
                                    },
                                );
                            } else {
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: (*l).clone(),
                                        chunks: Vec::new(),
                                    },
                                );
                            }
                        }
                        (None, Some(_)) => {
                            if l_dirty && l.mtime_ms > r.deleted_at.unwrap_or(0) {
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: (*l).clone(),
                                        chunks: l_chunks,
                                    },
                                );
                            } else {
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: (*r).clone(),
                                        chunks: Vec::new(),
                                    },
                                );
                            }
                        }
                        (None, None) => {
                            if l.kind == "dir" && r.kind == "dir" {
                                let mut winner = (*l).clone();
                                winner.mtime_ms = l.mtime_ms.max(r.mtime_ms);
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: winner,
                                        chunks: Vec::new(),
                                    },
                                );
                            } else if same_file_content(l, &l_chunks, r, &r_chunks) {
                                let winner = if r.mtime_ms >= l.mtime_ms {
                                    (*r).clone()
                                } else {
                                    (*l).clone()
                                };
                                let win_chunks = if r.mtime_ms >= l.mtime_ms {
                                    r_chunks
                                } else {
                                    l_chunks
                                };
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: winner,
                                        chunks: win_chunks,
                                    },
                                );
                            } else if !l_dirty {
                                // Only remote changed since sync.
                                merged.insert(
                                    path,
                                    MergedItem {
                                        entry: (*r).clone(),
                                        chunks: r_chunks,
                                    },
                                );
                            } else {
                                // True conflict: both sides hold distinct active content!
                                // Newer mtime keeps the canonical path; loser becomes conflict copy.
                                let (primary, primary_chunks, loser, loser_chunks, loser_dev) =
                                    if r.mtime_ms > l.mtime_ms {
                                        (
                                            (*r).clone(),
                                            r_chunks,
                                            (*l).clone(),
                                            l_chunks,
                                            local_device_id,
                                        )
                                    } else {
                                        (
                                            (*l).clone(),
                                            l_chunks,
                                            (*r).clone(),
                                            r_chunks,
                                            remote_device_id.as_str(),
                                        )
                                    };
                                merged.insert(
                                    path.clone(),
                                    MergedItem {
                                        entry: primary,
                                        chunks: primary_chunks,
                                    },
                                );
                                if loser.kind == "file" {
                                    let conflict_path = build_conflict_path(
                                        &path,
                                        loser_dev,
                                        &merged,
                                    );
                                    let (_, _, conflict_name) =
                                        normalize_vfs_path(&vfs_path_from_norm(&conflict_path))?;
                                    let mut conflict_entry = loser;
                                    conflict_entry.path = conflict_path.clone();
                                    conflict_entry.name = conflict_name;
                                    conflict_entry.updated_meta_ver = next_ver as i64;
                                    merged.insert(
                                        conflict_path,
                                        MergedItem {
                                            entry: conflict_entry,
                                            chunks: loser_chunks,
                                        },
                                    );
                                    conflicts_created += 1;
                                }
                            }
                        }
                    }
                }
                (None, None) => {}
            }
        }

        // Union replicas across both sides (latest verified_at wins).
        let mut replica_map: HashMap<(String, String), SnapshotReplica> = HashMap::new();
        for rep in local_replicas.into_iter().chain(remote_replicas) {
            let key = (rep.chunk_hash.clone(), rep.node_id.clone());
            replica_map
                .entry(key)
                .and_modify(|cur| {
                    if rep.verified_at > cur.verified_at {
                        *cur = rep.clone();
                    }
                })
                .or_insert(rep);
        }

        let mut gc_map: HashMap<(String, String), SnapshotGc> = HashMap::new();
        for g in local_gc.into_iter().chain(remote_gc) {
            gc_map
                .entry((g.chunk_hash.clone(), g.node_id.clone()))
                .or_insert(g);
        }

        let tx = conn.transaction()?;

        // Ensure all remote nodes exist in pool_nodes so replica foreign keys never fail.
        for rn in remote_nodes {
            tx.execute(
                "INSERT OR IGNORE INTO pool_nodes
                    (node_id, remote_id, base_prefix, failure_domain, quota_bytes, used_bytes,
                     role, is_meta_backup, health_score, avg_latency_ms, last_checked)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![
                    rn.node_id,
                    rn.remote_id,
                    rn.base_prefix,
                    rn.failure_domain,
                    rn.quota_bytes,
                    rn.used_bytes,
                    rn.role,
                    rn.is_meta_backup,
                    rn.health_score,
                    rn.avg_latency_ms,
                    rn.last_checked,
                ],
            )?;
        }

        tx.execute("DELETE FROM gc_queue", [])?;
        tx.execute("DELETE FROM chunk_replicas", [])?;
        tx.execute("DELETE FROM file_chunks", [])?;
        tx.execute("DELETE FROM entries", [])?;

        let mut live_hashes: HashSet<String> = HashSet::new();
        for (_, item) in merged {
            let new_id = insert_snapshot_entry(&tx, &item.entry)?;
            for ch in item.chunks {
                if item.entry.deleted_at.is_none() {
                    live_hashes.insert(ch.chunk_hash.clone());
                }
                tx.execute(
                    "INSERT INTO file_chunks (entry_id, chunk_index, chunk_hash, plain_size, stored_size, encrypted)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![
                        new_id,
                        ch.chunk_index,
                        ch.chunk_hash,
                        ch.plain_size,
                        ch.stored_size,
                        ch.encrypted
                    ],
                )?;
            }
        }

        for ((hash, node_id), rep) in replica_map {
            tx.execute(
                "INSERT OR IGNORE INTO chunk_replicas (chunk_hash, node_id, remote_relpath, status, verified_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![hash, node_id, rep.remote_relpath, rep.status, rep.verified_at],
            )?;
        }

        for ((hash, node_id), g) in gc_map {
            if !live_hashes.contains(&hash) {
                tx.execute(
                    "INSERT OR IGNORE INTO gc_queue (chunk_hash, node_id, remote_relpath, queued_at, retry_count)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![hash, node_id, g.remote_relpath, g.queued_at, g.retry_count],
                )?;
            }
        }

        set_meta_conn(&tx, "meta_version", &next_ver.to_string())?;
        set_meta_conn(&tx, "dirty", "1")?;
        recompute_node_usage_tx(&tx)?;
        tx.commit()?;
        Ok(conflicts_created)
    }
}

fn open_configured_connection(path: &Path, enable_wal: bool) -> PoolResult<Connection> {
    let conn = Connection::open(path)?;
    conn.busy_timeout(Duration::from_secs(10))?;
    if enable_wal {
        let mode: String = conn.query_row("PRAGMA journal_mode;", [], |r| r.get(0))?;
        if !mode.eq_ignore_ascii_case("wal") {
            let _ = conn.execute_batch("PRAGMA journal_mode = WAL;");
        }
    }
    conn.execute_batch(
        "
        PRAGMA foreign_keys = ON;
        PRAGMA synchronous = NORMAL;
        PRAGMA cache_size = -2000;
        PRAGMA temp_store = MEMORY;
        ",
    )?;
    Ok(conn)
}

fn set_meta_default(conn: &Connection, key: &str, value: &str) -> PoolResult<()> {
    conn.execute(
        "INSERT OR IGNORE INTO pool_meta (key, value) VALUES (?1, ?2)",
        params![key, value],
    )?;
    Ok(())
}

fn set_meta_conn(conn: &Connection, key: &str, value: &str) -> PoolResult<()> {
    conn.execute(
        "INSERT OR REPLACE INTO pool_meta (key, value) VALUES (?1, ?2)",
        params![key, value],
    )?;
    Ok(())
}

fn get_meta_u64_conn(conn: &Connection, key: &str) -> PoolResult<u64> {
    let val: Option<String> = conn
        .query_row(
            "SELECT value FROM pool_meta WHERE key = ?1",
            params![key],
            |r| r.get(0),
        )
        .optional()?;
    Ok(val.and_then(|s| s.parse::<u64>().ok()).unwrap_or(0))
}

fn bump_meta_version_tx(tx: &rusqlite::Transaction<'_>) -> PoolResult<u64> {
    let cur = get_meta_u64_conn(tx, "meta_version")?;
    let next = cur.saturating_add(1);
    set_meta_conn(tx, "meta_version", &next.to_string())?;
    set_meta_conn(tx, "dirty", "1")?;
    Ok(next)
}

fn row_to_entry_record(r: &rusqlite::Row<'_>) -> rusqlite::Result<PoolEntryRecord> {
    Ok(PoolEntryRecord {
        id: r.get(0)?,
        parent_path: r.get(1)?,
        path: r.get(2)?,
        name: r.get(3)?,
        kind: r.get(4)?,
        size_bytes: r.get::<_, i64>(5)?.max(0) as u64,
        mtime_ms: r.get(6)?,
        chunk_size: r.get::<_, i64>(7)?.max(0) as u32,
        content_hash: r.get(8)?,
        version: r.get(9)?,
        updated_meta_ver: r.get(10)?,
        deleted_at: r.get(11)?,
    })
}

fn query_active_entry(conn: &Connection, norm_path: &str) -> PoolResult<Option<PoolEntryRecord>> {
    let res = conn
        .query_row(
            "SELECT id, parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size,
                    content_hash, version, updated_meta_ver, deleted_at
             FROM entries WHERE path = ?1 AND deleted_at IS NULL",
            params![norm_path],
            row_to_entry_record,
        )
        .optional()?;
    Ok(res)
}

fn ensure_parent_dirs_tx(
    tx: &rusqlite::Transaction<'_>,
    norm_path: &str,
    now: i64,
    meta_ver: u64,
) -> PoolResult<()> {
    let segs: Vec<&str> = norm_path.split('/').filter(|s| !s.is_empty()).collect();
    if segs.len() <= 1 {
        return Ok(());
    }
    let mut cur_parent = String::new();
    for seg in &segs[..segs.len() - 1] {
        let cur_path = if cur_parent.is_empty() {
            (*seg).to_string()
        } else {
            format!("{cur_parent}/{seg}")
        };
        if let Some(existing) = query_active_entry(tx, &cur_path)? {
            if existing.kind != "dir" {
                return Err(PoolError::InvalidPath(format!(
                    "ancestor is a file, not a directory: {cur_path}"
                )));
            }
        } else {
            tx.execute(
                "INSERT INTO entries
                    (parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size, version, updated_meta_ver, deleted_at)
                 VALUES (?1, ?2, ?3, 'dir', 0, ?4, 0, 1, ?5, NULL)",
                params![cur_parent, cur_path, *seg, now, meta_ver as i64],
            )?;
        }
        cur_parent = cur_path;
    }
    Ok(())
}

fn recompute_node_usage_tx(tx: &rusqlite::Transaction<'_>) -> PoolResult<()> {
    tx.execute(
        "UPDATE pool_nodes SET used_bytes = COALESCE((
            SELECT SUM(c.stored_size)
            FROM chunk_replicas cr
            JOIN (
                SELECT chunk_hash, MAX(stored_size) AS stored_size
                FROM file_chunks
                GROUP BY chunk_hash
            ) c ON c.chunk_hash = cr.chunk_hash
            WHERE cr.node_id = pool_nodes.node_id AND cr.status != 'missing'
        ), 0)",
        [],
    )?;
    Ok(())
}

#[derive(Clone)]
struct SnapshotNode {
    node_id: String,
    remote_id: String,
    base_prefix: String,
    failure_domain: String,
    quota_bytes: i64,
    used_bytes: i64,
    role: String,
    is_meta_backup: i64,
    health_score: f64,
    avg_latency_ms: i64,
    last_checked: Option<i64>,
}

#[derive(Clone)]
struct SnapshotChunk {
    entry_id: i64,
    chunk_index: i64,
    chunk_hash: String,
    plain_size: i64,
    stored_size: i64,
    encrypted: i64,
}

#[derive(Clone)]
struct SnapshotReplica {
    chunk_hash: String,
    node_id: String,
    remote_relpath: String,
    status: String,
    verified_at: i64,
}

#[derive(Clone)]
struct SnapshotGc {
    chunk_hash: String,
    node_id: String,
    remote_relpath: String,
    queued_at: i64,
    retry_count: i64,
}

fn load_all_nodes(conn: &Connection) -> PoolResult<Vec<SnapshotNode>> {
    let mut stmt = conn.prepare(
        "SELECT node_id, remote_id, base_prefix, failure_domain, quota_bytes, used_bytes,
                role, is_meta_backup, health_score, avg_latency_ms, last_checked
         FROM pool_nodes",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(SnapshotNode {
            node_id: r.get(0)?,
            remote_id: r.get(1)?,
            base_prefix: r.get(2)?,
            failure_domain: r.get(3)?,
            quota_bytes: r.get(4)?,
            used_bytes: r.get(5)?,
            role: r.get(6)?,
            is_meta_backup: r.get(7)?,
            health_score: r.get(8)?,
            avg_latency_ms: r.get(9)?,
            last_checked: r.get(10)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_all_entries(conn: &Connection) -> PoolResult<Vec<PoolEntryRecord>> {
    let mut stmt = conn.prepare(
        "SELECT id, parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size,
                content_hash, version, updated_meta_ver, deleted_at
         FROM entries ORDER BY id ASC",
    )?;
    let rows = stmt.query_map([], row_to_entry_record)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_all_chunks(conn: &Connection) -> PoolResult<Vec<SnapshotChunk>> {
    let mut stmt = conn.prepare(
        "SELECT entry_id, chunk_index, chunk_hash, plain_size, stored_size, encrypted
         FROM file_chunks ORDER BY entry_id ASC, chunk_index ASC",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(SnapshotChunk {
            entry_id: r.get(0)?,
            chunk_index: r.get(1)?,
            chunk_hash: r.get(2)?,
            plain_size: r.get(3)?,
            stored_size: r.get(4)?,
            encrypted: r.get(5)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_all_replicas(conn: &Connection) -> PoolResult<Vec<SnapshotReplica>> {
    let mut stmt = conn.prepare(
        "SELECT chunk_hash, node_id, remote_relpath, status, verified_at FROM chunk_replicas",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(SnapshotReplica {
            chunk_hash: r.get(0)?,
            node_id: r.get(1)?,
            remote_relpath: r.get(2)?,
            status: r.get(3)?,
            verified_at: r.get(4)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn load_all_gc(conn: &Connection) -> PoolResult<Vec<SnapshotGc>> {
    let mut stmt = conn.prepare(
        "SELECT chunk_hash, node_id, remote_relpath, queued_at, retry_count FROM gc_queue",
    )?;
    let rows = stmt.query_map([], |r| {
        Ok(SnapshotGc {
            chunk_hash: r.get(0)?,
            node_id: r.get(1)?,
            remote_relpath: r.get(2)?,
            queued_at: r.get(3)?,
            retry_count: r.get(4)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

fn insert_snapshot_entry(tx: &rusqlite::Transaction<'_>, e: &PoolEntryRecord) -> PoolResult<i64> {
    tx.execute(
        "INSERT INTO entries
            (parent_path, path, name, kind, size_bytes, mtime_ms, chunk_size, content_hash,
             version, updated_meta_ver, deleted_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
        params![
            e.parent_path,
            e.path,
            e.name,
            e.kind,
            e.size_bytes.min(i64::MAX as u64) as i64,
            e.mtime_ms,
            e.chunk_size as i64,
            e.content_hash,
            e.version,
            e.updated_meta_ver,
            e.deleted_at,
        ],
    )?;
    Ok(tx.last_insert_rowid())
}

fn group_chunks_by_entry(chunks: Vec<SnapshotChunk>) -> HashMap<i64, Vec<SnapshotChunk>> {
    let mut map: HashMap<i64, Vec<SnapshotChunk>> = HashMap::new();
    for ch in chunks {
        map.entry(ch.entry_id).or_default().push(ch);
    }
    map
}

fn latest_entries_by_path(entries: &[PoolEntryRecord]) -> HashMap<String, &PoolEntryRecord> {
    let mut map: HashMap<String, &PoolEntryRecord> = HashMap::new();
    for e in entries {
        map.entry(e.path.clone())
            .and_modify(|cur| {
                // Active entry always supersedes an older tombstone at the same path;
                // otherwise pick the newer timestamp / id.
                let replace = match (cur.deleted_at, e.deleted_at) {
                    (Some(_), None) => true,
                    (None, Some(_)) => false,
                    _ => e.updated_meta_ver > cur.updated_meta_ver
                        || (e.updated_meta_ver == cur.updated_meta_ver && e.id > cur.id),
                };
                if replace {
                    *cur = e;
                }
            })
            .or_insert(e);
    }
    map
}

fn same_file_content(
    a: &PoolEntryRecord,
    a_chunks: &[SnapshotChunk],
    b: &PoolEntryRecord,
    b_chunks: &[SnapshotChunk],
) -> bool {
    if a.kind != b.kind || a.size_bytes != b.size_bytes {
        return false;
    }
    if a.content_hash.is_some() && a.content_hash == b.content_hash {
        return true;
    }
    if a_chunks.len() != b_chunks.len() {
        return false;
    }
    a_chunks
        .iter()
        .zip(b_chunks.iter())
        .all(|(x, y)| x.chunk_hash == y.chunk_hash && x.plain_size == y.plain_size)
}

fn build_conflict_path<V>(
    orig_path: &str,
    device_id: &str,
    existing: &BTreeMap<String, V>,
) -> String {
    let short_dev: String = device_id
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .take(8)
        .collect();
    let dev_tag = if short_dev.is_empty() {
        "peer".to_string()
    } else {
        short_dev
    };
    let (parent, name) = match orig_path.rsplit_once('/') {
        Some((p, n)) => (Some(p), n),
        None => (None, orig_path),
    };
    let (stem, ext) = match name.rfind('.') {
        Some(idx) if idx > 0 => (&name[..idx], &name[idx..]),
        _ => (name, ""),
    };

    for attempt in 0..1000u32 {
        let candidate_name = if attempt == 0 {
            format!("{stem} (conflict {dev_tag}){ext}")
        } else {
            format!("{stem} (conflict {dev_tag} {attempt}){ext}")
        };
        let full = match parent {
            Some(p) => format!("{p}/{candidate_name}"),
            None => candidate_name,
        };
        if !existing.contains_key(&full) {
            return full;
        }
    }
    format!("{orig_path}.conflict")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_legacy_db_and_migrates_remote_space_columns() {
        let dir = tempfile::tempdir().unwrap();
        let db_path = dir.path().join("legacy_meta.db");
        {
            let conn = Connection::open(&db_path).unwrap();
            conn.execute_batch(
                "
                CREATE TABLE pool_meta (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
                CREATE TABLE pool_nodes (
                    node_id        TEXT PRIMARY KEY,
                    remote_id      TEXT NOT NULL,
                    base_prefix    TEXT NOT NULL DEFAULT 'fm_pool',
                    failure_domain TEXT NOT NULL,
                    quota_bytes    INTEGER NOT NULL,
                    used_bytes     INTEGER NOT NULL DEFAULT 0,
                    role           TEXT NOT NULL DEFAULT 'rw',
                    is_meta_backup INTEGER NOT NULL DEFAULT 0,
                    health_score   REAL NOT NULL DEFAULT 1.0,
                    avg_latency_ms INTEGER NOT NULL DEFAULT 200,
                    last_checked   INTEGER
                );
                INSERT INTO pool_nodes
                    (node_id, remote_id, base_prefix, failure_domain, quota_bytes, used_bytes)
                VALUES ('n1', 'rem1', 'fm_pool', 'dom1', 1000, 250);
                ",
            )
            .unwrap();
        }

        let db = PoolMetaDb::open(&db_path, "legacy-pool", "dev-1").unwrap();
        let nodes = db.list_nodes().unwrap();
        assert_eq!(nodes.len(), 1);
        assert_eq!(nodes[0].node_id, "n1");
        assert_eq!(nodes[0].used_bytes, 250);
        assert_eq!(nodes[0].remote_free_bytes, None);
        assert_eq!(nodes[0].remote_total_bytes, None);

        db.update_node_space_db("n1", Some(400), Some(500)).unwrap();
        let after = db.list_nodes().unwrap();
        assert_eq!(after[0].remote_free_bytes, Some(400));
        assert_eq!(after[0].remote_total_bytes, Some(500));
    }
}
