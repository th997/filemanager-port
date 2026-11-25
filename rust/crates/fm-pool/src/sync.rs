//! Metadata snapshot synchronization, multi-node redundant backup upload,
//! startup pull, and 3-way conflict-preserving merge.

use crate::crypto::{
    compress_and_encrypt_snapshot, decrypt_and_decompress_snapshot, sha256_hex,
};
use crate::error::{PoolError, PoolResult};
use crate::meta::now_millis;
use crate::scheduler::NodePlacementInfo;
use crate::PoolState;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use fm_core::VfsPath;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::Notify;
use tokio::time::Duration;

const META_LATEST_RELPATH: &str = "meta/latest.json";
const MAX_SNAPSHOTS_KEPT: usize = 5;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LatestMetaManifest {
    pub pool_id: String,
    pub version: u64,
    pub device_id: String,
    pub snapshot_relpath: String,
    pub snapshot_sha256: String,
    pub encrypted: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kdf_salt_b64: Option<String>,
    pub updated_at_ms: i64,
    #[serde(default)]
    pub recent_snapshots: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolSyncReport {
    pub action: String,
    pub local_version_before: u64,
    pub remote_version: u64,
    pub final_version: u64,
    pub uploaded_backups: u32,
    pub conflicts_created: u32,
}

/// Perform full bidirectional metadata synchronization against `is_meta_backup`
/// nodes (pull/merge if remote has newer version, then push if local is dirty
/// or ahead).
pub async fn sync_pool_metadata(state: &PoolState) -> PoolResult<PoolSyncReport> {
    let _sync_guard = state.sync_lock.lock().await;

    let nodes = state.meta.list_nodes()?;
    let backup_nodes: Vec<NodePlacementInfo> = nodes
        .into_iter()
        .filter(|n| n.is_meta_backup && n.role != crate::scheduler::NodeRole::Offline)
        .collect();

    if backup_nodes.is_empty() {
        let local_ver = state.meta.get_meta_u64("meta_version")?;
        return Ok(PoolSyncReport {
            action: "no_backup_nodes".to_string(),
            local_version_before: local_ver,
            remote_version: 0,
            final_version: local_ver,
            uploaded_backups: 0,
            conflicts_created: 0,
        });
    }

    let local_version_before = state.meta.get_meta_u64("meta_version")?;
    let local_dirty = state.meta.is_dirty()?;
    let pool_id = state.pool_id().to_string();

    // 1. Concurrently fetch `meta/latest.json` from all backup nodes.
    let fetches = backup_nodes.iter().map(|node| async {
        let res = state.io.read_all(node, META_LATEST_RELPATH).await;
        (node.clone(), res)
    });
    let manifest_results = futures_util::future::join_all(fetches).await;

    let mut manifests: Vec<(NodePlacementInfo, LatestMetaManifest)> = Vec::new();
    for (node, res) in manifest_results {
        if let Ok(bytes) = res {
            if let Ok(manifest) = serde_json::from_slice::<LatestMetaManifest>(&bytes) {
                if manifest.pool_id == pool_id {
                    manifests.push((node, manifest));
                }
            }
        }
    }

    manifests.sort_by_key(|a| std::cmp::Reverse(a.1.version));
    let mut remote_version = 0u64;
    let mut conflicts_created = 0u32;
    let mut action = "up_to_date".to_string();
    let mut pulled_any = false;
    let mut known_snapshots: HashSet<String> = HashSet::new();
    for (_, m) in &manifests {
        for s in &m.recent_snapshots {
            known_snapshots.insert(s.clone());
        }
        known_snapshots.insert(m.snapshot_relpath.clone());
    }

    // 2. If remote has a newer version (or same version while local is dirty and from another device),
    // download and verify the highest valid snapshot.
    if let Some((_, best)) = manifests.first() {
        remote_version = best.version;
    }

    let should_pull = manifests.first().is_some_and(|(_, best)| {
        best.version > local_version_before
            || (local_dirty
                && best.version == local_version_before
                && best.device_id != state.device_id())
    });

    if should_pull {
        let mut downloaded_raw: Option<(LatestMetaManifest, Vec<u8>)> = None;
        for (_, manifest) in &manifests {
            // Try reading this snapshot from any backup node that might hold it.
            for candidate_node in &backup_nodes {
                let Ok(enc_bytes) = state.io.read_all(candidate_node, &manifest.snapshot_relpath).await else {
                    continue;
                };
                if sha256_hex(&enc_bytes) != manifest.snapshot_sha256 {
                    continue;
                }
                let crypto_guard = state.crypto();
                let dec_res = decrypt_and_decompress_snapshot(
                    &enc_bytes,
                    if manifest.encrypted {
                        crypto_guard.as_ref()
                    } else {
                        None
                    },
                    &pool_id,
                );
                if let Ok(raw_db) = dec_res {
                    downloaded_raw = Some((manifest.clone(), raw_db));
                    break;
                }
            }
            if downloaded_raw.is_some() {
                break;
            }
        }

        if let Some((manifest, raw_db)) = downloaded_raw {
            let tmp_db = state
                .pool_dir()
                .join(format!("pull_{}.db", uuid::Uuid::new_v4().simple()));
            tokio::fs::write(&tmp_db, &raw_db).await?;
            let pull_res = if !local_dirty {
                let meta = state.meta.clone();
                let p = tmp_db.clone();
                let ver = manifest.version;
                tokio::task::spawn_blocking(move || meta.replace_from_snapshot(&p, ver))
                    .await
                    .map_err(|e| PoolError::Sync(e.to_string()))?
                    .map(|()| 0u32)
            } else {
                let meta = state.meta.clone();
                let p = tmp_db.clone();
                let ver = manifest.version;
                let dev = state.device_id().to_string();
                tokio::task::spawn_blocking(move || meta.merge_from_snapshot(&p, ver, &dev))
                    .await
                    .map_err(|e| PoolError::Sync(e.to_string()))?
            };
            let _ = tokio::fs::remove_file(&tmp_db).await;
            conflicts_created = pull_res?;
            pulled_any = true;
            action = if conflicts_created > 0 {
                "merged_with_conflicts".to_string()
            } else if local_dirty {
                "merged".to_string()
            } else {
                "pulled".to_string()
            };
        }
    }

    // 3. Push local snapshot if local is dirty or newer than remote.
    let current_ver = state.meta.get_meta_u64("meta_version")?;
    let current_dirty = state.meta.is_dirty()?;
    let mut uploaded_backups = 0u32;

    if current_dirty || current_ver > remote_version {
        let upload_ver = current_ver.max(remote_version + 1);
        let snap_tmp = state
            .pool_dir()
            .join(format!("snap_{}.db", uuid::Uuid::new_v4().simple()));
        {
            let meta = state.meta.clone();
            let p = snap_tmp.clone();
            tokio::task::spawn_blocking(move || meta.export_vacuum_snapshot(&p))
                .await
                .map_err(|e| PoolError::Sync(e.to_string()))??;
        }
        let raw_db = tokio::fs::read(&snap_tmp).await?;
        let _ = tokio::fs::remove_file(&snap_tmp).await;

        let crypto_guard = state.crypto();
        let is_encrypted = crypto_guard.is_some();
        let encoded_snapshot =
            compress_and_encrypt_snapshot(&raw_db, crypto_guard.as_ref(), &pool_id)?;
        let snapshot_sha256 = sha256_hex(&encoded_snapshot);

        let short_dev: String = state
            .device_id()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
            .take(8)
            .collect();
        let ext = if is_encrypted { "db.gz.enc" } else { "db.gz" };
        let snapshot_relpath = format!("meta/v{upload_ver:06}_{short_dev}.{ext}");

        let mut history: Vec<String> = known_snapshots.into_iter().collect();
        history.sort();
        if !history.contains(&snapshot_relpath) {
            history.push(snapshot_relpath.clone());
        }
        let obsolete: Vec<String> = if history.len() > MAX_SNAPSHOTS_KEPT {
            let split = history.len() - MAX_SNAPSHOTS_KEPT;
            history.drain(..split).collect()
        } else {
            Vec::new()
        };

        let kdf_salt_b64 = state
            .config_snapshot()
            .kdf_salt
            .as_deref()
            .map(|s| s.to_string())
            .or_else(|| {
                state
                    .config_snapshot()
                    .kdf_salt_bytes()
                    .map(|b| STANDARD.encode(b))
            });

        let manifest = LatestMetaManifest {
            pool_id: pool_id.clone(),
            version: upload_ver,
            device_id: state.device_id().to_string(),
            snapshot_relpath: snapshot_relpath.clone(),
            snapshot_sha256,
            encrypted: is_encrypted,
            kdf_salt_b64,
            updated_at_ms: now_millis(),
            recent_snapshots: history,
        };
        let manifest_bytes = serde_json::to_vec_pretty(&manifest)?;

        let uploads = backup_nodes.iter().map(|node| {
            let snap_rel = snapshot_relpath.clone();
            let snap_data = &encoded_snapshot;
            let man_data = &manifest_bytes;
            let old_snaps = &obsolete;
            async move {
                state.io.write_bytes(node, &snap_rel, snap_data).await?;
                state.io.write_bytes(node, META_LATEST_RELPATH, man_data).await?;
                for old in old_snaps {
                    let _ = state.io.remove_blob(node, old).await;
                }
                Ok::<(), PoolError>(())
            }
        });
        let results = futures_util::future::join_all(uploads).await;
        let mut errors = Vec::new();
        for res in results {
            match res {
                Ok(()) => uploaded_backups += 1,
                Err(e) => errors.push(e.to_string()),
            }
        }

        let required = backup_nodes.len().min(2) as u32;
        if uploaded_backups < required {
            return Err(PoolError::Sync(format!(
                "metadata backup quorum not reached ({uploaded_backups}/{required} required): {}",
                errors.join("; ")
            )));
        }

        state.meta.set_meta_sync_state(upload_ver, false)?;
        action = if pulled_any {
            if conflicts_created > 0 {
                "merged_and_pushed_conflicts".to_string()
            } else {
                "merged_and_pushed".to_string()
            }
        } else {
            "pushed".to_string()
        };
    }

    let final_version = state.meta.get_meta_u64("meta_version")?;
    Ok(PoolSyncReport {
        action,
        local_version_before,
        remote_version,
        final_version,
        uploaded_backups,
        conflicts_created,
    })
}

/// Background debounced metadata sync worker spawned per active pool.
pub fn spawn_debounced_sync_worker(
    state: Arc<PoolState>,
    notify: Arc<Notify>,
    debounce: Duration,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        loop {
            notify.notified().await;
            // Coalesce rapid successive writes within `debounce`.
            loop {
                tokio::select! {
                    _ = notify.notified() => continue,
                    _ = tokio::time::sleep(debounce) => break,
                }
            }
            if state.is_closed() {
                break;
            }
            let _ = sync_pool_metadata(&state).await;
        }
    })
}

pub fn make_meta_relpath_prefix() -> VfsPath {
    VfsPath::from_slash_path("meta")
}
