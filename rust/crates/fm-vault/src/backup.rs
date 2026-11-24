use crate::crypto::{
    derive_kek_argon2id_with_params, encrypt_blob, random_bytes, unwrap_dek, validate_password,
    wrap_dek, KdfParams, VaultAuthMode, VaultCipher,
};
use crate::error::{VaultError, VaultResult};
use crate::index::{
    dir_file_path, migrate_legacy_index_to_dirs, VaultDirFile, DIRS_DIR, INDEX_ENC_FILE,
    INDEX_JSON_FILE,
};
use crate::meta::{VaultMeta, VAULT_META_FILE};
use crate::registry::{ensure_private_storage_root, make_registry_record, VaultStore};
use crate::vfs::{OBJECTS_DIR, THUMBS_DIR};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use zeroize::Zeroizing;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

const MAX_META_JSON_BYTES: u64 = 1024 * 1024;
const MAX_INDEX_BYTES: u64 = 128 * 1024 * 1024;
const ZIP64_FILE_THRESHOLD: u64 = 0xFFFF_FFFF;
const ZIP64_ARCHIVE_THRESHOLD: u64 = 0xE000_0000;
const PROGRESS_REPORT_STEP_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone)]
pub struct VaultBackupInfo {
    pub cipher: VaultCipher,
    pub original_auth_mode: VaultAuthMode,
    pub requires_password: bool,
    pub object_count: u32,
    pub original_name: Option<String>,
}

pub(crate) fn is_valid_vault_name(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && !name.contains('/')
        && !name.contains('\\')
}

#[derive(Debug, Clone)]
pub struct ImportedVaultResult {
    pub local_id: String,
    pub crypto_vault_id: String,
    pub name: String,
    pub dir_path: PathBuf,
    pub cipher: VaultCipher,
    pub auth_mode: VaultAuthMode,
    pub system_dek_b64: Option<String>,
}

fn check_cancelled(cancel: Option<&AtomicBool>) -> VaultResult<()> {
    if cancel.map(|c| c.load(Ordering::Acquire)).unwrap_or(false) {
        return Err(VaultError::Cancelled);
    }
    Ok(())
}

fn copy_with_progress<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    done_bytes: &mut u64,
    total_bytes: u64,
    cancel: Option<&AtomicBool>,
    on_progress: &mut Option<&mut dyn FnMut(u64, u64)>,
) -> VaultResult<u64> {
    let mut buf = vec![0u8; 256 * 1024];
    let mut copied = 0u64;
    let mut since_report = 0u64;
    loop {
        check_cancelled(cancel)?;
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        writer.write_all(&buf[..n])?;
        let n64 = n as u64;
        copied = copied.saturating_add(n64);
        *done_bytes = done_bytes.saturating_add(n64);
        since_report = since_report.saturating_add(n64);
        if since_report >= PROGRESS_REPORT_STEP_BYTES {
            since_report = 0;
            if let Some(cb) = on_progress.as_deref_mut() {
                cb(*done_bytes, total_bytes.max(*done_bytes));
            }
        }
    }
    if since_report > 0 {
        if let Some(cb) = on_progress.as_deref_mut() {
            cb(*done_bytes, total_bytes.max(*done_bytes));
        }
    }
    Ok(copied)
}

fn sum_dir_files_recursive(src_dir: &Path, depth: usize) -> VaultResult<u64> {
    if !src_dir.exists() {
        return Ok(0);
    }
    let mut sum = 0u64;
    for entry in std::fs::read_dir(src_dir)? {
        let entry = entry?;
        let path = entry.path();
        let Ok(meta) = std::fs::symlink_metadata(&path) else {
            continue;
        };
        let ft = meta.file_type();
        if ft.is_symlink() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if ft.is_dir() {
            if depth < 2 {
                sum = sum.saturating_add(sum_dir_files_recursive(&path, depth + 1)?);
            }
            continue;
        }
        if !ft.is_file() || name.ends_with(".tmp") || name.ends_with(".bak") {
            continue;
        }
        sum = sum.saturating_add(meta.len());
    }
    Ok(sum)
}

fn copy_dir_files_recursive<W: Write + std::io::Seek>(
    zip: &mut ZipWriter<W>,
    src_dir: &Path,
    archive_prefix: &str,
    method: CompressionMethod,
    depth: usize,
    archive_large: bool,
    done_bytes: &mut u64,
    total_bytes: u64,
    cancel: Option<&AtomicBool>,
    on_progress: &mut Option<&mut dyn FnMut(u64, u64)>,
) -> VaultResult<()> {
    for entry in std::fs::read_dir(src_dir)? {
        check_cancelled(cancel)?;
        let entry = entry?;
        let path = entry.path();
        let Ok(meta) = std::fs::symlink_metadata(&path) else {
            continue;
        };
        let ft = meta.file_type();
        if ft.is_symlink() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if ft.is_dir() {
            if depth < 2 {
                let next_prefix = format!("{archive_prefix}/{name}");
                copy_dir_files_recursive(
                    zip,
                    &path,
                    &next_prefix,
                    method,
                    depth + 1,
                    archive_large,
                    done_bytes,
                    total_bytes,
                    cancel,
                    on_progress,
                )?;
            }
            continue;
        }
        if !ft.is_file() || name.ends_with(".tmp") || name.ends_with(".bak") {
            continue;
        }
        let archive_name = format!("{archive_prefix}/{name}");
        let use_large = archive_large || meta.len() >= ZIP64_FILE_THRESHOLD;
        let opts = SimpleFileOptions::default()
            .compression_method(method)
            .large_file(use_large);
        zip.start_file(archive_name, opts)
            .map_err(|e| VaultError::Backup(format!("zip start_file failed: {e}")))?;
        let mut f = std::fs::File::open(&path)?;
        copy_with_progress(&mut f, zip, done_bytes, total_bytes, cancel, on_progress)?;
    }
    Ok(())
}

fn copy_dir_files_to_zip<W: Write + std::io::Seek>(
    zip: &mut ZipWriter<W>,
    src_dir: &Path,
    archive_prefix: &str,
    method: CompressionMethod,
    archive_large: bool,
    done_bytes: &mut u64,
    total_bytes: u64,
    cancel: Option<&AtomicBool>,
    on_progress: &mut Option<&mut dyn FnMut(u64, u64)>,
) -> VaultResult<()> {
    if !src_dir.exists() {
        return Ok(());
    }
    copy_dir_files_recursive(
        zip,
        src_dir,
        archive_prefix,
        method,
        0,
        archive_large,
        done_bytes,
        total_bytes,
        cancel,
        on_progress,
    )
}

/// Exports an encrypted (or unencrypted) vault directory to `<dest_archive_path>`.
/// When `cipher` is encrypted and `auth_mode == System`, `backup_password` (8-128 chars)
/// is required and used to wrap the DEK in `backup_wrapped_dek`.
pub fn export_vault_backup(
    vault_dir: &Path,
    vault_name: &str,
    unlocked_dek: Option<&[u8; 32]>,
    backup_password: Option<&str>,
    dest_archive_path: &Path,
) -> VaultResult<()> {
    export_vault_backup_with_progress(
        vault_dir,
        vault_name,
        unlocked_dek,
        backup_password,
        dest_archive_path,
        None,
        None,
    )
}

pub fn export_vault_backup_with_progress(
    vault_dir: &Path,
    vault_name: &str,
    unlocked_dek: Option<&[u8; 32]>,
    backup_password: Option<&str>,
    dest_archive_path: &Path,
    cancel: Option<&AtomicBool>,
    mut on_progress: Option<&mut dyn FnMut(u64, u64)>,
) -> VaultResult<()> {
    check_cancelled(cancel)?;
    let mut meta = VaultMeta::load(vault_dir)?;
    let trimmed_name = vault_name.trim();
    if !is_valid_vault_name(trimmed_name) {
        return Err(VaultError::InvalidPassword("invalid folder name".to_string()));
    }

    if meta.cipher.is_encrypted() {
        meta.backup_plain_name = None;
        if meta.enc_name_b64.is_none() {
            if let Some(dek) = unlocked_dek {
                let blob = encrypt_blob(
                    dek,
                    meta.cipher,
                    &VaultMeta::name_aad(&meta.vault_id),
                    trimmed_name.as_bytes(),
                )?;
                meta.enc_name_b64 = Some(STANDARD.encode(blob));
            }
        }
    } else {
        meta.backup_plain_name = Some(trimmed_name.to_string());
    }

    if meta.cipher.is_encrypted() && meta.auth_mode == VaultAuthMode::System {
        let pwd = backup_password.ok_or_else(|| {
            VaultError::InvalidPassword(
                "backup password (8-128 chars) is required for system-unlocked encrypted vault"
                    .to_string(),
            )
        })?;
        validate_password(pwd)?;
        let dek = unlocked_dek.ok_or_else(|| {
            VaultError::Locked("vault must be unlocked before exporting backup".to_string())
        })?;
        let salt = random_bytes::<16>();
        let params = KdfParams::default();
        let kek = derive_kek_argon2id_with_params(pwd, &salt, params)?;
        meta.backup_kdf_salt_b64 = Some(STANDARD.encode(salt));
        meta.backup_kdf_params = Some(params);
        meta.backup_wrapped_dek =
            Some(wrap_dek(&kek, dek, &VaultMeta::wrap_aad(&meta.vault_id))?);
    } else {
        meta.backup_kdf_salt_b64 = None;
        meta.backup_kdf_params = None;
        meta.backup_wrapped_dek = None;
    }

    let meta_bytes = serde_json::to_vec_pretty(&meta)?;
    let mut total_bytes = meta_bytes.len() as u64;
    if let Some(ref root_id) = meta.root_dir_id {
        if !dir_file_path(vault_dir, root_id, meta.cipher).exists() {
            return Err(VaultError::Backup("vault root directory index is missing".to_string()));
        }
        total_bytes = total_bytes.saturating_add(sum_dir_files_recursive(&vault_dir.join(DIRS_DIR), 0)?);
    } else {
        let idx_path = if meta.cipher.is_encrypted() {
            vault_dir.join(INDEX_ENC_FILE)
        } else {
            vault_dir.join(INDEX_JSON_FILE)
        };
        if let Ok(m) = std::fs::metadata(&idx_path) {
            total_bytes = total_bytes.saturating_add(m.len());
        }
    }
    total_bytes = total_bytes
        .saturating_add(sum_dir_files_recursive(&vault_dir.join(OBJECTS_DIR), 0)?)
        .saturating_add(sum_dir_files_recursive(&vault_dir.join(THUMBS_DIR), 0)?);
    let archive_large = total_bytes >= ZIP64_ARCHIVE_THRESHOLD;

    if let Some(cb) = on_progress.as_deref_mut() {
        cb(0, total_bytes);
    }

    if let Some(parent) = dest_archive_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let tmp_path = dest_archive_path.with_extension(format!("fpmtmp-{}", uuid::Uuid::new_v4().simple()));

    let write_res: VaultResult<u64> = (|| {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let file = opts.open(&tmp_path)?;
        let mut zip = ZipWriter::new(file);
        let mut done_bytes = 0u64;

        check_cancelled(cancel)?;
        let meta_opts = SimpleFileOptions::default()
            .compression_method(CompressionMethod::Deflated)
            .large_file(archive_large);
        zip.start_file(VAULT_META_FILE, meta_opts)
            .map_err(|e| VaultError::Backup(e.to_string()))?;
        zip.write_all(&meta_bytes)?;
        done_bytes = done_bytes.saturating_add(meta_bytes.len() as u64);

        if meta.root_dir_id.is_some() {
            let dir_method = if meta.cipher.is_encrypted() {
                CompressionMethod::Stored
            } else {
                CompressionMethod::Deflated
            };
            copy_dir_files_to_zip(
                &mut zip,
                &vault_dir.join(DIRS_DIR),
                DIRS_DIR,
                dir_method,
                archive_large,
                &mut done_bytes,
                total_bytes,
                cancel,
                &mut on_progress,
            )?;
        } else {
            let enc_idx = vault_dir.join(INDEX_ENC_FILE);
            let plain_idx = vault_dir.join(INDEX_JSON_FILE);
            if meta.cipher.is_encrypted() && enc_idx.exists() {
                let idx_len = std::fs::metadata(&enc_idx).map(|m| m.len()).unwrap_or(0);
                zip.start_file(
                    INDEX_ENC_FILE,
                    SimpleFileOptions::default()
                        .compression_method(CompressionMethod::Stored)
                        .large_file(archive_large || idx_len >= ZIP64_FILE_THRESHOLD),
                )
                .map_err(|e| VaultError::Backup(e.to_string()))?;
                let mut f = std::fs::File::open(&enc_idx)?;
                copy_with_progress(&mut f, &mut zip, &mut done_bytes, total_bytes, cancel, &mut on_progress)?;
            } else if !meta.cipher.is_encrypted() && plain_idx.exists() {
                let idx_len = std::fs::metadata(&plain_idx).map(|m| m.len()).unwrap_or(0);
                zip.start_file(
                    INDEX_JSON_FILE,
                    SimpleFileOptions::default()
                        .compression_method(CompressionMethod::Deflated)
                        .large_file(archive_large || idx_len >= ZIP64_FILE_THRESHOLD),
                )
                .map_err(|e| VaultError::Backup(e.to_string()))?;
                let mut f = std::fs::File::open(&plain_idx)?;
                copy_with_progress(&mut f, &mut zip, &mut done_bytes, total_bytes, cancel, &mut on_progress)?;
            } else {
                return Err(VaultError::Backup("vault index file is missing".to_string()));
            }
        }

        let obj_method = if meta.cipher.is_encrypted() {
            CompressionMethod::Stored
        } else {
            CompressionMethod::Deflated
        };
        copy_dir_files_to_zip(
            &mut zip,
            &vault_dir.join(OBJECTS_DIR),
            OBJECTS_DIR,
            obj_method,
            archive_large,
            &mut done_bytes,
            total_bytes,
            cancel,
            &mut on_progress,
        )?;
        copy_dir_files_to_zip(
            &mut zip,
            &vault_dir.join(THUMBS_DIR),
            THUMBS_DIR,
            obj_method,
            archive_large,
            &mut done_bytes,
            total_bytes,
            cancel,
            &mut on_progress,
        )?;

        check_cancelled(cancel)?;
        let file = zip
            .finish()
            .map_err(|e| VaultError::Backup(format!("zip finish failed: {e}")))?;
        file.sync_all()?;
        Ok(done_bytes)
    })();

    let final_done = match write_res {
        Ok(done) => done,
        Err(e) => {
            let _ = std::fs::remove_file(&tmp_path);
            return Err(e);
        }
    };

    if let Err(e) = std::fs::rename(&tmp_path, dest_archive_path) {
        if dest_archive_path.exists() {
            let _ = std::fs::remove_file(dest_archive_path);
            std::fs::rename(&tmp_path, dest_archive_path).inspect_err(|_| {
                let _ = std::fs::remove_file(&tmp_path);
            })?;
        } else {
            let _ = std::fs::remove_file(&tmp_path);
            return Err(VaultError::Io(e));
        }
    }
    if let Some(cb) = on_progress.as_deref_mut() {
        let final_total = total_bytes.max(final_done);
        cb(final_total, final_total);
    }
    Ok(())
}

fn read_meta_from_archive<R: Read + std::io::Seek>(
    archive: &mut ZipArchive<R>,
) -> VaultResult<VaultMeta> {
    let entry = archive
        .by_name(VAULT_META_FILE)
        .map_err(|e| VaultError::Backup(format!("missing {VAULT_META_FILE}: {e}")))?;
    if entry.size() > MAX_META_JSON_BYTES {
        return Err(VaultError::Backup("backup metadata too large".to_string()));
    }
    let mut bytes = Vec::with_capacity(entry.size() as usize);
    entry.take(MAX_META_JSON_BYTES + 1).read_to_end(&mut bytes)?;
    Ok(serde_json::from_slice(&bytes)?)
}

pub fn inspect_vault_backup(archive_path: &Path) -> VaultResult<VaultBackupInfo> {
    let f = std::fs::File::open(archive_path)?;
    let mut archive = ZipArchive::new(f)
        .map_err(|e| VaultError::Backup(format!("invalid vault archive: {e}")))?;
    let meta = read_meta_from_archive(&mut archive)?;

    let mut object_count = 0u32;
    for i in 0..archive.len() {
        let entry = archive
            .by_index(i)
            .map_err(|e| VaultError::Backup(e.to_string()))?;
        if entry.is_dir() {
            continue;
        }
        let name = entry
            .name()
            .map_err(|e| VaultError::Backup(e.to_string()))?
            .replace('\\', "/");
        if name.starts_with("objects/") && name.len() > "objects/".len() && !name.ends_with('/') {
            object_count = object_count.saturating_add(1);
        }
    }

    let requires_password = meta.backup_wrapped_dek.is_some()
        || meta.wrapped_dek.is_some()
        || meta.password_verifier.is_some();

    let original_name = if !meta.cipher.is_encrypted() {
        meta.backup_plain_name.clone()
    } else {
        None
    };

    Ok(VaultBackupInfo {
        cipher: meta.cipher,
        original_auth_mode: meta.auth_mode,
        requires_password,
        object_count,
        original_name,
    })
}

fn is_safe_leaf_name(leaf: &str) -> bool {
    !leaf.is_empty()
        && leaf != "."
        && leaf != ".."
        && !leaf.contains('/')
        && !leaf.contains('\\')
        && !leaf.contains('\0')
        && !leaf.contains(':')
}

fn safe_blob_dest(base_dir: &Path, rel: &str, raw_name: &str) -> VaultResult<PathBuf> {
    if rel.is_empty() || rel.contains('\\') || rel.contains('\0') || rel.contains(':') {
        return Err(VaultError::Backup(format!("unsafe archive entry: {raw_name}")));
    }
    let parts: Vec<&str> = rel.split('/').collect();
    match parts.as_slice() {
        [leaf] => {
            if !is_safe_leaf_name(leaf) {
                return Err(VaultError::Backup(format!("unsafe archive entry: {raw_name}")));
            }
            Ok(match crate::vfs::shard_prefix(leaf) {
                Some(prefix) => base_dir.join(prefix).join(leaf),
                None => base_dir.join(leaf),
            })
        }
        [shard, leaf] => {
            if shard.len() != 2
                || !shard.bytes().all(|b| b.is_ascii_hexdigit())
                || !is_safe_leaf_name(leaf)
            {
                return Err(VaultError::Backup(format!("unsafe archive entry: {raw_name}")));
            }
            Ok(base_dir.join(shard.to_ascii_lowercase()).join(leaf))
        }
        _ => Err(VaultError::Backup(format!("unsafe archive entry: {raw_name}"))),
    }
}

/// Imports a `.fpmvault` backup into `target_storage_root` under `vault_name`,
/// configuring local auth mode to `target_auth_mode` (and optional `new_local_password`).
///
/// Encrypted objects are copied as-is without decrypting them.
pub fn import_vault_backup(
    store: &VaultStore,
    archive_path: &Path,
    vault_name: Option<&str>,
    target_storage_root: &Path,
    backup_password: Option<&str>,
    target_auth_mode: VaultAuthMode,
    new_local_password: Option<&str>,
) -> VaultResult<ImportedVaultResult> {
    import_vault_backup_with_progress(
        store,
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

pub fn import_vault_backup_with_progress(
    store: &VaultStore,
    archive_path: &Path,
    vault_name: Option<&str>,
    target_storage_root: &Path,
    backup_password: Option<&str>,
    target_auth_mode: VaultAuthMode,
    new_local_password: Option<&str>,
    cancel: Option<&AtomicBool>,
    mut on_progress: Option<&mut dyn FnMut(u64, u64)>,
) -> VaultResult<ImportedVaultResult> {
    check_cancelled(cancel)?;
    let manual_name = vault_name.map(str::trim).filter(|s| !s.is_empty());
    if let Some(name) = manual_name {
        if !is_valid_vault_name(name) {
            return Err(VaultError::InvalidPassword("invalid folder name".to_string()));
        }
        if store.find_by_name(name)?.is_some() {
            return Err(VaultError::AlreadyExists(name.to_string()));
        }
    }

    if target_auth_mode == VaultAuthMode::Password {
        let effective_new_pwd = new_local_password.or(backup_password).ok_or_else(|| {
            VaultError::InvalidPassword("password (8-128 chars) is required".to_string())
        })?;
        validate_password(effective_new_pwd)?;
    }

    let f = std::fs::File::open(archive_path)?;
    let mut archive = ZipArchive::new(f)
        .map_err(|e| VaultError::Backup(format!("invalid vault archive: {e}")))?;
    let mut meta = read_meta_from_archive(&mut archive)?;

    // Recover DEK / verify backup credential before extracting anything.
    let dek: Zeroizing<[u8; 32]> = if let (Some(b_salt_b64), Some(b_wrapped)) = (
        meta.backup_kdf_salt_b64.as_deref(),
        meta.backup_wrapped_dek.as_deref(),
    ) {
        let pwd = backup_password.ok_or(VaultError::WrongCredential)?;
        let salt = STANDARD
            .decode(b_salt_b64.trim())
            .map_err(|e| VaultError::Backup(format!("invalid backup salt: {e}")))?;
        let kek = derive_kek_argon2id_with_params(
            pwd,
            &salt,
            meta.backup_kdf_params.unwrap_or_default(),
        )?;
        unwrap_dek(&kek, b_wrapped, &VaultMeta::wrap_aad(&meta.vault_id))?
    } else if meta.auth_mode == VaultAuthMode::Password {
        let pwd = backup_password.ok_or(VaultError::WrongCredential)?;
        meta.unlock_with_password(pwd)?
    } else if !meta.cipher.is_encrypted() {
        Zeroizing::new([0u8; 32])
    } else {
        return Err(VaultError::Backup(
            "backup archive contains neither wrapped DEK nor backup key".to_string(),
        ));
    };

    check_cancelled(cancel)?;
    let effective_name = if let Some(name) = manual_name {
        name.to_string()
    } else {
        let original = if meta.cipher.is_encrypted() {
            meta.decrypt_name(&dek)?
        } else {
            meta.backup_plain_name.clone()
        };
        let original = original
            .map(|s| s.trim().to_string())
            .filter(|s| is_valid_vault_name(s))
            .ok_or(VaultError::NameRequired)?;
        if store.find_by_name(&original)?.is_some() {
            return Err(VaultError::AlreadyExists(original));
        }
        original
    };

    let expected_index = if meta.cipher.is_encrypted() {
        INDEX_ENC_FILE
    } else {
        INDEX_JSON_FILE
    };
    let mut total_bytes = 0u64;
    for i in 0..archive.len() {
        check_cancelled(cancel)?;
        let entry = archive
            .by_index(i)
            .map_err(|e| VaultError::Backup(e.to_string()))?;
        if entry.is_dir() {
            continue;
        }
        let raw_name = entry
            .name()
            .map_err(|e| VaultError::Backup(e.to_string()))?
            .replace('\\', "/");
        if raw_name == VAULT_META_FILE {
            continue;
        }
        if raw_name == expected_index
            || raw_name.starts_with("dirs/")
            || raw_name.starts_with("objects/")
            || raw_name.starts_with("thumbs/")
        {
            total_bytes = total_bytes.saturating_add(entry.size());
        }
    }
    if let Some(cb) = on_progress.as_deref_mut() {
        cb(0, total_bytes);
    }

    // Determine unique local vault directory id (preserve meta.vault_id for crypto AAD).
    let local_id = if !store.has_id(&meta.vault_id)? && !target_storage_root.join(&meta.vault_id).exists() {
        meta.vault_id.clone()
    } else {
        uuid::Uuid::new_v4().simple().to_string()
    };

    ensure_private_storage_root(target_storage_root)?;
    let dest_dir = target_storage_root.join(&local_id);
    if dest_dir.exists() {
        return Err(VaultError::AlreadyExists(local_id));
    }

    let extract_res: VaultResult<u64> = (|| {
        std::fs::create_dir_all(dest_dir.join(OBJECTS_DIR))?;
        std::fs::create_dir_all(dest_dir.join(THUMBS_DIR))?;
        std::fs::create_dir_all(dest_dir.join(DIRS_DIR))?;

        let mut saw_index = false;
        let expected_root_path = meta
            .root_dir_id
            .as_deref()
            .map(|rid| dir_file_path(&dest_dir, rid, meta.cipher));
        let mut saw_root_dir = false;
        let mut done_bytes = 0u64;

        for i in 0..archive.len() {
            check_cancelled(cancel)?;
            let entry = archive
                .by_index(i)
                .map_err(|e| VaultError::Backup(e.to_string()))?;
            if entry.is_dir() {
                continue;
            }
            let raw_name = entry
                .name()
                .map_err(|e| VaultError::Backup(e.to_string()))?
                .replace('\\', "/");
            if raw_name == VAULT_META_FILE {
                continue;
            }
            if raw_name == expected_index {
                if entry.size() > MAX_INDEX_BYTES {
                    return Err(VaultError::Backup("index exceeds max size".to_string()));
                }
                let out_path = dest_dir.join(expected_index);
                let mut out = create_private_file(&out_path)?;
                let mut limited = entry.take(MAX_INDEX_BYTES + 1);
                let copied = copy_with_progress(
                    &mut limited,
                    &mut out,
                    &mut done_bytes,
                    total_bytes,
                    cancel,
                    &mut on_progress,
                )?;
                if copied > MAX_INDEX_BYTES {
                    return Err(VaultError::Backup("index exceeds max size".to_string()));
                }
                saw_index = true;
                continue;
            }
            if let Some(rel) = raw_name.strip_prefix("dirs/") {
                if entry.size() > MAX_INDEX_BYTES {
                    return Err(VaultError::Backup("directory index exceeds max size".to_string()));
                }
                let out_path = safe_blob_dest(&dest_dir.join(DIRS_DIR), rel, &raw_name)?;
                if let Some(parent) = out_path.parent() {
                    crate::vfs::ensure_private_bucket_dir(parent)?;
                }
                let mut out = create_private_file(&out_path)?;
                let mut limited = entry.take(MAX_INDEX_BYTES + 1);
                let copied = copy_with_progress(
                    &mut limited,
                    &mut out,
                    &mut done_bytes,
                    total_bytes,
                    cancel,
                    &mut on_progress,
                )?;
                if copied > MAX_INDEX_BYTES {
                    return Err(VaultError::Backup("directory index exceeds max size".to_string()));
                }
                if expected_root_path.as_ref() == Some(&out_path) {
                    saw_root_dir = true;
                }
                continue;
            }

            if let Some(rel) = raw_name.strip_prefix("objects/") {
                let out_path = safe_blob_dest(&dest_dir.join(OBJECTS_DIR), rel, &raw_name)?;
                if let Some(parent) = out_path.parent() {
                    crate::vfs::ensure_private_bucket_dir(parent)?;
                }
                let mut out = create_private_file(&out_path)?;
                let mut reader = entry;
                copy_with_progress(
                    &mut reader,
                    &mut out,
                    &mut done_bytes,
                    total_bytes,
                    cancel,
                    &mut on_progress,
                )?;
                continue;
            }
            if let Some(rel) = raw_name.strip_prefix("thumbs/") {
                let out_path = safe_blob_dest(&dest_dir.join(THUMBS_DIR), rel, &raw_name)?;
                if let Some(parent) = out_path.parent() {
                    crate::vfs::ensure_private_bucket_dir(parent)?;
                }
                let mut out = create_private_file(&out_path)?;
                let mut reader = entry;
                copy_with_progress(
                    &mut reader,
                    &mut out,
                    &mut done_bytes,
                    total_bytes,
                    cancel,
                    &mut on_progress,
                )?;
                continue;
            }
        }

        check_cancelled(cancel)?;
        if let Some(ref root_id) = meta.root_dir_id {
            if !saw_root_dir {
                return Err(VaultError::Backup("missing root directory index in backup".to_string()));
            }
            let _ = VaultDirFile::load(&dest_dir, &meta.vault_id, root_id, meta.cipher, &dek)?;
        } else {
            if !saw_index {
                return Err(VaultError::Backup(format!("missing {expected_index} in backup")));
            }
            // Verify legacy index decrypts with `dek` and auto-migrate to sharded directory files.
            let _ = migrate_legacy_index_to_dirs(&dest_dir, &mut meta, &dek)?;
        }

        // Update local name & target auth mode.
        meta.backup_plain_name = None;
        meta.update_name_fields(&effective_name, &dek)?;
        let effective_local_pwd = if target_auth_mode == VaultAuthMode::Password {
            Some(
                new_local_password
                    .or(backup_password)
                    .ok_or_else(|| {
                        VaultError::Backup("password required for Password auth mode".to_string())
                    })?,
            )
        } else {
            None
        };
        meta.apply_auth_mode(target_auth_mode, effective_local_pwd, &dek)?;
        meta.save(&dest_dir)?;
        Ok(done_bytes)
    })();

    let final_done = match extract_res {
        Ok(done) => done,
        Err(e) => {
            let _ = std::fs::remove_dir_all(&dest_dir);
            return Err(e);
        }
    };

    let rec = make_registry_record(local_id.clone(), &effective_name, &dest_dir, &meta);
    if let Err(e) = store.add_record(rec) {
        let _ = std::fs::remove_dir_all(&dest_dir);
        return Err(e);
    }

    let system_dek_b64 = if target_auth_mode == VaultAuthMode::System && meta.cipher.is_encrypted() {
        Some(STANDARD.encode(&*dek))
    } else {
        None
    };

    if let Some(cb) = on_progress.as_deref_mut() {
        let final_total = total_bytes.max(final_done);
        cb(final_total, final_total);
    }

    Ok(ImportedVaultResult {
        local_id,
        crypto_vault_id: meta.vault_id,
        name: effective_name,
        dir_path: dest_dir,
        cipher: meta.cipher,
        auth_mode: target_auth_mode,
        system_dek_b64,
    })
}

fn create_private_file(path: &Path) -> VaultResult<std::fs::File> {
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    Ok(opts.open(path)?)
}
