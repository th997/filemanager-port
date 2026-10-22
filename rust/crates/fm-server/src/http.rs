//! Axum-based HTTP local network sharing server with web UI and media streaming.

use axum::extract::{Path as AxumPath, Query, Request, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{Html, Response};
use base64::Engine as _;
use axum::routing::get;
use axum::{body::Body, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::fs::File;
use tokio::sync::oneshot;
use tokio_util::io::ReaderStream;

pub struct ServerState {
    pub root_dir: PathBuf,
    pub password: Option<String>,
    pub read_only: bool,
}

#[derive(Serialize)]
pub struct FileItem {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: Option<u64>,
}

#[derive(Deserialize)]
pub struct AuthQuery {
    pub token: Option<String>,
}

pub struct RunningServer {
    pub port: u16,
    pub shutdown_tx: oneshot::Sender<()>,
}

pub async fn start_http_share(
    root_dir: PathBuf,
    preferred_port: Option<u16>,
    password: Option<String>,
    read_only: bool,
) -> Result<RunningServer, String> {
    let port = preferred_port.unwrap_or(0);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| format!("failed to bind port {port}: {e}"))?;

    let actual_port = listener
        .local_addr()
        .map_err(|e| e.to_string())?
        .port();

    let state = Arc::new(ServerState {
        root_dir,
        password,
        read_only,
    });

    let app = Router::new()
        .route("/", get(handle_index))
        .route("/api/list", get(handle_list_root))
        .route("/api/list/{*subpath}", get(handle_list_sub))
        .route("/download/{*subpath}", get(handle_download))
        .layer(middleware::from_fn_with_state(state.clone(), require_auth))
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel();

    tokio::spawn(async move {
        let _ = axum::serve(listener, app)
            .with_graceful_shutdown(async move {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    Ok(RunningServer {
        port: actual_port,
        shutdown_tx,
    })
}

fn check_auth(headers: &HeaderMap, query: &AuthQuery, state: &ServerState) -> bool {
    let expected = match &state.password {
        Some(p) if !p.is_empty() => p,
        _ => return true,
    };

    let check_eq = |token: &str| -> bool {
        if token.len() != expected.len() {
            return false;
        }
        let mut diff = 0u8;
        for (a, b) in token.as_bytes().iter().zip(expected.as_bytes()) {
            diff |= a ^ b;
        }
        diff == 0
    };

    if let Some(token) = &query.token {
        if check_eq(token) {
            return true;
        }
    }

    if let Some(auth_val) = headers.get(header::AUTHORIZATION) {
        if let Ok(auth_str) = auth_val.to_str() {
            // HTTP Basic: base64("user:password"). The share has no
            // username concept, so only the part after the first ':' is
            // checked. Browsers send this automatically once the user has
            // answered the 401 challenge, which is what makes the web UI
            // usable with a password set.
            if let Some(basic) = auth_str
                .strip_prefix("Basic ")
                .or_else(|| auth_str.strip_prefix("basic "))
            {
                if let Ok(decoded) =
                    base64::engine::general_purpose::STANDARD.decode(basic.trim())
                {
                    if let Ok(credentials) = std::str::from_utf8(&decoded) {
                        let password = credentials
                            .split_once(':')
                            .map(|(_, p)| p)
                            .unwrap_or(credentials);
                        if check_eq(password) {
                            return true;
                        }
                    }
                }
            }

            let token = auth_str
                .strip_prefix("Bearer ")
                .or_else(|| auth_str.strip_prefix("bearer "))
                .unwrap_or(auth_str);
            if check_eq(token) {
                return true;
            }
        }
    }

    false
}

/// Gate every route (including the index page, which used to be served
/// without any check) behind `check_auth`, answering failures with a
/// `WWW-Authenticate` challenge so browsers prompt for the share password
/// and then resend it as Basic credentials on the page's own requests.
async fn require_auth(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
    Query(query): Query<AuthQuery>,
    request: Request,
    next: Next,
) -> Response {
    if check_auth(&headers, &query, &state) {
        next.run(request).await
    } else {
        unauthorized_response()
    }
}

fn unauthorized_response() -> Response {
    let mut response = Response::new(Body::from("unauthorized"));
    *response.status_mut() = StatusCode::UNAUTHORIZED;
    response.headers_mut().insert(
        header::WWW_AUTHENTICATE,
        header::HeaderValue::from_static("Basic realm=\"fm-share\""),
    );
    response
}

async fn handle_index() -> Html<&'static str> {
    Html(r###"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>LAN File Sharing</title>
    <style>
        body { font-family: system-ui, -apple-system, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); padding: 24px; }
        h1 { margin-top: 0; color: #1976D2; font-size: 24px; }
        ul { list-style: none; padding: 0; margin: 0; }
        li { padding: 12px; border-bottom: 1px solid #eee; display: flex; align-items: center; justify-content: space-between; }
        li:hover { background: #fafafa; }
        a { text-decoration: none; color: #333; font-weight: 500; }
        a:hover { color: #1976D2; }
        .size { color: #888; font-size: 13px; }
        .folder { color: #f57c00; margin-right: 8px; }
        .file { color: #1976D2; margin-right: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>📁 LAN File Sharing</h1>
        <div id="path-bar" style="margin-bottom: 16px; color: #666; font-size: 14px;">/</div>
        <ul id="file-list">Loading...</ul>
    </div>
    <script>
        let currentPath = '';
        function escapeHtml(str) {
            return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }
        async function loadDir(path) {
            currentPath = path;
            document.getElementById('path-bar').innerText = '/' + path;
            const res = await fetch('/api/list/' + encodeURI(path));
            if (!res.ok) { document.getElementById('file-list').innerHTML = '<li>Error loading directory</li>'; return; }
            const items = await res.json();
            let html = '';
            if (path) {
                const parts = path.split('/').filter(Boolean);
                parts.pop();
                const parent = parts.join('/');
                const parentEsc = encodeURIComponent(parent);
                html += `<li><a href="#" onclick="loadDir(decodeURIComponent('${parentEsc}'))">⬅️ [.. Back]</a><span></span></li>`;
            }
            for (const item of items) {
                const safeName = escapeHtml(item.name);
                const encodedPath = encodeURIComponent(item.path);
                if (item.is_dir) {
                    html += `<li><a href="#" onclick="loadDir(decodeURIComponent('${encodedPath}'))"><span class="folder">📁</span>${safeName}</a><span class="size">Folder</span></li>`;
                } else {
                    const sizeStr = item.size ? (item.size > 1048576 ? (item.size/1048576).toFixed(1) + ' MB' : (item.size/1024).toFixed(1) + ' KB') : '-';
                    html += `<li><a href="/download/${encodeURI(item.path)}" target="_blank"><span class="file">📄</span>${safeName}</a><span class="size">${sizeStr}</span></li>`;
                }
            }
            document.getElementById('file-list').innerHTML = html || '<li>(Empty folder)</li>';
        }
        loadDir('');
    </script>
</body>
</html>"###)
}

async fn handle_list_root(
    headers: HeaderMap,
    Query(query): Query<AuthQuery>,
    State(state): State<Arc<ServerState>>,
) -> Result<Json<Vec<FileItem>>, StatusCode> {
    handle_list_internal(headers, query, state, "").await
}

async fn handle_list_sub(
    headers: HeaderMap,
    Query(query): Query<AuthQuery>,
    State(state): State<Arc<ServerState>>,
    AxumPath(subpath): AxumPath<String>,
) -> Result<Json<Vec<FileItem>>, StatusCode> {
    handle_list_internal(headers, query, state, &subpath).await
}

async fn handle_list_internal(
    headers: HeaderMap,
    query: AuthQuery,
    state: Arc<ServerState>,
    subpath: &str,
) -> Result<Json<Vec<FileItem>>, StatusCode> {
    if !check_auth(&headers, &query, &state) {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let target_dir = resolve_path(&state.root_dir, subpath).map_err(|_| StatusCode::FORBIDDEN)?;
    let mut reader = tokio::fs::read_dir(target_dir)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    let mut items = Vec::new();
    while let Ok(Some(entry)) = reader.next_entry().await {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') {
            continue;
        }
        let is_dir = entry.file_type().await.map(|t| t.is_dir()).unwrap_or(false);
        let size = if is_dir {
            None
        } else {
            entry.metadata().await.map(|m| m.len()).ok()
        };

        let child_path = if subpath.is_empty() {
            name.clone()
        } else {
            format!("{subpath}/{name}")
        };

        items.push(FileItem {
            name,
            path: child_path,
            is_dir,
            size,
        });
    }

    items.sort_by(|a, b| {
        b.is_dir.cmp(&a.is_dir).then_with(|| a.name.cmp(&b.name))
    });

    Ok(Json(items))
}

fn percent_encode(s: &str) -> String {
    let mut out = String::with_capacity(s.len() * 3);
    for b in s.as_bytes() {
        if b.is_ascii_alphanumeric() || matches!(*b, b'-' | b'_' | b'.' | b'~') {
            out.push(*b as char);
        } else {
            use std::fmt::Write;
            let _ = write!(out, "%{:02X}", b);
        }
    }
    out
}

async fn handle_download(
    headers: HeaderMap,
    Query(query): Query<AuthQuery>,
    State(state): State<Arc<ServerState>>,
    AxumPath(subpath): AxumPath<String>,
) -> Result<Response, StatusCode> {
    if !check_auth(&headers, &query, &state) {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let file_path = resolve_path(&state.root_dir, &subpath).map_err(|_| StatusCode::FORBIDDEN)?;
    let file = File::open(&file_path).await.map_err(|_| StatusCode::NOT_FOUND)?;
    let metadata = file.metadata().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let total_size = metadata.len();

    let file_name = file_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");

    let safe_ascii: String = file_name
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' { c } else { '_' })
        .collect();
    let encoded_name = percent_encode(file_name);
    let disposition = format!("attachment; filename=\"{safe_ascii}\"; filename*=UTF-8''{encoded_name}");

    let stream = ReaderStream::with_capacity(file, 64 * 1024);
    let body = Body::from_stream(stream);

    let response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_DISPOSITION, disposition)
        .header(header::CONTENT_LENGTH, total_size.to_string())
        .body(body)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(response)
}

fn resolve_path(root: &Path, rel: &str) -> Result<PathBuf, ()> {
    let mut target = root.to_path_buf();
    for seg in rel.split('/') {
        if seg.is_empty() || seg == "." {
            continue;
        }
        if seg == ".." || seg.contains('\\') || seg.contains(':') || seg.contains('\0') {
            return Err(());
        }
        target.push(seg);
    }
    if let (Ok(c_root), Ok(c_target)) = (root.canonicalize(), target.canonicalize()) {
        if !c_target.starts_with(&c_root) {
            return Err(());
        }
    }
    Ok(target)
}

pub fn get_lan_ip_addresses() -> Vec<String> {
    let mut ips = Vec::new();
    if let Ok(interfaces) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if interfaces.connect("8.8.8.8:80").is_ok() {
            if let Ok(local_addr) = interfaces.local_addr() {
                let ip = local_addr.ip().to_string();
                if ip != "0.0.0.0" && ip != "127.0.0.1" {
                    ips.push(ip);
                }
            }
        }
    }
    if ips.is_empty() {
        ips.push("127.0.0.1".to_string());
    }
    ips
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_percent_encode() {
        assert_eq!(percent_encode("hello world.txt"), "hello%20world.txt");
        assert_eq!(percent_encode("文档.pdf"), "%E6%96%87%E6%A1%A3.pdf");
    }

    #[test]
    fn test_resolve_path_traversal() {
        let root = Path::new("/tmp");
        assert!(resolve_path(root, "foo/bar.txt").is_ok());
        assert!(resolve_path(root, "../etc/passwd").is_err());
        assert!(resolve_path(root, "..\\etc\\passwd").is_err());
        assert!(resolve_path(root, "foo/../../etc/passwd").is_err());
        assert!(resolve_path(root, "C:\\Windows\\win.ini").is_err());
        assert!(resolve_path(root, "foo\0bar").is_err());
    }
}
