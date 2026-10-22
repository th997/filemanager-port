//! Long-running file operations with progress.
//!
//! The original app runs copy, move, delete, compress and extract through a
//! foreground command service. The equivalent here is a task model the FFI
//! layer can drive and the UI can observe.

use fm_core::VfsPath;
use std::fmt;

pub mod runner;
pub use runner::{copy_recursive, delete_recursive, total_bytes, TaskHandle, TaskManager};

/// What to do when a copy/move destination already exists.
///
/// Until this existed, the answer was hard-coded: files were silently
/// overwritten and directories silently merged, so pasting a new version
/// of a document over an old one destroyed the old one without a word.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictPolicy {
    /// Replace the existing destination (the historical behaviour).
    Overwrite,
    /// Leave the existing destination alone and skip the source item.
    Skip,
    /// Keep both: write the source under a generated `name_copy` name.
    Rename,
}

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
    /// Why the task failed, when it did.
    pub error: Option<String>,
    /// Destination items left untouched by the `Skip` conflict policy.
    pub skipped: u64,
    /// Short human label for the operation ("Copy", "Move", ...), set by
    /// whoever started the task so a task list can say what each row is.
    pub label: Option<String>,
}

impl TaskProgress {
    pub fn pending() -> Self {
        Self {
            state: TaskState::Pending,
            completed: 0,
            total: None,
            current: None,
            error: None,
            skipped: 0,
            label: None,
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

    #[tokio::test]
    async fn copy_and_delete_flow() {
        use fm_local::LocalFs;
        use std::sync::{Arc, Mutex};
        use tokio_util::sync::CancellationToken;

        let temp1 = tempfile::tempdir().unwrap();
        let temp2 = tempfile::tempdir().unwrap();

        std::fs::write(temp1.path().join("file.txt"), b"copied content").unwrap();

        let src_fs = LocalFs::new(temp1.path());
        let dst_fs = LocalFs::new(temp2.path());

        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        let cancel = CancellationToken::new();

        copy_recursive(
            &src_fs,
            &VfsPath::from_slash_path("/file.txt"),
            &dst_fs,
            &VfsPath::from_slash_path("/file_dest.txt"),
            &progress,
            &cancel,
            ConflictPolicy::Overwrite,
        )
        .await
        .unwrap();

        assert_eq!(
            std::fs::read(temp2.path().join("file_dest.txt")).unwrap(),
            b"copied content"
        );

        delete_recursive(
            &dst_fs,
            &VfsPath::from_slash_path("/file_dest.txt"),
            &progress,
            &cancel,
        )
        .await
        .unwrap();

        assert!(!temp2.path().join("file_dest.txt").exists());
    }

    #[tokio::test]
    async fn copy_conflict_policies() {
        use fm_local::LocalFs;
        use std::sync::{Arc, Mutex};
        use tokio_util::sync::CancellationToken;

        let src_dir = tempfile::tempdir().unwrap();
        let dst_dir = tempfile::tempdir().unwrap();
        std::fs::write(src_dir.path().join("file.txt"), b"new").unwrap();
        std::fs::write(dst_dir.path().join("file.txt"), b"old").unwrap();

        let src_fs = LocalFs::new(src_dir.path());
        let dst_fs = LocalFs::new(dst_dir.path());
        let src = VfsPath::from_slash_path("/file.txt");
        let dst = VfsPath::from_slash_path("/file.txt");
        let cancel = CancellationToken::new();

        // Skip: the existing file is untouched and the skip is counted.
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        copy_recursive(&src_fs, &src, &dst_fs, &dst, &progress, &cancel, ConflictPolicy::Skip)
            .await
            .unwrap();
        assert_eq!(std::fs::read(dst_dir.path().join("file.txt")).unwrap(), b"old");
        assert_eq!(progress.lock().unwrap().skipped, 1);

        // Rename: both versions survive, the incoming one under a _copy name.
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        copy_recursive(&src_fs, &src, &dst_fs, &dst, &progress, &cancel, ConflictPolicy::Rename)
            .await
            .unwrap();
        assert_eq!(std::fs::read(dst_dir.path().join("file.txt")).unwrap(), b"old");
        assert_eq!(
            std::fs::read(dst_dir.path().join("file_copy.txt")).unwrap(),
            b"new"
        );

        // Overwrite: the destination is replaced.
        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        copy_recursive(
            &src_fs,
            &src,
            &dst_fs,
            &dst,
            &progress,
            &cancel,
            ConflictPolicy::Overwrite,
        )
        .await
        .unwrap();
        assert_eq!(std::fs::read(dst_dir.path().join("file.txt")).unwrap(), b"new");
    }
}
