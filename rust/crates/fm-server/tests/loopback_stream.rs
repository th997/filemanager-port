//! End-to-end checks for the loopback stream server over a real HTTP socket.

use fm_local::LocalFs;
use fm_server::start_stream_server;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::Path;
use std::sync::Arc;

/// Minimal HTTP/1.1 request; avoids pulling a client crate into dev-deps.
fn request(port: u16, token: &str, path: &str, method: &str, headers: &[(&str, &str)]) -> (u16, String, Vec<u8>) {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let mut req = format!("{method} /stream/{token}/{path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n");
    for (name, value) in headers {
        req.push_str(&format!("{name}: {value}\r\n"));
    }
    req.push_str("\r\n");
    stream.write_all(req.as_bytes()).expect("write");
    stream.flush().ok();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).expect("read");
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .expect("header terminator");
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let body = raw[split + 4..].to_vec();

    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse().ok())
        .expect("status code");
    (status, head, body)
}

/// Keep the runtime alive for the server's lifetime; dropping it would stop
/// the spawned serve loop.
struct Running {
    server: fm_server::StreamServer,
    runtime: tokio::runtime::Runtime,
    port: u16,
    token: String,
}

impl Running {
    fn start(dir: &Path) -> Self {
        let vfs = Arc::new(LocalFs::new(dir.to_string_lossy().to_string()));
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let server = runtime.block_on(start_stream_server(vfs)).expect("server");
        let port = server.port;
        let token = server.token.clone();
        Self {
            server,
            runtime,
            port,
            token,
        }
    }

    fn shutdown(self) {
        self.server.shutdown();
        drop(self.runtime);
    }
}

#[test]
fn serves_full_and_partial_ranges() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("data.bin"), b"0123456789abcdef").unwrap();
    let running = Running::start(temp.path());
    let (port, token) = (running.port, running.token.as_str());

    let (status, head, body) = request(port, token, "data.bin", "GET", &[]);
    assert_eq!(status, 200);
    assert!(head.contains("content-length: 16"));
    assert_eq!(body, b"0123456789abcdef");

    let (status, head, body) = request(port, token, "data.bin", "GET", &[("Range", "bytes=4-9")]);
    assert_eq!(status, 206);
    assert!(head.contains("content-range: bytes 4-9/16"));
    assert!(head.contains("content-length: 6"));
    assert_eq!(body, b"456789");

    let (status, head, _) = request(port, token, "data.bin", "GET", &[("Range", "bytes=99-")]);
    assert_eq!(status, 416);
    assert!(head.contains("content-range: bytes */16"));

    let (status, head, body) = request(port, token, "data.bin", "HEAD", &[]);
    assert_eq!(status, 200);
    assert!(head.contains("content-length: 16"));
    assert!(body.is_empty());

    running.shutdown();
}

#[test]
fn serves_empty_file_with_zero_length() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("empty.txt"), b"").unwrap();
    let running = Running::start(temp.path());
    let (port, token) = (running.port, running.token.as_str());

    let (status, head, body) = request(port, token, "empty.txt", "GET", &[]);
    assert_eq!(status, 200);
    assert!(head.contains("content-length: 0"));
    assert!(body.is_empty());

    running.shutdown();
}

#[test]
fn rejects_wrong_token() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("data.bin"), b"x").unwrap();
    let running = Running::start(temp.path());

    let (status, _, _) = request(running.port, "wrong", "data.bin", "GET", &[]);
    assert_eq!(status, 401);

    running.shutdown();
}
