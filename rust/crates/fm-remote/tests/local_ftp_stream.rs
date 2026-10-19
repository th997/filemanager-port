//! Manual check against a real FTP server.
//!
//! Run with a server on `FM_TEST_FTP_ADDR` (default `127.0.0.1:2121`) that
//! serves `FM_TEST_FTP_FILE` (default `sample.mp4`):
//!
//! ```text
//! python3 -m pyftpdlib -p 2121 -d /tmp/fmtest/files -u test -P test
//! FM_TEST_FTP_ADDR=127.0.0.1:2121 cargo test -p fm-remote --test local_ftp_stream -- --ignored
//! ```
//!
//! The point is that a small range must come back without transferring the
//! whole file: the test asks for 64 KiB and checks the bytes.

use fm_core::{LocationKind, VfsPath};
use fm_remote::{FtpFs, RemoteConfig};
use fm_vfs::Vfs;
use tokio::io::AsyncReadExt;

fn config() -> RemoteConfig {
    let addr = std::env::var("FM_TEST_FTP_ADDR").unwrap_or_else(|_| "127.0.0.1:2121".into());
    let (host, port) = addr.rsplit_once(':').expect("host:port");
    RemoteConfig {
        id: "test".into(),
        kind: LocationKind::Ftp,
        display_name: "test".into(),
        endpoint: None,
        region: None,
        bucket: None,
        host: Some(host.to_string()),
        port: Some(port.parse().expect("port")),
        root: String::new(),
        username: Some(std::env::var("FM_TEST_FTP_USER").unwrap_or_else(|_| "test".into())),
        password: Some(std::env::var("FM_TEST_FTP_PASS").unwrap_or_else(|_| "test".into())),
        key_id: None,
        key_secret: None,
        private_key: None,
        path_style: false,
    }
}

#[tokio::test]
#[ignore = "requires a local FTP server"]
async fn reads_a_byte_range_from_ftp() {
    let fs = FtpFs::new(&config());
    let name = std::env::var("FM_TEST_FTP_FILE").unwrap_or_else(|_| "sample.mp4".into());
    let path = VfsPath::from_slash_path(&name);

    let entry = fs.stat(&path).await.expect("stat");
    let size = entry.size.expect("size");
    assert!(size > 0, "server reported no size");

    let offset = size / 3;
    let want = 64 * 1024u64;
    let mut reader = fs
        .open_read_range(&path, offset, Some(want))
        .await
        .expect("open range");
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).await.expect("read");
    assert_eq!(buf.len() as u64, want, "short range");
}

#[tokio::test]
#[ignore = "requires a local FTP server"]
async fn open_read_streams_the_whole_file() {
    let fs = FtpFs::new(&config());
    let name = std::env::var("FM_TEST_FTP_FILE").unwrap_or_else(|_| "sample.mp4".into());
    let path = VfsPath::from_slash_path(&name);

    let entry = fs.stat(&path).await.expect("stat");
    let mut reader = fs.open_read(&path).await.expect("open");
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).await.expect("read");
    assert_eq!(Some(buf.len() as u64), entry.size);
}
