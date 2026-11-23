//! Archive extraction and compression utilities.

use fm_vfs::{VfsError, VfsResult};
use tokio_util::sync::CancellationToken;
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
struct CountingReader<'a, R: std::io::Read> {
    inner: R,
    budget: SharedBudget,
    cancel: &'a CancellationToken,
}

impl<R: std::io::Read> std::io::Read for CountingReader<'_, R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if self.cancel.is_cancelled() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "operation cancelled",
            ));
        }
        let n = self.inner.read(buf)?;
        self.budget.borrow_mut().charge(n as u64)?;
        Ok(n)
    }
}

/// Writer counterpart for the zip path.
struct CountingWriter<'a, W: std::io::Write> {
    inner: W,
    budget: SharedBudget,
    cancel: &'a CancellationToken,
}

impl<W: std::io::Write> std::io::Write for CountingWriter<'_, W> {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        if self.cancel.is_cancelled() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::Interrupted,
                "operation cancelled",
            ));
        }
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
    temps: Vec<std::path::PathBuf>,
}

impl CreatedPaths {
    fn track_file(&mut self, target: &Path) {
        if !target.exists() {
            self.files.push(target.to_path_buf());
        }
    }

    /// Temp files always belong to this extraction, whether or not a file
    /// already existed at the final path.
    fn track_temp(&mut self, tmp: &Path) {
        self.temps.push(tmp.to_path_buf());
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
        for tmp in &self.temps {
            let _ = std::fs::remove_file(tmp);
        }
        let mut dirs = self.dirs.clone();
        dirs.sort_by_key(|d| std::cmp::Reverse(d.components().count()));
        for dir in dirs {
            let _ = std::fs::remove_dir(dir);
        }
    }
}

fn sibling_tmp_path(target: &Path) -> std::path::PathBuf {
    let name = target
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("entry");
    let pid = std::process::id();
    let unique = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let tmp_name = format!(".{name}.{pid}.{unique}.fm-part");
    match target.parent() {
        Some(parent) => parent.join(tmp_name),
        None => std::path::PathBuf::from(tmp_name),
    }
}

/// Move the finished temp file into place.
///
/// Windows `rename` refuses to replace an existing file, so an overwrite
/// first moves the old target aside and puts it back if the swap fails.
fn install_temp(tmp: &Path, target: &Path) -> std::io::Result<()> {
    if std::fs::rename(tmp, target).is_ok() {
        return Ok(());
    }
    if !target.exists() {
        return std::fs::rename(tmp, target);
    }
    let backup = sibling_tmp_path(target).with_extension("fm-old");
    std::fs::rename(target, &backup)?;
    match std::fs::rename(tmp, target) {
        Ok(()) => {
            let _ = std::fs::remove_file(&backup);
            Ok(())
        }
        Err(e) => {
            let _ = std::fs::rename(&backup, target);
            Err(e)
        }
    }
}

fn backend_err(e: std::io::Error) -> VfsError {
    VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    }
}

/// Refuse to write an archive entry through a symlink that already exists in
/// the destination tree. `File::create` and `create_dir_all` both follow
/// links, so a purely lexical check (`enclosed_name` / `safe_join`) is not
/// enough: extracting an entry named `link/x` into a directory containing
/// `link -> /etc` would otherwise write outside the destination.
fn assert_contained(destination_dir: &Path, target: &Path) -> std::io::Result<()> {
    let escape = || {
        std::io::Error::new(
            std::io::ErrorKind::PermissionDenied,
            "archive entry escapes the destination directory",
        )
    };
    let dest_canon = destination_dir.canonicalize()?;

    if let Ok(meta) = std::fs::symlink_metadata(target) {
        if meta.file_type().is_symlink() {
            return Err(escape());
        }
    }

    let mut probe = target.parent().unwrap_or(destination_dir);
    loop {
        if std::fs::symlink_metadata(probe).is_ok() {
            let resolved = probe.canonicalize()?;
            if !resolved.starts_with(&dest_canon) {
                return Err(escape());
            }
            return Ok(());
        }
        probe = probe.parent().ok_or_else(escape)?;
    }
}

fn cancelled_err() -> VfsError {
    backend_err(std::io::Error::new(
        std::io::ErrorKind::Interrupted,
        "operation cancelled",
    ))
}

pub fn extract_archive(archive_path: &Path, destination_dir: &Path) -> VfsResult<()> {
    extract_archive_with_password(archive_path, destination_dir, None, &CancellationToken::new())
}

/// Extract with cooperative cancellation. The token is checked at every
/// entry boundary, so a cancelled task stops writing instead of running to
/// completion while the UI already shows it as cancelled.
pub fn extract_archive_with_cancel(
    archive_path: &Path,
    destination_dir: &Path,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    extract_archive_with_password(archive_path, destination_dir, None, cancel)
}

/// Extract an archive (including password-protected `.zip` and `.7z`) with
/// cooperative cancellation.
pub fn extract_archive_with_password(
    archive_path: &Path,
    destination_dir: &Path,
    password: Option<&str>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
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

    let result = extract_inner(
        format,
        archive_path,
        destination_dir,
        password.filter(|p| !p.is_empty()),
        &budget,
        &mut created,
        cancel,
    );
    if result.is_err() {
        created.cleanup();
    }
    result
}

fn extract_inner(
    format: ArchiveFormat,
    archive_path: &Path,
    destination_dir: &Path,
    password: Option<&str>,
    budget: &SharedBudget,
    created: &mut CreatedPaths,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    if cancel.is_cancelled() {
        return Err(cancelled_err());
    }
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
                if cancel.is_cancelled() {
                    return Err(cancelled_err());
                }
                let mut entry = match password {
                    Some(pw) => zip.by_index_decrypt(i, pw.as_bytes()),
                    None => zip.by_index(i),
                }
                .map_err(|e| {
                    let msg = match e {
                        zip::result::ZipError::UnsupportedArchive(
                            zip::result::ZipError::PASSWORD_REQUIRED,
                        ) => "ARCHIVE_PASSWORD_REQUIRED: password required to extract zip".to_string(),
                        zip::result::ZipError::InvalidPassword => {
                            "ARCHIVE_WRONG_PASSWORD: invalid password for zip".to_string()
                        }
                        other => {
                            let text = other.to_string();
                            if text.to_lowercase().contains("password required") {
                                format!("ARCHIVE_PASSWORD_REQUIRED: {text}")
                            } else if text.to_lowercase().contains("invalid password") {
                                format!("ARCHIVE_WRONG_PASSWORD: {text}")
                            } else {
                                text
                            }
                        }
                    };
                    backend_err(std::io::Error::new(std::io::ErrorKind::InvalidData, msg))
                })?;
                let Some(rel) = entry.enclosed_name() else {
                    return Err(backend_err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        format!("unsafe archive entry path: {}", entry.name().map(|n| n.into_owned()).unwrap_or_else(|_| "<invalid name>".to_string())),
                    )));
                };
                let target = destination_dir.join(&rel);
                assert_contained(destination_dir, &target).map_err(backend_err)?;
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
                    // Extract beside the target and rename over it only on
                    // success: truncating an existing file in place destroyed
                    // it even when extraction later failed or hit the budget,
                    // and cleanup only ever removed files it had created.
                    let tmp = sibling_tmp_path(&target);
                    created.track_temp(&tmp);
                    let out = File::create(&tmp).map_err(backend_err)?;
                    let mut out = std::io::BufWriter::with_capacity(128 * 1024, out);
                    let mut writer = CountingWriter {
                        inner: &mut out,
                        budget: budget.clone(),
                        cancel,
                    };
                    std::io::copy(&mut entry, &mut writer).map_err(backend_err)?;
                    writer.flush().map_err(backend_err)?;
                    drop(writer);
                    #[cfg(unix)]
                    if let Some(mode) = entry.unix_mode() {
                        use std::os::unix::fs::PermissionsExt;
                        let _ = std::fs::set_permissions(
                            &tmp,
                            std::fs::Permissions::from_mode(mode & 0o777),
                        );
                    }
                    created.track_file(&target);
                    install_temp(&tmp, &target).map_err(backend_err)?;
                }
            }
            Ok(())
        }
        ArchiveFormat::Tar => {
            let file = File::open(archive_path).map_err(backend_err)?;
            let reader = CountingReader {
                inner: std::io::BufReader::with_capacity(128 * 1024, file),
                budget: tar_stream_budget(budget),
                cancel,
            };
            let mut archive = tar::Archive::new(reader);
            extract_tar(&mut archive, destination_dir, created, cancel)
        }
        ArchiveFormat::TarGz => {
            let file = File::open(archive_path).map_err(backend_err)?;
            let gz = flate2::read::GzDecoder::new(std::io::BufReader::with_capacity(128 * 1024, file));
            let reader = CountingReader {
                inner: gz,
                budget: tar_stream_budget(budget),
                cancel,
            };
            let mut archive = tar::Archive::new(reader);
            extract_tar(&mut archive, destination_dir, created, cancel)
        }
        ArchiveFormat::SevenZip => {
            // sevenz-rust joins entry names onto the destination without
            // sanitising them, so a crafted archive can write outside it.
            let mut entries_seen = 0usize;
            let file = File::open(archive_path).map_err(backend_err)?;
            let pw = match password {
                Some(p) => sevenz_rust::Password::from(p),
                None => sevenz_rust::Password::empty(),
            };
            let result = sevenz_rust::decompress_with_extract_fn_and_password(
                file,
                destination_dir,
                pw,
                |entry, reader, _dest| {
                    if cancel.is_cancelled() {
                        return Err(sevenz_rust::Error::other("operation cancelled"));
                    }
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
                    assert_contained(destination_dir, &target)
                        .map_err(sevenz_rust::Error::io)?;
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
                        // Same temp-then-install rule as zip: never truncate
                        // an existing file before the entry fully extracted.
                        let tmp = sibling_tmp_path(&target);
                        created.track_temp(&tmp);
                        let file = File::create(&tmp).map_err(sevenz_rust::Error::io)?;
                        let mut file = std::io::BufWriter::with_capacity(128 * 1024, file);
                        let mut limited = CountingReader {
                            inner: reader,
                            budget: budget.clone(),
                            cancel,
                        };
                        std::io::copy(&mut limited, &mut file).map_err(sevenz_rust::Error::io)?;
                        file.flush().map_err(sevenz_rust::Error::io)?;
                        drop(file);
                        created.track_file(&target);
                        install_temp(&tmp, &target).map_err(sevenz_rust::Error::io)?;
                    }
                    Ok(true)
                },
            );
            result.map_err(|e| {
                let msg = match e {
                    sevenz_rust::Error::PasswordRequired => {
                        "ARCHIVE_PASSWORD_REQUIRED: password required to extract 7z".to_string()
                    }
                    sevenz_rust::Error::MaybeBadPassword(_) => {
                        "ARCHIVE_WRONG_PASSWORD: invalid password for 7z".to_string()
                    }
                    other => other.to_string(),
                };
                backend_err(std::io::Error::other(msg))
            })
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
    cancel: &CancellationToken,
) -> VfsResult<()> {
    let mut entries_seen = 0usize;
    let entries = archive.entries().map_err(backend_err)?;
    for entry in entries {
        if cancel.is_cancelled() {
            return Err(cancelled_err());
        }
        let mut entry = entry.map_err(backend_err)?;
        entries_seen += 1;
        if entries_seen > MAX_ENTRIES {
            return Err(backend_err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("archive has too many entries ({entries_seen})"),
            )));
        }
        let entry_path = entry.path().map_err(backend_err)?;
        let entry_str = entry_path.to_string_lossy().replace('\\', "/");
        let target = safe_join(destination_dir, &entry_str).ok_or_else(|| {
            backend_err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("unsafe archive entry path: {entry_str}"),
            ))
        })?;
        assert_contained(destination_dir, &target).map_err(backend_err)?;
        created.track_parent_dirs(&target, destination_dir);
        // Regular files go through a sibling temp so an existing
        // file is only replaced once the entry fully unpacked.
        if entry.header().entry_type().is_file() {
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent).map_err(backend_err)?;
            }
            let tmp = sibling_tmp_path(&target);
            created.track_temp(&tmp);
            entry.unpack(&tmp).map_err(backend_err)?;
            created.track_file(&target);
            install_temp(&tmp, &target).map_err(backend_err)?;
            continue;
        }
        if entry.header().entry_type().is_dir() {
            if !target.exists() && !created.dirs.iter().any(|d| d == &target) {
                created.dirs.push(target.clone());
            }
        } else {
            created.track_file(&target);
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
    create_zip_with_password(sources, destination_zip, None, &CancellationToken::new())
}

/// Compress with cooperative cancellation. The archive is built in a unique
/// sibling temp file and renamed into place only on success, so a cancelled
/// or failed run never truncates or corrupts an archive that already exists.
pub fn create_zip_with_cancel(
    sources: &[impl AsRef<Path>],
    destination_zip: &Path,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    create_zip_with_password(sources, destination_zip, None, cancel)
}

/// Compress into a `.zip` archive with optional AES-256 password encryption and
/// cooperative cancellation.
pub fn create_zip_with_password(
    sources: &[impl AsRef<Path>],
    destination_zip: &Path,
    password: Option<&str>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    let tmp_path = temp_zip_path(destination_zip);
    let result = create_zip_inner(
        sources,
        &tmp_path,
        destination_zip,
        password.filter(|p| !p.is_empty()),
        cancel,
    );
    match result {
        Ok(()) => {
            if let Err(e) = install_temp(&tmp_path, destination_zip) {
                let _ = std::fs::remove_file(&tmp_path);
                return Err(VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: e,
                });
            }
            Ok(())
        }
        Err(e) => {
            let _ = std::fs::remove_file(&tmp_path);
            Err(e)
        }
    }
}

fn copy_with_cancel<R: std::io::Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    let mut buf = [0u8; 128 * 1024];
    loop {
        if cancel.is_cancelled() {
            return Err(cancelled_err());
        }
        let n = reader.read(&mut buf).map_err(backend_err)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n]).map_err(backend_err)?;
    }
    Ok(())
}

fn temp_zip_path(destination_zip: &Path) -> std::path::PathBuf {
    let parent = destination_zip.parent().unwrap_or_else(|| Path::new("."));
    let name = destination_zip
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("archive.zip");
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    parent.join(format!(".{name}.fm-zip-{}-{nanos}", std::process::id()))
}

fn create_zip_inner(
    sources: &[impl AsRef<Path>],
    write_path: &Path,
    final_dest: &Path,
    password: Option<&str>,
    cancel: &CancellationToken,
) -> VfsResult<()> {
    if cancel.is_cancelled() {
        return Err(cancelled_err());
    }
    let file = File::create(write_path).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;
    let mut zip = zip::ZipWriter::new(std::io::BufWriter::with_capacity(128 * 1024, file));
    let mut options: zip::write::FileOptions<'_, '_, ()> = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);
    if let Some(pw) = password {
        options = options.with_aes_encryption(zip::AesMode::Aes256, pw);
    }

    // Exclude both the temp file being written and any pre-existing final
    // archive, so compressing a folder into a zip inside it never pulls the
    // output into itself.
    let mut exclude_canon: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(c) = write_path.canonicalize() {
        exclude_canon.push(c);
    }
    if let Ok(c) = final_dest.canonicalize() {
        if !exclude_canon.contains(&c) {
            exclude_canon.push(c);
        }
    }

    for source_ref in sources {
        if cancel.is_cancelled() {
            return Err(cancelled_err());
        }
        let source = source_ref.as_ref();
        if let Ok(sc) = source.canonicalize() {
            if exclude_canon.contains(&sc) {
                continue;
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
            let f = File::open(source).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut f = std::io::BufReader::with_capacity(128 * 1024, f);
            copy_with_cancel(&mut f, &mut zip, cancel)?;
        } else if source.is_dir() {
            let base_dir = source.parent().unwrap_or_else(|| Path::new(""));
            let dir_name = source
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("folder");
            let dir_entry = format!("{dir_name}/");
            zip.add_directory(&dir_entry, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            add_dir_to_zip(&mut zip, base_dir, source, options, &exclude_canon, cancel)?;
        }
    }

    let mut inner = zip.finish().map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: std::io::Error::other(e.to_string()),
    })?;
    inner.flush().map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;

    Ok(())
}

fn add_dir_to_zip<'a, 'b, W: Write + std::io::Seek>(
    zip: &mut zip::ZipWriter<W>,
    base_dir: &Path,
    current_dir: &Path,
    options: zip::write::FileOptions<'a, 'b, ()>,
    exclude_canon: &[std::path::PathBuf],
    cancel: &CancellationToken,
) -> VfsResult<()> {
    let read_dir = std::fs::read_dir(current_dir).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;

    for entry_res in read_dir {
        if cancel.is_cancelled() {
            return Err(cancelled_err());
        }
        let entry = entry_res.map_err(|e| VfsError::Backend {
            path: fm_core::VfsPath::root(),
            source: e,
        })?;
        let path = entry.path();
        if let Ok(pc) = path.canonicalize() {
            if exclude_canon.contains(&pc) {
                continue;
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
            add_dir_to_zip(zip, base_dir, &path, options, exclude_canon, cancel)?;
        } else if file_type.is_file() {
            zip.start_file(&rel_path_str, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            let f = File::open(&path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut f = std::io::BufReader::with_capacity(128 * 1024, f);
            copy_with_cancel(&mut f, zip, cancel)?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn cancelled_extraction_stops_before_writing() {
        let dir = tempdir().unwrap();
        let zip_path = dir.path().join("many.zip");
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored);
            for i in 0..50 {
                writer.start_file(format!("f{i}.txt"), options).unwrap();
                writer.write_all(b"hello").unwrap();
            }
            writer.finish().unwrap();
        }
        let cancel = CancellationToken::new();
        cancel.cancel();
        let dest = dir.path().join("out");
        assert!(extract_archive_with_cancel(&zip_path, &dest, &cancel).is_err());
        assert!(!dest.join("f0.txt").exists(), "cancelled extraction wrote a file");
    }

    #[test]
    fn failed_extraction_rolls_back_created_files() {
        let dir = tempdir().unwrap();
        let zip_path = dir.path().join("corrupt_second.zip");
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored);
            writer.start_file("first.txt", options).unwrap();
            writer.write_all(b"first file content").unwrap();
            // Second entry has an unsafe path that fails validation mid-extraction
            writer.start_file("../outside.txt", options).unwrap();
            writer.write_all(b"malicious").unwrap();
            writer.finish().unwrap();
        }
        let dest = dir.path().join("out");
        assert!(extract_archive(&zip_path, &dest).is_err());
        assert!(
            !dest.join("first.txt").exists(),
            "first entry should be rolled back when subsequent entry fails"
        );
    }

    #[cfg(unix)]
    #[test]
    fn extraction_refuses_to_follow_a_preexisting_symlink() {
        let dir = tempdir().unwrap();
        let outside = tempdir().unwrap();
        std::fs::write(outside.path().join("victim.txt"), b"original").unwrap();
        let dest = dir.path().join("out");
        std::fs::create_dir(&dest).unwrap();
        std::os::unix::fs::symlink(outside.path(), dest.join("escape")).unwrap();

        let zip_path = dir.path().join("evil.zip");
        {
            let file = File::create(&zip_path).unwrap();
            let mut writer = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default()
                .compression_method(zip::CompressionMethod::Stored);
            // Lexically harmless, but resolves through the planted link.
            writer.start_file("escape/victim.txt", options).unwrap();
            writer.write_all(b"overwritten").unwrap();
            writer.finish().unwrap();
        }
        assert!(extract_archive(&zip_path, &dest).is_err());
        assert_eq!(
            std::fs::read_to_string(outside.path().join("victim.txt")).unwrap(),
            "original"
        );
    }

    #[test]
    fn cancelled_compression_removes_the_partial_zip() {
        let dir = tempdir().unwrap();
        let src = dir.path().join("a.txt");
        std::fs::write(&src, b"data").unwrap();
        let out = dir.path().join("out.zip");
        let cancel = CancellationToken::new();
        cancel.cancel();
        assert!(create_zip_with_cancel(&[&src], &out, &cancel).is_err());
        assert!(!out.exists(), "cancelled compression left a broken zip");
    }

    #[test]
    fn cancelled_compression_keeps_an_existing_zip_intact() {
        let dir = tempdir().unwrap();
        let src = dir.path().join("a.txt");
        std::fs::write(&src, b"data").unwrap();
        let out = dir.path().join("out.zip");
        // A valid pre-existing archive that must survive a cancelled overwrite.
        create_zip(&[&src], &out).unwrap();
        let before = std::fs::read(&out).unwrap();

        let cancel = CancellationToken::new();
        cancel.cancel();
        assert!(create_zip_with_cancel(&[&src], &out, &cancel).is_err());
        assert_eq!(
            std::fs::read(&out).unwrap(),
            before,
            "cancelled overwrite corrupted the existing zip"
        );
        let strays: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().contains(".fm-zip-"))
            .collect();
        assert!(strays.is_empty(), "cancelled compression left a temp file");
    }

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

    #[test]
    fn test_create_zip_preserves_dir_name_and_handles_multiple_dirs() {
        let dir = tempdir().unwrap();
        let folder1 = dir.path().join("folder1");
        let folder2 = dir.path().join("folder2");
        std::fs::create_dir(&folder1).unwrap();
        std::fs::create_dir(&folder2).unwrap();
        std::fs::write(folder1.join("same_name.txt"), "content 1").unwrap();
        std::fs::write(folder2.join("same_name.txt"), "content 2").unwrap();

        let dest_zip = dir.path().join("multi.zip");
        create_zip(&[&folder1, &folder2], &dest_zip).unwrap();

        let file = File::open(&dest_zip).unwrap();
        let mut zip = zip::ZipArchive::new(file).unwrap();
        let names: Vec<String> = (0..zip.len())
            .map(|i| zip.by_index(i).unwrap().name().unwrap().to_string())
            .collect();
        assert!(names.contains(&"folder1/".to_string()));
        assert!(names.contains(&"folder1/same_name.txt".to_string()));
        assert!(names.contains(&"folder2/".to_string()));
        assert!(names.contains(&"folder2/same_name.txt".to_string()));
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
