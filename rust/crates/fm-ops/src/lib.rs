//! Long-running file operations with progress.
//!
//! The original app runs copy, move, delete, compress and extract through a
//! foreground command service. The equivalent here is a task model the FFI
//! layer can drive and the UI can observe.

use fm_core::VfsPath;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OperationKind {
    Copy,
    Move,
    Delete,
    Rename,
    Compress,
    Extract,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskState {
    Pending,
    Running,
    Cancelled,
    Failed,
    Completed,
}

#[derive(Debug, Clone)]
pub struct TaskProgress {
    pub state: TaskState,
    /// Bytes or items processed so far.
    pub completed: u64,
    /// Total when known; `None` for operations whose size is unknown upfront.
    pub total: Option<u64>,
    /// Item currently being processed.
    pub current: Option<VfsPath>,
}

impl TaskProgress {
    pub fn pending() -> Self {
        Self {
            state: TaskState::Pending,
            completed: 0,
            total: None,
            current: None,
        }
    }

    /// Fraction in `0.0..=1.0`, or `None` when the total is unknown. A total of
    /// zero reports `Some(1.0)` so an empty operation reads as finished.
    pub fn fraction(&self) -> Option<f32> {
        match self.total {
            None => None,
            Some(0) => Some(1.0),
            Some(total) => Some((self.completed.min(total) as f64 / total as f64) as f32),
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(
            self.state,
            TaskState::Cancelled | TaskState::Failed | TaskState::Completed
        )
    }
}

#[derive(Debug, Clone)]
pub struct TaskSpec {
    pub kind: OperationKind,
    pub sources: Vec<VfsPath>,
    pub destination: Option<VfsPath>,
}

impl fmt::Display for OperationKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Copy => "copy",
            Self::Move => "move",
            Self::Delete => "delete",
            Self::Rename => "rename",
            Self::Compress => "compress",
            Self::Extract => "extract",
        };
        f.write_str(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fraction_handles_unknown_and_zero_totals() {
        let mut progress = TaskProgress::pending();
        assert_eq!(progress.fraction(), None);
        progress.total = Some(0);
        assert_eq!(progress.fraction(), Some(1.0));
        progress.total = Some(200);
        progress.completed = 50;
        assert_eq!(progress.fraction(), Some(0.25));
    }

    #[test]
    fn terminal_states_are_reported() {
        let mut progress = TaskProgress::pending();
        assert!(!progress.is_terminal());
        progress.state = TaskState::Running;
        assert!(!progress.is_terminal());
        progress.state = TaskState::Cancelled;
        assert!(progress.is_terminal());
    }
}
