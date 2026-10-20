//! Manual check against a real WebDAV server (rclone `serve webdav`).
//!
//! ```text
//! rclone serve webdav /tmp/fmtest/files --addr 127.0.0.1:8081 --user test --pass test
//! FM_TEST_WEBDAV_ENDPOINT=http://127.0.0.1:8081 \
//!   cargo test -p fm-remote --test local_webdav_stream -- --ignored
//! ```

use fm_core::{LocationKind, VfsPath};
use fm_remote::{OpendalFs, RemoteConfig};
use fm_vfs::Vfs;
use tokio::io::AsyncReadExt;

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
    }
}

// Reqwest dispatches on a separate task; a current-thread runtime stalls that
// task while the test blocks on the reader.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires a local WebDAV server"]
async fn reads_a_byte_range_over_webdav() {
    let fs = OpendalFs::new_webdav(&config()).expect("operator");
    let name = std::env::var("FM_TEST_WEBDAV_FILE").unwrap_or_else(|_| "sample.mp4".into());
    let path = VfsPath::from_slash_path(&name);

    let entry = fs.stat(&path).await.expect("stat");
    let size = entry.size.expect("size");
    assert!(size > 0);

    let offset = size / 2;
    let want = 32 * 1024u64;
    let mut reader = fs
        .open_read_range(&path, offset, Some(want))
        .await
        .expect("open range");
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).await.expect("read");
    assert_eq!(buf.len() as u64, want);
}
