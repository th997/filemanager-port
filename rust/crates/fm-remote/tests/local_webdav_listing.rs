//! Manual check against a real WebDAV server (rclone `serve webdav`).
//!
//! ```text
//! rclone serve webdav /tmp/fmtest/files --addr 127.0.0.1:8081 --user test --pass test
//! FM_TEST_WEBDAV_ENDPOINT=http://127.0.0.1:8081 \
//!   cargo test -p fm-remote --test local_webdav_listing -- --ignored
//! ```
//!
//! Kept separate from the range test because OpenDAL installs a process-wide
//! HTTP transport tied to the first runtime that uses it; several runtimes in
//! one test binary would share a transport whose dispatch task has been dropped.

use fm_core::{LocationKind, VfsPath};
use fm_remote::{OpendalFs, RemoteConfig};
use fm_vfs::Vfs;

fn config() -> RemoteConfig {
    RemoteConfig {
        id: "test".into(),
        kind: LocationKind::WebDav,
        display_name: "test".into(),
        endpoint: Some(
            std::env::var("FM_TEST_WEBDAV_ENDPOINT")
                .unwrap_or_else(|_| "http://127.0.0.1:8081".into()),
        ),
        region: None,
        bucket: None,
        host: None,
        port: None,
        root: String::new(),
        username: Some("test".into()),
        password: Some("test".into()),
        key_id: None,
        key_secret: None,
        private_key: None,
        path_style: true,
        host_key_fingerprint: None,
    }
}

#[tokio::test]
#[ignore = "requires a local WebDAV server"]
async fn listing_has_no_self_entry_and_pages_agree() {
    let fs = OpendalFs::new_webdav(&config()).expect("operator");

    let root_entries = fs.list(&VfsPath::root()).await.expect("list root");
    let names: Vec<_> = root_entries.iter().map(|e| e.name.as_str()).collect();
    assert!(names.contains(&"aa"), "root listing: {names:?}");
    assert!(!names.iter().any(|n| n.is_empty()), "empty child name: {names:?}");

    let aa_path = VfsPath::from_slash_path("aa");
    let aa_entries = fs.list(&aa_path).await.expect("list aa");
    let aa_names: Vec<_> = aa_entries.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(aa_names, vec!["sub", "one.txt"], "aa listing: {aa_names:?}");

    // The prefix directory must not appear as its own child: deleting `aa`
    // recursively would otherwise try to remove `aa/aa`.
    assert!(!aa_names.contains(&"aa"));

    // Pages must partition the same entries as the unpaged listing, with no
    // duplicates and no self-referencing entry.
    let mut names = Vec::new();
    let mut page = 1;
    loop {
        let (entries, has_more) = fs.list_paged(&aa_path, page, 1).await.expect("page");
        names.extend(entries.into_iter().map(|e| e.name));
        if !has_more {
            break;
        }
        page += 1;
    }
    names.sort();
    assert_eq!(names, vec!["one.txt", "sub"]);
}
