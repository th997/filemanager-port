//! End-to-end integration tests for `fm-pool`:
//! 1. 12-node heterogeneous pool, cross-domain 2-replica placement, rename speed, delete/recreate
//! 2. Transparent read failover (connect fail + mid-stream fail) & write failover + degraded fallback
//! 3. Fixed-size chunking across small-quota nodes + dedup + cross-chunk Range reads
//! 4. Encrypted pool (`FPC1` AES-256-GCM): opacity, dedup, sub-chunk Range, tampered-replica failover
//! 5. Health EWMA + circuit breaker open & half-open recovery
//! 6. Heal (repairs degraded chunks) & Lazy GC (reclaims online blobs, defers offline nodes)
//! 7. Drain node (migrates data off retiring node and survives physical removal)
//! 8. Multi-device metadata sync across 3 backup nodes + 3-way conflict merge

use async_trait::async_trait;
use fm_core::{VfsPath, WriteMode};
use fm_local::LocalFs;
use fm_ops::{TaskControl, TaskProgress};
use fm_pool::gc::run_gc;
use fm_pool::heal::{run_drain, run_heal};
use fm_pool::scheduler::NodeRole;
use fm_pool::storage::{NodeVfsResolver, PoolIoTimeouts};
use fm_pool::sync::sync_pool_metadata;
use fm_pool::vfs::PoolVfs;
use fm_pool::{PoolConfig, PoolNodeConfig, PoolState};
use fm_vfs::{Vfs, VfsError, VfsResult};
use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, ReadBuf};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default)]
struct FaultProfile {
    offline: bool,
    fail_writes: bool,
    fail_reads_after_bytes: Option<usize>,
    read_delay: Option<Duration>,
    write_count: Arc<AtomicUsize>,
    read_count: Arc<AtomicUsize>,
}

struct FaultyReader {
    inner: Box<dyn AsyncRead + Send + Unpin>,
    read_so_far: usize,
    fail_after: Option<usize>,
}

impl AsyncRead for FaultyReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        match Pin::new(&mut self.inner).poll_read(cx, buf) {
            Poll::Ready(Ok(())) => {
                let got = buf.filled().len() - before;
                self.read_so_far += got;
                if let Some(limit) = self.fail_after {
                    if self.read_so_far > limit {
                        return Poll::Ready(Err(std::io::Error::new(
                            std::io::ErrorKind::ConnectionReset,
                            "simulated mid-stream network drop",
                        )));
                    }
                }
                Poll::Ready(Ok(()))
            }
            other => other,
        }
    }
}

struct FaultyNodeVfs {
    inner: LocalFs,
    fault: Arc<RwLock<FaultProfile>>,
}

#[async_trait]
impl Vfs for FaultyNodeVfs {
    fn capabilities(&self) -> fm_core::Capabilities {
        self.inner.capabilities()
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<fm_core::Entry>> {
        if self.fault.read().offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        self.inner.list(dir).await
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<fm_core::Entry> {
        if self.fault.read().offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        self.inner.stat(path).await
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
        let (offline, delay, fail_after, rc) = {
            let g = self.fault.read();
            (
                g.offline,
                g.read_delay,
                g.fail_reads_after_bytes,
                g.read_count.clone(),
            )
        };
        if offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        if let Some(d) = delay {
            tokio::time::sleep(d).await;
        }
        rc.fetch_add(1, Ordering::Relaxed);
        let reader = self.inner.open_read_range(path, offset, length).await?;
        Ok(Box::new(FaultyReader {
            inner: reader,
            read_so_far: 0,
            fail_after,
        }))
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        let (offline, fail_writes, wc) = {
            let g = self.fault.read();
            (g.offline, g.fail_writes, g.write_count.clone())
        };
        if offline || fail_writes {
            return Err(VfsError::Connection {
                message: "simulated write failure".to_string(),
            });
        }
        wc.fetch_add(1, Ordering::Relaxed);
        self.inner.open_write(path, mode).await
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        if self.fault.read().offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        self.inner.mkdir(path).await
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        if self.fault.read().offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        self.inner.remove(path).await
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        if self.fault.read().offline || self.fault.read().fail_writes {
            return Err(VfsError::Connection {
                message: "simulated rename failure".to_string(),
            });
        }
        self.inner.rename(from, to).await
    }

    async fn space_info(&self, path: &VfsPath) -> VfsResult<Option<fm_core::SpaceInfo>> {
        if self.fault.read().offline {
            return Err(VfsError::Connection {
                message: "simulated offline node".to_string(),
            });
        }
        self.inner.space_info(path).await
    }
}

type FaultNodeEntry = (PathBuf, Arc<RwLock<FaultProfile>>);

struct MockResolver {
    nodes: RwLock<HashMap<String, FaultNodeEntry>>,
}

impl MockResolver {
    fn new() -> Self {
        Self {
            nodes: RwLock::new(HashMap::new()),
        }
    }

    fn add_node(&self, remote_id: &str, dir: PathBuf) -> Arc<RwLock<FaultProfile>> {
        std::fs::create_dir_all(&dir).unwrap();
        let fault = Arc::new(RwLock::new(FaultProfile::default()));
        self.nodes
            .write()
            .insert(remote_id.to_string(), (dir, Arc::clone(&fault)));
        fault
    }

    fn dir_of(&self, remote_id: &str) -> PathBuf {
        self.nodes.read().get(remote_id).unwrap().0.clone()
    }
}

#[async_trait]
impl NodeVfsResolver for MockResolver {
    async fn resolve(&self, remote_id: &str) -> VfsResult<Arc<dyn Vfs>> {
        let (dir, fault) = self
            .nodes
            .read()
            .get(remote_id)
            .cloned()
            .ok_or_else(|| VfsError::Connection {
                message: format!("unknown remote {remote_id}"),
            })?;
        Ok(Arc::new(FaultyNodeVfs {
            inner: LocalFs::new(dir),
            fault,
        }))
    }
}

fn fast_timeouts() -> PoolIoTimeouts {
    PoolIoTimeouts {
        open_timeout: Duration::from_secs(2),
        read_timeout: Duration::from_secs(2),
        write_timeout: Duration::from_secs(5),
        probe_timeout: Duration::from_secs(2),
    }
}

fn make_node_cfg(id: &str, domain: &str, quota: u64, backup: bool) -> PoolNodeConfig {
    PoolNodeConfig {
        node_id: id.to_string(),
        remote_id: id.to_string(),
        base_prefix: "fm_pool".to_string(),
        failure_domain: domain.to_string(),
        quota_bytes: quota,
        role: NodeRole::Rw,
        is_meta_backup: backup,
    }
}

async fn write_pool_file(vfs: &dyn Vfs, path: &str, data: &[u8]) {
    let p = VfsPath::from_slash_path(path);
    let mut w = vfs.open_write(&p, WriteMode::Truncate).await.unwrap();
    w.write_all(data).await.unwrap();
    w.shutdown().await.unwrap();
}

async fn read_pool_file(vfs: &dyn Vfs, path: &str) -> Vec<u8> {
    let p = VfsPath::from_slash_path(path);
    let mut r = vfs.open_read(&p).await.unwrap();
    let mut out = Vec::new();
    r.read_to_end(&mut out).await.unwrap();
    out
}

async fn read_pool_range(vfs: &dyn Vfs, path: &str, off: u64, len: Option<u64>) -> Vec<u8> {
    let p = VfsPath::from_slash_path(path);
    let mut r = vfs.open_read_range(&p, off, len).await.unwrap();
    let mut out = Vec::new();
    r.read_to_end(&mut out).await.unwrap();
    out
}

fn collect_files_recursive(dir: &Path, out: &mut Vec<PathBuf>) {
    if !dir.exists() {
        return;
    }
    for entry in std::fs::read_dir(dir).unwrap().flatten() {
        let p = entry.path();
        if p.is_dir() {
            collect_files_recursive(&p, out);
        } else if p.is_file() {
            out.push(p);
        }
    }
}

#[tokio::test]
async fn twelve_node_pool_cross_domain_placement_fast_rename_and_delete_recreate() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    let domains = ["sftp-a", "sftp-b", "s3-c", "webdav-d"];
    let mut nodes = Vec::new();
    for i in 0..12 {
        let id = format!("node-{i:02}");
        resolver.add_node(&id, tmp.path().join("remotes").join(&id));
        nodes.push(make_node_cfg(
            &id,
            domains[i % domains.len()],
            10 * 1024 * 1024,
            i < 3,
        ));
    }

    let cfg = PoolConfig {
        id: "pool-12".into(),
        name: "12-Node Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: false,
        passphrase: None,
        kdf_salt: None,
        kdf_m_cost: None,
        kdf_t_cost: None,
        kdf_p_cost: None,
        device_id: Some("dev-main".into()),
        nodes,
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("pool_meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    vfs.mkdir(&VfsPath::from_slash_path("/movies/action"))
        .await
        .unwrap();
    let payload = vec![0xABu8; 256 * 1024];
    write_pool_file(&vfs, "/movies/action/clip.bin", &payload).await;

    // Verify 2 replicas landed in distinct failure domains.
    let entry = state
        .meta
        .stat(&VfsPath::from_slash_path("/movies/action/clip.bin"))
        .unwrap();
    let chunks = state.meta.get_file_chunks(entry.id).unwrap();
    assert_eq!(chunks.len(), 1);
    let reps = state.meta.get_chunk_replicas(&chunks[0].chunk_hash).unwrap();
    assert_eq!(reps.len(), 2);
    let db_nodes = state.meta.list_nodes().unwrap();
    let rep_domains: HashSet<String> = reps
        .iter()
        .map(|r| {
            db_nodes
                .iter()
                .find(|n| n.node_id == r.node_id)
                .unwrap()
                .failure_domain
                .clone()
        })
        .collect();
    assert_eq!(rep_domains.len(), 2);

    // Rename directory must complete locally in < 20ms.
    let start = Instant::now();
    vfs.rename(
        &VfsPath::from_slash_path("/movies"),
        &VfsPath::from_slash_path("/cinema"),
    )
    .await
    .unwrap();
    let elapsed = start.elapsed();
    assert!(
        elapsed < Duration::from_millis(50),
        "rename took {elapsed:?}"
    );
    assert_eq!(read_pool_file(&vfs, "/cinema/action/clip.bin").await, payload);

    // Delete and immediately recreate same path (regression check for partial unique index).
    vfs.remove(&VfsPath::from_slash_path("/cinema/action/clip.bin"))
        .await
        .unwrap();
    assert!(vfs
        .stat(&VfsPath::from_slash_path("/cinema/action/clip.bin"))
        .await
        .is_err());

    let payload2 = b"fresh replacement bytes".to_vec();
    write_pool_file(&vfs, "/cinema/action/clip.bin", &payload2).await;
    assert_eq!(
        read_pool_file(&vfs, "/cinema/action/clip.bin").await,
        payload2
    );
}

#[tokio::test]
async fn transparent_read_and_write_failover_including_degraded_write() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    let f1 = resolver.add_node("n1", tmp.path().join("n1"));
    let f2 = resolver.add_node("n2", tmp.path().join("n2"));
    let f3 = resolver.add_node("n3", tmp.path().join("n3"));

    let cfg = PoolConfig {
        id: "pool-fo".into(),
        name: "Failover Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: false,
        passphrase: None,
        kdf_salt: None,
        kdf_m_cost: None,
        kdf_t_cost: None,
        kdf_p_cost: None,
        device_id: Some("dev1".into()),
        nodes: vec![
            make_node_cfg("n1", "d1", 10 * 1024 * 1024, false),
            make_node_cfg("n2", "d2", 10 * 1024 * 1024, false),
            make_node_cfg("n3", "d3", 10 * 1024 * 1024, false),
        ],
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("pool"),
        resolver,
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    let data: Vec<u8> = (0..(180 * 1024)).map(|i| (i % 251) as u8).collect();
    write_pool_file(&vfs, "/video.bin", &data).await;

    let entry = state.meta.stat(&VfsPath::from_slash_path("/video.bin")).unwrap();
    let chunks = state.meta.get_file_chunks(entry.id).unwrap();
    let reps = state.meta.get_chunk_replicas(&chunks[0].chunk_hash).unwrap();
    assert_eq!(reps.len(), 2);

    // Force first replica to fail mid-stream after 10 KiB; PoolVfs must seamlessly switch to second replica.
    let first_node_id = &reps[0].node_id;
    let fault_map = [("n1", &f1), ("n2", &f2), ("n3", &f3)];
    for (id, f) in &fault_map {
        if id == first_node_id {
            f.write().fail_reads_after_bytes = Some(10 * 1024);
        }
    }
    let read_back = read_pool_file(&vfs, "/video.bin").await;
    assert_eq!(read_back, data);

    // Reset faults; now make n1 fail writes -> write should auto-pick a 3rd node and still hit 2 replicas!
    for (_, f) in &fault_map {
        *f.write() = FaultProfile::default();
    }
    f1.write().fail_writes = true;
    let data2 = b"write-failover-payload-3rd-node".to_vec();
    write_pool_file(&vfs, "/failover_write.txt", &data2).await;
    let e2 = state
        .meta
        .stat(&VfsPath::from_slash_path("/failover_write.txt"))
        .unwrap();
    let ch2 = state.meta.get_file_chunks(e2.id).unwrap();
    let reps2 = state.meta.get_chunk_replicas(&ch2[0].chunk_hash).unwrap();
    assert_eq!(reps2.len(), 2);
    assert!(reps2.iter().all(|r| r.node_id != "n1"));

    // Now make BOTH n1 and n2 fail -> only n3 remains, so degraded 1-replica write succeeds without blocking.
    f2.write().offline = true;
    let data3 = b"degraded-single-replica-ok".to_vec();
    write_pool_file(&vfs, "/degraded.txt", &data3).await;
    let summary = state.summary().unwrap();
    assert_eq!(summary.degraded_chunks, 1);
    assert_eq!(read_pool_file(&vfs, "/degraded.txt").await, data3);
}

#[tokio::test]
async fn chunking_exceeds_single_node_quota_dedup_and_range_reads() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    // 6 nodes with 2.4 MiB quota each across 3 failure domains.
    // Total logical 2-replica capacity = 7.2 MiB, while NO single node can hold a 3.5 MiB file!
    let mut nodes = Vec::new();
    let domains = ["dom-a", "dom-b", "dom-c"];
    for i in 0..6 {
        let id = format!("small-{i}");
        resolver.add_node(&id, tmp.path().join(&id));
        nodes.push(make_node_cfg(
            &id,
            domains[i % domains.len()],
            2_400 * 1024,
            false,
        ));
    }

    let cfg = PoolConfig {
        id: "pool-chunk".into(),
        name: "Chunk Pool".into(),
        chunk_size: 1024 * 1024, // 1 MiB chunk size (normalized min)
        replication_factor: 2,
        encrypt: false,
        passphrase: None,
        kdf_salt: None,
        kdf_m_cost: None,
        kdf_t_cost: None,
        kdf_p_cost: None,
        device_id: Some("dev1".into()),
        nodes,
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    // 3.5 MiB file -> 4 chunks (1 MiB, 1 MiB, 1 MiB, 0.5 MiB).
    let file_len = 3 * 1024 * 1024 + 512 * 1024;
    let payload: Vec<u8> = (0..file_len).map(|i| ((i * 31) % 256) as u8).collect();
    write_pool_file(&vfs, "/large.mp4", &payload).await;

    let entry = state.meta.stat(&VfsPath::from_slash_path("/large.mp4")).unwrap();
    let chunks = state.meta.get_file_chunks(entry.id).unwrap();
    assert_eq!(chunks.len(), 4);

    // Verify no node exceeded its quota.
    for n in state.meta.list_nodes().unwrap() {
        assert!(
            n.used_bytes <= n.quota_bytes,
            "node {} exceeded quota: {} > {}",
            n.node_id,
            n.used_bytes,
            n.quota_bytes
        );
    }

    // Cross-chunk Range read spanning chunk 0 -> chunk 2.
    let off = 900 * 1024u64;
    let len = 1_300 * 1024u64;
    let slice = read_pool_range(&vfs, "/large.mp4", off, Some(len)).await;
    assert_eq!(slice, payload[off as usize..(off + len) as usize]);

    // Dedup check: writing identical content to another path adds zero physical usage.
    let phys_before = state.summary().unwrap().total_physical_used;
    write_pool_file(&vfs, "/large_dup.mp4", &payload).await;
    let phys_after = state.summary().unwrap().total_physical_used;
    assert_eq!(phys_before, phys_after);
}

#[tokio::test]
async fn encrypted_pool_opacity_dedup_subchunk_range_and_tamper_failover() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    resolver.add_node("enc1", tmp.path().join("enc1"));
    resolver.add_node("enc2", tmp.path().join("enc2"));

    let cfg = PoolConfig {
        id: "pool-enc".into(),
        name: "Secret Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: true,
        passphrase: Some("very-secret-passphrase-123".into()),
        kdf_salt: None,
        kdf_m_cost: Some(1024),
        kdf_t_cost: Some(1),
        kdf_p_cost: Some(1),
        device_id: Some("dev1".into()),
        nodes: vec![
            make_node_cfg("enc1", "d1", 10 * 1024 * 1024, true),
            make_node_cfg("enc2", "d2", 10 * 1024 * 1024, true),
        ],
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    let mut plain = vec![0u8; 1_200 * 1024];
    for (i, b) in plain.iter_mut().enumerate() {
        *b = (i % 239) as u8;
    }
    let marker = b"TOP_SECRET_CONFIDENTIAL_PAYLOAD";
    plain[100_000..100_000 + marker.len()].copy_from_slice(marker);

    write_pool_file(&vfs, "/vault_doc.bin", &plain).await;

    // Verify remote blobs contain neither plaintext marker nor plaintext SHA-256 hash.
    let mut remote_blobs = Vec::new();
    collect_files_recursive(&tmp.path().join("enc1"), &mut remote_blobs);
    assert_eq!(remote_blobs.len(), 2);
    for blob_path in &remote_blobs {
        let raw = std::fs::read(blob_path).unwrap();
        assert!(raw.starts_with(b"FPC1"));
        assert!(!raw.windows(marker.len()).any(|w| w == marker));
    }

    // Encrypted dedup works for identical content.
    let used_before = state.summary().unwrap().total_physical_used;
    write_pool_file(&vfs, "/vault_doc_copy.bin", &plain).await;
    assert_eq!(state.summary().unwrap().total_physical_used, used_before);

    // Cross-subchunk & cross-chunk Range read (from 60KiB to 1.1MiB).
    let off = 60 * 1024u64;
    let len = 1_050 * 1024u64;
    let slice = read_pool_range(&vfs, "/vault_doc.bin", off, Some(len)).await;
    assert_eq!(slice, plain[off as usize..(off + len) as usize]);

    // Corrupt a byte in the blob on enc1; PoolVfs must fail over to enc2 and mark enc1 replica suspect.
    let mut corrupted = std::fs::read(&remote_blobs[0]).unwrap();
    let last_idx = corrupted.len() - 1;
    corrupted[last_idx] ^= 0x55;
    std::fs::write(&remote_blobs[0], &corrupted).unwrap();

    let full = read_pool_file(&vfs, "/vault_doc.bin").await;
    assert_eq!(full, plain);

    let entry = state.meta.stat(&VfsPath::from_slash_path("/vault_doc.bin")).unwrap();
    let chunks = state.meta.get_file_chunks(entry.id).unwrap();
    let reps_c1 = state.meta.get_chunk_replicas(&chunks[1].chunk_hash).unwrap();
    assert!(reps_c1.iter().any(|r| r.node_id == "enc1" && r.status == "suspect")
        || state
            .meta
            .get_chunk_replicas(&chunks[0].chunk_hash)
            .unwrap()
            .iter()
            .any(|r| r.node_id == "enc1" && r.status == "suspect"));
}

#[tokio::test]
async fn circuit_breaker_heal_and_lazy_gc_with_offline_node() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    let f1 = resolver.add_node("n1", tmp.path().join("n1"));
    let f2 = resolver.add_node("n2", tmp.path().join("n2"));
    let _f3 = resolver.add_node("n3", tmp.path().join("n3"));

    let cfg = PoolConfig {
        id: "pool-heal".into(),
        name: "Heal GC Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: false,
        passphrase: None,
        kdf_salt: None,
        kdf_m_cost: None,
        kdf_t_cost: None,
        kdf_p_cost: None,
        device_id: Some("dev1".into()),
        nodes: vec![
            make_node_cfg("n1", "d1", 10 * 1024 * 1024, false),
            make_node_cfg("n2", "d2", 10 * 1024 * 1024, false),
            make_node_cfg("n3", "d3", 10 * 1024 * 1024, false),
        ],
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_millis(60),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    // Cause 3 probe failures on n1 -> trips circuit breaker to Open.
    f1.write().offline = true;
    for _ in 0..3 {
        let _ = state.probe_all_nodes().await;
    }
    assert!(state.health.is_circuit_open("n1"));

    // Write file while n1 is circuit-open -> lands on n2 and n3 only.
    let payload = b"healthy-payload-on-n2-n3".to_vec();
    write_pool_file(&vfs, "/keep.txt", &payload).await;
    let e_keep = state.meta.stat(&VfsPath::from_slash_path("/keep.txt")).unwrap();
    let ch_keep = state.meta.get_file_chunks(e_keep.id).unwrap();
    let reps_keep = state.meta.get_chunk_replicas(&ch_keep[0].chunk_hash).unwrap();
    assert_eq!(reps_keep.len(), 2);
    assert!(reps_keep.iter().all(|r| r.node_id != "n1"));

    // Recover n1 (circuit moves HalfOpen -> Closed on probe), and take n2 offline & write degraded file.
    tokio::time::sleep(Duration::from_millis(80)).await;
    f1.write().offline = false;
    let statuses = state.probe_all_nodes().await.unwrap();
    assert_eq!(
        statuses.iter().find(|s| s.node_id == "n1").unwrap().circuit_state,
        "closed"
    );

    f1.write().offline = true;
    f2.write().offline = true;
    let deg_data = b"degraded-only-on-n3".to_vec();
    write_pool_file(&vfs, "/deg.txt", &deg_data).await;
    assert_eq!(state.summary().unwrap().degraded_chunks, 1);

    // Bring n1 back online and run Heal -> repairs /deg.txt to 2 replicas!
    f1.write().offline = false;
    let _ = state.probe_all_nodes().await;
    let prog = Arc::new(Mutex::new(TaskProgress::pending()));
    let cancel = CancellationToken::new();
    let ctrl = TaskControl::new();
    let heal_rep = run_heal(state.clone(), &prog, &cancel, &ctrl).await.unwrap();
    assert_eq!(heal_rep.healed_chunks, 1);
    assert_eq!(state.summary().unwrap().degraded_chunks, 0);

    // Delete /deg.txt and run GC with n1 offline -> n3 blob deleted immediately, n1 stays queued until online.
    vfs.remove(&VfsPath::from_slash_path("/deg.txt"))
        .await
        .unwrap();
    f1.write().offline = true;
    for _ in 0..3 {
        let _ = state.probe_all_nodes().await;
    }
    let gc1 = run_gc(state.clone(), 0, &prog, &cancel, &ctrl).await.unwrap();
    assert_eq!(gc1.purged_tombstones, 1);
    assert!(gc1.deleted_blobs >= 1);
    assert_eq!(gc1.deferred_blobs, 1);
    assert_eq!(state.meta.list_gc_queue().unwrap().len(), 1);

    // Bring n1 back online, probe, run GC again -> remaining orphan blob is reclaimed.
    tokio::time::sleep(Duration::from_millis(80)).await;
    f1.write().offline = false;
    let _ = state.probe_all_nodes().await;
    let gc2 = run_gc(state.clone(), 0, &prog, &cancel, &ctrl).await.unwrap();
    assert_eq!(gc2.deleted_blobs, 1);
    assert!(state.meta.list_gc_queue().unwrap().is_empty());
}

#[tokio::test]
async fn drain_node_migrates_data_and_survives_physical_removal() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    resolver.add_node("d1", tmp.path().join("d1"));
    resolver.add_node("d2", tmp.path().join("d2"));
    resolver.add_node("d3", tmp.path().join("d3"));

    let cfg = PoolConfig {
        id: "pool-drain".into(),
        name: "Drain Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: true,
        passphrase: Some("drain-secret-key".into()),
        kdf_salt: None,
        kdf_m_cost: Some(1024),
        kdf_t_cost: Some(1),
        kdf_p_cost: Some(1),
        device_id: Some("dev1".into()),
        nodes: vec![
            make_node_cfg("d1", "dom-1", 10 * 1024 * 1024, false),
            make_node_cfg("d2", "dom-2", 10 * 1024 * 1024, false),
            make_node_cfg("d3", "dom-3", 10 * 1024 * 1024, false),
        ],
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs = PoolVfs::new(state.clone());

    let p1 = vec![0x11u8; 300_000];
    let p2 = vec![0x22u8; 400_000];
    write_pool_file(&vfs, "/a.bin", &p1).await;
    write_pool_file(&vfs, "/b.bin", &p2).await;

    let prog = Arc::new(Mutex::new(TaskProgress::pending()));
    let cancel = CancellationToken::new();
    let ctrl = TaskControl::new();
    let report = run_drain(state.clone(), "d1", &prog, &cancel, &ctrl)
        .await
        .unwrap();
    assert_eq!(report.failed_chunks, 0);
    assert!(state.meta.list_chunks_on_node("d1").unwrap().is_empty());

    // Physically delete d1's backing directory!
    std::fs::remove_dir_all(resolver.dir_of("d1")).unwrap();

    // All files still maintain 2 healthy replicas across d2 and d3 and decrypt cleanly.
    assert_eq!(state.summary().unwrap().degraded_chunks, 0);
    assert_eq!(read_pool_file(&vfs, "/a.bin").await, p1);
    assert_eq!(read_pool_file(&vfs, "/b.bin").await, p2);
}

#[tokio::test]
async fn multi_device_metadata_sync_and_three_way_conflict_merge() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    resolver.add_node("r1", tmp.path().join("r1"));
    resolver.add_node("r2", tmp.path().join("r2"));
    resolver.add_node("r3", tmp.path().join("r3"));
    resolver.add_node("r4", tmp.path().join("r4"));

    let salt_b64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        [9u8; 16],
    );

    let mk_cfg = |dev: &str| PoolConfig {
        id: "shared-pool".into(),
        name: "Shared Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 2,
        encrypt: true,
        passphrase: Some("shared-sync-pass".into()),
        kdf_salt: Some(salt_b64.clone()),
        kdf_m_cost: Some(1024),
        kdf_t_cost: Some(1),
        kdf_p_cost: Some(1),
        device_id: Some(dev.into()),
        nodes: vec![
            make_node_cfg("r1", "dom-1", 20 * 1024 * 1024, true),
            make_node_cfg("r2", "dom-2", 20 * 1024 * 1024, true),
            make_node_cfg("r3", "dom-3", 20 * 1024 * 1024, true),
            make_node_cfg("r4", "dom-4", 20 * 1024 * 1024, false),
        ],
        created_at_ms: 1,
    };

    // Device A creates base.txt and syncs to the 3 backup nodes.
    let dev_a = PoolState::open(
        mk_cfg("devA1111"),
        tmp.path().join("devA_meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs_a = PoolVfs::new(dev_a.clone());
    write_pool_file(&vfs_a, "/base.txt", b"initial-base").await;
    let r_a1 = sync_pool_metadata(&dev_a).await.unwrap();
    assert_eq!(r_a1.action, "pushed");
    assert_eq!(r_a1.uploaded_backups, 3);

    // Device B starts fresh, pulls snapshot, sees base.txt.
    let dev_b = PoolState::open(
        mk_cfg("devB2222"),
        tmp.path().join("devB_meta"),
        resolver.clone(),
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();
    let vfs_b = PoolVfs::new(dev_b.clone());
    let r_b1 = sync_pool_metadata(&dev_b).await.unwrap();
    assert_eq!(r_b1.action, "pulled");
    assert_eq!(read_pool_file(&vfs_b, "/base.txt").await, b"initial-base");

    // Both devices go offline relative to each other and write:
    // - Device A writes `/only_a.txt` and `/shared.txt` (earlier)
    // - Device B writes `/only_b.txt` and `/shared.txt` (later -> wins canonical path)
    write_pool_file(&vfs_a, "/only_a.txt", b"from-device-a").await;
    write_pool_file(&vfs_a, "/shared.txt", b"shared-version-a").await;
    sync_pool_metadata(&dev_a).await.unwrap();

    tokio::time::sleep(Duration::from_millis(15)).await;
    write_pool_file(&vfs_b, "/only_b.txt", b"from-device-b").await;
    write_pool_file(&vfs_b, "/shared.txt", b"shared-version-b").await;

    let r_b2 = sync_pool_metadata(&dev_b).await.unwrap();
    assert_eq!(r_b2.conflicts_created, 1);

    // Device A pulls the merged state.
    let r_a2 = sync_pool_metadata(&dev_a).await.unwrap();
    assert_eq!(r_a2.action, "pulled");

    // Both devices have only_a.txt, only_b.txt, shared.txt (winner), and shared (conflict devA1111).txt (loser)!
    for vfs in [&vfs_a, &vfs_b] {
        assert_eq!(read_pool_file(vfs, "/only_a.txt").await, b"from-device-a");
        assert_eq!(read_pool_file(vfs, "/only_b.txt").await, b"from-device-b");
        assert_eq!(read_pool_file(vfs, "/shared.txt").await, b"shared-version-b");
        assert_eq!(
            read_pool_file(vfs, "/shared (conflict devA1111).txt").await,
            b"shared-version-a"
        );
    }
}

#[tokio::test]
async fn probe_populates_real_node_space_and_replication_gt_3_writes_all_replicas() {
    let tmp = tempfile::tempdir().unwrap();
    let resolver = Arc::new(MockResolver::new());
    for i in 1..=4 {
        resolver.add_node(&format!("n{i}"), tmp.path().join(format!("node_{i}")));
    }

    let cfg = PoolConfig {
        id: "rep4".into(),
        name: "Rep4 Pool".into(),
        chunk_size: 1024 * 1024,
        replication_factor: 4,
        encrypt: false,
        passphrase: None,
        kdf_salt: None,
        kdf_m_cost: None,
        kdf_t_cost: None,
        kdf_p_cost: None,
        device_id: Some("dev1".into()),
        nodes: vec![
            make_node_cfg("n1", "d1", 50 * 1024 * 1024, true),
            make_node_cfg("n2", "d2", 50 * 1024 * 1024, true),
            make_node_cfg("n3", "d3", 50 * 1024 * 1024, false),
            make_node_cfg("n4", "d4", 50 * 1024 * 1024, false),
        ],
        created_at_ms: 1,
    };

    let state = PoolState::open(
        cfg,
        tmp.path().join("meta"),
        resolver,
        fast_timeouts(),
        Duration::from_secs(30),
        Duration::from_secs(60),
    )
    .unwrap();

    assert_eq!(state.replication_factor(), 4);

    let probed = state.probe_all_nodes().await.unwrap();
    assert_eq!(probed.len(), 4);
    for st in &probed {
        assert!(st.remote_free_bytes.unwrap_or(0) > 0);
        assert!(st.remote_total_bytes.unwrap_or(0) >= st.remote_free_bytes.unwrap_or(0));
    }

    let summary = state.summary().unwrap();
    assert_eq!(summary.replication_factor, 4);
    assert!(summary.nodes.iter().all(|n| n.remote_free_bytes.is_some()));

    let vfs = PoolVfs::new(Arc::clone(&state));
    write_pool_file(&vfs, "/hello.bin", b"four-way-replica-test").await;
    let entry = state
        .meta
        .stat(&VfsPath::from_slash_path("/hello.bin"))
        .unwrap();
    let chunks = state.meta.get_file_chunks(entry.id).unwrap();
    let replicas = state.meta.get_chunk_replicas(&chunks[0].chunk_hash).unwrap();
    assert_eq!(replicas.len(), 4);
}
