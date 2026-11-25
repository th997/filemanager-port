//! Network interface enumeration and LAN IP selection helpers.
//!
//! Prioritizes real physical LAN interfaces (Wi-Fi / Ethernet) while filtering
//! out TUN/VPN fake IPs (e.g. `198.18.0.0/15`), loopback, link-local, and
//! virtual/tunnelling interfaces.

use std::collections::BTreeMap;
use std::net::{IpAddr, Ipv4Addr, UdpSocket};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LanInterface {
    pub name: String,
    pub ip: Ipv4Addr,
    pub netmask: Ipv4Addr,
    pub broadcast: Ipv4Addr,
    pub is_virtual: bool,
}

pub fn is_virtual_interface(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.starts_with("lo")
        || lower.starts_with("utun")
        || lower.starts_with("tun")
        || lower.starts_with("tap")
        || lower.starts_with("wg")
        || lower.starts_with("awdl")
        || lower.starts_with("llw")
        || lower.starts_with("anpi")
        || lower.starts_with("bridge")
        || lower.starts_with("gif")
        || lower.starts_with("stf")
        || lower == "ap1"
        || lower.starts_with("docker")
        || lower.starts_with("br-")
        || lower.starts_with("veth")
        || lower.starts_with("virbr")
        || lower.starts_with("meta")
        || lower.starts_with("tailscale")
        || lower.starts_with("zt")
        || lower.starts_with("pdp_ip")
        || lower.starts_with("rmnet")
        || lower.starts_with("ccmni")
        || lower.starts_with("wwan")
        || lower.starts_with("cell")
        || lower.contains("virtual")
        || lower.contains("vmware")
        || lower.contains("vbox")
        || lower.contains("hyper-v")
}

pub fn is_unusable_lan_ip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    let is_fake_ip_bench = o[0] == 198 && (o[1] == 18 || o[1] == 19);
    ip.is_loopback()
        || ip.is_link_local()
        || ip.is_unspecified()
        || ip.is_multicast()
        || ip.is_broadcast()
        || is_fake_ip_bench
}

pub fn is_private_lan_ip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 10
        || (o[0] == 172 && (16..=31).contains(&o[1]))
        || (o[0] == 192 && o[1] == 168)
}

pub fn is_cgnat_ip(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 100 && (o[1] & 0xC0) == 64
}

pub fn same_subnet(a: Ipv4Addr, b: Ipv4Addr, mask: Ipv4Addr) -> bool {
    let m = u32::from(mask);
    (u32::from(a) & m) == (u32::from(b) & m)
}

#[cfg(unix)]
pub fn set_udp_multicast_if_v4(sock: &tokio::net::UdpSocket, ip: Ipv4Addr) {
    use std::os::unix::io::AsRawFd;
    let in_addr = libc::in_addr {
        s_addr: u32::from_ne_bytes(ip.octets()),
    };
    // SAFETY: sock holds an open socket FD and in_addr is initialized for IP_MULTICAST_IF.
    unsafe {
        let _ = libc::setsockopt(
            sock.as_raw_fd(),
            libc::IPPROTO_IP,
            libc::IP_MULTICAST_IF,
            (&in_addr as *const libc::in_addr).cast(),
            std::mem::size_of::<libc::in_addr>() as libc::socklen_t,
        );
    }
}

#[cfg(not(unix))]
pub fn set_udp_multicast_if_v4(_sock: &tokio::net::UdpSocket, _ip: Ipv4Addr) {}

fn compute_broadcast(ip: Ipv4Addr, mask: Ipv4Addr) -> Ipv4Addr {
    Ipv4Addr::from(u32::from(ip) | !u32::from(mask))
}

#[cfg(unix)]
struct IfAddrsGuard(*mut libc::ifaddrs);

#[cfg(unix)]
impl Drop for IfAddrsGuard {
    fn drop(&mut self) {
        if !self.0.is_null() {
            // SAFETY: pointer was returned by a successful libc::getifaddrs call.
            unsafe { libc::freeifaddrs(self.0) };
        }
    }
}

#[cfg(unix)]
unsafe fn sockaddr_to_ipv4(ptr: *const libc::sockaddr) -> Option<Ipv4Addr> {
    if ptr.is_null() {
        return None;
    }
    // SAFETY: caller ensures ptr points to a valid sockaddr in the ifaddrs list.
    let family = unsafe { (*ptr).sa_family } as i32;
    if family != libc::AF_INET {
        return None;
    }
    // SAFETY: sa_family == AF_INET guarantees a sockaddr_in layout.
    let addr_in = unsafe { &*(ptr as *const libc::sockaddr_in) };
    Some(Ipv4Addr::from(addr_in.sin_addr.s_addr.to_ne_bytes()))
}

#[cfg(unix)]
pub fn get_lan_interfaces() -> Vec<LanInterface> {
    let mut ifap: *mut libc::ifaddrs = std::ptr::null_mut();
    // SAFETY: ifap is a valid stack out-pointer.
    if unsafe { libc::getifaddrs(&mut ifap) } != 0 || ifap.is_null() {
        return Vec::new();
    }
    let _guard = IfAddrsGuard(ifap);

    let iff_up = libc::IFF_UP as u32;
    let iff_loopback = libc::IFF_LOOPBACK as u32;
    let mut by_ip: BTreeMap<Ipv4Addr, LanInterface> = BTreeMap::new();
    let mut cur = ifap;

    while !cur.is_null() {
        // SAFETY: linked list nodes remain valid for the lifetime of _guard.
        let ifa = unsafe { &*cur };
        cur = ifa.ifa_next;

        let flags = ifa.ifa_flags as u32;
        if (flags & iff_up) == 0 || (flags & iff_loopback) != 0 {
            continue;
        }
        if ifa.ifa_name.is_null() {
            continue;
        }
        // SAFETY: ifa_name is a NUL-terminated C string from getifaddrs.
        let name = unsafe { std::ffi::CStr::from_ptr(ifa.ifa_name) }
            .to_string_lossy()
            .into_owned();

        // SAFETY: ifa_addr points to sockaddr within the getifaddrs entry.
        let Some(ip) = (unsafe { sockaddr_to_ipv4(ifa.ifa_addr) }) else {
            continue;
        };
        if is_unusable_lan_ip(ip) {
            continue;
        }

        // SAFETY: ifa_netmask is null or points to sockaddr within the entry.
        let netmask = unsafe { sockaddr_to_ipv4(ifa.ifa_netmask) }
            .filter(|m| !m.is_unspecified())
            .unwrap_or_else(|| Ipv4Addr::new(255, 255, 255, 0));
        let broadcast = compute_broadcast(ip, netmask);
        let is_virtual = is_virtual_interface(&name);

        let entry = LanInterface {
            name,
            ip,
            netmask,
            broadcast,
            is_virtual,
        };
        match by_ip.get(&ip) {
            Some(existing) if !existing.is_virtual && entry.is_virtual => {}
            _ => {
                by_ip.insert(ip, entry);
            }
        }
    }

    let mut out: Vec<LanInterface> = by_ip.into_values().collect();
    out.sort_by_key(|iface| {
        (
            iface.is_virtual,
            !is_private_lan_ip(iface.ip),
            is_cgnat_ip(iface.ip),
            iface.name.clone(),
            iface.ip.octets(),
        )
    });
    out
}

#[cfg(not(unix))]
pub fn get_lan_interfaces() -> Vec<LanInterface> {
    Vec::new()
}

pub fn get_lan_ip_addresses() -> Vec<String> {
    let ifaces = get_lan_interfaces();
    let physical: Vec<String> = ifaces
        .iter()
        .filter(|i| !i.is_virtual)
        .map(|i| i.ip.to_string())
        .collect();
    if !physical.is_empty() {
        return physical;
    }

    let virtual_ips: Vec<String> = ifaces
        .iter()
        .filter(|i| i.is_virtual)
        .map(|i| i.ip.to_string())
        .collect();
    if !virtual_ips.is_empty() {
        return virtual_ips;
    }

    let mut ips = Vec::new();
    for target in [
        "8.8.8.8:80",
        "192.168.1.1:80",
        "192.168.0.1:80",
        "10.0.0.1:80",
        "172.16.0.1:80",
    ] {
        if let Ok(socket) = UdpSocket::bind("0.0.0.0:0") {
            if socket.connect(target).is_ok() {
                if let Ok(local_addr) = socket.local_addr() {
                    if let IpAddr::V4(ip) = local_addr.ip() {
                        let s = ip.to_string();
                        if !is_unusable_lan_ip(ip) && !ips.contains(&s) {
                            ips.push(s);
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

pub fn select_best_peer_ip(
    src_ip: IpAddr,
    advertised_ips: &[String],
    local_ifaces: &[LanInterface],
) -> Option<Ipv4Addr> {
    let mut candidates: Vec<(Ipv4Addr, bool)> = Vec::new();
    if let IpAddr::V4(v4) = src_ip {
        if !is_unusable_lan_ip(v4) {
            candidates.push((v4, true));
        }
    }
    for raw in advertised_ips {
        if let Ok(v4) = raw.trim().parse::<Ipv4Addr>() {
            if !is_unusable_lan_ip(v4) && !candidates.iter().any(|(ip, _)| *ip == v4) {
                candidates.push((v4, false));
            }
        }
    }

    candidates
        .into_iter()
        .max_by_key(|(cand, is_src)| {
            let matches_physical_subnet = local_ifaces
                .iter()
                .any(|iface| !iface.is_virtual && same_subnet(*cand, iface.ip, iface.netmask));
            (
                matches_physical_subnet,
                is_private_lan_ip(*cand),
                !is_cgnat_ip(*cand),
                *is_src,
            )
        })
        .map(|(ip, _)| ip)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filters_fake_and_link_local_ips_and_virtual_nics() {
        assert!(is_unusable_lan_ip(Ipv4Addr::new(198, 18, 0, 1)));
        assert!(is_unusable_lan_ip(Ipv4Addr::new(198, 19, 12, 34)));
        assert!(is_unusable_lan_ip(Ipv4Addr::new(169, 254, 1, 2)));
        assert!(is_unusable_lan_ip(Ipv4Addr::new(127, 0, 0, 1)));
        assert!(!is_unusable_lan_ip(Ipv4Addr::new(10, 10, 10, 117)));
        assert!(!is_unusable_lan_ip(Ipv4Addr::new(192, 168, 1, 50)));

        assert!(is_virtual_interface("utun0"));
        assert!(is_virtual_interface("awdl0"));
        assert!(is_virtual_interface("docker0"));
        assert!(!is_virtual_interface("en0"));
        assert!(!is_virtual_interface("wlan0"));
    }

    #[test]
    fn select_best_peer_ip_prefers_same_physical_subnet_over_proxy_or_cgnat() {
        let local = vec![LanInterface {
            name: "en0".to_string(),
            ip: Ipv4Addr::new(10, 10, 10, 117),
            netmask: Ipv4Addr::new(255, 255, 255, 0),
            broadcast: Ipv4Addr::new(10, 10, 10, 255),
            is_virtual: false,
        }];

        let picked = select_best_peer_ip(
            IpAddr::V4(Ipv4Addr::new(198, 18, 0, 1)),
            &[
                "198.18.0.1".to_string(),
                "169.254.1.2".to_string(),
                "100.64.0.5".to_string(),
                "10.10.10.20".to_string(),
            ],
            &local,
        );
        assert_eq!(picked, Some(Ipv4Addr::new(10, 10, 10, 20)));

        let only_bad = select_best_peer_ip(
            IpAddr::V4(Ipv4Addr::new(198, 18, 0, 1)),
            &["169.254.5.6".to_string(), "127.0.0.1".to_string()],
            &local,
        );
        assert_eq!(only_bad, None);
    }
}
