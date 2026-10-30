use std::io::{Read, Write};
use std::net::TcpStream;

fn get_request(port: u16, path: &str) -> (u16, String, String) {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let req = format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");
    stream.write_all(req.as_bytes()).expect("write");
    stream.flush().ok();

    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).expect("read");
    let split = raw
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .expect("header terminator");
    let head = String::from_utf8_lossy(&raw[..split]).to_string();
    let body = String::from_utf8_lossy(&raw[split + 4..]).to_string();

    let status = head
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .and_then(|code| code.parse().ok())
        .expect("status code");
    (status, head, body)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_http_share_endpoints() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("file.txt"), "hello world").unwrap();
    std::fs::create_dir(temp.path().join("subfolder")).unwrap();
    std::fs::write(temp.path().join("subfolder").join("inner.txt"), "inside").unwrap();

    let server = fm_server::start_http_share(temp.path().to_path_buf(), None, None, true)
        .await
        .expect("start http share");
    let port = server.port;

    // Test 1: GET /
    let (status, _, body) = get_request(port, "/");
    assert_eq!(status, 200);
    assert!(body.contains("LAN File Sharing"));

    // Test 2: GET /api/list/
    let (status_slash, _, body_slash) = get_request(port, "/api/list/");
    println!("GET /api/list/ -> status: {status_slash}, body: {body_slash}");

    // Test 3: GET /api/list
    let (status_no_slash, _, body_no_slash) = get_request(port, "/api/list");
    println!("GET /api/list -> status: {status_no_slash}, body: {body_no_slash}");

    // Test 4: GET /api/list/subfolder
    let (status_sub, _, body_sub) = get_request(port, "/api/list/subfolder");
    println!("GET /api/list/subfolder -> status: {status_sub}, body: {body_sub}");

    let _ = server.shutdown_tx.send(());
}
