use crate::crypto::{constant_time_eq_hex, hash_name, random_bytes, VaultAuthMode, VaultCipher};
use crate::error::{VaultError, VaultResult};
use crate::meta::{atomic_write_bytes, now_millis, VaultMeta};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

const REGISTRY_FILE: &str = "privacy_vaults.json";
const IOS_CONTAINER_MARKER: &str = "/Containers/Data/Application/";

fn split_ios_container_path(path: &str) -> Option<(&str, &str)> {
    let idx = path.find(IOS_CONTAINER_MARKER)?;
    let uuid_start = idx + IOS_CONTAINER_MARKER.len();
    let rest = &path[uuid_start..];
    let uuid_end = match rest.find('/') {
        Some(rel) => uuid_start + rel,
        None => path.len(),
    };
    if uuid_end == uuid_start {
        return None;
    }
    Some((&path[..uuid_end], &path[uuid_end..]))
}

fn relocate_vault_dir_path(stored_dir: &str, app_data_dir: &Path, vault_id: &str) -> Option<PathBuf> {
    let app_data_str = app_data_dir.to_string_lossy();
    if let (Some((current_root, _)), Some((_, rel_suffix))) = (
        split_ios_container_path(&app_data_str),
        split_ios_container_path(stored_dir),
    ) {
        if !rel_suffix.is_empty() {
            let candidate = PathBuf::from(format!("{current_root}{rel_suffix}"));
            if candidate.join("vault.meta.json").exists() {
                return Some(candidate);
            }
        }
    }

    let fallback = app_data_dir.join("private_vaults").join(vault_id);
    if fallback.join("vault.meta.json").exists() {
        return Some(fallback);
    }
    None
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultRegistryRecord {
    pub id: String,
    pub name_salt_b64: String,
    pub name_hash: String,
    pub dir_path: String,
    pub cipher: VaultCipher,
    pub auth_mode: VaultAuthMode,
    pub created_at_ms: i64,
    #[serde(default)]
    pub failed_attempts: u32,
    #[serde(default)]
    pub locked_until_ms: i64,
}

impl VaultRegistryRecord {
    pub fn matches_name(&self, name: &str) -> bool {
        let Ok(salt) = STANDARD.decode(self.name_salt_b64.trim()) else {
            return false;
        };
        constant_time_eq_hex(&self.name_hash, &hash_name(&salt, name))
    }

    pub fn update_name_hash(&mut self, name: &str) {
        let salt = random_bytes::<16>();
        self.name_hash = hash_name(&salt, name);
        self.name_salt_b64 = STANDARD.encode(salt);
    }

    pub fn cooldown_remaining_secs(&self, now_ms: i64) -> Option<u64> {
        if self.locked_until_ms > now_ms {
            let diff_ms = self.locked_until_ms - now_ms;
            Some(((diff_ms + 999) / 1000) as u64)
        } else {
            None
        }
    }

    pub fn record_failure(&mut self, now_ms: i64) {
        self.failed_attempts = self.failed_attempts.saturating_add(1);
        let penalty_secs: i64 = if self.failed_attempts >= 8 {
            300
        } else if self.failed_attempts >= 6 {
            60
        } else if self.failed_attempts >= 5 {
            30
        } else {
            0
        };
        if penalty_secs > 0 {
            self.locked_until_ms = now_ms + penalty_secs * 1000;
        }
    }

    pub fn reset_failures(&mut self) {
        self.failed_attempts = 0;
        self.locked_until_ms = 0;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct RegistryFile {
    pub version: u32,
    pub vaults: Vec<VaultRegistryRecord>,
}

pub struct VaultStore {
    app_data_dir: PathBuf,
}

impl VaultStore {
    pub fn new(app_data_dir: impl Into<PathBuf>) -> Self {
        Self {
            app_data_dir: app_data_dir.into(),
        }
    }

    pub fn app_data_dir(&self) -> &Path {
        &self.app_data_dir
    }

    fn registry_path(&self) -> PathBuf {
        self.app_data_dir.join(REGISTRY_FILE)
    }

    fn load_file(&self) -> VaultResult<RegistryFile> {
        let p = self.registry_path();
        if !p.exists() {
            return Ok(RegistryFile {
                version: 1,
                vaults: Vec::new(),
            });
        }
        let bytes = std::fs::read(&p)?;
        let mut file: RegistryFile = serde_json::from_slice(&bytes)?;
        let mut repaired = false;
        for rec in &mut file.vaults {
            if !Path::new(&rec.dir_path).join("vault.meta.json").exists() {
                if let Some(relocated) =
                    relocate_vault_dir_path(&rec.dir_path, &self.app_data_dir, &rec.id)
                {
                    rec.dir_path = relocated.to_string_lossy().to_string();
                    repaired = true;
                }
            }
        }
        if repaired {
            let _ = self.save_file(&file);
        }
        Ok(file)
    }

    pub fn repair_relocated_paths(&self) -> VaultResult<usize> {
        let file = self.load_file()?;
        Ok(file.vaults.len())
    }

    fn save_file(&self, file: &RegistryFile) -> VaultResult<()> {
        let json = serde_json::to_vec_pretty(file)?;
        atomic_write_bytes(&self.registry_path(), &json)
    }

    pub fn list_records(&self) -> VaultResult<Vec<VaultRegistryRecord>> {
        Ok(self.load_file()?.vaults)
    }

    pub fn find_by_name(&self, name: &str) -> VaultResult<Option<VaultRegistryRecord>> {
        let file = self.load_file()?;
        for rec in file.vaults {
            if rec.matches_name(name) && Path::new(&rec.dir_path).join("vault.meta.json").exists() {
                return Ok(Some(rec));
            }
        }
        Ok(None)
    }

    pub fn find_by_id(&self, id: &str) -> VaultResult<Option<VaultRegistryRecord>> {
        let file = self.load_file()?;
        Ok(file.vaults.into_iter().find(|r| r.id == id))
    }

    pub fn has_id(&self, id: &str) -> VaultResult<bool> {
        Ok(self.find_by_id(id)?.is_some())
    }

    pub fn add_record(&self, rec: VaultRegistryRecord) -> VaultResult<()> {
        let mut file = self.load_file()?;
        file.version = 1;
        file.vaults.retain(|r| r.id != rec.id);
        file.vaults.push(rec);
        self.save_file(&file)
    }

    pub fn rename_record(&self, id: &str, new_name: &str) -> VaultResult<()> {
        let mut file = self.load_file()?;
        let rec = file
            .vaults
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or_else(|| VaultError::NotFound(id.to_string()))?;
        rec.update_name_hash(new_name);
        self.save_file(&file)
    }

    pub fn update_auth_mode(&self, id: &str, auth_mode: VaultAuthMode) -> VaultResult<()> {
        let mut file = self.load_file()?;
        let rec = file
            .vaults
            .iter_mut()
            .find(|r| r.id == id)
            .ok_or_else(|| VaultError::NotFound(id.to_string()))?;
        rec.auth_mode = auth_mode;
        rec.reset_failures();
        self.save_file(&file)
    }

    pub fn remove_record(&self, id: &str) -> VaultResult<Option<VaultRegistryRecord>> {
        let mut file = self.load_file()?;
        let pos = file.vaults.iter().position(|r| r.id == id);
        let removed = pos.map(|i| file.vaults.remove(i));
        if removed.is_some() {
            self.save_file(&file)?;
        }
        Ok(removed)
    }

    pub fn check_cooldown(&self, id: &str) -> VaultResult<()> {
        if let Some(rec) = self.find_by_id(id)? {
            if let Some(secs) = rec.cooldown_remaining_secs(now_millis()) {
                return Err(VaultError::CooldownActive(secs));
            }
        }
        Ok(())
    }

    pub fn record_auth_failure(&self, id: &str) -> VaultResult<()> {
        let mut file = self.load_file()?;
        if let Some(rec) = file.vaults.iter_mut().find(|r| r.id == id) {
            rec.record_failure(now_millis());
            self.save_file(&file)?;
        }
        Ok(())
    }

    pub fn reset_auth_failures(&self, id: &str) -> VaultResult<()> {
        let mut file = self.load_file()?;
        if let Some(rec) = file.vaults.iter_mut().find(|r| r.id == id) {
            if rec.failed_attempts != 0 || rec.locked_until_ms != 0 {
                rec.reset_failures();
                self.save_file(&file)?;
            }
        }
        Ok(())
    }
}

pub fn ensure_private_storage_root(path: &Path) -> VaultResult<()> {
    std::fs::create_dir_all(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700));
    }
    #[cfg(target_os = "windows")]
    {
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .map(|n| n.starts_with('.'))
            .unwrap_or(false)
        {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            let _ = std::process::Command::new("attrib")
                .arg("+H")
                .arg(path)
                .creation_flags(CREATE_NO_WINDOW)
                .status();
        }
    }
    Ok(())
}

pub fn make_registry_record(local_id: String, name: &str, dir_path: &Path, meta: &VaultMeta) -> VaultRegistryRecord {
    let mut rec = VaultRegistryRecord {
        id: local_id,
        name_salt_b64: String::new(),
        name_hash: String::new(),
        dir_path: dir_path.to_string_lossy().to_string(),
        cipher: meta.cipher,
        auth_mode: meta.auth_mode,
        created_at_ms: meta.created_at_ms,
        failed_attempts: 0,
        locked_until_ms: 0,
    };
    rec.update_name_hash(name);
    rec
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
const KEYRING_SERVICE: &str = "com.github.th997.filemanager.vault";

#[cfg(any(target_os = "macos", target_os = "windows"))]
pub fn desktop_keystore_save(key: &str, value: &str) -> VaultResult<()> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, key)
        .map_err(|e| VaultError::Crypto(format!("keyring entry failed: {e}")))?;
    entry
        .set_password(value)
        .map_err(|e| VaultError::Crypto(format!("keyring save failed: {e}")))
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn desktop_keystore_save(_key: &str, _value: &str) -> VaultResult<()> {
    Err(VaultError::Unsupported(
        "desktop keystore is only available on macOS and Windows".to_string(),
    ))
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
pub fn desktop_keystore_read(key: &str) -> VaultResult<Option<String>> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, key)
        .map_err(|e| VaultError::Crypto(format!("keyring entry failed: {e}")))?;
    match entry.get_password() {
        Ok(v) => Ok(Some(v)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(VaultError::Crypto(format!("keyring read failed: {e}"))),
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn desktop_keystore_read(_key: &str) -> VaultResult<Option<String>> {
    Err(VaultError::Unsupported(
        "desktop keystore is only available on macOS and Windows".to_string(),
    ))
}

#[cfg(any(target_os = "macos", target_os = "windows"))]
pub fn desktop_keystore_delete(key: &str) -> VaultResult<()> {
    let entry = keyring::Entry::new(KEYRING_SERVICE, key)
        .map_err(|e| VaultError::Crypto(format!("keyring entry failed: {e}")))?;
    match entry.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(VaultError::Crypto(format!("keyring delete failed: {e}"))),
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub fn desktop_keystore_delete(_key: &str) -> VaultResult<()> {
    Ok(())
}
