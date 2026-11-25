//! `fm-pool` — Heterogeneous distributed storage pool built on top of
//! `fm-vfs::Vfs`.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

pub mod chunker;
pub mod crypto;
pub mod error;
pub mod gc;
pub mod heal;
pub mod health;
pub mod meta;
pub mod scheduler;
pub mod storage;
pub mod sync;
pub mod vfs;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use crypto::PoolCrypto;
use error::{PoolError, PoolResult};
use fm_vault::crypto::{random_bytes, KdfParams};
use fm_vfs::Vfs;
use health::{CircuitState, HealthTracker};
use meta::{PoolMetaDb, PoolNodeSyncState};
use parking_lot::RwLock;
use scheduler::NodeRole;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;
pub use storage::NodeVfsResolver;
use storage::{PoolIoTimeouts, RemoteNodeIo};
use sync::{spawn_debounced_sync_worker, sync_pool_metadata, PoolSyncReport};
use tokio::sync::{Mutex as AsyncMutex, Notify};
use vfs::PoolVfs;

pub const DEFAULT_CHUNK_SIZE: u32 = 16 * 1024 * 1024;
pub const MIN_CHUNK_SIZE: u32 = 1024 * 1024;
pub const MAX_CHUNK_SIZE: u32 = 64 * 1024 * 1024;
pub const MAX_REPLICATION_FACTOR: usize = 16;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolNodeConfig {
    pub node_id: String,
    pub remote_id: String,
    #[serde(default = "default_base_prefix")]
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    #[serde(default)]
    pub role: NodeRole,
    #[serde(default)]
    pub is_meta_backup: bool,
}

fn default_base_prefix() -> String {
    "fm_pool".to_string()
}

#[derive(Clone, Serialize, Deserialize)]
pub struct PoolConfig {
    pub id: String,
    pub name: String,
    #[serde(default = "default_chunk_size")]
    pub chunk_size: u32,
    #[serde(default = "default_replication_factor")]
    pub replication_factor: usize,
    #[serde(default)]
    pub encrypt: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub passphrase: Option<String>,
    /// Base64-encoded 16-byte Argon2id salt (auto-generated on creation when encrypted).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kdf_salt: Option<String>,
    #[serde(default)]
    pub kdf_m_cost: Option<u32>,
    #[serde(default)]
    pub kdf_t_cost: Option<u32>,
    #[serde(default)]
    pub kdf_p_cost: Option<u32>,
    #[serde(default)]
    pub device_id: Option<String>,
    #[serde(default)]
    pub nodes: Vec<PoolNodeConfig>,
    #[serde(default)]
    pub created_at_ms: i64,
}

impl std::fmt::Debug for PoolConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PoolConfig")
            .field("id", &self.id)
            .field("name", &self.name)
            .field("chunk_size", &self.chunk_size)
            .field("replication_factor", &self.replication_factor)
            .field("encrypt", &self.encrypt)
            .field("passphrase", &self.passphrase.as_ref().map(|_| "<redacted>"))
            .field("nodes", &self.nodes.len())
            .finish()
    }
}

fn default_chunk_size() -> u32 {
    DEFAULT_CHUNK_SIZE
}

fn default_replication_factor() -> usize {
    2
}

impl PoolConfig {
    pub fn normalized_chunk_size(&self) -> u32 {
        self.chunk_size.clamp(MIN_CHUNK_SIZE, MAX_CHUNK_SIZE)
    }

    pub fn normalized_replication(&self) -> usize {
        self.replication_factor.clamp(1, MAX_REPLICATION_FACTOR)
    }

    pub fn kdf_salt_bytes(&self) -> Option<[u8; 16]> {
        let b64 = self.kdf_salt.as_deref()?;
        let raw = STANDARD.decode(b64.trim()).ok()?;
        <[u8; 16]>::try_from(raw.as_slice()).ok()
    }

    pub fn kdf_params(&self) -> KdfParams {
        let def = KdfParams::default();
        KdfParams {
            m_cost: self.kdf_m_cost.unwrap_or(def.m_cost),
            t_cost: self.kdf_t_cost.unwrap_or(def.t_cost),
            p_cost: self.kdf_p_cost.unwrap_or(def.p_cost),
        }
    }

    pub fn ensure_crypto_defaults(&mut self) {
        if self.encrypt && self.kdf_salt_bytes().is_none() {
            let salt = random_bytes::<16>();
            self.kdf_salt = Some(STANDARD.encode(salt));
        }
        if self
            .device_id
            .as_deref()
            .map(str::trim)
            .unwrap_or("")
            .is_empty()
        {
            self.device_id = Some(uuid::Uuid::new_v4().simple().to_string());
        }
        if self.created_at_ms == 0 {
            self.created_at_ms = meta::now_millis();
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolNodeStatus {
    pub node_id: String,
    pub remote_id: String,
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    pub used_bytes: u64,
    #[serde(default)]
    pub remote_free_bytes: Option<u64>,
    #[serde(default)]
    pub remote_total_bytes: Option<u64>,
    pub role: String,
    pub is_meta_backup: bool,
    pub health_score: f64,
    pub avg_latency_ms: u64,
    pub circuit_state: String,
    pub last_checked_ms: Option<i64>,
    pub last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolSummary {
    pub id: String,
    pub name: String,
    pub chunk_size: u32,
    pub replication_factor: usize,
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
    pub nodes: Vec<PoolNodeStatus>,
}

pub struct PoolState {
    config: RwLock<PoolConfig>,
    crypto: RwLock<Option<PoolCrypto>>,
    pool_dir: PathBuf,
    device_id: String,
    pub meta: PoolMetaDb,
    pub health: Arc<HealthTracker>,
    pub io: RemoteNodeIo,
    pub(crate) sync_lock: AsyncMutex<()>,
    sync_notify: Arc<Notify>,
    closed: AtomicBool,
}

impl PoolState {
    pub fn open(
        mut config: PoolConfig,
        pool_dir: impl AsRef<Path>,
        resolver: Arc<dyn NodeVfsResolver>,
        timeouts: PoolIoTimeouts,
        circuit_open_duration: Duration,
        sync_debounce: Duration,
    ) -> PoolResult<Arc<Self>> {
        config.ensure_crypto_defaults();
        let pool_dir = pool_dir.as_ref().to_path_buf();
        std::fs::create_dir_all(&pool_dir)?;
        let device_id = config
            .device_id
            .clone()
            .unwrap_or_else(|| uuid::Uuid::new_v4().simple().to_string());
        let db_path = pool_dir.join("meta.db");
        let meta = PoolMetaDb::open(&db_path, &config.id, &device_id)?;

        let crypto = if config.encrypt {
            let pass = config.passphrase.as_deref().unwrap_or("");
            let salt = config
                .kdf_salt_bytes()
                .ok_or_else(|| PoolError::Crypto("missing kdf_salt".to_string()))?;
            Some(PoolCrypto::from_passphrase(
                &config.id,
                pass,
                &salt,
                config.kdf_params(),
            )?)
        } else {
            None
        };

        let sync_nodes: Vec<PoolNodeSyncState> = config
            .nodes
            .iter()
            .map(|n| PoolNodeSyncState {
                node_id: n.node_id.clone(),
                remote_id: n.remote_id.clone(),
                base_prefix: if n.base_prefix.trim().is_empty() {
                    default_base_prefix()
                } else {
                    n.base_prefix.clone()
                },
                failure_domain: n.failure_domain.clone(),
                quota_bytes: n.quota_bytes,
                role: n.role,
                is_meta_backup: n.is_meta_backup,
            })
            .collect();
        meta.sync_nodes(&sync_nodes)?;

        let health = Arc::new(HealthTracker::new(circuit_open_duration, 3));
        for node in meta.list_nodes()? {
            health.seed_node(
                &node.node_id,
                node.db_health_score,
                node.db_avg_latency_ms,
                None,
            );
        }

        let io = RemoteNodeIo::new(resolver, Arc::clone(&health), meta.clone(), timeouts);
        let sync_notify = Arc::new(Notify::new());

        let state = Arc::new(Self {
            config: RwLock::new(config),
            crypto: RwLock::new(crypto),
            pool_dir,
            device_id,
            meta,
            health,
            io,
            sync_lock: AsyncMutex::new(()),
            sync_notify: Arc::clone(&sync_notify),
            closed: AtomicBool::new(false),
        });

        if tokio::runtime::Handle::try_current().is_ok() {
            let _handle = spawn_debounced_sync_worker(
                Arc::clone(&state),
                sync_notify,
                sync_debounce,
            );
        }

        Ok(state)
    }

    pub fn open_default(
        config: PoolConfig,
        pool_dir: impl AsRef<Path>,
        resolver: Arc<dyn NodeVfsResolver>,
    ) -> PoolResult<Arc<Self>> {
        Self::open(
            config,
            pool_dir,
            resolver,
            PoolIoTimeouts::default(),
            Duration::from_secs(30),
            Duration::from_secs(2),
        )
    }

    pub fn update_config(&self, mut next: PoolConfig) -> PoolResult<()> {
        next.ensure_crypto_defaults();
        let new_crypto = if next.encrypt {
            let pass = next.passphrase.as_deref().unwrap_or("");
            let salt = next
                .kdf_salt_bytes()
                .ok_or_else(|| PoolError::Crypto("missing kdf_salt".to_string()))?;
            Some(PoolCrypto::from_passphrase(
                &next.id,
                pass,
                &salt,
                next.kdf_params(),
            )?)
        } else {
            None
        };

        let sync_nodes: Vec<PoolNodeSyncState> = next
            .nodes
            .iter()
            .map(|n| PoolNodeSyncState {
                node_id: n.node_id.clone(),
                remote_id: n.remote_id.clone(),
                base_prefix: if n.base_prefix.trim().is_empty() {
                    default_base_prefix()
                } else {
                    n.base_prefix.clone()
                },
                failure_domain: n.failure_domain.clone(),
                quota_bytes: n.quota_bytes,
                role: n.role,
                is_meta_backup: n.is_meta_backup,
            })
            .collect();
        self.meta.sync_nodes(&sync_nodes)?;
        for node in self.meta.list_nodes()? {
            self.health.seed_node(
                &node.node_id,
                node.db_health_score,
                node.db_avg_latency_ms,
                None,
            );
        }

        *self.crypto.write() = new_crypto;
        *self.config.write() = next;
        self.io.clear_dir_cache();
        Ok(())
    }

    pub fn pool_id(&self) -> String {
        self.config.read().id.clone()
    }

    pub fn config_snapshot(&self) -> PoolConfig {
        self.config.read().clone()
    }

    pub fn chunk_size(&self) -> u32 {
        self.config.read().normalized_chunk_size()
    }

    pub fn replication_factor(&self) -> usize {
        self.config.read().normalized_replication()
    }

    pub fn is_encrypted(&self) -> bool {
        self.crypto.read().is_some()
    }

    pub fn crypto(&self) -> Option<PoolCrypto> {
        self.crypto.read().clone()
    }

    pub fn pool_dir(&self) -> &Path {
        &self.pool_dir
    }

    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }

    pub fn mark_closed(&self) {
        self.closed.store(true, Ordering::Release);
        self.sync_notify.notify_waiters();
    }

    pub fn schedule_debounced_sync(&self) {
        self.sync_notify.notify_one();
    }

    pub async fn probe_all_nodes(&self) -> PoolResult<Vec<PoolNodeStatus>> {
        let nodes = self.meta.list_nodes()?;
        let futs = nodes.iter().map(|node| async {
            let err = if node.role == NodeRole::Offline {
                Some("offline".to_string())
            } else {
                self.io.probe_node(node).await.err()
            };
            (node.node_id.clone(), err)
        });
        let probe_results = futures_util::future::join_all(futs).await;
        let errors: HashMap<String, Option<String>> = probe_results.into_iter().collect();

        let refreshed_nodes = self.meta.list_nodes()?;
        Ok(refreshed_nodes
            .into_iter()
            .map(|n| {
                let snap = self.health.snapshot(&n.node_id);
                let circuit = match snap.circuit_state {
                    CircuitState::Closed => "closed",
                    CircuitState::Open { .. } => "open",
                    CircuitState::HalfOpen => "half_open",
                };
                PoolNodeStatus {
                    last_error: errors.get(&n.node_id).cloned().flatten(),
                    node_id: n.node_id,
                    remote_id: n.remote_id,
                    base_prefix: n.base_prefix,
                    failure_domain: n.failure_domain,
                    quota_bytes: n.quota_bytes,
                    used_bytes: n.used_bytes,
                    remote_free_bytes: n.remote_free_bytes,
                    remote_total_bytes: n.remote_total_bytes,
                    role: n.role.as_str().to_string(),
                    is_meta_backup: n.is_meta_backup,
                    health_score: snap.health_score,
                    avg_latency_ms: snap.avg_latency_ms,
                    circuit_state: circuit.to_string(),
                    last_checked_ms: snap.last_checked_ms,
                }
            })
            .collect())
    }

    pub fn summary(&self) -> PoolResult<PoolSummary> {
        let cfg = self.config.read().clone();
        let db_stats = self.meta.compute_stats(cfg.normalized_replication())?;
        let db_nodes = self.meta.list_nodes()?;
        let nodes = db_nodes
            .into_iter()
            .map(|n| {
                let snap = self.health.snapshot(&n.node_id);
                PoolNodeStatus {
                    node_id: n.node_id,
                    remote_id: n.remote_id,
                    base_prefix: n.base_prefix,
                    failure_domain: n.failure_domain,
                    quota_bytes: n.quota_bytes,
                    used_bytes: n.used_bytes,
                    remote_free_bytes: n.remote_free_bytes,
                    remote_total_bytes: n.remote_total_bytes,
                    role: n.role.as_str().to_string(),
                    is_meta_backup: n.is_meta_backup,
                    health_score: snap.health_score,
                    avg_latency_ms: snap.avg_latency_ms,
                    circuit_state: snap.circuit_state.as_str().to_string(),
                    last_checked_ms: snap.last_checked_ms,
                    last_error: None,
                }
            })
            .collect();

        let chunk_size = cfg.normalized_chunk_size();
        let replication_factor = cfg.normalized_replication();
        Ok(PoolSummary {
            id: cfg.id,
            name: cfg.name,
            chunk_size,
            replication_factor,
            encrypted: cfg.encrypt,
            total_physical_quota: db_stats.total_physical_quota,
            effective_logical_capacity: db_stats.effective_logical_capacity,
            total_physical_used: db_stats.total_physical_used,
            logical_used_bytes: db_stats.logical_used_bytes,
            file_count: db_stats.file_count,
            dir_count: db_stats.dir_count,
            degraded_chunks: db_stats.degraded_chunks,
            pending_gc_count: db_stats.pending_gc_count,
            meta_version: db_stats.meta_version,
            dirty: db_stats.dirty,
            nodes,
        })
    }

    pub async fn sync_metadata(&self) -> PoolResult<PoolSyncReport> {
        sync_pool_metadata(self).await
    }
}

pub struct PoolManager {
    pools_dir: RwLock<Option<PathBuf>>,
    resolver: RwLock<Option<Arc<dyn NodeVfsResolver>>>,
    pools: RwLock<HashMap<String, Arc<PoolState>>>,
}

static INSTANCE: OnceLock<PoolManager> = OnceLock::new();

impl Default for PoolManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PoolManager {
    pub fn global() -> &'static Self {
        INSTANCE.get_or_init(Self::new)
    }

    pub fn new() -> Self {
        Self {
            pools_dir: RwLock::new(None),
            resolver: RwLock::new(None),
            pools: RwLock::new(HashMap::new()),
        }
    }

    pub fn init(&self, pools_dir: impl Into<PathBuf>, resolver: Arc<dyn NodeVfsResolver>) {
        let dir: PathBuf = pools_dir.into();
        let _ = std::fs::create_dir_all(&dir);
        *self.pools_dir.write() = Some(dir);
        *self.resolver.write() = Some(resolver);
    }

    pub fn register_or_reload_pool(&self, config: PoolConfig) -> PoolResult<Arc<PoolState>> {
        let pools_dir = self
            .pools_dir
            .read()
            .clone()
            .ok_or_else(|| PoolError::Backend("pool manager not initialized".to_string()))?;
        let resolver = self
            .resolver
            .read()
            .clone()
            .ok_or_else(|| PoolError::Backend("pool resolver not initialized".to_string()))?;

        if let Some(existing) = self.pools.read().get(&config.id).cloned() {
            existing.update_config(config)?;
            return Ok(existing);
        }

        let pool_dir = pools_dir.join(&config.id);
        let state = PoolState::open_default(config.clone(), pool_dir, resolver)?;
        self.pools.write().insert(config.id, Arc::clone(&state));
        Ok(state)
    }

    pub fn get_pool(&self, pool_id: &str) -> PoolResult<Arc<PoolState>> {
        self.pools
            .read()
            .get(pool_id)
            .cloned()
            .ok_or_else(|| PoolError::NotFound(pool_id.to_string()))
    }

    pub fn get_vfs(&self, pool_id: &str) -> PoolResult<Arc<dyn Vfs>> {
        let state = self.get_pool(pool_id)?;
        Ok(Arc::new(PoolVfs::new(state)))
    }

    pub fn remove_pool(&self, pool_id: &str, delete_local_meta: bool) {
        if let Some(state) = self.pools.write().remove(pool_id) {
            state.mark_closed();
        }
        if delete_local_meta {
            if let Some(dir) = self.pools_dir.read().as_ref() {
                let _ = std::fs::remove_dir_all(dir.join(pool_id));
            }
        }
    }

    pub fn invalidate_remote_caches(&self) {
        for state in self.pools.read().values() {
            state.io.clear_dir_cache();
        }
    }

    pub fn is_pool_encrypted(&self, pool_id: &str) -> bool {
        self.pools
            .read()
            .get(pool_id)
            .map(|s| s.is_encrypted())
            .unwrap_or(false)
    }
}
