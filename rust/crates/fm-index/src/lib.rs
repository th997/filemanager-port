//! Persistent metadata: bookmarks, history, search index, recycle bin.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

pub mod db;
pub mod secret;

use fm_core::{LocationId, VfsPath};
pub use db::{
    Database, IndexStatsRecord, IndexedFileRecord, PinnedFileRecord, PoolRecord, RemoteRecord,
};

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

        // Pool test (including encryption at rest for passphrase)
        let pool = PoolRecord {
            id: "pool-1".into(),
            name: "Mixed Cloud Pool".into(),
            config_json: r#"{"id":"pool-1","passphrase":"super-secret-pool-key"}"#.into(),
            created_at: 2000,
        };
        db.save_pool(&pool).unwrap();
        let pools = db.list_pools().unwrap();
        assert_eq!(pools.len(), 1);
        assert_eq!(pools[0].id, "pool-1");
        assert_eq!(pools[0].config_json, pool.config_json);
        let fetched = db.get_pool("pool-1").unwrap().unwrap();
        assert_eq!(fetched.config_json, pool.config_json);
        db.delete_pool("pool-1").unwrap();
        assert!(db.get_pool("pool-1").unwrap().is_none());
        assert_eq!(db.list_pools().unwrap().len(), 0);
    }

    #[test]
    fn concurrent_database_open_and_queries_do_not_lock() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_file = temp_dir.path().join("concurrent.db");
        let trash_dir = temp_dir.path().join("trash");
        let threads = 12;
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(threads));

        let mut handles = Vec::with_capacity(threads);
        for i in 0..threads {
            let db_p = db_file.clone();
            let tr_p = trash_dir.clone();
            let b = barrier.clone();
            handles.push(std::thread::spawn(move || {
                b.wait();
                let db = Database::open(&db_p, &tr_p).unwrap();
                let _ = db.list_remotes().unwrap();
                let _ = db.list_bookmarks().unwrap();
                let _ = db.list_history(50).unwrap();
                let _ = db.list_trash().unwrap();
                db.save_remote(&RemoteRecord {
                    id: format!("r-{i}"),
                    kind: "s3".into(),
                    display_name: format!("Remote {i}"),
                    config_json: "{}".into(),
                    created_at: i as i64,
                })
                .unwrap();
            }));
        }

        for h in handles {
            h.join().unwrap();
        }

        let db = Database::open(&db_file, &trash_dir).unwrap();
        assert_eq!(db.list_remotes().unwrap().len(), threads);
    }

    #[test]
    fn fts5_search_index_crud_and_query() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = Database::in_memory(temp_dir.path()).unwrap();

        let entries = vec![
            IndexedFileRecord {
                root: "/data".into(),
                path: "/Docs/Annual_Report_2026.pdf".into(),
                name: "Annual_Report_2026.pdf".into(),
                ext: "pdf".into(),
                category: "document".into(),
                is_dir: false,
                size: 2048,
                modified_millis: Some(1_700_000_000_000),
                hidden: false,
            },
            IndexedFileRecord {
                root: "/data".into(),
                path: "/Photos/sunset_beach.jpg".into(),
                name: "sunset_beach.jpg".into(),
                ext: "jpg".into(),
                category: "image".into(),
                is_dir: false,
                size: 4096,
                modified_millis: Some(1_700_000_100_000),
                hidden: false,
            },
            IndexedFileRecord {
                root: "/data".into(),
                path: "/.hidden_secret.txt".into(),
                name: ".hidden_secret.txt".into(),
                ext: "txt".into(),
                category: "document".into(),
                is_dir: false,
                size: 128,
                modified_millis: Some(1_700_000_200_000),
                hidden: true,
            },
        ];

        let stats = db.replace_root_index("/data", &entries).unwrap();
        assert_eq!(stats.entry_count, 3);
        assert_eq!(db.get_index_stats(Some("/data")).unwrap().len(), 1);

        // Prefix FTS5 match + category filter
        let hits = db
            .query_fts_index(
                Some("/data"),
                "annual report",
                Some("document"),
                None,
                None,
                None,
                None,
                false,
                20,
            )
            .unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "Annual_Report_2026.pdf");

        // Infix LIKE fallback when FTS5 prefix doesn't match mid-word
        let infix_hits = db
            .query_fts_index(Some("/data"), "nual", None, None, None, None, None, false, 20)
            .unwrap();
        assert_eq!(infix_hits.len(), 1);

        // Hidden entry exclusion & inclusion
        let hidden_excl = db
            .query_fts_index(Some("/data"), "secret", None, None, None, None, None, false, 20)
            .unwrap();
        assert!(hidden_excl.is_empty());
        let hidden_incl = db
            .query_fts_index(Some("/data"), "secret", None, None, None, None, None, true, 20)
            .unwrap();
        assert_eq!(hidden_incl.len(), 1);

        assert!(db.clear_root_index("/data").unwrap());
        assert!(db.get_index_stats(Some("/data")).unwrap().is_empty());
    }
}
