use crate::registry::VfsRegistry;
use fm_server::{
    discover_lan_services as discover_lan_services_impl, get_lan_ip_addresses,
    start_http_share_with_lang, start_stream_server_with_options, RunningServer, StreamServer,
};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::PathBuf;

static HTTP_RUNNING: Mutex<Option<RunningServer>> = Mutex::new(None);
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
