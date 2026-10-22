use crate::registry::VfsRegistry;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use std::path::Path;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

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
/// numerically — a direct port of the `_naturalCompare` the Dart side used
/// to apply to whichever page happened to be loaded.
fn natural_compare(a: &str, b: &str) -> std::cmp::Ordering {
    fn runs(s: &str) -> Vec<String> {
        let mut out = Vec::new();
        let mut cur = String::new();
        let mut cur_digit: Option<bool> = None;
        for ch in s.to_lowercase().chars() {
            let d = ch.is_ascii_digit();
            match cur_digit {
                Some(cd) if cd == d => cur.push(ch),
                _ => {
                    if !cur.is_empty() {
                        out.push(std::mem::take(&mut cur));
                    }
                    cur.push(ch);
                    cur_digit = Some(d);
                }
            }
        }
        if !cur.is_empty() {
            out.push(cur);
        }
        out
    }
    let ra = runs(a);
    let rb = runs(b);
    for (pa, pb) in ra.iter().zip(rb.iter()) {
        let num = |p: &String| -> Option<u128> {
            if p.chars().all(|c| c.is_ascii_digit()) {
                p.parse().ok()
            } else {
                None
            }
        };
        let cmp = match (num(pa), num(pb)) {
            (Some(x), Some(y)) => x.cmp(&y),
            _ => pa.cmp(pb),
        };
        if cmp != std::cmp::Ordering::Equal {
            return cmp;
        }
    }
    ra.len().cmp(&rb.len())
}

fn extension_of(e: &EntryDto) -> String {
    if e.is_dir {
        return String::new();
    }
    e.name
        .rsplit('.')
        .next()
        .unwrap_or(&e.name)
        .to_lowercase()
}

/// Sort a full folder listing the way the UI promises: directories first
/// (in both directions), then the requested key. This used to happen in
/// Dart over only the pages fetched so far, so "sort by size" in a large
/// folder actually sorted just the first hundred entries.
fn sort_dtos(entries: &mut [EntryDto], sort_by: &str, ascending: bool) {
    entries.sort_by(|a, b| {
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
            "type" => extension_of(a)
                .cmp(&extension_of(b))
                .then_with(|| natural_compare(&a.name, &b.name)),
            _ => natural_compare(&a.name, &b.name),
        };
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
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    // Sorting must see the whole folder: the VFS paged helper materialises
    // the full list anyway, so sort first, then slice out the page.
    let all = backend
        .list(&vfs_path)
        .await
        .map_err(|error| error.to_string())?;
    let mut dtos: Vec<EntryDto> = all.into_iter().map(EntryDto::from).collect();
    sort_dtos(&mut dtos, &sort_by, sort_ascending);

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
            if child.name.to_lowercase().contains(&needle) {
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
    backend.mkdir(&vfs_path).await.map_err(|e| e.to_string())
}

pub async fn remove_entry(root: String, path: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend.remove(&vfs_path).await.map_err(|e| e.to_string())
}

pub async fn rename_entry(root: String, from: String, to: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let from_path = VfsPath::from_slash_path(&from);
    let to_path = VfsPath::from_slash_path(&to);
    backend
        .rename(&from_path, &to_path)
        .await
        .map_err(|e| e.to_string())
}

/// Upper bound for opening a file in the text editor. The old code read
/// unboundedly into memory twice over (Rust buffer + Dart string), so a
/// stray tap on a several-hundred-MB log could OOM the whole app.
const MAX_TEXT_EDIT_BYTES: u64 = 50 * 1024 * 1024;

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
            let (text, _, _) = encoding_rs::GB18030.decode(&bytes);
            Ok(text.into_owned())
        }
    }
}

/// Drop a cached backend so the next access rebuilds it from stored config.
#[flutter_rust_bridge::frb(sync)]
pub fn invalidate_root(root: String) {
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
    let name = vfs_path.name().unwrap_or("file").to_string();
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
    tokio::io::copy(&mut reader, &mut file)
        .await
        .map_err(|e| e.to_string())?;
    file.flush().await.map_err(|e| e.to_string())?;

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
            dto("a.txt", false, None, None),
        ];
        sort_dtos(&mut v, "type", true);
        let names: Vec<&str> = v.iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, vec!["x.md", "a.txt", "b.txt"]);
    }
}
