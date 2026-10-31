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

fn post_multipart(port: u16, path: &str, boundary: &str, body_bytes: &[u8]) -> (u16, String, String) {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let req_header = format!(
        "POST {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: multipart/form-data; boundary={boundary}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body_bytes.len()
    );
    stream.write_all(req_header.as_bytes()).expect("write header");
    stream.write_all(body_bytes).expect("write body");
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

fn build_multipart_body(boundary: &str, files: &[(&str, &[u8])]) -> Vec<u8> {
    let mut out = Vec::new();
    for (filename, content) in files {
        out.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        out.extend_from_slice(
            format!("Content-Disposition: form-data; name=\"files\"; filename=\"{filename}\"\r\n").as_bytes(),
        );
        out.extend_from_slice(b"Content-Type: application/octet-stream\r\n\r\n");
        out.extend_from_slice(content);
        out.extend_from_slice(b"\r\n");
    }
    out.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    out
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_http_share_upload_folder_and_files() {
    let temp = tempfile::tempdir().unwrap();
    let server = fm_server::start_http_share(temp.path().to_path_buf(), None, None, false)
        .await
        .expect("start writable http share");
    let port = server.port;

    // Test GET /api/config
    let (status, _, body) = get_request(port, "/api/config");
    assert_eq!(status, 200);
    assert!(body.contains("\"read_only\":false"));

    // Test POST /api/upload with folder hierarchy
    let boundary = "----WebKitFormBoundaryX9Y8Z7";
    let files: &[(&str, &[u8])] = &[
        ("my_folder/docs/readme.txt", b"readme contents"),
        ("my_folder/images/logo.png", b"fake png data"),
        ("root_file.txt", b"root content"),
    ];
    let body_bytes = build_multipart_body(boundary, files);

    let (upload_status, _, upload_body) = post_multipart(port, "/api/upload", boundary, &body_bytes);
    assert_eq!(upload_status, 200);
    assert!(upload_body.contains("\"success\":true"));
    assert!(upload_body.contains("\"uploaded_files\":3"));

    // Verify files and directories created on disk
    let readme_path = temp.path().join("my_folder").join("docs").join("readme.txt");
    assert!(readme_path.exists());
    assert_eq!(std::fs::read_to_string(readme_path).unwrap(), "readme contents");

    let logo_path = temp.path().join("my_folder").join("images").join("logo.png");
    assert!(logo_path.exists());
    assert_eq!(std::fs::read(logo_path).unwrap(), b"fake png data");

    let root_file_path = temp.path().join("root_file.txt");
    assert!(root_file_path.exists());
    assert_eq!(std::fs::read_to_string(root_file_path).unwrap(), "root content");

    let _ = server.shutdown_tx.send(());

    // Test upload in read-only mode should fail with 403
    let server_ro = fm_server::start_http_share(temp.path().to_path_buf(), None, None, true)
        .await
        .expect("start read_only http share");
    let port_ro = server_ro.port;

    let (ro_status, _, _) = post_multipart(port_ro, "/api/upload", boundary, &body_bytes);
    assert_eq!(ro_status, 403);

    let _ = server_ro.shutdown_tx.send(());
}
