//! Chunk and metadata-snapshot encryption built on top of `fm-vault`'s
//! cryptographic primitives (Argon2id + HKDF-SHA256 + AES-256-GCM).
//!
//! Encrypted chunks use the self-contained `FPC1` 64 KiB sub-chunked format so
//! `Vfs::open_read_range` can seek directly to the minimal set of sub-chunks
//! covering an arbitrary byte range without downloading or decrypting an
//! entire 16 MiB chunk.

use crate::error::{PoolError, PoolResult};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm, Nonce,
};
use aes_gcm::aead::array::typenum::U12;
use flate2::{read::GzDecoder, write::GzEncoder, Compression};
use fm_vault::crypto::{
    decrypt_blob, derive_kek_argon2id_with_params, derive_subkey, encrypt_blob, random_bytes,
    KdfParams, VaultCipher,
};
use hmac::{digest::KeyInit as HmacKeyInit, Hmac, Mac};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use zeroize::Zeroizing;

pub const FPC1_MAGIC: [u8; 4] = *b"FPC1";
pub const FPC1_VERSION: u8 = 1;
pub const FPC1_HEADER_SIZE: usize = 40;
pub const FPC1_SUB_CHUNK_SIZE: usize = 64 * 1024;
pub const GCM_TAG_SIZE: usize = 16;

#[derive(Clone)]
pub struct PoolCrypto {
    pool_id: String,
    dek: Zeroizing<[u8; 32]>,
    dedup_key: Zeroizing<[u8; 32]>,
    chunk_master_key: Zeroizing<[u8; 32]>,
    meta_key: Zeroizing<[u8; 32]>,
}

impl std::fmt::Debug for PoolCrypto {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PoolCrypto")
            .field("pool_id", &self.pool_id)
            .field("keys", &"<redacted>")
            .finish()
    }
}

impl PoolCrypto {
    /// Derive pool DEK and domain-separated subkeys from a user passphrase,
    /// salt, and Argon2id parameters.
    pub fn from_passphrase(
        pool_id: &str,
        passphrase: &str,
        salt: &[u8; 16],
        kdf_params: KdfParams,
    ) -> PoolResult<Self> {
        if passphrase.is_empty() {
            return Err(PoolError::Crypto(
                "encryption passphrase cannot be empty when encryption is enabled".to_string(),
            ));
        }
        let dek = derive_kek_argon2id_with_params(passphrase, salt, kdf_params)?;
        let dedup_key = derive_subkey(&dek, salt, b"fm-pool-dedup-v1")?;
        let chunk_master_key = derive_subkey(&dek, salt, b"fm-pool-chunk-master-v1")?;
        let meta_key = derive_subkey(&dek, salt, b"fm-pool-meta-v1")?;
        Ok(Self {
            pool_id: pool_id.to_string(),
            dek,
            dedup_key,
            chunk_master_key,
            meta_key,
        })
    }

    pub fn pool_id(&self) -> &str {
        &self.pool_id
    }

    pub fn meta_key(&self) -> &[u8; 32] {
        &self.meta_key
    }

    /// Compute a keyed HMAC-SHA256 content identifier over plaintext so
    /// identical chunks deduplicate within this pool without leaking plaintext
    /// SHA-256 hashes to remote nodes.
    pub fn keyed_content_id(&self, plaintext: &[u8]) -> PoolResult<String> {
        type HmacSha256 = Hmac<Sha256>;
        let mut mac = <HmacSha256 as HmacKeyInit>::new_from_slice(&*self.dedup_key)
            .map_err(|e| PoolError::Crypto(format!("hmac init failed: {e}")))?;
        mac.update(plaintext);
        Ok(hex::encode(mac.finalize().into_bytes()))
    }

    pub fn derive_chunk_key(&self, chunk_salt: &[u8; 16]) -> PoolResult<Zeroizing<[u8; 32]>> {
        derive_subkey(&self.chunk_master_key, chunk_salt, b"fm-pool-subkey-v1")
            .map_err(PoolError::from)
    }

    pub fn verifier_hmac(&self) -> PoolResult<String> {
        type HmacSha256 = Hmac<Sha256>;
        let mut mac = <HmacSha256 as HmacKeyInit>::new_from_slice(&*self.dek)
            .map_err(|e| PoolError::Crypto(format!("hmac init failed: {e}")))?;
        mac.update(b"fm-pool-key-verify-v1:");
        mac.update(self.pool_id.as_bytes());
        Ok(hex::encode(mac.finalize().into_bytes()))
    }
}

/// Compute the stored `chunk_hash` for a plaintext chunk:
/// keyed HMAC-SHA256 in encrypted mode, raw SHA-256 in plaintext mode.
pub fn chunk_content_id(crypto: Option<&PoolCrypto>, plaintext: &[u8]) -> PoolResult<String> {
    match crypto {
        Some(c) => c.keyed_content_id(plaintext),
        None => Ok(sha256_hex(plaintext)),
    }
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fpc1Header {
    pub sub_chunk_size: u32,
    pub plain_len: u64,
    pub chunk_salt: [u8; 16],
    pub nonce_prefix: [u8; 4],
}

impl Fpc1Header {
    pub fn encode(&self) -> [u8; FPC1_HEADER_SIZE] {
        let mut buf = [0u8; FPC1_HEADER_SIZE];
        buf[0..4].copy_from_slice(&FPC1_MAGIC);
        buf[4] = FPC1_VERSION;
        buf[5] = 0; // flags
        buf[6..8].copy_from_slice(&0u16.to_le_bytes());
        buf[8..12].copy_from_slice(&self.sub_chunk_size.to_le_bytes());
        buf[12..20].copy_from_slice(&self.plain_len.to_le_bytes());
        buf[20..36].copy_from_slice(&self.chunk_salt);
        buf[36..40].copy_from_slice(&self.nonce_prefix);
        buf
    }

    pub fn decode(buf: &[u8]) -> PoolResult<Self> {
        if buf.len() < FPC1_HEADER_SIZE {
            return Err(PoolError::Crypto("FPC1 header truncated".to_string()));
        }
        if buf[0..4] != FPC1_MAGIC {
            return Err(PoolError::Crypto("invalid FPC1 magic".to_string()));
        }
        if buf[4] != FPC1_VERSION {
            return Err(PoolError::Crypto(format!(
                "unsupported FPC1 version {}",
                buf[4]
            )));
        }
        let sub_chunk_size = u32::from_le_bytes([buf[8], buf[9], buf[10], buf[11]]);
        if sub_chunk_size == 0 || sub_chunk_size > 16 * 1024 * 1024 {
            return Err(PoolError::Crypto(format!(
                "invalid FPC1 sub_chunk_size {sub_chunk_size}"
            )));
        }
        let plain_len = u64::from_le_bytes([
            buf[12], buf[13], buf[14], buf[15], buf[16], buf[17], buf[18], buf[19],
        ]);
        let mut chunk_salt = [0u8; 16];
        chunk_salt.copy_from_slice(&buf[20..36]);
        let mut nonce_prefix = [0u8; 4];
        nonce_prefix.copy_from_slice(&buf[36..40]);
        Ok(Self {
            sub_chunk_size,
            plain_len,
            chunk_salt,
            nonce_prefix,
        })
    }

    pub fn total_sub_chunks(&self) -> u64 {
        if self.plain_len == 0 {
            1
        } else {
            let cs = self.sub_chunk_size as u64;
            (self.plain_len - 1) / cs + 1
        }
    }

    pub fn expected_encoded_len(&self) -> u64 {
        if self.plain_len == 0 {
            (FPC1_HEADER_SIZE + GCM_TAG_SIZE) as u64
        } else {
            let total = self.total_sub_chunks();
            (FPC1_HEADER_SIZE as u64) + self.plain_len + total * (GCM_TAG_SIZE as u64)
        }
    }
}

pub fn fpc1_subchunk_nonce(prefix: &[u8; 4], sub_idx: u64) -> [u8; 12] {
    let mut nonce = [0u8; 12];
    nonce[0..4].copy_from_slice(prefix);
    nonce[4..12].copy_from_slice(&sub_idx.to_be_bytes());
    nonce
}

pub fn fpc1_subchunk_aad(
    pool_id: &str,
    chunk_hash: &str,
    chunk_salt: &[u8; 16],
    sub_idx: u64,
    is_final: bool,
) -> Vec<u8> {
    let mut aad = Vec::with_capacity(pool_id.len() + chunk_hash.len() + 16 + 8 + 2);
    aad.extend_from_slice(pool_id.as_bytes());
    aad.push(b':');
    aad.extend_from_slice(chunk_hash.as_bytes());
    aad.extend_from_slice(chunk_salt);
    aad.extend_from_slice(&sub_idx.to_be_bytes());
    aad.push(u8::from(is_final));
    aad
}

pub fn encrypt_chunk_fpc1(
    crypto: &PoolCrypto,
    chunk_hash: &str,
    plaintext: &[u8],
) -> PoolResult<Vec<u8>> {
    let chunk_salt = random_bytes::<16>();
    let nonce_prefix = random_bytes::<4>();
    let subkey = crypto.derive_chunk_key(&chunk_salt)?;
    let cipher = Aes256Gcm::new_from_slice(&*subkey)
        .map_err(|e| PoolError::Crypto(format!("aes256 init failed: {e}")))?;

    let header = Fpc1Header {
        sub_chunk_size: FPC1_SUB_CHUNK_SIZE as u32,
        plain_len: plaintext.len() as u64,
        chunk_salt,
        nonce_prefix,
    };

    let mut out = Vec::with_capacity(header.expected_encoded_len() as usize);
    out.extend_from_slice(&header.encode());

    if plaintext.is_empty() {
        let nonce_bytes = fpc1_subchunk_nonce(&nonce_prefix, 0);
        let nonce = Nonce::<U12>::from(nonce_bytes);
        let aad = fpc1_subchunk_aad(crypto.pool_id(), chunk_hash, &chunk_salt, 0, true);
        let ct = cipher
            .encrypt(&nonce, Payload { msg: &[], aad: &aad })
            .map_err(|_| PoolError::Crypto("encrypt empty subchunk failed".to_string()))?;
        out.extend_from_slice(&ct);
        return Ok(out);
    }

    let total_subs = header.total_sub_chunks();
    for (idx, slice) in plaintext.chunks(FPC1_SUB_CHUNK_SIZE).enumerate() {
        let sub_idx = idx as u64;
        let is_final = sub_idx + 1 == total_subs;
        let nonce_bytes = fpc1_subchunk_nonce(&nonce_prefix, sub_idx);
        let nonce = Nonce::<U12>::from(nonce_bytes);
        let aad = fpc1_subchunk_aad(crypto.pool_id(), chunk_hash, &chunk_salt, sub_idx, is_final);
        let ct = cipher
            .encrypt(&nonce, Payload { msg: slice, aad: &aad })
            .map_err(|_| PoolError::Crypto("encrypt subchunk failed".to_string()))?;
        out.extend_from_slice(&ct);
    }

    Ok(out)
}

pub fn decrypt_subchunk_fpc1(
    crypto: &PoolCrypto,
    header: &Fpc1Header,
    subkey: &[u8; 32],
    chunk_hash: &str,
    sub_idx: u64,
    ciphertext_with_tag: &[u8],
) -> PoolResult<Vec<u8>> {
    let total_subs = header.total_sub_chunks();
    if sub_idx >= total_subs {
        return Err(PoolError::Crypto("subchunk index out of range".to_string()));
    }
    let is_final = sub_idx + 1 == total_subs;
    let cipher = Aes256Gcm::new_from_slice(subkey)
        .map_err(|e| PoolError::Crypto(format!("aes256 init failed: {e}")))?;
    let nonce_bytes = fpc1_subchunk_nonce(&header.nonce_prefix, sub_idx);
    let nonce = Nonce::<U12>::from(nonce_bytes);
    let aad = fpc1_subchunk_aad(
        crypto.pool_id(),
        chunk_hash,
        &header.chunk_salt,
        sub_idx,
        is_final,
    );
    cipher
        .decrypt(
            &nonce,
            Payload {
                msg: ciphertext_with_tag,
                aad: &aad,
            },
        )
        .map_err(|_| PoolError::Crypto("chunk authentication failed".to_string()))
}

pub fn verify_and_decrypt_fpc1_full(
    crypto: &PoolCrypto,
    chunk_hash: &str,
    encoded: &[u8],
) -> PoolResult<Vec<u8>> {
    let header = Fpc1Header::decode(encoded)?;
    if encoded.len() as u64 != header.expected_encoded_len() {
        return Err(PoolError::Crypto(format!(
            "FPC1 payload size mismatch: expected {}, got {}",
            header.expected_encoded_len(),
            encoded.len()
        )));
    }
    let subkey = crypto.derive_chunk_key(&header.chunk_salt)?;

    if header.plain_len == 0 {
        let pt = decrypt_subchunk_fpc1(
            crypto,
            &header,
            &subkey,
            chunk_hash,
            0,
            &encoded[FPC1_HEADER_SIZE..],
        )?;
        return Ok(pt);
    }

    let cs = header.sub_chunk_size as usize;
    let total_subs = header.total_sub_chunks();
    let mut out = Vec::with_capacity(header.plain_len as usize);
    let mut pos = FPC1_HEADER_SIZE;
    for sub_idx in 0..total_subs {
        let is_final = sub_idx + 1 == total_subs;
        let plain_sub_len = if is_final {
            (header.plain_len - sub_idx * cs as u64) as usize
        } else {
            cs
        };
        let ct_len = plain_sub_len + GCM_TAG_SIZE;
        let pt = decrypt_subchunk_fpc1(
            crypto,
            &header,
            &subkey,
            chunk_hash,
            sub_idx,
            &encoded[pos..pos + ct_len],
        )?;
        out.extend_from_slice(&pt);
        pos += ct_len;
    }

    let expected_hash = crypto.keyed_content_id(&out)?;
    if expected_hash != chunk_hash {
        return Err(PoolError::Crypto("decrypted chunk HMAC mismatch".to_string()));
    }
    Ok(out)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fpc1SubchunkPlan {
    pub start_sub: u64,
    pub end_sub: u64,
    pub physical_offset: u64,
    pub physical_len: u64,
}

/// Compute the physical byte range inside an `FPC1` blob needed to read
/// `[plain_offset, plain_offset + plain_len)`.
pub fn fpc1_subchunk_plan(
    header: &Fpc1Header,
    plain_offset: u64,
    plain_len: u64,
) -> Option<Fpc1SubchunkPlan> {
    if header.plain_len == 0 || plain_len == 0 || plain_offset >= header.plain_len {
        return None;
    }
    let end = plain_offset.saturating_add(plain_len).min(header.plain_len);
    if end <= plain_offset {
        return None;
    }
    let cs = header.sub_chunk_size as u64;
    let total_subs = header.total_sub_chunks();
    let start_sub = plain_offset / cs;
    let end_sub = (end - 1) / cs;
    let phys_stride = cs + GCM_TAG_SIZE as u64;
    let physical_offset = (FPC1_HEADER_SIZE as u64) + start_sub * phys_stride;

    let mut physical_len = 0u64;
    for sub_idx in start_sub..=end_sub {
        let is_final = sub_idx + 1 == total_subs;
        let sub_plain = if is_final {
            header.plain_len - sub_idx * cs
        } else {
            cs
        };
        physical_len += sub_plain + GCM_TAG_SIZE as u64;
    }

    Some(Fpc1SubchunkPlan {
        start_sub,
        end_sub,
        physical_offset,
        physical_len,
    })
}

pub fn compress_and_encrypt_snapshot(
    raw_db: &[u8],
    crypto: Option<&PoolCrypto>,
    pool_id: &str,
) -> PoolResult<Vec<u8>> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(raw_db)?;
    let gz = encoder.finish()?;

    match crypto {
        Some(c) => {
            let aad = format!("fm-pool-meta-snapshot-v1:{pool_id}");
            encrypt_blob(c.meta_key(), VaultCipher::Aes256Gcm, aad.as_bytes(), &gz)
                .map_err(PoolError::from)
        }
        None => Ok(gz),
    }
}

pub fn decrypt_and_decompress_snapshot(
    blob: &[u8],
    crypto: Option<&PoolCrypto>,
    pool_id: &str,
) -> PoolResult<Vec<u8>> {
    let gz = match crypto {
        Some(c) => {
            let aad = format!("fm-pool-meta-snapshot-v1:{pool_id}");
            decrypt_blob(c.meta_key(), VaultCipher::Aes256Gcm, aad.as_bytes(), blob)?
        }
        None => blob.to_vec(),
    };

    let mut decoder = GzDecoder::new(&gz[..]);
    let mut raw = Vec::new();
    decoder.read_to_end(&mut raw)?;
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_crypto() -> PoolCrypto {
        let salt = [7u8; 16];
        let kdf = KdfParams {
            m_cost: 1024,
            t_cost: 1,
            p_cost: 1,
        };
        PoolCrypto::from_passphrase("pool-test", "hunter2-strong-pass", &salt, kdf).unwrap()
    }

    #[test]
    fn fpc1_encrypt_decrypt_and_subchunk_range_roundtrip() {
        let crypto = test_crypto();
        let plain: Vec<u8> = (0..(200 * 1024 + 123)).map(|i| (i % 251) as u8).collect();
        let cid = chunk_content_id(Some(&crypto), &plain).unwrap();
        let enc = encrypt_chunk_fpc1(&crypto, &cid, &plain).unwrap();

        // Ciphertext hides plaintext bytes and has exact expected size.
        let header = Fpc1Header::decode(&enc[..FPC1_HEADER_SIZE]).unwrap();
        assert_eq!(enc.len() as u64, header.expected_encoded_len());

        let full_pt = verify_and_decrypt_fpc1_full(&crypto, &cid, &enc).unwrap();
        assert_eq!(full_pt, plain);

        // Read middle cross-subchunk range.
        let off = 60 * 1024u64;
        let len = 80 * 1024u64;
        let plan = fpc1_subchunk_plan(&header, off, len).unwrap();
        assert_eq!(plan.start_sub, 0);
        assert_eq!(plan.end_sub, 2);

        let subkey = crypto.derive_chunk_key(&header.chunk_salt).unwrap();
        let cs = header.sub_chunk_size as u64;
        let mut cursor = plan.physical_offset as usize;
        let mut assembled = Vec::new();
        for sub_idx in plan.start_sub..=plan.end_sub {
            let is_final = sub_idx + 1 == header.total_sub_chunks();
            let plain_sub = if is_final {
                (header.plain_len - sub_idx * cs) as usize
            } else {
                cs as usize
            };
            let ct_len = plain_sub + GCM_TAG_SIZE;
            let pt = decrypt_subchunk_fpc1(
                &crypto,
                &header,
                &subkey,
                &cid,
                sub_idx,
                &enc[cursor..cursor + ct_len],
            )
            .unwrap();
            cursor += ct_len;

            let sub_start = sub_idx * cs;
            let slice_start = off.saturating_sub(sub_start) as usize;
            let slice_end = (off + len - sub_start).min(plain_sub as u64) as usize;
            assembled.extend_from_slice(&pt[slice_start..slice_end]);
        }
        assert_eq!(assembled, plain[off as usize..(off + len) as usize]);

        // Tampering ciphertext fails authentication.
        let mut tampered = enc.clone();
        let last = tampered.len() - 1;
        tampered[last] ^= 0xFF;
        assert!(verify_and_decrypt_fpc1_full(&crypto, &cid, &tampered).is_err());
    }

    #[test]
    fn empty_chunk_fpc1_roundtrip() {
        let crypto = test_crypto();
        let cid = chunk_content_id(Some(&crypto), &[]).unwrap();
        let enc = encrypt_chunk_fpc1(&crypto, &cid, &[]).unwrap();
        let pt = verify_and_decrypt_fpc1_full(&crypto, &cid, &enc).unwrap();
        assert!(pt.is_empty());
    }

    #[test]
    fn snapshot_compress_encrypt_roundtrip() {
        let crypto = test_crypto();
        let raw = b"sqlite snapshot bytes repeating repeating repeating 1234567890";
        let enc = compress_and_encrypt_snapshot(raw, Some(&crypto), "pool-test").unwrap();
        let dec = decrypt_and_decompress_snapshot(&enc, Some(&crypto), "pool-test").unwrap();
        assert_eq!(dec, raw);

        let plain_gz = compress_and_encrypt_snapshot(raw, None, "pool-test").unwrap();
        let plain_dec = decrypt_and_decompress_snapshot(&plain_gz, None, "pool-test").unwrap();
        assert_eq!(plain_dec, raw);
    }
}
