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
    pub canonical_root: Option<PathBuf>,
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

    let canonical_root = root_dir.canonicalize().ok();
    let state = Arc::new(ServerState {
        root_dir,
        canonical_root,
        password,
        read_only,
    });

    let app = Router::new()
        .route("/", get(handle_index))
        .route("/api/list", get(handle_list_root))
        .route("/api/list/", get(handle_list_root))
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
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>文件共享 - LAN File Sharing</title>
    <style>
        :root {
            --bg-page: #f8fafc;
            --bg-card: #ffffff;
            --border-color: #e2e8f0;
            --text-main: #0f172a;
            --text-sub: #64748b;
            --primary: #2563eb;
            --primary-hover: #1d4ed8;
            --item-hover: #f1f5f9;
            --badge-bg: #e0e7ff;
            --badge-text: #3730a3;
        }
        @media (prefers-color-scheme: dark) {
            :root {
                --bg-page: #0f172a;
                --bg-card: #1e293b;
                --border-color: #334155;
                --text-main: #f8fafc;
                --text-sub: #94a3b8;
                --primary: #3b82f6;
                --primary-hover: #60a5fa;
                --item-hover: #293548;
                --badge-bg: #1e3a8a;
                --badge-text: #bfdbfe;
            }
        }
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            margin: 0;
            padding: 24px 16px;
            background: var(--bg-page);
            color: var(--text-main);
            transition: background-color 0.2s ease;
        }
        .container {
            max-width: 960px;
            margin: 0 auto;
            background: var(--bg-card);
            border-radius: 14px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.06);
            border: 1px solid var(--border-color);
            padding: 24px 28px;
        }
        header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 20px;
            flex-wrap: wrap;
            gap: 12px;
        }
        h1 {
            margin: 0;
            font-size: 22px;
            font-weight: 700;
            display: flex;
            align-items: center;
            gap: 8px;
            color: var(--text-main);
        }
        .search-box {
            position: relative;
            flex-grow: 1;
            max-width: 320px;
            min-width: 200px;
        }
        .search-input {
            width: 100%;
            padding: 8px 12px 8px 32px;
            border-radius: 8px;
            border: 1px solid var(--border-color);
            background: var(--bg-page);
            color: var(--text-main);
            font-size: 14px;
            outline: none;
            transition: border-color 0.2s;
        }
        .search-input:focus {
            border-color: var(--primary);
        }
        .search-icon {
            position: absolute;
            left: 10px;
            top: 50%;
            transform: translateY(-50%);
            color: var(--text-sub);
            font-size: 13px;
        }
        .breadcrumb {
            display: flex;
            align-items: center;
            flex-wrap: wrap;
            gap: 6px;
            padding: 10px 14px;
            background: var(--bg-page);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            font-size: 14px;
            margin-bottom: 16px;
        }
        .breadcrumb-item {
            color: var(--primary);
            text-decoration: none;
            cursor: pointer;
            font-weight: 500;
        }
        .breadcrumb-item:hover {
            text-decoration: underline;
        }
        .breadcrumb-sep {
            color: var(--text-sub);
            font-size: 12px;
        }
        .breadcrumb-current {
            color: var(--text-sub);
            font-weight: 600;
        }
        ul.file-list {
            list-style: none;
            padding: 0;
            margin: 0;
            border: 1px solid var(--border-color);
            border-radius: 8px;
            overflow: hidden;
        }
        li.file-item {
            padding: 12px 16px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            border-bottom: 1px solid var(--border-color);
            transition: background 0.15s ease;
            gap: 12px;
        }
        li.file-item:last-child {
            border-bottom: none;
        }
        li.file-item:hover {
            background: var(--item-hover);
        }
        .item-main {
            display: flex;
            align-items: center;
            gap: 10px;
            flex: 1;
            min-width: 0;
            text-decoration: none;
            color: var(--text-main);
            cursor: pointer;
        }
        .item-main:hover .item-name {
            color: var(--primary);
        }
        .item-icon {
            font-size: 18px;
            flex-shrink: 0;
        }
        .item-name {
            font-size: 14px;
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            transition: color 0.15s;
        }
        .item-actions {
            display: flex;
            align-items: center;
            gap: 12px;
            flex-shrink: 0;
        }
        .item-size {
            font-size: 13px;
            color: var(--text-sub);
            font-variant-numeric: tabular-nums;
            min-width: 70px;
            text-align: right;
        }
        .btn-download {
            padding: 4px 10px;
            border-radius: 6px;
            background: var(--primary);
            color: #ffffff;
            font-size: 12px;
            font-weight: 500;
            text-decoration: none;
            transition: background 0.15s;
            display: inline-flex;
            align-items: center;
            gap: 4px;
        }
        .btn-download:hover {
            background: var(--primary-hover);
        }
        .empty-state {
            padding: 36px 16px;
            text-align: center;
            color: var(--text-sub);
            font-size: 14px;
        }
        .footer-info {
            margin-top: 16px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-size: 12px;
            color: var(--text-sub);
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📁 局域网文件共享</h1>
            <div class="search-box">
                <span class="search-icon">🔍</span>
                <input type="text" id="filter-input" class="search-input" placeholder="筛选当前目录文件..." />
            </div>
        </header>

        <div class="breadcrumb" id="breadcrumb-bar">
            <span class="breadcrumb-item" data-path="">根目录</span>
        </div>

        <ul class="file-list" id="file-list">
            <li class="empty-state">正在加载文件列表...</li>
        </ul>

        <div class="footer-info">
            <span id="item-count-text">0 项内容</span>
            <span>FileManager LAN Share</span>
        </div>
    </div>

    <script>
        let currentPath = '';
        let allItems = [];

        function escapeHtml(str) {
            return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }

        function formatSize(bytes) {
            if (bytes == null || bytes === undefined) return '-';
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
            if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
            return (bytes / 1073741824).toFixed(2) + ' GB';
        }

        function getFileIcon(name, isDir) {
            if (isDir) return '📁';
            const ext = (name.split('.').pop() || '').toLowerCase();
            if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(ext)) return '🖼️';
            if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv'].includes(ext)) return '🎬';
            if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].includes(ext)) return '🎵';
            if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].includes(ext)) return '📦';
            if (['html', 'htm', 'js', 'css', 'json', 'xml', 'rs', 'dart', 'py', 'c', 'cpp', 'java', 'ts'].includes(ext)) return '💻';
            if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md'].includes(ext)) return '📄';
            return '📄';
        }

        function buildListUrl(path) {
            const clean = (path || '').replace(/^\/+|\/+$/g, '');
            if (!clean) return '/api/list';
            return '/api/list/' + clean.split('/').map(encodeURIComponent).join('/');
        }

        function buildDownloadUrl(path) {
            const clean = (path || '').replace(/^\/+|\/+$/g, '');
            return '/download/' + clean.split('/').map(encodeURIComponent).join('/');
        }

        function renderBreadcrumbs(path) {
            const bar = document.getElementById('breadcrumb-bar');
            const clean = (path || '').replace(/^\/+|\/+$/g, '');
            let html = '<span class="breadcrumb-item" data-path="">根目录</span>';
            if (clean) {
                const parts = clean.split('/');
                let accum = '';
                for (let i = 0; i < parts.length; i++) {
                    accum = accum ? (accum + '/' + parts[i]) : parts[i];
                    html += '<span class="breadcrumb-sep">/</span>';
                    if (i === parts.length - 1) {
                        html += `<span class="breadcrumb-current">${escapeHtml(parts[i])}</span>`;
                    } else {
                        html += `<span class="breadcrumb-item" data-path="${escapeHtml(accum)}">${escapeHtml(parts[i])}</span>`;
                    }
                }
            }
            bar.innerHTML = html;
        }

        function renderItems(filterText) {
            const listEl = document.getElementById('file-list');
            const query = (filterText || '').trim().toLowerCase();
            const filtered = query
                ? allItems.filter(item => item.name.toLowerCase().includes(query))
                : allItems;

            document.getElementById('item-count-text').innerText = `${filtered.length} 项内容`;

            if (filtered.length === 0) {
                listEl.innerHTML = query
                    ? '<li class="empty-state">没有找到匹配的文件</li>'
                    : '<li class="empty-state">文件夹为空</li>';
                return;
            }

            let html = '';
            for (const item of filtered) {
                const icon = getFileIcon(item.name, item.is_dir);
                const safeName = escapeHtml(item.name);
                const safePath = escapeHtml(item.path);

                if (item.is_dir) {
                    html += `
                        <li class="file-item">
                            <div class="item-main folder-link" data-path="${safePath}">
                                <span class="item-icon">${icon}</span>
                                <span class="item-name">${safeName}</span>
                            </div>
                            <div class="item-actions">
                                <span class="item-size">文件夹</span>
                            </div>
                        </li>
                    `;
                } else {
                    const dlUrl = buildDownloadUrl(item.path);
                    const sizeStr = formatSize(item.size);
                    html += `
                        <li class="file-item">
                            <a class="item-main" href="${dlUrl}" target="_blank">
                                <span class="item-icon">${icon}</span>
                                <span class="item-name">${safeName}</span>
                            </a>
                            <div class="item-actions">
                                <span class="item-size">${sizeStr}</span>
                                <a class="btn-download" href="${dlUrl}" download="${safeName}">下载</a>
                            </div>
                        </li>
                    `;
                }
            }
            listEl.innerHTML = html;
        }

        async function loadDir(path) {
            currentPath = (path || '').replace(/^\/+|\/+$/g, '');
            renderBreadcrumbs(currentPath);
            document.getElementById('file-list').innerHTML = '<li class="empty-state">正在加载文件列表...</li>';

            try {
                const res = await fetch(buildListUrl(currentPath));
                if (!res.ok) {
                    document.getElementById('file-list').innerHTML = '<li class="empty-state" style="color:#ef4444;">加载目录失败（HTTP ' + res.status + '）</li>';
                    return;
                }
                allItems = await res.json();
                document.getElementById('filter-input').value = '';
                renderItems('');
            } catch (err) {
                document.getElementById('file-list').innerHTML = '<li class="empty-state" style="color:#ef4444;">网络请求出错：' + escapeHtml(err.message) + '</li>';
            }
        }

        document.getElementById('breadcrumb-bar').addEventListener('click', (e) => {
            const target = e.target.closest('.breadcrumb-item');
            if (target) {
                loadDir(target.getAttribute('data-path') || '');
            }
        });

        document.getElementById('file-list').addEventListener('click', (e) => {
            const folderLink = e.target.closest('.folder-link');
            if (folderLink) {
                e.preventDefault();
                loadDir(folderLink.getAttribute('data-path') || '');
            }
        });

        document.getElementById('filter-input').addEventListener('input', (e) => {
            renderItems(e.target.value);
        });

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

    let target_dir = resolve_path_inner(&state.root_dir, state.canonical_root.as_deref(), subpath)
        .map_err(|_| StatusCode::FORBIDDEN)?;
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

    items.sort_unstable_by(|a, b| {
        b.is_dir.cmp(&a.is_dir).then_with(|| a.name.cmp(&b.name))
    });

    Ok(Json(items))
}

fn percent_encode(s: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let bytes = s.as_bytes();
    let mut out = String::with_capacity(bytes.len() + 8);
    for &b in bytes {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push('%');
            out.push(HEX[(b >> 4) as usize] as char);
            out.push(HEX[(b & 0x0F) as usize] as char);
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

    let file_path = resolve_path_inner(&state.root_dir, state.canonical_root.as_deref(), &subpath)
        .map_err(|_| StatusCode::FORBIDDEN)?;
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

#[cfg(test)]
fn resolve_path(root: &Path, rel: &str) -> Result<PathBuf, ()> {
    resolve_path_inner(root, None, rel)
}

fn resolve_path_inner(root: &Path, canonical_root: Option<&Path>, rel: &str) -> Result<PathBuf, ()> {
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
    if let Ok(c_target) = target.canonicalize() {
        if let Some(c_root) = canonical_root {
            if !c_target.starts_with(c_root) {
                return Err(());
            }
        } else if let Ok(c_root) = root.canonicalize() {
            if !c_target.starts_with(&c_root) {
                return Err(());
            }
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
