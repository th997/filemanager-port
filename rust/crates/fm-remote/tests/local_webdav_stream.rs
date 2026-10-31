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
        host_key_fingerprint: None,
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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires remote WebDAV"]
async fn writes_streaming_data_over_webdav() {
    use tokio::io::AsyncWriteExt;
    let fs = OpendalFs::new_webdav(&config()).expect("operator");
    let test_path = VfsPath::from_slash_path("/test_stream_verify.txt");

    let mut writer = fs.open_write(&test_path, fm_core::WriteMode::Truncate).await.expect("open_write");
    let test_bytes = b"Hello world from streaming WebDAV pipe writer!";
    writer.write_all(test_bytes).await.expect("write_all");
    writer.flush().await.expect("flush");
    writer.shutdown().await.expect("shutdown");

    let meta = fs.stat(&test_path).await.expect("stat");
    assert_eq!(meta.size, Some(test_bytes.len() as u64));

    let mut reader = fs.open_read(&test_path).await.expect("open_read");
    let mut downloaded = Vec::new();
    reader.read_to_end(&mut downloaded).await.expect("read_to_end");
    assert_eq!(downloaded, test_bytes);

    fs.remove(&test_path).await.expect("remove");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
#[ignore = "requires remote WebDAV"]
async fn writes_multi_chunk_stream_over_webdav() {
    use tokio::io::AsyncWriteExt;
    let fs = OpendalFs::new_webdav(&config()).expect("operator");
    let test_path = VfsPath::from_slash_path("/test_multi_chunk.bin");

    let mut writer = fs.open_write(&test_path, fm_core::WriteMode::Truncate).await.expect("open_write");
    let chunk = vec![0xABu8; 64 * 1024]; // 64 KB
    let num_chunks = 16; // 1 MB total
    for _ in 0..num_chunks {
        writer.write_all(&chunk).await.expect("write_all chunk");
    }
    writer.flush().await.expect("flush");
    writer.shutdown().await.expect("shutdown");

    let meta = fs.stat(&test_path).await.expect("stat");
    assert_eq!(meta.size, Some((num_chunks * chunk.len()) as u64));

    fs.remove(&test_path).await.expect("remove");
}
