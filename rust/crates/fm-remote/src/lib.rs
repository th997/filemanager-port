//! Remote protocol backends.
//!
//! Connection parameters are modelled once so the UI and keychain layers do
//! not grow per-protocol branches. Backends are added in M4.

use fm_core::LocationKind;

/// Credentials are kept out of logs and Debug output.
#[derive(Clone)]
pub enum Credential {
    Anonymous,
    Password { username: String, password: String },
    PrivateKey { username: String, key: String, passphrase: Option<String> },
}

impl std::fmt::Debug for Credential {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Anonymous => f.write_str("Credential::Anonymous"),
            Self::Password { username, .. } => f
                .debug_struct("Credential::Password")
                .field("username", username)
                .field("password", &"<redacted>")
                .finish(),
            Self::PrivateKey { username, .. } => f
                .debug_struct("Credential::PrivateKey")
                .field("username", username)
                .field("key", &"<redacted>")
                .finish(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct RemoteSpec {
    pub kind: LocationKind,
    pub host: String,
    pub port: u16,
    pub root: String,
    pub credential: Credential,
}

impl RemoteSpec {
    /// Default port per protocol. Unknown kinds return `None` rather than a
    /// guessed value.
    pub fn default_port(kind: LocationKind) -> Option<u16> {
        match kind {
            LocationKind::Sftp => Some(22),
            LocationKind::Ftp => Some(21),
            LocationKind::Ftps => Some(990),
            LocationKind::Smb => Some(445),
            LocationKind::WebDav => Some(443),
            LocationKind::Local | LocationKind::Archive => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_redacts_secrets() {
        let credential = Credential::Password {
            username: "u".into(),
            password: "hunter2".into(),
        };
        let rendered = format!("{credential:?}");
        assert!(!rendered.contains("hunter2"));
        assert!(rendered.contains("<redacted>"));
    }

    #[test]
    fn default_ports_are_protocol_specific() {
        assert_eq!(RemoteSpec::default_port(LocationKind::Sftp), Some(22));
        assert_eq!(RemoteSpec::default_port(LocationKind::Smb), Some(445));
        assert_eq!(RemoteSpec::default_port(LocationKind::Local), None);
    }
}
