//! Persistent metadata: bookmarks, history, search index, recycle bin.
//!
//! Backed by SQLite. Schema and migrations land in M2; the types here define
//! what callers may store.

use fm_core::{LocationId, VfsPath};

#[derive(Debug, Clone)]
pub struct Bookmark {
    pub location: LocationId,
    pub path: VfsPath,
    pub display_name: String,
}

#[derive(Debug, Clone)]
pub struct HistoryEntry {
    pub location: LocationId,
    pub path: VfsPath,
    /// Milliseconds since the Unix epoch, as recorded by the caller.
    pub visited_at_millis: i64,
}

/// An item moved to the in-app recycle bin.
#[derive(Debug, Clone)]
pub struct RecycleItem {
    pub location: LocationId,
    pub original_path: VfsPath,
    pub stored_path: VfsPath,
    pub deleted_at_millis: i64,
}
