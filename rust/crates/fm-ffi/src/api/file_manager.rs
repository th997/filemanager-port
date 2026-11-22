use crate::registry::VfsRegistry;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::Path;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[derive(Clone)]
struct DirCacheEntry {
    created_at: Instant,
    dtos: Vec<EntryDto>,
}

/// (root, slash path, filter, show hidden) — the four values that make a
/// directory listing unique.
type DirCacheKey = (String, String, String, bool);
type DirCache = Mutex<HashMap<DirCacheKey, DirCacheEntry>>;

fn dir_cache() -> &'static DirCache {
    static CACHE: OnceLock<DirCache> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(crate) fn invalidate_dir_cache(root: &str) {
    let mut cache = dir_cache().lock();
    cache.retain(|(r, _, _, _), _| r != root);
}

pub(crate) fn invalidate_dir_cache_for_vault(vault_id: &str) {
    let vault_root = format!("vault://{vault_id}");
    let archive_exact = format!("archive://{vault_root}");
    let archive_prefix = format!("{archive_exact}/");
    let mut cache = dir_cache().lock();
    cache.retain(|(r, _, _, _), _| {
        r != &vault_root && r != &archive_exact && !r.starts_with(&archive_prefix)
    });
}

pub(crate) fn invalidate_local_dir_caches() {
    let mut cache = dir_cache().lock();
    cache.retain(|(r, _, _, _), _| {
        r.starts_with("remote://") || r.starts_with("archive://") || r.starts_with("vault://")
    });
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CapabilitiesDto {
    pub read: bool,
    pub write: bool,
    pub rename: bool,
    pub copy: bool,
    pub mkdir: bool,
    pub remove: bool,
    pub serve_http: bool,
    pub serve_ftp: bool,
}

impl From<Capabilities> for CapabilitiesDto {
    fn from(c: Capabilities) -> Self {
        Self {
            read: c.read,
            write: c.write,
            rename: c.rename,
            copy: c.copy,
            mkdir: c.mkdir,
            remove: c.remove,
            serve_http: c.serve_http,
            serve_ftp: c.serve_ftp,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryDto {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: Option<u64>,
    pub modified_millis: Option<i64>,
    pub hidden: bool,
    pub is_symlink: bool,
}

impl From<Entry> for EntryDto {
    fn from(entry: Entry) -> Self {
        Self {
            name: entry.name,
            path: entry.path.to_slash_string(),
            is_dir: entry.kind == EntryKind::Dir,
            size: entry.size,
            modified_millis: entry
                .modified
                .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|duration| duration.as_millis() as i64),
            hidden: entry.hidden,
            is_symlink: entry.is_symlink,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PagedEntriesDto {
    pub entries: Vec<EntryDto>,
    pub page: u32,
    pub page_size: u32,
    pub has_more: bool,
    /// Total entries in the folder (all pages), so the UI can show real
    /// counts and fetch everything at once when the user selects all.
    pub total: u32,
}

/// Natural (human) ordering: case-insensitive, digit runs compare
/// numerically. Uses zero heap allocations by streaming sub-slices.
fn natural_compare(mut a: &str, mut b: &str) -> std::cmp::Ordering {
    fn next_chunk<'a>(s: &mut &'a str) -> Option<(&'a str, bool)> {
        if s.is_empty() {
            return None;
        }
        if s.is_ascii() {
            let bytes = s.as_bytes();
            let is_digit = bytes[0].is_ascii_digit();
            let end = bytes
                .iter()
                .position(|&b| b.is_ascii_digit() != is_digit)
                .unwrap_or(bytes.len());
            let chunk = &s[..end];
            *s = &s[end..];
            Some((chunk, is_digit))
        } else {
            let first = s.chars().next()?;
            let is_digit = first.is_ascii_digit();
            let end = s
                .char_indices()
                .find(|&(_, ch)| ch.is_ascii_digit() != is_digit)
                .map(|(idx, _)| idx)
                .unwrap_or(s.len());
            let chunk = &s[..end];
            *s = &s[end..];
            Some((chunk, is_digit))
        }
    }

    let mut first_numeric_tie_break = std::cmp::Ordering::Equal;

    loop {
        match (next_chunk(&mut a), next_chunk(&mut b)) {
            (Some((pa, true)), Some((pb, true))) => {
                let na: Option<u128> = pa.parse().ok();
                let nb: Option<u128> = pb.parse().ok();
                let cmp = match (na, nb) {
                    (Some(x), Some(y)) => x.cmp(&y),
                    _ => pa.cmp(pb),
                };
                if cmp != std::cmp::Ordering::Equal {
                    return cmp;
                }
                if first_numeric_tie_break == std::cmp::Ordering::Equal && pa != pb {
                    first_numeric_tie_break = pa.len().cmp(&pb.len()).then_with(|| pa.cmp(pb));
                }
            }
            (Some((pa, _)), Some((pb, _))) => {
                let cmp = if pa.is_ascii() && pb.is_ascii() {
                    if pa.eq_ignore_ascii_case(pb) {
                        std::cmp::Ordering::Equal
                    } else {
                        pa.as_bytes()
                            .iter()
                            .map(u8::to_ascii_lowercase)
                            .cmp(pb.as_bytes().iter().map(u8::to_ascii_lowercase))
                    }
                } else {
                    pa.chars()
                        .map(|c| c.to_ascii_lowercase())
                        .cmp(pb.chars().map(|c| c.to_ascii_lowercase()))
                };
                if cmp != std::cmp::Ordering::Equal {
                    return cmp;
                }
            }
            (Some(_), None) => return std::cmp::Ordering::Greater,
            (None, Some(_)) => return std::cmp::Ordering::Less,
            (None, None) => return first_numeric_tie_break,
        }
    }
}

fn extension_of(e: &EntryDto) -> &str {
    if e.is_dir {
        return "";
    }
    match e.name.rfind('.') {
        Some(idx) if idx > 0 => &e.name[idx + 1..],
        _ => "",
    }
}

fn compare_extensions(a: &EntryDto, b: &EntryDto) -> std::cmp::Ordering {
    let ea = extension_of(a);
    let eb = extension_of(b);
    if ea.is_ascii() && eb.is_ascii() {
        ea.as_bytes()
            .iter()
            .map(u8::to_ascii_lowercase)
            .cmp(eb.as_bytes().iter().map(u8::to_ascii_lowercase))
    } else {
        ea.chars()
            .map(|c| c.to_ascii_lowercase())
            .cmp(eb.chars().map(|c| c.to_ascii_lowercase()))
    }
}

/// Sort a full folder listing the way the UI promises: directories first
/// (in both directions), then the requested key. This used to happen in
/// Dart over only the pages fetched so far, so "sort by size" in a large
/// folder actually sorted just the first hundred entries.
fn sort_dtos(entries: &mut [EntryDto], sort_by: &str, ascending: bool) {
    entries.sort_unstable_by(|a, b| {
        if a.is_dir != b.is_dir {
            return if a.is_dir {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Greater
            };
        }
        let cmp = match sort_by {
            "size" => a.size.unwrap_or(0).cmp(&b.size.unwrap_or(0)),
            "modified" => a
                .modified_millis
                .unwrap_or(0)
                .cmp(&b.modified_millis.unwrap_or(0)),
            "type" => compare_extensions(a, b)
                .then_with(|| natural_compare(&a.name, &b.name)),
            _ => natural_compare(&a.name, &b.name),
        }
        .then_with(|| a.name.cmp(&b.name));
        if ascending {
            cmp
        } else {
            cmp.reverse()
        }
    });
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_database(db_path: String) {
    VfsRegistry::global().set_database_path(db_path);
}

pub async fn get_capabilities(root: String) -> CapabilitiesDto {
    match VfsRegistry::global().get_or_create(&root).await {
        Ok(vfs) => vfs.capabilities().into(),
        Err(_) => Capabilities::READ_ONLY.into(),
    }
}

pub async fn list_dir(root: String, path: String) -> Result<Vec<EntryDto>, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend
        .list(&vfs_path)
        .await
        .map(|entries| entries.into_iter().map(EntryDto::from).collect())
        .map_err(|error| error.to_string())
}

pub async fn list_dir_paged(
    root: String,
    path: String,
    page: u32,
    page_size: u32,
    sort_by: String,
    sort_ascending: bool,
) -> Result<PagedEntriesDto, String> {
    let cache_key = (root.clone(), path.clone(), sort_by.clone(), sort_ascending);
    let ttl = Duration::from_secs(5);

    let cached_dtos = {
        let mut cache = dir_cache().lock();
        let now = Instant::now();
        cache.retain(|_, entry| now.saturating_duration_since(entry.created_at) < ttl);
        if page > 1 {
            cache.get(&cache_key).and_then(|entry| {
                if now.saturating_duration_since(entry.created_at) < ttl {
                    Some(entry.dtos.clone())
                } else {
                    None
                }
            })
        } else {
            None
        }
    };

    let dtos = match cached_dtos {
        Some(dtos) => dtos,
        None => {
            let backend = VfsRegistry::global().get_or_create(&root).await?;
            let vfs_path = VfsPath::from_slash_path(&path);
            let all = backend
                .list(&vfs_path)
                .await
                .map_err(|error| error.to_string())?;
            let mut dtos: Vec<EntryDto> = all.into_iter().map(EntryDto::from).collect();
            sort_dtos(&mut dtos, &sort_by, sort_ascending);

            let mut cache = dir_cache().lock();
            cache.insert(
                cache_key,
                DirCacheEntry {
                    created_at: Instant::now(),
                    dtos: dtos.clone(),
                },
            );
            dtos
        }
    };

    let total = dtos.len() as u32;
    let page = page.max(1);
    let page_size = page_size.max(1);
    let skip = ((page - 1) as usize).saturating_mul(page_size as usize);
    let has_more = skip + (page_size as usize) < total as usize;
    let entries = dtos
        .into_iter()
        .skip(skip)
        .take(page_size as usize)
        .collect();

    Ok(PagedEntriesDto {
        entries,
        page,
        page_size,
        has_more,
        total,
    })
}

fn contains_ignore_case(haystack: &str, needle_lower: &str) -> bool {
    if needle_lower.is_empty() {
        return true;
    }
    if haystack.is_ascii() && needle_lower.is_ascii() {
        let needle_bytes = needle_lower.as_bytes();
        let haystack_bytes = haystack.as_bytes();
        if needle_bytes.len() > haystack_bytes.len() {
            return false;
        }
        haystack_bytes
            .windows(needle_bytes.len())
            .any(|window| window.eq_ignore_ascii_case(needle_bytes))
    } else {
        haystack.to_lowercase().contains(needle_lower)
    }
}

/// Recursive name search under `path`. Added because the UI's "search"
/// was really a filter over whichever pages had been fetched — it never
/// looked inside subfolders. Safety bounds keep a pathological tree (a
/// huge NAS share) from running away: result cap, visited-dir cap, depth
/// cap. Symlinked directories are not descended into, like everywhere
/// else in the app; unreadable subfolders are skipped, not fatal.
pub async fn search_entries(
    root: String,
    path: String,
    query: String,
    max_results: u32,
) -> Result<Vec<EntryDto>, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let needle = query.trim().to_lowercase();
    if needle.is_empty() {
        return Ok(Vec::new());
    }
    let max_results = max_results.clamp(1, 1000) as usize;
    const MAX_DIRS: usize = 5000;
    const MAX_DEPTH: usize = 32;

    let mut results: Vec<EntryDto> = Vec::new();
    let mut visited = 0usize;
    let mut first = true;
    let mut stack: Vec<(VfsPath, usize)> = vec![(VfsPath::from_slash_path(&path), 0)];
    while let Some((dir, depth)) = stack.pop() {
        if results.len() >= max_results || visited >= MAX_DIRS {
            break;
        }
        visited += 1;
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
            let descend =
                child.kind == EntryKind::Dir && !child.is_symlink && depth < MAX_DEPTH;
            let child_path = child.path.clone();
            if contains_ignore_case(&child.name, &needle) {
                results.push(EntryDto::from(child));
                if results.len() >= max_results {
                    break;
                }
            }
            if descend {
                stack.push((child_path, depth + 1));
            }
        }
    }
    Ok(results)
}

pub async fn stat_entry(root: String, path: String) -> Result<EntryDto, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend
        .stat(&vfs_path)
        .await
        .map(EntryDto::from)
        .map_err(|error| error.to_string())
}

pub async fn create_dir(root: String, path: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend.mkdir(&vfs_path).await.map_err(|e| e.to_string())?;
    invalidate_dir_cache(&root);
    Ok(())
}

pub async fn remove_entry(root: String, path: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend.remove(&vfs_path).await.map_err(|e| e.to_string())?;
    invalidate_dir_cache(&root);
    Ok(())
}

pub async fn rename_entry(root: String, from: String, to: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let from_path = VfsPath::from_slash_path(&from);
    let to_path = VfsPath::from_slash_path(&to);
    backend
        .rename(&from_path, &to_path)
        .await
        .map_err(|e| e.to_string())?;
    invalidate_dir_cache(&root);
    Ok(())
}

/// Upper bound for opening a file in the text editor. The old code read
/// unboundedly into memory twice over (Rust buffer + Dart string), so a
/// stray tap on a several-hundred-MB log could OOM the whole app.
const MAX_TEXT_EDIT_BYTES: u64 = 50 * 1024 * 1024;

/// Reads raw file bytes into memory up to `max_bytes` (default 50 MB).
/// Used for in-memory previewing/viewing of encrypted privacy folder files
/// without spilling plaintext to temporary disk files.
pub async fn read_file_bytes(
    root: String,
    path: String,
    max_bytes: Option<u64>,
) -> Result<Vec<u8>, String> {
    let limit = max_bytes.unwrap_or(MAX_TEXT_EDIT_BYTES).min(256 * 1024 * 1024);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let reader = backend.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    reader
        .take(limit + 1)
        .read_to_end(&mut bytes)
        .await
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > limit {
        return Err(format!("file exceeds in-memory read limit ({limit} bytes)"));
    }
    Ok(bytes)
}

pub async fn read_text_file(root: String, path: String) -> Result<String, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let reader = backend.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    reader
        .take(MAX_TEXT_EDIT_BYTES + 1)
        .read_to_end(&mut bytes)
        .await
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_TEXT_EDIT_BYTES {
        return Err(
            "file is too large to open in the text editor (limit 50 MB)".to_string(),
        );
    }
    // Decode as UTF-8 first. If that fails, fall back to GB18030: a large
    // share of real-world non-UTF-8 text (Windows Notepad saves in Chinese
    // locales, CSV exports) is GBK-family. The previous lossy decode showed
    // `�` everywhere — and pressing Save then wrote those replacement
    // characters back over the original bytes, silently destroying the file.
    match String::from_utf8(bytes) {
        Ok(text) => Ok(text),
        Err(e) => {
            let bytes = e.into_bytes();
            let (text, _, had_errors) = encoding_rs::GB18030.decode(&bytes);
            if had_errors {
                return Err("file is not valid UTF-8 or GB18030 text".to_string());
            }
            Ok(text.into_owned())
        }
    }
}

#[derive(Debug, Clone)]
pub struct TextChunkDto {
    pub text: String,
    pub start_offset: u64,
    pub end_offset: u64,
    pub total_size: u64,
    pub encoding: String,
    pub has_prev: bool,
    pub has_next: bool,
}

fn decode_text_chunk_bytes(
    bytes: &[u8],
    start_offset: u64,
    has_more_bytes: bool,
) -> Result<(String, usize, usize, String), String> {
    if bytes.is_empty() {
        return Ok((String::new(), 0, 0, "utf-8".to_string()));
    }
    let mut lead = 0usize;
    if start_offset > 0 {
        while lead < bytes.len() && lead < 3 && (bytes[lead] & 0xC0) == 0x80 {
            lead += 1;
        }
    }
    let trimmed = &bytes[lead..];
    match std::str::from_utf8(trimmed) {
        Ok(s) => {
            let len = s.len();
            Ok((s.to_string(), lead, lead + len, "utf-8".to_string()))
        }
        Err(err) => {
            if err.error_len().is_none() && has_more_bytes && err.valid_up_to() > 0 {
                let valid = &trimmed[..err.valid_up_to()];
                let s = std::str::from_utf8(valid).map_err(|e| e.to_string())?;
                let len = s.len();
                return Ok((s.to_string(), lead, lead + len, "utf-8".to_string()));
            }
            let (text, _, had_errors) = encoding_rs::GB18030.decode(bytes);
            if !had_errors {
                return Ok((text.into_owned(), 0, bytes.len(), "gb18030".to_string()));
            }
            if has_more_bytes && bytes.len() > 1 {
                let (text2, _, had_errors2) =
                    encoding_rs::GB18030.decode(&bytes[..bytes.len() - 1]);
                if !had_errors2 {
                    return Ok((text2.into_owned(), 0, bytes.len() - 1, "gb18030".to_string()));
                }
            }
            Err("file is not valid UTF-8 or GB18030 text".to_string())
        }
    }
}

pub async fn read_text_chunk(
    root: String,
    path: String,
    offset: u64,
    max_bytes: u64,
) -> Result<TextChunkDto, String> {
    let window = max_bytes.clamp(4 * 1024, 2 * 1024 * 1024);
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let total_size = backend.stat(&vfs_path).await.ok().and_then(|e| e.size).unwrap_or(0);
    if total_size > 0 && offset >= total_size {
        return Ok(TextChunkDto {
            text: String::new(),
            start_offset: total_size,
            end_offset: total_size,
            total_size,
            encoding: "utf-8".to_string(),
            has_prev: total_size > 0,
            has_next: false,
        });
    }

    let reader = backend
        .open_read_range(&vfs_path, offset, Some(window + 1))
        .await
        .map_err(|e| e.to_string())?;
    let mut raw = Vec::new();
    reader
        .take(window + 1)
        .read_to_end(&mut raw)
        .await
        .map_err(|e| e.to_string())?;

    let truncated = (raw.len() as u64) > window;
    let slice = if truncated {
        &raw[..window as usize]
    } else {
        &raw[..]
    };
    let has_more_after_slice =
        truncated || (total_size > 0 && offset + (slice.len() as u64) < total_size);
    let (text, trimmed_lead, consumed, encoding) =
        decode_text_chunk_bytes(slice, offset, has_more_after_slice)?;

    let start_offset = offset + (trimmed_lead as u64);
    let end_offset = offset + (consumed as u64);
    let effective_total = if total_size > 0 { total_size } else { end_offset };
    let has_prev = start_offset > 0;
    let has_next = truncated || (total_size > 0 && end_offset < total_size);

    Ok(TextChunkDto {
        text,
        start_offset,
        end_offset,
        total_size: effective_total,
        encoding,
        has_prev,
        has_next,
    })
}

/// Drop a cached backend so the next access rebuilds it from stored config.
#[flutter_rust_bridge::frb(sync)]
pub fn invalidate_root(root: String) {
    invalidate_dir_cache(&root);
    VfsRegistry::global().invalidate(&root);
}

/// Size in bytes of the downloaded remote-archive cache.
#[flutter_rust_bridge::frb(sync)]
pub fn archive_cache_size() -> u64 {
    VfsRegistry::global().archive_cache_size()
}

/// Deletes all cached remote archives; open archive views are dropped
/// and re-download on next access.
#[flutter_rust_bridge::frb(sync)]
pub fn clear_archive_cache() {
    VfsRegistry::global().clear_archive_cache();
}

pub async fn write_text_file(root: String, path: String, content: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);

    if !backend.prefers_direct_write() && backend.capabilities().rename {
        let name = vfs_path.name().unwrap_or("file");
        let parent = vfs_path.parent().unwrap_or_else(VfsPath::root);
        let tmp_path = parent.join(format!("{name}.{}.fm-part", uuid::Uuid::new_v4().simple()));

        let write_res: Result<(), String> = async {
            let mut writer = backend
                .open_write(&tmp_path, WriteMode::Truncate)
                .await
                .map_err(|e| e.to_string())?;
            writer
                .write_all(content.as_bytes())
                .await
                .map_err(|e| e.to_string())?;
            writer.flush().await.map_err(|e| e.to_string())?;
            writer.shutdown().await.map_err(|e| e.to_string())?;
            Ok(())
        }
        .await;

        if let Err(e) = write_res {
            let _ = backend.remove(&tmp_path).await;
            return Err(e);
        }

        if let Err(rename_err) = backend.rename(&tmp_path, &vfs_path).await {
            if backend.stat(&vfs_path).await.is_ok() {
                let bak_path = parent.join(format!("{name}.{}.fm-old", uuid::Uuid::new_v4().simple()));
                if backend.rename(&vfs_path, &bak_path).await.is_ok() {
                    match backend.rename(&tmp_path, &vfs_path).await {
                        Ok(()) => {
                            let _ = backend.remove(&bak_path).await;
                        }
                        Err(e) => {
                            let _ = backend.rename(&bak_path, &vfs_path).await;
                            let _ = backend.remove(&tmp_path).await;
                            return Err(e.to_string());
                        }
                    }
                } else {
                    let _ = backend.remove(&tmp_path).await;
                    return Err(rename_err.to_string());
                }
            } else {
                let _ = backend.remove(&tmp_path).await;
                return Err(rename_err.to_string());
            }
        }
        invalidate_dir_cache(&root);
        return Ok(());
    }

    let mut writer = backend
        .open_write(&vfs_path, WriteMode::Truncate)
        .await
        .map_err(|e| e.to_string())?;
    writer
        .write_all(content.as_bytes())
        .await
        .map_err(|e| e.to_string())?;
    writer.flush().await.map_err(|e| e.to_string())?;
    // Remote writers commit the object on shutdown; flush alone is not enough.
    writer.shutdown().await.map_err(|e| e.to_string())?;
    invalidate_dir_cache(&root);
    Ok(())
}

/// Copy one VFS entry to a native path the platform can hand to another app.
///
/// `cache_dir` is chosen by the host (an app-private directory); the file keeps
/// its own name so the receiving app sees the right extension. Re-opening the
/// same entry overwrites the cached copy instead of accumulating copies.
pub async fn export_to_native(
    root: String,
    path: String,
    cache_dir: String,
) -> Result<String, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let raw_name = vfs_path.name().unwrap_or("file");
    // The name comes from a remote server's listing; a malicious server can
    // return names containing separators or "..", which would write outside
    // the cache dir through the join below.
    let name: String = raw_name
        .chars()
        .map(|c| if c == '/' || c == '\\' || c == '\0' { '_' } else { c })
        .collect();
    let name = if name == ".." || name == "." || name.is_empty() {
        "file".to_string()
    } else {
        name
    };
    let dir = Path::new(&cache_dir);
    let native = dir.join(name);
    tokio::fs::create_dir_all(dir)
        .await
        .map_err(|e| e.to_string())?;

    let mut reader = backend
        .open_read(&vfs_path)
        .await
        .map_err(|e| e.to_string())?;
    let mut file = tokio::fs::File::create(&native)
        .await
        .map_err(|e| e.to_string())?;
    if let Err(e) = tokio::io::copy(&mut reader, &mut file).await {
        let _ = tokio::fs::remove_file(&native).await;
        return Err(e.to_string());
    }
    if let Err(e) = file.flush().await {
        let _ = tokio::fs::remove_file(&native).await;
        return Err(e.to_string());
    }

    Ok(native.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;

    fn dto(name: &str, is_dir: bool, size: Option<u64>, modified: Option<i64>) -> EntryDto {
        EntryDto {
            name: name.to_string(),
            path: name.to_string(),
            is_dir,
            size,
            modified_millis: modified,
            hidden: false,
            is_symlink: false,
        }
    }

    #[test]
    fn natural_compare_orders_digit_runs_numerically() {
        assert_eq!(natural_compare("file2", "file10"), Ordering::Less);
        assert_eq!(natural_compare("file10", "file2"), Ordering::Greater);
        assert_eq!(natural_compare("File1", "file1"), Ordering::Equal);
        assert_eq!(natural_compare("a", "a1"), Ordering::Less);
        assert_eq!(natural_compare("img_9", "img_10"), Ordering::Less);
        assert_eq!(natural_compare("file1", "file01"), Ordering::Less);
        assert_eq!(natural_compare("file01", "file1"), Ordering::Greater);
    }

    #[test]
    fn sort_keeps_dirs_first_in_both_directions() {
        let mut v = vec![
            dto("b.txt", false, Some(10), None),
            dto("zdir", true, None, None),
            dto("a.txt", false, Some(30), None),
        ];
        sort_dtos(&mut v, "size", false);
        assert_eq!(v[0].name, "zdir");
        assert_eq!(v[1].name, "a.txt");
        assert_eq!(v[2].name, "b.txt");
    }

    #[test]
    fn sort_by_type_then_name() {
        let mut v = vec![
            dto("b.txt", false, None, None),
            dto("x.md", false, None, None),
            dto("Makefile", false, None, None),
            dto(".bashrc", false, None, None),
            dto("a.txt", false, None, None),
        ];
        sort_dtos(&mut v, "type", true);
        let names: Vec<&str> = v.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, vec![".bashrc", "Makefile", "x.md", "a.txt", "b.txt"]);
    }

    #[test]
    fn test_contains_ignore_case() {
        assert!(super::contains_ignore_case("hello_world.txt", "world"));
        assert!(super::contains_ignore_case("PHOTO_2026.JPG", "photo"));
        assert!(super::contains_ignore_case("PHOTO_2026.JPG", "2026"));
        assert!(!super::contains_ignore_case("PHOTO_2026.JPG", "png"));
        assert!(super::contains_ignore_case("中文测试.txt", "中文"));
        assert!(!super::contains_ignore_case("中文测试.txt", "英文"));
    }

    #[test]
    fn decode_text_chunk_bytes_aligns_multibyte_utf8_boundaries() {
        let s = "你好世界测试";
        let bytes = s.as_bytes();
        // Split cleanly at byte 4 (inside 2nd 3-byte char '好') at offset 0 -> emits only '你' (0..3).
        let (t1, lead1, consumed1, enc1) = decode_text_chunk_bytes(&bytes[..4], 0, true).unwrap();
        assert_eq!(t1, "你");
        assert_eq!(lead1, 0);
        assert_eq!(consumed1, 3);
        assert_eq!(enc1, "utf-8");

        // Jump directly to raw byte offset 4 (mid-char continuation bytes of '好') -> skips 2 bytes to '世'.
        let (t2, lead2, consumed2, enc2) = decode_text_chunk_bytes(&bytes[4..], 4, false).unwrap();
        assert_eq!(t2, "世界测试");
        assert_eq!(lead2, 2);
        assert_eq!(consumed2, bytes.len() - 4);
        assert_eq!(enc2, "utf-8");
    }
}
