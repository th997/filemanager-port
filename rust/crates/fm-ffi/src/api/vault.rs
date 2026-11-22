use crate::api::file_manager::invalidate_dir_cache_for_vault;
use crate::api::servers::stop_media_streams_for_vault;
use crate::registry::VfsRegistry;
use fm_vault::{
    desktop_keystore_delete, desktop_keystore_read, desktop_keystore_save, UnlockedVaultInfo,
    VaultAuthMode, VaultBackupInfo, VaultCipher, VaultGcResult, VaultManager, VaultStats,
};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct UnlockedVaultDto {
    pub id: String,
    pub name: String,
    pub dir_path: String,
    pub cipher: String,
    pub auth_mode: String,
    pub created_at_ms: i64,
}

impl From<UnlockedVaultInfo> for UnlockedVaultDto {
    fn from(v: UnlockedVaultInfo) -> Self {
        Self {
            id: v.id,
            name: v.name,
            dir_path: v.dir_path,
            cipher: v.cipher.as_str().to_string(),
            auth_mode: v.auth_mode.as_str().to_string(),
            created_at_ms: v.created_at_ms,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VaultLookupDto {
    pub exists: bool,
    pub id: Option<String>,
    pub auth_mode: Option<String>,
    pub cipher: Option<String>,
    pub unlocked: bool,
    pub cooldown_secs: u64,
}

#[derive(Debug, Clone)]
pub struct VaultCreateResultDto {
    pub vault: UnlockedVaultDto,
    pub system_dek_b64: Option<String>,
}

#[derive(Debug, Clone)]
pub struct VaultBackupInfoDto {
    pub cipher: String,
    pub original_auth_mode: String,
    pub requires_password: bool,
    pub object_count: u32,
    pub original_name: Option<String>,
}

impl From<VaultBackupInfo> for VaultBackupInfoDto {
    fn from(b: VaultBackupInfo) -> Self {
        Self {
            cipher: b.cipher.as_str().to_string(),
            original_auth_mode: b.original_auth_mode.as_str().to_string(),
            requires_password: b.requires_password,
            object_count: b.object_count,
            original_name: b.original_name,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VaultImportResultDto {
    pub vault: UnlockedVaultDto,
    pub system_dek_b64: Option<String>,
}

#[derive(Debug, Clone)]
pub struct VaultBackupTaskProgressDto {
    pub task_id: String,
    pub state: String,
    pub done_bytes: u64,
    pub total_bytes: u64,
    pub fraction: Option<f32>,
    pub error: Option<String>,
    pub imported: Option<VaultImportResultDto>,
}

#[derive(Debug, Clone)]
pub struct VaultStatsDto {
    pub file_count: u64,
    pub dir_count: u64,
    pub total_plain_bytes: u64,
    pub disk_bytes: u64,
    pub orphan_count: u64,
    pub orphan_bytes: u64,
}

impl From<VaultStats> for VaultStatsDto {
    fn from(s: VaultStats) -> Self {
        Self {
            file_count: s.file_count,
            dir_count: s.dir_count,
            total_plain_bytes: s.total_plain_bytes,
            disk_bytes: s.disk_bytes,
            orphan_count: s.orphan_count,
            orphan_bytes: s.orphan_bytes,
        }
    }
}

#[derive(Debug, Clone)]
pub struct VaultGcResultDto {
    pub removed_files: u64,
    pub freed_bytes: u64,
}

impl From<VaultGcResult> for VaultGcResultDto {
    fn from(r: VaultGcResult) -> Self {
        Self {
            removed_files: r.removed_files,
            freed_bytes: r.freed_bytes,
        }
    }
}

struct BackupTaskEntry {
    state: Mutex<VaultBackupTaskProgressDto>,
    cancel: AtomicBool,
    finished_at: Mutex<Option<Instant>>,
}

static BACKUP_TASKS: OnceLock<Mutex<HashMap<String, Arc<BackupTaskEntry>>>> = OnceLock::new();

fn backup_tasks() -> &'static Mutex<HashMap<String, Arc<BackupTaskEntry>>> {
    BACKUP_TASKS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn register_backup_task() -> (String, Arc<BackupTaskEntry>) {
    let task_id = uuid::Uuid::new_v4().simple().to_string();
    let entry = Arc::new(BackupTaskEntry {
        state: Mutex::new(VaultBackupTaskProgressDto {
            task_id: task_id.clone(),
            state: "running".to_string(),
            done_bytes: 0,
            total_bytes: 0,
            fraction: None,
            error: None,
            imported: None,
        }),
        cancel: AtomicBool::new(false),
        finished_at: Mutex::new(None),
    });
    let mut map = backup_tasks().lock();
    let cutoff = Duration::from_secs(600);
    map.retain(|_, v| {
        v.finished_at
            .lock()
            .map(|t| t.elapsed() < cutoff)
            .unwrap_or(true)
    });
    map.insert(task_id.clone(), Arc::clone(&entry));
    (task_id, entry)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_init_store(app_data_dir: String) {
    VaultManager::global().init_store(app_data_dir);
    VfsRegistry::global().clear_all_vault_archive_caches();
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_list_unlocked() -> Vec<UnlockedVaultDto> {
    VaultManager::global()
        .list_unlocked()
        .into_iter()
        .map(UnlockedVaultDto::from)
        .collect()
}

pub async fn vault_lookup(name: String) -> Result<VaultLookupDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .lookup_by_name(&name)
            .map(|r| VaultLookupDto {
                exists: r.exists,
                id: r.id,
                auth_mode: r.auth_mode.map(|a| a.as_str().to_string()),
                cipher: r.cipher.map(|c| c.as_str().to_string()),
                unlocked: r.unlocked,
                cooldown_secs: r.cooldown_secs,
            })
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_create(
    name: String,
    storage_root: String,
    cipher: String,
    auth_mode: String,
    password: Option<String>,
) -> Result<VaultCreateResultDto, String> {
    tokio::task::spawn_blocking(move || {
        let c = VaultCipher::from_str(&cipher).map_err(|e| e.to_string())?;
        let a = VaultAuthMode::from_str(&auth_mode).map_err(|e| e.to_string())?;
        let out = VaultManager::global()
            .create_vault(
                &name,
                &PathBuf::from(storage_root),
                c,
                a,
                password.as_deref(),
            )
            .map_err(|e| e.to_string())?;
        Ok(VaultCreateResultDto {
            vault: UnlockedVaultDto::from(out.info),
            system_dek_b64: out.system_dek_b64,
        })
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_unlock_with_password(
    name: String,
    password: String,
) -> Result<UnlockedVaultDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .unlock_with_password(&name, &password)
            .map(UnlockedVaultDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_unlock_with_system_key(
    name: String,
    system_dek_b64: Option<String>,
) -> Result<UnlockedVaultDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .unlock_with_system_key(&name, system_dek_b64.as_deref())
            .map(UnlockedVaultDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

fn cleanup_vault_runtime(vault_id: &str) {
    stop_media_streams_for_vault(vault_id);
    invalidate_dir_cache_for_vault(vault_id);
    VfsRegistry::global().invalidate_vault(vault_id);
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_lock(vault_id: String) -> bool {
    let was_unlocked = VaultManager::global().lock(&vault_id);
    cleanup_vault_runtime(&vault_id);
    was_unlocked
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_lock_all() -> Vec<String> {
    let ids = VaultManager::global().lock_all();
    for id in &ids {
        cleanup_vault_runtime(id);
    }
    ids
}

pub async fn vault_read_thumbnail(vault_id: String, rel_path: String) -> Result<Option<Vec<u8>>, String> {
    VaultManager::global()
        .read_thumbnail(&vault_id, &rel_path)
        .await
        .map_err(|e| e.to_string())
}

pub async fn vault_save_thumbnail(
    vault_id: String,
    rel_path: String,
    bytes: Vec<u8>,
) -> Result<(), String> {
    VaultManager::global()
        .save_thumbnail(&vault_id, &rel_path, bytes)
        .await
        .map_err(|e| e.to_string())
}

pub async fn vault_export_backup(
    vault_id: String,
    backup_password: Option<String>,
    dest_archive_path: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .export_backup(
                &vault_id,
                backup_password.as_deref(),
                &PathBuf::from(dest_archive_path),
            )
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_inspect_backup(archive_path: String) -> Result<VaultBackupInfoDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .inspect_backup(&PathBuf::from(archive_path))
            .map(VaultBackupInfoDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_import_backup(
    archive_path: String,
    vault_name: Option<String>,
    target_storage_root: String,
    backup_password: Option<String>,
    target_auth_mode: String,
    new_local_password: Option<String>,
) -> Result<VaultImportResultDto, String> {
    tokio::task::spawn_blocking(move || {
        let auth = VaultAuthMode::from_str(&target_auth_mode).map_err(|e| e.to_string())?;
        let imported = VaultManager::global()
            .import_backup(
                &PathBuf::from(archive_path),
                vault_name.as_deref(),
                &PathBuf::from(target_storage_root),
                backup_password.as_deref(),
                auth,
                new_local_password.as_deref(),
            )
            .map_err(|e| e.to_string())?;
        let unlocked = VaultManager::global()
            .list_unlocked()
            .into_iter()
            .find(|v| v.id == imported.local_id)
            .ok_or_else(|| "imported vault missing from active map".to_string())?;
        Ok(VaultImportResultDto {
            vault: UnlockedVaultDto::from(unlocked),
            system_dek_b64: imported.system_dek_b64,
        })
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_rename(vault_id: String, new_name: String) -> Result<UnlockedVaultDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .rename_vault(&vault_id, &new_name)
            .map(UnlockedVaultDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_delete(vault_id: String) -> Result<(), String> {
    cleanup_vault_runtime(&vault_id);
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .delete_vault(&vault_id)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_desktop_keystore_save(key: String, value: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || desktop_keystore_save(&key, &value).map_err(|e| e.to_string()))
        .await
        .map_err(|e| e.to_string())?
}

pub async fn vault_desktop_keystore_read(key: String) -> Result<Option<String>, String> {
    tokio::task::spawn_blocking(move || desktop_keystore_read(&key).map_err(|e| e.to_string()))
        .await
        .map_err(|e| e.to_string())?
}

pub async fn vault_desktop_keystore_delete(key: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || desktop_keystore_delete(&key).map_err(|e| e.to_string()))
        .await
        .map_err(|e| e.to_string())?
}

pub async fn vault_stats(vault_id: String) -> Result<VaultStatsDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .vault_stats(&vault_id)
            .map(VaultStatsDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_gc(vault_id: String) -> Result<VaultGcResultDto, String> {
    VaultManager::global()
        .gc_vault(&vault_id)
        .await
        .map(VaultGcResultDto::from)
        .map_err(|e| e.to_string())
}

pub async fn vault_change_password(
    vault_id: String,
    current_password: Option<String>,
    new_password: String,
) -> Result<UnlockedVaultDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .change_password(&vault_id, current_password.as_deref(), &new_password)
            .map(UnlockedVaultDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_prepare_switch_to_system(
    vault_id: String,
    current_password: String,
) -> Result<Option<String>, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .prepare_switch_to_system(&vault_id, &current_password)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_commit_switch_to_system(vault_id: String) -> Result<UnlockedVaultDto, String> {
    tokio::task::spawn_blocking(move || {
        VaultManager::global()
            .commit_switch_to_system(&vault_id)
            .map(UnlockedVaultDto::from)
            .map_err(|e| e.to_string())
    })
    .await
    .map_err(|e| e.to_string())?
}

pub async fn vault_start_export_backup(
    vault_id: String,
    backup_password: Option<String>,
    dest_archive_path: String,
) -> Result<String, String> {
    let (task_id, entry) = register_backup_task();
    let entry_clone = Arc::clone(&entry);
    tokio::task::spawn_blocking(move || {
        let mut on_progress = |done: u64, total: u64| {
            let mut st = entry_clone.state.lock();
            st.done_bytes = done;
            st.total_bytes = total;
            st.fraction = if total > 0 {
                Some((done as f32 / total as f32).clamp(0.0, 1.0))
            } else {
                None
            };
        };
        let res = VaultManager::global().export_backup_with_progress(
            &vault_id,
            backup_password.as_deref(),
            &PathBuf::from(dest_archive_path),
            Some(&entry_clone.cancel),
            Some(&mut on_progress),
        );
        let mut st = entry_clone.state.lock();
        match res {
            Ok(()) => {
                st.state = "completed".to_string();
                st.fraction = Some(1.0);
                if st.total_bytes > 0 {
                    st.done_bytes = st.total_bytes;
                }
            }
            Err(e) => {
                if entry_clone.cancel.load(Ordering::Acquire) {
                    st.state = "cancelled".to_string();
                    st.error = Some("operation cancelled".to_string());
                } else {
                    st.state = "failed".to_string();
                    st.error = Some(e.to_string());
                }
            }
        }
        *entry_clone.finished_at.lock() = Some(Instant::now());
    });
    Ok(task_id)
}

pub async fn vault_start_import_backup(
    archive_path: String,
    vault_name: Option<String>,
    target_storage_root: String,
    backup_password: Option<String>,
    target_auth_mode: String,
    new_local_password: Option<String>,
) -> Result<String, String> {
    let auth = VaultAuthMode::from_str(&target_auth_mode).map_err(|e| e.to_string())?;
    let (task_id, entry) = register_backup_task();
    let entry_clone = Arc::clone(&entry);
    tokio::task::spawn_blocking(move || {
        let mut on_progress = |done: u64, total: u64| {
            let mut st = entry_clone.state.lock();
            st.done_bytes = done;
            st.total_bytes = total;
            st.fraction = if total > 0 {
                Some((done as f32 / total as f32).clamp(0.0, 1.0))
            } else {
                None
            };
        };
        let res = (|| -> Result<VaultImportResultDto, String> {
            let imported = VaultManager::global()
                .import_backup_with_progress(
                    &PathBuf::from(archive_path),
                    vault_name.as_deref(),
                    &PathBuf::from(target_storage_root),
                    backup_password.as_deref(),
                    auth,
                    new_local_password.as_deref(),
                    Some(&entry_clone.cancel),
                    Some(&mut on_progress),
                )
                .map_err(|e| e.to_string())?;
            let unlocked = VaultManager::global()
                .list_unlocked()
                .into_iter()
                .find(|v| v.id == imported.local_id)
                .ok_or_else(|| "imported vault missing from active map".to_string())?;
            Ok(VaultImportResultDto {
                vault: UnlockedVaultDto::from(unlocked),
                system_dek_b64: imported.system_dek_b64,
            })
        })();
        let mut st = entry_clone.state.lock();
        match res {
            Ok(dto) => {
                st.state = "completed".to_string();
                st.fraction = Some(1.0);
                if st.total_bytes > 0 {
                    st.done_bytes = st.total_bytes;
                }
                st.imported = Some(dto);
            }
            Err(e) => {
                if entry_clone.cancel.load(Ordering::Acquire) {
                    st.state = "cancelled".to_string();
                    st.error = Some("operation cancelled".to_string());
                } else {
                    st.state = "failed".to_string();
                    st.error = Some(e);
                }
            }
        }
        *entry_clone.finished_at.lock() = Some(Instant::now());
    });
    Ok(task_id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_backup_task_progress(task_id: String) -> Option<VaultBackupTaskProgressDto> {
    let map = backup_tasks().lock();
    map.get(&task_id).map(|e| e.state.lock().clone())
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_cancel_backup_task(task_id: String) -> bool {
    let map = backup_tasks().lock();
    if let Some(entry) = map.get(&task_id) {
        entry.cancel.store(true, Ordering::Release);
        true
    } else {
        false
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_remove_backup_task(task_id: String) {
    backup_tasks().lock().remove(&task_id);
}
