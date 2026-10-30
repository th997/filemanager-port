//! Virtual filesystem implementation for archive browsing.

use async_trait::async_trait;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use std::collections::HashMap;
use std::fs::File;
use std::io::{Read, Write};
use std::path::PathBuf;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_util::io::SyncIoBridge;

use crate::ArchiveFormat;

#[derive(Debug, Clone)]
struct ArchiveFileInfo {
    size: u64,
    index: usize,
}

pub struct ArchiveFs {
    archive_path: PathBuf,
    format: ArchiveFormat,
    dir_entries: HashMap<VfsPath, Vec<Entry>>,
    file_map: HashMap<VfsPath, ArchiveFileInfo>,
}

impl ArchiveFs {
    pub fn open(path: impl Into<PathBuf>) -> VfsResult<Self> {
        let archive_path = path.into();
        let name = archive_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        let format = ArchiveFormat::from_name(name).ok_or(VfsError::Unsupported {
            operation: "unsupported archive format",
        })?;

        let mut fs = Self {
            archive_path,
            format,
            dir_entries: HashMap::new(),
            file_map: HashMap::new(),
        };

        fs.build_index()?;
        Ok(fs)
    }

    fn build_index(&mut self) -> VfsResult<()> {
        match self.format {
            ArchiveFormat::Zip | ArchiveFormat::Epub => self.build_zip_index(),
            ArchiveFormat::Tar => self.build_tar_index(false),
            ArchiveFormat::TarGz => self.build_tar_index(true),
            ArchiveFormat::SevenZip => self.build_7z_index(),
        }
    }

    fn build_zip_index(&mut self) -> VfsResult<()> {
        let file = File::open(&self.archive_path).map_err(|e| VfsError::Backend {
            path: VfsPath::root(),
            source: e,
        })?;
        let buffered = std::io::BufReader::with_capacity(128 * 1024, file);
        let mut zip = zip::ZipArchive::new(buffered).map_err(|e| VfsError::Backend {
            path: VfsPath::root(),
            source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
        })?;

        for i in 0..zip.len() {
            let zip_file = match zip.by_index_raw(i) {
                Ok(f) => f,
                Err(_) => continue,
            };

            let raw_name = match zip_file.name() {
                Ok(n) => n.to_string(),
                Err(_) => continue,
            };
            let is_dir = zip_file.is_dir() || raw_name.ends_with('/');
            let vfs_path = VfsPath::from_slash_path(&raw_name);
            if vfs_path.is_root() {
                continue;
            }

            let entry_name = vfs_path.name().unwrap_or("").to_string();
            let parent_path = vfs_path.parent().unwrap_or_else(VfsPath::root);

            let kind = if is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            };
            let size = if is_dir {
                None
            } else {
                Some(zip_file.size())
            };
            self.ensure_parent_dirs(&vfs_path);
            let hidden = entry_name.starts_with('.');

            let entry = Entry {
                name: entry_name,
                path: vfs_path.clone(),
                kind,
                size,
                modified: None,
                mode: None,
                hidden,
                is_symlink: false,
                mime: None,
            };

            // Register in parent directory
            self.dir_entries
                .entry(parent_path)
                .or_default()
                .push(entry);

            if !is_dir {
                self.file_map.insert(
                    vfs_path,
                    ArchiveFileInfo {
                        size: zip_file.size(),
                        index: i,
                    },
                );
            }
        }

        self.sort_directories();
        Ok(())
    }

    fn collect_tar_entries<R: std::io::Read>(
        archive: &mut tar::Archive<R>,
    ) -> VfsResult<Vec<(usize, String, bool, u64)>> {
        let backend_err = |e: std::io::Error| VfsError::Backend {
            path: VfsPath::root(),
            source: e,
        };
        let entries = archive.entries().map_err(backend_err)?;
        let mut found = Vec::new();
        for (idx, entry_res) in entries.enumerate() {
            let entry = entry_res.map_err(backend_err)?;
            // Only an entry whose path cannot be decoded at all is skipped;
            // the archive around it is still readable.
            if let Ok(path) = entry.path() {
                let path_str = path.to_string_lossy().to_string();
                let is_dir = entry.header().entry_type().is_dir();
                let size = entry.header().size().unwrap_or(0);
                found.push((idx, path_str, is_dir, size));
            }
        }
        Ok(found)
    }

    fn build_tar_index(&mut self, is_gz: bool) -> VfsResult<()> {
        let file = File::open(&self.archive_path).map_err(|e| VfsError::Backend {
            path: VfsPath::root(),
            source: e,
        })?;
        let buffered = std::io::BufReader::with_capacity(128 * 1024, file);

        // Read errors must propagate: swallowing them here made a truncated
        // or corrupt tar open successfully as an "empty" archive.
        let entries_found = if is_gz {
            let gz = flate2::read::GzDecoder::new(buffered);
            let mut archive = tar::Archive::new(gz);
            Self::collect_tar_entries(&mut archive)?
        } else {
            let mut archive = tar::Archive::new(buffered);
            Self::collect_tar_entries(&mut archive)?
        };

        for (idx, raw_name, is_dir, size) in entries_found {
            let vfs_path = VfsPath::from_slash_path(&raw_name);
            if vfs_path.is_root() {
                continue;
            }
            let entry_name = vfs_path.name().unwrap_or("").to_string();
            let parent_path = vfs_path.parent().unwrap_or_else(VfsPath::root);

            let kind = if is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            };
            let hidden = entry_name.starts_with('.');
            self.ensure_parent_dirs(&vfs_path);

            let entry = Entry {
                name: entry_name,
                path: vfs_path.clone(),
                kind,
                size: if is_dir { None } else { Some(size) },
                modified: None,
                mode: None,
                hidden,
                is_symlink: false,
                mime: None,
            };

            self.dir_entries
                .entry(parent_path)
                .or_default()
                .push(entry);

            if !is_dir {
                self.file_map
                    .insert(vfs_path, ArchiveFileInfo { size, index: idx });
            }
        }

        self.sort_directories();
        Ok(())
    }

    fn build_7z_index(&mut self) -> VfsResult<()> {
        let archive = sevenz_rust::Archive::open(&self.archive_path).map_err(|e| {
            VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
            }
        })?;

        for (idx, zip_entry) in archive.files.iter().enumerate() {
            let raw_name = zip_entry.name().replace('\\', "/");
            let is_dir = zip_entry.is_directory() || raw_name.ends_with('/');
            let vfs_path = VfsPath::from_slash_path(&raw_name);
            if vfs_path.is_root() {
                continue;
            }

            let entry_name = vfs_path.name().unwrap_or("").to_string();
            let parent_path = vfs_path.parent().unwrap_or_else(VfsPath::root);

            let kind = if is_dir {
                EntryKind::Dir
            } else {
                EntryKind::File
            };
            let size = if is_dir {
                None
            } else {
                Some(zip_entry.size())
            };
            let hidden = entry_name.starts_with('.');
            self.ensure_parent_dirs(&vfs_path);

            let entry = Entry {
                name: entry_name,
                path: vfs_path.clone(),
                kind,
                size,
                modified: None,
                mode: None,
                hidden,
                is_symlink: false,
                mime: None,
            };

            self.dir_entries
                .entry(parent_path)
                .or_default()
                .push(entry);

            if !is_dir {
                self.file_map.insert(
                    vfs_path,
                    ArchiveFileInfo {
                        size: zip_entry.size(),
                        index: idx,
                    },
                );
            }
        }

        self.sort_directories();
        Ok(())
    }

    /// Archives written from a stream often contain no explicit directory
    /// entries; create the missing ancestors so the tree is browsable.
    fn ensure_parent_dirs(&mut self, path: &VfsPath) {
        let mut ancestors = Vec::new();
        let mut current = path.parent();
        while let Some(dir) = current {
            if dir.is_root() || self.dir_entries.contains_key(&dir) {
                break;
            }
            ancestors.push(dir.clone());
            current = dir.parent();
        }

        for dir in ancestors.into_iter().rev() {
            let name = dir.name().unwrap_or("").to_string();
            let parent = dir.parent().unwrap_or_else(VfsPath::root);
            let entry = Entry {
                name: name.clone(),
                path: dir.clone(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: name.starts_with('.'),
                is_symlink: false,
                mime: None,
            };
            self.dir_entries.entry(dir).or_default();
            self.dir_entries.entry(parent).or_default().push(entry);
        }
    }

    fn sort_directories(&mut self) {
        for list in self.dir_entries.values_mut() {
            list.sort_by(|a, b| {
                let a_dir = a.kind == EntryKind::Dir;
                let b_dir = b.kind == EntryKind::Dir;
                b_dir.cmp(&a_dir).then_with(|| a.name.cmp(&b.name))
            });
            list.dedup_by(|a, b| a.path == b.path);
        }
    }

    /// Open an entry as a byte range, decompressing only what the caller
    /// consumes.
    ///
    /// Decompression is synchronous, so it runs on a blocking thread and feeds
    /// an in-memory pipe. The archive is reopened per call: keeping a
    /// decompressor alive across seeks would pin the whole entry in memory.
    fn spawn_reader(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let info = self
            .file_map
            .get(path)
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })?;
        let index = info.index;
        let format = self.format;
        let archive_path = self.archive_path.clone();
        let target_name = path.to_slash_string().trim_start_matches('/').to_string();

        let (writer, out) = tokio::io::duplex(256 * 1024);
        let handle = tokio::runtime::Handle::current();
        tokio::task::spawn_blocking(move || {
            let mut bridge = SyncIoBridge::new_with_handle(writer, handle);
            let _ = pump_entry(
                format,
                &archive_path,
                index,
                &target_name,
                offset,
                length,
                &mut bridge,
            );
            // Dropping the bridge closes the pipe; the caller sees EOF.
        });

        Ok(Box::new(out))
    }

    pub fn read_entry_bytes(&self, path: &VfsPath) -> VfsResult<Vec<u8>> {
        let info = self
            .file_map
            .get(path)
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })?;

        match self.format {
            ArchiveFormat::Zip | ArchiveFormat::Epub => {
                let file = File::open(&self.archive_path).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                let buffered = std::io::BufReader::with_capacity(128 * 1024, file);
                let mut zip = zip::ZipArchive::new(buffered).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
                })?;
                let mut entry = zip.by_index(info.index).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
                })?;
                let mut buf = Vec::with_capacity(prealloc_for_declared_size(info.size));
                entry.read_to_end(&mut buf).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                Ok(buf)
            }
            ArchiveFormat::Tar => {
                let file = File::open(&self.archive_path).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                let buffered = std::io::BufReader::with_capacity(128 * 1024, file);
                let mut archive = tar::Archive::new(buffered);
                let mut entries = archive.entries().map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                if let Some(Ok(mut entry)) = entries.nth(info.index) {
                    let mut buf = Vec::with_capacity(prealloc_for_declared_size(info.size));
                    entry.read_to_end(&mut buf).map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: e,
                    })?;
                    Ok(buf)
                } else {
                    Err(VfsError::NotFound { path: path.clone() })
                }
            }
            ArchiveFormat::TarGz => {
                let file = File::open(&self.archive_path).map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                let buffered = std::io::BufReader::with_capacity(128 * 1024, file);
                let gz = flate2::read::GzDecoder::new(buffered);
                let mut archive = tar::Archive::new(gz);
                let mut entries = archive.entries().map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: e,
                })?;
                if let Some(Ok(mut entry)) = entries.nth(info.index) {
                    let mut buf = Vec::with_capacity(prealloc_for_declared_size(info.size));
                    entry.read_to_end(&mut buf).map_err(|e| VfsError::Backend {
                        path: path.clone(),
                        source: e,
                    })?;
                    Ok(buf)
                } else {
                    Err(VfsError::NotFound { path: path.clone() })
                }
            }
            ArchiveFormat::SevenZip => {
                let mut found_bytes = Vec::new();
                let target_name = path.to_slash_string().trim_start_matches('/').to_string();
                sevenz_rust::decompress_file_with_extract_fn(
                    &self.archive_path,
                    "",
                    |entry, reader, _dest| {
                        // The index normalised entry names to '/' when it
                        // was built; raw names here may still use '\\'
                        // (Windows-created archives) and would never match,
                        // silently returning empty content.
                        if entry.name().replace('\\', "/") == target_name {
                            match reader.read_to_end(&mut found_bytes) {
                                Ok(_) => Ok(false), // stop search
                                Err(e) => Err(sevenz_rust::Error::io(e)),
                            }
                        } else {
                            Ok(true)
                        }
                    },
                )
                .map_err(|e| VfsError::Backend {
                    path: path.clone(),
                    source: std::io::Error::other(e.to_string()),
                })?;
                Ok(found_bytes)
            }
        }
    }
}

/// Initial buffer capacity for reading an entry. The declared size comes
/// from the archive's own headers and is untrusted: a forged entry can
/// declare terabytes and abort the process trying to allocate it. Cap the
/// preallocation and let `read_to_end` grow the buffer to the real size.
fn prealloc_for_declared_size(declared: u64) -> usize {
    const MAX_PREALLOC: u64 = 4 * 1024 * 1024;
    declared.min(MAX_PREALLOC) as usize
}

/// Copy one entry's bytes into `sink`, skipping `offset` bytes first.
fn pump_entry(
    format: ArchiveFormat,
    archive_path: &std::path::Path,
    index: usize,
    target_name: &str,
    offset: u64,
    length: Option<u64>,
    sink: &mut dyn Write,
) -> VfsResult<()> {
    let copy_from = |reader: &mut dyn Read, sink: &mut dyn Write| -> std::io::Result<()> {
        let mut left = offset;
        let mut scratch = [0u8; 64 * 1024];
        while left > 0 {
            let want = left.min(scratch.len() as u64) as usize;
            let n = reader.read(&mut scratch[..want])?;
            if n == 0 {
                return Ok(());
            }
            left -= n as u64;
        }
        let mut remaining = length.unwrap_or(u64::MAX);
        while remaining > 0 {
            let want = remaining.min(scratch.len() as u64) as usize;
            let n = reader.read(&mut scratch[..want])?;
            if n == 0 {
                break;
            }
            sink.write_all(&scratch[..n])?;
            remaining -= n as u64;
        }
        Ok(())
    };

    let open_err = |e: std::io::Error| VfsError::Backend {
        path: VfsPath::root(),
        source: e,
    };

    match format {
        ArchiveFormat::Zip | ArchiveFormat::Epub => {
            let file = File::open(archive_path).map_err(open_err)?;
            let mut zip = zip::ZipArchive::new(file).map_err(|e| VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
            })?;
            let mut entry = zip.by_index(index).map_err(|e| VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
            })?;
            copy_from(&mut entry, sink).map_err(open_err)?;
        }
        ArchiveFormat::Tar | ArchiveFormat::TarGz => {
            let file = File::open(archive_path).map_err(open_err)?;
            if format == ArchiveFormat::TarGz {
                let gz = flate2::read::GzDecoder::new(file);
                let mut archive = tar::Archive::new(gz);
                let mut entries = archive.entries().map_err(open_err)?;
                if let Some(Ok(mut entry)) = entries.nth(index) {
                    copy_from(&mut entry, sink).map_err(open_err)?;
                }
            } else {
                let mut archive = tar::Archive::new(file);
                let mut entries = archive.entries().map_err(open_err)?;
                if let Some(Ok(mut entry)) = entries.nth(index) {
                    copy_from(&mut entry, sink).map_err(open_err)?;
                }
            }
        }
        ArchiveFormat::SevenZip => {
            // Solid archives must be decompressed from the start; the callback
            // skips the prefix of the wanted entry and then stops the scan.
            sevenz_rust::decompress_file_with_extract_fn(
                archive_path,
                "",
                |entry, reader, _dest| {
                    if entry.name().replace('\\', "/") != target_name {
                        return Ok(true);
                    }
                    let result = copy_from(reader, sink);
                    match result {
                        Ok(()) => Ok(false),
                        Err(e) => Err(sevenz_rust::Error::other(e.to_string())),
                    }
                },
            )
            .map_err(|e| VfsError::Backend {
                path: VfsPath::root(),
                source: std::io::Error::other(e.to_string()),
            })?;
        }
    }

    Ok(())
}

#[async_trait]
impl Vfs for ArchiveFs {
    fn capabilities(&self) -> Capabilities {
        Capabilities::READ_ONLY
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        Ok(self.dir_entries.get(dir).cloned().unwrap_or_default())
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        if path.is_root() {
            return Ok(Entry {
                name: self
                    .archive_path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("")
                    .to_string(),
                path: VfsPath::root(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                is_symlink: false,
                mime: None,
            });
        }

        let parent = path.parent().unwrap_or_else(VfsPath::root);
        if let Some(siblings) = self.dir_entries.get(&parent) {
            if let Some(entry) = siblings.iter().find(|e| &e.path == path) {
                return Ok(entry.clone());
            }
        }

        Err(VfsError::NotFound { path: path.clone() })
    }

    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        self.spawn_reader(path, 0, None)
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        self.spawn_reader(path, offset, length)
    }

    async fn open_write(
        &self,
        _path: &VfsPath,
        _mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        Err(VfsError::Unsupported {
            operation: "writing inside archive is not supported",
        })
    }

    async fn mkdir(&self, _path: &VfsPath) -> VfsResult<()> {
        Err(VfsError::Unsupported { operation: "mkdir in archive" })
    }

    async fn remove(&self, _path: &VfsPath) -> VfsResult<()> {
        Err(VfsError::Unsupported { operation: "remove in archive" })
    }

    async fn rename(&self, _from: &VfsPath, _to: &VfsPath) -> VfsResult<()> {
        Err(VfsError::Unsupported { operation: "rename in archive" })
    }
}
