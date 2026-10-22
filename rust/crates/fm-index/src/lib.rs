//! Persistent metadata: bookmarks, history, search index, recycle bin.

pub mod db;
pub mod secret;

use fm_core::{LocationId, VfsPath};
pub use db::{Database, RemoteRecord};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bookmark {
    pub location: LocationId,
    pub path: VfsPath,
    pub display_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryEntry {
    pub location: LocationId,
    pub path: VfsPath,
    /// Milliseconds since the Unix epoch, as recorded by the caller.
    pub visited_at_millis: i64,
}

/// An item moved to the in-app recycle bin.
///
/// Paths are stored as raw native path strings: a `VfsPath` cannot represent a
/// Windows drive path (`C:\...`) without losing the drive and separator form.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecycleItem {
    pub location: LocationId,
    pub original_path: String,
    pub stored_path: String,
    pub deleted_at_millis: i64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn database_crud_flow() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = Database::in_memory(temp_dir.path()).unwrap();

        // Bookmark test
        let bm = Bookmark {
            location: LocationId("loc1".into()),
            path: VfsPath::from_slash_path("/test"),
            display_name: "Test Bookmark".into(),
        };
        db.add_bookmark(&bm).unwrap();
        let list = db.list_bookmarks().unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].display_name, "Test Bookmark");
        db.remove_bookmark("loc1", "/test").unwrap();
        assert_eq!(db.list_bookmarks().unwrap().len(), 0);

        // Remote test
        let remote = RemoteRecord {
            id: "s3-test".into(),
            kind: "S3".into(),
            display_name: "My Bucket".into(),
            config_json: "{}".into(),
            created_at: 1000,
        };
        db.save_remote(&remote).unwrap();
        let remotes = db.list_remotes().unwrap();
        assert_eq!(remotes.len(), 1);
        assert_eq!(remotes[0].id, "s3-test");
        db.delete_remote("s3-test").unwrap();
        assert_eq!(db.list_remotes().unwrap().len(), 0);
    }
}
