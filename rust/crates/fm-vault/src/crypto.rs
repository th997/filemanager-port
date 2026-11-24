use crate::error::{VaultError, VaultResult};
use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes128Gcm, Aes256Gcm, Nonce,
};
use aes_gcm::aead::array::typenum::U12;
use argon2::Argon2;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use hkdf::Hkdf;
use hmac::{digest::KeyInit as HmacKeyInit, Hmac, Mac};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::Path;
use zeroize::Zeroizing;

pub const FPV1_MAGIC: [u8; 4] = *b"FPV1";
pub const FPV1_VERSION: u8 = 1;
pub const FPB1_MAGIC: [u8; 4] = *b"FPB1";
pub const CHUNK_SIZE: usize = 64 * 1024;
pub const TAG_SIZE: usize = 16;
pub const FPV1_HEADER_SIZE: usize = 40;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VaultCipher {
    None,
    Aes128Gcm,
    Aes256Gcm,
}

impl Default for VaultCipher {
    fn default() -> Self {
        Self::Aes128Gcm
    }
}

impl VaultCipher {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::Aes128Gcm => "aes128gcm",
            Self::Aes256Gcm => "aes256gcm",
        }
    }

    pub fn from_str(s: &str) -> VaultResult<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "none" => Ok(Self::None),
            "aes128gcm" | "aes-128-gcm" => Ok(Self::Aes128Gcm),
            "aes256gcm" | "aes-256-gcm" => Ok(Self::Aes256Gcm),
            other => Err(VaultError::Unsupported(format!("unknown cipher: {other}"))),
        }
    }

    pub fn cipher_id(self) -> u8 {
        match self {
            Self::None => 0,
            Self::Aes128Gcm => 1,
            Self::Aes256Gcm => 2,
        }
    }

    pub fn from_cipher_id(id: u8) -> VaultResult<Self> {
        match id {
            0 => Ok(Self::None),
            1 => Ok(Self::Aes128Gcm),
            2 => Ok(Self::Aes256Gcm),
            other => Err(VaultError::Crypto(format!("unsupported cipher id {other}"))),
        }
    }

    pub fn is_encrypted(self) -> bool {
        !matches!(self, Self::None)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VaultAuthMode {
    Password,
    System,
}

impl Default for VaultAuthMode {
    fn default() -> Self {
        Self::Password
    }
}

impl VaultAuthMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Password => "password",
            Self::System => "system",
        }
    }

    pub fn from_str(s: &str) -> VaultResult<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "password" => Ok(Self::Password),
            "system" => Ok(Self::System),
            other => Err(VaultError::Unsupported(format!(
                "unknown auth mode: {other}"
            ))),
        }
    }
}

pub fn validate_password(password: &str) -> VaultResult<()> {
    let char_len = password.chars().count();
    if char_len < 8 || char_len > 128 {
        return Err(VaultError::InvalidPassword(
            "password must be 8 to 128 characters".to_string(),
        ));
    }
    Ok(())
}

pub fn random_bytes<const N: usize>() -> [u8; N] {
    let mut buf = [0u8; N];
    OsRng.fill_bytes(&mut buf);
    buf
}

pub fn hash_name(salt: &[u8], name: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"fm-vault-name-v1:");
    hasher.update(salt);
    hasher.update(b":");
    hasher.update(name.as_bytes());
    hex::encode(hasher.finalize())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdfParams {
    pub m_cost: u32,
    pub t_cost: u32,
    pub p_cost: u32,
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            m_cost: argon2::Params::DEFAULT_M_COST,
            t_cost: argon2::Params::DEFAULT_T_COST,
            p_cost: argon2::Params::DEFAULT_P_COST,
        }
    }
}

pub fn derive_kek_argon2id_with_params(
    password: &str,
    salt: &[u8],
    params: KdfParams,
) -> VaultResult<Zeroizing<[u8; 32]>> {
    let p = argon2::Params::new(params.m_cost, params.t_cost, params.p_cost, Some(32))
        .map_err(|e| VaultError::Crypto(format!("invalid argon2 params: {e}")))?;
    let a2 = Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, p);
    let mut out = Zeroizing::new([0u8; 32]);
    a2.hash_password_into(password.as_bytes(), salt, &mut *out)
        .map_err(|e| VaultError::Crypto(format!("argon2id failed: {e}")))?;
    Ok(out)
}

pub fn derive_kek_argon2id(password: &str, salt: &[u8]) -> VaultResult<Zeroizing<[u8; 32]>> {
    derive_kek_argon2id_with_params(password, salt, KdfParams::default())
}

pub fn password_verifier_hmac(kek: &[u8; 32]) -> VaultResult<String> {
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = <HmacSha256 as HmacKeyInit>::new_from_slice(kek)
        .map_err(|e| VaultError::Crypto(format!("hmac init failed: {e}")))?;
    mac.update(b"fm-vault-pwd-verify-v1");
    Ok(hex::encode(mac.finalize().into_bytes()))
}

pub fn system_dek_verifier(dek: &[u8; 32]) -> VaultResult<String> {
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = <HmacSha256 as HmacKeyInit>::new_from_slice(dek)
        .map_err(|e| VaultError::Crypto(format!("hmac init failed: {e}")))?;
    mac.update(b"fm-vault-system-dek-v1");
    Ok(hex::encode(mac.finalize().into_bytes()))
}

pub fn constant_time_eq_hex(a: &str, b: &str) -> bool {
    let ab = a.as_bytes();
    let bb = b.as_bytes();
    if ab.len() != bb.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in ab.iter().zip(bb.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

pub fn wrap_dek(kek: &[u8; 32], dek: &[u8; 32], aad: &[u8]) -> VaultResult<String> {
    let cipher = Aes256Gcm::new_from_slice(kek)
        .map_err(|e| VaultError::Crypto(format!("wrap cipher init failed: {e}")))?;
    let nonce_bytes = random_bytes::<12>();
    let nonce = Nonce::<U12>::from(nonce_bytes);
    let ct = cipher
        .encrypt(&nonce, Payload { msg: dek, aad })
        .map_err(|_| VaultError::Crypto("dek wrap failed".to_string()))?;
    let mut out = Vec::with_capacity(12 + ct.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ct);
    Ok(STANDARD.encode(out))
}

pub fn unwrap_dek(
    kek: &[u8; 32],
    wrapped_b64: &str,
    aad: &[u8],
) -> VaultResult<Zeroizing<[u8; 32]>> {
    let raw = STANDARD
        .decode(wrapped_b64.trim())
        .map_err(|e| VaultError::Crypto(format!("invalid wrapped dek base64: {e}")))?;
    if raw.len() < 12 + 16 {
        return Err(VaultError::Crypto("wrapped dek too short".to_string()));
    }
    let mut nonce_bytes = [0u8; 12];
    nonce_bytes.copy_from_slice(&raw[..12]);
    let nonce = Nonce::<U12>::from(nonce_bytes);
    let cipher = Aes256Gcm::new_from_slice(kek)
        .map_err(|e| VaultError::Crypto(format!("unwrap cipher init failed: {e}")))?;
    let pt = cipher
        .decrypt(
            &nonce,
            Payload {
                msg: &raw[12..],
                aad,
            },
        )
        .map_err(|_| VaultError::WrongCredential)?;
    if pt.len() != 32 {
        return Err(VaultError::Crypto("unwrapped dek length mismatch".to_string()));
    }
    let mut dek = Zeroizing::new([0u8; 32]);
    dek.copy_from_slice(&pt);
    Ok(dek)
}

pub fn derive_subkey(dek: &[u8; 32], salt: &[u8; 16], info: &[u8]) -> VaultResult<Zeroizing<[u8; 32]>> {
    let hk = Hkdf::<Sha256>::new(Some(salt), dek);
    let mut out = Zeroizing::new([0u8; 32]);
    hk.expand(info, &mut *out)
        .map_err(|_| VaultError::Crypto("hkdf expand failed".to_string()))?;
    Ok(out)
}

fn encrypt_aead(
    cipher_kind: VaultCipher,
    key: &[u8; 32],
    nonce_bytes: [u8; 12],
    aad: &[u8],
    plaintext: &[u8],
) -> VaultResult<Vec<u8>> {
    let nonce = Nonce::<U12>::from(nonce_bytes);
    let payload = Payload {
        msg: plaintext,
        aad,
    };
    match cipher_kind {
        VaultCipher::Aes128Gcm => {
            let cipher = Aes128Gcm::new_from_slice(&key[..16])
                .map_err(|e| VaultError::Crypto(format!("aes128 init: {e}")))?;
            cipher
                .encrypt(&nonce, payload)
                .map_err(|_| VaultError::Crypto("aes128 encrypt failed".to_string()))
        }
        VaultCipher::Aes256Gcm => {
            let cipher = Aes256Gcm::new_from_slice(key)
                .map_err(|e| VaultError::Crypto(format!("aes256 init: {e}")))?;
            cipher
                .encrypt(&nonce, payload)
                .map_err(|_| VaultError::Crypto("aes256 encrypt failed".to_string()))
        }
        VaultCipher::None => Err(VaultError::Crypto("cannot AEAD encrypt with none cipher".to_string())),
    }
}

fn decrypt_aead(
    cipher_kind: VaultCipher,
    key: &[u8; 32],
    nonce_bytes: [u8; 12],
    aad: &[u8],
    ciphertext: &[u8],
) -> VaultResult<Vec<u8>> {
    let nonce = Nonce::<U12>::from(nonce_bytes);
    let payload = Payload {
        msg: ciphertext,
        aad,
    };
    match cipher_kind {
        VaultCipher::Aes128Gcm => {
            let cipher = Aes128Gcm::new_from_slice(&key[..16])
                .map_err(|e| VaultError::Crypto(format!("aes128 init: {e}")))?;
            cipher
                .decrypt(&nonce, payload)
                .map_err(|_| VaultError::Crypto("authentication failed".to_string()))
        }
        VaultCipher::Aes256Gcm => {
            let cipher = Aes256Gcm::new_from_slice(key)
                .map_err(|e| VaultError::Crypto(format!("aes256 init: {e}")))?;
            cipher
                .decrypt(&nonce, payload)
                .map_err(|_| VaultError::Crypto("authentication failed".to_string()))
        }
        VaultCipher::None => Err(VaultError::Crypto("cannot AEAD decrypt with none cipher".to_string())),
    }
}

pub fn encrypt_blob(
    dek: &[u8; 32],
    cipher_kind: VaultCipher,
    aad: &[u8],
    plaintext: &[u8],
) -> VaultResult<Vec<u8>> {
    if !cipher_kind.is_encrypted() {
        return Ok(plaintext.to_vec());
    }
    let salt = random_bytes::<16>();
    let nonce = random_bytes::<12>();
    let key = derive_subkey(dek, &salt, b"fm-vault-blob-v1")?;
    let mut full_aad = Vec::with_capacity(aad.len() + 16 + 1);
    full_aad.extend_from_slice(aad);
    full_aad.extend_from_slice(&salt);
    full_aad.push(cipher_kind.cipher_id());
    let ct = encrypt_aead(cipher_kind, &key, nonce, &full_aad, plaintext)?;
    let mut out = Vec::with_capacity(4 + 1 + 16 + 12 + ct.len());
    out.extend_from_slice(&FPB1_MAGIC);
    out.push(cipher_kind.cipher_id());
    out.extend_from_slice(&salt);
    out.extend_from_slice(&nonce);
    out.extend_from_slice(&ct);
    Ok(out)
}

pub fn decrypt_blob(
    dek: &[u8; 32],
    expected_cipher: VaultCipher,
    aad: &[u8],
    data: &[u8],
) -> VaultResult<Vec<u8>> {
    if !expected_cipher.is_encrypted() {
        return Ok(data.to_vec());
    }
    if data.len() < 4 + 1 + 16 + 12 + TAG_SIZE {
        return Err(VaultError::Crypto("encrypted blob too short".to_string()));
    }
    if data[..4] != FPB1_MAGIC {
        return Err(VaultError::Crypto("invalid blob magic".to_string()));
    }
    let cipher_kind = VaultCipher::from_cipher_id(data[4])?;
    if cipher_kind != expected_cipher {
        return Err(VaultError::Crypto("blob cipher mismatch".to_string()));
    }
    let mut salt = [0u8; 16];
    salt.copy_from_slice(&data[5..21]);
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&data[21..33]);
    let key = derive_subkey(dek, &salt, b"fm-vault-blob-v1")?;
    let mut full_aad = Vec::with_capacity(aad.len() + 16 + 1);
    full_aad.extend_from_slice(aad);
    full_aad.extend_from_slice(&salt);
    full_aad.push(cipher_kind.cipher_id());
    decrypt_aead(cipher_kind, &key, nonce, &full_aad, &data[33..])
}

#[derive(Debug, Clone)]
pub struct Fpv1Header {
    pub cipher: VaultCipher,
    pub chunk_size: u32,
    pub plaintext_len: u64,
    pub file_salt: [u8; 16],
    pub nonce_prefix: [u8; 4],
}

impl Fpv1Header {
    pub fn encode(&self) -> [u8; FPV1_HEADER_SIZE] {
        let mut buf = [0u8; FPV1_HEADER_SIZE];
        buf[0..4].copy_from_slice(&FPV1_MAGIC);
        buf[4] = FPV1_VERSION;
        buf[5] = self.cipher.cipher_id();
        buf[6] = 0;
        buf[7] = 0;
        buf[8..12].copy_from_slice(&self.chunk_size.to_le_bytes());
        buf[12..20].copy_from_slice(&self.plaintext_len.to_le_bytes());
        buf[20..36].copy_from_slice(&self.file_salt);
        buf[36..40].copy_from_slice(&self.nonce_prefix);
        buf
    }

    pub fn decode(buf: &[u8; FPV1_HEADER_SIZE]) -> VaultResult<Self> {
        if buf[0..4] != FPV1_MAGIC {
            return Err(VaultError::Crypto("invalid FPV1 magic".to_string()));
        }
        if buf[4] != FPV1_VERSION {
            return Err(VaultError::Crypto(format!(
                "unsupported FPV1 version {}",
                buf[4]
            )));
        }
        let cipher = VaultCipher::from_cipher_id(buf[5])?;
        if !cipher.is_encrypted() {
            return Err(VaultError::Crypto("FPV1 header cannot have none cipher".to_string()));
        }
        let chunk_size = u32::from_le_bytes([buf[8], buf[9], buf[10], buf[11]]);
        if chunk_size == 0 || chunk_size > 16 * 1024 * 1024 {
            return Err(VaultError::Crypto(format!(
                "invalid FPV1 chunk size {chunk_size}"
            )));
        }
        let plaintext_len = u64::from_le_bytes([
            buf[12], buf[13], buf[14], buf[15], buf[16], buf[17], buf[18], buf[19],
        ]);
        let mut file_salt = [0u8; 16];
        file_salt.copy_from_slice(&buf[20..36]);
        let mut nonce_prefix = [0u8; 4];
        nonce_prefix.copy_from_slice(&buf[36..40]);
        Ok(Self {
            cipher,
            chunk_size,
            plaintext_len,
            file_salt,
            nonce_prefix,
        })
    }

    pub fn total_chunks(&self) -> u64 {
        if self.plaintext_len == 0 {
            1
        } else {
            let cs = self.chunk_size as u64;
            (self.plaintext_len - 1) / cs + 1
        }
    }
}

pub fn chunk_nonce(prefix: &[u8; 4], chunk_idx: u64) -> [u8; 12] {
    let mut nonce = [0u8; 12];
    nonce[0..4].copy_from_slice(prefix);
    nonce[4..12].copy_from_slice(&chunk_idx.to_be_bytes());
    nonce
}

pub fn chunk_aad(vault_id: &str, file_salt: &[u8; 16], chunk_idx: u64, is_final: bool) -> Vec<u8> {
    let mut aad = Vec::with_capacity(vault_id.len() + 16 + 8 + 1);
    aad.extend_from_slice(vault_id.as_bytes());
    aad.extend_from_slice(file_salt);
    aad.extend_from_slice(&chunk_idx.to_be_bytes());
    aad.push(u8::from(is_final));
    aad
}

pub fn read_fpv1_header(file: &mut std::fs::File) -> VaultResult<Fpv1Header> {
    file.seek(SeekFrom::Start(0))?;
    let mut buf = [0u8; FPV1_HEADER_SIZE];
    file.read_exact(&mut buf)?;
    Fpv1Header::decode(&buf)
}

pub struct Fpv1SyncWriter {
    file: std::fs::File,
    vault_id: String,
    header: Fpv1Header,
    file_key: Zeroizing<[u8; 32]>,
    chunk_idx: u64,
    plaintext_len: u64,
}

impl Fpv1SyncWriter {
    pub fn create(
        tmp_path: &Path,
        vault_id: &str,
        dek: &[u8; 32],
        cipher: VaultCipher,
    ) -> VaultResult<Self> {
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        let mut file = opts.open(tmp_path)?;
        let file_salt = random_bytes::<16>();
        let nonce_prefix = random_bytes::<4>();
        let file_key = derive_subkey(dek, &file_salt, b"fm-vault-file-v1")?;
        let header = Fpv1Header {
            cipher,
            chunk_size: CHUNK_SIZE as u32,
            plaintext_len: 0,
            file_salt,
            nonce_prefix,
        };
        file.write_all(&header.encode())?;
        Ok(Self {
            file,
            vault_id: vault_id.to_string(),
            header,
            file_key,
            chunk_idx: 0,
            plaintext_len: 0,
        })
    }

    pub fn write_chunk(&mut self, plaintext: &[u8], is_final: bool) -> VaultResult<()> {
        let nonce = chunk_nonce(&self.header.nonce_prefix, self.chunk_idx);
        let aad = chunk_aad(
            &self.vault_id,
            &self.header.file_salt,
            self.chunk_idx,
            is_final,
        );
        let ct = encrypt_aead(self.header.cipher, &self.file_key, nonce, &aad, plaintext)?;
        self.file.write_all(&ct)?;
        self.plaintext_len = self.plaintext_len.saturating_add(plaintext.len() as u64);
        self.chunk_idx = self.chunk_idx.saturating_add(1);
        Ok(())
    }

    pub fn finalize(mut self) -> VaultResult<u64> {
        self.header.plaintext_len = self.plaintext_len;
        let encoded = self.header.encode();
        self.file.seek(SeekFrom::Start(0))?;
        self.file.write_all(&encoded)?;
        self.file.flush()?;
        self.file.sync_data()?;
        Ok(self.plaintext_len)
    }
}

pub fn stream_fpv1_range<F>(
    file: &mut std::fs::File,
    vault_id: &str,
    dek: &[u8; 32],
    offset: u64,
    length: Option<u64>,
    mut on_chunk: F,
) -> io::Result<()>
where
    F: FnMut(&[u8]) -> io::Result<()>,
{
    let header = read_fpv1_header(file).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let file_key = derive_subkey(dek, &header.file_salt, b"fm-vault-file-v1")
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    if header.plaintext_len == 0 {
        // Still verify the 0-byte final chunk tag to detect truncation/tampering.
        let mut ct = [0u8; TAG_SIZE];
        file.seek(SeekFrom::Start(FPV1_HEADER_SIZE as u64))?;
        file.read_exact(&mut ct)?;
        let nonce = chunk_nonce(&header.nonce_prefix, 0);
        let aad = chunk_aad(vault_id, &header.file_salt, 0, true);
        let _ = decrypt_aead(header.cipher, &file_key, nonce, &aad, &ct)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        return Ok(());
    }

    if offset >= header.plaintext_len {
        return Ok(());
    }

    let end = match length {
        Some(len) => offset.saturating_add(len).min(header.plaintext_len),
        None => header.plaintext_len,
    };
    if end <= offset {
        return Ok(());
    }

    let cs = header.chunk_size as u64;
    let start_chunk = offset / cs;
    let end_chunk = (end - 1) / cs;
    let total_chunks = header.total_chunks();

    let phys_stride = cs + TAG_SIZE as u64;
    let seek_pos = (FPV1_HEADER_SIZE as u64) + start_chunk * phys_stride;
    file.seek(SeekFrom::Start(seek_pos))?;

    let mut ct_buf = vec![0u8; cs as usize + TAG_SIZE];
    for chunk_idx in start_chunk..=end_chunk {
        let is_final = chunk_idx + 1 == total_chunks;
        let plain_chunk_len = if is_final {
            let rem = header.plaintext_len - chunk_idx * cs;
            rem as usize
        } else {
            cs as usize
        };
        let ct_len = plain_chunk_len + TAG_SIZE;
        file.read_exact(&mut ct_buf[..ct_len])?;

        let nonce = chunk_nonce(&header.nonce_prefix, chunk_idx);
        let aad = chunk_aad(vault_id, &header.file_salt, chunk_idx, is_final);
        let pt = decrypt_aead(header.cipher, &file_key, nonce, &aad, &ct_buf[..ct_len])
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        let chunk_start_off = chunk_idx * cs;
        let slice_start = if offset > chunk_start_off {
            (offset - chunk_start_off) as usize
        } else {
            0
        };
        let slice_end = (end - chunk_start_off).min(plain_chunk_len as u64) as usize;
        if slice_end > slice_start {
            on_chunk(&pt[slice_start..slice_end])?;
        }
    }
    Ok(())
}

pub fn stream_fpv1_to_writer<F>(
    file: &mut std::fs::File,
    vault_id: &str,
    dek: &[u8; 32],
    on_chunk: F,
) -> io::Result<()>
where
    F: FnMut(&[u8]) -> io::Result<()>,
{
    stream_fpv1_range(file, vault_id, dek, 0, None, on_chunk)
}

pub fn decrypt_fpv1_range_to_vec(
    file: &mut std::fs::File,
    vault_id: &str,
    dek: &[u8; 32],
    offset: u64,
    length: Option<u64>,
) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    stream_fpv1_range(file, vault_id, dek, offset, length, |chunk| {
        out.extend_from_slice(chunk);
        Ok(())
    })?;
    Ok(out)
}

struct ChannelAsyncReader {
    rx: tokio::sync::mpsc::Receiver<io::Result<Vec<u8>>>,
    current: Option<(Vec<u8>, usize)>,
}

impl tokio::io::AsyncRead for ChannelAsyncReader {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<io::Result<()>> {
        loop {
            if let Some((ref chunk, ref mut pos)) = self.current {
                let avail = chunk.len() - *pos;
                if avail > 0 {
                    let take = avail.min(buf.remaining());
                    buf.put_slice(&chunk[*pos..*pos + take]);
                    *pos += take;
                    if *pos >= chunk.len() {
                        self.current = None;
                    }
                    return std::task::Poll::Ready(Ok(()));
                }
                self.current = None;
            }
            match self.rx.poll_recv(cx) {
                std::task::Poll::Ready(Some(Ok(bytes))) => {
                    if !bytes.is_empty() {
                        self.current = Some((bytes, 0));
                    }
                }
                std::task::Poll::Ready(Some(Err(e))) => {
                    return std::task::Poll::Ready(Err(e));
                }
                std::task::Poll::Ready(None) => {
                    return std::task::Poll::Ready(Ok(()));
                }
                std::task::Poll::Pending => return std::task::Poll::Pending,
            }
        }
    }
}

/// Streams a byte range from an FPV1 encrypted file using constant memory (~256 KiB).
pub fn open_fpv1_range_stream(
    obj_path: std::path::PathBuf,
    vault_id: String,
    dek: Zeroizing<[u8; 32]>,
    offset: u64,
    length: Option<u64>,
) -> Box<dyn tokio::io::AsyncRead + Send + Unpin> {
    let (tx, rx) = tokio::sync::mpsc::channel::<io::Result<Vec<u8>>>(4);

    tokio::task::spawn_blocking(move || {
        let send_err = |err: io::Error| {
            let _ = tx.blocking_send(Err(err));
        };

        let mut file = match std::fs::File::open(&obj_path) {
            Ok(f) => f,
            Err(e) => {
                send_err(e);
                return;
            }
        };
        let header = match read_fpv1_header(&mut file) {
            Ok(h) => h,
            Err(e) => {
                send_err(io::Error::new(io::ErrorKind::InvalidData, e));
                return;
            }
        };
        let file_key = match derive_subkey(&dek, &header.file_salt, b"fm-vault-file-v1") {
            Ok(k) => k,
            Err(e) => {
                send_err(io::Error::new(io::ErrorKind::InvalidData, e));
                return;
            }
        };

        if header.plaintext_len == 0 {
            let mut ct = [0u8; TAG_SIZE];
            if let Err(e) = file.seek(SeekFrom::Start(FPV1_HEADER_SIZE as u64)) {
                send_err(e);
                return;
            }
            if let Err(e) = file.read_exact(&mut ct) {
                send_err(e);
                return;
            }
            let nonce = chunk_nonce(&header.nonce_prefix, 0);
            let aad = chunk_aad(&vault_id, &header.file_salt, 0, true);
            if let Err(e) = decrypt_aead(header.cipher, &file_key, nonce, &aad, &ct) {
                send_err(io::Error::new(io::ErrorKind::InvalidData, e));
            }
            return;
        }

        if offset >= header.plaintext_len {
            return;
        }
        let end = match length {
            Some(len) => offset.saturating_add(len).min(header.plaintext_len),
            None => header.plaintext_len,
        };
        if end <= offset {
            return;
        }

        let cs = header.chunk_size as u64;
        let start_chunk = offset / cs;
        let end_chunk = (end - 1) / cs;
        let total_chunks = header.total_chunks();
        let phys_stride = cs + TAG_SIZE as u64;
        let seek_pos = (FPV1_HEADER_SIZE as u64) + start_chunk * phys_stride;
        if let Err(e) = file.seek(SeekFrom::Start(seek_pos)) {
            send_err(e);
            return;
        }

        let mut ct_buf = vec![0u8; cs as usize + TAG_SIZE];
        for chunk_idx in start_chunk..=end_chunk {
            let is_final = chunk_idx + 1 == total_chunks;
            let plain_chunk_len = if is_final {
                (header.plaintext_len - chunk_idx * cs) as usize
            } else {
                cs as usize
            };
            let ct_len = plain_chunk_len + TAG_SIZE;
            if let Err(e) = file.read_exact(&mut ct_buf[..ct_len]) {
                send_err(e);
                return;
            }
            let nonce = chunk_nonce(&header.nonce_prefix, chunk_idx);
            let aad = chunk_aad(&vault_id, &header.file_salt, chunk_idx, is_final);
            let pt = match decrypt_aead(header.cipher, &file_key, nonce, &aad, &ct_buf[..ct_len]) {
                Ok(p) => p,
                Err(e) => {
                    send_err(io::Error::new(io::ErrorKind::InvalidData, e));
                    return;
                }
            };

            let chunk_start_off = chunk_idx * cs;
            let slice_start = if offset > chunk_start_off {
                (offset - chunk_start_off) as usize
            } else {
                0
            };
            let slice_end = (end - chunk_start_off).min(plain_chunk_len as u64) as usize;
            if slice_end > slice_start {
                if tx
                    .blocking_send(Ok(pt[slice_start..slice_end].to_vec()))
                    .is_err()
                {
                    return;
                }
            }
        }
    });

    Box::new(ChannelAsyncReader { rx, current: None })
}

/// Encrypts a portable configuration/migration JSON payload with Argon2id + AES-256-GCM.
/// Returns base64-encoded `(salt, nonce, ciphertext)` strings.
pub fn encrypt_portable_secret(
    plaintext: &[u8],
    password: &str,
) -> VaultResult<(String, String, String)> {
    if password.is_empty() {
        return Err(VaultError::InvalidPassword(
            "migration password cannot be empty".to_string(),
        ));
    }
    let salt: [u8; 16] = random_bytes();
    let nonce: [u8; 12] = random_bytes();
    let key = derive_kek_argon2id_with_params(password, &salt, KdfParams::default())?;
    let ct = encrypt_aead(
        VaultCipher::Aes256Gcm,
        &key,
        nonce,
        b"fp-migration-v1",
        plaintext,
    )?;
    Ok((
        STANDARD.encode(salt),
        STANDARD.encode(nonce),
        STANDARD.encode(ct),
    ))
}

/// Decrypts a portable payload created by [`encrypt_portable_secret`].
pub fn decrypt_portable_secret(
    salt_b64: &str,
    nonce_b64: &str,
    ciphertext_b64: &str,
    password: &str,
) -> VaultResult<Vec<u8>> {
    if password.is_empty() {
        return Err(VaultError::InvalidPassword(
            "migration password cannot be empty".to_string(),
        ));
    }
    let salt = STANDARD
        .decode(salt_b64.trim())
        .map_err(|_| VaultError::Crypto("invalid migration salt".to_string()))?;
    let nonce_vec = STANDARD
        .decode(nonce_b64.trim())
        .map_err(|_| VaultError::Crypto("invalid migration nonce".to_string()))?;
    let nonce: [u8; 12] = nonce_vec
        .try_into()
        .map_err(|_| VaultError::Crypto("invalid migration nonce length".to_string()))?;
    let ct = STANDARD
        .decode(ciphertext_b64.trim())
        .map_err(|_| VaultError::Crypto("invalid migration ciphertext".to_string()))?;
    let key = derive_kek_argon2id_with_params(password, &salt, KdfParams::default())?;
    decrypt_aead(
        VaultCipher::Aes256Gcm,
        &key,
        nonce,
        b"fp-migration-v1",
        &ct,
    )
}

