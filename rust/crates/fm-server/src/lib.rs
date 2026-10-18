//! Local network sharing services.
//!
//! The original app exposes an FTP server and an HTTP server that serve a
//! chosen directory with an optional random port and password. This crate owns
//! the server-side model; transport implementations land in M5.

use fm_core::VfsPath;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    Http,
    Ftp,
    Ftps,
}

#[derive(Debug, Clone)]
pub struct ServerConfig {
    pub protocol: Protocol,
    /// Directory being shared.
    pub root: VfsPath,
    /// `None` means the OS assigns a free port.
    pub port: Option<u16>,
    /// `None` means anonymous access.
    pub password: Option<String>,
    pub read_only: bool,
}

impl ServerConfig {
    /// Address shown to the user once the server is running.
    pub fn url(&self, host: &str, port: u16) -> String {
        let scheme = match self.protocol {
            Protocol::Http => "http",
            Protocol::Ftp => "ftp",
            Protocol::Ftps => "ftps",
        };
        format!("{scheme}://{host}:{port}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_matches_protocol() {
        let config = ServerConfig {
            protocol: Protocol::Ftp,
            root: VfsPath::root(),
            port: Some(2121),
            password: None,
            read_only: true,
        };
        assert_eq!(config.url("192.168.1.5", 2121), "ftp://192.168.1.5:2121");
    }
}
