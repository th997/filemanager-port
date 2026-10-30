//! Loopback HTTP server that exposes one VFS as byte-range streams.
//!
//! The media player runs in the Flutter process and needs a URL with HTTP
//! Range support, while remote and archive backends only expose an
//! `AsyncRead`. Serving the bytes over loopback keeps seeking working without
//! copying the whole file into memory first.
//!
//! The listener binds to `127.0.0.1` and every request must carry the random
//! token generated when the server starts: other apps on the device can reach
//! loopback ports, so the port alone is not an access control.

use axum::extract::{Path as AxumPath, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{body::Body, Router};
use fm_core::VfsPath;
use fm_vfs::Vfs;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio::net::TcpListener;
use tokio::sync::oneshot;
use tokio_util::io::ReaderStream;

/// Bytes pushed to the socket per read. 256 KiB leaves the network
/// and loopback streaming responsive even at high bitrate and fast playback rates.
const STREAM_BUFFER: usize = 256 * 1024;

/// In-memory prefetch capacity per stream (4 MiB). Decouples remote backend reads
/// (e.g. SFTP over WAN) from loopback socket polling so AVPlayer is never starved by network jitter,
/// while preventing multiple concurrent stream ranges from ballooning memory.
const PREFETCH_CAPACITY: usize = 4 * 1024 * 1024;

pub struct StreamServer {
    pub port: u16,
    pub token: String,
    shutdown_tx: oneshot::Sender<()>,
}

impl StreamServer {
    pub fn shutdown(self) {
        let _ = self.shutdown_tx.send(());
    }
}

struct StreamState {
    vfs: Arc<dyn Vfs>,
    token: String,
}

/// Start a loopback stream server for `vfs`.
pub async fn start_stream_server(vfs: Arc<dyn Vfs>) -> Result<StreamServer, String> {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| format!("failed to bind loopback port: {e}"))?;
    let port = listener
        .local_addr()
        .map_err(|e| e.to_string())?
        .port();

    let token = uuid::Uuid::new_v4().to_string();
    let state = Arc::new(StreamState {
        vfs,
        token: token.clone(),
    });

    let app = Router::new()
        .route("/stream/{token}/{*path}", get(handle_stream))
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel();
    tokio::spawn(async move {
        let _ = axum::serve(listener, app)
            .with_graceful_shutdown(async move {
                let _ = shutdown_rx.await;
            })
            .await;
    });

    Ok(StreamServer {
        port,
        token,
        shutdown_tx,
    })
}

async fn handle_stream(
    State(state): State<Arc<StreamState>>,
    AxumPath((token, subpath)): AxumPath<(String, String)>,
    method: Method,
    headers: HeaderMap,
) -> Response {
    if token != state.token {
        return StatusCode::UNAUTHORIZED.into_response();
    }

    let path = VfsPath::from_slash_path(&subpath);
    let entry = match state.vfs.stat(&path).await {
        Ok(entry) => entry,
        Err(_) => {
            return StatusCode::NOT_FOUND.into_response();
        }
    };
    let total = entry.size;

    let range = parse_range(headers.get(header::RANGE), total);
    let (offset, length, status) = match range {
        RangeSpec::None => (0, None, StatusCode::OK),
        RangeSpec::Satisfiable { offset, length } => {
            (offset, Some(length), StatusCode::PARTIAL_CONTENT)
        }
        RangeSpec::Unsatisfiable => {
            let mut response = StatusCode::RANGE_NOT_SATISFIABLE.into_response();
            if let Some(total) = total {
                if let Ok(value) = HeaderValue::from_str(&format!("bytes */{total}")) {
                    response.headers_mut().insert(header::CONTENT_RANGE, value);
                }
            }
            return response;
        }
    };

    let raw_mime = mime_guess::from_path(&subpath)
        .first_or_octet_stream()
        .to_string();
    let mime = if raw_mime.starts_with("text/") && !raw_mime.contains("charset") {
        format!("{raw_mime}; charset=utf-8")
    } else {
        raw_mime
    };

    let cache_control = if mime.starts_with("image/")
        || mime.starts_with("font/")
        || mime.starts_with("video/")
        || mime.starts_with("audio/")
        || mime == "text/css"
        || mime == "application/javascript"
    {
        "public, max-age=300"
    } else {
        "no-cache"
    };

    let mut builder = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, mime)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::CONNECTION, "keep-alive")
        .header(header::CACHE_CONTROL, cache_control)
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*");

    match (total, length) {
        (Some(total), Some(length)) => {
            builder = builder
                .header(header::CONTENT_LENGTH, length.to_string())
                .header(
                    header::CONTENT_RANGE,
                    format!("bytes {offset}-{}/{total}", offset + length - 1),
                );
        }
        (Some(total), None) => {
            builder = builder.header(header::CONTENT_LENGTH, total.to_string());
        }
        // Unknown size: no length, the body is chunked and runs to EOF.
        (None, _) => {}
    }

    if method == Method::HEAD {
        return builder.body(Body::empty()).unwrap_or_else(|_| {
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        });
    }

    let reader = match state.vfs.open_read_range(&path, offset, length).await {
        Ok(reader) => reader,
        Err(_) => {
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let prefetch_cap = match length.or(total) {
        Some(size) => ((size as usize).min(PREFETCH_CAPACITY)).max(64 * 1024),
        None => 1024 * 1024,
    };
    let read_buf_size = prefetch_cap.min(64 * 1024);
    let stream_buf = prefetch_cap.min(STREAM_BUFFER);

    let (reader_end, mut writer_end) = tokio::io::simplex(prefetch_cap);
    tokio::spawn(async move {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let mut reader = reader;
        let mut buf = vec![0u8; read_buf_size];
        loop {
            match reader.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    if writer_end.write_all(&buf[..n]).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    let body = Body::from_stream(ReaderStream::with_capacity(reader_end, stream_buf));
    builder.body(body).unwrap_or_else(|_| {
        StatusCode::INTERNAL_SERVER_ERROR.into_response()
    })
}

enum RangeSpec {
    None,
    Satisfiable { offset: u64, length: u64 },
    Unsatisfiable,
}

/// Parse a single `Range: bytes=...` header.
///
/// Multi-range requests and malformed values are ignored (the whole entity is
/// served). A well-formed range past the end is unsatisfiable and must produce
/// `416`, not an empty `206`.
fn parse_range(value: Option<&HeaderValue>, total: Option<u64>) -> RangeSpec {
    let value = match value.and_then(|v| v.to_str().ok()) {
        Some(value) => value,
        None => return RangeSpec::None,
    };
    let spec = match value.strip_prefix("bytes=") {
        Some(spec) => spec,
        None => return RangeSpec::None,
    };
    if spec.contains(',') {
        return RangeSpec::None;
    }
    let (start, end) = match spec.split_once('-') {
        Some(parts) => parts,
        None => return RangeSpec::None,
    };

    // Without a known size no range can be validated; stream everything.
    let total = match total {
        Some(total) => total,
        None => return RangeSpec::None,
    };

    if start.is_empty() {
        let suffix: u64 = match end.parse() {
            Ok(suffix) => suffix,
            Err(_) => return RangeSpec::None,
        };
        if suffix == 0 || total == 0 {
            return RangeSpec::Unsatisfiable;
        }
        let offset = total.saturating_sub(suffix);
        return RangeSpec::Satisfiable {
            offset,
            length: total - offset,
        };
    }

    let offset: u64 = match start.parse() {
        Ok(offset) => offset,
        Err(_) => return RangeSpec::None,
    };
    if offset >= total {
        return RangeSpec::Unsatisfiable;
    }
    let last = total - 1;
    let end: u64 = if end.is_empty() {
        last
    } else {
        match end.parse::<u64>() {
            Ok(requested) => requested.min(last),
            Err(_) => return RangeSpec::None,
        }
    };
    if end < offset {
        return RangeSpec::Unsatisfiable;
    }
    RangeSpec::Satisfiable {
        offset,
        length: end - offset + 1,
    }
}

/// Read a byte range into memory. Used by the FFI download path and tests.
pub async fn read_range(
    vfs: &dyn Vfs,
    path: &VfsPath,
    offset: u64,
    length: Option<u64>,
) -> Result<Vec<u8>, String> {
    let mut reader = vfs
        .open_read_range(path, offset, length)
        .await
        .map_err(|e| e.to_string())?;
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).await.map_err(|e| e.to_string())?;
    Ok(buf)
}

/// Seek helper kept for backends that expose `AsyncSeek`.
pub async fn seek_to<S>(stream: &mut S, offset: u64) -> std::io::Result<()>
where
    S: tokio::io::AsyncSeek + Unpin,
{
    stream.seek(std::io::SeekFrom::Start(offset)).await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn range(spec: &str, total: Option<u64>) -> RangeSpec {
        let value = HeaderValue::from_str(spec).unwrap();
        parse_range(Some(&value), total)
    }

    fn assert_range(actual: RangeSpec, offset: u64, length: u64) {
        match actual {
            RangeSpec::Satisfiable { offset: o, length: l } => {
                assert_eq!((o, l), (offset, length));
            }
            RangeSpec::None => panic!("expected a range, got none"),
            RangeSpec::Unsatisfiable => panic!("expected a range, got unsatisfiable"),
        }
    }

    #[test]
    fn parses_closed_and_open_ranges() {
        assert_range(range("bytes=0-99", Some(1000)), 0, 100);
        assert_range(range("bytes=100-", Some(1000)), 100, 900);
        assert_range(range("bytes=-100", Some(1000)), 900, 100);
        assert_range(range("bytes=990-5000", Some(1000)), 990, 10);
        assert_range(range("bytes=-5000", Some(1000)), 0, 1000);
    }

    #[test]
    fn ignores_multi_and_malformed_ranges() {
        assert!(matches!(range("bytes=0-1,5-6", Some(1000)), RangeSpec::None));
        assert!(matches!(range("bytes=abc-def", Some(1000)), RangeSpec::None));
        assert!(matches!(range("items=0-1", Some(1000)), RangeSpec::None));
        assert!(matches!(parse_range(None, Some(1000)), RangeSpec::None));
    }

    #[test]
    fn rejects_unsatisfiable_ranges() {
        assert!(matches!(range("bytes=1000-", Some(1000)), RangeSpec::Unsatisfiable));
        assert!(matches!(range("bytes=2000-3000", Some(1000)), RangeSpec::Unsatisfiable));
        assert!(matches!(range("bytes=-0", Some(1000)), RangeSpec::Unsatisfiable));
        assert!(matches!(range("bytes=500-400", Some(1000)), RangeSpec::Unsatisfiable));
        assert!(matches!(range("bytes=0-", Some(0)), RangeSpec::Unsatisfiable));
    }

    #[test]
    fn ignores_ranges_when_size_is_unknown() {
        assert!(matches!(range("bytes=0-99", None), RangeSpec::None));
        assert!(matches!(range("bytes=-100", None), RangeSpec::None));
    }
}
