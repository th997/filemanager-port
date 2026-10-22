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

fn cipher(data_dir: &Path) -> XChaCha20Poly1305 {
    XChaCha20Poly1305::new(&Key::from(*master_key(data_dir)))
}

pub fn encrypt_config(plain: &str, data_dir: &Path) -> String {
    if plain.starts_with(PREFIX) {
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
    let cipher = cipher(data_dir);
    let nonce = XNonce::from_slice(&raw[..NONCE_LEN]);
    match cipher.decrypt(nonce, &raw[NONCE_LEN..]) {
        Ok(pt) => String::from_utf8(pt).unwrap_or_else(|_| stored.to_string()),
        // Wrong key or corrupt data: hand back the stored form instead of
        // silently dropping the connection; the caller will surface it as
        // a config error the user can act on.
        Err(_) => stored.to_string(),
    }
}

fn master_key(data_dir: &Path) -> &'static [u8; 32] {
    KEY.get_or_init(|| load_or_create_key(data_dir))
}

fn decode_key(b64: &str) -> Option<[u8; 32]> {
    let bytes = STANDARD.decode(b64.trim()).ok()?;
    <[u8; 32]>::try_from(bytes.as_slice()).ok()
}

fn key_file(data_dir: &Path) -> PathBuf {
    data_dir.join("master.key")
}

fn load_or_create_key(data_dir: &Path) -> [u8; 32] {
    // 1. OS keyring, when it already holds a key.
    let entry = keyring::Entry::new("filemanager-port", "master-key").ok();
    if let Some(entry) = &entry {
        if let Ok(existing) = entry.get_password() {
            if let Some(key) = decode_key(&existing) {
                return key;
            }
        }
    }
    // 2. A key file minted by an earlier fallback run. This must win
    //    over minting a fresh keyring key, or every config written by
    //    that run would become unreadable.
    if let Ok(existing) = std::fs::read_to_string(key_file(data_dir)) {
        if let Some(key) = decode_key(&existing) {
            // Adopt it into the keyring for future runs when possible.
            if let Some(entry) = &entry {
                let _ = entry.set_password(&existing);
            }
            return key;
        }
    }
    // 3. Mint a new key: keyring first, file as the fallback store.
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    let encoded = STANDARD.encode(key);
    let stored_in_keyring = entry
        .as_ref()
        .map(|e| e.set_password(&encoded).is_ok())
        .unwrap_or(false);
    if !stored_in_keyring {
        write_key_file(&key_file(data_dir), &encoded);
    }
    key
}

fn write_key_file(path: &Path, encoded: &str) {
    if std::fs::write(path, encoded).is_ok() {
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
        }
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
        let raw = std::fs::read(&db_file).unwrap();
        let raw_text = String::from_utf8_lossy(&raw);
        assert!(!raw_text.contains("hunter2"), "plaintext leaked into DB file");
        assert!(raw_text.contains("enc:v1:"));

        // Reading back returns the original config transparently.
        let listed = db.list_remotes().unwrap();
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].config_json, record.config_json);
    }
}
