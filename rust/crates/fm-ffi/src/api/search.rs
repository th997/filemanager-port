//! Advanced multi-dimensional search, category filtering, and full-text Grep search.

use std::collections::VecDeque;

use crate::api::file_manager::EntryDto;
use crate::registry::VfsRegistry;
use fm_core::{EntryKind, VfsPath};
use regex::RegexBuilder;
use tokio::io::AsyncReadExt;

/// A single content match produced by [`grep_text_files`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GrepMatchDto {
    pub path: String,
    pub name: String,
    pub line_number: u32,
    pub line_text: String,
    pub match_start: u32,
    pub match_end: u32,
}

/// Multi-dimensional search options for [`search_entries_advanced`].
#[derive(Debug, Clone)]
pub struct AdvancedSearchQueryDto {
    pub query: String,
    /// Optional category: `"all"`, `"image"`, `"video"`, `"audio"`, `"document"`, `"archive"`, `"apk"`, `"code"`, `"folder"`.
    pub category: String,
    pub min_size: Option<u64>,
    pub max_size: Option<u64>,
    pub modified_after_millis: Option<i64>,
    pub modified_before_millis: Option<i64>,
    /// Match mode: `"contains"`, `"wildcard"`, or `"regex"`.
    pub match_mode: String,
    pub case_sensitive: bool,
    pub include_hidden: bool,
    pub max_results: u32,
}

pub(crate) fn file_category_of(name: &str, is_dir: bool) -> &'static str {
    if is_dir {
        return "folder";
    }
    let ext = match name.rfind('.') {
        Some(idx) if idx + 1 < name.len() => name[idx + 1..].to_ascii_lowercase(),
        _ => return "other",
    };
    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "svg" | "heic" | "heif" | "ico"
        | "tiff" | "tif" | "avif" | "raw" | "dng" => "image",
        "mp4" | "mkv" | "mov" | "avi" | "webm" | "flv" | "wmv" | "m4v" | "ts" | "mts"
        | "m2ts" | "3gp" | "mpeg" | "mpg" | "rmvb" | "ogv" => "video",
        "mp3" | "wav" | "flac" | "aac" | "m4a" | "ogg" | "opus" | "wma" | "aiff" | "alac" => {
            "audio"
        }
        "pdf" | "doc" | "docx" | "xls" | "xlsx" | "ppt" | "pptx" | "txt" | "md" | "markdown"
        | "rtf" | "csv" | "tsv" | "odt" | "ods" | "odp" | "epub" | "pages" | "numbers"
        | "key" => "document",
        "zip" | "tar" | "gz" | "tgz" | "bz2" | "xz" | "7z" | "rar" | "jar" | "cbz" | "cbr" => {
            "archive"
        }
        "apk" | "apks" | "apkm" | "xapk" | "ipa" | "dmg" | "deb" | "rpm" | "msi" | "exe" => "apk",
        "rs" | "dart" | "py" | "js" | "tsx" | "jsx" | "java" | "kt" | "swift" | "c"
        | "cpp" | "h" | "hpp" | "go" | "rb" | "php" | "sh" | "bash" | "zsh" | "yaml" | "yml"
        | "toml" | "json" | "xml" | "html" | "htm" | "css" | "scss" | "sql" | "ini" | "conf"
        | "log" | "gradle" | "cmake" => "code",
        _ => "other",
    }
}

fn is_searchable_text_file(name: &str) -> bool {
    let ext = match name.rfind('.') {
        Some(idx) if idx + 1 < name.len() => name[idx + 1..].to_ascii_lowercase(),
        _ => {
            let lower = name.to_ascii_lowercase();
            return matches!(
                lower.as_str(),
                "makefile" | "dockerfile" | "readme" | "license" | "changelog" | ".gitignore"
                    | ".env"
            );
        }
    };
    matches!(
        ext.as_str(),
        "txt" | "md" | "markdown" | "json" | "yaml" | "yml" | "toml" | "xml" | "html" | "htm"
            | "css" | "scss" | "less" | "js" | "mjs" | "cjs" | "ts" | "tsx" | "jsx" | "dart"
            | "rs" | "py" | "java" | "kt" | "kts" | "swift" | "c" | "cc" | "cpp" | "h" | "hpp"
            | "go" | "rb" | "php" | "sh" | "bash" | "zsh" | "ps1" | "bat" | "cmd" | "sql"
            | "csv" | "tsv" | "ini" | "cfg" | "conf" | "env" | "log" | "properties" | "gradle"
            | "srt" | "vtt" | "ass" | "sub" | "svg" | "tex" | "rst" | "arb"
            | "cmake" | "plist" | "vue" | "svelte"
    )
}

fn is_noisy_dir(name: &str) -> bool {
    matches!(
        name,
        "node_modules"
            | "target"
            | "__pycache__"
            | "venv"
            | ".venv"
            | "Pods"
            | "DerivedData"
            | ".git"
            | ".cache"
            | ".cargo"
            | ".rustup"
            | ".npm"
            | ".pnpm-store"
            | ".yarn"
            | ".gradle"
            | ".dart_tool"
    )
}

fn wildcard_to_regex(pattern: &str) -> String {
    let mut out = String::from("^");
    for ch in pattern.chars() {
        match ch {
            '*' => out.push_str(".*"),
            '?' => out.push('.'),
            other => out.push_str(&regex::escape(&other.to_string())),
        }
    }
    out.push('$');
    out
}

pub(crate) fn contains_ignore_case(haystack: &str, needle_lower: &str) -> bool {
    if needle_lower.is_ascii() {
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

pub(crate) async fn search_entries_impl(
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
    const MAX_DIRS: usize = 8000;
    const MAX_DEPTH: usize = 32;
    let match_path_fragment = needle.contains('/');

    let mut results: Vec<EntryDto> = Vec::new();
    let mut visited = 0usize;
    let mut first = true;
    let mut primary_queue: VecDeque<(VfsPath, usize)> =
        VecDeque::from([(VfsPath::from_slash_path(&path), 0)]);
    let mut deferred_queue: VecDeque<(VfsPath, usize)> = VecDeque::new();
    while let Some((dir, depth)) = primary_queue
        .pop_front()
        .or_else(|| deferred_queue.pop_front())
    {
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
            let defer = child.hidden || is_noisy_dir(&child.name);
            let name_hit = contains_ignore_case(&child.name, &needle);
            let path_hit = !name_hit
                && match_path_fragment
                && contains_ignore_case(&child_path.to_slash_string(), &needle);
            if name_hit || path_hit {
                results.push(EntryDto::from(child));
                if results.len() >= max_results {
                    break;
                }
            }
            if descend {
                if defer {
                    deferred_queue.push_back((child_path, depth + 1));
                } else {
                    primary_queue.push_back((child_path, depth + 1));
                }
            }
        }
    }
    Ok(results)
}

/// Multi-dimensional recursive search supporting category, size range, modified
/// time range, regex, and wildcard matching.
pub async fn search_entries_advanced(
    root: String,
    path: String,
    options: AdvancedSearchQueryDto,
) -> Result<Vec<EntryDto>, String> {
    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let query = options.query.trim().to_string();
    let category = options.category.trim().to_ascii_lowercase();
    let match_mode = options.match_mode.trim().to_ascii_lowercase();

    let compiled_regex = if !query.is_empty() && (match_mode == "regex" || match_mode == "wildcard") {
        let pat = if match_mode == "wildcard" {
            wildcard_to_regex(&query)
        } else {
            query.clone()
        };
        let re = RegexBuilder::new(&pat)
            .case_insensitive(!options.case_sensitive)
            .build()
            .map_err(|e| format!("invalid pattern: {e}"))?;
        Some(re)
    } else {
        None
    };
    let needle_lower = query.to_lowercase();
    let match_path_fragment = compiled_regex.is_none() && query.contains('/');

    let max_results = options.max_results.clamp(1, 2000) as usize;
    const MAX_DIRS: usize = 12_000;
    const MAX_DEPTH: usize = 32;

    let mut results: Vec<EntryDto> = Vec::new();
    let mut visited = 0usize;
    let mut first = true;
    let mut primary_queue: VecDeque<(VfsPath, usize)> =
        VecDeque::from([(VfsPath::from_slash_path(&path), 0)]);
    let mut deferred_queue: VecDeque<(VfsPath, usize)> = VecDeque::new();

    while let Some((dir, depth)) = primary_queue
        .pop_front()
        .or_else(|| deferred_queue.pop_front())
    {
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
            if !options.include_hidden && child.hidden {
                continue;
            }
            let is_dir = child.kind == EntryKind::Dir;
            let descend = is_dir && !child.is_symlink && depth < MAX_DEPTH;
            let child_path = child.path.clone();
            let defer = is_noisy_dir(&child.name);

            let mut matched = true;

            if !query.is_empty() {
                matched = if let Some(ref re) = compiled_regex {
                    re.is_match(&child.name)
                } else if options.case_sensitive {
                    child.name.contains(&query)
                        || (match_path_fragment && child_path.to_slash_string().contains(&query))
                } else {
                    contains_ignore_case(&child.name, &needle_lower)
                        || (match_path_fragment
                            && contains_ignore_case(&child_path.to_slash_string(), &needle_lower))
                };
            }

            if matched && !category.is_empty() && category != "all" {
                let entry_cat = file_category_of(&child.name, is_dir);
                matched = entry_cat == category;
            }

            if matched && (options.min_size.is_some() || options.max_size.is_some()) {
                if is_dir {
                    matched = false;
                } else {
                    let sz = child.size.unwrap_or(0);
                    if let Some(min) = options.min_size {
                        if sz < min {
                            matched = false;
                        }
                    }
                    if let Some(max) = options.max_size {
                        if sz > max {
                            matched = false;
                        }
                    }
                }
            }

            if matched
                && (options.modified_after_millis.is_some()
                    || options.modified_before_millis.is_some())
            {
                let mtime = child
                    .modified
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64);
                match mtime {
                    None => matched = false,
                    Some(ms) => {
                        if let Some(after) = options.modified_after_millis {
                            if ms < after {
                                matched = false;
                            }
                        }
                        if let Some(before) = options.modified_before_millis {
                            if ms > before {
                                matched = false;
                            }
                        }
                    }
                }
            }

            if matched {
                results.push(EntryDto::from(child));
                if results.len() >= max_results {
                    break;
                }
            }

            if descend {
                if defer {
                    deferred_queue.push_back((child_path, depth + 1));
                } else {
                    primary_queue.push_back((child_path, depth + 1));
                }
            }
        }
    }

    Ok(results)
}

/// Full-text content search (Grep mode) across text files under `path`.
pub async fn grep_text_files(
    root: String,
    path: String,
    pattern: String,
    use_regex: bool,
    case_sensitive: bool,
    include_hidden: bool,
    max_matches: u32,
) -> Result<Vec<GrepMatchDto>, String> {
    let pattern = pattern.trim().to_string();
    if pattern.is_empty() {
        return Ok(Vec::new());
    }
    let re_str = if use_regex {
        pattern.clone()
    } else {
        regex::escape(&pattern)
    };
    let re = RegexBuilder::new(&re_str)
        .case_insensitive(!case_sensitive)
        .build()
        .map_err(|e| format!("invalid search pattern: {e}"))?;

    let backend = VfsRegistry::global().get_or_create(&root).await?;
    let max_matches = max_matches.clamp(1, 1000) as usize;
    const MAX_FILES_SCANNED: usize = 3000;
    const MAX_DIRS: usize = 6000;
    const MAX_FILE_BYTES: u64 = 4 * 1024 * 1024;
    const MAX_DEPTH: usize = 24;

    let mut matches: Vec<GrepMatchDto> = Vec::new();
    let mut visited_dirs = 0usize;
    let mut scanned_files = 0usize;
    let mut first = true;
    let mut primary_queue: VecDeque<(VfsPath, usize)> =
        VecDeque::from([(VfsPath::from_slash_path(&path), 0)]);
    let mut deferred_queue: VecDeque<(VfsPath, usize)> = VecDeque::new();

    while let Some((dir, depth)) = primary_queue
        .pop_front()
        .or_else(|| deferred_queue.pop_front())
    {
        if matches.len() >= max_matches
            || visited_dirs >= MAX_DIRS
            || scanned_files >= MAX_FILES_SCANNED
        {
            break;
        }
        visited_dirs += 1;
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
            if !include_hidden && child.hidden {
                continue;
            }
            if child.kind == EntryKind::Dir {
                if !child.is_symlink && depth < MAX_DEPTH {
                    if is_noisy_dir(&child.name) {
                        deferred_queue.push_back((child.path.clone(), depth + 1));
                    } else {
                        primary_queue.push_back((child.path.clone(), depth + 1));
                    }
                }
                continue;
            }
            if child.kind != EntryKind::File || child.is_symlink {
                continue;
            }
            if child.size.unwrap_or(0) > MAX_FILE_BYTES || !is_searchable_text_file(&child.name) {
                continue;
            }
            if scanned_files >= MAX_FILES_SCANNED || matches.len() >= max_matches {
                break;
            }
            scanned_files += 1;

            let reader = match backend.open_read(&child.path).await {
                Ok(r) => r,
                Err(_) => continue,
            };
            let mut raw = Vec::new();
            if reader.take(MAX_FILE_BYTES).read_to_end(&mut raw).await.is_err() {
                continue;
            }
            // Skip binary files containing NUL bytes in prefix.
            if raw.iter().take(4096).any(|&b| b == 0) {
                continue;
            }
            let text = match std::str::from_utf8(&raw) {
                Ok(s) => std::borrow::Cow::Borrowed(s),
                Err(_) => {
                    let (decoded, _, _) = encoding_rs::GB18030.decode(&raw);
                    decoded
                }
            };

            let slash_path = child.path.to_slash_string();
            for (idx, line) in text.lines().enumerate() {
                if let Some(m) = re.find(line) {
                    let trimmed = if line.len() > 240 {
                        let mut end = 240;
                        while !line.is_char_boundary(end) && end > 0 {
                            end -= 1;
                        }
                        format!("{}…", &line[..end])
                    } else {
                        line.to_string()
                    };
                    matches.push(GrepMatchDto {
                        path: slash_path.clone(),
                        name: child.name.clone(),
                        line_number: (idx + 1) as u32,
                        line_text: trimmed,
                        match_start: m.start() as u32,
                        match_end: m.end() as u32,
                    });
                    if matches.len() >= max_matches {
                        break;
                    }
                }
            }
        }
    }

    Ok(matches)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn advanced_search_filters_by_category_size_and_wildcard() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("report_2026.pdf"), vec![b'a'; 500]).unwrap();
        std::fs::write(dir.path().join("photo_01.jpg"), vec![b'b'; 2000]).unwrap();
        std::fs::write(dir.path().join("tiny.txt"), b"hi").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let docs = search_entries_advanced(
            root.clone(),
            "".into(),
            AdvancedSearchQueryDto {
                query: "report_*".into(),
                category: "document".into(),
                min_size: Some(100),
                max_size: Some(1000),
                modified_after_millis: None,
                modified_before_millis: None,
                match_mode: "wildcard".into(),
                case_sensitive: false,
                include_hidden: false,
                max_results: 50,
            },
        )
        .await
        .unwrap();
        assert_eq!(docs.len(), 1);
        assert_eq!(docs[0].name, "report_2026.pdf");
    }

    #[tokio::test]
    async fn grep_finds_line_numbers_in_text_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(
            dir.path().join("notes.md"),
            "first line\nhello Rust VFS world\nthird line\n",
        )
        .unwrap();
        std::fs::write(dir.path().join("bin.dat"), b"\x00\x01Rust VFS").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let hits = grep_text_files(
            root,
            "".into(),
            "rust vfs".into(),
            false,
            false,
            false,
            50,
        )
        .await
        .unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "notes.md");
        assert_eq!(hits[0].line_number, 2);
    }

    #[tokio::test]
    async fn advanced_search_bfs_finds_shallow_folders_and_path_fragments() {
        let dir = tempfile::tempdir().unwrap();
        let noisy = dir.path().join("node_modules");
        for i in 0..10 {
            let deep = noisy.join(format!("pkg_{i}/nested/deep"));
            std::fs::create_dir_all(&deep).unwrap();
            std::fs::write(deep.join("DesignFolder_dep.txt"), b"x").unwrap();
        }
        let target = dir.path().join("MyProjects/DesignFolder");
        std::fs::create_dir_all(&target).unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let all_hits = search_entries_advanced(
            root.clone(),
            "".into(),
            AdvancedSearchQueryDto {
                query: "designfolder".into(),
                category: "all".into(),
                min_size: None,
                max_size: None,
                modified_after_millis: None,
                modified_before_millis: None,
                match_mode: "contains".into(),
                case_sensitive: false,
                include_hidden: false,
                max_results: 1,
            },
        )
        .await
        .unwrap();
        assert_eq!(all_hits.len(), 1);
        assert_eq!(all_hits[0].name, "DesignFolder");
        assert!(all_hits[0].is_dir);

        let folder_hits = search_entries_advanced(
            root.clone(),
            "".into(),
            AdvancedSearchQueryDto {
                query: "design".into(),
                category: "folder".into(),
                min_size: None,
                max_size: None,
                modified_after_millis: None,
                modified_before_millis: None,
                match_mode: "contains".into(),
                case_sensitive: false,
                include_hidden: false,
                max_results: 10,
            },
        )
        .await
        .unwrap();
        assert_eq!(folder_hits.len(), 1);
        assert_eq!(folder_hits[0].name, "DesignFolder");

        let path_hits = search_entries_advanced(
            root,
            "".into(),
            AdvancedSearchQueryDto {
                query: "myprojects/design".into(),
                category: "folder".into(),
                min_size: None,
                max_size: None,
                modified_after_millis: None,
                modified_before_millis: None,
                match_mode: "contains".into(),
                case_sensitive: false,
                include_hidden: false,
                max_results: 10,
            },
        )
        .await
        .unwrap();
        assert_eq!(path_hits.len(), 1);
        assert_eq!(path_hits[0].path, "/MyProjects/DesignFolder");
    }

    #[tokio::test]
    async fn search_entries_impl_bfs_deprioritizes_noisy_dirs() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("node_modules/pkg")).unwrap();
        std::fs::write(dir.path().join("node_modules/pkg/target_hit.txt"), b"1").unwrap();
        std::fs::create_dir_all(dir.path().join("Docs/TargetFolder")).unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let hits = search_entries_impl(root, "".into(), "target".into(), 1)
            .await
            .unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "TargetFolder");
        assert!(hits[0].is_dir);
    }

    #[tokio::test]
    async fn grep_bfs_finds_shallow_text_files_before_noisy_dirs() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir.path().join("node_modules/pkg")).unwrap();
        std::fs::write(dir.path().join("node_modules/pkg/a.txt"), "magic_needle").unwrap();
        std::fs::create_dir_all(dir.path().join("notes")).unwrap();
        std::fs::write(dir.path().join("notes/todo.md"), "magic_needle").unwrap();
        let root = dir.path().to_string_lossy().to_string();

        let hits = grep_text_files(
            root,
            "".into(),
            "magic_needle".into(),
            false,
            false,
            false,
            1,
        )
        .await
        .unwrap();
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].name, "todo.md");
    }
}
