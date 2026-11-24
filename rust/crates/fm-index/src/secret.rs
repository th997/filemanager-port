//! Encryption at rest for saved remote configs.
//!
//! A remote config JSON contains passwords and secret access keys, and
//! until now it sat in the SQLite database as plaintext — anyone (or any
//! other app, on Android shared storage) reading the DB file got every
//! credential. Configs are now stored as XChaCha20-Poly1305 ciphertext:
//!
//! ```text
//! enc:v1:<base64(24-byte nonce || ciphertext)>
//! ```
//!
//! The 32-byte master key lives in the OS keyring (service
//! `filemanager-port`, account `master-key`) when one is available. On
//! systems without a keyring it falls back to a `master.key` file next
//! to the database with 0600 permissions — weaker (key and data side by
//! side) but still keeps credentials out of the DB file itself, which is
//! the file that gets backed up, synced and shared in bug reports.
//!
//! Values without the `enc:v1:` prefix are legacy plaintext: they read
//! back unchanged and are rewritten encrypted on the next save.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit},
    Key, XChaCha20Poly1305, XNonce,
};
use rand_core::{OsRng, RngCore};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const PREFIX: &str = "enc:v1:";
const NONCE_LEN: usize = 24;

static KEY: OnceLock<[u8; 32]> = OnceLock::new();
static KEY_PERSISTED: OnceLock<bool> = OnceLock::new();

fn cipher(data_dir: &Path) -> XChaCha20Poly1305 {
    XChaCha20Poly1305::new(&Key::from(*master_key(data_dir)))
}

pub fn encrypt_config(plain: &str, data_dir: &Path) -> String {
    if plain.starts_with(PREFIX) {
        return plain.to_string();
    }
    // Resolve the key first: if it could not be stored anywhere durable,
    // encrypting would write a row that no later process can open. Keeping
    // the plaintext at least leaves the connection usable.
    let _ = master_key(data_dir);
    if !key_is_persisted() {
        eprintln!(
            "[fm-index] WARNING: master key could not be persisted to OS keyring or master.key;              remote credentials are stored in plaintext in SQLite."
        );
        return plain.to_string();
    }
    let cipher = cipher(data_dir);
    let nonce = XChaCha20Poly1305::generate_nonce(OsRng);
    match cipher.encrypt(&nonce, plain.as_bytes()) {
        Ok(ct) => {
            let mut buf = Vec::with_capacity(NONCE_LEN + ct.len());
            buf.extend_from_slice(&nonce);
            buf.extend_from_slice(&ct);
            format!("{PREFIX}{}", STANDARD.encode(buf))
        }
        // Encryption failing must never lose the user's connection:
        // store plaintext rather than nothing (in practice unreachable).
        Err(_) => plain.to_string(),
    }
}

pub fn decrypt_config(stored: &str, data_dir: &Path) -> String {
    let Some(b64) = stored.strip_prefix(PREFIX) else {
        return stored.to_string();
    };
    let Ok(raw) = STANDARD.decode(b64) else {
        return stored.to_string();
    };
    if raw.len() < NONCE_LEN {
        return stored.to_string();
    }
    let nonce = XNonce::from_slice(&raw[..NONCE_LEN]);
    let body = &raw[NONCE_LEN..];
    if let Ok(pt) = cipher(data_dir).decrypt(nonce, body) {
        return String::from_utf8(pt).unwrap_or_else(|_| stored.to_string());
    }
    // Rows written before an Android storage migration were encrypted with
    // the key left in the old shared-storage dir. The migration keeps that
    // key as `master.key.legacy`; without trying it here those rows stay
    // unreadable even though the key is still on disk.
    if let Some(key) = legacy_key(data_dir) {
        let legacy_cipher = XChaCha20Poly1305::new(&Key::from(key));
        if let Ok(pt) = legacy_cipher.decrypt(nonce, body) {
            if let Ok(text) = String::from_utf8(pt) {
                return text;
            }
        }
    }
    // Wrong key or corrupt data: hand back the stored form instead of
    // silently dropping the connection; the caller will surface it as
    // a config error the user can act on.
    stored.to_string()
}

fn legacy_key(data_dir: &Path) -> Option<[u8; 32]> {
    let raw = std::fs::read_to_string(data_dir.join("master.key.legacy")).ok()?;
    decode_key(&raw)
}

fn master_key(data_dir: &Path) -> &'static [u8; 32] {
    KEY.get_or_init(|| {
        let (key, persisted) = load_or_create_key(data_dir);
        let _ = KEY_PERSISTED.set(persisted);
        key
    })
}

/// Whether the master key reached storage that survives a restart.
fn key_is_persisted() -> bool {
    *KEY_PERSISTED.get().unwrap_or(&false)
}

/// Public diagnostic helper indicating whether at-rest credential encryption is active.
pub fn is_encryption_active_for_dir(data_dir: &Path) -> bool {
    let _ = master_key(data_dir);
    key_is_persisted()
}

/// Public diagnostic helper indicating whether at-rest credential encryption is active.
pub fn is_encryption_active() -> bool {
    key_is_persisted()
}

fn decode_key(b64: &str) -> Option<[u8; 32]> {
    let bytes = STANDARD.decode(b64.trim()).ok()?;
    <[u8; 32]>::try_from(bytes.as_slice()).ok()
}

fn key_file(data_dir: &Path) -> PathBuf {
    data_dir.join("master.key")
}

/// True only when the platform keyring really stores secrets across process
/// restarts.
///
/// Android has no keyring backend in the `keyring` crate, so it silently
/// falls back to an in-memory mock whose `set_password` returns `Ok(())`
/// without persisting anything. Trusting that answer meant the master key
/// was never written to disk: every app launch minted a fresh random key,
/// and every remote config saved before the restart became undecryptable.
#[cfg(not(target_os = "macos"))]
fn keyring_persists() -> bool {
    matches!(
        keyring::default::default_credential_builder().persistence(),
        keyring::credential::CredentialPersistence::UntilDelete
    )
}

fn keyring_entry() -> Option<keyring::Entry> {
    // macOS desktop is excluded: ad-hoc signed builds trigger OS Keychain
    // authorization prompts, so the 0600 key file is the primary store there.
    #[cfg(target_os = "macos")]
    {
        None
    }
    #[cfg(not(target_os = "macos"))]
    {
        if !keyring_persists() {
            return None;
        }
        keyring::Entry::new("filemanager-port", "master-key").ok()
    }
}

fn load_or_create_key(data_dir: &Path) -> ([u8; 32], bool) {
    let entry = keyring_entry();
    load_or_create_key_with(data_dir, entry.as_ref())
}

/// Returns the key and whether it is stored durably (keyring or key file).
fn load_or_create_key_with(data_dir: &Path, entry: Option<&keyring::Entry>) -> ([u8; 32], bool) {
    // 1. A key file minted on disk. It is the primary store on desktop and
    //    the only store on platforms without a persistent keyring (Android).
    if let Ok(existing) = std::fs::read_to_string(key_file(data_dir)) {
        if let Some(key) = decode_key(&existing) {
            return (key, true);
        }
    }

    // 2. OS keyring, when one exists and actually persists.
    if let Some(entry) = entry {
        if let Ok(existing) = entry.get_password() {
            if let Some(key) = decode_key(&existing) {
                return (key, true);
            }
        }
    }

    // 3. Mint a new key and store it wherever it survives a restart.
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    let encoded = STANDARD.encode(key);
    let stored_in_keyring = entry
        .map(|e| e.set_password(&encoded).is_ok())
        .unwrap_or(false);
    if stored_in_keyring {
        return (key, true);
    }
    let stored_on_disk = write_key_file(&key_file(data_dir), &encoded);
    (key, stored_on_disk)
}

fn write_key_file(path: &Path, encoded: &str) -> bool {
    // Create with 0600 from the start: writing first and chmod-ing after
    // left a window where any local user could read the master key.
    #[cfg(unix)]
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let opened = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path);
        if let Ok(mut file) = opened {
            let wrote = file.write_all(encoded.as_bytes()).is_ok();
            use std::os::unix::fs::PermissionsExt;
            // Re-assert in case the file already existed with wider perms.
            let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
            return wrote;
        }
        false
    }
    #[cfg(not(unix))]
    {
        std::fs::write(path, encoded).is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("fm-secret-test-{tag}"));
        let _ = std::fs::create_dir_all(&dir);
        dir
    }

    #[test]
    fn round_trip_hides_plaintext() {
        let dir = temp_dir("roundtrip");
        let plain = r#"{"kind":"sftp","password":"hunter2"}"#;
        let stored = encrypt_config(plain, &dir);
        assert!(stored.starts_with(PREFIX));
        assert!(!stored.contains("hunter2"));
        assert_eq!(decrypt_config(&stored, &dir), plain);
    }

    #[test]
    fn legacy_plaintext_passes_through() {
        let dir = temp_dir("legacy");
        let plain = r#"{"kind":"ftp","password":"old"}"#;
        assert_eq!(decrypt_config(plain, &dir), plain);
        // Already-encrypted input is never double-wrapped.
        let once = encrypt_config(plain, &dir);
        assert_eq!(encrypt_config(&once, &dir), once);
    }

    #[test]
    fn tampered_ciphertext_is_returned_unchanged() {
        let dir = temp_dir("tamper");
        let stored = encrypt_config("secret", &dir);
        let mut raw = STANDARD.decode(stored.strip_prefix(PREFIX).unwrap()).unwrap();
        let last = raw.len() - 1;
        raw[last] ^= 0xFF;
        let forged = format!("{PREFIX}{}", STANDARD.encode(raw));
        assert_eq!(decrypt_config(&forged, &dir), forged);
    }

    /// Android has no persistent keyring; the key must still reach disk, or
    /// the next process start invents a new one and every config saved in
    /// the previous session becomes unreadable.
    #[test]
    fn key_is_written_to_disk_without_a_persistent_keyring() {
        let dir = temp_dir("nokeyring");
        let _ = std::fs::remove_file(key_file(&dir));
        let (key, persisted) = load_or_create_key_with(&dir, None);
        assert!(persisted);
        let written = std::fs::read_to_string(key_file(&dir)).expect("key file written");
        assert_eq!(decode_key(&written), Some(key));
    }

    #[test]
    fn existing_key_file_is_reused_across_calls() {
        let dir = temp_dir("reuse");
        let _ = std::fs::remove_file(key_file(&dir));
        let (first, _) = load_or_create_key_with(&dir, None);
        let (second, _) = load_or_create_key_with(&dir, None);
        assert_eq!(first, second);
    }

    /// Rows encrypted with the pre-migration key must still open when that
    /// key was preserved as `master.key.legacy`.
    #[test]
    fn legacy_key_decrypts_rows_written_before_the_key_changed() {
        let dir = temp_dir("legacykey");
        let _ = std::fs::remove_file(key_file(&dir));
        let _ = std::fs::remove_file(dir.join("master.key.legacy"));

        let old_key = [7u8; 32];
        std::fs::write(
            dir.join("master.key.legacy"),
            STANDARD.encode(old_key),
        )
        .unwrap();
        let old_cipher = XChaCha20Poly1305::new(&Key::from(old_key));
        let nonce = XChaCha20Poly1305::generate_nonce(OsRng);
        let ct = old_cipher.encrypt(&nonce, b"old-config".as_slice()).unwrap();
        let mut buf = Vec::new();
        buf.extend_from_slice(&nonce);
        buf.extend_from_slice(&ct);
        let stored = format!("{PREFIX}{}", STANDARD.encode(buf));

        // A different current key is now in place.
        let _ = load_or_create_key_with(&dir, None);
        assert_eq!(decrypt_config(&stored, &dir), "old-config");
    }

    #[test]
    fn missing_legacy_key_is_not_an_error() {
        let dir = temp_dir("nolegacykey");
        let _ = std::fs::remove_file(dir.join("master.key.legacy"));
        let stored = encrypt_config("current", &dir);
        assert_eq!(decrypt_config(&stored, &dir), "current");
    }
}

#[cfg(test)]
mod db_integration_tests {
    use crate::db::{Database, RemoteRecord};

    #[test]
    fn remote_configs_are_encrypted_at_rest_and_decrypt_on_read() {
        let dir = std::env::temp_dir().join("fm-secret-test-db");
        let _ = std::fs::create_dir_all(&dir);
        let db_file = dir.join("test.db");
        let _ = std::fs::remove_file(&db_file);
        let db = Database::open(&db_file, dir.join("trash")).unwrap();
        let record = RemoteRecord {
            id: "r1".into(),
            kind: "sftp".into(),
            display_name: "Test".into(),
            config_json: r#"{"password":"hunter2"}"#.into(),
            created_at: 1,
        };
        db.save_remote(&record).unwrap();

        // The raw column must not contain the password.
        let raw = std::fs::read(&db_file).unwrap_or_default();
        let wal = std::fs::read(dir.join("test.db-wal")).unwrap_or_default();
        let raw_text = format!("{}{}", String::from_utf8_lossy(&raw), String::from_utf8_lossy(&wal));
        assert!(!raw_text.contains("hunter2"), "plaintext leaked into DB file");
        assert!(raw_text.contains("enc:v1:"));

        // Reading back returns the original config transparently.
        let listed = db.list_remotes().unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].config_json, record.config_json);
    }

    /// Mirrors fm-ffi's `pin_host_key`, which re-saves an existing record
    /// with `..record` purely to attach an SSH host key pin. That rewrite
    /// turns a legacy plaintext row into ciphertext, so it must keep
    /// `created_at` and must stay readable afterwards.
    #[test]
    fn pinning_a_host_key_on_a_legacy_row_keeps_it_readable() {
        let dir = std::env::temp_dir().join("fm-secret-test-pin");
        let _ = std::fs::create_dir_all(&dir);
        let db_file = dir.join("pin.db");
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(dir.join(format!("pin.db{suffix}")));
        }
        let plain = r#"{"kind":"Sftp","host":"example.invalid","password":"hunter2"}"#;
        let created_at = 1_792_508_462_721_i64;
        {
            let db = Database::open(&db_file, dir.join("trash")).unwrap();
            drop(db);
            let conn = rusqlite::Connection::open(&db_file).unwrap();
            conn.execute(
                "INSERT INTO remotes (id, kind, display_name, config_json, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                rusqlite::params!["sftp_th", "sftp", "th", plain, created_at],
            )
            .unwrap();
        }

        let db = Database::open(&db_file, dir.join("trash")).unwrap();
        let stored = db.list_remotes().unwrap().remove(0);
        assert_eq!(stored.config_json, plain);
        assert_eq!(stored.created_at, created_at);

        let pinned = RemoteRecord {
            config_json: r#"{"kind":"Sftp","host":"example.invalid","password":"hunter2","host_key_fingerprint":"SHA256:pin"}"#.into(),
            ..stored
        };
        db.save_remote(&pinned).unwrap();

        let after = db.list_remotes().unwrap().remove(0);
        assert_eq!(after.created_at, created_at);
        assert_eq!(after.config_json, pinned.config_json);
    }
}
