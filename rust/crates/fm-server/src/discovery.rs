//! LAN service auto-discovery via mDNS (DNS-SD) and fast local subnet probing.
//!
//! Discovers SMB (445), SFTP (22), WebDAV (80/443/5005/5006/8080), and FTP (21)
//! services on the local network so the remote connection wizard can pre-fill
//! host, port, and protocol with one click.

use std::collections::{BTreeMap, HashSet};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::{TcpStream, UdpSocket};
use tokio::sync::Semaphore;

use crate::http::get_lan_ip_addresses;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveredService {
    pub name: String,
    pub host: String,
    pub port: u16,
    /// Protocol tag matching RemoteConfig kinds: `"smb"`, `"sftp"`, `"webdav"`, `"ftp"`.
    pub protocol: String,
    /// Discovery method: `"mdns"` or `"scan"`.
    pub source: String,
}

const MDNS_ADDR: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 251);
const MDNS_PORT: u16 = 5353;

const MDNS_QUERIES: &[(&str, &str, u16)] = &[
    ("_smb._tcp.local", "smb", 445),
    ("_sftp-ssh._tcp.local", "sftp", 22),
    ("_webdav._tcp.local", "webdav", 5005),
    ("_webdavs._tcp.local", "webdav", 5006),
    ("_ftp._tcp.local", "ftp", 21),
];

const SCAN_PORTS: &[(u16, &str)] = &[
    (445, "smb"),
    (22, "sftp"),
    (21, "ftp"),
    (5005, "webdav"),
    (5006, "webdav"),
];

/// Discover SMB, SFTP, WebDAV, and FTP services on the local network.
pub async fn discover_lan_services(timeout_ms: u32) -> Vec<DiscoveredService> {
    let clamped_ms = timeout_ms.clamp(500, 8000) as u64;
    let mdns_budget = Duration::from_millis(clamped_ms.min(2500));
    let scan_budget = Duration::from_millis(clamped_ms);

    let (mdns_found, scan_found) = tokio::join!(
        query_mdns_services(mdns_budget),
        probe_local_subnets(scan_budget),
    );

    // Deduplicate by (host, port, protocol), preferring richer mDNS names.
    let mut by_key: BTreeMap<(String, u16, String), DiscoveredService> = BTreeMap::new();
    for svc in scan_found {
        by_key.insert((svc.host.clone(), svc.port, svc.protocol.clone()), svc);
    }
    for svc in mdns_found {
        by_key.insert((svc.host.clone(), svc.port, svc.protocol.clone()), svc);
    }

    let mut out: Vec<DiscoveredService> = by_key.into_values().collect();
    out.sort_by(|a, b| {
        a.protocol
            .cmp(&b.protocol)
            .then_with(|| a.host.cmp(&b.host))
            .then_with(|| a.port.cmp(&b.port))
    });
    out
}

/// Build a minimal RFC 1035 / RFC 6762 PTR query packet for `service_name`.
fn build_mdns_ptr_query(service_name: &str) -> Vec<u8> {
    let mut buf = Vec::with_capacity(64);
    // Header: ID=0, Flags=0 (standard query), QDCOUNT=1, AN/NS/AR=0
    buf.extend_from_slice(&[0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    for label in service_name.split('.') {
        if label.is_empty() || label.len() > 63 {
            continue;
        }
        buf.push(label.len() as u8);
        buf.extend_from_slice(label.as_bytes());
    }
    buf.push(0x00); // root label
    // QTYPE = PTR (12), QCLASS = IN (1) with unicast-response bit (0x8001)
    buf.extend_from_slice(&[0x00, 0x0c, 0x80, 0x01]);
    buf
}

fn read_dns_name(packet: &[u8], mut offset: usize) -> Option<(String, usize)> {
    let mut labels = Vec::new();
    let mut jumped = false;
    let mut end_offset = offset;
    let mut steps = 0;

    while offset < packet.len() && steps < 64 {
        steps += 1;
        let len = packet[offset];
        if len == 0 {
            if !jumped {
                end_offset = offset + 1;
            }
            break;
        }
        if (len & 0xC0) == 0xC0 {
            if offset + 1 >= packet.len() {
                return None;
            }
            let ptr = (((len & 0x3F) as usize) << 8) | (packet[offset + 1] as usize);
            if !jumped {
                end_offset = offset + 2;
                jumped = true;
            }
            offset = ptr;
        } else {
            let l = len as usize;
            offset += 1;
            if offset + l > packet.len() {
                return None;
            }
            labels.push(String::from_utf8_lossy(&packet[offset..offset + l]).into_owned());
            offset += l;
        }
    }
    Some((labels.join("."), end_offset))
}

fn protocol_for_service_name(name: &str) -> Option<(&'static str, u16)> {
    let lower = name.to_ascii_lowercase();
    if lower.contains("_smb._tcp") {
        Some(("smb", 445))
    } else if lower.contains("_sftp-ssh._tcp") || lower.contains("_ssh._tcp") {
        Some(("sftp", 22))
    } else if lower.contains("_webdavs._tcp") {
        Some(("webdav", 5006))
    } else if lower.contains("_webdav._tcp") {
        Some(("webdav", 5005))
    } else if lower.contains("_ftp._tcp") {
        Some(("ftp", 21))
    } else {
        None
    }
}

/// Parse an mDNS response packet and extract discovered services.
pub(crate) fn parse_mdns_response(packet: &[u8], src_ip: IpAddr) -> Vec<DiscoveredService> {
    if packet.len() < 12 {
        return Vec::new();
    }
    let qdcount = u16::from_be_bytes([packet[4], packet[5]]) as usize;
    let ancount = u16::from_be_bytes([packet[6], packet[7]]) as usize;
    let nscount = u16::from_be_bytes([packet[8], packet[9]]) as usize;
    let arcount = u16::from_be_bytes([packet[10], packet[11]]) as usize;
    let total_rrs = ancount.saturating_add(nscount).saturating_add(arcount);

    let mut offset = 12usize;
    for _ in 0..qdcount {
        let Some((_, next)) = read_dns_name(packet, offset) else {
            return Vec::new();
        };
        offset = next + 4;
        if offset > packet.len() {
            return Vec::new();
        }
    }

    let mut srv_records: Vec<(String, u16, String)> = Vec::new(); // (instance, port, target)
    let mut ptr_records: Vec<(String, String)> = Vec::new(); // (service_type, instance)
    let mut a_records: BTreeMap<String, String> = BTreeMap::new(); // hostname -> ipv4

    for _ in 0..total_rrs {
        let Some((rr_name, next)) = read_dns_name(packet, offset) else {
            break;
        };
        if next + 10 > packet.len() {
            break;
        }
        let rtype = u16::from_be_bytes([packet[next], packet[next + 1]]);
        let rdlen = u16::from_be_bytes([packet[next + 8], packet[next + 9]]) as usize;
        let rdata_start = next + 10;
        let rdata_end = rdata_start.saturating_add(rdlen);
        if rdata_end > packet.len() {
            break;
        }
        match rtype {
            1 if rdlen == 4 => {
                // A record
                let ip = Ipv4Addr::new(
                    packet[rdata_start],
                    packet[rdata_start + 1],
                    packet[rdata_start + 2],
                    packet[rdata_start + 3],
                );
                a_records.insert(rr_name.to_ascii_lowercase(), ip.to_string());
            }
            12 => {
                // PTR record
                if let Some((target, _)) = read_dns_name(packet, rdata_start) {
                    ptr_records.push((rr_name, target));
                }
            }
            33 if rdlen >= 6 => {
                // SRV record: priority(2), weight(2), port(2), target
                let port = u16::from_be_bytes([packet[rdata_start + 4], packet[rdata_start + 5]]);
                if let Some((target, _)) = read_dns_name(packet, rdata_start + 6) {
                    srv_records.push((rr_name, port, target));
                }
            }
            _ => {}
        }
        offset = rdata_end;
    }

    let mut results = Vec::new();
    for (instance, port, target) in srv_records {
        if let Some((protocol, default_port)) = protocol_for_service_name(&instance) {
            let host = a_records
                .get(&target.to_ascii_lowercase())
                .cloned()
                .unwrap_or_else(|| src_ip.to_string());
            let friendly = instance
                .split("._")
                .next()
                .unwrap_or(&instance)
                .trim()
                .to_string();
            results.push(DiscoveredService {
                name: if friendly.is_empty() { host.clone() } else { friendly },
                host,
                port: if port > 0 { port } else { default_port },
                protocol: protocol.to_string(),
                source: "mdns".to_string(),
            });
        }
    }

    if results.is_empty() {
        for (svc_type, instance) in ptr_records {
            if let Some((protocol, default_port)) = protocol_for_service_name(&svc_type) {
                let friendly = instance
                    .split("._")
                    .next()
                    .unwrap_or(&instance)
                    .trim()
                    .to_string();
                results.push(DiscoveredService {
                    name: if friendly.is_empty() {
                        src_ip.to_string()
                    } else {
                        friendly
                    },
                    host: src_ip.to_string(),
                    port: default_port,
                    protocol: protocol.to_string(),
                    source: "mdns".to_string(),
                });
            }
        }
    }

    results
}

async fn query_mdns_services(budget: Duration) -> Vec<DiscoveredService> {
    let socket = match UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0)).await {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };
    let _ = socket.set_multicast_loop_v4(true);
    let target = SocketAddr::V4(SocketAddrV4::new(MDNS_ADDR, MDNS_PORT));

    for (svc, _, _) in MDNS_QUERIES {
        let pkt = build_mdns_ptr_query(svc);
        let _ = socket.send_to(&pkt, target).await;
    }

    let mut found = Vec::new();
    let deadline = tokio::time::Instant::now() + budget;
    let mut buf = [0u8; 4096];
    loop {
        let now = tokio::time::Instant::now();
        if now >= deadline {
            break;
        }
        let rem = deadline - now;
        match tokio::time::timeout(rem, socket.recv_from(&mut buf)).await {
            Ok(Ok((n, peer))) => {
                found.extend(parse_mdns_response(&buf[..n], peer.ip()));
            }
            _ => break,
        }
    }
    found
}

async fn probe_local_subnets(budget: Duration) -> Vec<DiscoveredService> {
    let lan_ips = get_lan_ip_addresses();
    let mut prefixes: HashSet<[u8; 3]> = HashSet::new();
    let mut self_ips: HashSet<Ipv4Addr> = HashSet::new();

    for ip_str in lan_ips {
        if let Ok(ip) = ip_str.parse::<Ipv4Addr>() {
            if ip.is_loopback() || ip.is_link_local() {
                continue;
            }
            self_ips.insert(ip);
            let o = ip.octets();
            prefixes.insert([o[0], o[1], o[2]]);
        }
    }

    if prefixes.is_empty() {
        return Vec::new();
    }

    // Cap to at most 2 /24 subnets to keep probing fast and polite on multi-homed hosts.
    let prefixes: Vec<[u8; 3]> = prefixes.into_iter().take(2).collect();
    let sem = Arc::new(Semaphore::new(96));
    let connect_timeout = Duration::from_millis(220);

    let probe_all = async {
        let mut handles = Vec::new();
        for prefix in prefixes {
            for last in 1u8..=254u8 {
                let ip = Ipv4Addr::new(prefix[0], prefix[1], prefix[2], last);
                if self_ips.contains(&ip) {
                    continue;
                }
                for &(port, protocol) in SCAN_PORTS {
                    let sem = Arc::clone(&sem);
                    handles.push(tokio::spawn(async move {
                        let _permit = sem.acquire().await.ok()?;
                        let addr = SocketAddr::V4(SocketAddrV4::new(ip, port));
                        match tokio::time::timeout(connect_timeout, TcpStream::connect(addr)).await
                        {
                            Ok(Ok(_stream)) => Some(DiscoveredService {
                                name: format!("{} ({})", ip, protocol.to_ascii_uppercase()),
                                host: ip.to_string(),
                                port,
                                protocol: protocol.to_string(),
                                source: "scan".to_string(),
                            }),
                            _ => None,
                        }
                    }));
                }
            }
        }
        let mut out = Vec::new();
        for h in handles {
            if let Ok(Some(svc)) = h.await {
                out.push(svc);
            }
        }
        out
    };

    tokio::time::timeout(budget, probe_all)
        .await
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_valid_mdns_ptr_query() {
        let pkt = build_mdns_ptr_query("_smb._tcp.local");
        assert!(pkt.len() > 16);
        assert_eq!(&pkt[4..6], &[0x00, 0x01]); // QDCOUNT = 1
        assert_eq!(&pkt[pkt.len() - 4..], &[0x00, 0x0c, 0x80, 0x01]);
    }

    #[test]
    fn parses_mdns_srv_and_a_records() {
        // Construct a synthetic mDNS response with SRV + A record for MyNAS._smb._tcp.local
        let mut pkt = vec![
            0x00, 0x00, // ID
            0x84, 0x00, // Response, AA
            0x00, 0x00, // QDCOUNT=0
            0x00, 0x02, // ANCOUNT=2
            0x00, 0x00, // NSCOUNT=0
            0x00, 0x00, // ARCOUNT=0
        ];
        // RR1: MyNAS._smb._tcp.local SRV port 445 -> nas.local
        for l in ["MyNAS", "_smb", "_tcp", "local"] {
            pkt.push(l.len() as u8);
            pkt.extend_from_slice(l.as_bytes());
        }
        pkt.push(0);
        pkt.extend_from_slice(&33u16.to_be_bytes()); // SRV
        pkt.extend_from_slice(&1u16.to_be_bytes()); // IN
        pkt.extend_from_slice(&120u32.to_be_bytes()); // TTL
        let mut srv_rdata = vec![0, 0, 0, 0, 0x01, 0xBD]; // port 445
        for l in ["nas", "local"] {
            srv_rdata.push(l.len() as u8);
            srv_rdata.extend_from_slice(l.as_bytes());
        }
        srv_rdata.push(0);
        pkt.extend_from_slice(&(srv_rdata.len() as u16).to_be_bytes());
        pkt.extend_from_slice(&srv_rdata);

        // RR2: nas.local A 192.168.1.50
        for l in ["nas", "local"] {
            pkt.push(l.len() as u8);
            pkt.extend_from_slice(l.as_bytes());
        }
        pkt.push(0);
        pkt.extend_from_slice(&1u16.to_be_bytes()); // A
        pkt.extend_from_slice(&1u16.to_be_bytes()); // IN
        pkt.extend_from_slice(&120u32.to_be_bytes()); // TTL
        pkt.extend_from_slice(&4u16.to_be_bytes());
        pkt.extend_from_slice(&[192, 168, 1, 50]);

        let parsed = parse_mdns_response(&pkt, IpAddr::V4(Ipv4Addr::new(192, 168, 1, 50)));
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].name, "MyNAS");
        assert_eq!(parsed[0].host, "192.168.1.50");
        assert_eq!(parsed[0].port, 445);
        assert_eq!(parsed[0].protocol, "smb");
        assert_eq!(parsed[0].source, "mdns");
    }
}
