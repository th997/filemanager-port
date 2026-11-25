//! Per-node health tracking (EWMA latency, health score, and circuit breaker).

use parking_lot::RwLock;
use std::collections::HashMap;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    Closed,
    Open { opened_at: Instant },
    HalfOpen,
}

impl CircuitState {
    pub fn as_str(&self) -> &'static str {
        match self {
            CircuitState::Closed => "closed",
            CircuitState::Open { .. } => "open",
            CircuitState::HalfOpen => "half_open",
        }
    }
}

#[derive(Debug, Clone)]
pub struct NodeHealthSnapshot {
    pub health_score: f64,
    pub avg_latency_ms: u64,
    pub circuit_state: CircuitState,
    pub consecutive_failures: u32,
    pub last_checked_ms: Option<i64>,
}

impl Default for NodeHealthSnapshot {
    fn default() -> Self {
        Self {
            health_score: 1.0,
            avg_latency_ms: 200,
            circuit_state: CircuitState::Closed,
            consecutive_failures: 0,
            last_checked_ms: None,
        }
    }
}

#[derive(Debug)]
pub struct HealthTracker {
    nodes: RwLock<HashMap<String, NodeHealthSnapshot>>,
    open_duration: Duration,
    failure_threshold: u32,
}

impl Default for HealthTracker {
    fn default() -> Self {
        Self::new(Duration::from_secs(30), 3)
    }
}

impl HealthTracker {
    pub fn new(open_duration: Duration, failure_threshold: u32) -> Self {
        Self {
            nodes: RwLock::new(HashMap::new()),
            open_duration,
            failure_threshold: failure_threshold.max(1),
        }
    }

    pub fn seed_node(&self, node_id: &str, health_score: f64, avg_latency_ms: u64, last_checked_ms: Option<i64>) {
        let mut map = self.nodes.write();
        map.entry(node_id.to_string()).or_insert(NodeHealthSnapshot {
            health_score: health_score.clamp(0.05, 1.0),
            avg_latency_ms: avg_latency_ms.max(1),
            circuit_state: CircuitState::Closed,
            consecutive_failures: 0,
            last_checked_ms,
        });
    }

    pub fn snapshot(&self, node_id: &str) -> NodeHealthSnapshot {
        let now = Instant::now();
        let mut map = self.nodes.write();
        let entry = map.entry(node_id.to_string()).or_default();
        if let CircuitState::Open { opened_at } = entry.circuit_state {
            if now.duration_since(opened_at) >= self.open_duration {
                entry.circuit_state = CircuitState::HalfOpen;
            }
        }
        entry.clone()
    }

    pub fn is_circuit_open(&self, node_id: &str) -> bool {
        matches!(self.snapshot(node_id).circuit_state, CircuitState::Open { .. })
    }

    pub fn record_success(&self, node_id: &str, latency_ms: u64, checked_at_ms: i64) -> NodeHealthSnapshot {
        let mut map = self.nodes.write();
        let entry = map.entry(node_id.to_string()).or_default();
        let measured = latency_ms.max(1);
        entry.avg_latency_ms = ((entry.avg_latency_ms as f64) * 0.7 + (measured as f64) * 0.3)
            .round()
            .max(1.0) as u64;
        entry.health_score = (entry.health_score + 0.2).clamp(0.05, 1.0);
        entry.consecutive_failures = 0;
        entry.circuit_state = CircuitState::Closed;
        entry.last_checked_ms = Some(checked_at_ms);
        entry.clone()
    }

    pub fn record_failure(&self, node_id: &str, checked_at_ms: i64) -> NodeHealthSnapshot {
        let mut map = self.nodes.write();
        let entry = map.entry(node_id.to_string()).or_default();
        entry.consecutive_failures = entry.consecutive_failures.saturating_add(1);
        entry.health_score = (entry.health_score * 0.5).clamp(0.05, 1.0);
        entry.last_checked_ms = Some(checked_at_ms);
        if entry.consecutive_failures >= self.failure_threshold
            || matches!(entry.circuit_state, CircuitState::HalfOpen)
        {
            entry.circuit_state = CircuitState::Open {
                opened_at: Instant::now(),
            };
        }
        entry.clone()
    }

    pub fn reset_circuit(&self, node_id: &str) {
        let mut map = self.nodes.write();
        if let Some(entry) = map.get_mut(node_id) {
            entry.circuit_state = CircuitState::Closed;
            entry.consecutive_failures = 0;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn circuit_breaker_opens_and_recovers_via_half_open() {
        let tracker = HealthTracker::new(Duration::from_millis(25), 3);
        tracker.seed_node("n1", 1.0, 100, None);
        assert!(!tracker.is_circuit_open("n1"));

        tracker.record_failure("n1", 1);
        assert!(!tracker.is_circuit_open("n1"));
        tracker.record_failure("n1", 2);
        assert!(!tracker.is_circuit_open("n1"));
        let snap = tracker.record_failure("n1", 3);
        assert!(matches!(snap.circuit_state, CircuitState::Open { .. }));
        assert!(tracker.is_circuit_open("n1"));

        std::thread::sleep(Duration::from_millis(35));
        let half = tracker.snapshot("n1");
        assert_eq!(half.circuit_state, CircuitState::HalfOpen);
        assert!(!tracker.is_circuit_open("n1"));

        // Failure in half-open immediately re-opens.
        let reopened = tracker.record_failure("n1", 4);
        assert!(matches!(reopened.circuit_state, CircuitState::Open { .. }));

        std::thread::sleep(Duration::from_millis(35));
        assert_eq!(tracker.snapshot("n1").circuit_state, CircuitState::HalfOpen);
        let recovered = tracker.record_success("n1", 40, 5);
        assert_eq!(recovered.circuit_state, CircuitState::Closed);
        assert_eq!(recovered.consecutive_failures, 0);
        assert!(recovered.avg_latency_ms < 100);
    }
}
