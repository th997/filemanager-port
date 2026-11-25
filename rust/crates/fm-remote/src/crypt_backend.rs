//! Zero-knowledge client-side encryption decorator (`CryptFs`).
//!
//! Wraps any [`Vfs`] backend (S3, OSS, WebDAV, SFTP, SMB, Local) with:
//! - Deterministic AES-256-GCM filename encryption per path segment (stateless:
//!   no central metadata index file, multi-device concurrent writes never clash).
//! - Chunked 64 KiB AES-256-GCM file payload encryption supporting O(1)
//!   plaintext size calculation and arbitrary byte-range seeking (`open_read_range`)
//!   for instant media playback over encrypted cloud storage.

use std::io;
use std::sync::Arc;

use aes_gcm::aead::{Aead, Payload};
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use argon2::Argon2;
use async_trait::async_trait;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use fm_core::{Capabilities, Entry, EntryKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};
use hkdf::Hkdf;
use hmac::{Hmac, KeyInit as HmacKeyInit, Mac};
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use zeroize::{Zeroize, Zeroizing};

use crate::pipe_writer::{pipe_writer, signaling_reader};

const MAGIC: [u8; 8] = *b"FMCRYPT1";
const HEADER_SIZE: usize = 32;
const PLAIN_CHUNK_SIZE: usize = 65536;
const TAG_SIZE: usize = 16;
const CIPHER_CHUNK_SIZE: usize = PLAIN_CHUNK_SIZE + TAG_SIZE;
const NAME_SUFFIX: &str = ".fmc";

type HmacSha256 = Hmac<Sha256>;

struct CryptKeys {
    content_key: Zeroizing<[u8; 32]>,
    name_key: Zeroizing<[u8; 32]>,
}

/// Zero-knowledge encrypted VFS decorator wrapping a backing [`Vfs`].
pub struct CryptFs {
    backing: Arc<dyn Vfs>,
    base_prefix: VfsPath,
    keys: CryptKeys,
}

impl CryptFs {
    /// Creates a new `CryptFs` wrapping `backing` rooted at `base_prefix`.
    pub fn new(
        backing: Arc<dyn Vfs>,
        base_prefix: &str,
        password: &str,
        salt: Option<&str>,
    ) -> VfsResult<Self> {
        if password.is_empty() {
            return Err(VfsError::Connection {
                message: "zero-knowledge vault password must not be empty".to_string(),
            });
        }
        let keys = derive_keys(password, salt)?;
        Ok(Self {
            backing,
            base_prefix: VfsPath::from_slash_path(base_prefix),
            keys,
        })
    }

    pub fn encrypt_segment(&self, segment: &str) -> Result<String, String> {
        let nonce = synthetic_name_nonce(&self.keys.name_key, segment)?;
        let cipher = Aes256Gcm::new_from_slice(&*self.keys.name_key)
            .map_err(|e| format!("name cipher init failed: {e}"))?;
        let ct = cipher
            .encrypt(&Nonce::from(nonce), segment.as_bytes())
            .map_err(|e| format!("segment encryption failed: {e}"))?;
        let mut combined = Vec::with_capacity(12 + ct.len());
        combined.extend_from_slice(&nonce);
        combined.extend_from_slice(&ct);
        Ok(format!("{}{NAME_SUFFIX}", URL_SAFE_NO_PAD.encode(&combined)))
    }

    pub fn decrypt_segment(&self, encrypted_name: &str) -> Option<String> {
        let encoded = encrypted_name.strip_suffix(NAME_SUFFIX)?;
        let raw = URL_SAFE_NO_PAD.decode(encoded.as_bytes()).ok()?;
        if raw.len() < 12 + TAG_SIZE {
            return None;
        }
        let (nonce, ct) = raw.split_at(12);
        let nonce_arr: [u8; 12] = nonce.try_into().ok()?;
        let cipher = Aes256Gcm::new_from_slice(&*self.keys.name_key).ok()?;
        let pt = cipher.decrypt(&Nonce::from(nonce_arr), ct).ok()?;
        String::from_utf8(pt).ok()
    }

    fn map_path(&self, logical: &VfsPath) -> VfsResult<VfsPath> {
        let mut out = self.base_prefix.clone();
        for seg in logical.segments() {
            let enc = self.encrypt_segment(seg).map_err(|msg| VfsError::Backend {
                path: logical.clone(),
                source: io::Error::other(msg),
            })?;
            out = out.join(enc);
        }
        Ok(out)
    }

    async fn ensure_base_prefix(&self) -> VfsResult<()> {
        let mut cur = VfsPath::root();
        for seg in self.base_prefix.segments() {
            cur = cur.join(seg);
            if self.backing.stat(&cur).await.is_ok() {
                continue;
            }
            match self.backing.mkdir(&cur).await {
                Ok(()) => {}
                Err(e) => {
                    if self.backing.stat(&cur).await.is_ok() {
                        continue;
                    }
                    if matches!(
                        &e,
                        VfsError::Backend { source, .. }
                            if source.kind() == io::ErrorKind::AlreadyExists
                    ) {
                        continue;
                    }
                    return Err(e);
                }
            }
        }
        Ok(())
    }

    fn map_entry(&self, backing_entry: Entry, parent_logical: &VfsPath) -> Option<Entry> {
        let plain_name = self.decrypt_segment(&backing_entry.name)?;
        let plain_path = parent_logical.join(&plain_name);
        let plain_size = if backing_entry.kind == EntryKind::Dir {
            None
        } else {
            backing_entry.size.and_then(plaintext_size_from_encrypted)
        };
        Some(Entry {
            hidden: plain_name.starts_with('.'),
            name: plain_name,
            path: plain_path,
            kind: backing_entry.kind,
            size: plain_size,
            modified: backing_entry.modified,
            mode: backing_entry.mode,
            is_symlink: backing_entry.is_symlink,
            mime: None,
        })
    }
}

fn derive_keys(password: &str, salt: Option<&str>) -> VfsResult<CryptKeys> {
    let salt_input = format!("FMCRYPT1:KDF:{}", salt.unwrap_or("default").trim());
    let mut salt_hash = Sha256::digest(salt_input.as_bytes());
    let mut kdf_salt = [0u8; 16];
    kdf_salt.copy_from_slice(&salt_hash[..16]);
    salt_hash.zeroize();

    let mut ikm = Zeroizing::new([0u8; 32]);
    Argon2::default()
        .hash_password_into(password.as_bytes(), &kdf_salt, &mut *ikm)
        .map_err(|e| VfsError::Connection {
            message: format!("argon2 key derivation failed: {e}"),
        })?;

    let hk = Hkdf::<Sha256>::new(Some(&kdf_salt), &*ikm);
    let mut content_key = Zeroizing::new([0u8; 32]);
    let mut name_key = Zeroizing::new([0u8; 32]);
    hk.expand(b"fm-crypt-content-v1", &mut *content_key)
        .map_err(|e| VfsError::Connection {
            message: format!("hkdf content key failed: {e}"),
        })?;
    hk.expand(b"fm-crypt-name-v1", &mut *name_key)
        .map_err(|e| VfsError::Connection {
            message: format!("hkdf name key failed: {e}"),
        })?;
    Ok(CryptKeys {
        content_key,
        name_key,
    })
}

fn synthetic_name_nonce(name_key: &[u8; 32], segment: &str) -> Result<[u8; 12], String> {
    let mut mac = <HmacSha256 as HmacKeyInit>::new_from_slice(name_key)
        .map_err(|e| format!("hmac init failed: {e}"))?;
    mac.update(b"name:");
    mac.update(segment.as_bytes());
    let digest = mac.finalize().into_bytes();
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&digest[..12]);
    Ok(nonce)
}

fn chunk_nonce(base_nonce: &[u8; 12], chunk_idx: u64) -> [u8; 12] {
    let mut out = *base_nonce;
    let idx_bytes = chunk_idx.to_le_bytes();
    for i in 0..8 {
        out[4 + i] ^= idx_bytes[i];
    }
    out
}

fn chunk_aad(chunk_idx: u64) -> [u8; 16] {
    let mut aad = [0u8; 16];
    aad[..8].copy_from_slice(&MAGIC);
    aad[8..16].copy_from_slice(&chunk_idx.to_le_bytes());
    aad
}

fn encode_header(base_nonce: &[u8; 12]) -> [u8; HEADER_SIZE] {
    let mut hdr = [0u8; HEADER_SIZE];
    hdr[..8].copy_from_slice(&MAGIC);
    hdr[8..12].copy_from_slice(&(PLAIN_CHUNK_SIZE as u32).to_le_bytes());
    hdr[12..24].copy_from_slice(base_nonce);
    hdr
}

fn decode_header(hdr: &[u8]) -> Result<[u8; 12], String> {
    if hdr.len() < HEADER_SIZE {
        return Err("truncated encrypted file header".to_string());
    }
    if hdr[..8] != MAGIC {
        return Err("invalid encrypted file magic (wrong format or unencrypted)".to_string());
    }
    let mut chunk_bytes = [0u8; 4];
    chunk_bytes.copy_from_slice(&hdr[8..12]);
    let chunk_size = u32::from_le_bytes(chunk_bytes) as usize;
    if chunk_size != PLAIN_CHUNK_SIZE {
        return Err(format!("unsupported encrypted chunk size: {chunk_size}"));
    }
    let mut base_nonce = [0u8; 12];
    base_nonce.copy_from_slice(&hdr[12..24]);
    Ok(base_nonce)
}

pub(crate) fn plaintext_size_from_encrypted(enc_len: u64) -> Option<u64> {
    if enc_len < HEADER_SIZE as u64 {
        return None;
    }
    let payload = enc_len - HEADER_SIZE as u64;
    let full_chunks = payload / (CIPHER_CHUNK_SIZE as u64);
    let rem = payload % (CIPHER_CHUNK_SIZE as u64);
    if rem > 0 && rem < TAG_SIZE as u64 {
        return None;
    }
    let plain_rem = if rem == 0 { 0 } else { rem - TAG_SIZE as u64 };
    Some(full_chunks * (PLAIN_CHUNK_SIZE as u64) + plain_rem)
}

async fn read_exact_or_eof<R: AsyncRead + Unpin>(
    reader: &mut R,
    buf: &mut [u8],
) -> Result<usize, String> {
    let mut filled = 0;
    while filled < buf.len() {
        let n = reader
            .read(&mut buf[filled..])
            .await
            .map_err(|e| format!("read error: {e}"))?;
        if n == 0 {
            break;
        }
        filled += n;
    }
    Ok(filled)
}

#[async_trait]
impl Vfs for CryptFs {
    fn capabilities(&self) -> Capabilities {
        self.backing.capabilities()
    }

    fn prefers_direct_write(&self) -> bool {
        true
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        let enc_dir = self.map_path(dir)?;
        let raw_entries = match self.backing.list(&enc_dir).await {
            Ok(v) => v,
            Err(VfsError::NotFound { .. }) if dir.is_root() && !self.base_prefix.is_root() => {
                return Ok(Vec::new());
            }
            Err(e) => return Err(e),
        };
        let mut out = Vec::with_capacity(raw_entries.len());
        for entry in raw_entries {
            if let Some(mapped) = self.map_entry(entry, dir) {
                out.push(mapped);
            }
        }
        Ok(out)
    }

    async fn list_paged_with_total(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool, Option<u32>)> {
        let mut all = self.list(dir).await?;
        all.sort_unstable_by(|a, b| {
            fm_core::compare_dir_and_name(
                a.kind == EntryKind::Dir,
                &a.name,
                b.kind == EntryKind::Dir,
                &b.name,
                true,
            )
        });
        let total = all.len();
        let page = page.max(1) as usize;
        let page_size = page_size.max(1) as usize;
        let skip = (page - 1).saturating_mul(page_size);
        let has_more = skip.saturating_add(page_size) < total;
        let slice = all.into_iter().skip(skip).take(page_size).collect();
        Ok((slice, has_more, Some(total as u32)))
    }

    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        let (entries, has_more, _) = self.list_paged_with_total(dir, page, page_size).await?;
        Ok((entries, has_more))
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        let enc_path = self.map_path(path)?;
        let raw = self.backing.stat(&enc_path).await?;
        if path.is_root() {
            return Ok(Entry {
                name: String::new(),
                path: VfsPath::root(),
                kind: EntryKind::Dir,
                size: None,
                modified: raw.modified,
                mode: raw.mode,
                hidden: false,
                is_symlink: raw.is_symlink,
                mime: None,
            });
        }
        let parent = path.parent().unwrap_or_else(VfsPath::root);
        self.map_entry(raw, &parent)
            .ok_or_else(|| VfsError::NotFound { path: path.clone() })
    }

    async fn open_read(
        &self,
        path: &VfsPath,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        self.open_read_range(path, 0, None).await
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        if matches!(length, Some(0)) {
            return Ok(Box::new(tokio::io::empty()));
        }
        let enc_path = self.map_path(path)?;
        let content_key = Zeroizing::new(*self.keys.content_key);
        let backing = Arc::clone(&self.backing);

        let start_chunk = offset / (PLAIN_CHUNK_SIZE as u64);
        let mut skip_in_first = (offset % (PLAIN_CHUNK_SIZE as u64)) as usize;
        let cipher_offset = (HEADER_SIZE as u64).saturating_add(
            start_chunk.saturating_mul(CIPHER_CHUNK_SIZE as u64),
        );
        let cipher_len = length.map(|len| {
            let end_plain = offset.saturating_add(len).saturating_sub(1);
            let end_chunk = end_plain / (PLAIN_CHUNK_SIZE as u64);
            let chunk_count = end_chunk.saturating_sub(start_chunk).saturating_add(1);
            chunk_count.saturating_mul(CIPHER_CHUNK_SIZE as u64)
        });

        // When starting in chunk 0, open a single backing stream at offset 0 for both the
        // 32-byte header and the ciphertext chunks. This prevents HTTP 416 errors on
        // 0-byte encrypted files (which are stored as 32-byte header-only objects) on
        // S3/OSS/WebDAV and eliminates an extra network round-trip.
        let (base_nonce, mut cipher_reader) = if start_chunk == 0 {
            let total_req_len = cipher_len.map(|cl| (HEADER_SIZE as u64).saturating_add(cl));
            let mut combined = backing
                .open_read_range(&enc_path, 0, total_req_len)
                .await?;
            let mut hdr_buf = [0u8; HEADER_SIZE];
            let hdr_n = read_exact_or_eof(&mut combined, &mut hdr_buf)
                .await
                .map_err(|msg| VfsError::Backend {
                    path: path.clone(),
                    source: io::Error::other(msg),
                })?;
            let nonce = decode_header(&hdr_buf[..hdr_n]).map_err(|msg| VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::InvalidData, msg),
            })?;
            (nonce, combined)
        } else {
            let enc_stat = backing.stat(&enc_path).await?;
            let mut hdr_reader = backing
                .open_read_range(&enc_path, 0, Some(HEADER_SIZE as u64))
                .await?;
            let mut hdr_buf = [0u8; HEADER_SIZE];
            let hdr_n = read_exact_or_eof(&mut hdr_reader, &mut hdr_buf)
                .await
                .map_err(|msg| VfsError::Backend {
                    path: path.clone(),
                    source: io::Error::other(msg),
                })?;
            let nonce = decode_header(&hdr_buf[..hdr_n]).map_err(|msg| VfsError::Backend {
                path: path.clone(),
                source: io::Error::new(io::ErrorKind::InvalidData, msg),
            })?;
            if let Some(enc_total) = enc_stat.size {
                if cipher_offset >= enc_total {
                    return Ok(Box::new(tokio::io::empty()));
                }
            }
            let reader = backing
                .open_read_range(&enc_path, cipher_offset, cipher_len)
                .await?;
            (nonce, reader)
        };

        Ok(signaling_reader(move |mut tx| async move {
            let cipher = Aes256Gcm::new_from_slice(&*content_key)
                .map_err(|e| format!("content cipher init failed: {e}"))?;
            let mut remaining = length;
            let mut chunk_idx = start_chunk;
            let mut buf = vec![0u8; CIPHER_CHUNK_SIZE];

            loop {
                if matches!(remaining, Some(0)) {
                    break;
                }
                let n = read_exact_or_eof(&mut cipher_reader, &mut buf).await?;
                if n == 0 {
                    break;
                }
                if n < TAG_SIZE {
                    return Err("truncated encrypted chunk".to_string());
                }
                let nonce = chunk_nonce(&base_nonce, chunk_idx);
                let aad = chunk_aad(chunk_idx);
                let pt = cipher
                    .decrypt(
                        &Nonce::from(nonce),
                        Payload {
                            msg: &buf[..n],
                            aad: &aad,
                        },
                    )
                    .map_err(|_| "decryption failed: wrong password or corrupted data".to_string())?;

                if skip_in_first < pt.len() {
                    let slice = &pt[skip_in_first..];
                    let emit = match remaining {
                        Some(rem) => {
                            let take = rem.min(slice.len() as u64) as usize;
                            remaining = Some(rem - take as u64);
                            &slice[..take]
                        }
                        None => slice,
                    };
                    tx.write_all(emit).await.map_err(|e| e.to_string())?;
                }
                skip_in_first = 0;
                chunk_idx = chunk_idx.saturating_add(1);
            }
            tx.shutdown().await.map_err(|e| e.to_string())?;
            Ok(())
        }))
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        if mode == WriteMode::Append {
            return Err(VfsError::Unsupported {
                operation: "append on encrypted cloud vault",
            });
        }
        self.ensure_base_prefix().await?;
        let enc_path = self.map_path(path)?;
        let content_key = Zeroizing::new(*self.keys.content_key);
        let mut out_writer = self.backing.open_write(&enc_path, mode).await?;

        Ok(pipe_writer(move |mut rx| async move {
            let cipher = Aes256Gcm::new_from_slice(&*content_key)
                .map_err(|e| format!("content cipher init failed: {e}"))?;
            let mut base_nonce = [0u8; 12];
            OsRng.fill_bytes(&mut base_nonce);
            let hdr = encode_header(&base_nonce);
            out_writer
                .write_all(&hdr)
                .await
                .map_err(|e| e.to_string())?;

            let mut chunk_idx: u64 = 0;
            let mut buf = vec![0u8; PLAIN_CHUNK_SIZE];
            loop {
                let n = read_exact_or_eof(&mut rx, &mut buf).await?;
                if n == 0 {
                    break;
                }
                let nonce = chunk_nonce(&base_nonce, chunk_idx);
                let aad = chunk_aad(chunk_idx);
                let ct = cipher
                    .encrypt(
                        &Nonce::from(nonce),
                        Payload {
                            msg: &buf[..n],
                            aad: &aad,
                        },
                    )
                    .map_err(|e| format!("chunk encryption failed: {e}"))?;
                out_writer
                    .write_all(&ct)
                    .await
                    .map_err(|e| e.to_string())?;
                chunk_idx = chunk_idx.saturating_add(1);
            }
            out_writer.shutdown().await.map_err(|e| e.to_string())?;
            Ok(())
        }))
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        self.ensure_base_prefix().await?;
        let enc_path = self.map_path(path)?;
        self.backing.mkdir(&enc_path).await
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        if path.is_root() {
            return Err(VfsError::PermissionDenied { path: path.clone() });
        }
        let enc_path = self.map_path(path)?;
        self.backing.remove(&enc_path).await
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        if from.is_root() || to.is_root() {
            return Err(VfsError::PermissionDenied { path: from.clone() });
        }
        let enc_from = self.map_path(from)?;
        let enc_to = self.map_path(to)?;
        self.backing.rename(&enc_from, &enc_to).await
    }

    async fn space_info(&self, _path: &VfsPath) -> VfsResult<Option<fm_core::SpaceInfo>> {
        self.backing.space_info(&self.base_prefix).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fm_local::LocalFs;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[tokio::test]
    async fn crypt_fs_roundtrip_multi_chunk_range_seek_and_wrong_password() {
        let temp = tempfile::tempdir().unwrap();
        let backing: Arc<dyn Vfs> = Arc::new(LocalFs::new(temp.path()));
        let crypt = CryptFs::new(Arc::clone(&backing), "/vault", "correct-horse-battery", Some("nas1")).unwrap();

        let dir = VfsPath::from_slash_path("/Photos");
        crypt.mkdir(&dir).await.unwrap();

        // Backing directory name must be encrypted (not "Photos").
        let raw_root_entries = backing
            .list(&VfsPath::from_slash_path("/vault"))
            .await
            .unwrap();
        assert_eq!(raw_root_entries.len(), 1);
        assert_ne!(raw_root_entries[0].name, "Photos");
        assert!(raw_root_entries[0].name.ends_with(".fmc"));

        // Write > 150 KiB (3 encrypted chunks).
        let payload: Vec<u8> = (0..(150 * 1024 + 321))
            .map(|i| ((i * 31 + 7) % 251) as u8)
            .collect();
        let file_path = dir.join("secret.bin");
        let mut writer = crypt.open_write(&file_path, WriteMode::Truncate).await.unwrap();
        writer.write_all(&payload).await.unwrap();
        writer.shutdown().await.unwrap();

        // List & stat report exact decrypted name and plaintext byte size O(1).
        let entries = crypt.list(&dir).await.unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].name, "secret.bin");
        assert_eq!(entries[0].size, Some(payload.len() as u64));
        assert_eq!(crypt.stat(&file_path).await.unwrap().size, Some(payload.len() as u64));

        // Full read matches plaintext.
        let mut full_reader = crypt.open_read(&file_path).await.unwrap();
        let mut got_full = Vec::new();
        full_reader.read_to_end(&mut got_full).await.unwrap();
        assert_eq!(got_full, payload);

        // Arbitrary mid-chunk seek crossing chunk boundary (offset 65500, length 200).
        let mut range_reader = crypt.open_read_range(&file_path, 65500, Some(200)).await.unwrap();
        let mut got_range = Vec::new();
        range_reader.read_to_end(&mut got_range).await.unwrap();
        assert_eq!(got_range, payload[65500..65700]);

        // Rename & delete work via decrypted logical paths.
        let renamed = dir.join("renamed.bin");
        crypt.rename(&file_path, &renamed).await.unwrap();
        assert_eq!(crypt.list(&dir).await.unwrap()[0].name, "renamed.bin");

        // Wrong password sees nothing and rejects decryption.
        let wrong = CryptFs::new(Arc::clone(&backing), "/vault", "wrong-password", Some("nas1")).unwrap();
        assert!(wrong.list(&VfsPath::root()).await.unwrap().is_empty());

        crypt.remove(&renamed).await.unwrap();
        assert!(crypt.list(&dir).await.unwrap().is_empty());

        // Zero-byte encrypted file reads cleanly as empty without 416 / header failure,
        // and root remove/rename are denied.
        let empty_path = dir.join("empty.bin");
        let mut ew = crypt.open_write(&empty_path, WriteMode::Truncate).await.unwrap();
        ew.shutdown().await.unwrap();
        assert_eq!(crypt.stat(&empty_path).await.unwrap().size, Some(0));
        let mut er = crypt.open_read(&empty_path).await.unwrap();
        let mut empty_buf = Vec::new();
        er.read_to_end(&mut empty_buf).await.unwrap();
        assert!(empty_buf.is_empty());
        assert!(crypt.remove(&VfsPath::root()).await.is_err());
        assert!(crypt.rename(&VfsPath::root(), &dir).await.is_err());
    }
}
