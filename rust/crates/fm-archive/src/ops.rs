//! Archive extraction and compression utilities.

use fm_vfs::{VfsError, VfsResult};
use std::fs::File;
use std::io::Write;
use std::path::Path;
use zip::write::SimpleFileOptions;

use crate::ArchiveFormat;

/// Hard cap on entries in one archive: bombs abuse tiny files as well
/// as big ones (inode exhaustion).
const MAX_ENTRIES: usize = 200_000;

/// Decompressed-bytes budget for one extraction, derived from the
/// archive's own size: 200x its compressed size plus 512 MiB of slack,
/// capped at 32 GiB. Path traversal was already handled (enclosed
/// names / unpack_in / safe_join); this is the missing half — a highly
/// compressible archive (the classic zip bomb) could otherwise fill
/// the disk, which on a phone wedges the whole system, not just us.
fn extract_budget(archive_len: u64) -> u64 {
    archive_len
        .saturating_mul(200)
        .saturating_add(64 * 1024 * 1024)
        .min(32 * 1024 * 1024 * 1024)
}

#[derive(Default)]
struct Budget {
    used: u64,
    limit: u64,
}

impl Budget {
    fn charge(&mut self, n: u64) -> std::io::Result<()> {
        self.used = self.used.saturating_add(n);
        if self.used > self.limit {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "extraction aborted: decompressed data exceeds the safety limit of {} bytes for this archive",
                    self.limit
                ),
            ));
        }
        Ok(())
    }
}

type SharedBudget = std::rc::Rc<std::cell::RefCell<Budget>>;

/// Reader that charges every byte pulled through it to the budget. For
/// tar this bounds the whole stream (headers included — the caller
/// adds slack); for 7z it wraps each entry's reader.
struct CountingReader<R: std::io::Read> {
    inner: R,
    budget: SharedBudget,
}

impl<R: std::io::Read> std::io::Read for CountingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.budget.borrow_mut().charge(n as u64)?;
        Ok(n)
    }
}

/// Writer counterpart for the zip path.
struct CountingWriter<W: std::io::Write> {
    inner: W,
    budget: SharedBudget,
}

impl<W: std::io::Write> std::io::Write for CountingWriter<W> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let n = self.inner.write(buf)?;
        self.budget.borrow_mut().charge(n as u64)?;
        Ok(n)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

/// Tracks files and directories an extraction creates, so a failed or
/// over-budget run can remove exactly its own half-written output
/// without touching anything that was already there.
#[derive(Default)]
struct CreatedPaths {
    files: Vec<std::path::PathBuf>,
    dirs: Vec<std::path::PathBuf>,
}

impl CreatedPaths {
    fn track_file(&mut self, target: &Path) {
        if !target.exists() {
            self.files.push(target.to_path_buf());
        }
    }

    fn track_parent_dirs(&mut self, target: &Path, dest: &Path) {
        let mut current = target.parent();
        while let Some(dir) = current {
            if dir == dest || !dir.starts_with(dest) {
                break;
            }
            if !dir.exists() && !self.dirs.iter().any(|d| d == dir) {
                self.dirs.push(dir.to_path_buf());
            }
            current = dir.parent();
        }
    }

    fn cleanup(&self) {
        for file in &self.files {
            let _ = std::fs::remove_file(file);
        }
        let mut dirs = self.dirs.clone();
        dirs.sort_by_key(|d| std::cmp::Reverse(d.components().count()));
        for dir in dirs {
            let _ = std::fs::remove_dir(dir);
        }
    }
}

fn backend_err(e: std::io::Error) -> VfsError {
    VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    }
}

pub fn extract_archive(archive_path: &Path, destination_dir: &Path) -> VfsResult<()> {
    std::fs::create_dir_all(destination_dir).map_err(backend_err)?;

    let name = archive_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    let format = ArchiveFormat::from_name(name).ok_or(VfsError::Unsupported {
        operation: "unknown archive format for extraction",
    })?;

    let archive_len = std::fs::metadata(archive_path).map(|m| m.len()).unwrap_or(0);
    let budget: SharedBudget = std::rc::Rc::new(std::cell::RefCell::new(Budget {
        used: 0,
        limit: extract_budget(archive_len),
    }));
    let mut created = CreatedPaths::default();

    let result = extract_inner(format, archive_path, destination_dir, &budget, &mut created);
    if result.is_err() {
        created.cleanup();
    }
    result
}

fn extract_inner(
    format: ArchiveFormat,
    archive_path: &Path,
    destination_dir: &Path,
    budget: &SharedBudget,
    created: &mut CreatedPaths,
) -> VfsResult<()> {
    match format {
        ArchiveFormat::Zip | ArchiveFormat::Epub => {
            let file = File::open(archive_path).map_err(backend_err)?;
            let mut zip = zip::ZipArchive::new(file).map_err(|e| {
                backend_err(std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))
            })?;
            if zip.len() > MAX_ENTRIES {
                return Err(backend_err(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("archive has too many entries ({})", zip.len()),
                )));
            }
            // Manual loop instead of ZipArchive::extract: the stock
            // extractor gives no byte budget and materialises symlink
            // entries as real symlinks; here symlinks become plain
            // files holding the target text, and every written byte is
            // charged to the budget.
            for i in 0..zip.len() {
                let mut entry = zip.by_index(i).map_err(|e| {
                    backend_err(std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()))
                })?;
                let Some(rel) = entry.enclosed_name() else {
                    return Err(backend_err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("unsafe archive entry path: {}", entry.name().map(|n| n.into_owned()).unwrap_or_else(|_| "<invalid name>".to_string())),
                    )));
                };
                let target = destination_dir.join(&rel);
                if entry.is_dir() {
                    created.track_parent_dirs(&target.join("x"), destination_dir);
                    if !target.exists() {
                        created.dirs.push(target.clone());
                    }
                    std::fs::create_dir_all(&target).map_err(backend_err)?;
                } else {
                    created.track_parent_dirs(&target, destination_dir);
                    if let Some(parent) = target.parent() {
                        std::fs::create_dir_all(parent).map_err(backend_err)?;
                    }
                    created.track_file(&target);
                    let mut out = File::create(&target).map_err(backend_err)?;
                    let mut writer = CountingWriter {
                        inner: &mut out,
                        budget: budget.clone(),
                    };
                    std::io::copy(&mut entry, &mut writer).map_err(backend_err)?;
                    drop(writer);
                    #[cfg(unix)]
                    if let Some(mode) = entry.unix_mode() {
                        use std::os::unix::fs::PermissionsExt;
                        let _ = std::fs::set_permissions(
                            &target,
                            std::fs::Permissions::from_mode(mode & 0o777),
                        );
                    }
                }
            }
            Ok(())
        }
        ArchiveFormat::Tar => {
            let file = File::open(archive_path).map_err(backend_err)?;
            let reader = CountingReader {
                inner: file,
                budget: tar_stream_budget(budget),
            };
            let mut archive = tar::Archive::new(reader);
            extract_tar(&mut archive, destination_dir, created)
        }
        ArchiveFormat::TarGz => {
            let file = File::open(archive_path).map_err(backend_err)?;
            let gz = flate2::read::GzDecoder::new(file);
            let reader = CountingReader {
                inner: gz,
                budget: tar_stream_budget(budget),
            };
            let mut archive = tar::Archive::new(reader);
            extract_tar(&mut archive, destination_dir, created)
        }
        ArchiveFormat::SevenZip => {
            // sevenz-rust joins entry names onto the destination without
            // sanitising them, so a crafted archive can write outside it.
            let mut entries_seen = 0usize;
            let result = sevenz_rust::decompress_file_with_extract_fn(
                archive_path,
                destination_dir,
                |entry, reader, _dest| {
                    entries_seen += 1;
                    if entries_seen > MAX_ENTRIES {
                        return Err(sevenz_rust::Error::other(format!(
                            "archive has too many entries ({entries_seen})"
                        )));
                    }
                    let target = safe_join(destination_dir, entry.name()).ok_or_else(|| {
                        sevenz_rust::Error::other(format!(
                            "unsafe archive entry path: {}",
                            entry.name()
                        ))
                    })?;
                    if entry.is_directory() {
                        created.track_parent_dirs(&target.join("x"), destination_dir);
                        if !target.exists() {
                            created.dirs.push(target.clone());
                        }
                        std::fs::create_dir_all(&target).map_err(sevenz_rust::Error::io)?;
                    } else {
                        created.track_parent_dirs(&target, destination_dir);
                        if let Some(parent) = target.parent() {
                            std::fs::create_dir_all(parent).map_err(sevenz_rust::Error::io)?;
                        }
                        created.track_file(&target);
                        let mut file = File::create(&target).map_err(sevenz_rust::Error::io)?;
                        let mut limited = CountingReader {
                            inner: reader,
                            budget: budget.clone(),
                        };
                        std::io::copy(&mut limited, &mut file).map_err(sevenz_rust::Error::io)?;
                    }
                    Ok(true)
                },
            );
            result.map_err(|e| backend_err(std::io::Error::other(e.to_string())))
        }
    }
}

/// The tar guard counts stream bytes, which include per-entry headers
/// and padding on top of file data, so it gets its own budget: the
/// data limit plus generous slack. (The decompressed stream is also
/// what a tar.gz bomb inflates, so this bounds the gz path too.)
fn tar_stream_budget(budget: &SharedBudget) -> SharedBudget {
    let limit = budget.borrow().limit;
    std::rc::Rc::new(std::cell::RefCell::new(Budget {
        used: 0,
        limit: limit.saturating_add(64 * 1024 * 1024),
    }))
}

/// Extract a tar stream entry by entry with `unpack_in`, which validates
/// link targets as well as entry paths. Plain `Archive::unpack` only checks
/// the entry path itself, so an archive containing a symlink entry followed
/// by a file beneath it writes outside the destination.
fn extract_tar<R: std::io::Read>(
    archive: &mut tar::Archive<R>,
    destination_dir: &Path,
    created: &mut CreatedPaths,
) -> VfsResult<()> {
    let mut entries_seen = 0usize;
    let entries = archive.entries().map_err(backend_err)?;
    for entry in entries {
        let mut entry = entry.map_err(backend_err)?;
        entries_seen += 1;
        if entries_seen > MAX_ENTRIES {
            return Err(backend_err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("archive has too many entries ({entries_seen})"),
            )));
        }
        if let Ok(entry_path) = entry.path() {
            let entry_str = entry_path.to_string_lossy().replace('\\', "/");
            if let Some(target) = safe_join(destination_dir, &entry_str) {
                created.track_parent_dirs(&target, destination_dir);
                created.track_file(&target);
            }
        }
        entry.unpack_in(destination_dir).map_err(backend_err)?;
    }
    Ok(())
}

/// Join an archive entry name onto `base`, rejecting absolute paths and any
/// component that would escape it.
fn safe_join(base: &Path, entry_name: &str) -> Option<std::path::PathBuf> {
    let normalized = entry_name.replace('\\', "/");
    let mut out = base.to_path_buf();
    for component in normalized.split('/') {
        match component {
            "" | "." => continue,
            ".." => return None,
            _ => out.push(component),
        }
    }
    if out.starts_with(base) {
        Some(out)
    } else {
        None
    }
}

pub fn create_zip(sources: &[impl AsRef<Path>], destination_zip: &Path) -> VfsResult<()> {
    let file = File::create(destination_zip).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);

    let dest_canon = destination_zip.canonicalize().ok();

    for source_ref in sources {
        let source = source_ref.as_ref();
        if let Some(ref dc) = dest_canon {
            if let Ok(sc) = source.canonicalize() {
                if sc == *dc {
                    continue;
                }
            }
        }
        if source.is_file() {
            let file_name = source
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("file");
            zip.start_file(file_name, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            let mut f = File::open(source).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            std::io::copy(&mut f, &mut zip).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        } else if source.is_dir() {
            add_dir_to_zip(&mut zip, source, source, options, dest_canon.as_deref())?;
        }
    }

    zip.finish().map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: std::io::Error::other(e.to_string()),
    })?;

    Ok(())
}

fn add_dir_to_zip<W: Write + std::io::Seek>(
    zip: &mut zip::ZipWriter<W>,
    base_dir: &Path,
    current_dir: &Path,
    options: SimpleFileOptions,
    dest_canon: Option<&Path>,
) -> VfsResult<()> {
    let read_dir = std::fs::read_dir(current_dir).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;

    for entry_res in read_dir {
        let entry = entry_res.map_err(|e| VfsError::Backend {
            path: fm_core::VfsPath::root(),
            source: e,
        })?;
        let path = entry.path();
        if let Some(dc) = dest_canon {
            if let Ok(pc) = path.canonicalize() {
                if pc == dc {
                    continue;
                }
            }
        }
        let rel_path = path
            .strip_prefix(base_dir)
            .map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidInput, e.to_string()),
            })?;
        let rel_path_str = rel_path.to_string_lossy().replace('\\', "/");

        let file_type = entry.file_type().map_err(|e| VfsError::Backend {
            path: fm_core::VfsPath::root(),
            source: e,
        })?;
        if file_type.is_symlink() {
            // Avoid cyclic symlink recursion and directory traversal
            continue;
        }

        if file_type.is_dir() {
            zip.add_directory(format!("{rel_path_str}/"), options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            add_dir_to_zip(zip, base_dir, &path, options, dest_canon)?;
        } else if file_type.is_file() {
            zip.start_file(&rel_path_str, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            let mut f = File::open(&path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            std::io::copy(&mut f, zip).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_create_zip_skips_destination_inside_source() {
        let dir = tempdir().unwrap();
        let src_folder = dir.path().join("my_folder");
        std::fs::create_dir(&src_folder).unwrap();
        std::fs::write(src_folder.join("file1.txt"), "hello world").unwrap();

        // Put destination zip INSIDE the folder being compressed
        let dest_zip = src_folder.join("archive.zip");
        create_zip(&[&src_folder], &dest_zip).unwrap();

        assert!(dest_zip.exists());
        let file = File::open(&dest_zip).unwrap();
        let mut zip = zip::ZipArchive::new(file).unwrap();
        let names: Vec<String> = (0..zip.len())
            .map(|i| zip.by_index(i).unwrap().name().unwrap().to_string())
            .collect();
        assert!(names.iter().any(|n| n.ends_with("file1.txt")));
        assert!(!names.iter().any(|n| n.ends_with("archive.zip")));
    }
}


#[cfg(test)]
mod bomb_tests {
    use super::*;

    #[test]
    fn zip_bomb_is_aborted_and_cleaned_up() {
        let dir = tempfile::tempdir().unwrap();
        let zip_path = dir.path().join("bomb.zip");
        // 100 MiB of zeros in a ~100 KiB zip: budget is
        // 200 * zip_len + 64 MiB < 100 MiB, so extraction must abort.
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Deflated);
            writer.start_file("zeros.bin", options).unwrap();
            let chunk = [0u8; 1024 * 1024];
            for _ in 0..100 {
                writer.write_all(&chunk).unwrap();
            }
            writer.finish().unwrap();
        }
        let dest = dir.path().join("out");
        let result = extract_archive(&zip_path, &dest);
        assert!(result.is_err(), "bomb extraction must fail");
        assert!(
            !dest.join("zeros.bin").exists(),
            "half-extracted bomb file must be cleaned up"
        );
    }

    #[test]
    fn budget_scales_with_archive() {
        assert!(extract_budget(0) >= 64 * 1024 * 1024);
        assert!(extract_budget(1024 * 1024) >= 200 * 1024 * 1024);
        assert_eq!(extract_budget(u64::MAX), 32 * 1024 * 1024 * 1024);
    }
}
