use crate::crypto::{
    constant_time_eq_hex, decrypt_blob, derive_kek_argon2id_with_params, encrypt_blob, hash_name,
    password_verifier_hmac, random_bytes, system_dek_verifier, unwrap_dek, validate_password,
    wrap_dek, KdfParams, VaultAuthMode, VaultCipher,
};
use crate::error::{VaultError, VaultResult};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use zeroize::Zeroizing;

pub const VAULT_META_FILE: &str = "vault.meta.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VaultMeta {
    pub version: u32,
    pub vault_id: String,
    pub cipher: VaultCipher,
    pub auth_mode: VaultAuthMode,
    pub name_salt_b64: String,
    pub name_hash: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enc_name_b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kdf_salt_b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kdf_params: Option<KdfParams>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wrapped_dek: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub password_verifier: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub system_dek_verifier: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup_kdf_salt_b64: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup_kdf_params: Option<KdfParams>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup_wrapped_dek: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backup_plain_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub root_dir_id: Option<String>,
    pub created_at_ms: i64,
}

pub fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn atomic_write_bytes(path: &Path, bytes: &[u8]) -> VaultResult<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let tmp_name = format!(
        "{}.{}.tmp",
        path.file_name().and_then(|n| n.to_str()).unwrap_or("vault"),
        uuid::Uuid::new_v4().simple()
    );
    let tmp_path = parent.join(tmp_name);

    let write_res = (|| -> std::io::Result<()> {
        use std::io::Write;
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut f = opts.open(&tmp_path)?;
        f.write_all(bytes)?;
        f.flush()?;
        f.sync_all()?;
        Ok(())
    })();

    if let Err(e) = write_res {
        let _ = std::fs::remove_file(&tmp_path);
        return Err(VaultError::Io(e));
    }

    if let Err(first_err) = std::fs::rename(&tmp_path, path) {
        if path.exists() {
            let bak_path = parent.join(format!(
                "{}.{}.bak",
                path.file_name().and_then(|n| n.to_str()).unwrap_or("vault"),
                uuid::Uuid::new_v4().simple()
            ));
            let moved_old = std::fs::rename(path, &bak_path).is_ok();
            match std::fs::rename(&tmp_path, path) {
                Ok(()) => {
                    if moved_old {
                        let _ = std::fs::remove_file(&bak_path);
                    }
                    return Ok(());
                }
                Err(e) => {
                    if moved_old {
                        let _ = std::fs::rename(&bak_path, path);
                    }
                    let _ = std::fs::remove_file(&tmp_path);
                    return Err(VaultError::Io(e));
                }
            }
        }
        let _ = std::fs::remove_file(&tmp_path);
        return Err(VaultError::Io(first_err));
    }
    Ok(())
}

impl VaultMeta {
    pub fn wrap_aad(vault_id: &str) -> Vec<u8> {
        format!("fm-vault-dek-v1:{vault_id}").into_bytes()
    }

    pub fn name_aad(vault_id: &str) -> Vec<u8> {
        format!("fm-vault-name-v1:{vault_id}").into_bytes()
    }

    pub fn new_vault(
        vault_id: String,
        name: &str,
        cipher: VaultCipher,
        auth_mode: VaultAuthMode,
        password: Option<&str>,
    ) -> VaultResult<(Self, Zeroizing<[u8; 32]>)> {
        let name_salt = random_bytes::<16>();
        let name_hash = hash_name(&name_salt, name);
        let name_salt_b64 = STANDARD.encode(name_salt);

        let dek = Zeroizing::new(if cipher.is_encrypted() {
            random_bytes::<32>()
        } else {
            [0u8; 32]
        });

        let enc_name_b64 = if cipher.is_encrypted() {
            let blob = encrypt_blob(&dek, cipher, &Self::name_aad(&vault_id), name.as_bytes())?;
            Some(STANDARD.encode(blob))
        } else {
            None
        };

        let mut kdf_salt_b64 = None;
        let mut kdf_params = None;
        let mut wrapped_dek = None;
        let mut pwd_verifier = None;
        let mut sys_verifier = None;

        match auth_mode {
            VaultAuthMode::Password => {
                let pwd = password.ok_or_else(|| {
                    VaultError::InvalidPassword("password is required".to_string())
                })?;
                validate_password(pwd)?;
                let salt = random_bytes::<16>();
                let params = KdfParams::default();
                let kek = derive_kek_argon2id_with_params(pwd, &salt, params)?;
                kdf_salt_b64 = Some(STANDARD.encode(salt));
                kdf_params = Some(params);
                if cipher.is_encrypted() {
                    wrapped_dek = Some(wrap_dek(&kek, &dek, &Self::wrap_aad(&vault_id))?);
                } else {
                    pwd_verifier = Some(password_verifier_hmac(&kek)?);
                }
            }
            VaultAuthMode::System => {
                if cipher.is_encrypted() {
                    sys_verifier = Some(system_dek_verifier(&dek)?);
                }
            }
        }

        let meta = Self {
            version: 1,
            vault_id,
            cipher,
            auth_mode,
            name_salt_b64,
            name_hash,
            enc_name_b64,
            kdf_salt_b64,
            kdf_params,
            wrapped_dek,
            password_verifier: pwd_verifier,
            system_dek_verifier: sys_verifier,
            backup_kdf_salt_b64: None,
            backup_kdf_params: None,
            backup_wrapped_dek: None,
            backup_plain_name: None,
            root_dir_id: Some(uuid::Uuid::new_v4().simple().to_string()),
            created_at_ms: now_millis(),
        };
        Ok((meta, dek))
    }

    pub fn load(vault_dir: &Path) -> VaultResult<Self> {
        let bytes = std::fs::read(vault_dir.join(VAULT_META_FILE))?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    pub fn save(&self, vault_dir: &Path) -> VaultResult<()> {
        let json = serde_json::to_vec_pretty(self)?;
        atomic_write_bytes(&vault_dir.join(VAULT_META_FILE), &json)
    }

    pub fn verify_name(&self, name: &str) -> VaultResult<bool> {
        let salt = STANDARD
            .decode(self.name_salt_b64.trim())
            .map_err(|e| VaultError::Crypto(format!("invalid name salt: {e}")))?;
        Ok(constant_time_eq_hex(&self.name_hash, &hash_name(&salt, name)))
    }

    pub fn unlock_with_password(&self, password: &str) -> VaultResult<Zeroizing<[u8; 32]>> {
        if self.auth_mode != VaultAuthMode::Password {
            return Err(VaultError::Unsupported(
                "this privacy folder uses system unlock".to_string(),
            ));
        }
        let salt_b64 = self
            .kdf_salt_b64
            .as_deref()
            .ok_or_else(|| VaultError::Crypto("missing kdf salt".to_string()))?;
        let salt = STANDARD
            .decode(salt_b64.trim())
            .map_err(|e| VaultError::Crypto(format!("invalid kdf salt: {e}")))?;
        let kek = derive_kek_argon2id_with_params(password, &salt, self.kdf_params.unwrap_or_default())?;
        if self.cipher.is_encrypted() {
            let wrapped = self
                .wrapped_dek
                .as_deref()
                .ok_or_else(|| VaultError::Crypto("missing wrapped dek".to_string()))?;
            unwrap_dek(&kek, wrapped, &Self::wrap_aad(&self.vault_id))
        } else {
            let expected = self
                .password_verifier
                .as_deref()
                .ok_or_else(|| VaultError::Crypto("missing password verifier".to_string()))?;
            let actual = password_verifier_hmac(&kek)?;
            if !constant_time_eq_hex(expected, &actual) {
                return Err(VaultError::WrongCredential);
            }
            Ok(Zeroizing::new([0u8; 32]))
        }
    }

    pub fn unlock_with_system_dek(&self, dek_bytes: &[u8]) -> VaultResult<Zeroizing<[u8; 32]>> {
        if self.auth_mode != VaultAuthMode::System {
            return Err(VaultError::Unsupported(
                "this privacy folder uses password unlock".to_string(),
            ));
        }
        if !self.cipher.is_encrypted() {
            return Ok(Zeroizing::new([0u8; 32]));
        }
        if dek_bytes.len() != 32 {
            return Err(VaultError::WrongCredential);
        }
        let mut dek = Zeroizing::new([0u8; 32]);
        dek.copy_from_slice(dek_bytes);
        let expected = self
            .system_dek_verifier
            .as_deref()
            .ok_or_else(|| VaultError::Crypto("missing system dek verifier".to_string()))?;
        let actual = system_dek_verifier(&dek)?;
        if !constant_time_eq_hex(expected, &actual) {
            return Err(VaultError::WrongCredential);
        }
        Ok(dek)
    }

    pub fn decrypt_name(&self, dek: &[u8; 32]) -> VaultResult<Option<String>> {
        if !self.cipher.is_encrypted() {
            return Ok(None);
        }
        let Some(ref enc_b64) = self.enc_name_b64 else {
            return Ok(None);
        };
        let blob = STANDARD
            .decode(enc_b64.trim())
            .map_err(|e| VaultError::Crypto(format!("invalid encrypted name: {e}")))?;
        let plain = decrypt_blob(dek, self.cipher, &Self::name_aad(&self.vault_id), &blob)?;
        let s = String::from_utf8(plain)
            .map_err(|e| VaultError::Crypto(format!("invalid utf8 vault name: {e}")))?;
        Ok(Some(s))
    }

    pub fn update_name_fields(&mut self, new_name: &str, dek: &[u8; 32]) -> VaultResult<()> {
        let salt = random_bytes::<16>();
        self.name_hash = hash_name(&salt, new_name);
        self.name_salt_b64 = STANDARD.encode(salt);
        self.backup_plain_name = None;
        if self.cipher.is_encrypted() {
            let blob = encrypt_blob(
                dek,
                self.cipher,
                &Self::name_aad(&self.vault_id),
                new_name.as_bytes(),
            )?;
            self.enc_name_b64 = Some(STANDARD.encode(blob));
        } else {
            self.enc_name_b64 = None;
        }
        Ok(())
    }

    pub fn apply_auth_mode(
        &mut self,
        auth_mode: VaultAuthMode,
        password: Option<&str>,
        dek: &[u8; 32],
    ) -> VaultResult<()> {
        self.auth_mode = auth_mode;
        self.kdf_salt_b64 = None;
        self.kdf_params = None;
        self.wrapped_dek = None;
        self.password_verifier = None;
        self.system_dek_verifier = None;
        self.backup_kdf_salt_b64 = None;
        self.backup_kdf_params = None;
        self.backup_wrapped_dek = None;
        self.backup_plain_name = None;

        match auth_mode {
            VaultAuthMode::Password => {
                let pwd = password.ok_or_else(|| {
                    VaultError::InvalidPassword("password is required".to_string())
                })?;
                validate_password(pwd)?;
                let salt = random_bytes::<16>();
                let params = KdfParams::default();
                let kek = derive_kek_argon2id_with_params(pwd, &salt, params)?;
                self.kdf_salt_b64 = Some(STANDARD.encode(salt));
                self.kdf_params = Some(params);
                if self.cipher.is_encrypted() {
                    self.wrapped_dek =
                        Some(wrap_dek(&kek, dek, &Self::wrap_aad(&self.vault_id))?);
                } else {
                    self.password_verifier = Some(password_verifier_hmac(&kek)?);
                }
            }
            VaultAuthMode::System => {
                if self.cipher.is_encrypted() {
                    self.system_dek_verifier = Some(system_dek_verifier(dek)?);
                }
            }
        }
        Ok(())
    }
}
