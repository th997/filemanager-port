//! Local filesystem backend rooted at a native path.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use tokio::io::{AsyncRead, AsyncWrite};

pub struct LocalFs {
    root: PathBuf,
    canonical_root: Option<PathBuf>,
    capabilities: Capabilities,
}

impl LocalFs {
    /// Reject special files (FIFOs, sockets, devices) before opening:
    /// `File::open` on a FIFO blocks until a writer appears, which in
    /// an async app means an operation that never returns. Only
    /// regular files may be opened for reading. (A `/dev/null`-style
    /// char device would "work", but nothing a file manager does with
    /// one is meaningful.)
    async fn ensure_regular_file(&self, path: &VfsPath, native: &Path) -> VfsResult<()> {
        let metadata = tokio::fs::metadata(native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        if !metadata.is_file() {
            return Err(VfsError::Unsupported {
                operation: "open a special file (device, pipe or socket)",
            });
        }
        Ok(())
    }

    pub fn new(root: impl Into<PathBuf>) -> Self {
        let root = root.into();
        let canonical_root = root.canonicalize().ok();
        Self {
            root,
            canonical_root,
            capabilities: Capabilities::READ_WRITE,
        }
    }

    pub fn read_only(root: impl Into<PathBuf>) -> Self {
        let root = root.into();
        let canonical_root = root.canonicalize().ok();
        Self {
            root,
            canonical_root,
            capabilities: Capabilities::READ_ONLY,
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Join a backend path under the root, lexically.
    ///
    /// Segments are already decoded components, so joining is direct. A
    /// component of `..` or `.` would escape the root; reject it rather than
    /// silently normalising.
    fn join_lexical(&self, path: &VfsPath) -> VfsResult<PathBuf> {
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

    /// Resolve a backend path under the root.
    ///
    /// On top of the lexical checks, the real location must stay inside
    /// the root: a symlink planted inside the root (synced in, extracted
    /// from an archive, ...) otherwise lets reads, writes and recursive
    /// deletes walk straight out of the granted directory. The deepest
    /// existing ancestor is canonicalised and compared; anything below it
    /// is made of already-validated plain names and cannot escape.
    fn resolve(&self, path: &VfsPath) -> VfsResult<PathBuf> {
        let native = self.join_lexical(path)?;
        self.check_contained(path, &native, true)?;
        Ok(native)
    }

    /// Like `resolve`, but the final component itself may be a symlink.
    /// Operations that act on the directory entry — stat, remove, rename —
    /// must be able to see and manipulate links themselves, so only the
    /// parent chain is required to stay inside the root.
    fn resolve_parent(&self, path: &VfsPath) -> VfsResult<PathBuf> {
        let native = self.join_lexical(path)?;
        self.check_contained(path, &native, false)?;
        Ok(native)
    }

    fn check_contained(
        &self,
        path: &VfsPath,
        native: &Path,
        include_final: bool,
    ) -> VfsResult<()> {
        let canonical_root = match &self.canonical_root {
            Some(cr) => cr,
            None => {
                // The root could not be canonicalised when the backend was
                // built (usually because it does not exist yet). Creating a
                // brand-new entry below a non-existent root is safe; touching
                // an existing entry we cannot verify is not. Fail closed.
                if std::fs::symlink_metadata(native).is_ok() {
                    return Err(VfsError::PermissionDenied { path: path.clone() });
                }
                return Ok(());
            }
        };
        let mut existing = if include_final || path.is_root() {
            native.to_path_buf()
        } else {
            native
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| native.to_path_buf())
        };
        // symlink_metadata (not `exists`) so a dangling link counts as an
        // existing entry and is checked rather than skipped.
        while std::fs::symlink_metadata(&existing).is_err() {
            if !existing.pop() {
                return Err(VfsError::PermissionDenied { path: path.clone() });
            }
        }
        // If the deepest existing ancestor cannot be resolved we cannot
        // prove containment — refuse instead of silently trusting it.
        let canonical = existing.canonicalize().map_err(|_| {
            VfsError::PermissionDenied { path: path.clone() }
        })?;
        if !canonical.starts_with(canonical_root) {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        Ok(())
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

fn entry_from_metadata(
    path: VfsPath,
    name: String,
    metadata: &std::fs::Metadata,
    is_symlink: bool,
) -> Entry {
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
        is_symlink,
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
        let dir_clone = dir.clone();
        tokio::task::spawn_blocking(move || {
            let read_dir = std::fs::read_dir(&native).map_err(|error| VfsError::Backend {
                path: dir_clone.clone(),
                source: error,
            })?;
            let mut entries = Vec::new();
            for item_res in read_dir {
                let item = match item_res {
                    Ok(i) => i,
                    Err(_) => continue,
                };
                let name = item.file_name().to_string_lossy().into_owned();
                let child = dir_clone.join(name.clone());

                let file_type = item.file_type().ok();
                let is_symlink = file_type.map(|ft| ft.is_symlink()).unwrap_or(false);

                let metadata = if is_symlink {
                    // Follow symlink to get target metadata; if broken, keep symlink metadata
                    std::fs::metadata(item.path())
                        .or_else(|_| std::fs::symlink_metadata(item.path()))
                        .ok()
                } else {
                    item.metadata().ok()
                };

                let Some(meta) = metadata else {
                    continue;
                };

                entries.push(entry_from_metadata(child, name, &meta, is_symlink));
            }
            entries.sort_unstable_by(|a, b| {
                let a_dir = a.kind == EntryKind::Dir;
                let b_dir = b.kind == EntryKind::Dir;
                b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
            });
            Ok(entries)
        })
        .await
        .map_err(|join_err| VfsError::Backend {
            path: dir.clone(),
            source: std::io::Error::other(join_err.to_string()),
        })?
    }

    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        let (entries, has_more, _) = self.list_paged_with_total(dir, page, page_size).await?;
        Ok((entries, has_more))
    }

    async fn list_paged_with_total(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool, Option<u32>)> {
        let native = self.resolve(dir)?;
        let dir_clone = dir.clone();
        let page = page.max(1);
        let page_size = page_size.max(1) as usize;
        let skip = ((page - 1) as usize).saturating_mul(page_size);

        tokio::task::spawn_blocking(move || {
            let read_dir = std::fs::read_dir(&native).map_err(|error| VfsError::Backend {
                path: dir_clone.clone(),
                source: error,
            })?;

            // Pass 1: collect lightweight (is_dir_hint, name, path, is_symlink) without
            // calling full stat() on entries outside the requested page window.
            let mut lightweight: Vec<(bool, String, std::path::PathBuf, bool)> = Vec::new();
            for item_res in read_dir {
                let item = match item_res {
                    Ok(i) => i,
                    Err(_) => continue,
                };
                let name = item.file_name().to_string_lossy().into_owned();
                let path = item.path();
                let file_type = item.file_type().ok();
                let is_symlink = file_type.map(|ft| ft.is_symlink()).unwrap_or(false);
                let is_dir = if is_symlink {
                    std::fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false)
                } else {
                    file_type.map(|ft| ft.is_dir()).unwrap_or(false)
                };
                lightweight.push((is_dir, name, path, is_symlink));
            }

            lightweight.sort_unstable_by(|a, b| {
                fm_core::compare_dir_and_name(a.0, &a.1, b.0, &b.1, true)
            });

            let total = lightweight.len();
            let has_more = skip.saturating_add(page_size) < total;
            let mut entries = Vec::with_capacity(page_size.min(total.saturating_sub(skip)));

            // Pass 2: call metadata() only for entries in the requested page slice.
            for (_, name, path, is_symlink) in lightweight.into_iter().skip(skip).take(page_size) {
                let metadata = if is_symlink {
                    std::fs::metadata(&path)
                        .or_else(|_| std::fs::symlink_metadata(&path))
                        .ok()
                } else {
                    std::fs::metadata(&path).ok()
                };
                let Some(meta) = metadata else {
                    continue;
                };
                let child = dir_clone.join(name.clone());
                entries.push(entry_from_metadata(child, name, &meta, is_symlink));
            }

            Ok((entries, has_more, Some(total as u32)))
        })
        .await
        .map_err(|join_err| VfsError::Backend {
            path: dir.clone(),
            source: std::io::Error::other(join_err.to_string()),
        })?
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let native = self.resolve_parent(path)?;
        let sym_meta = tokio::fs::symlink_metadata(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        let is_symlink = sym_meta.file_type().is_symlink();
        let metadata = if is_symlink {
            tokio::fs::metadata(&native).await.unwrap_or(sym_meta)
        } else {
            sym_meta
        };
        let name = path.name().unwrap_or("").to_owned();
        Ok(entry_from_metadata(path.clone(), name, &metadata, is_symlink))
    }


    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let native = self.resolve(path)?;
        self.ensure_regular_file(path, &native).await?;
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
        self.ensure_regular_file(path, &native).await?;
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
        let native = self.resolve_parent(path)?;
        let metadata = tokio::fs::symlink_metadata(&native)
            .await
            .map_err(|error| self.io_error(path, error))?;
        let result = if metadata.file_type().is_symlink() {
            #[cfg(windows)]
            {
                use std::os::windows::fs::FileTypeExt;
                if metadata.file_type().is_symlink_dir() {
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
        let from_native = self.resolve_parent(from)?;
        let to_native = self.resolve_parent(to)?;
        tokio::fs::rename(&from_native, &to_native)
            .await
            .map_err(|error| self.io_error(from, error))
    }

    async fn set_mode(&self, path: &VfsPath, mode: u32) -> VfsResult<()> {
        if !self.capabilities.write {
            return Err(VfsError::Unsupported { operation: "chmod" });
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let native = self.resolve(path)?;
            let perms = std::fs::Permissions::from_mode(mode & 0o7777);
            tokio::fs::set_permissions(&native, perms)
                .await
                .map_err(|error| self.io_error(path, error))
        }
        #[cfg(not(unix))]
        {
            let _ = (path, mode);
            Err(VfsError::Unsupported { operation: "chmod" })
        }
    }

    fn supports_space_info(&self) -> bool {
        true
    }

    async fn space_info(&self, path: &VfsPath) -> VfsResult<Option<fm_core::SpaceInfo>> {
        let native = self.join_lexical(path)?;
        self.check_contained(path, &native, false)?;
        let mut target = native;
        while !target.exists() {
            if target == self.root {
                break;
            }
            match target.parent() {
                Some(parent) => target = parent.to_path_buf(),
                None => break,
            }
        }
        if !target.exists() {
            target = self.root.clone();
        }
        let space = tokio::task::spawn_blocking(move || stat_local_space(&target))
            .await
            .map_err(|join_err| VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::other(join_err.to_string()),
            })?
            .map_err(|source| VfsError::Backend {
                path: path.clone(),
                source,
            })?;
        Ok(Some(space))
    }
}

fn stat_local_space(path: &Path) -> std::io::Result<fm_core::SpaceInfo> {
    #[cfg(unix)]
    {
        use std::ffi::CString;
        use std::os::unix::ffi::OsStrExt;
        let c_path = CString::new(path.as_os_str().as_bytes())
            .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "invalid path"))?;
        let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
        let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
        if rc != 0 {
            return Err(std::io::Error::last_os_error());
        }
        let block_size = if stat.f_frsize > 0 {
            stat.f_frsize as u64
        } else {
            stat.f_bsize as u64
        };
        let total = (stat.f_blocks as u64).saturating_mul(block_size);
        let free = (stat.f_bavail as u64).saturating_mul(block_size);
        Ok(fm_core::SpaceInfo {
            total_bytes: (total > 0).then_some(total),
            free_bytes: free,
        })
    }
    #[cfg(windows)]
    {
        use std::os::windows::ffi::OsStrExt;
        #[link(name = "kernel32")]
        extern "system" {
            fn GetDiskFreeSpaceExW(
                lpDirectoryName: *const u16,
                lpFreeBytesAvailableToCaller: *mut u64,
                lpTotalNumberOfBytes: *mut u64,
                lpTotalNumberOfFreeBytes: *mut u64,
            ) -> i32;
        }
        let wide: Vec<u16> = path
            .as_os_str()
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();
        let mut avail = 0u64;
        let mut total = 0u64;
        let mut free = 0u64;
        let ok = unsafe {
            GetDiskFreeSpaceExW(wide.as_ptr(), &mut avail, &mut total, &mut free)
        };
        if ok == 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok(fm_core::SpaceInfo {
            total_bytes: (total > 0).then_some(total),
            free_bytes: avail,
        })
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = path;
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "space query unsupported on this platform",
        ))
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

    #[cfg(unix)]
    #[tokio::test]
    async fn symlink_inside_root_cannot_escape_it() {
        let dir = fixture();
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(outside.path().join("secret.txt"), b"secret").unwrap();
        std::os::unix::fs::symlink(outside.path(), dir.path().join("escape")).unwrap();

        let fs = LocalFs::new(dir.path());
        let escaped = VfsPath::from_slash_path("/escape/secret.txt");
        assert!(matches!(
            fs.open_read(&escaped).await,
            Err(VfsError::PermissionDenied { .. })
        ));
        assert!(matches!(
            fs.open_write(&escaped, WriteMode::Create).await,
            Err(VfsError::PermissionDenied { .. })
        ));
        assert_eq!(std::fs::read_to_string(outside.path().join("secret.txt")).unwrap(), "secret");
    }

    #[tokio::test]
    async fn unresolvable_root_fails_closed_for_existing_entries() {
        let dir = fixture();
        let mut fs = LocalFs::new(dir.path());
        fs.canonical_root = None;
        assert!(matches!(
            fs.stat(&VfsPath::from_slash_path("/a.txt")).await,
            Err(VfsError::PermissionDenied { .. })
        ));
        // Creating a brand-new entry below a not-yet-existing root is still
        // allowed; there is nothing inside it to be a planted symlink.
        let writer = fs
            .open_write(&VfsPath::from_slash_path("/brand-new.txt"), WriteMode::Create)
            .await;
        assert!(writer.is_ok());
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

    #[tokio::test]
    async fn space_info_reports_positive_space_even_for_missing_subpath() {
        let dir = fixture();
        let fs = LocalFs::new(dir.path());
        let root_space = fs.space_info(&VfsPath::root()).await.unwrap().unwrap();
        assert!(root_space.free_bytes > 0);
        assert!(root_space.total_bytes.unwrap_or(0) >= root_space.free_bytes);

        let nested = fs
            .space_info(&VfsPath::from_slash_path("/fm_pool/sub/not_created"))
            .await
            .unwrap()
            .unwrap();
        assert!(nested.free_bytes > 0);
    }

}
