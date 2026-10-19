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

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_database(db_path: String) {
    VfsRegistry::global().set_database_path(db_path);
}

pub async fn get_capabilities(root: String) -> CapabilitiesDto {
    match VfsRegistry::global().get_or_create(&root) {
        Ok(vfs) => vfs.capabilities().into(),
        Err(_) => Capabilities::READ_ONLY.into(),
    }
}

pub async fn list_dir(root: String, path: String) -> Result<Vec<EntryDto>, String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend
        .list(&vfs_path)
        .await
        .map(|entries| entries.into_iter().map(EntryDto::from).collect())
        .map_err(|error| error.to_string())
}

pub async fn stat_entry(root: String, path: String) -> Result<EntryDto, String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend
        .stat(&vfs_path)
        .await
        .map(EntryDto::from)
        .map_err(|error| error.to_string())
}

pub async fn create_dir(root: String, path: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend.mkdir(&vfs_path).await.map_err(|e| e.to_string())
}

pub async fn remove_entry(root: String, path: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let vfs_path = VfsPath::from_slash_path(&path);
    backend.remove(&vfs_path).await.map_err(|e| e.to_string())
}

pub async fn rename_entry(root: String, from: String, to: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let from_path = VfsPath::from_slash_path(&from);
    let to_path = VfsPath::from_slash_path(&to);
    backend
        .rename(&from_path, &to_path)
        .await
        .map_err(|e| e.to_string())
}

pub async fn read_text_file(root: String, path: String) -> Result<String, String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
    let vfs_path = VfsPath::from_slash_path(&path);
    let mut reader = backend.open_read(&vfs_path).await.map_err(|e| e.to_string())?;
    let mut buffer = String::new();
    reader
        .read_to_string(&mut buffer)
        .await
        .map_err(|e| e.to_string())?;
    Ok(buffer)
}

pub async fn write_text_file(root: String, path: String, content: String) -> Result<(), String> {
    let backend = VfsRegistry::global().get_or_create(&root)?;
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
    let backend = VfsRegistry::global().get_or_create(&root)?;
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
