//! Direct LAN peer-to-peer file & clipboard text transfer (LocalSend-style).
//!
//! Devices running the receiver advertise over UDP (`PEER_DISCOVERY_PORT`) and
//! accept HTTP transfer offers requiring explicit receiver consent before
//! streaming payload bytes directly to disk.

use std::collections::BTreeMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::extract::{DefaultBodyLimit, Path as AxumPath, Request, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use fm_core::VfsPath;
use fm_vfs::Vfs;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;
use tokio::net::UdpSocket;
use tokio::sync::oneshot;
use tokio_util::io::ReaderStream;

pub const PEER_DISCOVERY_PORT: u16 = 45892;
#[cfg(target_pointer_width = "64")]
const MAX_PEER_UPLOAD_BYTES: usize = 8 * 1024 * 1024 * 1024;
#[cfg(not(target_pointer_width = "64"))]
const MAX_PEER_UPLOAD_BYTES: usize = usize::MAX;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerDeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerTransferOffer {
    pub offer_id: String,
    pub sender_name: String,
    pub kind: String,
    pub items: Vec<String>,
    pub total_bytes: u64,
    pub text_preview: Option<String>,
    pub text_payload: Option<String>,
    pub status: String,
    pub save_dir: Option<String>,
    pub received_files: u32,
}

#[derive(Clone)]
struct PeerState {
    device_id: String,
    device_name: String,
    platform: String,
    port: u16,
    default_save_dir: PathBuf,
    offers: Arc<Mutex<Vec<PeerTransferOffer>>>,
}

pub struct RunningPeerReceiver {
    pub device_id: String,
    pub device_name: String,
    pub port: u16,
    pub save_dir: PathBuf,
    offers: Arc<Mutex<Vec<PeerTransferOffer>>>,
    shutdown_tx: oneshot::Sender<()>,
}

impl RunningPeerReceiver {
    pub fn list_offers(&self) -> Vec<PeerTransferOffer> {
        let guard = self.offers.lock().unwrap_or_else(|e| e.into_inner());
        guard.clone()
    }

    pub fn respond_offer(&self, offer_id: &str, accept: bool, save_dir: Option<&str>) -> bool {
        let mut guard = self.offers.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(offer) = guard.iter_mut().find(|o| o.offer_id == offer_id) {
            if offer.status != "pending" {
                return false;
            }
            if accept {
                offer.status = if offer.kind == "text" {
                    "completed".to_string()
                } else {
                    "accepted".to_string()
                };
                if let Some(dir) = save_dir.filter(|s| !s.trim().is_empty()) {
                    offer.save_dir = Some(dir.trim().to_string());
                }
            } else {
                offer.status = "rejected".to_string();
            }
            true
        } else {
            false
        }
    }

    pub fn shutdown(self) {
        let _ = self.shutdown_tx.send(());
    }
}

use crate::net::{get_lan_interfaces, get_lan_ip_addresses, select_best_peer_ip, LanInterface};

#[derive(Debug, Serialize, Deserialize)]
struct UdpBeacon {
    device_id: String,
    device_name: String,
    platform: String,
    port: u16,
    version: u8,
    #[serde(default)]
    ips: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct UdpProbe {
    #[allow(dead_code)]
    probe: bool,
}

#[derive(Debug, Deserialize)]
struct CreateOfferRequest {
    sender_name: String,
    kind: String,
    items: Vec<String>,
    total_bytes: u64,
    text_preview: Option<String>,
    text_payload: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct CreateOfferResponse {
    offer_id: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct OfferStatusResponse {
    status: String,
}

async fn broadcast_beacon_payload(payload: &[u8], main_sock: &UdpSocket) {
    let bcast_global = SocketAddr::new(IpAddr::V4(Ipv4Addr::BROADCAST), PEER_DISCOVERY_PORT);
    let _ = main_sock.send_to(payload, bcast_global).await;

    for iface in get_lan_interfaces().into_iter().filter(|i| !i.is_virtual) {
        let target = SocketAddr::new(IpAddr::V4(iface.broadcast), PEER_DISCOVERY_PORT);
        // Send from an ephemeral socket bound to the physical interface IP so
        // TUN/VPN default routes cannot hijack directed LAN broadcasts.
        if let Ok(nic_sock) = UdpSocket::bind((iface.ip, 0)).await {
            let _ = nic_sock.set_broadcast(true);
            let _ = nic_sock.send_to(payload, target).await;
        }
        let _ = main_sock.send_to(payload, target).await;
    }
}

fn beacon_to_peer_info(
    beacon: UdpBeacon,
    src_ip: IpAddr,
    local_ifaces: &[LanInterface],
) -> Option<PeerDeviceInfo> {
    let ip = select_best_peer_ip(src_ip, &beacon.ips, local_ifaces)?;
    Some(PeerDeviceInfo {
        device_id: beacon.device_id,
        device_name: beacon.device_name,
        platform: beacon.platform,
        host: ip.to_string(),
        port: beacon.port,
    })
}

pub async fn start_peer_receiver(
    device_name: String,
    save_dir: PathBuf,
    port: Option<u16>,
) -> Result<RunningPeerReceiver, String> {
    let bind_port = port.unwrap_or(0);
    let addr: SocketAddr = format!("0.0.0.0:{bind_port}")
        .parse()
        .map_err(|e| format!("invalid peer receiver address: {e}"))?;
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .map_err(|e| format!("failed to bind peer receiver: {e}"))?;
    let actual_port = listener
        .local_addr()
        .map_err(|e| format!("failed to read peer receiver port: {e}"))?
        .port();

    let _ = tokio::fs::create_dir_all(&save_dir).await;

    let device_id = uuid::Uuid::new_v4().to_string();
    let platform = std::env::consts::OS.to_string();
    let offers = Arc::new(Mutex::new(Vec::<PeerTransferOffer>::new()));

    let state = PeerState {
        device_id: device_id.clone(),
        device_name: device_name.clone(),
        platform: platform.clone(),
        port: actual_port,
        default_save_dir: save_dir.clone(),
        offers: Arc::clone(&offers),
    };

    let app = Router::new()
        .route("/api/v1/peer/info", get(peer_info_handler))
        .route(
            "/api/v1/peer/offer",
            post(create_offer_handler).route_layer(DefaultBodyLimit::max(1024 * 1024)),
        )
        .route("/api/v1/peer/offer/{id}/status", get(offer_status_handler))
        .route(
            "/api/v1/peer/upload/{id}",
            post(upload_file_handler).route_layer(DefaultBodyLimit::max(MAX_PEER_UPLOAD_BYTES)),
        )
        .with_state(state);

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let (udp_stop_tx, mut udp_stop_rx) = oneshot::channel::<()>();

    tokio::spawn(async move {
        let _ = axum::serve(listener, app)
            .with_graceful_shutdown(async {
                let _ = shutdown_rx.await;
                let _ = udp_stop_tx.send(());
            })
            .await;
    });

    // Spawn lightweight UDP broadcast beacon + probe responder (best-effort if port 45892 is free).
    let beacon = UdpBeacon {
        device_id: device_id.clone(),
        device_name: device_name.clone(),
        platform,
        port: actual_port,
        version: 1,
        ips: get_lan_ip_addresses(),
    };
    tokio::spawn(async move {
        let Ok(sock) = UdpSocket::bind(("0.0.0.0", PEER_DISCOVERY_PORT)).await else {
            let _ = udp_stop_rx.await;
            return;
        };
        let _ = sock.set_broadcast(true);
        let Ok(payload) = serde_json::to_vec(&beacon) else {
            return;
        };
        broadcast_beacon_payload(&payload, &sock).await;

        let mut buf = [0u8; 512];
        let mut interval = tokio::time::interval(Duration::from_secs(2));
        loop {
            tokio::select! {
                _ = &mut udp_stop_rx => break,
                _ = interval.tick() => {
                    broadcast_beacon_payload(&payload, &sock).await;
                }
                recv = sock.recv_from(&mut buf) => {
                    if let Ok((n, src)) = recv {
                        if serde_json::from_slice::<UdpProbe>(&buf[..n]).is_ok() {
                            let _ = sock.send_to(&payload, src).await;
                        }
                    }
                }
            }
        }
    });

    Ok(RunningPeerReceiver {
        device_id,
        device_name,
        port: actual_port,
        save_dir,
        offers,
        shutdown_tx,
    })
}

pub async fn discover_lan_peers(
    timeout_ms: u32,
    self_device_id: Option<&str>,
) -> Vec<PeerDeviceInfo> {
    let budget = Duration::from_millis(timeout_ms.clamp(400, 5000) as u64);
    let local_ifaces = get_lan_interfaces();
    let mut sockets = Vec::new();

    for iface in local_ifaces.iter().filter(|i| !i.is_virtual) {
        if let Ok(sock) = UdpSocket::bind((iface.ip, 0)).await {
            let _ = sock.set_broadcast(true);
            let bcast_iface = SocketAddr::new(IpAddr::V4(iface.broadcast), PEER_DISCOVERY_PORT);
            let bcast_global = SocketAddr::new(IpAddr::V4(Ipv4Addr::BROADCAST), PEER_DISCOVERY_PORT);
            let _ = sock.send_to(br#"{"probe":true}"#, bcast_iface).await;
            let _ = sock.send_to(br#"{"probe":true}"#, bcast_global).await;
            sockets.push(sock);
        }
    }

    if let Ok(sock) = UdpSocket::bind(("0.0.0.0", 0)).await {
        let _ = sock.set_broadcast(true);
        let bcast_global = SocketAddr::new(IpAddr::V4(Ipv4Addr::BROADCAST), PEER_DISCOVERY_PORT);
        let _ = sock.send_to(br#"{"probe":true}"#, bcast_global).await;
        for iface in local_ifaces.iter().filter(|i| !i.is_virtual) {
            let bcast_iface = SocketAddr::new(IpAddr::V4(iface.broadcast), PEER_DISCOVERY_PORT);
            let _ = sock.send_to(br#"{"probe":true}"#, bcast_iface).await;
        }
        sockets.push(sock);
    }

    if sockets.is_empty() {
        return Vec::new();
    }

    let deadline = tokio::time::Instant::now() + budget;
    let ifaces_arc = Arc::new(local_ifaces);
    let self_id_owned = self_device_id.map(str::to_string);
    let mut handles = Vec::with_capacity(sockets.len());
    for sock in sockets {
        let ifaces = Arc::clone(&ifaces_arc);
        let self_id = self_id_owned.clone();
        handles.push(tokio::spawn(async move {
            let mut local_peers: BTreeMap<String, PeerDeviceInfo> = BTreeMap::new();
            let mut buf = [0u8; 1024];
            loop {
                let now = tokio::time::Instant::now();
                if now >= deadline {
                    break;
                }
                let remain = deadline.saturating_duration_since(now);
                match tokio::time::timeout(remain, sock.recv_from(&mut buf)).await {
                    Ok(Ok((n, src))) => {
                        if let Ok(beacon) = serde_json::from_slice::<UdpBeacon>(&buf[..n]) {
                            if self_id.as_deref() == Some(beacon.device_id.as_str()) {
                                continue;
                            }
                            if let Some(info) = beacon_to_peer_info(beacon, src.ip(), &ifaces) {
                                local_peers.insert(info.device_id.clone(), info);
                            }
                        }
                    }
                    Ok(Err(_)) => continue,
                    Err(_) => break,
                }
            }
            local_peers
        }));
    }

    let mut peers: BTreeMap<String, PeerDeviceInfo> = BTreeMap::new();
    for h in handles {
        if let Ok(part) = h.await {
            peers.extend(part);
        }
    }
    peers.into_values().collect()
}

async fn peer_info_handler(State(state): State<PeerState>) -> Json<PeerDeviceInfo> {
    Json(PeerDeviceInfo {
        device_id: state.device_id,
        device_name: state.device_name,
        platform: state.platform,
        host: String::new(),
        port: state.port,
    })
}

async fn create_offer_handler(
    State(state): State<PeerState>,
    Json(req): Json<CreateOfferRequest>,
) -> Json<CreateOfferResponse> {
    let offer_id = uuid::Uuid::new_v4().to_string();
    let preview = req.text_preview.or_else(|| {
        req.text_payload.as_ref().map(|t| {
            let trimmed: String = t.chars().take(200).collect();
            trimmed
        })
    });
    let offer = PeerTransferOffer {
        offer_id: offer_id.clone(),
        sender_name: req.sender_name,
        kind: req.kind,
        items: req.items,
        total_bytes: req.total_bytes,
        text_preview: preview,
        text_payload: req.text_payload,
        status: "pending".to_string(),
        save_dir: Some(state.default_save_dir.to_string_lossy().into_owned()),
        received_files: 0,
    };
    let mut guard = state.offers.lock().unwrap_or_else(|e| e.into_inner());
    if guard.len() >= 100 {
        guard.remove(0);
    }
    guard.push(offer);
    Json(CreateOfferResponse { offer_id })
}

async fn offer_status_handler(
    State(state): State<PeerState>,
    AxumPath(id): AxumPath<String>,
) -> Result<Json<OfferStatusResponse>, StatusCode> {
    let guard = state.offers.lock().unwrap_or_else(|e| e.into_inner());
    let Some(offer) = guard.iter().find(|o| o.offer_id == id) else {
        return Err(StatusCode::NOT_FOUND);
    };
    Ok(Json(OfferStatusResponse {
        status: offer.status.clone(),
    }))
}

fn percent_decode_header(raw: &str) -> Result<String, StatusCode> {
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex_str) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                if let Ok(v) = u8::from_str_radix(hex_str, 16) {
                    out.push(v);
                    i += 3;
                    continue;
                }
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).map_err(|_| StatusCode::BAD_REQUEST)
}

fn percent_encode_header(raw: &str) -> String {
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

fn normalize_offered_item(raw: &str) -> String {
    raw.replace('\\', "/").trim_start_matches('/').to_string()
}

fn sanitize_relative_path(raw: &str) -> Result<(PathBuf, String), StatusCode> {
    let decoded = percent_decode_header(raw)?;
    if decoded.contains('\0') {
        return Err(StatusCode::BAD_REQUEST);
    }
    let mut clean = PathBuf::new();
    let mut normalized_parts = Vec::new();
    for seg in decoded.split(['/', '\\']) {
        if seg.is_empty() || seg == "." {
            continue;
        }
        if seg == ".." || seg.contains(':') {
            return Err(StatusCode::BAD_REQUEST);
        }
        clean.push(seg);
        normalized_parts.push(seg.to_string());
    }
    if clean.as_os_str().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    Ok((clean, normalized_parts.join("/")))
}

async fn choose_unique_dest_path(desired: PathBuf) -> PathBuf {
    if tokio::fs::symlink_metadata(&desired).await.is_err() {
        return desired;
    }
    let parent = desired.parent().map(Path::to_path_buf).unwrap_or_default();
    let stem = desired
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("file");
    let ext = desired
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{e}"))
        .unwrap_or_default();
    for i in 1u32..10000 {
        let candidate = parent.join(format!("{stem}_{i}{ext}"));
        if tokio::fs::symlink_metadata(&candidate).await.is_err() {
            return candidate;
        }
    }
    parent.join(format!("{stem}_{}{ext}", uuid::Uuid::new_v4()))
}

async fn upload_file_handler(
    State(state): State<PeerState>,
    AxumPath(id): AxumPath<String>,
    req: Request,
) -> StatusCode {
    let rel_hdr = req
        .headers()
        .get("x-relative-path")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("received.bin");
    let Ok((rel_path, normalized_rel)) = sanitize_relative_path(rel_hdr) else {
        return StatusCode::BAD_REQUEST;
    };

    let save_dir = {
        let guard = state.offers.lock().unwrap_or_else(|e| e.into_inner());
        let Some(offer) = guard.iter().find(|o| o.offer_id == id) else {
            return StatusCode::NOT_FOUND;
        };
        if offer.kind != "files" || offer.status != "accepted" {
            return StatusCode::FORBIDDEN;
        }
        if offer.received_files as usize >= offer.items.len() {
            return StatusCode::FORBIDDEN;
        }
        if !offer
            .items
            .iter()
            .any(|item| normalize_offered_item(item) == normalized_rel)
        {
            return StatusCode::FORBIDDEN;
        }
        offer
            .save_dir
            .as_deref()
            .map(PathBuf::from)
            .unwrap_or_else(|| state.default_save_dir.clone())
    };

    if tokio::fs::create_dir_all(&save_dir).await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR;
    }
    let Ok(canon_save) = tokio::fs::canonicalize(&save_dir).await else {
        return StatusCode::INTERNAL_SERVER_ERROR;
    };

    let raw_dest = save_dir.join(rel_path);
    let Some(parent) = raw_dest.parent() else {
        return StatusCode::BAD_REQUEST;
    };
    if tokio::fs::create_dir_all(parent).await.is_err() {
        return StatusCode::INTERNAL_SERVER_ERROR;
    }
    let Ok(canon_parent) = tokio::fs::canonicalize(parent).await else {
        return StatusCode::INTERNAL_SERVER_ERROR;
    };
    if !canon_parent.starts_with(&canon_save) {
        return StatusCode::FORBIDDEN;
    }

    let safe_file_name = raw_dest
        .file_name()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("received.bin"));
    let final_dest = choose_unique_dest_path(canon_parent.join(safe_file_name)).await;
    let temp_dest = canon_parent.join(format!(".fm-peer-part-{}", uuid::Uuid::new_v4()));

    let Ok(mut file) = tokio::fs::File::create(&temp_dest).await else {
        return StatusCode::INTERNAL_SERVER_ERROR;
    };
    let mut stream = req.into_body().into_data_stream();
    while let Some(chunk_res) = stream.next().await {
        let Ok(chunk) = chunk_res else {
            drop(file);
            let _ = tokio::fs::remove_file(&temp_dest).await;
            return StatusCode::BAD_REQUEST;
        };
        if file.write_all(&chunk).await.is_err() {
            drop(file);
            let _ = tokio::fs::remove_file(&temp_dest).await;
            return StatusCode::INTERNAL_SERVER_ERROR;
        }
    }
    if file.shutdown().await.is_err() {
        let _ = tokio::fs::remove_file(&temp_dest).await;
        return StatusCode::INTERNAL_SERVER_ERROR;
    }
    drop(file);

    if tokio::fs::rename(&temp_dest, &final_dest).await.is_err() {
        let _ = tokio::fs::remove_file(&temp_dest).await;
        return StatusCode::INTERNAL_SERVER_ERROR;
    }

    let mut guard = state.offers.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(offer) = guard.iter_mut().find(|o| o.offer_id == id) {
        if offer.kind != "files" || offer.status != "accepted" {
            return StatusCode::FORBIDDEN;
        }
        offer.received_files = offer.received_files.saturating_add(1);
        if offer.received_files as usize >= offer.items.len() {
            offer.status = "completed".to_string();
        }
    }
    StatusCode::OK
}

async fn wait_for_offer_acceptance(
    client: &reqwest::Client,
    base_url: &str,
    offer_id: &str,
) -> Result<(), String> {
    let url = format!("{}/api/v1/peer/offer/{offer_id}/status", base_url.trim_end_matches('/'));
    for _ in 0..200 {
        let resp = client
            .get(&url)
            .send()
            .await
            .map_err(|e| format!("failed to poll offer status: {e}"))?;
        if !resp.status().is_success() {
            return Err(format!("peer status HTTP {}", resp.status()));
        }
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| format!("failed to read peer status body: {e}"))?;
        let st: OfferStatusResponse = serde_json::from_slice(&bytes)
            .map_err(|e| format!("invalid peer status JSON: {e}"))?;
        match st.status.as_str() {
            "accepted" | "completed" => return Ok(()),
            "rejected" => return Err("recipient rejected the transfer".to_string()),
            _ => tokio::time::sleep(Duration::from_millis(300)).await,
        }
    }
    Err("timed out waiting for recipient acceptance".to_string())
}

pub async fn send_peer_text(
    peer_url: &str,
    sender_name: &str,
    text: &str,
) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let base = peer_url.trim_end_matches('/');
    let body = serde_json::json!({
        "sender_name": sender_name,
        "kind": "text",
        "items": ["Clipboard Text"],
        "total_bytes": text.len() as u64,
        "text_payload": text,
    });
    let payload_bytes = serde_json::to_vec(&body).map_err(|e| e.to_string())?;
    let resp = client
        .post(format!("{base}/api/v1/peer/offer"))
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(payload_bytes)
        .send()
        .await
        .map_err(|e| format!("failed to send text offer: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("peer rejected offer request: HTTP {}", resp.status()));
    }
    let created_bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    let created: CreateOfferResponse =
        serde_json::from_slice(&created_bytes).map_err(|e| e.to_string())?;
    wait_for_offer_acceptance(&client, base, &created.offer_id).await
}

pub async fn send_peer_files(
    peer_url: &str,
    sender_name: &str,
    vfs: Arc<dyn Vfs>,
    vfs_paths: Vec<(VfsPath, String)>,
) -> Result<u32, String> {
    if vfs_paths.is_empty() {
        return Ok(0);
    }
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .read_timeout(Duration::from_secs(120))
        .build()
        .map_err(|e| e.to_string())?;
    let base = peer_url.trim_end_matches('/');

    let mut total_bytes = 0u64;
    let mut item_names = Vec::with_capacity(vfs_paths.len());
    for (vp, rel_name) in &vfs_paths {
        if let Ok(st) = vfs.stat(vp).await {
            total_bytes = total_bytes.saturating_add(st.size.unwrap_or(0));
        }
        let clean = Path::new(rel_name)
            .to_string_lossy()
            .replace('\\', "/");
        item_names.push(clean);
    }

    let offer_body = serde_json::json!({
        "sender_name": sender_name,
        "kind": "files",
        "items": item_names,
        "total_bytes": total_bytes,
    });
    let offer_bytes = serde_json::to_vec(&offer_body).map_err(|e| e.to_string())?;
    let resp = client
        .post(format!("{base}/api/v1/peer/offer"))
        .header(reqwest::header::CONTENT_TYPE, "application/json")
        .body(offer_bytes)
        .send()
        .await
        .map_err(|e| format!("failed to send file offer: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("peer offer failed: HTTP {}", resp.status()));
    }
    let created_bytes = resp.bytes().await.map_err(|e| e.to_string())?;
    let created: CreateOfferResponse =
        serde_json::from_slice(&created_bytes).map_err(|e| e.to_string())?;
    wait_for_offer_acceptance(&client, base, &created.offer_id).await?;

    let mut sent = 0u32;
    for (idx, (vp, _)) in vfs_paths.iter().enumerate() {
        let reader = vfs.open_read(vp).await.map_err(|e| e.to_string())?;
        let stream = ReaderStream::new(reader);
        let rel = &item_names[idx];
        let encoded_rel = percent_encode_header(rel);
        let upload_url = format!("{base}/api/v1/peer/upload/{}", created.offer_id);
        let up_resp = client
            .post(upload_url)
            .header("x-relative-path", encoded_rel)
            .body(reqwest::Body::wrap_stream(stream))
            .send()
            .await
            .map_err(|e| format!("failed uploading {rel}: {e}"))?;
        if !up_resp.status().is_success() {
            return Err(format!("peer upload rejected {rel}: HTTP {}", up_resp.status()));
        }
        sent += 1;
    }
    Ok(sent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn beacon_json_backwards_compatible_and_prefers_lan_ip() {
        let old_json = br#"{"device_id":"d1","device_name":"iPhone","platform":"ios","port":1234,"version":1}"#;
        let parsed: UdpBeacon = serde_json::from_slice(old_json).unwrap();
        assert!(parsed.ips.is_empty());

        let local = vec![LanInterface {
            name: "en0".to_string(),
            ip: Ipv4Addr::new(10, 10, 10, 117),
            netmask: Ipv4Addr::new(255, 255, 255, 0),
            broadcast: Ipv4Addr::new(10, 10, 10, 255),
            is_virtual: false,
        }];
        let beacon = UdpBeacon {
            device_id: "d2".into(),
            device_name: "Phone".into(),
            platform: "ios".into(),
            port: 9000,
            version: 1,
            ips: vec!["198.18.0.1".into(), "10.10.10.22".into()],
        };
        let info = beacon_to_peer_info(
            beacon,
            IpAddr::V4(Ipv4Addr::new(198, 18, 0, 1)),
            &local,
        )
        .unwrap();
        assert_eq!(info.host, "10.10.10.22");
    }
}
