use crate::backup::{
    export_vault_backup_with_progress, import_vault_backup_with_progress, inspect_vault_backup,
    ImportedVaultResult, VaultBackupInfo,
};
use crate::crypto::{validate_password, VaultAuthMode, VaultCipher};
use crate::error::{VaultError, VaultResult};
use crate::index::{migrate_legacy_index_to_dirs, VaultDirFile, DIRS_DIR};
use crate::meta::VaultMeta;
use crate::registry::{ensure_private_storage_root, make_registry_record, VaultRegistryRecord, VaultStore};
use crate::vfs::{sweep_stale_tmp_files, VaultFs, VaultGcResult, VaultState, VaultStats, OBJECTS_DIR, THUMBS_DIR};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use fm_core::VfsPath;
use fm_vfs::Vfs;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, OnceLock};
use std::time::Duration;
use zeroize::Zeroizing;

#[derive(Debug, Clone)]
pub struct UnlockedVaultInfo {
    pub id: String,
    pub name: String,
    pub dir_path: String,
    pub cipher: VaultCipher,
    pub auth_mode: VaultAuthMode,
    pub created_at_ms: i64,
}

#[derive(Debug, Clone)]
pub struct VaultLookupInfo {
    pub exists: bool,
    pub id: Option<String>,
    pub auth_mode: Option<VaultAuthMode>,
    pub cipher: Option<VaultCipher>,
    pub unlocked: bool,
    pub cooldown_secs: u64,
}

#[derive(Debug, Clone)]
pub struct CreateVaultOutput {
    pub info: UnlockedVaultInfo,
    pub system_dek_b64: Option<String>,
}

struct UnlockedEntry {
    info: UnlockedVaultInfo,
    dek: Zeroizing<[u8; 32]>,
    state: Arc<VaultState>,
}

pub struct VaultManager {
    app_data_dir: RwLock<Option<PathBuf>>,
    unlocked: RwLock<HashMap<String, UnlockedEntry>>,
}

static INSTANCE: OnceLock<VaultManager> = OnceLock::new();

impl Default for VaultManager {
    fn default() -> Self {
        Self::new()
    }
}

impl VaultManager {
    pub fn global() -> &'static Self {
        INSTANCE.get_or_init(Self::new)
    }

    pub fn new() -> Self {
        Self {
            app_data_dir: RwLock::new(None),
            unlocked: RwLock::new(HashMap::new()),
        }
    }

    pub fn init_store(&self, app_data_dir: impl Into<PathBuf>) {
        let dir: PathBuf = app_data_dir.into();
        *self.app_data_dir.write() = Some(dir.clone());
        let _ = VaultStore::new(dir).repair_relocated_paths();
    }

    fn store(&self) -> VaultResult<VaultStore> {
        let dir = self
            .app_data_dir
            .read()
            .clone()
            .ok_or_else(|| VaultError::Unsupported("vault store not initialized".to_string()))?;
        Ok(VaultStore::new(dir))
    }

    pub fn lookup_by_name(&self, name: &str) -> VaultResult<VaultLookupInfo> {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Ok(VaultLookupInfo {
                exists: false,
                id: None,
                auth_mode: None,
                cipher: None,
                unlocked: false,
                cooldown_secs: 0,
            });
        }
        let store = self.store()?;
        let Some(rec) = store.find_by_name(trimmed)? else {
            return Ok(VaultLookupInfo {
                exists: false,
                id: None,
                auth_mode: None,
                cipher: None,
                unlocked: false,
                cooldown_secs: 0,
            });
        };
        let is_unlocked = self.unlocked.read().contains_key(&rec.id);
        let cooldown_secs = rec
            .cooldown_remaining_secs(crate::meta::now_millis())
            .unwrap_or(0);
        Ok(VaultLookupInfo {
            exists: true,
            id: Some(rec.id),
            auth_mode: Some(rec.auth_mode),
            cipher: Some(rec.cipher),
            unlocked: is_unlocked,
            cooldown_secs,
        })
    }

    pub fn create_vault(
        &self,
        name: &str,
        storage_root: &Path,
        cipher: VaultCipher,
        auth_mode: VaultAuthMode,
        password: Option<&str>,
    ) -> VaultResult<CreateVaultOutput> {
        let trimmed = name.trim();
        if trimmed.is_empty()
            || trimmed == "."
            || trimmed == ".."
            || trimmed.contains('/')
            || trimmed.contains('\\')
        {
            return Err(VaultError::InvalidPassword(
                "privacy folder name cannot be empty or contain path separators".to_string(),
            ));
        }

        let store = self.store()?;
        if store.find_by_name(trimmed)?.is_some() {
            return Err(VaultError::AlreadyExists(trimmed.to_string()));
        }

        let vault_id = uuid::Uuid::new_v4().simple().to_string();
        ensure_private_storage_root(storage_root)?;
        let vault_dir = storage_root.join(&vault_id);
        if vault_dir.exists() {
            return Err(VaultError::AlreadyExists(vault_id));
        }

        let init_res: VaultResult<(VaultMeta, Zeroizing<[u8; 32]>, Arc<VaultState>)> = (|| {
            std::fs::create_dir_all(vault_dir.join(OBJECTS_DIR))?;
            std::fs::create_dir_all(vault_dir.join(THUMBS_DIR))?;
            std::fs::create_dir_all(vault_dir.join(DIRS_DIR))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&vault_dir, std::fs::Permissions::from_mode(0o700));
            }
            let (meta, dek) = VaultMeta::new_vault(vault_id.clone(), trimmed, cipher, auth_mode, password)?;
            let root_dir_id = meta
                .root_dir_id
                .clone()
                .ok_or_else(|| VaultError::Crypto("missing root_dir_id".to_string()))?;
            VaultDirFile::default().save(&vault_dir, &vault_id, &root_dir_id, cipher, &dek)?;
            meta.save(&vault_dir)?;
            let state = VaultState::open(
                vault_id.clone(),
                root_dir_id,
                vault_dir.clone(),
                cipher,
                Zeroizing::new(*dek),
            )?;
            Ok((meta, dek, state))
        })();

        let (meta, dek, state) = match init_res {
            Ok(v) => v,
            Err(e) => {
                let _ = std::fs::remove_dir_all(&vault_dir);
                return Err(e);
            }
        };

        let rec = make_registry_record(vault_id.clone(), trimmed, &vault_dir, &meta);
        if let Err(e) = store.add_record(rec) {
            let _ = std::fs::remove_dir_all(&vault_dir);
            return Err(e);
        }

        let info = UnlockedVaultInfo {
            id: vault_id.clone(),
            name: trimmed.to_string(),
            dir_path: vault_dir.to_string_lossy().to_string(),
            cipher,
            auth_mode,
            created_at_ms: meta.created_at_ms,
        };
        let system_dek_b64 = if auth_mode == VaultAuthMode::System && cipher.is_encrypted() {
            Some(STANDARD.encode(&*dek))
        } else {
            None
        };

        self.unlocked.write().insert(
            vault_id,
            UnlockedEntry {
                info: info.clone(),
                dek,
                state,
            },
        );

        Ok(CreateVaultOutput {
            info,
            system_dek_b64,
        })
    }

    pub fn unlock_with_password(&self, name: &str, password: &str) -> VaultResult<UnlockedVaultInfo> {
        let trimmed = name.trim();
        let store = self.store()?;
        let rec = store
            .find_by_name(trimmed)?
            .ok_or_else(|| VaultError::NotFound(trimmed.to_string()))?;

        store.check_cooldown(&rec.id)?;

        let vault_dir = PathBuf::from(&rec.dir_path);
        let meta = VaultMeta::load(&vault_dir)?;
        if !meta.verify_name(trimmed)? {
            return Err(VaultError::NotFound(trimmed.to_string()));
        }

        let dek = match meta.unlock_with_password(password) {
            Ok(d) => d,
            Err(VaultError::WrongCredential) => {
                store.record_auth_failure(&rec.id)?;
                if let Some(updated) = store.find_by_id(&rec.id)? {
                    if let Some(secs) = updated.cooldown_remaining_secs(crate::meta::now_millis()) {
                        return Err(VaultError::CooldownActive(secs));
                    }
                }
                return Err(VaultError::WrongCredential);
            }
            Err(e) => return Err(e),
        };
        store.reset_auth_failures(&rec.id)?;
        self.finish_unlock(rec, trimmed.to_string(), vault_dir, meta, dek)
    }

    pub fn unlock_with_system_key(
        &self,
        name: &str,
        system_dek_b64: Option<&str>,
    ) -> VaultResult<UnlockedVaultInfo> {
        let trimmed = name.trim();
        let store = self.store()?;
        let rec = store
            .find_by_name(trimmed)?
            .ok_or_else(|| VaultError::NotFound(trimmed.to_string()))?;

        let vault_dir = PathBuf::from(&rec.dir_path);
        let meta = VaultMeta::load(&vault_dir)?;
        if !meta.verify_name(trimmed)? {
            return Err(VaultError::NotFound(trimmed.to_string()));
        }

        let dek = if meta.cipher.is_encrypted() {
            let b64 = system_dek_b64.ok_or(VaultError::WrongCredential)?;
            let raw = STANDARD
                .decode(b64.trim())
                .map_err(|_| VaultError::WrongCredential)?;
            meta.unlock_with_system_dek(&raw)?
        } else {
            meta.unlock_with_system_dek(&[])?
        };
        store.reset_auth_failures(&rec.id)?;
        self.finish_unlock(rec, trimmed.to_string(), vault_dir, meta, dek)
    }

    fn finish_unlock(
        &self,
        rec: VaultRegistryRecord,
        entered_name: String,
        vault_dir: PathBuf,
        mut meta: VaultMeta,
        dek: Zeroizing<[u8; 32]>,
    ) -> VaultResult<UnlockedVaultInfo> {
        let root_dir_id = match meta.root_dir_id.clone() {
            Some(rid) if crate::index::dir_file_path(&vault_dir, &rid, meta.cipher).exists() => rid,
            _ => migrate_legacy_index_to_dirs(&vault_dir, &mut meta, &dek)?,
        };
        let resolved_name = meta
            .decrypt_name(&dek)
            .ok()
            .flatten()
            .unwrap_or(entered_name);
        let state = VaultState::open(
            meta.vault_id.clone(),
            root_dir_id,
            vault_dir.clone(),
            meta.cipher,
            Zeroizing::new(*dek),
        )?;
        let info = UnlockedVaultInfo {
            id: rec.id.clone(),
            name: resolved_name,
            dir_path: rec.dir_path,
            cipher: meta.cipher,
            auth_mode: meta.auth_mode,
            created_at_ms: meta.created_at_ms,
        };
        self.unlocked.write().insert(
            rec.id,
            UnlockedEntry {
                info: info.clone(),
                dek,
                state,
            },
        );
        let sweep_dir = vault_dir;
        std::thread::spawn(move || {
            let _ = sweep_stale_tmp_files(&sweep_dir, Duration::from_secs(300));
        });
        Ok(info)
    }

    pub fn lock(&self, vault_id: &str) -> bool {
        let mut map = self.unlocked.write();
        if let Some(entry) = map.remove(vault_id) {
            entry.state.lock_and_zeroize();
            true
        } else {
            false
        }
    }

    pub fn lock_all(&self) -> Vec<String> {
        let mut map = self.unlocked.write();
        let ids: Vec<String> = map.keys().cloned().collect();
        for (_, entry) in map.drain() {
            entry.state.lock_and_zeroize();
        }
        ids
    }

    pub fn list_unlocked(&self) -> Vec<UnlockedVaultInfo> {
        let mut list: Vec<UnlockedVaultInfo> = self
            .unlocked
            .read()
            .values()
            .map(|e| e.info.clone())
            .collect();
        list.sort_by_key(|v| v.created_at_ms);
        list
    }

    pub fn get_vfs(&self, vault_id: &str) -> VaultResult<Arc<dyn Vfs>> {
        let guard = self.unlocked.read();
        let entry = guard
            .get(vault_id)
            .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
        Ok(Arc::new(VaultFs::new(entry.state.clone())))
    }

    pub fn get_state(&self, vault_id: &str) -> VaultResult<Arc<VaultState>> {
        let guard = self.unlocked.read();
        let entry = guard
            .get(vault_id)
            .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
        Ok(entry.state.clone())
    }

    pub async fn read_thumbnail(&self, vault_id: &str, rel_path: &str) -> VaultResult<Option<Vec<u8>>> {
        let state = self.get_state(vault_id)?;
        let path = VfsPath::from_slash_path(rel_path);
        state.read_thumbnail(&path).await
    }

    pub async fn save_thumbnail(
        &self,
        vault_id: &str,
        rel_path: &str,
        bytes: Vec<u8>,
    ) -> VaultResult<()> {
        let state = self.get_state(vault_id)?;
        let path = VfsPath::from_slash_path(rel_path);
        state.save_thumbnail(&path, bytes).await
    }

    pub fn export_backup(
        &self,
        vault_id: &str,
        backup_password: Option<&str>,
        dest_archive_path: &Path,
    ) -> VaultResult<()> {
        self.export_backup_with_progress(vault_id, backup_password, dest_archive_path, None, None)
    }

    pub fn export_backup_with_progress(
        &self,
        vault_id: &str,
        backup_password: Option<&str>,
        dest_archive_path: &Path,
        cancel: Option<&AtomicBool>,
        on_progress: Option<&mut dyn FnMut(u64, u64)>,
    ) -> VaultResult<()> {
        let (dir_path, vault_name, dek_copy) = {
            let guard = self.unlocked.read();
            let entry = guard
                .get(vault_id)
                .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
            (
                PathBuf::from(&entry.info.dir_path),
                entry.info.name.clone(),
                Zeroizing::new(*entry.dek),
            )
        };
        let _ = VaultMeta::load(&dir_path)?;
        export_vault_backup_with_progress(
            &dir_path,
            &vault_name,
            Some(&dek_copy),
            backup_password,
            dest_archive_path,
            cancel,
            on_progress,
        )
    }

    pub fn inspect_backup(&self, archive_path: &Path) -> VaultResult<VaultBackupInfo> {
        inspect_vault_backup(archive_path)
    }

    pub fn rename_vault(&self, vault_id: &str, new_name: &str) -> VaultResult<UnlockedVaultInfo> {
        let trimmed = new_name.trim();
        if !crate::backup::is_valid_vault_name(trimmed) {
            return Err(VaultError::InvalidPassword("invalid folder name".to_string()));
        }

        let (dir_path, dek_copy) = {
            let guard = self.unlocked.read();
            let entry = guard
                .get(vault_id)
                .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
            if entry.info.name == trimmed {
                return Ok(entry.info.clone());
            }
            (
                PathBuf::from(&entry.info.dir_path),
                Zeroizing::new(*entry.dek),
            )
        };

        let store = self.store()?;
        if let Some(existing) = store.find_by_name(trimmed)? {
            if existing.id != vault_id {
                return Err(VaultError::AlreadyExists(trimmed.to_string()));
            }
        }

        let old_meta = VaultMeta::load(&dir_path)?;
        let mut new_meta = old_meta.clone();
        new_meta.update_name_fields(trimmed, &dek_copy)?;
        new_meta.save(&dir_path)?;

        if let Err(e) = store.rename_record(vault_id, trimmed) {
            let _ = old_meta.save(&dir_path);
            return Err(e);
        }

        let mut guard = self.unlocked.write();
        if let Some(entry) = guard.get_mut(vault_id) {
            entry.info.name = trimmed.to_string();
            return Ok(entry.info.clone());
        }
        Err(VaultError::Locked(vault_id.to_string()))
    }

    pub fn change_password(
        &self,
        vault_id: &str,
        current_password: Option<&str>,
        new_password: &str,
    ) -> VaultResult<UnlockedVaultInfo> {
        validate_password(new_password)?;
        let (dir_path, dek_copy) = {
            let guard = self.unlocked.read();
            let entry = guard
                .get(vault_id)
                .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
            (
                PathBuf::from(&entry.info.dir_path),
                Zeroizing::new(*entry.dek),
            )
        };

        let old_meta = VaultMeta::load(&dir_path)?;
        if old_meta.auth_mode == VaultAuthMode::Password {
            let cur = current_password.ok_or(VaultError::WrongCredential)?;
            let _ = old_meta.unlock_with_password(cur)?;
        }

        let store = self.store()?;
        let mut new_meta = old_meta.clone();
        new_meta.apply_auth_mode(VaultAuthMode::Password, Some(new_password), &dek_copy)?;
        new_meta.save(&dir_path)?;

        if let Err(e) = store.update_auth_mode(vault_id, VaultAuthMode::Password) {
            let _ = old_meta.save(&dir_path);
            return Err(e);
        }

        let mut guard = self.unlocked.write();
        if let Some(entry) = guard.get_mut(vault_id) {
            entry.info.auth_mode = VaultAuthMode::Password;
            return Ok(entry.info.clone());
        }
        Err(VaultError::Locked(vault_id.to_string()))
    }

    pub fn prepare_switch_to_system(
        &self,
        vault_id: &str,
        current_password: &str,
    ) -> VaultResult<Option<String>> {
        let (dir_path, dek_copy) = {
            let guard = self.unlocked.read();
            let entry = guard
                .get(vault_id)
                .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
            (
                PathBuf::from(&entry.info.dir_path),
                Zeroizing::new(*entry.dek),
            )
        };

        let meta = VaultMeta::load(&dir_path)?;
        if meta.auth_mode != VaultAuthMode::Password {
            return Err(VaultError::Unsupported(
                "privacy folder already uses system unlock".to_string(),
            ));
        }
        let _ = meta.unlock_with_password(current_password)?;
        if meta.cipher.is_encrypted() {
            Ok(Some(STANDARD.encode(&*dek_copy)))
        } else {
            Ok(None)
        }
    }

    pub fn commit_switch_to_system(&self, vault_id: &str) -> VaultResult<UnlockedVaultInfo> {
        let (dir_path, dek_copy) = {
            let guard = self.unlocked.read();
            let entry = guard
                .get(vault_id)
                .ok_or_else(|| VaultError::Locked(vault_id.to_string()))?;
            (
                PathBuf::from(&entry.info.dir_path),
                Zeroizing::new(*entry.dek),
            )
        };

        let old_meta = VaultMeta::load(&dir_path)?;
        let store = self.store()?;
        let mut new_meta = old_meta.clone();
        new_meta.apply_auth_mode(VaultAuthMode::System, None, &dek_copy)?;
        new_meta.save(&dir_path)?;

        if let Err(e) = store.update_auth_mode(vault_id, VaultAuthMode::System) {
            let _ = old_meta.save(&dir_path);
            return Err(e);
        }

        let mut guard = self.unlocked.write();
        if let Some(entry) = guard.get_mut(vault_id) {
            entry.info.auth_mode = VaultAuthMode::System;
            return Ok(entry.info.clone());
        }
        Err(VaultError::Locked(vault_id.to_string()))
    }

    pub fn vault_stats(&self, vault_id: &str) -> VaultResult<VaultStats> {
        let state = self.get_state(vault_id)?;
        state.compute_stats(Duration::from_secs(60))
    }

    pub async fn gc_vault(&self, vault_id: &str) -> VaultResult<VaultGcResult> {
        let state = self.get_state(vault_id)?;
        state.gc_orphaned_files_async(Duration::from_secs(60)).await
    }

    pub fn import_backup(
        &self,
        archive_path: &Path,
        vault_name: Option<&str>,
        target_storage_root: &Path,
        backup_password: Option<&str>,
        target_auth_mode: VaultAuthMode,
        new_local_password: Option<&str>,
    ) -> VaultResult<ImportedVaultResult> {
        self.import_backup_with_progress(
            archive_path,
            vault_name,
            target_storage_root,
            backup_password,
            target_auth_mode,
            new_local_password,
            None,
            None,
        )
    }

    pub fn import_backup_with_progress(
        &self,
        archive_path: &Path,
        vault_name: Option<&str>,
        target_storage_root: &Path,
        backup_password: Option<&str>,
        target_auth_mode: VaultAuthMode,
        new_local_password: Option<&str>,
        cancel: Option<&AtomicBool>,
        on_progress: Option<&mut dyn FnMut(u64, u64)>,
    ) -> VaultResult<ImportedVaultResult> {
        let store = self.store()?;
        let imported = import_vault_backup_with_progress(
            &store,
            archive_path,
            vault_name,
            target_storage_root,
            backup_password,
            target_auth_mode,
            new_local_password,
            cancel,
            on_progress,
        )?;
        let meta = VaultMeta::load(&imported.dir_path)?;
        let root_dir_id = meta
            .root_dir_id
            .clone()
            .ok_or_else(|| VaultError::Backup("imported vault missing root_dir_id".to_string()))?;
        let dek = if let Some(ref b64) = imported.system_dek_b64 {
            let raw = STANDARD
                .decode(b64.trim())
                .map_err(|e| VaultError::Crypto(e.to_string()))?;
            meta.unlock_with_system_dek(&raw)?
        } else if imported.auth_mode == VaultAuthMode::Password {
            let pwd = new_local_password.or(backup_password).unwrap_or("");
            meta.unlock_with_password(pwd)?
        } else {
            Zeroizing::new([0u8; 32])
        };

        let state = VaultState::open(
            meta.vault_id.clone(),
            root_dir_id,
            imported.dir_path.clone(),
            imported.cipher,
            Zeroizing::new(*dek),
        )?;
        let info = UnlockedVaultInfo {
            id: imported.local_id.clone(),
            name: imported.name.clone(),
            dir_path: imported.dir_path.to_string_lossy().to_string(),
            cipher: imported.cipher,
            auth_mode: imported.auth_mode,
            created_at_ms: meta.created_at_ms,
        };
        self.unlocked.write().insert(
            imported.local_id.clone(),
            UnlockedEntry {
                info,
                dek,
                state,
            },
        );
        Ok(imported)
    }

    pub fn delete_vault(&self, vault_id: &str) -> VaultResult<()> {
        let _ = self.lock(vault_id);
        let store = self.store()?;
        if let Some(rec) = store.remove_record(vault_id)? {
            let dir = PathBuf::from(&rec.dir_path);
            if dir.exists() {
                std::fs::remove_dir_all(&dir)?;
            }
            Ok(())
        } else {
            Err(VaultError::NotFound(vault_id.to_string()))
        }
    }
}
