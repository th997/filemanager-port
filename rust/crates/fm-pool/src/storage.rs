//! Remote member node I/O abstraction with directory caching and per-op
//! timeouts so a single stalled SFTP/WebDAV/S3 node never blocks the pool.

use crate::error::{PoolError, PoolResult};
use crate::health::HealthTracker;
use crate::meta::{now_millis, PoolMetaDb};
use crate::scheduler::NodePlacementInfo;
use async_trait::async_trait;
use fm_core::{VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt};

#[async_trait]
pub trait NodeVfsResolver: Send + Sync {
    async fn resolve(&self, remote_id: &str) -> VfsResult<Arc<dyn Vfs>>;
}

#[derive(Debug, Clone, Copy)]
pub struct PoolIoTimeouts {
    pub open_timeout: Duration,
    pub read_timeout: Duration,
    pub write_timeout: Duration,
    pub probe_timeout: Duration,
}

impl Default for PoolIoTimeouts {
    fn default() -> Self {
        Self {
            open_timeout: Duration::from_secs(15),
            read_timeout: Duration::from_secs(30),
            write_timeout: Duration::from_secs(90),
            probe_timeout: Duration::from_secs(10),
        }
    }
}

pub fn blob_relpath(chunk_hash: &str) -> String {
    let clean: String = chunk_hash
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .collect();
    if clean.len() >= 4 {
        format!("blobs/{}/{}/{}.blk", &clean[..2], &clean[2..4], clean)
    } else {
        format!("blobs/{clean}.blk")
    }
}

pub fn node_vfs_path(base_prefix: &str, relpath: &str) -> VfsPath {
    let prefix_trimmed = base_prefix.trim_matches('/');
    let rel_trimmed = relpath.trim_matches('/');
    let mut segs: Vec<String> = Vec::new();
    for s in prefix_trimmed.split('/').filter(|s| !s.is_empty()) {
        segs.push(s.to_string());
    }
    for s in rel_trimmed.split('/').filter(|s| !s.is_empty()) {
        segs.push(s.to_string());
    }
    VfsPath::new(segs)
}

pub struct RemoteNodeIo {
    resolver: Arc<dyn NodeVfsResolver>,
    health: Arc<HealthTracker>,
    meta: PoolMetaDb,
    timeouts: PoolIoTimeouts,
    created_dirs: RwLock<HashMap<String, HashSet<String>>>,
}

impl RemoteNodeIo {
    pub fn new(
        resolver: Arc<dyn NodeVfsResolver>,
        health: Arc<HealthTracker>,
        meta: PoolMetaDb,
        timeouts: PoolIoTimeouts,
    ) -> Self {
        Self {
            resolver,
            health,
            meta,
            timeouts,
            created_dirs: RwLock::new(HashMap::new()),
        }
    }

    pub fn clear_dir_cache(&self) {
        self.created_dirs.write().clear();
    }

    pub async fn resolve_node(&self, node: &NodePlacementInfo) -> PoolResult<Arc<dyn Vfs>> {
        let start = Instant::now();
        let res = tokio::time::timeout(
            self.timeouts.open_timeout,
            self.resolver.resolve(&node.remote_id),
        )
        .await;
        match res {
            Ok(Ok(vfs)) => Ok(vfs),
            Ok(Err(e)) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(e.to_string()))
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "resolve node {} timed out after {:?} ({}ms)",
                    node.node_id,
                    self.timeouts.open_timeout,
                    start.elapsed().as_millis()
                )))
            }
        }
    }

    pub fn record_success(&self, node_id: &str, latency_ms: u64) {
        let now = now_millis();
        let snap = self.health.record_success(node_id, latency_ms, now);
        let _ = self.meta.update_node_health_db(
            node_id,
            snap.health_score,
            snap.avg_latency_ms,
            now,
        );
    }

    pub fn record_failure(&self, node_id: &str) {
        let now = now_millis();
        let snap = self.health.record_failure(node_id, now);
        let _ = self.meta.update_node_health_db(
            node_id,
            snap.health_score,
            snap.avg_latency_ms,
            now,
        );
    }

    async fn ensure_parent_dirs(
        &self,
        vfs: &dyn Vfs,
        node: &NodePlacementInfo,
        target: &VfsPath,
    ) -> PoolResult<()> {
        if vfs.prefers_direct_write() {
            return Ok(());
        }
        let Some(parent) = target.parent() else {
            return Ok(());
        };
        if parent.is_root() {
            return Ok(());
        }
        let parent_key = parent.to_slash_string();
        if self
            .created_dirs
            .read()
            .get(&node.node_id)
            .map(|set| set.contains(&parent_key))
            .unwrap_or(false)
        {
            return Ok(());
        }

        let mut cur = VfsPath::root();
        for seg in parent.segments() {
            cur = cur.join(seg.clone());
            let cur_key = cur.to_slash_string();
            let already = self
                .created_dirs
                .read()
                .get(&node.node_id)
                .map(|set| set.contains(&cur_key))
                .unwrap_or(false);
            if already {
                continue;
            }
            if let Err(e) = tokio::time::timeout(self.timeouts.open_timeout, vfs.mkdir(&cur))
                .await
                .map_err(|_| PoolError::Backend(format!("mkdir {cur} timed out")))?
            {
                let exists_dir = tokio::time::timeout(self.timeouts.open_timeout, vfs.stat(&cur))
                    .await
                    .ok()
                    .and_then(|r| r.ok())
                    .map(|s| s.kind == fm_core::EntryKind::Dir)
                    .unwrap_or(false);
                if !exists_dir {
                    return Err(PoolError::Backend(format!(
                        "mkdir {cur} on node {} failed: {e}",
                        node.node_id
                    )));
                }
            }
            self.created_dirs
                .write()
                .entry(node.node_id.clone())
                .or_default()
                .insert(cur_key);
        }
        Ok(())
    }

    /// Write an object or chunk atomically onto `node` at `relpath`.
    pub async fn write_bytes(
        &self,
        node: &NodePlacementInfo,
        relpath: &str,
        bytes: &[u8],
    ) -> PoolResult<()> {
        let start = Instant::now();
        let vfs = self.resolve_node(node).await?;
        let target = node_vfs_path(&node.base_prefix, relpath);

        let res = tokio::time::timeout(self.timeouts.write_timeout, async {
            if let Err(_first_err) = self.ensure_parent_dirs(vfs.as_ref(), node, &target).await {
                // Retry once after clearing cached directory state in case a remote dir was removed.
                self.created_dirs.write().remove(&node.node_id);
                self.ensure_parent_dirs(vfs.as_ref(), node, &target).await?;
            }

            if vfs.prefers_direct_write() || !vfs.capabilities().rename {
                let mut w = vfs
                    .open_write(&target, WriteMode::Truncate)
                    .await
                    .map_err(|e| PoolError::Backend(e.to_string()))?;
                w.write_all(bytes).await?;
                w.shutdown().await?;
                Ok::<(), PoolError>(())
            } else {
                let tmp_name = format!(
                    ".{}.{}.fm-tmp",
                    target.name().unwrap_or("obj"),
                    uuid::Uuid::new_v4().simple()
                );
                let tmp_path = target.parent().unwrap_or_else(VfsPath::root).join(tmp_name);
                let write_res: PoolResult<()> = async {
                    let mut w = vfs
                        .open_write(&tmp_path, WriteMode::Truncate)
                        .await
                        .map_err(|e| PoolError::Backend(e.to_string()))?;
                    w.write_all(bytes).await?;
                    w.shutdown().await?;
                    Ok(())
                }
                .await;
                if let Err(e) = write_res {
                    let _ = vfs.remove(&tmp_path).await;
                    return Err(e);
                }

                if let Err(rename_err) = vfs.rename(&tmp_path, &target).await {
                    let _ = vfs.remove(&target).await;
                    if let Err(e2) = vfs.rename(&tmp_path, &target).await {
                        let _ = vfs.remove(&tmp_path).await;
                        return Err(PoolError::Backend(format!(
                            "rename {tmp_path} -> {target} failed: {rename_err}; retry: {e2}"
                        )));
                    }
                }
                Ok(())
            }
        })
        .await;

        match res {
            Ok(Ok(())) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(())
            }
            Ok(Err(e)) => {
                self.created_dirs.write().remove(&node.node_id);
                self.record_failure(&node.node_id);
                Err(e)
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "write to node {} ({relpath}) timed out after {:?}",
                    node.node_id, self.timeouts.write_timeout
                )))
            }
        }
    }

    pub async fn read_all(&self, node: &NodePlacementInfo, relpath: &str) -> PoolResult<Vec<u8>> {
        let start = Instant::now();
        let vfs = self.resolve_node(node).await?;
        let target = node_vfs_path(&node.base_prefix, relpath);

        let res = tokio::time::timeout(self.timeouts.read_timeout, async {
            let mut reader = vfs
                .open_read(&target)
                .await
                .map_err(|e| PoolError::Backend(e.to_string()))?;
            let mut out = Vec::new();
            reader.read_to_end(&mut out).await?;
            Ok::<Vec<u8>, PoolError>(out)
        })
        .await;

        match res {
            Ok(Ok(bytes)) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(bytes)
            }
            Ok(Err(e)) => {
                self.record_failure(&node.node_id);
                Err(e)
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "read from node {} ({relpath}) timed out after {:?}",
                    node.node_id, self.timeouts.read_timeout
                )))
            }
        }
    }

    pub async fn read_exact_range(
        &self,
        node: &NodePlacementInfo,
        relpath: &str,
        offset: u64,
        len: u64,
    ) -> PoolResult<Vec<u8>> {
        let start = Instant::now();
        let vfs = self.resolve_node(node).await?;
        let target = node_vfs_path(&node.base_prefix, relpath);

        let res = tokio::time::timeout(self.timeouts.read_timeout, async {
            let mut reader = vfs
                .open_read_range(&target, offset, Some(len))
                .await
                .map_err(|e| PoolError::Backend(e.to_string()))?;
            let mut out = Vec::with_capacity(len.min(1024 * 1024) as usize);
            reader.read_to_end(&mut out).await?;
            if (out.len() as u64) < len {
                return Err(PoolError::Backend(format!(
                    "unexpected EOF reading range offset={offset} len={len} from {} ({relpath}): got {} bytes",
                    node.node_id,
                    out.len()
                )));
            }
            Ok::<Vec<u8>, PoolError>(out)
        })
        .await;

        match res {
            Ok(Ok(bytes)) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(bytes)
            }
            Ok(Err(e)) => {
                self.record_failure(&node.node_id);
                Err(e)
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "range read from node {} ({relpath}) timed out",
                    node.node_id
                )))
            }
        }
    }

    pub async fn open_read_range_stream(
        &self,
        node: &NodePlacementInfo,
        relpath: &str,
        offset: u64,
        len: Option<u64>,
    ) -> PoolResult<Box<dyn AsyncRead + Send + Unpin>> {
        let start = Instant::now();
        let vfs = self.resolve_node(node).await?;
        let target = node_vfs_path(&node.base_prefix, relpath);

        let res = tokio::time::timeout(
            self.timeouts.open_timeout,
            vfs.open_read_range(&target, offset, len),
        )
        .await;
        match res {
            Ok(Ok(reader)) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(reader)
            }
            Ok(Err(e)) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(e.to_string()))
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "open_read_range on node {} ({relpath}) timed out",
                    node.node_id
                )))
            }
        }
    }

    pub async fn remove_blob(&self, node: &NodePlacementInfo, relpath: &str) -> PoolResult<()> {
        let start = Instant::now();
        let vfs = self.resolve_node(node).await?;
        let target = node_vfs_path(&node.base_prefix, relpath);

        let res = tokio::time::timeout(self.timeouts.open_timeout, vfs.remove(&target)).await;
        match res {
            Ok(Ok(())) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(())
            }
            Ok(Err(VfsError::NotFound { .. })) => {
                self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                Ok(())
            }
            Ok(Err(e)) => {
                // Some backends return Backend error with "not found" message for absent paths.
                let msg = e.to_string().to_ascii_lowercase();
                if msg.contains("not found") || msg.contains("no such file") || msg.contains("404") {
                    self.record_success(&node.node_id, start.elapsed().as_millis() as u64);
                    return Ok(());
                }
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(e.to_string()))
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(PoolError::Backend(format!(
                    "remove on node {} ({relpath}) timed out",
                    node.node_id
                )))
            }
        }
    }

    async fn refresh_node_space(
        &self,
        vfs: &dyn Vfs,
        node: &NodePlacementInfo,
        target: &VfsPath,
        force: bool,
    ) {
        if !vfs.supports_space_info() {
            let _ = self
                .meta
                .update_node_space_db(&node.node_id, None, None, Some(false));
            return;
        }
        if !force && node.space_supported == Some(false) {
            return;
        }
        let res = tokio::time::timeout(self.timeouts.probe_timeout, vfs.space_info(target)).await;
        match res {
            Ok(Ok(Some(info))) => {
                let _ = self.meta.update_node_space_db(
                    &node.node_id,
                    Some(info.free_bytes),
                    info.total_bytes,
                    Some(true),
                );
            }
            Ok(Ok(None)) => {
                let _ = self
                    .meta
                    .update_node_space_db(&node.node_id, None, None, Some(false));
            }
            Ok(Err(_)) | Err(_) => {
                // Transient error or timeout: preserve any previously cached space info.
            }
        }
    }

    pub async fn probe_node_space_only(&self, node: &NodePlacementInfo) {
        if node.role == crate::scheduler::NodeRole::Offline || node.space_supported == Some(false) {
            return;
        }
        let Ok(vfs) = self.resolve_node(node).await else {
            return;
        };
        if !vfs.supports_space_info() {
            let _ = self
                .meta
                .update_node_space_db(&node.node_id, None, None, Some(false));
            return;
        }
        let prefix_path = node_vfs_path(&node.base_prefix, "");
        let target = if prefix_path.is_root() {
            VfsPath::root()
        } else {
            prefix_path
        };
        self.refresh_node_space(vfs.as_ref(), node, &target, false)
            .await;
    }

    /// Recursively removes ONLY `<base_prefix>/blobs` and `<base_prefix>/meta`
    /// plus any tracked `known_relpaths`, never touching unrelated sibling files
    /// when `base_prefix` is `/`. Returns `(deleted_objects, failed_objects, node_reachable)`.
    pub async fn purge_node_pool_data(
        &self,
        node: &NodePlacementInfo,
        known_relpaths: &[String],
    ) -> (u64, u64, bool) {
        let Ok(vfs) = self.resolve_node(node).await else {
            return (0, known_relpaths.len().max(1) as u64, false);
        };

        let mut deleted = 0u64;
        let mut failed = 0u64;
        let mut attempted: HashSet<String> = HashSet::new();

        for sub in ["blobs", "meta"] {
            let root = node_vfs_path(&node.base_prefix, sub);
            let (d, f) = self
                .purge_subtree_recursive(vfs.as_ref(), &root, &mut attempted)
                .await;
            deleted = deleted.saturating_add(d);
            failed = failed.saturating_add(f);
        }

        for rel in known_relpaths {
            let target = node_vfs_path(&node.base_prefix, rel);
            if !attempted.insert(target.to_slash_string()) {
                continue;
            }
            match tokio::time::timeout(self.timeouts.open_timeout, vfs.remove(&target)).await {
                Ok(Ok(())) | Ok(Err(VfsError::NotFound { .. })) => {
                    deleted = deleted.saturating_add(1);
                }
                Ok(Err(e)) => {
                    let lower = e.to_string().to_ascii_lowercase();
                    if lower.contains("not found")
                        || lower.contains("no such file")
                        || lower.contains("404")
                    {
                        deleted = deleted.saturating_add(1);
                    } else {
                        failed = failed.saturating_add(1);
                    }
                }
                Err(_) => {
                    failed = failed.saturating_add(1);
                }
            }
        }

        let prefix_path = node_vfs_path(&node.base_prefix, "");
        if !prefix_path.is_root() {
            if let Ok(Ok(entries)) =
                tokio::time::timeout(self.timeouts.probe_timeout, vfs.list(&prefix_path)).await
            {
                if entries.is_empty() {
                    let _ =
                        tokio::time::timeout(self.timeouts.open_timeout, vfs.remove(&prefix_path))
                            .await;
                }
            }
        }

        self.created_dirs.write().remove(&node.node_id);
        (deleted, failed, true)
    }

    async fn purge_subtree_recursive(
        &self,
        vfs: &dyn Vfs,
        subtree_root: &VfsPath,
        attempted: &mut HashSet<String>,
    ) -> (u64, u64) {
        const MAX_DEPTH: usize = 8;
        let mut queue: Vec<(VfsPath, usize)> = vec![(subtree_root.clone(), 0)];
        let mut files: Vec<VfsPath> = Vec::new();
        let mut dirs: Vec<VfsPath> = Vec::new();

        while let Some((dir, depth)) = queue.pop() {
            let Ok(res) = tokio::time::timeout(self.timeouts.probe_timeout, vfs.list(&dir)).await
            else {
                continue;
            };
            match res {
                Ok(entries) => {
                    dirs.push(dir.clone());
                    for entry in entries {
                        if entry.kind == fm_core::EntryKind::Dir {
                            if depth < MAX_DEPTH {
                                queue.push((entry.path, depth + 1));
                            }
                        } else {
                            files.push(entry.path);
                        }
                    }
                }
                Err(VfsError::NotFound { .. }) => {}
                Err(e) => {
                    let lower = e.to_string().to_ascii_lowercase();
                    if !(lower.contains("not found")
                        || lower.contains("no such file")
                        || lower.contains("404"))
                    {
                        dirs.push(dir);
                    }
                }
            }
        }

        let mut deleted = 0u64;
        let mut failed = 0u64;

        for file in files {
            if !attempted.insert(file.to_slash_string()) {
                continue;
            }
            match tokio::time::timeout(self.timeouts.open_timeout, vfs.remove(&file)).await {
                Ok(Ok(())) | Ok(Err(VfsError::NotFound { .. })) => {
                    deleted = deleted.saturating_add(1);
                }
                Ok(Err(e)) => {
                    let lower = e.to_string().to_ascii_lowercase();
                    if lower.contains("not found")
                        || lower.contains("no such file")
                        || lower.contains("404")
                    {
                        deleted = deleted.saturating_add(1);
                    } else {
                        failed = failed.saturating_add(1);
                    }
                }
                Err(_) => {
                    failed = failed.saturating_add(1);
                }
            }
        }

        for dir in dirs.into_iter().rev() {
            let _ = tokio::time::timeout(self.timeouts.open_timeout, vfs.remove(&dir)).await;
        }

        (deleted, failed)
    }

    pub async fn probe_node(&self, node: &NodePlacementInfo) -> Result<u64, String> {
        let start = Instant::now();
        let vfs = self
            .resolve_node(node)
            .await
            .map_err(|e| e.to_string())?;
        let prefix_path = node_vfs_path(&node.base_prefix, "");
        let target = if prefix_path.is_root() {
            VfsPath::root()
        } else {
            prefix_path
        };

        let res = tokio::time::timeout(self.timeouts.probe_timeout, vfs.list(&target)).await;
        let elapsed_ms = start.elapsed().as_millis().max(1) as u64;
        match res {
            Ok(Ok(_)) | Ok(Err(VfsError::NotFound { .. })) => {
                // If prefix doesn't exist yet, also check root so we distinguish
                // "unreachable server" from "prefix not yet created".
                if matches!(res, Ok(Err(VfsError::NotFound { .. }))) && !target.is_root() {
                    let root_res =
                        tokio::time::timeout(self.timeouts.probe_timeout, vfs.list(&VfsPath::root()))
                            .await;
                    match root_res {
                        Ok(Ok(_)) | Ok(Err(VfsError::NotFound { .. })) => {}
                        Ok(Err(e)) => {
                            self.record_failure(&node.node_id);
                            return Err(e.to_string());
                        }
                        Err(_) => {
                            self.record_failure(&node.node_id);
                            return Err("probe timed out".to_string());
                        }
                    }
                }
                self.health.reset_circuit(&node.node_id);
                self.record_success(&node.node_id, elapsed_ms);
                self.refresh_node_space(vfs.as_ref(), node, &target, true)
                    .await;
                Ok(elapsed_ms)
            }
            Ok(Err(e)) => {
                let msg = e.to_string();
                let lower = msg.to_ascii_lowercase();
                if lower.contains("not found") || lower.contains("no such file") {
                    self.health.reset_circuit(&node.node_id);
                    self.record_success(&node.node_id, elapsed_ms);
                    self.refresh_node_space(vfs.as_ref(), node, &target, true)
                        .await;
                    return Ok(elapsed_ms);
                }
                self.record_failure(&node.node_id);
                Err(msg)
            }
            Err(_) => {
                self.record_failure(&node.node_id);
                Err(format!(
                    "probe timed out after {:?}",
                    self.timeouts.probe_timeout
                ))
            }
        }
    }

    pub fn read_timeout(&self) -> Duration {
        self.timeouts.read_timeout
    }
}
