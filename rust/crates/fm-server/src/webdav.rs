//! LAN WebDAV server exposing any [`fm_vfs::Vfs`] backend over HTTP.
//!
//! Supports `OPTIONS`, `PROPFIND` (Depth 0/1), `GET`/`HEAD` (with HTTP `Range`),
//! `PUT`, `MKCOL`, `DELETE`, `MOVE`, and `COPY`, with optional HTTP Basic Auth and
//! read-only mode so Infuse, Kodi, macOS Finder, Windows Explorer, and Linux
//! desktop clients can mount local folders, remote buckets, or unlocked vaults.

use std::collections::HashSet;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::SystemTime;

use axum::body::Body;
use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Router;
use base64::Engine as _;
use chrono::{DateTime, Utc};
use fm_core::{Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError};
use futures_util::StreamExt;
use tokio::io::AsyncWriteExt;
use tokio::sync::oneshot;
use tokio_util::io::ReaderStream;

#[cfg(target_pointer_width = "64")]
const MAX_PUT_BYTES: usize = 8 * 1024 * 1024 * 1024;
#[cfg(not(target_pointer_width = "64"))]
const MAX_PUT_BYTES: usize = usize::MAX;

#[derive(Clone)]
struct WebDavState {
    vfs: Arc<dyn Vfs>,
    base_prefix: VfsPath,
    read_only: bool,
    username: Option<String>,
    password: Option<String>,
}

pub struct RunningWebDavServer {
    pub port: u16,
    pub shutdown_tx: oneshot::Sender<()>,
}

/// Starts a WebDAV server exposing `vfs` at `base_prefix` on all LAN interfaces.
pub async fn start_webdav_server(
    vfs: Arc<dyn Vfs>,
    base_prefix: VfsPath,
    port: Option<u16>,
    username: Option<String>,
    password: Option<String>,
    read_only: bool,
) -> Result<RunningWebDavServer, String> {
    let username = username.map(|s| s.trim().to_string()).filter(|s| !s.is_empty());
    let password = password.filter(|s| !s.is_empty());
    if username.is_some() && password.is_none() {
        return Err("WebDAV username requires a non-empty password".to_string());
    }

    let bind_port = port.unwrap_or(0);
    let addr: SocketAddr = format!("0.0.0.0:{bind_port}")
        .parse()
        .map_err(|e| format!("invalid bind address: {e}"))?;
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| format!("failed to bind WebDAV port: {e}"))?;
    let actual_port = listener
        .local_addr()
        .map_err(|e| format!("failed to query WebDAV local addr: {e}"))?
        .port();

    let state = WebDavState {
        vfs,
        base_prefix,
        read_only,
        username,
        password,
    };

    let app = Router::new()
        .fallback(handle_webdav)
        .layer(DefaultBodyLimit::max(MAX_PUT_BYTES))
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    tokio::spawn(async move {
        let _ = axum::serve(listener, app)
            .with_graceful_shutdown(async {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    Ok(RunningWebDavServer {
        port: actual_port,
        shutdown_tx,
    })
}

fn ct_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    let len = a.len().max(b.len());
    let mut diff: u8 = if a.len() == b.len() { 0 } else { 1 };
    for i in 0..len {
        let ab = *a.get(i).unwrap_or(&0);
        let bb = *b.get(i).unwrap_or(&0);
        diff |= ab ^ bb;
    }
    diff == 0
}

fn check_basic_auth(state: &WebDavState, headers: &HeaderMap) -> bool {
    let (Some(expected_user), Some(expected_pass)) = (&state.username, &state.password) else {
        if let Some(expected_pass) = &state.password {
            // Password-only configuration accepts any username with matching password.
            return parse_basic_auth(headers)
                .map(|(_, p)| ct_eq(&p, expected_pass))
                .unwrap_or(false);
        }
        return true;
    };
    parse_basic_auth(headers)
        .map(|(u, p)| ct_eq(&u, expected_user) && ct_eq(&p, expected_pass))
        .unwrap_or(false)
}

fn parse_basic_auth(headers: &HeaderMap) -> Option<(String, String)> {
    let val = headers.get(header::AUTHORIZATION)?.to_str().ok()?.trim();
    if val.len() < 6 || !val[..6].eq_ignore_ascii_case("Basic ") {
        return None;
    }
    let encoded = val[6..].trim();
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .ok()?;
    let s = String::from_utf8(decoded).ok()?;
    let (u, p) = s.split_once(':')?;
    Some((u.to_string(), p.to_string()))
}

fn unauthorized_response() -> Response {
    (
        StatusCode::UNAUTHORIZED,
        [(
            header::WWW_AUTHENTICATE,
            HeaderValue::from_static(r#"Basic realm="FP File Manager WebDAV""#),
        )],
        "Unauthorized",
    )
        .into_response()
}

fn percent_decode(raw: &str) -> Result<String, ()> {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex_str = std::str::from_utf8(&bytes[i + 1..i + 3]).map_err(|_| ())?;
            if let Ok(v) = u8::from_str_radix(hex_str, 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).map_err(|_| ())
}

fn percent_encode_path(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for &b in raw.as_bytes() {
        let safe = b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~' | b'/');
        if safe {
            out.push(b as char);
        } else {
            out.push('%');
            out.push_str(&format!("{b:02X}"));
        }
    }
    out
}

fn resolve_vfs_path(base_prefix: &VfsPath, raw_uri_path: &str) -> Result<(VfsPath, Vec<String>), StatusCode> {
    let decoded = percent_decode(raw_uri_path).map_err(|_| StatusCode::BAD_REQUEST)?;
    if decoded.contains('\0') {
        return Err(StatusCode::BAD_REQUEST);
    }
    let mut rel_segments = Vec::new();
    for seg in decoded.split(['/', '\\']) {
        if seg.is_empty() || seg == "." {
            continue;
        }
        if seg == ".." {
            return Err(StatusCode::BAD_REQUEST);
        }
        rel_segments.push(seg.to_string());
    }
    let mut full = base_prefix.clone();
    for seg in &rel_segments {
        full = full.join(seg);
    }
    Ok((full, rel_segments))
}

fn extract_destination_path(headers: &HeaderMap) -> Result<String, StatusCode> {
    let dest = headers
        .get("destination")
        .or_else(|| headers.get("Destination"))
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::BAD_REQUEST)?
        .trim();

    let raw_path = if let Some(scheme_end) = dest.find("://") {
        let rest = &dest[scheme_end + 3..];
        let path_start = rest.find('/').unwrap_or(rest.len());
        &rest[path_start..]
    } else {
        dest
    };
    let without_frag = raw_path.split('#').next().unwrap_or(raw_path);
    let without_query = without_frag.split('?').next().unwrap_or(without_frag);
    Ok(without_query.to_string())
}

fn vfs_err_to_status(err: VfsError) -> StatusCode {
    match err {
        VfsError::NotFound { .. } => StatusCode::NOT_FOUND,
        VfsError::PermissionDenied { .. } => StatusCode::FORBIDDEN,
        VfsError::Unsupported { .. } => StatusCode::METHOD_NOT_ALLOWED,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

fn xml_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            other => out.push(other),
        }
    }
    out
}

fn format_http_date(st: SystemTime) -> String {
    let dt: DateTime<Utc> = st.into();
    dt.format("%a, %d %b %Y %H:%M:%S GMT").to_string()
}

fn build_propfind_response_xml(href_path: &str, entry: &Entry) -> String {
    let is_dir = entry.kind == EntryKind::Dir;
    let mut href = percent_encode_path(href_path);
    if is_dir && !href.ends_with('/') {
        href.push('/');
    } else if !is_dir && href.len() > 1 && href.ends_with('/') {
        href.pop();
    }
    let display_name = if entry.name.is_empty() {
        "/"
    } else {
        entry.name.as_str()
    };
    let last_mod = entry
        .modified
        .map(format_http_date)
        .unwrap_or_else(|| "Thu, 01 Jan 1970 00:00:00 GMT".to_string());

    let res_type = if is_dir {
        "<D:resourcetype><D:collection/></D:resourcetype>"
    } else {
        "<D:resourcetype/>"
    };
    let size_xml = if !is_dir {
        format!(
            "<D:getcontentlength>{}</D:getcontentlength>",
            entry.size.unwrap_or(0)
        )
    } else {
        String::new()
    };
    let mime_xml = if !is_dir {
        let mime = entry
            .mime
            .clone()
            .unwrap_or_else(|| {
                mime_guess::from_path(&entry.name)
                    .first_or_octet_stream()
                    .essence_str()
                    .to_string()
            });
        format!("<D:getcontenttype>{}</D:getcontenttype>", xml_escape(&mime))
    } else {
        String::new()
    };

    format!(
        "<D:response>\
         <D:href>{href}</D:href>\
         <D:propstat>\
         <D:prop>\
         <D:displayname>{}</D:displayname>\
         {res_type}\
         {size_xml}\
         {mime_xml}\
         <D:getlastmodified>{last_mod}</D:getlastmodified>\
         </D:prop>\
         <D:status>HTTP/1.1 200 OK</D:status>\
         </D:propstat>\
         </D:response>",
        xml_escape(display_name)
    )
}

fn parse_byte_range(range_hdr: &str, total: u64) -> Option<(u64, u64)> {
    if total == 0 {
        return None;
    }
    let spec = range_hdr.trim().strip_prefix("bytes=")?.split(',').next()?.trim();
    let (start_s, end_s) = spec.split_once('-')?;
    if start_s.is_empty() {
        let suffix: u64 = end_s.parse().ok()?;
        if suffix == 0 {
            return None;
        }
        let start = total.saturating_sub(suffix);
        return Some((start, total - 1));
    }
    let start: u64 = start_s.parse().ok()?;
    if start >= total {
        return None;
    }
    let end = if end_s.is_empty() {
        total - 1
    } else {
        end_s.parse::<u64>().ok()?.min(total - 1)
    };
    if end < start {
        None
    } else {
        Some((start, end))
    }
}

async fn handle_webdav(State(state): State<WebDavState>, req: Request) -> Response {
    if !check_basic_auth(&state, req.headers()) {
        return unauthorized_response();
    }

    let method = req.method().as_str().to_ascii_uppercase();
    let raw_path = req.uri().path().to_string();

    if method == "OPTIONS" {
        let allow = if state.read_only {
            "OPTIONS, GET, HEAD, PROPFIND"
        } else {
            "OPTIONS, GET, HEAD, PUT, DELETE, MKCOL, MOVE, COPY, PROPFIND"
        };
        return (
            StatusCode::OK,
            [
                ("DAV", "1, 2"),
                ("MS-Author-Via", "DAV"),
                ("Allow", allow),
                ("Accept-Ranges", "bytes"),
            ],
            "",
        )
            .into_response();
    }

    let (vfs_path, rel_segments) = match resolve_vfs_path(&state.base_prefix, &raw_path) {
        Ok(v) => v,
        Err(code) => return code.into_response(),
    };

    match method.as_str() {
        "PROPFIND" => {
            let depth = req
                .headers()
                .get("depth")
                .or_else(|| req.headers().get("Depth"))
                .and_then(|v| v.to_str().ok())
                .map(|s| s.trim().to_ascii_lowercase())
                .unwrap_or_else(|| "1".to_string());

            let entry = if rel_segments.is_empty() && state.base_prefix.is_root() {
                Entry {
                    name: String::new(),
                    path: VfsPath::root(),
                    kind: EntryKind::Dir,
                    size: None,
                    modified: None,
                    mode: None,
                    hidden: false,
                    is_symlink: false,
                    mime: None,
                }
            } else {
                match state.vfs.stat(&vfs_path).await {
                    Ok(e) => e,
                    Err(e) => return vfs_err_to_status(e).into_response(),
                }
            };

            let base_href = if rel_segments.is_empty() {
                "/".to_string()
            } else {
                format!("/{}", rel_segments.join("/"))
            };

            let mut responses_xml = String::new();
            responses_xml.push_str(&build_propfind_response_xml(&base_href, &entry));

            if depth != "0" && entry.kind == EntryKind::Dir {
                let children = match state.vfs.list(&vfs_path).await {
                    Ok(c) => c,
                    Err(e) => return vfs_err_to_status(e).into_response(),
                };
                let mut seen = HashSet::new();
                for child in children {
                    if !seen.insert(child.name.clone()) {
                        continue;
                    }
                    let child_href = if base_href == "/" {
                        format!("/{}", child.name)
                    } else {
                        format!("{}/{}", base_href, child.name)
                    };
                    responses_xml.push_str(&build_propfind_response_xml(&child_href, &child));
                }
            }

            let body = format!(
                "<?xml version=\"1.0\" encoding=\"utf-8\"?>\
                 <D:multistatus xmlns:D=\"DAV:\">{responses_xml}</D:multistatus>"
            );
            (
                StatusCode::MULTI_STATUS,
                [(header::CONTENT_TYPE, "application/xml; charset=utf-8")],
                body,
            )
                .into_response()
        }
        "GET" | "HEAD" => {
            let is_head = method == "HEAD";
            let stat = match state.vfs.stat(&vfs_path).await {
                Ok(e) => e,
                Err(e) => return vfs_err_to_status(e).into_response(),
            };
            if stat.kind == EntryKind::Dir {
                return StatusCode::METHOD_NOT_ALLOWED.into_response();
            }
            let mime = stat.mime.unwrap_or_else(|| {
                mime_guess::from_path(&stat.name)
                    .first_or_octet_stream()
                    .essence_str()
                    .to_string()
            });

            if let (Some(total), Some(range_hdr)) = (
                stat.size,
                req.headers().get(header::RANGE).and_then(|v| v.to_str().ok()),
            ) {
                let Some((start, end)) = parse_byte_range(range_hdr, total) else {
                    return (
                        StatusCode::RANGE_NOT_SATISFIABLE,
                        [(header::CONTENT_RANGE, format!("bytes */{total}"))],
                        "",
                    )
                        .into_response();
                };
                let len = end - start + 1;
                let builder = Response::builder()
                    .status(StatusCode::PARTIAL_CONTENT)
                    .header(header::CONTENT_TYPE, mime)
                    .header(header::ACCEPT_RANGES, "bytes")
                    .header(header::CONTENT_LENGTH, len.to_string())
                    .header(header::CONTENT_RANGE, format!("bytes {start}-{end}/{total}"));
                if is_head {
                    return builder.body(Body::empty()).unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response());
                }
                let reader = match state.vfs.open_read_range(&vfs_path, start, Some(len)).await {
                    Ok(r) => r,
                    Err(e) => return vfs_err_to_status(e).into_response(),
                };
                return builder
                    .body(Body::from_stream(ReaderStream::new(reader)))
                    .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response());
            }

            let mut builder = Response::builder()
                .status(StatusCode::OK)
                .header(header::CONTENT_TYPE, mime)
                .header(header::ACCEPT_RANGES, "bytes");
            if let Some(sz) = stat.size {
                builder = builder.header(header::CONTENT_LENGTH, sz.to_string());
            }
            if is_head {
                return builder.body(Body::empty()).unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response());
            }
            let reader = match state.vfs.open_read(&vfs_path).await {
                Ok(r) => r,
                Err(e) => return vfs_err_to_status(e).into_response(),
            };
            builder
                .body(Body::from_stream(ReaderStream::new(reader)))
                .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
        }
        "PUT" => {
            if state.read_only {
                return StatusCode::FORBIDDEN.into_response();
            }
            if rel_segments.is_empty() {
                return StatusCode::METHOD_NOT_ALLOWED.into_response();
            }
            let existed = state.vfs.stat(&vfs_path).await.is_ok();
            let mut writer = match state.vfs.open_write(&vfs_path, WriteMode::Truncate).await {
                Ok(w) => w,
                Err(e) => return vfs_err_to_status(e).into_response(),
            };
            let mut stream = req.into_body().into_data_stream();
            while let Some(chunk_res) = stream.next().await {
                let chunk = match chunk_res {
                    Ok(c) => c,
                    Err(_) => return StatusCode::BAD_REQUEST.into_response(),
                };
                if writer.write_all(&chunk).await.is_err() {
                    return StatusCode::INTERNAL_SERVER_ERROR.into_response();
                }
            }
            if writer.shutdown().await.is_err() {
                return StatusCode::INTERNAL_SERVER_ERROR.into_response();
            }
            if existed {
                StatusCode::NO_CONTENT.into_response()
            } else {
                StatusCode::CREATED.into_response()
            }
        }
        "MKCOL" => {
            if state.read_only {
                return StatusCode::FORBIDDEN.into_response();
            }
            if rel_segments.is_empty() {
                return StatusCode::METHOD_NOT_ALLOWED.into_response();
            }
            match state.vfs.mkdir(&vfs_path).await {
                Ok(()) => StatusCode::CREATED.into_response(),
                Err(e) => vfs_err_to_status(e).into_response(),
            }
        }
        "DELETE" => {
            if state.read_only {
                return StatusCode::FORBIDDEN.into_response();
            }
            if rel_segments.is_empty() {
                return StatusCode::FORBIDDEN.into_response();
            }
            match state.vfs.remove(&vfs_path).await {
                Ok(()) => StatusCode::NO_CONTENT.into_response(),
                Err(e) => vfs_err_to_status(e).into_response(),
            }
        }
        "MOVE" | "COPY" => {
            if state.read_only {
                return StatusCode::FORBIDDEN.into_response();
            }
            if rel_segments.is_empty() {
                return StatusCode::FORBIDDEN.into_response();
            }
            let dest_raw = match extract_destination_path(req.headers()) {
                Ok(p) => p,
                Err(code) => return code.into_response(),
            };
            let (dst_vfs_path, dst_rel_segments) =
                match resolve_vfs_path(&state.base_prefix, &dest_raw) {
                    Ok(v) => v,
                    Err(code) => return code.into_response(),
                };
            if dst_rel_segments.is_empty() || vfs_path == dst_vfs_path {
                return StatusCode::FORBIDDEN.into_response();
            }
            let overwrite_false = req
                .headers()
                .get("overwrite")
                .or_else(|| req.headers().get("Overwrite"))
                .and_then(|v| v.to_str().ok())
                .map(|s| s.trim().eq_ignore_ascii_case("F"))
                .unwrap_or(false);
            let existed = state.vfs.stat(&dst_vfs_path).await.is_ok();
            if overwrite_false && existed {
                return StatusCode::PRECONDITION_FAILED.into_response();
            }
            if method == "MOVE" {
                match state.vfs.rename(&vfs_path, &dst_vfs_path).await {
                    Ok(()) => {
                        if existed {
                            StatusCode::NO_CONTENT.into_response()
                        } else {
                            StatusCode::CREATED.into_response()
                        }
                    }
                    Err(e) => vfs_err_to_status(e).into_response(),
                }
            } else {
                let src_stat = match state.vfs.stat(&vfs_path).await {
                    Ok(s) => s,
                    Err(e) => return vfs_err_to_status(e).into_response(),
                };
                if src_stat.kind == EntryKind::Dir {
                    if let Err(code) = copy_vfs_dir_recursive(
                        state.vfs.as_ref(),
                        &vfs_path,
                        &dst_vfs_path,
                    )
                    .await
                    {
                        return code.into_response();
                    }
                    if existed {
                        StatusCode::NO_CONTENT.into_response()
                    } else {
                        StatusCode::CREATED.into_response()
                    }
                } else {
                    if let Err(code) = copy_vfs_file(
                        state.vfs.as_ref(),
                        &vfs_path,
                        &dst_vfs_path,
                    )
                    .await
                    {
                        return code.into_response();
                    }
                    if existed {
                        StatusCode::NO_CONTENT.into_response()
                    } else {
                        StatusCode::CREATED.into_response()
                    }
                }
            }
        }
        _ => StatusCode::METHOD_NOT_ALLOWED.into_response(),
    }
}

async fn copy_vfs_file(vfs: &dyn Vfs, src: &VfsPath, dst: &VfsPath) -> Result<(), StatusCode> {
    let mut r = vfs.open_read(src).await.map_err(vfs_err_to_status)?;
    let mut w = vfs
        .open_write(dst, WriteMode::Truncate)
        .await
        .map_err(vfs_err_to_status)?;
    if tokio::io::copy(&mut r, &mut w).await.is_err() || w.shutdown().await.is_err() {
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }
    Ok(())
}

async fn copy_vfs_dir_recursive(
    vfs: &dyn Vfs,
    src_root: &VfsPath,
    dst_root: &VfsPath,
) -> Result<(), StatusCode> {
    let mut queue = std::collections::VecDeque::from([(src_root.clone(), dst_root.clone())]);
    while let Some((src_dir, dst_dir)) = queue.pop_front() {
        if vfs.stat(&dst_dir).await.is_err() {
            vfs.mkdir(&dst_dir).await.map_err(vfs_err_to_status)?;
        }
        let children = vfs.list(&src_dir).await.map_err(vfs_err_to_status)?;
        for child in children {
            if child.is_symlink {
                continue;
            }
            let child_dst = dst_dir.join(&child.name);
            if child.kind == EntryKind::Dir {
                queue.push_back((child.path, child_dst));
            } else {
                copy_vfs_file(vfs, &child.path, &child_dst).await?;
            }
        }
    }
    Ok(())
}
