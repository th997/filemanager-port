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
    raw_request_with_headers(port, method, path, body_bytes, content_type, &[])
}

fn raw_request_with_headers(
    port: u16,
    method: &str,
    path: &str,
    body_bytes: &[u8],
    content_type: Option<&str>,
    extra_headers: &[(&str, &str)],
) -> (u16, String, String) {
    let mut stream = TcpStream::connect(("127.0.0.1", port)).expect("connect");
    let mut req = format!(
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    );
    if let Some(ct) = content_type {
        req.push_str(&format!("Content-Type: {ct}\r\n"));
    }
    for (k, v) in extra_headers {
        req.push_str(&format!("{k}: {v}\r\n"));
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

    // First visit to `GET /?token=` mints an HttpOnly cookie and 302-redirects to `/`.
    let (status, head, _) = get_request(server.port, &with_token("/", &server.share_token));
    assert_eq!(status, 302);
    assert!(head.to_lowercase().contains("location: /"));
    let set_cookie = head
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("set-cookie:"))
        .expect("Set-Cookie header on redirect");
    let cookie_pair = set_cookie
        .split_once(':')
        .unwrap()
        .1
        .trim()
        .split(';')
        .next()
        .unwrap()
        .trim()
        .to_string();

    // Following `/` with the minted HttpOnly cookie serves 200 OK without URL token.
    let (page_status, _, body) =
        raw_request_with_headers(server.port, "GET", "/", &[], None, &[("Cookie", &cookie_pair)]);
    assert_eq!(page_status, 200);
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

    // Test 1: GET /?token=... mints HttpOnly cookie and 302-redirects to `/`.
    let (status, redir_head, _) = get_request(port, &with_token("/", &token));
    assert_eq!(status, 302);
    let cookie_pair = redir_head
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("set-cookie:"))
        .unwrap()
        .split_once(':')
        .unwrap()
        .1
        .trim()
        .split(';')
        .next()
        .unwrap()
        .trim()
        .to_string();
    let (page_status, _, body) =
        raw_request_with_headers(port, "GET", "/", &[], None, &[("Cookie", &cookie_pair)]);
    assert_eq!(page_status, 200);
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

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn web_ui_honours_accept_language_and_app_default_lang() {
    let temp = tempfile::tempdir().unwrap();
    let server = fm_server::start_http_share(temp.path().to_path_buf(), None, None, true)
        .await
        .expect("start http share");

    for (accept, expected_lang) in [
        ("ja-JP,ja;q=0.9,en;q=0.8", "ja"),
        ("zh-CN,zh;q=0.9", "zh"),
        ("en-US,en;q=0.9", "en"),
        ("fr-FR,fr;q=0.9", "en"),
    ] {
        let (_, head, _) = get_request(server.port, &with_token("/", &server.share_token));
        let cookie_pair = head
            .lines()
            .find(|l| l.to_ascii_lowercase().starts_with("set-cookie:"))
            .unwrap()
            .split_once(':')
            .unwrap()
            .1
            .trim()
            .split(';')
            .next()
            .unwrap()
            .trim()
            .to_string();
        let (status, resp_head, body) = raw_request_with_headers(
            server.port,
            "GET",
            "/",
            &[],
            None,
            &[("Accept-Language", accept), ("Cookie", &cookie_pair)],
        );
        assert_eq!(status, 200);
        assert!(
            body.contains(&format!("data-server-lang=\"{expected_lang}\"")),
            "expected {expected_lang} for Accept-Language: {accept}"
        );
        assert!(
            resp_head
                .to_lowercase()
                .contains(&format!("content-language: {expected_lang}")),
            "expected Content-Language: {expected_lang}"
        );
    }
    let _ = server.shutdown_tx.send(());

    // App-configured default_lang overrides Accept-Language.
    let server_ja = fm_server::start_http_share_with_lang(
        temp.path().to_path_buf(),
        None,
        None,
        true,
        Some("ja".into()),
    )
    .await
    .expect("start http share with default lang");
    let (_, head_ja, _) = get_request(server_ja.port, &with_token("/", &server_ja.share_token));
    let cookie_ja = head_ja
        .lines()
        .find(|l| l.to_ascii_lowercase().starts_with("set-cookie:"))
        .unwrap()
        .split_once(':')
        .unwrap()
        .1
        .trim()
        .split(';')
        .next()
        .unwrap()
        .trim()
        .to_string();
    let (_, _, body) = raw_request_with_headers(
        server_ja.port,
        "GET",
        "/",
        &[],
        None,
        &[("Cookie", &cookie_ja)],
    );
    assert!(body.contains("data-server-lang=\"ja\""));
    let _ = server_ja.shutdown_tx.send(());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn single_file_share_lists_and_downloads_only_that_file() {
    let temp = tempfile::tempdir().unwrap();
    let target = temp.path().join("report.txt");
    std::fs::write(&target, b"single file payload").unwrap();
    std::fs::write(temp.path().join("other.txt"), b"should not leak").unwrap();

    let server = fm_server::start_http_share(target, None, None, false)
        .await
        .expect("start single file share");

    let (status, _, list_body) =
        get_request(server.port, &with_token("/api/list", &server.share_token));
    assert_eq!(status, 200);
    assert!(list_body.contains("report.txt"));
    assert!(!list_body.contains("other.txt"));

    let (dl_status, _, dl_body) = get_request(
        server.port,
        &with_token("/download/report.txt", &server.share_token),
    );
    assert_eq!(dl_status, 200);
    assert_eq!(dl_body, "single file payload");

    let (other_status, _, _) = get_request(
        server.port,
        &with_token("/download/other.txt", &server.share_token),
    );
    assert_eq!(other_status, 404);

    let _ = server.shutdown_tx.send(());
}
