//! Scrub & Heal (repairing under-replicated chunks across distinct failure
//! domains) and Drain Node (migrating all chunks off a retiring node).

use crate::crypto::{chunk_content_id, verify_and_decrypt_fpc1_full};
use crate::error::{PoolError, PoolResult};
use crate::meta::UnderReplicatedChunk;
use crate::scheduler::{rank_read_replicas, select_write_nodes, NodePlacementInfo, NodeRole};
use crate::storage::blob_relpath;
use crate::PoolState;
use fm_core::VfsPath;
use fm_ops::{TaskControl, TaskProgress, TaskState};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HealReport {
    pub scanned_chunks: u64,
    pub healed_chunks: u64,
    pub failed_chunks: u64,
    pub bytes_copied: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DrainReport {
    pub node_id: String,
    pub total_chunks: u64,
    pub migrated_chunks: u64,
    pub failed_chunks: u64,
    pub bytes_copied: u64,
}

fn check_cancelled(cancel: &CancellationToken) -> PoolResult<()> {
    if cancel.is_cancelled() {
        Err(PoolError::Cancelled)
    } else {
        Ok(())
    }
}

async fn read_and_verify_chunk_payload(
    state: &PoolState,
    chunk: &UnderReplicatedChunk,
    all_nodes: &[NodePlacementInfo],
) -> PoolResult<Vec<u8>> {
    let replicas = state.meta.get_chunk_replicas(&chunk.chunk_hash)?;
    let ranked = rank_read_replicas(&replicas, all_nodes, &state.health);
    if ranked.is_empty() {
        return Err(PoolError::AllReplicasFailed {
            chunk_hash: chunk.chunk_hash.clone(),
            details: "no online replicas available".to_string(),
        });
    }

    let crypto_guard = state.crypto();
    let mut errors: Vec<String> = Vec::new();
    for (rep, node) in ranked {
        match state.io.read_all(&node, &rep.remote_relpath).await {
            Ok(bytes) => {
                if chunk.encrypted {
                    let Some(crypto) = crypto_guard.as_ref() else {
                        return Err(PoolError::Crypto(
                            "encrypted pool is locked during heal".to_string(),
                        ));
                    };
                    match verify_and_decrypt_fpc1_full(crypto, &chunk.chunk_hash, &bytes) {
                        Ok(_) => return Ok(bytes),
                        Err(e) => {
                            let _ = state.meta.mark_replica_status(
                                &chunk.chunk_hash,
                                &node.node_id,
                                "suspect",
                            );
                            errors.push(format!("{}: {e}", node.node_id));
                        }
                    }
                } else {
                    match chunk_content_id(None, &bytes) {
                        Ok(actual) if actual == chunk.chunk_hash => return Ok(bytes),
                        Ok(actual) => {
                            let _ = state.meta.mark_replica_status(
                                &chunk.chunk_hash,
                                &node.node_id,
                                "suspect",
                            );
                            errors.push(format!(
                                "{}: hash mismatch ({actual} != {})",
                                node.node_id, chunk.chunk_hash
                            ));
                        }
                        Err(e) => errors.push(format!("{}: {e}", node.node_id)),
                    }
                }
            }
            Err(e) => {
                errors.push(format!("{}: {e}", node.node_id));
            }
        }
    }

    Err(PoolError::AllReplicasFailed {
        chunk_hash: chunk.chunk_hash.clone(),
        details: errors.join("; "),
    })
}

async fn heal_single_chunk(
    state: &PoolState,
    chunk: &UnderReplicatedChunk,
    target_replicas: usize,
    exclude_extra_node_id: Option<&str>,
) -> PoolResult<(u64, bool)> {
    let all_nodes = state.meta.list_nodes()?;
    let existing_replicas = state.meta.get_ok_replicas_for_chunk(&chunk.chunk_hash)?;

    let mut current_ok_nodes: HashSet<String> = HashSet::new();
    let mut existing_domains: HashSet<String> = HashSet::new();
    let mut current_ok_count = 0usize;

    for rep in &existing_replicas {
        if let Some(ex) = exclude_extra_node_id {
            if rep.node_id == ex {
                continue;
            }
        }
        if let Some(node) = all_nodes.iter().find(|n| n.node_id == rep.node_id) {
            if matches!(node.role, NodeRole::Rw | NodeRole::Ro) {
                current_ok_count += 1;
                current_ok_nodes.insert(node.node_id.clone());
                existing_domains.insert(node.failure_domain.clone());
            }
        }
    }

    if current_ok_count >= target_replicas {
        return Ok((0, false));
    }

    let mut exclude_ids = current_ok_nodes;
    if let Some(ex) = exclude_extra_node_id {
        exclude_ids.insert(ex.to_string());
    }

    let needed = target_replicas - current_ok_count;
    let payload = read_and_verify_chunk_payload(state, chunk, &all_nodes).await?;
    let payload_len = payload.len() as u64;
    let relpath = blob_relpath(&chunk.chunk_hash);

    let mut copied = 0u64;
    let mut replicated_any = false;
    let mut remaining_needed = needed;

    while remaining_needed > 0 {
        let candidates = select_write_nodes(
            &all_nodes,
            &state.health,
            payload_len,
            remaining_needed,
            &exclude_ids,
            &existing_domains,
        );
        if candidates.is_empty() {
            break;
        }
        for target_node in candidates {
            exclude_ids.insert(target_node.node_id.clone());
            match state.io.write_bytes(&target_node, &relpath, &payload).await {
                Ok(()) => {
                    state
                        .meta
                        .add_replica(&chunk.chunk_hash, &target_node.node_id, &relpath)?;
                    existing_domains.insert(target_node.failure_domain.clone());
                    copied = copied.saturating_add(payload_len);
                    replicated_any = true;
                    remaining_needed = remaining_needed.saturating_sub(1);
                }
                Err(_) => continue,
            }
        }
    }

    if remaining_needed > 0 && !replicated_any {
        return Err(PoolError::NoWritableNodes);
    }
    Ok((copied, replicated_any))
}

/// Scan all active chunks with `< target_replicas` healthy `rw` replicas and
/// replicate them from surviving replicas onto new distinct failure-domain nodes.
pub async fn run_heal(
    state: Arc<PoolState>,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: &TaskControl,
) -> PoolResult<HealReport> {
    let target_replicas = state.replication_factor();
    let under = state.meta.list_under_replicated_chunks(target_replicas)?;
    let total_bytes: u64 = under.iter().map(|c| c.stored_size.max(c.plain_size)).sum();

    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.state = TaskState::Running;
        p.total = Some(total_bytes);
        p.completed = 0;
    }

    let mut report = HealReport {
        scanned_chunks: under.len() as u64,
        ..Default::default()
    };

    for chunk in under {
        control
            .wait_if_paused(progress, cancel)
            .await
            .map_err(|_| PoolError::Cancelled)?;
        check_cancelled(cancel)?;

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.current = Some(VfsPath::from_slash_path(&chunk.chunk_hash));
        }

        match heal_single_chunk(&state, &chunk, target_replicas, None).await {
            Ok((bytes, healed)) => {
                if healed {
                    report.healed_chunks += 1;
                    report.bytes_copied += bytes;
                }
            }
            Err(_) => {
                report.failed_chunks += 1;
            }
        }

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed = p
                .completed
                .saturating_add(chunk.stored_size.max(chunk.plain_size));
        }
    }

    if report.healed_chunks > 0 {
        state.schedule_debounced_sync();
    }
    Ok(report)
}

/// Mark `node_id` as `draining`, copy every chunk it holds onto other healthy
/// nodes so `target_replicas` remain intact without `node_id`, remove its
/// remote blobs (or queue to `gc_queue` if temporarily unreachable), and mark
/// the node `offline` once drained.
pub async fn run_drain(
    state: Arc<PoolState>,
    node_id: &str,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: &TaskControl,
) -> PoolResult<DrainReport> {
    let nodes = state.meta.list_nodes()?;
    let target_node = nodes
        .into_iter()
        .find(|n| n.node_id == node_id)
        .ok_or_else(|| PoolError::NotFound(format!("node {node_id}")))?;

    state.meta.set_node_role(node_id, NodeRole::Draining)?;
    let target_replicas = state.replication_factor();
    let chunks = state.meta.list_chunks_on_node(node_id)?;
    let total_bytes: u64 = chunks.iter().map(|c| c.stored_size.max(c.plain_size)).sum();

    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.state = TaskState::Running;
        p.total = Some(total_bytes);
        p.completed = 0;
    }

    let mut report = DrainReport {
        node_id: node_id.to_string(),
        total_chunks: chunks.len() as u64,
        ..Default::default()
    };

    for chunk in chunks {
        control
            .wait_if_paused(progress, cancel)
            .await
            .map_err(|_| PoolError::Cancelled)?;
        check_cancelled(cancel)?;

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.current = Some(VfsPath::from_slash_path(&chunk.chunk_hash));
        }

        let Some(relpath) = state.meta.get_replica_relpath(&chunk.chunk_hash, node_id)? else {
            continue;
        };

        // Ensure at least `target_replicas` (or if pool has fewer total non-drained nodes,
        // at least 1 other node) hold this chunk before dropping it from `node_id`.
        let all_nodes = state.meta.list_nodes()?;
        let other_writable = all_nodes
            .iter()
            .filter(|n| n.node_id != node_id && matches!(n.role, NodeRole::Rw | NodeRole::Ro))
            .count();
        let desired_other = target_replicas.min(other_writable.max(1));

        match heal_single_chunk(&state, &chunk, desired_other, Some(node_id)).await {
            Ok((bytes, _)) => {
                report.bytes_copied += bytes;
                // Double check at least 1 other healthy replica exists before dropping this replica.
                let reps_after = state.meta.get_ok_replicas_for_chunk(&chunk.chunk_hash)?;
                let has_other = reps_after.iter().any(|r| r.node_id != node_id);
                if !has_other {
                    report.failed_chunks += 1;
                    continue;
                }

                let remote_removed = state.io.remove_blob(&target_node, &relpath).await.is_ok();
                state.meta.remove_replica_and_maybe_queue_gc(
                    &chunk.chunk_hash,
                    node_id,
                    &relpath,
                    !remote_removed,
                )?;
                report.migrated_chunks += 1;
            }
            Err(_) => {
                report.failed_chunks += 1;
            }
        }

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed = p
                .completed
                .saturating_add(chunk.stored_size.max(chunk.plain_size));
        }
    }

    if state.meta.list_chunks_on_node(node_id)?.is_empty() {
        state.meta.set_node_role(node_id, NodeRole::Offline)?;
    }

    state.schedule_debounced_sync();
    Ok(report)
}
