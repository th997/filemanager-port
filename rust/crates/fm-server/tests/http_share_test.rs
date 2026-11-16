use base64::Engine as _;
use std::io::{Read, Write};
use std::net::TcpStream;

const PASSWORD: &str = "test-pass";

/// The web UI authenticates with a random per-share session token. Add it to
/// every request so the tests exercise the same path a real browser uses.
fn with_token(path: &str, token: &str) -> String {
    if path.contains('?') {
        format!("{path}&token={token}")
    } else {
        format!("{path}?token={token}")
    }
}

fn get_request(port: u16, path: &str) -> (u16, String, String) {
    raw_request(port, "GET", path, &[], None)
}

fn post_multipart(port: u16, path: &str, boundary: &str, body_bytes: &[u8]) -> (u16, String, String) {
    let content_type = format!("multipart/form-data; boundary={boundary}");
    raw_request(port, "POST", path, body_bytes, Some(content_type.as_str()))
}

fn raw_request(
    port: u16,
    method: &str,
    path: &str,
    body_bytes: &[u8],
    content_type: Option<&str>,
) -> (u16, String, String) {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let mut req = format!(
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    );
    if let Some(ct) = content_type {
        req.push_str(&format!("Content-Type: {ct}\r\n"));
    }
    req.push_str(&format!("Content-Length: {}\r\n\r\n", body_bytes.len()));
    stream.write_all(req.as_bytes()).expect("write");
    if !body_bytes.is_empty() {
        stream.write_all(body_bytes).expect("write body");
    }
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
async fn anonymous_requests_are_rejected() {
    let temp = tempfile::tempdir().unwrap();
    let server = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        false,
    )
    .await
    .expect("start http share");

    let (status, head, _) = get_request(server.port, "/");
    assert_eq!(status, 401);
    assert!(head.to_lowercase().contains("www-authenticate"));

    let (no_token, _, _) = get_request(server.port, "/api/list");
    assert_eq!(no_token, 401);

    // The password must not work as a URL token: that would leak it into
    // browser history, Referer headers and proxy logs.
    let (as_token, _, _) = get_request(server.port, &format!("/?token={PASSWORD}"));
    assert_eq!(as_token, 401);

    // Basic auth with the real password still works.
    let credentials =
        base64::engine::general_purpose::STANDARD.encode(format!("anyuser:{PASSWORD}"));
    let mut stream = TcpStream::connect(("127.0.0.1", server.port)).unwrap();
    let req = format!(
        "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Basic {credentials}\r\nConnection: close\r\n\r\n"
    );
    stream.write_all(req.as_bytes()).unwrap();
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).unwrap();
    let head = String::from_utf8_lossy(&raw).to_string();
    assert!(head.starts_with("HTTP/1.1 200"), "unexpected response: {head}");

    let _ = server.shutdown_tx.send(());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn share_page_wires_token_into_every_api_call() {
    let temp = tempfile::tempdir().unwrap();
    let server = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        true,
    )
    .await
    .expect("start http share");

    // The browser only has the URL token; every endpoint the page calls must
    // echo it back, otherwise browsing/downloading silently 401s.
    let (status, _, body) = get_request(server.port, &with_token("/", &server.share_token));
    assert_eq!(status, 200);
    for endpoint in [
        "withToken('/api/list')",
        "withToken('/api/config')",
        "withToken('/download/'",
        "withToken('/api/upload?dir='",
    ] {
        assert!(
            body.contains(endpoint),
            "share page does not authenticate {endpoint}"
        );
    }

    let _ = server.shutdown_tx.send(());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_http_share_endpoints() {
    let temp = tempfile::tempdir().unwrap();
    std::fs::write(temp.path().join("file.txt"), "hello world").unwrap();
    std::fs::create_dir(temp.path().join("subfolder")).unwrap();
    std::fs::write(temp.path().join("subfolder").join("inner.txt"), "inside").unwrap();

    let server = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        true,
    )
    .await
    .expect("start http share");
    let port = server.port;
    let token = server.share_token.clone();
    assert_ne!(token, PASSWORD);

    // Test 1: GET /
    let (status, _, body) = get_request(port, &with_token("/", &token));
    assert_eq!(status, 200);
    assert!(body.contains("LAN File Sharing"));

    // Test 2: GET /api/list/
    let (status_slash, _, body_slash) = get_request(port, &with_token("/api/list/", &token));
    println!("GET /api/list/ -> status: {status_slash}, body: {body_slash}");
    assert_eq!(status_slash, 200);

    // Test 3: GET /api/list
    let (status_no_slash, _, body_no_slash) = get_request(port, &with_token("/api/list", &token));
    println!("GET /api/list -> status: {status_no_slash}, body: {body_no_slash}");
    assert_eq!(status_no_slash, 200);

    // Test 4: GET /api/list/subfolder
    let (status_sub, _, body_sub) = get_request(port, &with_token("/api/list/subfolder", &token));
    println!("GET /api/list/subfolder -> status: {status_sub}, body: {body_sub}");
    assert_eq!(status_sub, 200);

    let _ = server.shutdown_tx.send(());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_http_share_upload_folder_and_files() {
    let temp = tempfile::tempdir().unwrap();
    let server = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        false,
    )
    .await
    .expect("start writable http share");
    let port = server.port;
    let token = server.share_token.clone();

    // Test GET /api/config
    let (status, _, body) = get_request(port, &with_token("/api/config", &token));
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

    let (upload_status, _, upload_body) = post_multipart(
        port,
        &with_token("/api/upload?dir=testdir", &token),
        boundary,
        &body_bytes,
    );
    assert_eq!(upload_status, 200, "upload body: {upload_body}");
    assert!(upload_body.contains("\"success\":true"));
    assert!(upload_body.contains("\"uploaded_files\":3"));

    // Verify files and directories created on disk
    let readme_path = temp.path().join("testdir").join("my_folder").join("docs").join("readme.txt");
    assert!(readme_path.exists());
    assert_eq!(std::fs::read_to_string(readme_path).unwrap(), "readme contents");

    let logo_path = temp.path().join("testdir").join("my_folder").join("images").join("logo.png");
    assert!(logo_path.exists());
    assert_eq!(std::fs::read(logo_path).unwrap(), b"fake png data");

    let root_file_path = temp.path().join("testdir").join("root_file.txt");
    assert!(root_file_path.exists());
    assert_eq!(std::fs::read_to_string(root_file_path).unwrap(), "root content");

    let _ = server.shutdown_tx.send(());

    // Test upload in read-only mode should fail with 403
    let server_ro = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        true,
    )
    .await
    .expect("start read_only http share");
    let port_ro = server_ro.port;
    let token_ro = server_ro.share_token.clone();

    let (ro_status, _, _) = post_multipart(
        port_ro,
        &with_token("/api/upload", &token_ro),
        boundary,
        &body_bytes,
    );
    assert_eq!(ro_status, 403);

    let _ = server_ro.shutdown_tx.send(());
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn upload_cannot_plant_directories_through_a_symlink() {
    let temp = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), temp.path().join("escape")).unwrap();

    let server = fm_server::start_http_share(
        temp.path().to_path_buf(),
        None,
        Some(PASSWORD.into()),
        false,
    )
    .await
    .expect("start writable http share");

    let boundary = "----fmboundary";
    let body = build_multipart_body(boundary, &[("file.txt", b"data")]);
    let (status, _, resp) = post_multipart(
        server.port,
        &with_token("/api/upload?dir=escape/newdir", &server.share_token),
        boundary,
        &body,
    );
    assert_eq!(status, 403, "upload through escaping symlink must be refused: {resp}");
    // The containment check must run before create_dir_all, so nothing is
    // planted outside the shared root.
    assert!(!outside.path().join("newdir").exists());

    let _ = server.shutdown_tx.send(());
}
