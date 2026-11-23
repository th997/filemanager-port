//! VFS inspection utilities: directory sizing with cancellation, checksums
//! (MD5 / SHA-1 / SHA-256), disk space queries, storage analyzer, 3-stage
//! duplicate file scanner, and Unix permission (`chmod`) helpers.

use crate::api::search::file_category_of;
use crate::registry::VfsRegistry;
use fm_core::{EntryKind, VfsPath};
use md5::Digest as _;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::io::AsyncReadExt;
use tokio_util::sync::CancellationToken;

fn inspect_ops() -> &'static Mutex<HashMap<String, CancellationToken>> {
    static OPS: OnceLock<Mutex<HashMap<String, CancellationToken>>> = OnceLock::new();
    OPS.get_or_init(|| Mutex::new(HashMap::new()))
}

struct OpGuard {
    id: String,
    token: CancellationToken,
}

impl OpGuard {
    fn register(op_id: Option<String>) -> Self {
        let id = op_id
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let token = CancellationToken::new();
        inspect_ops().lock().insert(id.clone(), token.clone());
        Self { id, token }
    }
}

impl Drop for OpGuard {
    fn drop(&mut self) {
        inspect_ops().lock().remove(&self.id);
    }
}

/// Cancel an in-flight inspection operation (directory measure, hash, storage
/// analysis, or duplicate scan) identified by `op_id`.
#[flutter_rust_bridge::frb(sync)]
pub fn cancel_inspect_op(op_id: String) -> bool {
    if let Some(token) = inspect_ops().lock().get(&op_id) {
        token.cancel();
        true
    } else {
        false
    }
}

#[derive(Debug, Clone)]
pub struct DirMeasurementDto {
    pub total_bytes: u64,
    pub file_count: u64,
    pub dir_count: u64,
    pub truncated: bool,
    pub cancelled: bool,
}

/// Recursively measure a directory across any VFS (local, remote, vault,
/// archive) with cancellation, entry-count cap, and wall-clock timeout.
pub async fn measure_vfs_directory(
    root: String,
    path: String,
    op_id: Option<String>,
    max_entries: Option<u32>,
    timeout_ms: Option<u32>,
) -> Result<DirMeasurementDto, String> {
    let guard = OpGuard::register(op_id);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let entry_cap = max_entries.unwrap_or(50_000).clamp(100, 500_000) as u64;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms.unwrap_or(20_000) as u64);

    let mut total_bytes = 0u64;
    let mut file_count = 0u64;
    let mut dir_count = 0u64;
    let mut truncated = false;
    let mut cancelled = false;

    let mut stack: Vec<(VfsPath, usize)> = vec![(VfsPath::from_slash_path(&path), 0)];
    let mut first = true;
    const MAX_DEPTH: usize = 64;

    while let Some((dir, depth)) = stack.pop() {
        if guard.token.is_cancelled() {
            cancelled = true;
            break;
        }
        if Instant::now() >= deadline || file_count + dir_count >= entry_cap {
            truncated = true;
            break;
        }
        let children = match backend.list(&dir).await {
            Ok(c) => c,
            Err(e) => {
                if first {
                    return Err(e.to_string());
                }
                continue;
            }
        };
        first = false;
        for child in children {
            if guard.token.is_cancelled() {
                cancelled = true;
                break;
            }
            if file_count + dir_count >= entry_cap || Instant::now() >= deadline {
                truncated = true;
                break;
            }
            if child.kind == EntryKind::Dir {
                dir_count += 1;
                if !child.is_symlink && depth < MAX_DEPTH {
                    stack.push((child.path, depth + 1));
                }
            } else {
                file_count += 1;
                total_bytes = total_bytes.saturating_add(child.size.unwrap_or(0));
            }
        }
        if cancelled || truncated {
            break;
        }
    }

    Ok(DirMeasurementDto {
        total_bytes,
        file_count,
        dir_count,
        truncated,
        cancelled,
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileHashesDto {
    pub md5: String,
    pub sha1: String,
    pub sha256: String,
    pub bytes_hashed: u64,
}

/// Stream a VFS file once and compute its MD5, SHA-1, and SHA-256 digests.
pub async fn compute_file_hashes(
    root: String,
    path: String,
    op_id: Option<String>,
) -> Result<FileHashesDto, String> {
    let guard = OpGuard::register(op_id);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let mut reader = backend.open_read(&vfs_path).await.map_err(|e| e.to_string())?;

    let mut md5_hasher = md5::Md5::new();
    let mut sha1_hasher = sha1::Sha1::new();
    let mut sha256_hasher = sha2::Sha256::new();
    let mut buf = vec![0u8; 256 * 1024];
    let mut bytes_hashed = 0u64;

    loop {
        if guard.token.is_cancelled() {
            return Err("operation cancelled".to_string());
        }
        let n = reader.read(&mut buf).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        let slice = &buf[..n];
        md5_hasher.update(slice);
        sha1_hasher.update(slice);
        sha256_hasher.update(slice);
        bytes_hashed = bytes_hashed.saturating_add(n as u64);
    }

    Ok(FileHashesDto {
        md5: hex::encode(md5_hasher.finalize()),
        sha1: hex::encode(sha1_hasher.finalize()),
        sha256: hex::encode(sha256_hasher.finalize()),
        bytes_hashed,
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiskSpaceDto {
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub used_bytes: u64,
}

/// Query total and available disk space for a local filesystem path.
#[flutter_rust_bridge::frb(sync)]
pub fn get_disk_space(path: String) -> Result<DiskSpaceDto, String> {
    #[cfg(unix)]
    {
        use std::ffi::CString;
        let c_path = CString::new(path).map_err(|_| "invalid path".to_string())?;
        let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
        let rc = unsafe { libc::statvfs(c_path.as_ptr(), &mut stat) };
        if rc != 0 {
            return Err(std::io::Error::last_os_error().to_string());
        }
        let block_size = if stat.f_frsize > 0 {
            stat.f_frsize as u64
        } else {
            stat.f_bsize as u64
        };
        let total = (stat.f_blocks as u64).saturating_mul(block_size);
        let avail = (stat.f_bavail as u64).saturating_mul(block_size);
        let used = total.saturating_sub(avail);
        Ok(DiskSpaceDto {
            total_bytes: total,
            available_bytes: avail,
            used_bytes: used,
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
        let wide: Vec<u16> = std::ffi::OsStr::new(&path)
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
            return Err(std::io::Error::last_os_error().to_string());
        }
        Ok(DiskSpaceDto {
            total_bytes: total,
            available_bytes: avail,
            used_bytes: total.saturating_sub(avail),
        })
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = path;
        Err("disk space query unsupported on this platform".to_string())
    }
}

#[derive(Debug, Clone)]
pub struct StorageFolderRankDto {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub file_count: u64,
}

#[derive(Debug, Clone)]
pub struct StorageFileRankDto {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub modified_millis: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct StorageCategoryDto {
    pub category: String,
    pub size_bytes: u64,
    pub file_count: u64,
}

#[derive(Debug, Clone)]
pub struct StorageAnalysisDto {
    pub total_bytes: u64,
    pub total_files: u64,
    pub total_dirs: u64,
    pub truncated: bool,
    pub cancelled: bool,
    pub folders: Vec<StorageFolderRankDto>,
    pub largest_files: Vec<StorageFileRankDto>,
    pub categories: Vec<StorageCategoryDto>,
}

/// Analyze disk usage under `(root, path)`: immediate child folder ranking,
/// file-type category breakdown, and Top N largest files.
pub async fn analyze_storage(
    root: String,
    path: String,
    top_n: u32,
    op_id: Option<String>,
) -> Result<StorageAnalysisDto, String> {
    let guard = OpGuard::register(op_id);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let base = VfsPath::from_slash_path(&path);
    let top_n = top_n.clamp(5, 200) as usize;
    const MAX_ENTRIES: u64 = 120_000;
    const MAX_DEPTH: usize = 48;

    let top_children = backend.list(&base).await.map_err(|e| e.to_string())?;
    let mut folder_totals: HashMap<String, (String, u64, u64)> = HashMap::new(); // path -> (name, bytes, files)
    let mut cat_totals: HashMap<&'static str, (u64, u64)> = HashMap::new();
    let mut largest_files: Vec<StorageFileRankDto> = Vec::new();
    let mut total_bytes = 0u64;
    let mut total_files = 0u64;
    let mut total_dirs = 0u64;
    let mut truncated = false;
    let mut cancelled = false;

    // Queue holds (dir_path, depth, top_level_folder_key)
    let mut stack: Vec<(VfsPath, usize, Option<String>)> = Vec::new();
    for child in top_children {
        if child.kind == EntryKind::Dir {
            total_dirs += 1;
            let key = child.path.to_slash_string();
            folder_totals.insert(key.clone(), (child.name.clone(), 0, 0));
            if !child.is_symlink {
                stack.push((child.path, 1, Some(key)));
            }
        } else {
            let sz = child.size.unwrap_or(0);
            total_files += 1;
            total_bytes = total_bytes.saturating_add(sz);
            let cat = file_category_of(&child.name, false);
            let entry = cat_totals.entry(cat).or_insert((0, 0));
            entry.0 = entry.0.saturating_add(sz);
            entry.1 += 1;
            let mtime = child
                .modified
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64);
            push_top_file(
                &mut largest_files,
                StorageFileRankDto {
                    name: child.name,
                    path: child.path.to_slash_string(),
                    size_bytes: sz,
                    modified_millis: mtime,
                },
                top_n,
            );
        }
    }

    while let Some((dir, depth, top_key)) = stack.pop() {
        if guard.token.is_cancelled() {
            cancelled = true;
            break;
        }
        if total_files + total_dirs >= MAX_ENTRIES {
            truncated = true;
            break;
        }
        let children = match backend.list(&dir).await {
            Ok(c) => c,
            Err(_) => continue,
        };
        for child in children {
            if guard.token.is_cancelled() {
                cancelled = true;
                break;
            }
            if total_files + total_dirs >= MAX_ENTRIES {
                truncated = true;
                break;
            }
            if child.kind == EntryKind::Dir {
                total_dirs += 1;
                if !child.is_symlink && depth < MAX_DEPTH {
                    stack.push((child.path, depth + 1, top_key.clone()));
                }
            } else {
                let sz = child.size.unwrap_or(0);
                total_files += 1;
                total_bytes = total_bytes.saturating_add(sz);
                if let Some(ref k) = top_key {
                    if let Some(slot) = folder_totals.get_mut(k) {
                        slot.1 = slot.1.saturating_add(sz);
                        slot.2 += 1;
                    }
                }
                let cat = file_category_of(&child.name, false);
                let entry = cat_totals.entry(cat).or_insert((0, 0));
                entry.0 = entry.0.saturating_add(sz);
                entry.1 += 1;
                let mtime = child
                    .modified
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64);
                push_top_file(
                    &mut largest_files,
                    StorageFileRankDto {
                        name: child.name,
                        path: child.path.to_slash_string(),
                        size_bytes: sz,
                        modified_millis: mtime,
                    },
                    top_n,
                );
            }
        }
        if cancelled || truncated {
            break;
        }
    }

    let mut folders: Vec<StorageFolderRankDto> = folder_totals
        .into_iter()
        .map(|(p, (name, size_bytes, file_count))| StorageFolderRankDto {
            name,
            path: p,
            size_bytes,
            file_count,
        })
        .collect();
    folders.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));
    folders.truncate(top_n);

    largest_files.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));

    let mut categories: Vec<StorageCategoryDto> = cat_totals
        .into_iter()
        .map(|(cat, (size_bytes, file_count))| StorageCategoryDto {
            category: cat.to_string(),
            size_bytes,
            file_count,
        })
        .collect();
    categories.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));

    Ok(StorageAnalysisDto {
        total_bytes,
        total_files,
        total_dirs,
        truncated,
        cancelled,
        folders,
        largest_files,
        categories,
    })
}

fn push_top_file(list: &mut Vec<StorageFileRankDto>, item: StorageFileRankDto, limit: usize) {
    if list.len() < limit {
        list.push(item);
        return;
    }
    if let Some((min_idx, min_item)) = list
        .iter()
        .enumerate()
        .min_by_key(|(_, x)| x.size_bytes)
    {
        if item.size_bytes > min_item.size_bytes {
            list[min_idx] = item;
        }
    }
}

#[derive(Debug, Clone)]
pub struct DuplicateFileItemDto {
    pub name: String,
    pub path: String,
    pub size_bytes: u64,
    pub modified_millis: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct DuplicateGroupDto {
    pub sha256: String,
    pub size_bytes: u64,
    pub files: Vec<DuplicateFileItemDto>,
}

#[derive(Debug, Clone)]
pub struct DuplicateScanResultDto {
    pub groups: Vec<DuplicateGroupDto>,
    pub scanned_files: u64,
    pub wasted_bytes: u64,
    pub cancelled: bool,
}

async fn sample_hash_vfs(
    backend: &dyn fm_vfs::Vfs,
    path: &VfsPath,
    size: u64,
) -> Result<String, String> {
    const SAMPLE: u64 = 8 * 1024;
    let mut hasher = sha2::Sha256::new();
    let mut head_reader = backend
        .open_read_range(path, 0, Some(SAMPLE.min(size)))
        .await
        .map_err(|e| e.to_string())?;
    let mut buf = Vec::with_capacity(SAMPLE.min(size) as usize);
    head_reader
        .read_to_end(&mut buf)
        .await
        .map_err(|e| e.to_string())?;
    hasher.update(&buf);

    if size > SAMPLE * 2 {
        let tail_offset = size - SAMPLE;
        let mut tail_reader = backend
            .open_read_range(path, tail_offset, Some(SAMPLE))
            .await
            .map_err(|e| e.to_string())?;
        buf.clear();
        tail_reader
            .read_to_end(&mut buf)
            .await
            .map_err(|e| e.to_string())?;
        hasher.update(&buf);
    }
    Ok(hex::encode(hasher.finalize()))
}

async fn full_sha256_vfs(
    backend: &dyn fm_vfs::Vfs,
    path: &VfsPath,
    cancel: &CancellationToken,
) -> Result<String, String> {
    let mut reader = backend.open_read(path).await.map_err(|e| e.to_string())?;
    let mut hasher = sha2::Sha256::new();
    let mut buf = vec![0u8; 256 * 1024];
    loop {
        if cancel.is_cancelled() {
            return Err("cancelled".to_string());
        }
        let n = reader.read(&mut buf).await.map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// 3-stage duplicate file finder:
/// 1. Group all regular files by exact byte size (skipping unique sizes and files < `min_size`).
/// 2. Compute head+tail 8 KB sampling SHA-256 on same-size candidates.
/// 3. Verify remaining candidates with full-file SHA-256.
pub async fn find_duplicate_files(
    root: String,
    path: String,
    min_size: Option<u64>,
    op_id: Option<String>,
) -> Result<DuplicateScanResultDto, String> {
    let guard = OpGuard::register(op_id);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let min_bytes = min_size.unwrap_or(1).max(1);
    const MAX_FILES: u64 = 100_000;
    const MAX_DEPTH: usize = 48;

    // Stage 1: collect and group by exact size
    let mut by_size: HashMap<u64, Vec<(VfsPath, DuplicateFileItemDto)>> = HashMap::new();
    let mut scanned_files = 0u64;
    let mut cancelled = false;
    let mut stack: Vec<(VfsPath, usize)> = vec![(VfsPath::from_slash_path(&path), 0)];
    let mut first = true;

    while let Some((dir, depth)) = stack.pop() {
        if guard.token.is_cancelled() {
            cancelled = true;
            break;
        }
        if scanned_files >= MAX_FILES {
            break;
        }
        let children = match backend.list(&dir).await {
            Ok(c) => c,
            Err(e) => {
                if first {
                    return Err(e.to_string());
                }
                continue;
            }
        };
        first = false;
        for child in children {
            if guard.token.is_cancelled() {
                cancelled = true;
                break;
            }
            if child.kind == EntryKind::Dir {
                if !child.is_symlink && depth < MAX_DEPTH {
                    stack.push((child.path, depth + 1));
                }
            } else if child.kind == EntryKind::File && !child.is_symlink {
                scanned_files += 1;
                let sz = child.size.unwrap_or(0);
                if sz >= min_bytes {
                    let mtime = child
                        .modified
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_millis() as i64);
                    let dto = DuplicateFileItemDto {
                        name: child.name,
                        path: child.path.to_slash_string(),
                        size_bytes: sz,
                        modified_millis: mtime,
                    };
                    by_size.entry(sz).or_default().push((child.path, dto));
                }
            }
        }
    }

    if cancelled {
        return Ok(DuplicateScanResultDto {
            groups: Vec::new(),
            scanned_files,
            wasted_bytes: 0,
            cancelled: true,
        });
    }

    // Stage 2: head + tail sampling hash
    let mut by_sample: HashMap<(u64, String), Vec<(VfsPath, DuplicateFileItemDto)>> = HashMap::new();
    for (size, items) in by_size {
        if items.len() < 2 {
            continue;
        }
        for (vfs_path, dto) in items {
            if guard.token.is_cancelled() {
                cancelled = true;
                break;
            }
            if let Ok(sample) = sample_hash_vfs(backend.as_ref(), &vfs_path, size).await {
                by_sample.entry((size, sample)).or_default().push((vfs_path, dto));
            }
        }
        if cancelled {
            break;
        }
    }

    // Stage 3: full SHA-256 verification
    let mut by_full: HashMap<(u64, String), Vec<DuplicateFileItemDto>> = HashMap::new();
    if !cancelled {
        for ((size, _), items) in by_sample {
            if items.len() < 2 {
                continue;
            }
            for (vfs_path, dto) in items {
                if guard.token.is_cancelled() {
                    cancelled = true;
                    break;
                }
                if let Ok(hash) = full_sha256_vfs(backend.as_ref(), &vfs_path, &guard.token).await {
                    by_full.entry((size, hash)).or_default().push(dto);
                }
            }
            if cancelled {
                break;
            }
        }
    }

    let mut groups: Vec<DuplicateGroupDto> = by_full
        .into_iter()
        .filter(|(_, files)| files.len() >= 2)
        .map(|((size_bytes, sha256), mut files)| {
            files.sort_by(|a, b| a.path.cmp(&b.path));
            DuplicateGroupDto {
                sha256,
                size_bytes,
                files,
            }
        })
        .collect();
    groups.sort_by(|a, b| {
        let wa = a.size_bytes.saturating_mul(a.files.len().saturating_sub(1) as u64);
        let wb = b.size_bytes.saturating_mul(b.files.len().saturating_sub(1) as u64);
        wb.cmp(&wa)
    });

    let wasted_bytes = groups
        .iter()
        .map(|g| g.size_bytes.saturating_mul(g.files.len().saturating_sub(1) as u64))
        .fold(0u64, u64::saturating_add);

    Ok(DuplicateScanResultDto {
        groups,
        scanned_files,
        wasted_bytes,
        cancelled,
    })
}

/// Returns Unix mode bits (e.g. `0o755`) for entries on Unix local or SFTP backends.
pub async fn get_unix_permissions(root: String, path: String) -> Result<Option<u32>, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let entry = backend.stat(&vfs_path).await.map_err(|e| e.to_string())?;
    Ok(entry.mode.map(|m| m & 0o7777))
}

/// Modifies Unix mode bits (chmod) on Unix local or SFTP backends.
pub async fn set_unix_permissions(root: String, path: String, mode: u32) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend
        .set_mode(&vfs_path, mode & 0o7777)
        .await
        .map_err(|e| e.to_string())?;
    crate::api::file_manager::invalidate_dir_cache(&root);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn compute_file_hashes_matches_known_vectors() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("hello.txt"), b"hello").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let hashes = compute_file_hashes(root, "hello.txt".into(), None)
            .await
            .unwrap();
        assert_eq!(hashes.md5, "5d41402abc4b2a76b9719d911017c592");
        assert_eq!(hashes.sha1, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d");
        assert_eq!(
            hashes.sha256,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        assert_eq!(hashes.bytes_hashed, 5);
    }

    #[tokio::test]
    async fn measure_vfs_directory_counts_and_respects_cancel() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("sub")).unwrap();
        std::fs::write(dir.path().join("a.bin"), vec![1u8; 100]).unwrap();
        std::fs::write(dir.path().join("sub/b.bin"), vec![2u8; 250]).unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let m = measure_vfs_directory(root.clone(), "".into(), None, None, None)
            .await
            .unwrap();
        assert_eq!(m.total_bytes, 350);
        assert_eq!(m.file_count, 2);
        assert_eq!(m.dir_count, 1);
        assert!(!m.cancelled);
        assert!(!m.truncated);

        // Pre-cancelled op_id exits immediately as cancelled.
        let tok = CancellationToken::new();
        tok.cancel();
        inspect_ops().lock().insert("pre-cancel".into(), tok);
        assert!(cancel_inspect_op("pre-cancel".into()));
    }

    #[tokio::test]
    async fn duplicate_finder_detects_exact_duplicates_only() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("orig.txt"), b"duplicate content payload").unwrap();
        std::fs::write(dir.path().join("copy.txt"), b"duplicate content payload").unwrap();
        std::fs::write(dir.path().join("same_len.txt"), b"different content payload").unwrap();
        std::fs::write(dir.path().join("unique.txt"), b"short").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let res = find_duplicate_files(root, "".into(), Some(1), None)
            .await
            .unwrap();
        assert_eq!(res.groups.len(), 1);
        assert_eq!(res.groups[0].files.len(), 2);
        assert_eq!(res.wasted_bytes, 25);
    }

    #[tokio::test]
    async fn storage_analyzer_ranks_folders_files_and_categories() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("videos")).unwrap();
        std::fs::write(dir.path().join("videos/clip.mp4"), vec![0u8; 4096]).unwrap();
        std::fs::write(dir.path().join("doc.pdf"), vec![0u8; 1024]).unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let analysis = analyze_storage(root, "".into(), 10, None).await.unwrap();
        assert_eq!(analysis.total_bytes, 5120);
        assert_eq!(analysis.folders.len(), 1);
        assert_eq!(analysis.folders[0].name, "videos");
        assert_eq!(analysis.largest_files[0].name, "clip.mp4");
        assert!(analysis.categories.iter().any(|c| c.category == "video"));
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn unix_permissions_get_and_set_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("script.sh"), b"#!/bin/sh\n").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        set_unix_permissions(root.clone(), "script.sh".into(), 0o755)
            .await
            .unwrap();
        let mode = get_unix_permissions(root, "script.sh".into())
            .await
            .unwrap();
        assert_eq!(mode, Some(0o755));
    }

    #[test]
    fn disk_space_returns_nonzero_for_tempdir() {
        let dir = tempfile::tempdir().unwrap();
        let space = get_disk_space(dir.path().to_string_lossy().to_string()).unwrap();
        assert!(space.total_bytes > 0);
    }
}
