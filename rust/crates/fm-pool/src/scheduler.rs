//! Failure-domain-isolated node placement scheduler and read replica ranker.

use crate::health::{CircuitState, HealthTracker};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NodeRole {
    #[default]
    Rw,
    Ro,
    Draining,
    Offline,
}

impl NodeRole {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Rw => "rw",
            Self::Ro => "ro",
            Self::Draining => "draining",
            Self::Offline => "offline",
        }
    }

    pub fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "ro" | "read_only" | "read-only" => Self::Ro,
            "draining" => Self::Draining,
            "offline" => Self::Offline,
            _ => Self::Rw,
        }
    }

    pub fn is_writable(&self) -> bool {
        matches!(self, Self::Rw)
    }

    pub fn is_readable(&self) -> bool {
        !matches!(self, Self::Offline)
    }
}

#[derive(Debug, Clone)]
pub struct NodePlacementInfo {
    pub node_id: String,
    pub remote_id: String,
    pub base_prefix: String,
    pub failure_domain: String,
    pub quota_bytes: u64,
    pub used_bytes: u64,
    pub remote_free_bytes: Option<u64>,
    pub remote_total_bytes: Option<u64>,
    pub role: NodeRole,
    pub is_meta_backup: bool,
    pub db_health_score: f64,
    pub db_avg_latency_ms: u64,
}

impl NodePlacementInfo {
    pub fn free_bytes(&self) -> u64 {
        let quota_free = self.quota_bytes.saturating_sub(self.used_bytes);
        match self.remote_free_bytes {
            Some(remote_free) => quota_free.min(remote_free),
            None => quota_free,
        }
    }
}

/// Compute placement score for writing a chunk onto `node`:
/// `(free / quota)^1.5 * health_score / (1 + latency_ms / 1000)`
pub fn score_node(
    node: &NodePlacementInfo,
    health: &HealthTracker,
) -> f64 {
    let snap = health.snapshot(&node.node_id);
    let free = node.free_bytes() as f64;
    let quota = (node.quota_bytes.max(1)) as f64;
    let free_ratio = (free / quota).clamp(0.0, 1.0);
    let latency_factor = 1.0 / (1.0 + (snap.avg_latency_ms as f64) / 1000.0);
    let score = free_ratio.powf(1.5) * snap.health_score.clamp(0.05, 1.0) * latency_factor;
    if score <= 0.0 {
        0.0001
    } else {
        score
    }
}

/// Select up to `count` writable nodes for storing a blob of `stored_size`
/// bytes, prioritizing distinct failure domains.
///
/// Nodes in `exclude_node_ids` are never picked. `prefer_avoid_domains` are
/// avoided when choosing cross-domain targets (e.g., when repairing a degraded
/// chunk that already has a replica in domain `D1`), falling back to them only
/// if no other domain has an eligible candidate.
pub fn select_write_nodes(
    nodes: &[NodePlacementInfo],
    health: &HealthTracker,
    stored_size: u64,
    count: usize,
    exclude_node_ids: &HashSet<String>,
    prefer_avoid_domains: &HashSet<String>,
) -> Vec<NodePlacementInfo> {
    if count == 0 {
        return Vec::new();
    }

    // Require 5% headroom above chunk size so metadata/temp files fit safely.
    let required_free = stored_size.saturating_add((stored_size / 20).max(1));

    let mut candidates: Vec<(NodePlacementInfo, f64)> = nodes
        .iter()
        .filter(|n| {
            n.role.is_writable()
                && !exclude_node_ids.contains(&n.node_id)
                && !health.is_circuit_open(&n.node_id)
                && n.free_bytes() >= required_free
        })
        .map(|n| (n.clone(), score_node(n, health)))
        .collect();

    candidates.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.0.node_id.cmp(&b.0.node_id))
    });

    let mut chosen: Vec<NodePlacementInfo> = Vec::with_capacity(count);
    let mut used_ids: HashSet<String> = HashSet::new();
    let mut used_domains: HashSet<String> = prefer_avoid_domains.clone();

    // Pass 1: select highest-scoring candidates from unused failure domains.
    for (cand, _) in &candidates {
        if chosen.len() >= count {
            break;
        }
        if !used_domains.contains(&cand.failure_domain) && used_ids.insert(cand.node_id.clone()) {
            used_domains.insert(cand.failure_domain.clone());
            chosen.push(cand.clone());
        }
    }

    // Pass 2: if fewer than `count` distinct domains exist, pick remaining
    // candidates (excluding already chosen node_ids).
    if chosen.len() < count {
        for (cand, _) in &candidates {
            if chosen.len() >= count {
                break;
            }
            if used_ids.insert(cand.node_id.clone()) {
                chosen.push(cand.clone());
            }
        }
    }

    chosen
}

#[derive(Debug, Clone)]
pub struct ReplicaLocation {
    pub chunk_hash: String,
    pub node_id: String,
    pub remote_relpath: String,
    pub status: String,
    pub verified_at: i64,
}

/// Rank readable replicas by:
/// 1. `status == "ok"` before `"suspect"` (never `"missing"`)
/// 2. Circuit not open (Closed / HalfOpen before Open)
/// 3. Highest `health_score`
/// 4. Lowest `avg_latency_ms`
pub fn rank_read_replicas(
    replicas: &[ReplicaLocation],
    nodes: &[NodePlacementInfo],
    health: &HealthTracker,
) -> Vec<(ReplicaLocation, NodePlacementInfo)> {
    let mut ranked = Vec::new();
    for rep in replicas {
        if rep.status == "missing" {
            continue;
        }
        let Some(node) = nodes.iter().find(|n| n.node_id == rep.node_id) else {
            continue;
        };
        if !node.role.is_readable() {
            continue;
        }
        let snap = health.snapshot(&node.node_id);
        let is_open = matches!(snap.circuit_state, CircuitState::Open { .. });
        let status_rank = if rep.status == "ok" { 0u8 } else { 1u8 };
        ranked.push((
            status_rank,
            is_open,
            snap.health_score,
            snap.avg_latency_ms,
            rep.clone(),
            node.clone(),
        ));
    }

    ranked.sort_by(|a, b| {
        a.0.cmp(&b.0)
            .then_with(|| a.1.cmp(&b.1))
            .then_with(|| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal))
            .then_with(|| a.3.cmp(&b.3))
            .then_with(|| a.5.node_id.cmp(&b.5.node_id))
    });

    ranked
        .into_iter()
        .map(|(_, _, _, _, rep, node)| (rep, node))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mk_node(id: &str, domain: &str, quota: u64, used: u64, latency: u64, health: f64) -> NodePlacementInfo {
        NodePlacementInfo {
            node_id: id.into(),
            remote_id: id.into(),
            base_prefix: "fm_pool".into(),
            failure_domain: domain.into(),
            quota_bytes: quota,
            used_bytes: used,
            remote_free_bytes: None,
            remote_total_bytes: None,
            role: NodeRole::Rw,
            is_meta_backup: false,
            db_health_score: health,
            db_avg_latency_ms: latency,
        }
    }

    #[test]
    fn selects_distinct_failure_domains_over_higher_same_domain_score() {
        let tracker = HealthTracker::default();
        let nodes = vec![
            mk_node("n1", "aws", 1000, 0, 20, 1.0),
            mk_node("n2", "aws", 1000, 50, 25, 1.0),
            mk_node("n3", "hetzner", 1000, 400, 80, 0.9),
        ];
        for n in &nodes {
            tracker.seed_node(&n.node_id, n.db_health_score, n.db_avg_latency_ms, None);
        }

        let picked = select_write_nodes(
            &nodes,
            &tracker,
            100,
            2,
            &HashSet::new(),
            &HashSet::new(),
        );
        assert_eq!(picked.len(), 2);
        assert_eq!(picked[0].node_id, "n1");
        assert_eq!(picked[1].node_id, "n3");
        assert_ne!(picked[0].failure_domain, picked[1].failure_domain);
    }

    #[test]
    fn falls_back_to_same_domain_when_no_other_domain_available() {
        let tracker = HealthTracker::default();
        let nodes = vec![
            mk_node("n1", "aws", 1000, 0, 20, 1.0),
            mk_node("n2", "aws", 1000, 100, 30, 1.0),
        ];
        for n in &nodes {
            tracker.seed_node(&n.node_id, n.db_health_score, n.db_avg_latency_ms, None);
        }

        let picked = select_write_nodes(
            &nodes,
            &tracker,
            100,
            2,
            &HashSet::new(),
            &HashSet::new(),
        );
        assert_eq!(picked.len(), 2);
    }

    #[test]
    fn respects_quota_and_avoided_domains() {
        let tracker = HealthTracker::default();
        let nodes = vec![
            mk_node("n1", "d1", 1000, 950, 10, 1.0), // only 50 free -> too small for 100
            mk_node("n2", "d1", 1000, 0, 10, 1.0),
            mk_node("n3", "d2", 1000, 0, 50, 1.0),
        ];
        for n in &nodes {
            tracker.seed_node(&n.node_id, n.db_health_score, n.db_avg_latency_ms, None);
        }
        let avoid = HashSet::from(["d1".to_string()]);
        let picked = select_write_nodes(&nodes, &tracker, 100, 1, &HashSet::new(), &avoid);
        assert_eq!(picked.len(), 1);
        assert_eq!(picked[0].node_id, "n3");
    }

    #[test]
    fn free_bytes_caps_quota_by_remote_free_bytes() {
        let mut node = mk_node("n1", "d1", 1000, 200, 10, 1.0);
        assert_eq!(node.free_bytes(), 800);
        node.remote_free_bytes = Some(150);
        assert_eq!(node.free_bytes(), 150);
        node.remote_free_bytes = Some(5000);
        assert_eq!(node.free_bytes(), 800);
    }
}
