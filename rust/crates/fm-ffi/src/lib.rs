//! The single FFI boundary between Rust and Flutter.
//!
//! Everything exported here is intentionally small and typed: the UI never
//! sees backend internals, and the bridge file is generated from this crate
//! alone.

use fm_core::{Capabilities, Entry, EntryKind, VfsPath};
use fm_local::LocalFs;
use fm_vfs::Vfs;
use std::sync::OnceLock;

/// Plain transfer types: `SystemTime` and trait objects do not cross the
/// bridge, so entries are flattened here.
#[derive(Debug, Clone)]
pub struct EntryDto {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size: Option<u64>,
    pub modified_millis: Option<i64>,
    pub hidden: bool,
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
        }
    }
}

fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("tokio runtime")
    })
}

fn backend(root: String) -> LocalFs {
    LocalFs::new(root)
}

/// What the given root supports. The UI uses this to hide unavailable actions.
pub fn capabilities(root: String) -> Capabilities {
    backend(root).capabilities()
}

/// List a directory. `root` is a native path; `path` is a `/`-separated path
/// relative to that root.
pub fn list_dir(root: String, path: String) -> Result<Vec<EntryDto>, String> {
    let backend = backend(root);
    let path = VfsPath::from_slash_path(&path);
    runtime()
        .block_on(backend.list(&path))
        .map(|entries| entries.into_iter().map(EntryDto::from).collect())
        .map_err(|error| error.to_string())
}

/// Stat one entry relative to `root`.
pub fn stat(root: String, path: String) -> Result<EntryDto, String> {
    let backend = backend(root);
    let path = VfsPath::from_slash_path(&path);
    runtime()
        .block_on(backend.stat(&path))
        .map(EntryDto::from)
        .map_err(|error| error.to_string())
}
