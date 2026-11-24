use crate::registry::VfsRegistry;
use fm_core::VfsPath;
use fm_server::{
    discover_lan_peers as discover_lan_peers_impl,
    discover_lan_services as discover_lan_services_impl, get_lan_ip_addresses,
    send_peer_files as send_peer_files_impl, send_peer_text as send_peer_text_impl,
    start_http_share_with_lang, start_peer_receiver as start_peer_receiver_impl,
    start_stream_server_with_options, start_webdav_server, PeerTransferOffer, RunningPeerReceiver,
    RunningServer, RunningWebDavServer, StreamServer,
};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::PathBuf;

static HTTP_RUNNING: Mutex<Option<RunningServer>> = Mutex::new(None);
static WEBDAV_RUNNING: Mutex<Option<(RunningWebDavServer, ServerStatusDto, String)>> =
    Mutex::new(None);
static PEER_RECEIVER: Mutex<Option<(RunningPeerReceiver, ServerStatusDto)>> = Mutex::new(None);
static STREAMS: Mutex<Option<HashMap<String, StreamServer>>> = Mutex::new(None);

#[derive(Debug, Clone)]
pub struct ServerStatusDto {
    pub running: bool,
    pub port: u16,
    pub addresses: Vec<String>,
    pub url: String,
}

#[derive(Debug, Clone)]
pub struct LanServiceDto {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub protocol: String,
    pub source: String,
}

pub async fn start_lan_http_server(
    root_dir: String,
    port: Option<u16>,
    password: Option<String>,
    read_only: bool,
) -> Result<ServerStatusDto, String> {
    start_lan_http_server_with_lang(root_dir, port, password, read_only, None).await
}

pub async fn start_lan_http_server_with_lang(
    root_dir: String,
    port: Option<u16>,
    password: Option<String>,
    read_only: bool,
    default_lang: Option<String>,
) -> Result<ServerStatusDto, String> {
    let existing = {
        let mut guard = HTTP_RUNNING.lock();
        guard.take()
    };
    if let Some(s) = existing {
        let _ = s.shutdown_tx.send(());
    }

    let server = start_http_share_with_lang(
        PathBuf::from(root_dir),
        port,
        password,
        read_only,
        default_lang,
    )
    .await?;
    let actual_port = server.port;
    let share_token = server.share_token.clone();

    {
        let mut guard = HTTP_RUNNING.lock();
        *guard = Some(server);
    }

    let addresses = get_lan_ip_addresses();
    let primary_ip = addresses.first().cloned().unwrap_or_else(|| "127.0.0.1".to_string());
    let url = format!("http://{primary_ip}:{actual_port}/?token={share_token}");

    Ok(ServerStatusDto {
        running: true,
        port: actual_port,
        addresses,
        url,
    })
}

/// Discover LAN file servers (SMB, SFTP, WebDAV, FTP) via mDNS and subnet scan.
pub async fn discover_lan_services(timeout_ms: Option<u32>) -> Vec<LanServiceDto> {
    discover_lan_services_impl(timeout_ms.unwrap_or(2500))
        .await
        .into_iter()
        .map(|s| LanServiceDto {
            name: s.name,
            host: s.host,
            port: s.port,
            protocol: s.protocol,
            source: s.source,
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn stop_lan_http_server() -> bool {
    let mut guard = HTTP_RUNNING.lock();
    if let Some(server) = guard.take() {
        let _ = server.shutdown_tx.send(());
        true
    } else {
        false
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_lan_ip_list() -> Vec<String> {
    get_lan_ip_addresses()
}

/// Serve one root over loopback for media playback and return the base URL.
///
/// One server per root is reused across files so opening the next video does
/// not rebind a port. The URL includes the random access token.
pub async fn start_media_stream(root: String) -> Result<String, String> {
    let vfs = VfsRegistry::global().get_or_create(&root).await?;

    {
        let guard = STREAMS.lock();
        if let Some(map) = guard.as_ref() {
            if let Some(server) = map.get(&root) {
                return Ok(format!(
                    "http://127.0.0.1:{}/stream/{}/",
                    server.port, server.token
                ));
            }
        }
    }

    let no_cache = root.starts_with("vault://") || root.starts_with("archive://vault://");
    let server = start_stream_server_with_options(vfs, no_cache).await?;
    let url = format!(
        "http://127.0.0.1:{}/stream/{}/",
        server.port, server.token
    );

    let mut guard = STREAMS.lock();
    guard
        .get_or_insert_with(HashMap::new)
        .insert(root, server);

    Ok(url)
}

#[flutter_rust_bridge::frb(sync)]
pub fn stop_media_streams() {
    let mut guard = STREAMS.lock();
    if let Some(map) = guard.take() {
        for (_, server) in map {
            server.shutdown();
        }
    }
}

pub(crate) fn stop_media_streams_for_vault(vault_id: &str) {
    let vault_root = format!("vault://{vault_id}");
    let archive_exact = format!("archive://{vault_root}");
    let archive_prefix = format!("{archive_exact}/");
    let mut removed = Vec::new();
    {
        let mut guard = STREAMS.lock();
        if let Some(map) = guard.as_mut() {
            let keys: Vec<String> = map
                .keys()
                .filter(|k| {
                    *k == &vault_root || *k == &archive_exact || k.starts_with(&archive_prefix)
                })
                .cloned()
                .collect();
            for k in keys {
                if let Some(server) = map.remove(&k) {
                    removed.push(server);
                }
            }
        }
    }
    for server in removed {
        server.shutdown();
    }
}

#[derive(Debug, Clone)]
pub struct PeerInfoDto {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub host: String,
    pub port: u16,
    pub url: String,
}

#[derive(Debug, Clone)]
pub struct PeerOfferDto {
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

impl From<PeerTransferOffer> for PeerOfferDto {
    fn from(o: PeerTransferOffer) -> Self {
        Self {
            offer_id: o.offer_id,
            sender_name: o.sender_name,
            kind: o.kind,
            items: o.items,
            total_bytes: o.total_bytes,
            text_preview: o.text_preview,
            text_payload: o.text_payload,
            status: o.status,
            save_dir: o.save_dir,
            received_files: o.received_files,
        }
    }
}

/// Start a LAN WebDAV server exposing any VFS root (local, remote, or unlocked
/// vault) over HTTP so TV media players and desktop file managers can mount it.
pub async fn start_lan_webdav_server(
    root: String,
    rel_path: String,
    port: Option<u16>,
    username: Option<String>,
    password: Option<String>,
    read_only: bool,
) -> Result<ServerStatusDto, String> {
    let existing = {
        let mut guard = WEBDAV_RUNNING.lock();
        guard.take()
    };
    if let Some((srv, _, _)) = existing {
        let _ = srv.shutdown_tx.send(());
    }

    let vfs = VfsRegistry::global().get_or_create(&root).await?;
    let base_prefix = VfsPath::from_slash_path(&rel_path);
    let server = start_webdav_server(vfs, base_prefix, port, username, password, read_only).await?;
    let actual_port = server.port;
    let addresses = get_lan_ip_addresses();
    let primary_ip = addresses
        .first()
        .cloned()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let status = ServerStatusDto {
        running: true,
        port: actual_port,
        addresses,
        url: format!("http://{primary_ip}:{actual_port}/"),
    };

    {
        let mut guard = WEBDAV_RUNNING.lock();
        *guard = Some((server, status.clone(), root));
    }
    Ok(status)
}

#[flutter_rust_bridge::frb(sync)]
pub fn stop_lan_webdav_server() -> bool {
    let mut guard = WEBDAV_RUNNING.lock();
    if let Some((server, _, _)) = guard.take() {
        let _ = server.shutdown_tx.send(());
        true
    } else {
        false
    }
}

pub(crate) fn stop_webdav_for_vault(vault_id: &str) {
    let direct_prefix = format!("vault://{vault_id}");
    let archive_prefix = format!("archive://vault://{vault_id}");
    let mut guard = WEBDAV_RUNNING.lock();
    let matches = guard
        .as_ref()
        .map(|(_, _, root)| {
            root == &direct_prefix
                || root.starts_with(&format!("{direct_prefix}/"))
                || root == &archive_prefix
                || root.starts_with(&format!("{archive_prefix}/"))
        })
        .unwrap_or(false);
    if matches {
        if let Some((server, _, _)) = guard.take() {
            let _ = server.shutdown_tx.send(());
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn lan_webdav_status() -> Option<ServerStatusDto> {
    WEBDAV_RUNNING.lock().as_ref().map(|(_, st, _)| st.clone())
}

/// Start the LAN direct peer transfer receiver (HTTP server + UDP beacon).
pub async fn start_peer_receiver(
    device_name: String,
    save_dir: String,
    port: Option<u16>,
) -> Result<ServerStatusDto, String> {
    let existing = {
        let mut guard = PEER_RECEIVER.lock();
        guard.take()
    };
    if let Some((old, _)) = existing {
        old.shutdown();
    }

    let receiver = start_peer_receiver_impl(device_name, PathBuf::from(save_dir), port).await?;
    let actual_port = receiver.port;
    let addresses = get_lan_ip_addresses();
    let primary_ip = addresses
        .first()
        .cloned()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let status = ServerStatusDto {
        running: true,
        port: actual_port,
        addresses,
        url: format!("http://{primary_ip}:{actual_port}"),
    };
    {
        let mut guard = PEER_RECEIVER.lock();
        *guard = Some((receiver, status.clone()));
    }
    Ok(status)
}

#[flutter_rust_bridge::frb(sync)]
pub fn stop_peer_receiver() -> bool {
    let mut guard = PEER_RECEIVER.lock();
    if let Some((receiver, _)) = guard.take() {
        receiver.shutdown();
        true
    } else {
        false
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn peer_receiver_status() -> Option<ServerStatusDto> {
    PEER_RECEIVER.lock().as_ref().map(|(_, st)| st.clone())
}

pub async fn discover_lan_peers(timeout_ms: Option<u32>) -> Vec<PeerInfoDto> {
    let self_id = PEER_RECEIVER
        .lock()
        .as_ref()
        .map(|(r, _)| r.device_id.clone());
    discover_lan_peers_impl(timeout_ms.unwrap_or(1800), self_id.as_deref())
        .await
        .into_iter()
        .map(|p| {
            let url = format!("http://{}:{}", p.host, p.port);
            PeerInfoDto {
                device_id: p.device_id,
                device_name: p.device_name,
                platform: p.platform,
                host: p.host,
                port: p.port,
                url,
            }
        })
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn poll_peer_offers() -> Vec<PeerOfferDto> {
    PEER_RECEIVER
        .lock()
        .as_ref()
        .map(|(r, _)| r.list_offers().into_iter().map(PeerOfferDto::from).collect())
        .unwrap_or_default()
}

#[flutter_rust_bridge::frb(sync)]
pub fn respond_peer_offer(offer_id: String, accept: bool, save_dir: Option<String>) -> bool {
    PEER_RECEIVER
        .lock()
        .as_ref()
        .map(|(r, _)| r.respond_offer(&offer_id, accept, save_dir.as_deref()))
        .unwrap_or(false)
}

fn unique_send_filename(used: &mut std::collections::HashSet<String>, base: &str) -> String {
    if used.insert(base.to_string()) {
        return base.to_string();
    }
    let (stem, ext) = match base.rfind('.') {
        Some(idx) if idx > 0 => (&base[..idx], &base[idx..]),
        _ => (base, ""),
    };
    for i in 2u32..10000 {
        let cand = format!("{stem} ({i}){ext}");
        if used.insert(cand.clone()) {
            return cand;
        }
    }
    format!("{stem}_{}{ext}", uuid::Uuid::new_v4())
}

pub async fn send_peer_files(
    peer_url: String,
    sender_name: String,
    src_root: String,
    src_paths: Vec<String>,
) -> Result<u32, String> {
    let vfs = VfsRegistry::global().get_or_create(&src_root).await?;
    let mut mapped = Vec::with_capacity(src_paths.len());
    let mut used_names = std::collections::HashSet::new();
    for raw in src_paths {
        let vp = VfsPath::from_slash_path(&raw);
        let st = vfs.stat(&vp).await.map_err(|e| e.to_string())?;
        if st.kind == fm_core::EntryKind::Dir {
            continue;
        }
        let base_name = vp.name().unwrap_or("file.bin");
        let rel_name = unique_send_filename(&mut used_names, base_name);
        mapped.push((vp, rel_name));
    }
    if mapped.is_empty() {
        return Err("no regular files selected to send".to_string());
    }
    send_peer_files_impl(&peer_url, &sender_name, vfs, mapped).await
}

pub async fn send_peer_text(
    peer_url: String,
    sender_name: String,
    text: String,
) -> Result<(), String> {
    send_peer_text_impl(&peer_url, &sender_name, &text).await
}
