//! Archive backend.
//!
//! Format support is deliberately pure Rust so the same code builds for
//! Android and iOS without a system libarchive. Readers for zip, tar and
//! 7z land in M3; this crate currently defines the format registry so callers
//! and UI can be written against a stable surface.

use fm_core::LocationKind;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArchiveFormat {
    Zip,
    Tar,
    TarGz,
    SevenZip,
    Epub,
}

impl ArchiveFormat {
    /// Pick a reader from a file name. Returns `None` when the extension is not
    /// one this backend claims; callers must not guess.
    pub fn from_name(name: &str) -> Option<Self> {
        let lower = name.to_ascii_lowercase();
        if lower.ends_with(".tar.gz") || lower.ends_with(".tgz") {
            return Some(Self::TarGz);
        }
        if lower.ends_with(".tar") {
            return Some(Self::Tar);
        }
        if lower.ends_with(".epub") {
            return Some(Self::Epub);
        }
        if lower.ends_with(".7z") {
            return Some(Self::SevenZip);
        }
        // APK, APKM, APKS and OBB are ZIP containers.
        const ZIP_SUFFIXES: [&str; 7] =
            [".zip", ".jar", ".apk", ".apkm", ".apks", ".obb", ".cbz"];
        ZIP_SUFFIXES
            .iter()
            .find(|suffix| lower.ends_with(*suffix))
            .map(|_| Self::Zip)
    }

    pub fn location_kind(self) -> LocationKind {
        LocationKind::Archive
    }
}

/// Formats the app deliberately does not claim. RAR needs a separate decoder;
/// reporting it explicitly is better than a generic open failure.
pub fn is_known_unsupported(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    lower.ends_with(".rar") || lower.ends_with(".cbr")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognises_container_formats() {
        assert_eq!(ArchiveFormat::from_name("a.ZIP"), Some(ArchiveFormat::Zip));
        assert_eq!(ArchiveFormat::from_name("app.apks"), Some(ArchiveFormat::Zip));
        assert_eq!(ArchiveFormat::from_name("x.tar.gz"), Some(ArchiveFormat::TarGz));
        assert_eq!(ArchiveFormat::from_name("x.epub"), Some(ArchiveFormat::Epub));
        assert_eq!(ArchiveFormat::from_name("x.txt"), None);
    }

    #[test]
    fn rar_is_reported_separately() {
        assert!(is_known_unsupported("movie.RAR"));
        assert!(!is_known_unsupported("movie.zip"));
    }
}
