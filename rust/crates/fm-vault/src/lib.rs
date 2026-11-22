pub mod backup;
pub mod crypto;
pub mod error;
pub mod index;
pub mod manager;
pub mod meta;
pub mod registry;
pub mod vfs;

pub use backup::{VaultBackupInfo, ImportedVaultResult};
pub use crypto::{validate_password, KdfParams, VaultAuthMode, VaultCipher};
pub use error::{VaultError, VaultResult};
pub use manager::{CreateVaultOutput, UnlockedVaultInfo, VaultLookupInfo, VaultManager};
pub use registry::{
    desktop_keystore_delete, desktop_keystore_read, desktop_keystore_save, VaultStore,
};
pub use vfs::{VaultFs, VaultGcResult, VaultStats};

#[cfg(test)]
mod tests {
    use super::*;
    use fm_core::{EntryKind, VfsPath, WriteMode};
    use fm_local::LocalFs;
    use fm_ops::{copy_recursive, ConflictPolicy, TaskProgress};
    use std::path::{Path, PathBuf};
    use std::sync::{Arc, Mutex};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio_util::sync::CancellationToken;

    fn test_manager(tmp: &Path) -> VaultManager {
        let m = VaultManager::new();
        m.init_store(tmp.join("app_data"));
        m
    }

    fn collect_files_recursive(dir: &Path) -> Vec<std::path::PathBuf> {
        let mut out = Vec::new();
        let Ok(entries) = std::fs::read_dir(dir) else {
            return out;
        };
        for ent in entries.flatten() {
            let path = ent.path();
            if path.is_dir() {
                out.extend(collect_files_recursive(&path));
            } else if path.is_file() {
                out.push(path);
            }
        }
        out
    }

    #[test]
    fn password_validation_accepts_special_symbols_and_bounds() {
        assert!(validate_password("1234567").is_err());
        assert!(validate_password("a!@#1234").is_ok());
        let p128: String = std::iter::repeat('A').take(126).collect::<String>() + "!@";
        assert_eq!(p128.chars().count(), 128);
        assert!(validate_password(&p128).is_ok());
        let p129 = format!("{p128}#");
        assert!(validate_password(&p129).is_err());
    }

    #[tokio::test]
    async fn stealth_lookup_and_wrong_password_cooldown() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join(".fpm");

        // Missing folder -> exists == false
        let missing = mgr.lookup_by_name("secret-none").unwrap();
        assert!(!missing.exists);

        mgr.create_vault(
            "diary",
            &storage,
            VaultCipher::Aes128Gcm,
            VaultAuthMode::Password,
            Some("Pass!word#1"),
        )
        .unwrap();

        // Check registry JSON never stores plaintext folder name.
        let reg_raw = std::fs::read_to_string(tmp.path().join("app_data/privacy_vaults.json")).unwrap();
        assert!(!reg_raw.contains("diary"));

        let locked = mgr.lock_all();
        assert_eq!(locked.len(), 1);
        assert!(mgr.list_unlocked().is_empty());

        let found = mgr.lookup_by_name("diary").unwrap();
        assert!(found.exists);
        assert_eq!(found.auth_mode, Some(VaultAuthMode::Password));
        assert_eq!(found.cipher, Some(VaultCipher::Aes128Gcm));

        // 5 wrong attempts trigger cooldown
        for i in 0..4 {
            let err = mgr.unlock_with_password("diary", "wrong123!").unwrap_err();
            assert!(matches!(err, VaultError::WrongCredential), "attempt {i}: {err}");
        }
        let err5 = mgr.unlock_with_password("diary", "wrong123!").unwrap_err();
        assert!(matches!(err5, VaultError::CooldownActive(_)), "expected cooldown, got {err5}");

        // Even valid password blocked while cooldown active
        let err_during = mgr.unlock_with_password("diary", "Pass!word#1").unwrap_err();
        assert!(matches!(err_during, VaultError::CooldownActive(_)));
    }

    #[tokio::test]
    async fn chunked_encryption_range_seek_and_ops_decrypt_across_ciphers() {
        for cipher in [VaultCipher::None, VaultCipher::Aes128Gcm, VaultCipher::Aes256Gcm] {
            let tmp = tempfile::tempdir().unwrap();
            let mgr = test_manager(tmp.path());
            let storage = tmp.path().join("storage");

            let created = mgr
                .create_vault(
                    &format!("vault-{:?}", cipher),
                    &storage,
                    cipher,
                    VaultAuthMode::Password,
                    Some("S3cr3t@Vault!"),
                )
                .unwrap();
            let vfs = mgr.get_vfs(&created.info.id).unwrap();

            vfs.mkdir(&VfsPath::from_slash_path("/photos")).await.unwrap();

            // 210 KiB payload (> 3 chunks of 64 KiB) to exercise multi-chunk boundaries.
            let mut payload = vec![0u8; 210 * 1024 + 17];
            for (i, b) in payload.iter_mut().enumerate() {
                *b = ((i * 31 + 7) & 0xFF) as u8;
            }
            let file_path = VfsPath::from_slash_path("/photos/big.bin");
            let mut writer = vfs.open_write(&file_path, WriteMode::Truncate).await.unwrap();
            writer.write_all(&payload).await.unwrap();
            writer.flush().await.unwrap();
            writer.shutdown().await.unwrap();

            // Verify exact boundary: chunk size 65536
            let mut exact_64k = vec![42u8; 65536];
            exact_64k[0] = 9;
            exact_64k[65535] = 99;
            let exact_path = VfsPath::from_slash_path("/exact64k.bin");
            let mut w2 = vfs.open_write(&exact_path, WriteMode::Create).await.unwrap();
            w2.write_all(&exact_64k).await.unwrap();
            w2.shutdown().await.unwrap();

            // Verify 0-byte empty file
            let empty_path = VfsPath::from_slash_path("/empty.txt");
            let mut w0 = vfs.open_write(&empty_path, WriteMode::Create).await.unwrap();
            w0.shutdown().await.unwrap();

            // Range read crossing chunk 0->1->2 boundary
            let range_offset = 65000u64;
            let range_len = 70000u64;
            let mut r = vfs
                .open_read_range(&file_path, range_offset, Some(range_len))
                .await
                .unwrap();
            let mut got_range = Vec::new();
            r.read_to_end(&mut got_range).await.unwrap();
            assert_eq!(
                got_range,
                payload[range_offset as usize..(range_offset + range_len) as usize]
            );

            // Check encrypted thumbnail round-trip
            mgr.save_thumbnail(&created.info.id, "/photos/big.bin", vec![1, 2, 3, 4, 5])
                .await
                .unwrap();
            let thumb = mgr
                .read_thumbnail(&created.info.id, "/photos/big.bin")
                .await
                .unwrap();
            assert_eq!(thumb.as_deref(), Some(&[1, 2, 3, 4, 5][..]));

            // Copy subfolder out to plain LocalFs -> must auto-decrypt
            let export_root = tmp.path().join("plain_export");
            std::fs::create_dir_all(&export_root).unwrap();
            let local_vfs = LocalFs::new(&export_root);
            let progress = Arc::new(Mutex::new(TaskProgress::pending()));
            let cancel = CancellationToken::new();
            copy_recursive(
                vfs.as_ref(),
                &VfsPath::from_slash_path("/photos"),
                &local_vfs,
                &VfsPath::from_slash_path("/photos"),
                &progress,
                &cancel,
                ConflictPolicy::Overwrite,
            )
            .await
            .unwrap();
            let exported_bytes = std::fs::read(export_root.join("photos/big.bin")).unwrap();
            assert_eq!(exported_bytes, payload);

            // Rename directory and re-stat exact/empty files after lock + re-unlock
            vfs.rename(
                &VfsPath::from_slash_path("/photos"),
                &VfsPath::from_slash_path("/pictures"),
            )
            .await
            .unwrap();
            assert_eq!(
                vfs.stat(&VfsPath::from_slash_path("/pictures/big.bin"))
                    .await
                    .unwrap()
                    .kind,
                EntryKind::File
            );
            assert!(vfs.list(&VfsPath::root()).await.unwrap().len() >= 3);

            assert!(mgr.lock(&created.info.id));
            assert!(mgr.get_vfs(&created.info.id).is_err());

            // Unlock again and verify exact64k and empty files survived cleanly
            let name = format!("vault-{:?}", cipher);
            let unlocked = mgr
                .unlock_with_password(&name, "S3cr3t@Vault!")
                .unwrap();
            let vfs2 = mgr.get_vfs(&unlocked.id).unwrap();
            let mut got64 = Vec::new();
            vfs2.open_read(&exact_path)
                .await
                .unwrap()
                .read_to_end(&mut got64)
                .await
                .unwrap();
            assert_eq!(got64, exact_64k);

            let mut got0 = Vec::new();
            vfs2.open_read(&empty_path)
                .await
                .unwrap()
                .read_to_end(&mut got0)
                .await
                .unwrap();
            assert!(got0.is_empty());

            // Verify raw disk file for encrypted ciphers is sharded and does NOT contain plaintext
            if cipher.is_encrypted() {
                let objs_dir = Path::new(&created.info.dir_path).join("objects");
                let enc_files = collect_files_recursive(&objs_dir);
                assert!(!enc_files.is_empty());
                for path in enc_files {
                    let rel = path.strip_prefix(&objs_dir).unwrap();
                    let comps: Vec<_> = rel.components().collect();
                    assert_eq!(comps.len(), 2, "expected 1-level shard path, got {rel:?}");
                    let shard = comps[0].as_os_str().to_str().unwrap();
                    let leaf = comps[1].as_os_str().to_str().unwrap();
                    assert_eq!(shard.len(), 2);
                    assert!(shard.bytes().all(|b| b.is_ascii_hexdigit()));
                    assert!(leaf.starts_with(shard));

                    let bytes = std::fs::read(&path).unwrap();
                    assert!(bytes.starts_with(b"FPV1"));
                    if bytes.len() > 65536 {
                        assert_ne!(&bytes[40..50], &payload[0..10]);
                    }
                }
            }
        }
    }

    #[tokio::test]
    async fn backup_and_import_for_password_and_system_vaults() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr1 = test_manager(&tmp.path().join("dev1"));
        let storage1 = tmp.path().join("dev1/vaults");

        // 1. System-unlocked encrypted vault
        let sys_out = mgr1
            .create_vault(
                "sys-vault",
                &storage1,
                VaultCipher::Aes256Gcm,
                VaultAuthMode::System,
                None,
            )
            .unwrap();
        let sys_dek_b64 = sys_out.system_dek_b64.clone().unwrap();
        let vfs = mgr1.get_vfs(&sys_out.info.id).unwrap();
        let mut w = vfs
            .open_write(&VfsPath::from_slash_path("/note.txt"), WriteMode::Create)
            .await
            .unwrap();
        w.write_all(b"top secret note 123456").await.unwrap();
        w.shutdown().await.unwrap();

        // System vault requires backup password on export
        let archive = tmp.path().join("sys_backup.fpmvault");
        assert!(mgr1.export_backup(&sys_out.info.id, None, &archive).is_err());
        mgr1.export_backup(&sys_out.info.id, Some("BackupPwd!99"), &archive)
            .unwrap();

        let info = mgr1.inspect_backup(&archive).unwrap();
        assert_eq!(info.cipher, VaultCipher::Aes256Gcm);
        assert_eq!(info.original_auth_mode, VaultAuthMode::System);
        assert!(info.requires_password);
        assert_eq!(info.object_count, 1);

        // Lock and unlock on dev1 with system key
        mgr1.lock(&sys_out.info.id);
        assert!(mgr1.unlock_with_system_key("sys-vault", Some("invalid")).is_err());
        let reunlocked = mgr1
            .unlock_with_system_key("sys-vault", Some(&sys_dek_b64))
            .unwrap();
        assert_eq!(reunlocked.name, "sys-vault");

        // Import onto a second clean store ("dev2") converting to password mode
        let mgr2 = test_manager(&tmp.path().join("dev2"));
        let storage2 = tmp.path().join("dev2/vaults");
        assert!(mgr2
            .import_backup(
                &archive,
                Some("imported-vault"),
                &storage2,
                Some("WrongPwd!1"),
                VaultAuthMode::Password,
                Some("NewLocalPwd!1"),
            )
            .is_err());

        let imported = mgr2
            .import_backup(
                &archive,
                Some("imported-vault"),
                &storage2,
                Some("BackupPwd!99"),
                VaultAuthMode::Password,
                Some("NewLocalPwd!1"),
            )
            .unwrap();
        let vfs2 = mgr2.get_vfs(&imported.local_id).unwrap();
        let mut read_back = Vec::new();
        vfs2.open_read(&VfsPath::from_slash_path("/note.txt"))
            .await
            .unwrap()
            .read_to_end(&mut read_back)
            .await
            .unwrap();
        assert_eq!(read_back, b"top secret note 123456");

        // Re-unlock imported vault on dev2 using NewLocalPwd!1
        mgr2.lock(&imported.local_id);
        let u2 = mgr2
            .unlock_with_password("imported-vault", "NewLocalPwd!1")
            .unwrap();
        assert_eq!(u2.id, imported.local_id);
    }

    #[tokio::test]
    async fn import_preserves_original_name_prompts_on_conflict_and_rename_works() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr1 = test_manager(&tmp.path().join("dev1"));
        let storage1 = tmp.path().join("dev1/vaults");

        // 1. Encrypted vault with Chinese/Unicode name
        let created = mgr1
            .create_vault(
                "绝密相册",
                &storage1,
                VaultCipher::Aes256Gcm,
                VaultAuthMode::Password,
                Some("OrigPwd!123"),
            )
            .unwrap();
        let vfs = mgr1.get_vfs(&created.info.id).unwrap();
        let mut w = vfs
            .open_write(&VfsPath::from_slash_path("/secret.txt"), WriteMode::Create)
            .await
            .unwrap();
        w.write_all(b"unicode-vault-payload").await.unwrap();
        w.shutdown().await.unwrap();

        let enc_archive = tmp.path().join("album.fpmvault");
        mgr1.export_backup(&created.info.id, None, &enc_archive).unwrap();

        // Import onto clean dev2 without specifying name -> keeps exact original name
        let mgr2 = test_manager(&tmp.path().join("dev2"));
        let storage2 = tmp.path().join("dev2/vaults");
        let imported = mgr2
            .import_backup(
                &enc_archive,
                None,
                &storage2,
                Some("OrigPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();
        assert_eq!(imported.name, "绝密相册");

        // Re-importing same backup onto dev2 without a manual name -> AlreadyExists("绝密相册")
        let conflict = mgr2
            .import_backup(
                &enc_archive,
                None,
                &storage2,
                Some("OrigPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap_err();
        match conflict {
            VaultError::AlreadyExists(n) => assert_eq!(n, "绝密相册"),
            other => panic!("expected AlreadyExists(\"绝密相册\"), got {other:?}"),
        }

        // Retrying with a manual new name succeeds while keeping existing vault intact
        let renamed_import = mgr2
            .import_backup(
                &enc_archive,
                Some("绝密相册-副本"),
                &storage2,
                Some("OrigPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();
        assert_eq!(renamed_import.name, "绝密相册-副本");
        assert!(mgr2.lookup_by_name("绝密相册").unwrap().exists);
        assert!(mgr2.lookup_by_name("绝密相册-副本").unwrap().exists);

        // 2. Unencrypted vault backup preserves original_name on inspect and clears backup_plain_name locally
        let plain_vault = mgr1
            .create_vault(
                "明文备忘",
                &storage1,
                VaultCipher::None,
                VaultAuthMode::Password,
                Some("PlainPwd!123"),
            )
            .unwrap();
        let plain_archive = tmp.path().join("plain.fpmvault");
        mgr1.export_backup(&plain_vault.info.id, None, &plain_archive)
            .unwrap();
        let plain_info = mgr2.inspect_backup(&plain_archive).unwrap();
        assert_eq!(plain_info.original_name.as_deref(), Some("明文备忘"));

        let imported_plain = mgr2
            .import_backup(
                &plain_archive,
                None,
                &storage2,
                Some("PlainPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();
        assert_eq!(imported_plain.name, "明文备忘");
        let meta_raw = std::fs::read_to_string(imported_plain.dir_path.join("vault.meta.json")).unwrap();
        assert!(!meta_raw.contains("backup_plain_name"));
        assert!(!meta_raw.contains("明文备忘"));

        // 3. Rename existing vault: collision blocked, no-op allowed, rename updates lookup/unlock/subsequent backup
        let err_dup = mgr2
            .rename_vault(&imported.local_id, "绝密相册-副本")
            .unwrap_err();
        assert!(matches!(err_dup, VaultError::AlreadyExists(_)));

        let noop = mgr2.rename_vault(&imported.local_id, "绝密相册").unwrap();
        assert_eq!(noop.name, "绝密相册");

        let renamed = mgr2.rename_vault(&imported.local_id, "家庭资料").unwrap();
        assert_eq!(renamed.name, "家庭资料");

        mgr2.lock(&imported.local_id);
        assert!(!mgr2.lookup_by_name("绝密相册").unwrap().exists);
        assert!(mgr2.lookup_by_name("家庭资料").unwrap().exists);

        let reunlocked = mgr2
            .unlock_with_password("家庭资料", "OrigPwd!123")
            .unwrap();
        assert_eq!(reunlocked.name, "家庭资料");
        let vfs_re = mgr2.get_vfs(&reunlocked.id).unwrap();
        let mut read_back = Vec::new();
        vfs_re
            .open_read(&VfsPath::from_slash_path("/secret.txt"))
            .await
            .unwrap()
            .read_to_end(&mut read_back)
            .await
            .unwrap();
        assert_eq!(read_back, b"unicode-vault-payload");

        let after_rename_archive = tmp.path().join("renamed.fpmvault");
        mgr2.export_backup(&reunlocked.id, None, &after_rename_archive)
            .unwrap();
        let mgr3 = test_manager(&tmp.path().join("dev3"));
        let imported_after_rename = mgr3
            .import_backup(
                &after_rename_archive,
                None,
                &tmp.path().join("dev3/vaults"),
                Some("OrigPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();
        assert_eq!(imported_after_rename.name, "家庭资料");
    }

    #[tokio::test]
    async fn tamper_detection_fails_instead_of_truncating() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("storage");
        let created = mgr
            .create_vault(
                "tamper-check",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("ValidPwd!123"),
            )
            .unwrap();
        let vfs = mgr.get_vfs(&created.info.id).unwrap();
        let fp = VfsPath::from_slash_path("/data.bin");
        let mut w = vfs.open_write(&fp, WriteMode::Create).await.unwrap();
        w.write_all(&vec![7u8; 80_000]).await.unwrap();
        w.shutdown().await.unwrap();

        let objs_dir = Path::new(&created.info.dir_path).join("objects");
        let enc_file = collect_files_recursive(&objs_dir).into_iter().next().unwrap();
        let mut raw = std::fs::read(&enc_file).unwrap();
        let last = raw.len() - 1;
        raw[last] ^= 0xFF;
        std::fs::write(&enc_file, &raw).unwrap();

        let mut reader = vfs.open_read(&fp).await.unwrap();
        let mut out = Vec::new();
        assert!(reader.read_to_end(&mut out).await.is_err());
    }

    #[tokio::test]
    async fn sharded_objects_and_legacy_flat_fallback() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr1 = test_manager(&tmp.path().join("dev1"));
        let storage1 = tmp.path().join("dev1/vaults");
        let created = mgr1
            .create_vault(
                "sharded-check",
                &storage1,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("ShardPwd!123"),
            )
            .unwrap();
        let vfs = mgr1.get_vfs(&created.info.id).unwrap();

        let p_a = VfsPath::from_slash_path("/a.txt");
        let mut wa = vfs.open_write(&p_a, WriteMode::Create).await.unwrap();
        wa.write_all(b"alpha-content").await.unwrap();
        wa.shutdown().await.unwrap();

        vfs.mkdir(&VfsPath::from_slash_path("/sub")).await.unwrap();
        let p_b = VfsPath::from_slash_path("/sub/b.bin");
        let payload_b: Vec<u8> = (0..(90 * 1024)).map(|i| (i % 251) as u8).collect();
        let mut wb = vfs.open_write(&p_b, WriteMode::Create).await.unwrap();
        wb.write_all(&payload_b).await.unwrap();
        wb.shutdown().await.unwrap();

        mgr1.save_thumbnail(&created.info.id, "/a.txt", vec![9, 8, 7, 6])
            .await
            .unwrap();

        let vault_dir = Path::new(&created.info.dir_path);
        let objs_dir = vault_dir.join("objects");
        let thumbs_dir = vault_dir.join("thumbs");
        let obj_files = collect_files_recursive(&objs_dir);
        let thumb_files = collect_files_recursive(&thumbs_dir);
        assert_eq!(obj_files.len(), 2);
        assert_eq!(thumb_files.len(), 1);
        for f in obj_files.iter().chain(thumb_files.iter()) {
            let root = if f.starts_with(&objs_dir) { &objs_dir } else { &thumbs_dir };
            assert_eq!(f.strip_prefix(root).unwrap().components().count(), 2);
        }

        // Move one object and the thumbnail to legacy flat paths to simulate an old vault on disk.
        let mut legacy_obj_a = None;
        for f in &obj_files {
            if f.parent().unwrap() != objs_dir {
                let flat = objs_dir.join(f.file_name().unwrap());
                std::fs::rename(f, &flat).unwrap();
                legacy_obj_a = Some(flat);
                break;
            }
        }
        assert!(legacy_obj_a.unwrap().exists());

        let old_thumb = &thumb_files[0];
        let flat_thumb = thumbs_dir.join(old_thumb.file_name().unwrap());
        std::fs::rename(old_thumb, &flat_thumb).unwrap();

        // Thumbnail read still succeeds via legacy fallback.
        assert_eq!(
            mgr1.read_thumbnail(&created.info.id, "/a.txt")
                .await
                .unwrap()
                .as_deref(),
            Some(&[9, 8, 7, 6][..])
        );

        // Move remaining object flat too and verify range-read + append fallback cleanly.
        for f in collect_files_recursive(&objs_dir) {
            if f.parent().unwrap() != objs_dir {
                let flat = objs_dir.join(f.file_name().unwrap());
                std::fs::rename(&f, &flat).unwrap();
            }
        }
        let mut range_out = Vec::new();
        vfs.open_read_range(&p_b, 65000, Some(2000))
            .await
            .unwrap()
            .read_to_end(&mut range_out)
            .await
            .unwrap();
        assert_eq!(range_out, payload_b[65000..67000]);

        let mut wa_append = vfs.open_write(&p_a, WriteMode::Append).await.unwrap();
        wa_append.write_all(b"+appended").await.unwrap();
        wa_append.shutdown().await.unwrap();
        // Overwriting/appending clears previous thumbnail (including legacy flat thumb path).
        assert!(!flat_thumb.exists());

        let mut got_a = Vec::new();
        vfs.open_read(&p_a)
            .await
            .unwrap()
            .read_to_end(&mut got_a)
            .await
            .unwrap();
        assert_eq!(got_a, b"alpha-content+appended");

        // Save a fresh thumbnail and flatten it to test backup/import upgrading legacy flat thumbs.
        mgr1.save_thumbnail(&created.info.id, "/a.txt", vec![5, 4, 3, 2])
            .await
            .unwrap();
        let new_thumb = collect_files_recursive(&thumbs_dir).into_iter().next().unwrap();
        let flat_thumb2 = thumbs_dir.join(new_thumb.file_name().unwrap());
        std::fs::rename(&new_thumb, &flat_thumb2).unwrap();

        // Export mixed/legacy backup -> import on fresh store upgrades everything to sharded buckets.
        let archive = tmp.path().join("mixed.fpmvault");
        mgr1.export_backup(&created.info.id, None, &archive).unwrap();
        let info = mgr1.inspect_backup(&archive).unwrap();
        assert_eq!(info.object_count, 2);

        let mgr2 = test_manager(&tmp.path().join("dev2"));
        let imported = mgr2
            .import_backup(
                &archive,
                None,
                &tmp.path().join("dev2/vaults"),
                Some("ShardPwd!123"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();

        let imp_objs = imported.dir_path.join("objects");
        let imp_thumbs = imported.dir_path.join("thumbs");
        let imp_obj_files = collect_files_recursive(&imp_objs);
        let imp_thumb_files = collect_files_recursive(&imp_thumbs);
        assert_eq!(imp_obj_files.len(), 2);
        assert_eq!(imp_thumb_files.len(), 1);
        for f in imp_obj_files.iter().chain(imp_thumb_files.iter()) {
            let root = if f.starts_with(&imp_objs) { &imp_objs } else { &imp_thumbs };
            assert_eq!(f.strip_prefix(root).unwrap().components().count(), 2);
        }

        let vfs2 = mgr2.get_vfs(&imported.local_id).unwrap();
        let mut got_b = Vec::new();
        vfs2.open_read(&p_b)
            .await
            .unwrap()
            .read_to_end(&mut got_b)
            .await
            .unwrap();
        assert_eq!(got_b, payload_b);
        assert_eq!(
            mgr2.read_thumbnail(&imported.local_id, "/a.txt")
                .await
                .unwrap()
                .as_deref(),
            Some(&[5, 4, 3, 2][..])
        );

        // Deleting removes both object and thumbnail blobs cleanly.
        vfs2.remove(&p_a).await.unwrap();
        assert_eq!(collect_files_recursive(&imp_objs).len(), 1);
        assert_eq!(collect_files_recursive(&imp_thumbs).len(), 0);
    }

    #[tokio::test]
    async fn per_dir_sharded_index_lru_and_o1_dir_rename() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "million-ready",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("DirShard!123"),
            )
            .unwrap();
        let vault_dir = std::path::PathBuf::from(&created.info.dir_path);
        assert!(!vault_dir.join("index.enc").exists());
        assert_eq!(collect_files_recursive(&vault_dir.join("dirs")).len(), 1);

        let vfs = mgr.get_vfs(&created.info.id).unwrap();

        // Exceed DIR_CACHE_CAPACITY (256) with 270 directories.
        for i in 0..270u32 {
            let p = VfsPath::from_slash_path(&format!("/d{i:03}"));
            vfs.mkdir(&p).await.unwrap();
        }
        assert_eq!(collect_files_recursive(&vault_dir.join("dirs")).len(), 271);

        // Multi-chunk file (> 130 KiB) + thumbnail in d000, plus a file in d269.
        let p0 = VfsPath::from_slash_path("/d000/big.bin");
        let mut init_data: Vec<u8> = (0..(130 * 1024 + 19)).map(|i| (i % 199) as u8).collect();
        let mut w0 = vfs.open_write(&p0, WriteMode::Create).await.unwrap();
        w0.write_all(&init_data).await.unwrap();
        w0.shutdown().await.unwrap();
        mgr.save_thumbnail(&created.info.id, "/d000/big.bin", vec![11, 22, 33])
            .await
            .unwrap();

        // Streaming WriteMode::Append crossing chunk boundaries.
        let extra: Vec<u8> = (0..70_000).map(|i| ((i * 7) % 251) as u8).collect();
        let mut wa = vfs.open_write(&p0, WriteMode::Append).await.unwrap();
        wa.write_all(&extra).await.unwrap();
        wa.shutdown().await.unwrap();
        init_data.extend_from_slice(&extra);
        // Append replaces file entry (thumbnail cleared); re-save thumb for rename/delete test.
        mgr.save_thumbnail(&created.info.id, "/d000/big.bin", vec![44, 55, 66])
            .await
            .unwrap();

        let p269 = VfsPath::from_slash_path("/d269/leaf.txt");
        let mut w269 = vfs.open_write(&p269, WriteMode::Create).await.unwrap();
        w269.write_all(b"leaf-269").await.unwrap();
        w269.shutdown().await.unwrap();

        // O(1) directory rename across evicted cache boundary: /d000 -> /d269/moved
        vfs.rename(
            &VfsPath::from_slash_path("/d000"),
            &VfsPath::from_slash_path("/d269/moved"),
        )
        .await
        .unwrap();

        // Moving directory into its own descendant must be rejected.
        assert!(vfs
            .rename(
                &VfsPath::from_slash_path("/d269"),
                &VfsPath::from_slash_path("/d269/moved/sub"),
            )
            .await
            .is_err());

        let moved_file = VfsPath::from_slash_path("/d269/moved/big.bin");
        let mut got = Vec::new();
        vfs.open_read(&moved_file)
            .await
            .unwrap()
            .read_to_end(&mut got)
            .await
            .unwrap();
        assert_eq!(got, init_data);
        assert_eq!(
            mgr.read_thumbnail(&created.info.id, "/d269/moved/big.bin")
                .await
                .unwrap()
                .as_deref(),
            Some(&[44, 55, 66][..])
        );
        assert_eq!(vfs.list(&VfsPath::from_slash_path("/d001")).await.unwrap().len(), 0);

        // Recursive remove deletes subtree objects, thumbs, and dirs files cleanly.
        vfs.remove(&VfsPath::from_slash_path("/d269")).await.unwrap();
        assert!(collect_files_recursive(&vault_dir.join("objects")).is_empty());
        assert!(collect_files_recursive(&vault_dir.join("thumbs")).is_empty());
        assert_eq!(collect_files_recursive(&vault_dir.join("dirs")).len(), 269);
    }

    #[tokio::test]
    async fn legacy_v1_index_and_backup_auto_migrate_to_dirs() {
        use crate::index::VaultIndex;
        use crate::meta::VaultMeta;
        use crate::registry::make_registry_record;
        use zip::write::SimpleFileOptions;
        use zip::{CompressionMethod, ZipWriter};

        let tmp = tempfile::tempdir().unwrap();
        let store1 = VaultStore::new(tmp.path().join("app1"));
        let vault_id = "legacyvault1234".to_string();
        let v1_dir = tmp.path().join("v1_vaults").join(&vault_id);
        std::fs::create_dir_all(v1_dir.join("objects")).unwrap();
        std::fs::create_dir_all(v1_dir.join("thumbs")).unwrap();

        let (mut meta, dek) = VaultMeta::new_vault(
            vault_id.clone(),
            "legacy-box",
            VaultCipher::Aes256Gcm,
            VaultAuthMode::Password,
            Some("LegacyPwd!1"),
        )
        .unwrap();
        meta.root_dir_id = None;
        meta.save(&v1_dir).unwrap();

        // Create legacy object & thumb + V1 VaultIndex.
        let obj_id = "ab12cd34ef56".to_string();
        let flat_obj = v1_dir.join("objects").join(format!("{obj_id}.enc"));
        let mut w = crate::crypto::Fpv1SyncWriter::create(&flat_obj, &vault_id, &dek, VaultCipher::Aes256Gcm)
            .unwrap();
        w.write_chunk(b"legacy-v1-secret-payload", true).unwrap();
        w.finalize().unwrap();

        let mut legacy_idx = VaultIndex::default();
        legacy_idx.mkdir(&VfsPath::from_slash_path("/nested")).unwrap();
        legacy_idx
            .upsert_file(&VfsPath::from_slash_path("/nested/doc.txt"), obj_id.clone(), 24)
            .unwrap();
        legacy_idx.save(&v1_dir, &vault_id, VaultCipher::Aes256Gcm, &dek).unwrap();

        let rec = make_registry_record(vault_id.clone(), "legacy-box", &v1_dir, &meta);
        store1.add_record(rec).unwrap();

        // Build a synthetic v1 .fpmvault archive before unlocking/migrating v1_dir.
        let v1_backup = tmp.path().join("legacy_v1.fpmvault");
        {
            let f = std::fs::File::create(&v1_backup).unwrap();
            let mut zip = ZipWriter::new(f);
            zip.start_file("vault.meta.json", SimpleFileOptions::default())
                .unwrap();
            std::io::Write::write_all(&mut zip, &std::fs::read(v1_dir.join("vault.meta.json")).unwrap())
                .unwrap();
            zip.start_file(
                "index.enc",
                SimpleFileOptions::default().compression_method(CompressionMethod::Stored),
            )
            .unwrap();
            std::io::Write::write_all(&mut zip, &std::fs::read(v1_dir.join("index.enc")).unwrap())
                .unwrap();
            zip.start_file(
                format!("objects/{obj_id}.enc"),
                SimpleFileOptions::default().compression_method(CompressionMethod::Stored),
            )
            .unwrap();
            std::io::Write::write_all(&mut zip, &std::fs::read(&flat_obj).unwrap())
                .unwrap();
            zip.finish().unwrap();
        }

        // 1. Unlocking legacy v1 vault auto-migrates index.enc -> dirs/
        let mgr1 = test_manager(tmp.path());
        mgr1.init_store(tmp.path().join("app1"));
        let unlocked = mgr1.unlock_with_password("legacy-box", "LegacyPwd!1").unwrap();
        assert!(!v1_dir.join("index.enc").exists());
        assert_eq!(collect_files_recursive(&v1_dir.join("dirs")).len(), 2);
        let migrated_meta = VaultMeta::load(&v1_dir).unwrap();
        assert!(migrated_meta.root_dir_id.is_some());

        let vfs1 = mgr1.get_vfs(&unlocked.id).unwrap();
        let mut got1 = Vec::new();
        vfs1.open_read(&VfsPath::from_slash_path("/nested/doc.txt"))
            .await
            .unwrap()
            .read_to_end(&mut got1)
            .await
            .unwrap();
        assert_eq!(got1, b"legacy-v1-secret-payload");

        // 2. Importing legacy v1 .fpmvault backup on fresh store also auto-migrates to dirs/ + sharded objects/
        let mgr2 = test_manager(&tmp.path().join("dev2"));
        let imported = mgr2
            .import_backup(
                &v1_backup,
                None,
                &tmp.path().join("dev2/vaults"),
                Some("LegacyPwd!1"),
                VaultAuthMode::Password,
                None,
            )
            .unwrap();
        assert_eq!(imported.name, "legacy-box");
        assert!(!imported.dir_path.join("index.enc").exists());
        assert_eq!(collect_files_recursive(&imported.dir_path.join("dirs")).len(), 2);
        let imp_objs = collect_files_recursive(&imported.dir_path.join("objects"));
        assert_eq!(imp_objs.len(), 1);
        assert_eq!(
            imp_objs[0].strip_prefix(imported.dir_path.join("objects")).unwrap().components().count(),
            2
        );

        let vfs2 = mgr2.get_vfs(&imported.local_id).unwrap();
        let mut got2 = Vec::new();
        vfs2.open_read(&VfsPath::from_slash_path("/nested/doc.txt"))
            .await
            .unwrap()
            .read_to_end(&mut got2)
            .await
            .unwrap();
        assert_eq!(got2, b"legacy-v1-secret-payload");
    }

    #[tokio::test]
    async fn ios_sandbox_container_relocation_recovers_vaults() {
        let tmp = tempfile::tempdir().unwrap();
        let containers_base = tmp.path().join("Containers/Data/Application");
        let old_container = containers_base.join("OLD-UUID-1111");
        let old_app_support = old_container.join("Library/Application Support");
        let old_default_storage = old_app_support.join("private_vaults");
        let old_custom_storage = old_container.join("Documents/CustomVaults");

        let mgr1 = VaultManager::new();
        mgr1.init_store(&old_app_support);

        let pwd_out = mgr1
            .create_vault(
                "face-and-pwd",
                &old_default_storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("VaultPass!1"),
            )
            .unwrap();
        let mut f1 = mgr1
            .get_vfs(&pwd_out.info.id)
            .unwrap()
            .open_write(
                &VfsPath::from_slash_path("/note.txt"),
                WriteMode::Create,
            )
            .await
            .unwrap();
        f1.write_all(b"ios-default-vault-data").await.unwrap();
        f1.shutdown().await.unwrap();

        let sys_out = mgr1
            .create_vault(
                "custom-face-box",
                &old_custom_storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::System,
                None,
            )
            .unwrap();
        let mut f2 = mgr1
            .get_vfs(&sys_out.info.id)
            .unwrap()
            .open_write(
                &VfsPath::from_slash_path("/secret.bin"),
                WriteMode::Create,
            )
            .await
            .unwrap();
        f2.write_all(b"ios-custom-vault-data").await.unwrap();
        f2.shutdown().await.unwrap();
        mgr1.lock_all();

        // Simulate iOS rotating the Data Container UUID across reinstall.
        let new_container = containers_base.join("NEW-UUID-2222");
        std::fs::rename(&old_container, &new_container).unwrap();
        let new_app_support = new_container.join("Library/Application Support");

        let mgr2 = VaultManager::new();
        mgr2.init_store(&new_app_support);

        let l1 = mgr2.lookup_by_name("face-and-pwd").unwrap();
        assert!(l1.exists);
        let l2 = mgr2.lookup_by_name("custom-face-box").unwrap();
        assert!(l2.exists);

        let u1 = mgr2.unlock_with_password("face-and-pwd", "VaultPass!1").unwrap();
        let mut got1 = Vec::new();
        mgr2.get_vfs(&u1.id)
            .unwrap()
            .open_read(&VfsPath::from_slash_path("/note.txt"))
            .await
            .unwrap()
            .read_to_end(&mut got1)
            .await
            .unwrap();
        assert_eq!(got1, b"ios-default-vault-data");

        let u2 = mgr2
            .unlock_with_system_key("custom-face-box", sys_out.system_dek_b64.as_deref())
            .unwrap();
        let mut got2 = Vec::new();
        mgr2.get_vfs(&u2.id)
            .unwrap()
            .open_read(&VfsPath::from_slash_path("/secret.bin"))
            .await
            .unwrap()
            .read_to_end(&mut got2)
            .await
            .unwrap();
        assert_eq!(got2, b"ios-custom-vault-data");

        // Verify persisted privacy_vaults.json now references NEW-UUID-2222.
        let registry_raw =
            std::fs::read_to_string(new_app_support.join("privacy_vaults.json")).unwrap();
        assert!(!registry_raw.contains("OLD-UUID-1111"));
        assert!(registry_raw.contains("NEW-UUID-2222"));
    }

    #[test]
    fn kdf_params_match_argon2_default_and_legacy_meta_unlocks() {
        let salt = b"0123456789abcdef";
        let mut expected = [0u8; 32];
        argon2::Argon2::default()
            .hash_password_into(b"Legacy!Pass123", salt, &mut expected)
            .unwrap();
        let actual = crate::crypto::derive_kek_argon2id_with_params(
            "Legacy!Pass123",
            salt,
            KdfParams::default(),
        )
        .unwrap();
        assert_eq!(&*actual, &expected);

        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "compat-vault",
                &storage,
                VaultCipher::Aes256Gcm,
                VaultAuthMode::Password,
                Some("Legacy!Pass123"),
            )
            .unwrap();

        let vault_dir = PathBuf::from(&created.info.dir_path);
        let meta = crate::meta::VaultMeta::load(&vault_dir).unwrap();
        assert_eq!(meta.kdf_params, Some(KdfParams::default()));

        // Strip `kdf_params` from vault.meta.json to simulate a pre-existing vault.
        let meta_path = vault_dir.join(crate::meta::VAULT_META_FILE);
        let mut raw_val: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&meta_path).unwrap()).unwrap();
        raw_val.as_object_mut().unwrap().remove("kdf_params");
        std::fs::write(&meta_path, serde_json::to_vec_pretty(&raw_val).unwrap()).unwrap();

        mgr.lock(&created.info.id);
        let unlocked = mgr
            .unlock_with_password("compat-vault", "Legacy!Pass123")
            .unwrap();
        assert_eq!(unlocked.id, created.info.id);
    }

    #[tokio::test]
    async fn change_password_and_switch_auth_modes_preserve_data() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "switch-box",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("Pass#One1"),
            )
            .unwrap();

        let mut f = mgr
            .get_vfs(&created.info.id)
            .unwrap()
            .open_write(&VfsPath::from_slash_path("/doc.txt"), WriteMode::Create)
            .await
            .unwrap();
        f.write_all(b"stable-encrypted-payload").await.unwrap();
        f.shutdown().await.unwrap();

        let err = mgr
            .change_password(&created.info.id, Some("Wrong#Pass"), "Pass#Two2")
            .unwrap_err();
        assert!(matches!(err, VaultError::WrongCredential));

        let updated = mgr
            .change_password(&created.info.id, Some("Pass#One1"), "Pass#Two2")
            .unwrap();
        assert_eq!(updated.auth_mode, VaultAuthMode::Password);
        mgr.lock(&created.info.id);

        assert!(matches!(
            mgr.unlock_with_password("switch-box", "Pass#One1").unwrap_err(),
            VaultError::WrongCredential
        ));
        mgr.unlock_with_password("switch-box", "Pass#Two2").unwrap();

        assert!(matches!(
            mgr.prepare_switch_to_system(&created.info.id, "Pass#One1")
                .unwrap_err(),
            VaultError::WrongCredential
        ));
        let sys_dek = mgr
            .prepare_switch_to_system(&created.info.id, "Pass#Two2")
            .unwrap()
            .expect("encrypted vault returns system dek");
        let sys_info = mgr.commit_switch_to_system(&created.info.id).unwrap();
        assert_eq!(sys_info.auth_mode, VaultAuthMode::System);
        mgr.lock(&created.info.id);

        mgr.unlock_with_system_key("switch-box", Some(&sys_dek))
            .unwrap();
        let back_info = mgr
            .change_password(&created.info.id, None, "Pass#Three3")
            .unwrap();
        assert_eq!(back_info.auth_mode, VaultAuthMode::Password);
        mgr.lock(&created.info.id);

        mgr.unlock_with_password("switch-box", "Pass#Three3").unwrap();
        let mut got = Vec::new();
        mgr.get_vfs(&created.info.id)
            .unwrap()
            .open_read(&VfsPath::from_slash_path("/doc.txt"))
            .await
            .unwrap()
            .read_to_end(&mut got)
            .await
            .unwrap();
        assert_eq!(got, b"stable-encrypted-payload");
    }

    #[tokio::test]
    async fn write_mode_create_enforces_atomicity_at_commit() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "create-race",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("Race!Pass1"),
            )
            .unwrap();
        let vfs = mgr.get_vfs(&created.info.id).unwrap();
        let target = VfsPath::from_slash_path("/race.txt");

        let mut w1 = vfs.open_write(&target, WriteMode::Create).await.unwrap();
        let mut w2 = vfs.open_write(&target, WriteMode::Create).await.unwrap();

        w1.write_all(b"winner-content").await.unwrap();
        w2.write_all(b"loser-content").await.unwrap();

        w1.shutdown().await.unwrap();
        let err = w2.shutdown().await.unwrap_err();
        assert_eq!(err.kind(), std::io::ErrorKind::AlreadyExists);

        let mut got = Vec::new();
        vfs.open_read(&target)
            .await
            .unwrap()
            .read_to_end(&mut got)
            .await
            .unwrap();
        assert_eq!(got, b"winner-content");

        // Only 1 object blob should remain on disk for the winning file.
        let obj_files = collect_files_recursive(&PathBuf::from(&created.info.dir_path).join("objects"));
        assert_eq!(obj_files.len(), 1);
    }

    #[tokio::test]
    async fn backup_progress_and_cancellation_cleanup() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "prog-vault",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("Back!Pass1"),
            )
            .unwrap();
        let vfs = mgr.get_vfs(&created.info.id).unwrap();
        let payload = vec![0x42u8; 2 * 1024 * 1024 + 512];
        let mut w = vfs
            .open_write(&VfsPath::from_slash_path("/big.bin"), WriteMode::Create)
            .await
            .unwrap();
        w.write_all(&payload).await.unwrap();
        w.shutdown().await.unwrap();

        let backup_path = tmp.path().join("out/prog.fpmvault");
        let mut updates: Vec<(u64, u64)> = Vec::new();
        let mut cb = |done: u64, total: u64| {
            updates.push((done, total));
        };
        mgr.export_backup_with_progress(
            &created.info.id,
            None,
            &backup_path,
            None,
            Some(&mut cb),
        )
        .unwrap();
        assert!(backup_path.exists());
        assert!(!updates.is_empty());
        let last = *updates.last().unwrap();
        assert!(last.1 > 0);
        assert_eq!(last.0, last.1);

        // Cancelled export cleans up its temp archive and leaves no file behind.
        let cancelled_path = tmp.path().join("out/cancelled.fpmvault");
        let cancel_flag = std::sync::atomic::AtomicBool::new(false);
        let mut cancel_cb = |done: u64, _total: u64| {
            if done > 0 {
                cancel_flag.store(true, std::sync::atomic::Ordering::Release);
            }
        };
        let err = mgr
            .export_backup_with_progress(
                &created.info.id,
                None,
                &cancelled_path,
                Some(&cancel_flag),
                Some(&mut cancel_cb),
            )
            .unwrap_err();
        assert!(matches!(err, VaultError::Cancelled));
        assert!(!cancelled_path.exists());
        let leftovers: Vec<_> = std::fs::read_dir(tmp.path().join("out"))
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().contains("fpmtmp-"))
            .collect();
        assert!(leftovers.is_empty());

        // Cancelled import cleans up destination directory cleanly.
        let cancel_import = std::sync::atomic::AtomicBool::new(true);
        let import_dest = tmp.path().join("import_storage");
        let err_imp = mgr
            .import_backup_with_progress(
                &backup_path,
                Some("imported-cancelled"),
                &import_dest,
                Some("Back!Pass1"),
                VaultAuthMode::Password,
                Some("Back!Pass2"),
                Some(&cancel_import),
                None,
            )
            .unwrap_err();
        assert!(matches!(err_imp, VaultError::Cancelled));
        assert!(mgr.lookup_by_name("imported-cancelled").unwrap().exists == false);
    }

    #[tokio::test]
    async fn stats_gc_and_stale_tmp_sweep() {
        let tmp = tempfile::tempdir().unwrap();
        let mgr = test_manager(tmp.path());
        let storage = tmp.path().join("vaults");
        let created = mgr
            .create_vault(
                "stats-vault",
                &storage,
                VaultCipher::Aes128Gcm,
                VaultAuthMode::Password,
                Some("Stat!Pass1"),
            )
            .unwrap();
        let vfs = mgr.get_vfs(&created.info.id).unwrap();
        vfs.mkdir(&VfsPath::from_slash_path("/photos")).await.unwrap();
        let mut w = vfs
            .open_write(&VfsPath::from_slash_path("/photos/pic.png"), WriteMode::Create)
            .await
            .unwrap();
        w.write_all(b"live-image-bytes").await.unwrap();
        w.shutdown().await.unwrap();
        mgr.save_thumbnail(&created.info.id, "/photos/pic.png", vec![1, 2, 3, 4])
            .await
            .unwrap();

        let vault_dir = PathBuf::from(&created.info.dir_path);
        // Inject orphaned blob, thumb, dir file, and stale .tmp file.
        std::fs::create_dir_all(vault_dir.join("objects/aa")).unwrap();
        std::fs::write(vault_dir.join("objects/aa/deadbeef01.enc"), b"orphan-obj-123").unwrap();
        std::fs::write(vault_dir.join("objects/aa/stale.enc.tmp"), b"stale-tmp-1234").unwrap();
        std::fs::create_dir_all(vault_dir.join("thumbs/bb")).unwrap();
        std::fs::write(vault_dir.join("thumbs/bb/deadthumb01.enc"), b"orphan-th").unwrap();
        std::fs::write(vault_dir.join("dirs/deaddir01.enc"), b"orphan-dir").unwrap();

        let (swept, freed_tmp) =
            crate::vfs::sweep_stale_tmp_files(&vault_dir, std::time::Duration::ZERO);
        assert_eq!(swept, 1);
        assert_eq!(freed_tmp, 14);

        // Add another orphan .tmp for stats + GC verification.
        std::fs::write(vault_dir.join("objects/aa/stale2.enc.tmp"), b"stale2").unwrap();
        let state = mgr.get_state(&created.info.id).unwrap();
        let before = state.compute_stats(std::time::Duration::ZERO).unwrap();
        assert_eq!(before.file_count, 1);
        assert_eq!(before.dir_count, 1);
        assert_eq!(before.total_plain_bytes, 16);
        assert_eq!(before.orphan_count, 4);
        assert_eq!(before.orphan_bytes, 14 + 6 + 9 + 10);

        let gc = state
            .gc_orphaned_files_async(std::time::Duration::ZERO)
            .await
            .unwrap();
        assert_eq!(gc.removed_files, 4);
        assert_eq!(gc.freed_bytes, before.orphan_bytes);

        let after = state.compute_stats(std::time::Duration::ZERO).unwrap();
        assert_eq!(after.orphan_count, 0);
        assert_eq!(after.orphan_bytes, 0);
        assert_eq!(after.file_count, 1);

        // Live file and thumbnail remain readable after GC.
        let mut got = Vec::new();
        vfs.open_read(&VfsPath::from_slash_path("/photos/pic.png"))
            .await
            .unwrap()
            .read_to_end(&mut got)
            .await
            .unwrap();
        assert_eq!(got, b"live-image-bytes");
        let thumb = mgr
            .read_thumbnail(&created.info.id, "/photos/pic.png")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(thumb, vec![1, 2, 3, 4]);
    }
}
