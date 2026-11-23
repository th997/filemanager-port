//! Axum-based HTTP local network sharing server with web UI and media streaming.

use axum::extract::{ConnectInfo, DefaultBodyLimit, Multipart, Path as AxumPath, Query, Request, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{Html, IntoResponse, Response};
use base64::Engine as _;
use axum::routing::{get, post};
use axum::{body::Body, Json, Router};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::fs::File;
use tokio::io::AsyncWriteExt;
use tokio::sync::oneshot;
use tokio_util::io::ReaderStream;

/// Cap for a single multipart upload request. The web UI uploads in
/// chunks, so without a cap a client can keep streaming until the disk
/// is full.
const MAX_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;

pub struct ServerState {
    pub root_dir: PathBuf,
    pub canonical_root: Option<PathBuf>,
    /// When `Some`, the server shares a single file rather than a directory.
    pub single_file_name: Option<String>,
    pub password: Option<String>,
    /// Random per-share bearer token used by the web UI. Deliberately NOT
    /// the password: a share link must never disclose the password itself.
    pub share_token: String,
    pub read_only: bool,
    /// Optional App-configured default language (`"en"`, `"zh"`, `"ja"`).
    pub default_lang: Option<String>,
    /// Failed auth attempts per client IP, for brute-force throttling.
    pub auth_failures: std::sync::Mutex<std::collections::HashMap<std::net::IpAddr, (u32, std::time::Instant)>>,
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

#[derive(Deserialize)]
pub struct UploadQuery {
    pub token: Option<String>,
    pub dir: Option<String>,
}

#[derive(Serialize)]
pub struct ConfigResponse {
    pub read_only: bool,
    pub lang: String,
    pub single_file: bool,
}

#[derive(Serialize)]
pub struct UploadResponse {
    pub success: bool,
    pub uploaded_files: usize,
    pub message: String,
}

pub struct RunningServer {
    pub port: u16,
    pub shutdown_tx: oneshot::Sender<()>,
    pub share_token: String,
}

pub async fn start_http_share(
    root_dir: PathBuf,
    preferred_port: Option<u16>,
    password: Option<String>,
    read_only: bool,
) -> Result<RunningServer, String> {
    start_http_share_with_lang(root_dir, preferred_port, password, read_only, None).await
}

pub async fn start_http_share_with_lang(
    root_dir: PathBuf,
    preferred_port: Option<u16>,
    password: Option<String>,
    read_only: bool,
    default_lang: Option<String>,
) -> Result<RunningServer, String> {
    let password = password
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty());
    let share_token = uuid::Uuid::new_v4().simple().to_string();
    let single_file_name = if root_dir.is_file() {
        root_dir
            .file_name()
            .and_then(|n| n.to_str())
            .map(|s| s.to_string())
    } else {
        None
    };
    let effective_read_only = read_only || single_file_name.is_some();
    let normalized_lang = default_lang.and_then(|l| normalize_lang_code(&l).map(|s| s.to_string()));

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
        single_file_name,
        password,
        share_token: share_token.clone(),
        read_only: effective_read_only,
        default_lang: normalized_lang,
        auth_failures: std::sync::Mutex::new(std::collections::HashMap::new()),
    });

    let app = Router::new()
        .route("/", get(handle_index))
        .route("/api/config", get(handle_config))
        .route("/api/upload", post(handle_upload))
        .route("/api/list", get(handle_list_root))
        .route("/api/list/", get(handle_list_root))
        .route("/api/list/{*subpath}", get(handle_list_sub))
        .route("/download/{*subpath}", get(handle_download))
        .layer(DefaultBodyLimit::max(MAX_UPLOAD_BYTES as usize))
        .layer(middleware::from_fn_with_state(state.clone(), require_auth))
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel();

    tokio::spawn(async move {
        let _ = axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
            .with_graceful_shutdown(async move {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    Ok(RunningServer {
        port: actual_port,
        shutdown_tx,
        share_token,
    })
}

fn check_auth(headers: &HeaderMap, query: &AuthQuery, state: &ServerState) -> bool {
    let check_eq = |candidate: &str, secret: &str| -> bool {
        if candidate.len() != secret.len() {
            return false;
        }
        let mut diff = 0u8;
        for (a, b) in candidate.as_bytes().iter().zip(secret.as_bytes()) {
            diff |= a ^ b;
        }
        diff == 0
    };

    // 1. The URL token is a random session token minted at startup.
    // Anyone accessing with the valid token is authenticated immediately.
    if let Some(token) = &query.token {
        if check_eq(token, &state.share_token) {
            return true;
        }
    }

    // 2. HTTP Basic / Bearer with password if password was configured
    if let Some(expected) = state.password.as_deref() {
        if let Some(auth_val) = headers.get(header::AUTHORIZATION) {
            if let Ok(auth_str) = auth_val.to_str() {
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
                            if check_eq(password, expected) {
                                return true;
                            }
                        }
                    }
                }

                let token = auth_str
                    .strip_prefix("Bearer ")
                    .or_else(|| auth_str.strip_prefix("bearer "))
                    .unwrap_or(auth_str);
                if check_eq(token, expected) {
                    return true;
                }
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
    request: Request,
    next: Next,
) -> Response {
    // Parse the token from the URI directly: a Query extractor would
    // consume the request body, which middleware must pass through.
    let mut query = AuthQuery { token: None };
    if let Some(q) = request.uri().query() {
        for pair in q.split('&') {
            let (k, v) = pair.split_once('=').unwrap_or((pair, ""));
            if k == "token" {
                query.token = Some(percent_decode_str(v));
            }
        }
    }
    // ConnectInfo is inserted by into_make_service_with_connect_info; read
    // it from the extensions so the middleware signature stays generic.
    let peer_ip = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ci| ci.0.ip())
        .unwrap_or_else(|| std::net::IpAddr::V4(std::net::Ipv4Addr::UNSPECIFIED));
    let now = std::time::Instant::now();
    let locked_out = {
        let failures = state.auth_failures.lock().unwrap_or_else(|e| e.into_inner());
        match failures.get(&peer_ip) {
            // Exponential backoff: 5+ failures lock the IP out for a window
            // that grows with the count, so 0.0.0.0 sharing is not a free
            // brute-force target.
            Some((count, last)) if *count >= 5 => {
                let window = std::time::Duration::from_secs(
                    5u64.saturating_mul(*count as u64).min(300),
                );
                now.duration_since(*last) < window
            }
            _ => false,
        }
    };
    if locked_out {
        return StatusCode::TOO_MANY_REQUESTS.into_response();
    }

    if check_auth(&headers, &query, &state) {
        {
            let mut failures = state.auth_failures.lock().unwrap_or_else(|e| e.into_inner());
            failures.remove(&peer_ip);
        }
        next.run(request).await
    } else {
        let mut failures = state.auth_failures.lock().unwrap_or_else(|e| e.into_inner());
        if failures.len() > 1024 {
            failures.retain(|_, (_, last)| now.duration_since(*last) < std::time::Duration::from_secs(3600));
        }
        let entry = failures.entry(peer_ip).or_insert((0, now));
        entry.0 = entry.0.saturating_add(1);
        entry.1 = now;
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

const INDEX_HTML_TEMPLATE: &str = include_str!("../assets/index.html");
const APP_CSS: &str = include_str!("../assets/app.css");
const APP_JS: &str = include_str!("../assets/app.js");
const I18N_EN_JSON: &str = include_str!("../assets/i18n/en.json");
const I18N_ZH_JSON: &str = include_str!("../assets/i18n/zh.json");
const I18N_JA_JSON: &str = include_str!("../assets/i18n/ja.json");

fn normalize_lang_code(raw: &str) -> Option<&'static str> {
    let lower = raw.trim().to_ascii_lowercase();
    if lower.starts_with("zh") {
        Some("zh")
    } else if lower.starts_with("ja") {
        Some("ja")
    } else if lower.starts_with("en") {
        Some("en")
    } else {
        None
    }
}

pub(crate) fn pick_language(default_lang: Option<&str>, headers: &HeaderMap) -> &'static str {
    if let Some(d) = default_lang.and_then(normalize_lang_code) {
        return d;
    }
    if let Some(val) = headers.get(header::ACCEPT_LANGUAGE).and_then(|v| v.to_str().ok()) {
        for part in val.split(',') {
            let tag = part.split(';').next().unwrap_or("");
            if let Some(code) = normalize_lang_code(tag) {
                return code;
            }
        }
    }
    "en"
}

fn rendered_index_html_for_lang(lang: &str) -> String {
    let html_lang = match lang {
        "zh" => "zh-CN",
        "ja" => "ja",
        _ => "en",
    };
    let i18n_bundle = format!(
        "{{\"en\":{I18N_EN_JSON},\"zh\":{I18N_ZH_JSON},\"ja\":{I18N_JA_JSON}}}"
    );
    INDEX_HTML_TEMPLATE
        .replace("__HTML_LANG__", html_lang)
        .replace("__SERVER_LANG__", lang)
        .replace("/*__APP_CSS__*/", APP_CSS)
        .replace("/*__I18N_JSON__*/", &i18n_bundle)
        .replace("/*__APP_JS__*/", APP_JS)
}

async fn handle_index(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> Response {
    let lang = pick_language(state.default_lang.as_deref(), &headers);
    let mut resp = Html(rendered_index_html_for_lang(lang)).into_response();
    if let Ok(val) = header::HeaderValue::from_str(lang) {
        resp.headers_mut().insert(header::CONTENT_LANGUAGE, val);
    }
    resp
}

async fn handle_config(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> Json<ConfigResponse> {
    let lang = pick_language(state.default_lang.as_deref(), &headers).to_string();
    Json(ConfigResponse {
        read_only: state.read_only,
        lang,
        single_file: state.single_file_name.is_some(),
    })
}

async fn handle_upload(
    headers: HeaderMap,
    Query(query): Query<UploadQuery>,
    State(state): State<Arc<ServerState>>,
    mut multipart: Multipart,
) -> Result<Json<UploadResponse>, (StatusCode, &'static str)> {
    let auth_query = AuthQuery {
        token: query.token.clone(),
    };
    if !check_auth(&headers, &auth_query, &state) {
        return Err((StatusCode::UNAUTHORIZED, "Unauthorized"));
    }

    if state.read_only {
        return Err((StatusCode::FORBIDDEN, "Server is read-only"));
    }

    let base_dir = query.dir.as_deref().unwrap_or("").trim_matches('/');
    let mut uploaded_count = 0;
    let mut total_written: u64 = 0;

    loop {
        // `while let Ok(Some(..))` used to treat a broken upload stream as a
        // normal end-of-file and report success with a truncated file.
        let mut field = match multipart.next_field().await {
            Ok(Some(field)) => field,
            Ok(None) => break,
            Err(_) => return Err((StatusCode::BAD_REQUEST, "Malformed multipart upload")),
        };
        let file_name = match field.file_name() {
            Some(name) if !name.trim().is_empty() => name.to_string(),
            _ => continue,
        };

        let normalized_file_path = file_name.replace('\\', "/");
        let combined_rel = if base_dir.is_empty() {
            normalized_file_path
        } else {
            format!("{base_dir}/{}", normalized_file_path.trim_start_matches('/'))
        };

        let target_path = resolve_path_inner(&state.root_dir, state.canonical_root.as_deref(), &combined_rel)
            .map_err(|_| (StatusCode::BAD_REQUEST, "Invalid file path"))?;

        let parent = target_path
            .parent()
            .ok_or((StatusCode::BAD_REQUEST, "Invalid file path"))?;
        let root_canon = state.canonical_root.as_deref().unwrap_or(&state.root_dir);
        // Verify containment against the deepest existing ancestor BEFORE
        // creating anything: create_dir_all follows symlinks, so creating
        // first could plant directories outside the shared root.
        let mut probe = parent.to_path_buf();
        loop {
            if std::fs::symlink_metadata(&probe).is_ok() {
                let resolved = probe.canonicalize().map_err(|_| {
                    (StatusCode::FORBIDDEN, "Cannot verify destination directory")
                })?;
                if !resolved.starts_with(root_canon) {
                    return Err((StatusCode::FORBIDDEN, "Path traverses outside root"));
                }
                break;
            }
            if !probe.pop() {
                return Err((StatusCode::FORBIDDEN, "Cannot verify destination directory"));
            }
        }
        if !parent.exists() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Failed to create directory"))?;
        }
        // Fail closed: if the parent cannot be canonicalised we cannot prove
        // that the upload still lands inside the shared root.
        let c_parent = parent.canonicalize().map_err(|_| {
            (StatusCode::FORBIDDEN, "Cannot verify destination directory")
        })?;
        if !c_parent.starts_with(root_canon) {
            return Err((StatusCode::FORBIDDEN, "Path traverses outside root"));
        }

        // Stream into a unique sibling temp file and rename only on success:
        // an interrupted upload must not leave a truncated file behind or
        // destroy a file that was already there.
        let base_name = target_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("upload");
        let tmp_path = parent.join(format!(
            ".{base_name}.fm-upload-{}",
            uuid::Uuid::new_v4().simple()
        ));

        let mut file = tokio::fs::File::create(&tmp_path)
            .await
            .map_err(|_| (StatusCode::INTERNAL_SERVER_ERROR, "Failed to create destination file"))?;

        let mut failure: Option<(StatusCode, &'static str)> = None;
        loop {
            match field.chunk().await {
                Ok(Some(chunk)) => {
                    total_written = total_written.saturating_add(chunk.len() as u64);
                    if total_written > MAX_UPLOAD_BYTES {
                        failure = Some((StatusCode::PAYLOAD_TOO_LARGE, "Upload exceeds size limit"));
                        break;
                    }
                    if file.write_all(&chunk).await.is_err() {
                        failure = Some((StatusCode::INTERNAL_SERVER_ERROR, "Failed to write file data"));
                        break;
                    }
                }
                Ok(None) => break,
                Err(_) => {
                    failure = Some((StatusCode::BAD_REQUEST, "Upload stream interrupted"));
                    break;
                }
            }
        }

        if failure.is_none() && file.flush().await.is_err() {
            failure = Some((StatusCode::INTERNAL_SERVER_ERROR, "Failed to flush file"));
        }
        drop(file);

        if let Some(err) = failure {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(err);
        }
        if tokio::fs::rename(&tmp_path, &target_path).await.is_err() {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err((StatusCode::INTERNAL_SERVER_ERROR, "Failed to finalize upload"));
        }

        uploaded_count += 1;
    }

    Ok(Json(UploadResponse {
        success: true,
        uploaded_files: uploaded_count,
        message: format!("Successfully uploaded {uploaded_count} file(s)"),
    }))
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

    if let Some(ref single_name) = state.single_file_name {
        if !subpath.is_empty() {
            return Err(StatusCode::NOT_FOUND);
        }
        let size = tokio::fs::metadata(&state.root_dir)
            .await
            .map(|m| m.len())
            .ok();
        return Ok(Json(vec![FileItem {
            name: single_name.clone(),
            path: single_name.clone(),
            is_dir: false,
            size,
        }]));
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

fn percent_decode_str(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'%' if i + 2 < bytes.len() => {
                let hi = (bytes[i + 1] as char).to_digit(16);
                let lo = (bytes[i + 2] as char).to_digit(16);
                match (hi, lo) {
                    (Some(h), Some(l)) => {
                        out.push((h * 16 + l) as u8);
                        i += 3;
                    }
                    _ => {
                        out.push(bytes[i]);
                        i += 1;
                    }
                }
            }
            b'+' => {
                out.push(b' ');
                i += 1;
            }
            b => {
                out.push(b);
                i += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
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

    let file_path = if let Some(ref single_name) = state.single_file_name {
        let trimmed = subpath.trim_start_matches('/');
        if trimmed == single_name.as_str() {
            state.root_dir.clone()
        } else {
            return Err(StatusCode::NOT_FOUND);
        }
    } else {
        resolve_path_inner(&state.root_dir, state.canonical_root.as_deref(), &subpath)
            .map_err(|_| StatusCode::FORBIDDEN)?
    };
    let file = File::open(&file_path).await.map_err(|_| StatusCode::NOT_FOUND)?;
    let metadata = file.metadata().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if metadata.is_dir() {
        return Err(StatusCode::BAD_REQUEST);
    }
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

    // Honour Range so browsers can seek in shared media and resume
    // interrupted downloads; the stream path already does this.
    let (offset, length, status) = match crate::stream::parse_range(
        headers.get(header::RANGE),
        Some(total_size),
    ) {
        crate::stream::RangeSpec::None => (0u64, None, StatusCode::OK),
        crate::stream::RangeSpec::Satisfiable { offset, length } => {
            (offset, Some(length), StatusCode::PARTIAL_CONTENT)
        }
        crate::stream::RangeSpec::Unsatisfiable => {
            let mut response = StatusCode::RANGE_NOT_SATISFIABLE.into_response();
            if let Ok(value) = header::HeaderValue::from_str(&format!("bytes */{total_size}")) {
                response.headers_mut().insert(header::CONTENT_RANGE, value);
            }
            return Ok(response);
        }
    };

    let reader: Box<dyn tokio::io::AsyncRead + Send + Unpin> = if offset > 0 || length.is_some() {
        let mut f = file;
        use tokio::io::AsyncSeekExt;
        f.seek(std::io::SeekFrom::Start(offset))
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        match length {
            Some(len) => Box::new(tokio::io::AsyncReadExt::take(f, len)),
            None => Box::new(f),
        }
    } else {
        Box::new(file)
    };

    let body = Body::from_stream(ReaderStream::with_capacity(reader, 64 * 1024));

    let mut builder = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(header::CONTENT_DISPOSITION, disposition)
        .header(header::ACCEPT_RANGES, "bytes");
    builder = match length {
        Some(len) => builder
            .header(header::CONTENT_LENGTH, len.to_string())
            .header(
                header::CONTENT_RANGE,
                format!("bytes {}-{}/{}", offset, offset + len - 1, total_size),
            ),
        None => builder.header(header::CONTENT_LENGTH, total_size.to_string()),
    };

    let response = builder
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
    match target.canonicalize() {
        Ok(c_target) => {
            let c_root = canonical_root
                .map(Path::to_path_buf)
                .or_else(|| root.canonicalize().ok());
            match c_root {
                Some(c_root) if !c_target.starts_with(&c_root) => return Err(()),
                Some(_) => {}
                // We cannot resolve the root: refuse instead of assuming
                // that the target is contained in it.
                None => return Err(()),
            }
        }
        Err(_) => {
            // A file that does not exist yet has no canonical path; the
            // caller must verify its parent directory. An entry that exists
            // but cannot be resolved (dangling symlink, permission error)
            // is untrusted and refused.
            if std::fs::symlink_metadata(&target).is_ok() {
                return Err(());
            }
        }
    }
    Ok(target)
}

pub fn get_lan_ip_addresses() -> Vec<String> {
    let mut ips = Vec::new();

    // 1. On Linux, check default gateway from /proc/net/route to avoid being hijacked by TUN/VPN fake-ip (e.g. Clash Meta 198.18.x.x)
    #[cfg(target_os = "linux")]
    {
        if let Ok(content) = std::fs::read_to_string("/proc/net/route") {
            for line in content.lines() {
                let fields: Vec<&str> = line.split_whitespace().collect();
                if fields.len() >= 3 && fields[1] == "00000000" {
                    if let Ok(hex_val) = u32::from_str_radix(fields[2], 16) {
                        if hex_val != 0 {
                            let ip_bytes = hex_val.to_le_bytes();
                            let gw_ip = std::net::Ipv4Addr::from(ip_bytes);
                            if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
                                if socket.connect((gw_ip, 80)).is_ok() {
                                    if let Ok(local_addr) = socket.local_addr() {
                                        let ip = local_addr.ip().to_string();
                                        if ip != "0.0.0.0" && ip != "127.0.0.1" && !ip.starts_with("198.18.") && !ips.contains(&ip) {
                                            ips.push(ip);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 2. Standard UDP route probe, filtering out loopback and CGNAT/TUN fake IPs (198.18.x.x / 198.19.x.x)
    if let Ok(interfaces) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if interfaces.connect("8.8.8.8:80").is_ok() {
            if let Ok(local_addr) = interfaces.local_addr() {
                let ip = local_addr.ip().to_string();
                if ip != "0.0.0.0" && ip != "127.0.0.1" && !ip.starts_with("198.18.") && !ip.starts_with("198.19.") && !ips.contains(&ip) {
                    ips.push(ip);
                }
            }
        }
    }

    // 3. Fallback probes for common LAN gateways if empty
    if ips.is_empty() {
        for target in ["192.168.1.1:80", "192.168.0.1:80", "10.0.0.1:80", "172.16.0.1:80"] {
            if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
                if socket.connect(target).is_ok() {
                    if let Ok(local_addr) = socket.local_addr() {
                        let ip = local_addr.ip().to_string();
                        if ip != "0.0.0.0" && ip != "127.0.0.1" && !ip.starts_with("198.18.") && !ips.contains(&ip) {
                            ips.push(ip);
                        }
                    }
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

    fn auth_state(password: Option<&str>, token: &str) -> ServerState {
        ServerState {
            root_dir: PathBuf::from("/tmp"),
            canonical_root: None,
            single_file_name: None,
            password: password.map(str::to_string),
            share_token: token.to_string(),
            read_only: true,
            default_lang: None,
            auth_failures: std::sync::Mutex::new(std::collections::HashMap::new()),
        }
    }

    #[test]
    fn empty_password_never_grants_anonymous_access() {
        for state in [auth_state(None, "random-token"), auth_state(Some(""), "random-token")] {
            let headers = HeaderMap::new();
            assert!(!check_auth(&headers, &AuthQuery { token: None }, &state));
            assert!(!check_auth(
                &headers,
                &AuthQuery { token: Some("anything".into()) },
                &state
            ));
        }
    }

    #[test]
    fn url_token_is_session_token_not_password() {
        let state = auth_state(Some("hunter2"), "session-abc");
        let headers = HeaderMap::new();
        assert!(check_auth(
            &headers,
            &AuthQuery { token: Some("session-abc".into()) },
            &state
        ));
        // Passing the password in the URL must not authenticate: otherwise
        // a shared link would leak the password into history/Referer/logs.
        assert!(!check_auth(
            &headers,
            &AuthQuery { token: Some("hunter2".into()) },
            &state
        ));
        assert!(!check_auth(
            &headers,
            &AuthQuery { token: Some("wrong".into()) },
            &state
        ));
    }

    #[test]
    fn basic_auth_still_uses_the_password() {
        let state = auth_state(Some("hunter2"), "session-abc");
        let mut headers = HeaderMap::new();
        let encoded = base64::engine::general_purpose::STANDARD.encode("anyuser:hunter2");
        headers.insert(
            header::AUTHORIZATION,
            format!("Basic {encoded}").parse().unwrap(),
        );
        assert!(check_auth(&headers, &AuthQuery { token: None }, &state));
        headers.insert(
            header::AUTHORIZATION,
            "Bearer session-abc".parse().unwrap(),
        );
        assert!(!check_auth(&headers, &AuthQuery { token: None }, &state));
    }
}
