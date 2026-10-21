//! Local filesystem backend rooted at a native path.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use tokio::io::{AsyncRead, AsyncWrite};

pub struct LocalFs {
    root: PathBuf,
    capabilities: Capabilities,
}

impl LocalFs {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            capabilities: Capabilities::READ_WRITE,
        }
    }

    pub fn read_only(root: impl Into<PathBuf>) -> Self {
        Self {
            root: root.into(),
            capabilities: Capabilities::READ_ONLY,
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Resolve a backend path under the root.
    ///
    /// Segments are already decoded components, so joining is direct. A
    /// component of `..` or `.` would escape the root; reject it rather than
    /// silently normalising.
    fn resolve(&self, path: &VfsPath) -> VfsResult<PathBuf> {
        let mut native = self.root.clone();
        for segment in path.segments() {
            // A segment is one path component. Anything containing a separator
            // or a drive prefix would let a crafted archive/remote name escape
            // the granted root (notably on Windows, where `Path::push` treats
            // `C:` and `\\server` as new roots).
            #[cfg(windows)]
            let unsafe_segment = segment.contains('\\') || segment.contains(':');
            #[cfg(not(windows))]
            let unsafe_segment = false;
            if segment.is_empty()
                || segment == "."
                || segment == ".."
                || segment.contains('/')
                || segment.contains('\0')
                || unsafe_segment
            {
                return Err(VfsError::PermissionDenied { path: path.clone() });
            }
            native.push(segment);
        }
        Ok(native)
    }

    fn io_error(&self, path: &VfsPath, source: std::io::Error) -> VfsError {
        match source.kind() {
            std::io::ErrorKind::NotFound => VfsError::NotFound { path: path.clone() },
            std::io::ErrorKind::PermissionDenied => {
                VfsError::PermissionDenied { path: path.clone() }
            }
            _ => VfsError::Backend {
                path: path.clone(),
                source,
            },
        }
    }
}

fn entry_from_metadata(path: VfsPath, name: String, metadata: &std::fs::Metadata) -> Entry {
    let kind = if metadata.is_dir() {
        EntryKind::Dir
    } else if metadata.is_file() {
        EntryKind::File
    } else if metadata.file_type().is_symlink() {
        EntryKind::Symlink
    } else {
        EntryKind::Other
    };
    let hidden = is_hidden_name(&name);
    Entry {
        name,
        path,
        kind,
        size: if metadata.is_file() {
            Some(metadata.len())
        } else {
            None
        },
        modified: metadata.modified().ok(),
        mode: mode_of(metadata),
        hidden,
        mime: None,
    }
}

#[cfg(unix)]
fn mode_of(metadata: &std::fs::Metadata) -> Option<u32> {
    use std::os::unix::fs::PermissionsExt;
    Some(metadata.permissions().mode())
}

#[cfg(not(unix))]
fn mode_of(_metadata: &std::fs::Metadata) -> Option<u32> {
    None
}

fn is_hidden_name(name: &str) -> bool {
    name.starts_with('.')
}

#[async_trait]
impl Vfs for LocalFs {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let native = self.resolve(dir)?;
        let mut reader = tokio::fs::read_dir(&native)
            .await
            .map_err(|error| self.io_error(dir, error))?;
        let mut entries = Vec::new();
        while let Some(item) = reader
            .next_entry()
            .await
            .map_err(|error| self.io_error(dir, error))?
        {
            let name = item.file_name().to_string_lossy().into_owned();
            let child = dir.join(name.clone());
            // Follow symlinks so links to directories list as directories and
            // links to files report the target's size. `DirEntry::metadata`
            // does not follow links, which made every link look like a plain
            // file the UI could not open. Broken links fall back to link
            // metadata and stay `EntryKind::Symlink`.
            let metadata = match tokio::fs::metadata(item.path()).await {
                Ok(metadata) => metadata,
                Err(_) => match tokio::fs::symlink_metadata(item.path()).await {
                    Ok(meta) => meta,
                    Err(_) => continue,
                },
            };
            entries.push(entry_from_metadata(child, name, &metadata));
        }
        entries.sort_by(|a, b| {
            let a_dir = a.kind == EntryKind::Dir;
            let b_dir = b.kind == EntryKind::Dir;
            b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
        });
        Ok(entries)
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let native = self.resolve(path)?;
        let metadata = tokio::fs::metadata(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        let name = path.name().unwrap_or("").to_owned();
        Ok(entry_from_metadata(path.clone(), name, &metadata))
    }

    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let native = self.resolve(path)?;
        let file = tokio::fs::File::open(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        Ok(Box::new(file))
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        use tokio::io::{AsyncReadExt, AsyncSeekExt};

        let native = self.resolve(path)?;
        let mut file = tokio::fs::File::open(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        if offset > 0 {
            file.seek(std::io::SeekFrom::Start(offset))
                .await
                .map_err(|error| self.io_error(path, error))?;
        }
        Ok(match length {
            Some(len) => Box::new(file.take(len)),
            None => Box::new(file),
        })
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        if !self.capabilities.write {
            return Err(VfsError::Unsupported {
                operation: "write",
            });
        }
        let native = self.resolve(path)?;
        let mut options = tokio::fs::OpenOptions::new();
        options.write(true).create(true);
        match mode {
            WriteMode::Create => {
                options.create_new(true);
            }
            WriteMode::Truncate => {
                options.truncate(true);
            }
            WriteMode::Append => {
                options.append(true);
            }
        }
        let file = options
            .open(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        Ok(Box::new(file))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        if !self.capabilities.mkdir {
            return Err(VfsError::Unsupported { operation: "mkdir" });
        }
        let native = self.resolve(path)?;
        tokio::fs::create_dir(&native)
            .await
            .map_err(|error| self.io_error(path, error))
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        if !self.capabilities.remove {
            return Err(VfsError::Unsupported {
                operation: "remove",
            });
        }
        let native = self.resolve(path)?;
        let metadata = tokio::fs::symlink_metadata(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        let result = if metadata.file_type().is_symlink() {
            #[cfg(windows)]
            {
                if metadata.is_dir() {
                    tokio::fs::remove_dir(&native).await
                } else {
                    tokio::fs::remove_file(&native).await
                }
            }
            #[cfg(not(windows))]
            {
                tokio::fs::remove_file(&native).await
            }
        } else if metadata.is_dir() {
            tokio::fs::remove_dir_all(&native).await
        } else {
            tokio::fs::remove_file(&native).await
        };
        result.map_err(|error| self.io_error(path, error))
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        if !self.capabilities.rename {
            return Err(VfsError::Unsupported {
                operation: "rename",
            });
        }
        let from_native = self.resolve(from)?;
        let to_native = self.resolve(to)?;
        tokio::fs::rename(&from_native, &to_native)
            .await
            .map_err(|error| self.io_error(from, error))
    }
}

/// Convenience for callers that want a modification time without pulling in
/// the trait.
pub fn modified_of(metadata: &std::fs::Metadata) -> Option<SystemTime> {
    metadata.modified().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::AsyncWriteExt;

    fn fixture() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("b.txt"), b"hello").unwrap();
        std::fs::write(dir.path().join("a.txt"), b"hi").unwrap();
        std::fs::write(dir.path().join(".hidden"), b"").unwrap();
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        std::fs::File::create(dir.path().join("sub/child")).unwrap();
        dir
    }

    #[tokio::test]
    async fn lists_system_root() {
        let fs = LocalFs::new("/");
        let entries = fs.list(&VfsPath::root()).await.unwrap();
        assert!(!entries.is_empty());
    }

    #[tokio::test]
    async fn lists_directories_first_then_names() {
        let dir = fixture();
        let fs = LocalFs::new(dir.path());
        let entries = fs.list(&VfsPath::root()).await.unwrap();
        let names: Vec<_> = entries.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, ["sub", ".hidden", "a.txt", "b.txt"]);
        assert_eq!(entries[0].kind, EntryKind::Dir);
    }

    #[tokio::test]
    async fn stat_reports_size_and_hidden() {
        let dir = fixture();
        let fs = LocalFs::new(dir.path());
        let entry = fs.stat(&VfsPath::from_slash_path("/b.txt")).await.unwrap();
        assert_eq!(entry.size, Some(5));
        assert!(!entry.hidden);
        let hidden = fs.stat(&VfsPath::from_slash_path("/.hidden")).await.unwrap();
        assert!(hidden.hidden);
    }

    #[tokio::test]
    async fn parent_segments_are_rejected() {
        let dir = fixture();
        let fs = LocalFs::new(dir.path());
        let escape = VfsPath::new(["..", "etc", "passwd"]);
        assert!(matches!(
            fs.stat(&escape).await,
            Err(VfsError::PermissionDenied { .. })
        ));
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn list_follows_symlinks() {
        let dir = fixture();
        std::os::unix::fs::symlink(dir.path().join("sub"), dir.path().join("link_dir")).unwrap();
        std::os::unix::fs::symlink(dir.path().join("b.txt"), dir.path().join("link_file"))
            .unwrap();
        std::os::unix::fs::symlink(dir.path().join("missing"), dir.path().join("link_broken"))
            .unwrap();

        let fs = LocalFs::new(dir.path());
        let entries = fs.list(&VfsPath::root()).await.unwrap();
        let find = |name: &str| entries.iter().find(|e| e.name == name).unwrap();

        assert_eq!(find("link_dir").kind, EntryKind::Dir);
        assert_eq!(find("link_file").kind, EntryKind::File);
        assert_eq!(find("link_file").size, Some(5));
        assert_eq!(find("link_broken").kind, EntryKind::Symlink);
    }

    #[tokio::test]
    async fn read_only_backend_refuses_writes() {
        let dir = fixture();
        let fs = LocalFs::read_only(dir.path());
        let result = fs
            .open_write(&VfsPath::from_slash_path("/new.txt"), WriteMode::Create)
            .await;
        assert!(matches!(result, Err(VfsError::Unsupported { .. })));
    }

    #[tokio::test]
    async fn write_then_read_round_trips() {
        let dir = fixture();
        let fs = LocalFs::new(dir.path());
        let path = VfsPath::from_slash_path("/out.txt");
        let mut writer = fs.open_write(&path, WriteMode::Create).await.unwrap();
        writer.write_all(b"data").await.unwrap();
        drop(writer);
        let mut reader = fs.open_read(&path).await.unwrap();
        let mut buf = String::new();
        tokio::io::AsyncReadExt::read_to_string(&mut reader, &mut buf)
            .await
            .unwrap();
        assert_eq!(buf, "data");
    }
}
