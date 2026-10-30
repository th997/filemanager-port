//! Domain types shared by every backend and adapter.
//!
//! Identity is kept separate from display: [`LocationId`] identifies a
//! location, [`Location::display_name`] is presentation only. Paths stay in
//! backend-native form ([`VfsPath`]) and are never re-parsed from a display
//! string.

use serde::{Deserialize, Serialize};
use std::fmt;
use std::time::SystemTime;

/// Stable identifier for a location. Callers persist this, never the display
/// name.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct LocationId(pub String);

impl fmt::Display for LocationId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LocationKind {
    Local,
    Archive,
    Sftp,
    Ftp,
    Ftps,
    Smb,
    WebDav,
    S3,
    Oss,
}

/// A browsable root. `root` is the backend-native path of the location root.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Location {
    pub id: LocationId,
    pub kind: LocationKind,
    pub display_name: String,
    pub root: VfsPath,
}

/// Backend-native path inside a location.
///
/// `segments` are decoded path components. Keeping them as components rather
/// than a joined string means names containing `/`, `\`, or `:` survive a
/// round trip.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct VfsPath {
    segments: Vec<String>,
}

impl VfsPath {
    pub fn root() -> Self {
        Self {
            segments: Vec::new(),
        }
    }

    pub fn new(segments: impl IntoIterator<Item = impl Into<String>>) -> Self {
        Self {
            segments: segments.into_iter().map(Into::into).collect(),
        }
    }

    /// Parse an absolute path using `/` as the separator. Empty components are
    /// dropped so `/a//b` and `/a/b` are the same path.
    pub fn from_slash_path(path: &str) -> Self {
        Self::new(
            path.split('/')
                .filter(|segment| !segment.is_empty())
                .map(str::to_owned),
        )
    }

    pub fn segments(&self) -> &[String] {
        &self.segments
    }

    pub fn is_root(&self) -> bool {
        self.segments.is_empty()
    }

    pub fn name(&self) -> Option<&str> {
        self.segments.last().map(String::as_str)
    }

    pub fn join(&self, name: impl Into<String>) -> Self {
        let mut segments = Vec::with_capacity(self.segments.len() + 1);
        segments.extend_from_slice(&self.segments);
        segments.push(name.into());
        Self { segments }
    }

    pub fn parent(&self) -> Option<Self> {
        if self.is_root() {
            return None;
        }
        let mut segments = self.segments.clone();
        segments.pop();
        Some(Self { segments })
    }

    /// Whether `self` is `prefix` or a descendant of it, compared per segment
    /// so `/ab` is not considered inside `/a`.
    pub fn starts_with(&self, prefix: &Self) -> bool {
        self.segments.len() >= prefix.segments.len()
            && self.segments[..prefix.segments.len()] == prefix.segments[..]
    }

    /// Render with `/` separators. Display and native-path conversion only;
    /// do not parse the result back to recover identity.
    pub fn to_slash_string(&self) -> String {
        if self.segments.is_empty() {
            return "/".to_string();
        }
        let total_len = self.segments.iter().map(|s| s.len() + 1).sum::<usize>();
        let mut out = String::with_capacity(total_len);
        for segment in &self.segments {
            out.push('/');
            out.push_str(segment);
        }
        out
    }
}

impl fmt::Display for VfsPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.segments.is_empty() {
            return f.write_str("/");
        }
        for segment in &self.segments {
            f.write_str("/")?;
            f.write_str(segment)?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntryKind {
    File,
    Dir,
    Symlink,
    Other,
}

/// One directory entry. Unknown metadata stays `None` rather than being
/// replaced with a plausible-looking default.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Entry {
    pub name: String,
    pub path: VfsPath,
    pub kind: EntryKind,
    pub size: Option<u64>,
    pub modified: Option<SystemTime>,
    pub mode: Option<u32>,
    pub hidden: bool,
    /// True when the entry itself is a symbolic link, even if the link
    /// resolves to a file or directory. Broken links stay `EntryKind::Symlink`.
    pub is_symlink: bool,
    pub mime: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WriteMode {
    Create,
    Truncate,
    Append,
}

/// What a backend can actually do. UI hides unsupported actions instead of
/// branching on platform.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    pub read: bool,
    pub write: bool,
    pub rename: bool,
    pub copy: bool,
    pub mkdir: bool,
    pub remove: bool,
    pub serve_http: bool,
    pub serve_ftp: bool,
}

impl Capabilities {
    pub const READ_ONLY: Self = Self {
        read: true,
        write: false,
        rename: false,
        copy: false,
        mkdir: false,
        remove: false,
        serve_http: false,
        serve_ftp: false,
    };

    pub const READ_WRITE: Self = Self {
        read: true,
        write: true,
        rename: true,
        copy: true,
        mkdir: true,
        remove: true,
        serve_http: false,
        serve_ftp: false,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slash_path_round_trips_components() {
        let path = VfsPath::from_slash_path("/storage/emulated/0/Download");
        assert_eq!(path.segments(), ["storage", "emulated", "0", "Download"]);
        assert_eq!(path.to_slash_string(), "/storage/emulated/0/Download");
    }

    #[test]
    fn names_with_separators_survive_join() {
        let path = VfsPath::root().join("a/b").join("c\\d");
        assert_eq!(path.segments(), ["a/b", "c\\d"]);
        assert_eq!(path.name(), Some("c\\d"));
    }

    #[test]
    fn parent_of_root_is_none() {
        assert!(VfsPath::root().parent().is_none());
        let child = VfsPath::from_slash_path("/a");
        assert_eq!(child.parent(), Some(VfsPath::root()));
    }
}
