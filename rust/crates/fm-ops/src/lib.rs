//! Long-running file operations with progress.
//!
//! The original app runs copy, move, delete, compress and extract through a
//! foreground command service. The equivalent here is a task model the FFI
//! layer can drive and the UI can observe.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

use fm_core::VfsPath;
use serde::{Deserialize, Serialize};
use std::fmt;

pub mod runner;
pub use runner::{
    copy_recursive, copy_recursive_with_control, delete_recursive, total_bytes, TaskControl,
    TaskHandle, TaskManager,
};

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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OperationKind {
    Copy,
    Move,
    Delete,
    Rename,
    Compress,
    Extract,
    Sync,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskState {
    Pending,
    Running,
    Paused,
    Cancelled,
    Failed,
    Completed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FailedTaskItem {
    pub src_root: String,
    pub src_path: String,
    pub dst_root: String,
    pub dst_path: String,
    pub is_dir: bool,
    pub error: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskHistoryRecord {
    pub id: String,
    pub state: TaskState,
    pub completed: u64,
    pub total: Option<u64>,
    pub current: Option<String>,
    pub error: Option<String>,
    pub skipped: u64,
    pub label: Option<String>,
    pub failed_items: Vec<FailedTaskItem>,
    pub retry_kind: Option<String>,
    pub conflict_policy: Option<String>,
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
    /// Skips caused specifically by the `Skip` conflict policy (internal,
    /// not exported). `skipped` also counts symlinks/special files, so move
    /// cannot use it to decide whether the source is still needed.
    pub policy_skips: u64,
    /// Short human label for the operation ("Copy", "Move", ...), set by
    /// whoever started the task so a task list can say what each row is.
    pub label: Option<String>,
    /// Per-item failures recorded during batch operations so failed items can
    /// be retried individually without re-running the entire batch.
    pub failed_items: Vec<FailedTaskItem>,
    /// Operation kind tag used for partial retry ("copy", "move", "delete", "sync").
    pub retry_kind: Option<String>,
    /// Conflict policy used by the original task ("overwrite", "skip", "rename").
    pub conflict_policy: Option<String>,
    /// Optional bandwidth throttle in bytes/second (0 = unlimited).
    pub rate_limit_bps: u64,
    /// Whether this task supports pause/resume.
    pub can_pause: bool,
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
            policy_skips: 0,
            label: None,
            failed_items: Vec::new(),
            retry_kind: None,
            conflict_policy: None,
            rate_limit_bps: 0,
            can_pause: false,
        }
    }

    pub fn from_history(record: &TaskHistoryRecord) -> Self {
        Self {
            state: match record.state {
                TaskState::Pending | TaskState::Running | TaskState::Paused => TaskState::Cancelled,
                terminal => terminal,
            },
            completed: record.completed,
            total: record.total,
            current: record.current.as_deref().map(VfsPath::from_slash_path),
            error: record.error.clone(),
            skipped: record.skipped,
            policy_skips: 0,
            label: record.label.clone(),
            failed_items: record.failed_items.clone(),
            retry_kind: record.retry_kind.clone(),
            conflict_policy: record.conflict_policy.clone(),
            rate_limit_bps: 0,
            can_pause: false,
        }
    }

    pub fn to_history(&self, id: &str) -> TaskHistoryRecord {
        TaskHistoryRecord {
            id: id.to_string(),
            state: self.state,
            completed: self.completed,
            total: self.total,
            current: self.current.as_ref().map(|c| c.to_slash_string()),
            error: self.error.clone(),
            skipped: self.skipped,
            label: self.label.clone(),
            failed_items: self.failed_items.clone(),
            retry_kind: self.retry_kind.clone(),
            conflict_policy: self.conflict_policy.clone(),
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
            Self::Sync => "sync",
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

    #[tokio::test]
    async fn copy_folder_with_broken_symlink_skips_and_completes() {
        use fm_local::LocalFs;
        use std::sync::{Arc, Mutex};
        use tokio_util::sync::CancellationToken;

        let src_dir = tempfile::tempdir().unwrap();
        let dst_dir = tempfile::tempdir().unwrap();

        std::fs::write(src_dir.path().join("good.txt"), b"good file").unwrap();
        std::fs::create_dir(src_dir.path().join("sub")).unwrap();
        std::fs::write(src_dir.path().join("sub").join("nested.txt"), b"nested file").unwrap();

        #[cfg(unix)]
        {
            let _ = std::os::unix::fs::symlink(
                "/nonexistent/path/that/does/not/exist",
                src_dir.path().join("broken_link"),
            );
        }

        let src_fs = LocalFs::new(src_dir.path());
        let dst_fs = LocalFs::new(dst_dir.path());

        let progress = Arc::new(Mutex::new(TaskProgress::pending()));
        let cancel = CancellationToken::new();

        copy_recursive(
            &src_fs,
            &VfsPath::root(),
            &dst_fs,
            &VfsPath::root(),
            &progress,
            &cancel,
            ConflictPolicy::Overwrite,
        )
        .await
        .unwrap();

        assert_eq!(
            std::fs::read(dst_dir.path().join("good.txt")).unwrap(),
            b"good file"
        );
        assert_eq!(
            std::fs::read(dst_dir.path().join("sub").join("nested.txt")).unwrap(),
            b"nested file"
        );
        #[cfg(unix)]
        assert!(progress.lock().unwrap().skipped >= 1);
    }

    #[tokio::test]
    async fn pause_resume_and_resumable_copy_work() {
        use fm_local::LocalFs;

        let src_dir = tempfile::tempdir().unwrap();
        let dst_dir = tempfile::tempdir().unwrap();
        let payload: Vec<u8> = (0..(512 * 1024)).map(|i| (i % 251) as u8).collect();
        std::fs::write(src_dir.path().join("big.bin"), &payload).unwrap();
        // Pre-seed a half-written `.fm-resume` file to verify range resume appends cleanly.
        std::fs::write(dst_dir.path().join(".big.bin.fm-resume"), &payload[..100_000]).unwrap();

        let src_fs = LocalFs::new(src_dir.path());
        let dst_fs = LocalFs::new(dst_dir.path());
        let mgr = TaskManager::new();
        let (progress, cancel, control) = mgr.register_with_control("t1");
        mgr.pause("t1");
        assert_eq!(mgr.get_progress("t1").unwrap().state, TaskState::Paused);

        let mgr_clone = mgr.clone();
        let resumer = tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(40)).await;
            assert!(mgr_clone.resume("t1"));
        });

        copy_recursive_with_control(
            &src_fs,
            &VfsPath::from_slash_path("big.bin"),
            &dst_fs,
            &VfsPath::from_slash_path("big.bin"),
            &progress,
            &cancel,
            &control,
            ConflictPolicy::Overwrite,
        )
        .await
        .unwrap();
        resumer.await.unwrap();

        assert_eq!(std::fs::read(dst_dir.path().join("big.bin")).unwrap(), payload);
        assert!(!dst_dir.path().join(".big.bin.fm-resume").exists());

        // History persistence round-trip.
        {
            let mut p = progress.lock().unwrap();
            p.state = TaskState::Failed;
            p.label = Some("Copy".into());
            p.failed_items.push(FailedTaskItem {
                src_root: "/a".into(),
                src_path: "x.txt".into(),
                dst_root: "/b".into(),
                dst_path: "x.txt".into(),
                is_dir: false,
                error: "timeout".into(),
            });
        }
        let hist_file = dst_dir.path().join("tasks.json");
        mgr.set_history_path(hist_file.clone());
        mgr.persist_history();

        let mgr2 = TaskManager::new();
        mgr2.set_history_path(hist_file);
        let restored = mgr2.get_progress("t1").unwrap();
        assert_eq!(restored.state, TaskState::Failed);
        assert_eq!(restored.failed_items.len(), 1);
        assert_eq!(restored.failed_items[0].src_path, "x.txt");
    }
}
