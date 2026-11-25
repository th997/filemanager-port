//! Lazy garbage collector: purges expired soft-deleted entries and cleans
//! orphaned remote blobs from `gc_queue` (leaving offline nodes queued for
//! automatic retry later).

use crate::error::{PoolError, PoolResult};
use crate::meta::now_millis;
use crate::scheduler::NodeRole;
use crate::PoolState;
use fm_core::VfsPath;
use fm_ops::{TaskControl, TaskProgress, TaskState};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

pub const DEFAULT_GC_GRACE_PERIOD_MS: i64 = 24 * 60 * 60 * 1000;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct GcReport {
    pub purged_tombstones: u64,
    pub deleted_blobs: u64,
    pub deferred_blobs: u64,
    pub failed_blobs: u64,
}

pub async fn run_gc(
    state: Arc<PoolState>,
    grace_period_ms: i64,
    progress: &Arc<Mutex<TaskProgress>>,
    cancel: &CancellationToken,
    control: &TaskControl,
) -> PoolResult<GcReport> {
    let cutoff = now_millis().saturating_sub(grace_period_ms.max(0));
    let purged_tombstones = state.meta.sweep_expired_soft_deletes(cutoff)?;

    let queue = state.meta.list_gc_queue()?;
    let nodes = state.meta.list_nodes()?;

    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.state = TaskState::Running;
        p.total = Some(queue.len() as u64);
        p.completed = 0;
    }

    let mut report = GcReport {
        purged_tombstones,
        ..Default::default()
    };

    for item in queue {
        control
            .wait_if_paused(progress, cancel)
            .await
            .map_err(|_| PoolError::Cancelled)?;
        if cancel.is_cancelled() {
            return Err(PoolError::Cancelled);
        }

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.current = Some(VfsPath::from_slash_path(&item.remote_relpath));
        }

        let Some(node) = nodes.iter().find(|n| n.node_id == item.node_id) else {
            // Node was permanently removed from pool_nodes; drop stale queue item.
            let _ = state.meta.remove_gc_item(&item.chunk_hash, &item.node_id);
            report.deleted_blobs += 1;
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed += 1;
            continue;
        };

        if node.role == NodeRole::Offline || state.health.is_circuit_open(&node.node_id) {
            report.deferred_blobs += 1;
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed += 1;
            continue;
        }

        match state.io.remove_blob(node, &item.remote_relpath).await {
            Ok(()) => {
                state.meta.remove_gc_item(&item.chunk_hash, &item.node_id)?;
                report.deleted_blobs += 1;
            }
            Err(_) => {
                let _ = state.meta.increment_gc_retry(&item.chunk_hash, &item.node_id);
                report.failed_blobs += 1;
            }
        }

        {
            let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
            p.completed += 1;
        }
    }

    if purged_tombstones > 0 || report.deleted_blobs > 0 {
        state.schedule_debounced_sync();
    }
    Ok(report)
}
