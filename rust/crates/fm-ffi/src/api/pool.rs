use crate::api::file_manager::invalidate_dir_cache_for_pool;
use crate::api::servers::stop_media_streams_for_pool;
use crate::api::tasks::{finish_sync_task, register_sync_task};
use crate::registry::VfsRegistry;
use fm_index::PoolRecord;
use fm_pool::gc::{run_gc, DEFAULT_GC_GRACE_PERIOD_MS};
use fm_pool::heal::{run_drain, run_heal};
use fm_pool::scheduler::NodeRole;
use fm_pool::sync::PoolSyncReport;
use fm_pool::{PoolConfig, PoolManager, PoolNodeConfig, PoolNodeStatus, PoolSummary};

#[derive(Debug, Clone)]
pub struct PoolNodeConfigDto {
    pub node_id: String,
    pub remote_id: String,
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    pub role: String,
    pub is_meta_backup: bool,
}

#[derive(Debug, Clone)]
pub struct PoolConfigDto {
    pub id: String,
    pub name: String,
    pub chunk_size: u32,
    pub replication_factor: u32,
    pub encrypt: bool,
    pub passphrase: Option<String>,
    pub kdf_salt: Option<String>,
    pub nodes: Vec<PoolNodeConfigDto>,
}

#[derive(Debug, Clone)]
pub struct PoolNodeStatusDto {
    pub node_id: String,
    pub remote_id: String,
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    pub used_bytes: u64,
    pub remote_free_bytes: Option<u64>,
    pub remote_total_bytes: Option<u64>,
    pub role: String,
    pub is_meta_backup: bool,
    pub health_score: f64,
    pub avg_latency_ms: u64,
    pub circuit_state: String,
    pub last_checked_ms: Option<i64>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct PoolSummaryDto {
    pub id: String,
    pub name: String,
    pub chunk_size: u32,
    pub replication_factor: u32,
    pub encrypted: bool,
    pub total_physical_quota: u64,
    pub effective_logical_capacity: u64,
    pub total_physical_used: u64,
    pub logical_used_bytes: u64,
    pub file_count: u64,
    pub dir_count: u64,
    pub degraded_chunks: u64,
    pub pending_gc_count: u64,
    pub meta_version: u64,
    pub dirty: bool,
    pub nodes: Vec<PoolNodeStatusDto>,
}

#[derive(Debug, Clone)]
pub struct PoolSyncReportDto {
    pub action: String,
    pub local_version_before: u64,
    pub remote_version: u64,
    pub final_version: u64,
    pub uploaded_backups: u32,
    pub conflicts_created: u32,
}

impl From<PoolNodeStatus> for PoolNodeStatusDto {
    fn from(s: PoolNodeStatus) -> Self {
        Self {
            node_id: s.node_id,
            remote_id: s.remote_id,
            base_prefix: s.base_prefix,
            failure_domain: s.failure_domain,
            quota_bytes: s.quota_bytes,
            used_bytes: s.used_bytes,
            remote_free_bytes: s.remote_free_bytes,
            remote_total_bytes: s.remote_total_bytes,
            role: s.role,
            is_meta_backup: s.is_meta_backup,
            health_score: s.health_score,
            avg_latency_ms: s.avg_latency_ms,
            circuit_state: s.circuit_state,
            last_checked_ms: s.last_checked_ms,
            last_error: s.last_error,
        }
    }
}

impl From<PoolSummary> for PoolSummaryDto {
    fn from(s: PoolSummary) -> Self {
        Self {
            id: s.id,
            name: s.name,
            chunk_size: s.chunk_size,
            replication_factor: s.replication_factor as u32,
            encrypted: s.encrypted,
            total_physical_quota: s.total_physical_quota,
            effective_logical_capacity: s.effective_logical_capacity,
            total_physical_used: s.total_physical_used,
            logical_used_bytes: s.logical_used_bytes,
            file_count: s.file_count,
            dir_count: s.dir_count,
            degraded_chunks: s.degraded_chunks,
            pending_gc_count: s.pending_gc_count,
            meta_version: s.meta_version,
            dirty: s.dirty,
            nodes: s.nodes.into_iter().map(PoolNodeStatusDto::from).collect(),
        }
    }
}

impl From<PoolSyncReport> for PoolSyncReportDto {
    fn from(r: PoolSyncReport) -> Self {
        Self {
            action: r.action,
            local_version_before: r.local_version_before,
            remote_version: r.remote_version,
            final_version: r.final_version,
            uploaded_backups: r.uploaded_backups,
            conflicts_created: r.conflicts_created,
        }
    }
}

impl From<PoolConfig> for PoolConfigDto {
    fn from(c: PoolConfig) -> Self {
        Self {
            id: c.id,
            name: c.name,
            chunk_size: c.chunk_size,
            replication_factor: c.replication_factor as u32,
            encrypt: c.encrypt,
            passphrase: c.passphrase,
            kdf_salt: c.kdf_salt,
            nodes: c
                .nodes
                .into_iter()
                .map(|n| PoolNodeConfigDto {
                    node_id: n.node_id,
                    remote_id: n.remote_id,
                    base_prefix: n.base_prefix,
                    failure_domain: n.failure_domain,
                    quota_bytes: n.quota_bytes,
                    role: n.role.as_str().to_string(),
                    is_meta_backup: n.is_meta_backup,
                })
                .collect(),
        }
    }
}

fn dto_to_pool_config(dto: PoolConfigDto, existing: Option<&PoolConfig>) -> PoolConfig {
    let mut cfg = PoolConfig {
        id: dto.id,
        name: dto.name,
        chunk_size: dto.chunk_size,
        replication_factor: dto
            .replication_factor
            .clamp(1, fm_pool::MAX_REPLICATION_FACTOR as u32) as usize,
        encrypt: dto.encrypt,
        passphrase: dto.passphrase.filter(|p| !p.is_empty()).or_else(|| {
            if dto.encrypt {
                existing.and_then(|e| e.passphrase.clone())
            } else {
                None
            }
        }),
        kdf_salt: dto
            .kdf_salt
            .filter(|s| !s.is_empty())
            .or_else(|| existing.and_then(|e| e.kdf_salt.clone())),
        kdf_m_cost: existing.and_then(|e| e.kdf_m_cost),
        kdf_t_cost: existing.and_then(|e| e.kdf_t_cost),
        kdf_p_cost: existing.and_then(|e| e.kdf_p_cost),
        device_id: existing.and_then(|e| e.device_id.clone()),
        nodes: dto
            .nodes
            .into_iter()
            .map(|n| PoolNodeConfig {
                node_id: n.node_id,
                remote_id: n.remote_id,
                base_prefix: if n.base_prefix.trim().is_empty() {
                    "fm_pool".to_string()
                } else {
                    n.base_prefix
                },
                failure_domain: n.failure_domain,
                quota_bytes: n.quota_bytes,
                role: NodeRole::parse(&n.role),
                is_meta_backup: n.is_meta_backup,
            })
            .collect(),
        created_at_ms: existing.map(|e| e.created_at_ms).unwrap_or(0),
    };
    cfg.ensure_crypto_defaults();
    cfg
}

pub async fn list_pools(db_path: String) -> Result<Vec<PoolSummaryDto>, String> {
    let reg = VfsRegistry::global();
    if reg.get_database_path().is_none() {
        reg.set_database_path(db_path.clone());
    }
    let db = reg.open_database(&db_path)?;
    let records = db.list_pools().map_err(|e| e.to_string())?;
    let mut summaries = Vec::with_capacity(records.len());
    for rec in records {
        let cfg: PoolConfig = match serde_json::from_str(&rec.config_json) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let state = PoolManager::global()
            .register_or_reload_pool(cfg)
            .map_err(|e| e.to_string())?;
        let summary = state.summary().map_err(|e| e.to_string())?;
        summaries.push(PoolSummaryDto::from(summary));
    }
    Ok(summaries)
}

pub async fn get_pool_config(db_path: String, pool_id: String) -> Result<PoolConfigDto, String> {
    let reg = VfsRegistry::global();
    let db = reg.open_database(&db_path)?;
    let rec = db
        .get_pool(&pool_id)
        .map_err(|e| e.to_string())?
        .ok_or_else(|| format!("storage pool '{pool_id}' not found"))?;
    let mut cfg: PoolConfig =
        serde_json::from_str(&rec.config_json).map_err(|e| e.to_string())?;
    // Never send stored passphrase back over FFI unnecessarily; keep salt so edits preserve KDF.
    cfg.passphrase = None;
    Ok(PoolConfigDto::from(cfg))
}

pub async fn save_pool_config(
    db_path: String,
    config: PoolConfigDto,
) -> Result<PoolSummaryDto, String> {
    let reg = VfsRegistry::global();
    if reg.get_database_path().is_none() {
        reg.set_database_path(db_path.clone());
    }
    let db = reg.open_database(&db_path)?;
    let existing = db
        .get_pool(&config.id)
        .map_err(|e| e.to_string())?
        .and_then(|rec| serde_json::from_str::<PoolConfig>(&rec.config_json).ok());

    let mut pool_cfg = dto_to_pool_config(config, existing.as_ref());
    if pool_cfg.id.trim().is_empty() {
        pool_cfg.id = uuid::Uuid::new_v4().simple().to_string();
    }
    if pool_cfg.name.trim().is_empty() {
        return Err("pool name cannot be empty".to_string());
    }
    if pool_cfg.nodes.is_empty() {
        return Err("storage pool must contain at least one member node".to_string());
    }

    let state = PoolManager::global()
        .register_or_reload_pool(pool_cfg.clone())
        .map_err(|e| e.to_string())?;

    let json = serde_json::to_string(&pool_cfg).map_err(|e| e.to_string())?;
    let record = PoolRecord {
        id: pool_cfg.id.clone(),
        name: pool_cfg.name.clone(),
        config_json: json,
        created_at: pool_cfg.created_at_ms,
    };
    db.save_pool(&record).map_err(|e| e.to_string())?;
    reg.invalidate_pool(&pool_cfg.id);
    invalidate_dir_cache_for_pool(&pool_cfg.id);

    let summary = state.summary().map_err(|e| e.to_string())?;
    Ok(PoolSummaryDto::from(summary))
}

pub async fn delete_pool(db_path: String, pool_id: String) -> Result<(), String> {
    let reg = VfsRegistry::global();
    let db = reg.open_database(&db_path)?;
    db.delete_pool(&pool_id).map_err(|e| e.to_string())?;
    stop_media_streams_for_pool(&pool_id);
    invalidate_dir_cache_for_pool(&pool_id);
    reg.invalidate_pool(&pool_id);
    PoolManager::global().remove_pool(&pool_id, true);
    Ok(())
}

pub async fn probe_pool_health(pool_id: String) -> Result<Vec<PoolNodeStatusDto>, String> {
    let state = VfsRegistry::global().ensure_pool_loaded(&pool_id)?;
    let statuses = state.probe_all_nodes().await.map_err(|e| e.to_string())?;
    Ok(statuses.into_iter().map(PoolNodeStatusDto::from).collect())
}

pub async fn sync_pool_metadata(pool_id: String) -> Result<PoolSyncReportDto, String> {
    let state = VfsRegistry::global().ensure_pool_loaded(&pool_id)?;
    let report = state.sync_metadata().await.map_err(|e| e.to_string())?;
    invalidate_dir_cache_for_pool(&pool_id);
    Ok(PoolSyncReportDto::from(report))
}

pub async fn start_pool_heal_task(pool_id: String) -> Result<String, String> {
    let state = VfsRegistry::global().ensure_pool_loaded(&pool_id)?;
    let (task_id, progress, cancel, control) = register_sync_task(&format!(
        "Pool Heal ({})",
        state.config_snapshot().name
    ));
    progress.lock().unwrap_or_else(|e| e.into_inner()).can_pause = true;

    tokio::spawn(async move {
        let res = run_heal(state, &progress, &cancel, &control)
            .await
            .map(|r| {
                if r.failed_chunks > 0 {
                    Err(format!(
                        "healed {} chunk(s), {} failed",
                        r.healed_chunks, r.failed_chunks
                    ))
                } else {
                    Ok(())
                }
            })
            .unwrap_or_else(|e| Err(e.to_string()));
        invalidate_dir_cache_for_pool(&pool_id);
        finish_sync_task(&progress, &cancel, res);
    });

    Ok(task_id)
}

pub async fn start_pool_drain_task(pool_id: String, node_id: String) -> Result<String, String> {
    let state = VfsRegistry::global().ensure_pool_loaded(&pool_id)?;
    let (task_id, progress, cancel, control) = register_sync_task(&format!(
        "Drain Node ({})",
        node_id
    ));
    progress.lock().unwrap_or_else(|e| e.into_inner()).can_pause = true;

    tokio::spawn(async move {
        let res = run_drain(state, &node_id, &progress, &cancel, &control)
            .await
            .map(|r| {
                if r.failed_chunks > 0 {
                    Err(format!(
                        "migrated {} chunk(s), {} failed",
                        r.migrated_chunks, r.failed_chunks
                    ))
                } else {
                    Ok(())
                }
            })
            .unwrap_or_else(|e| Err(e.to_string()));
        invalidate_dir_cache_for_pool(&pool_id);
        finish_sync_task(&progress, &cancel, res);
    });

    Ok(task_id)
}

pub async fn start_pool_gc_task(
    pool_id: String,
    purge_immediately: bool,
) -> Result<String, String> {
    let state = VfsRegistry::global().ensure_pool_loaded(&pool_id)?;
    let (task_id, progress, cancel, control) = register_sync_task(&format!(
        "Pool GC ({})",
        state.config_snapshot().name
    ));
    progress.lock().unwrap_or_else(|e| e.into_inner()).can_pause = true;

    let grace_ms = if purge_immediately {
        0
    } else {
        DEFAULT_GC_GRACE_PERIOD_MS
    };

    tokio::spawn(async move {
        let res = run_gc(state, grace_ms, &progress, &cancel, &control)
            .await
            .map(|_| ())
            .map_err(|e| e.to_string());
        invalidate_dir_cache_for_pool(&pool_id);
        finish_sync_task(&progress, &cancel, res);
    });

    Ok(task_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use fm_core::{VfsPath, WriteMode};
    use fm_index::Database;
    use fm_pool::NodeVfsResolver;
    use fm_vfs::{Vfs, VfsError, VfsResult};
    use std::collections::HashMap;
    use std::path::PathBuf;
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    struct LocalMapResolver(HashMap<String, PathBuf>);

    #[async_trait::async_trait]
    impl NodeVfsResolver for LocalMapResolver {
        async fn resolve(&self, remote_id: &str) -> VfsResult<Arc<dyn Vfs>> {
            let dir = self.0.get(remote_id).ok_or_else(|| VfsError::Connection {
                message: format!("missing {remote_id}"),
            })?;
            Ok(Arc::new(fm_local::LocalFs::new(dir)))
        }
    }

    #[tokio::test]
    async fn pool_dto_persistence_and_manager_vfs_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let db_file = dir.path().join("fm.db");
        let db = Database::open(&db_file, dir.path().join("trash")).unwrap();

        let n1_dir = dir.path().join("n1");
        let n2_dir = dir.path().join("n2");
        std::fs::create_dir_all(&n1_dir).unwrap();
        std::fs::create_dir_all(&n2_dir).unwrap();

        let dto = PoolConfigDto {
            id: "ffi-pool-1".into(),
            name: "FFI Pool".into(),
            chunk_size: 1024 * 1024,
            replication_factor: 2,
            encrypt: true,
            passphrase: Some("ffi-secret-pass".into()),
            kdf_salt: None,
            nodes: vec![
                PoolNodeConfigDto {
                    node_id: "n1".into(),
                    remote_id: "rem1".into(),
                    base_prefix: "fm_pool".into(),
                    failure_domain: "dom-a".into(),
                    quota_bytes: 10 * 1024 * 1024,
                    role: "rw".into(),
                    is_meta_backup: true,
                },
                PoolNodeConfigDto {
                    node_id: "n2".into(),
                    remote_id: "rem2".into(),
                    base_prefix: "fm_pool".into(),
                    failure_domain: "dom-b".into(),
                    quota_bytes: 10 * 1024 * 1024,
                    role: "rw".into(),
                    is_meta_backup: true,
                },
            ],
        };

        let cfg = dto_to_pool_config(dto, None);
        assert!(cfg.kdf_salt_bytes().is_some());
        let json = serde_json::to_string(&cfg).unwrap();
        db.save_pool(&PoolRecord {
            id: cfg.id.clone(),
            name: cfg.name.clone(),
            config_json: json,
            created_at: cfg.created_at_ms,
        })
        .unwrap();

        let loaded_rec = db.get_pool("ffi-pool-1").unwrap().unwrap();
        let loaded_cfg: PoolConfig = serde_json::from_str(&loaded_rec.config_json).unwrap();
        assert_eq!(loaded_cfg.passphrase.as_deref(), Some("ffi-secret-pass"));

        let mut map = HashMap::new();
        map.insert("rem1".to_string(), n1_dir);
        map.insert("rem2".to_string(), n2_dir);

        let mgr = PoolManager::new();
        mgr.init(dir.path().join("pools"), Arc::new(LocalMapResolver(map)));
        let state = mgr.register_or_reload_pool(loaded_cfg).unwrap();
        assert!(mgr.is_pool_encrypted("ffi-pool-1"));

        let vfs = mgr.get_vfs("ffi-pool-1").unwrap();
        let path = VfsPath::from_slash_path("/hello.txt");
        let mut w = vfs.open_write(&path, WriteMode::Truncate).await.unwrap();
        w.write_all(b"hello-ffi-pool").await.unwrap();
        w.shutdown().await.unwrap();

        let mut r = vfs.open_read(&path).await.unwrap();
        let mut out = Vec::new();
        r.read_to_end(&mut out).await.unwrap();
        assert_eq!(out, b"hello-ffi-pool");

        let summary_dto = PoolSummaryDto::from(state.summary().unwrap());
        assert_eq!(summary_dto.file_count, 1);
        assert_eq!(summary_dto.degraded_chunks, 0);
        assert!(summary_dto.encrypted);
    }
}
