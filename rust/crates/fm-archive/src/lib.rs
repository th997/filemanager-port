//! Archive backend.

pub mod archive_fs;
pub mod ops;

use fm_core::LocationKind;

pub use archive_fs::ArchiveFs;
pub use ops::{create_zip, extract_archive};

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
    use fm_vfs::Vfs;

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

    #[test]
    fn zip_archive_roundtrip() {
        let temp_dir = tempfile::tempdir().unwrap();
        let src_file = temp_dir.path().join("test.txt");
        std::fs::write(&src_file, b"archive data content").unwrap();

        let zip_file = temp_dir.path().join("output.zip");
        create_zip(&[src_file], &zip_file).unwrap();

        let fs = ArchiveFs::open(&zip_file).unwrap();
        let entries = tokio::runtime::Runtime::new()
            .unwrap()
            .block_on(fs.list(&fm_core::VfsPath::root()))
            .unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, "test.txt");

        let content = fs.read_entry_bytes(&entries[0].path).unwrap();
        assert_eq!(content, b"archive data content");
    }

    #[test]
    fn range_read_skips_into_zip_entry() {
        use tokio::io::AsyncReadExt;

        let temp_dir = tempfile::tempdir().unwrap();
        let src_file = temp_dir.path().join("test.txt");
        std::fs::write(&src_file, b"0123456789abcdef").unwrap();

        let zip_file = temp_dir.path().join("output.zip");
        create_zip(&[src_file], &zip_file).unwrap();

        let fs = ArchiveFs::open(&zip_file).unwrap();
        let path = fm_core::VfsPath::from_slash_path("test.txt");
        let runtime = tokio::runtime::Runtime::new().unwrap();
        let bytes = runtime.block_on(async {
            let mut reader = fs.open_read_range(&path, 4, Some(6)).await.unwrap();
            let mut buf = Vec::new();
            reader.read_to_end(&mut buf).await.unwrap();
            buf
        });
        assert_eq!(bytes, b"456789");
    }
}
