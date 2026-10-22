//! Multi-bucket VFS backend for S3 and Aliyun OSS.
//!
//! When an account does not specify a single fixed bucket, the VFS root (`/`)
//! exposes all available buckets as directories. Navigation into `/<bucket>/...`
//! delegates to a cached per-bucket `OpendalFs` instance.

use async_trait::async_trait;
use base64::prelude::*;
use chrono::Utc;
use hmac::{digest::KeyInit, Hmac, Mac};
use parking_lot::RwLock;
use regex::Regex;
use sha1::Sha1;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncRead, AsyncWrite};

use fm_core::{Capabilities, Entry, EntryKind, LocationKind, VfsPath, WriteMode};
use fm_vfs::{Vfs, VfsError, VfsResult};

use crate::opendal_backend::OpendalFs;
use crate::RemoteConfig;

/// Parses configured bucket list if specified as comma/space-separated names.
pub fn parse_configured_buckets(bucket_str: Option<&str>) -> Option<Vec<String>> {
    let s = bucket_str?;
    let buckets: Vec<String> = s
        .split([',', ' ', ';', '\n'])
        .map(|x| x.trim().to_string())
        .filter(|x| !x.is_empty())
        .collect();
    if buckets.is_empty() {
        None
    } else {
        Some(buckets)
    }
}

fn get_s3_base_and_host(config: &RemoteConfig) -> Result<(String, String), VfsError> {
    if let Some(endpoint) = &config.endpoint {
        let trimmed = endpoint.trim().trim_end_matches('/');
        let ep = if !trimmed.starts_with("http://") && !trimmed.starts_with("https://") {
            format!("https://{trimmed}")
        } else {
            trimmed.to_string()
        };
        let parsed = reqwest::Url::parse(&ep).map_err(|e| VfsError::Connection {
            message: format!("invalid S3 endpoint URL: {e}"),
        })?;
        let host = parsed.host_str().unwrap_or("localhost").to_string();
        let host_header = if let Some(port) = parsed.port() {
            format!("{host}:{port}")
        } else {
            host
        };
        Ok((ep, host_header))
    } else {
        let region = config.region.as_deref().unwrap_or("us-east-1");
        if region == "us-east-1" {
            Ok((
                "https://s3.amazonaws.com".to_string(),
                "s3.amazonaws.com".to_string(),
            ))
        } else {
            Ok((
                format!("https://s3.{region}.amazonaws.com"),
                format!("s3.{region}.amazonaws.com"),
            ))
        }
    }
}

fn sign_s3_request(
    method: &str,
    uri_path: &str,
    host_header: &str,
    region: &str,
    key_id: &str,
    key_secret: &str,
    payload_hash: &str,
) -> Result<(String, String, String), VfsError> {
    let now = Utc::now();
    let date_stamp = now.format("%Y%m%d").to_string();
    let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();

    let canonical_headers = format!(
        "host:{host_header}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amz_date}\n"
    );
    let signed_headers = "host;x-amz-content-sha256;x-amz-date";
    let canonical_request = format!(
        "{method}\n{uri_path}\n\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    );

    let mut hasher = Sha256::new();
    hasher.update(canonical_request.as_bytes());
    let canonical_request_hash = hex::encode(hasher.finalize());

    let credential_scope = format!("{date_stamp}/{region}/s3/aws4_request");
    let string_to_sign = format!(
        "AWS4-HMAC-SHA256\n{amz_date}\n{credential_scope}\n{canonical_request_hash}"
    );

    type HmacSha256 = Hmac<Sha256>;
    let mut mac = HmacSha256::new_from_slice(format!("AWS4{key_secret}").as_bytes())
        .map_err(|e| VfsError::Connection { message: e.to_string() })?;
    mac.update(date_stamp.as_bytes());
    let k_date = mac.finalize().into_bytes();

    let mut mac = HmacSha256::new_from_slice(&k_date)
        .map_err(|e| VfsError::Connection { message: e.to_string() })?;
    mac.update(region.as_bytes());
    let k_region = mac.finalize().into_bytes();

    let mut mac = HmacSha256::new_from_slice(&k_region)
        .map_err(|e| VfsError::Connection { message: e.to_string() })?;
    mac.update(b"s3");
    let k_service = mac.finalize().into_bytes();

    let mut mac = HmacSha256::new_from_slice(&k_service)
        .map_err(|e| VfsError::Connection { message: e.to_string() })?;
    mac.update(b"aws4_request");
    let k_signing = mac.finalize().into_bytes();

    let mut mac = HmacSha256::new_from_slice(&k_signing)
        .map_err(|e| VfsError::Connection { message: e.to_string() })?;
    mac.update(string_to_sign.as_bytes());
    let signature = hex::encode(mac.finalize().into_bytes());

    let auth_header = format!(
        "AWS4-HMAC-SHA256 Credential={key_id}/{credential_scope}, SignedHeaders={signed_headers}, Signature={signature}"
    );

    Ok((auth_header, amz_date, host_header.to_string()))
}

/// Lists all buckets for an AWS S3 or compatible service account using SigV4.
pub async fn list_s3_buckets(config: &RemoteConfig) -> Result<Vec<String>, VfsError> {
    let (base_url, host_header) = get_s3_base_and_host(config)?;
    let region = config.region.as_deref().unwrap_or("us-east-1");
    let payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| VfsError::Connection {
            message: format!("failed to build HTTP client: {e}"),
        })?;

    let mut req = client.get(format!("{base_url}/"));

    if let (Some(key_id), Some(key_secret)) = (&config.key_id, &config.key_secret) {
        if !key_id.is_empty() && !key_secret.is_empty() {
            let (auth, amz_date, host) = sign_s3_request(
                "GET",
                "/",
                &host_header,
                region,
                key_id,
                key_secret,
                payload_hash,
            )?;
            req = req
                .header("host", host)
                .header("x-amz-date", amz_date)
                .header("x-amz-content-sha256", payload_hash)
                .header("authorization", auth);
        }
    }

    let resp = req.send().await.map_err(|e| VfsError::Connection {
        message: format!("failed to send S3 ListBuckets request: {e}"),
    })?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(VfsError::Connection {
            message: format!("S3 ListBuckets returned status {status}: {body}"),
        });
    }

    let xml = resp.text().await.map_err(|e| VfsError::Connection {
        message: format!("failed to read S3 ListBuckets response: {e}"),
    })?;

    parse_bucket_names(&xml)
}

/// Create a new bucket in S3.
pub async fn create_s3_bucket(config: &RemoteConfig, bucket: &str) -> Result<(), VfsError> {
    let (base_url, host_header) = get_s3_base_and_host(config)?;
    let region = config.region.as_deref().unwrap_or("us-east-1");
    let payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| VfsError::Connection {
            message: format!("failed to build HTTP client: {e}"),
        })?;

    let uri_path = format!("/{bucket}");
    let mut req = client.put(format!("{base_url}/{bucket}"));

    if let (Some(key_id), Some(key_secret)) = (&config.key_id, &config.key_secret) {
        if !key_id.is_empty() && !key_secret.is_empty() {
            let (auth, amz_date, host) = sign_s3_request(
                "PUT",
                &uri_path,
                &host_header,
                region,
                key_id,
                key_secret,
                payload_hash,
            )?;
            req = req
                .header("host", host)
                .header("x-amz-date", amz_date)
                .header("x-amz-content-sha256", payload_hash)
                .header("authorization", auth);
        }
    }

    let resp = req.send().await.map_err(|e| VfsError::Connection {
        message: format!("failed to send S3 CreateBucket request: {e}"),
    })?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(VfsError::Connection {
            message: format!("S3 CreateBucket returned status {status}: {body}"),
        });
    }

    Ok(())
}

/// Delete an empty bucket in S3.
pub async fn delete_s3_bucket(config: &RemoteConfig, bucket: &str) -> Result<(), VfsError> {
    let (base_url, host_header) = get_s3_base_and_host(config)?;
    let region = config.region.as_deref().unwrap_or("us-east-1");
    let payload_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| VfsError::Connection {
            message: format!("failed to build HTTP client: {e}"),
        })?;

    let uri_path = format!("/{bucket}");
    let mut req = client.delete(format!("{base_url}/{bucket}"));

    if let (Some(key_id), Some(key_secret)) = (&config.key_id, &config.key_secret) {
        if !key_id.is_empty() && !key_secret.is_empty() {
            let (auth, amz_date, host) = sign_s3_request(
                "DELETE",
                &uri_path,
                &host_header,
                region,
                key_id,
                key_secret,
                payload_hash,
            )?;
            req = req
                .header("host", host)
                .header("x-amz-date", amz_date)
                .header("x-amz-content-sha256", payload_hash)
                .header("authorization", auth);
        }
    }

    let resp = req.send().await.map_err(|e| VfsError::Connection {
        message: format!("failed to send S3 DeleteBucket request: {e}"),
    })?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(VfsError::Connection {
            message: format!("S3 DeleteBucket returned status {status}: {body}"),
        });
    }

    Ok(())
}

/// Lists all buckets for an Aliyun OSS account.
pub async fn list_oss_buckets(config: &RemoteConfig) -> Result<Vec<String>, VfsError> {
    let endpoint = config
        .endpoint
        .as_deref()
        .unwrap_or("https://oss-cn-hangzhou.aliyuncs.com");
    let ep = endpoint.trim_end_matches('/');
    let parsed = reqwest::Url::parse(ep).map_err(|e| VfsError::Connection {
        message: format!("invalid OSS endpoint URL: {e}"),
    })?;
    let host = parsed
        .host_str()
        .unwrap_or("oss-cn-hangzhou.aliyuncs.com")
        .to_string();
    let host_header = if let Some(port) = parsed.port() {
        format!("{host}:{port}")
    } else {
        host
    };

    let now = Utc::now();
    let date_str = now.format("%a, %d %b %Y %H:%M:%S GMT").to_string();

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| VfsError::Connection {
            message: format!("failed to build HTTP client: {e}"),
        })?;

    let mut req = client.get(format!("{ep}/"));

    if let (Some(key_id), Some(key_secret)) = (&config.key_id, &config.key_secret) {
        if !key_id.is_empty() && !key_secret.is_empty() {
            let string_to_sign = format!("GET\n\n\n{date_str}\n/");
            type HmacSha1 = Hmac<Sha1>;
            let mut mac = HmacSha1::new_from_slice(key_secret.as_bytes())
                .map_err(|e| VfsError::Connection {
                    message: e.to_string(),
                })?;
            mac.update(string_to_sign.as_bytes());
            let sig = BASE64_STANDARD.encode(mac.finalize().into_bytes());
            let auth = format!("OSS {}:{}", key_id, sig);

            req = req
                .header("Host", &host_header)
                .header("Date", &date_str)
                .header("Authorization", auth);
        }
    }

    let resp = req.send().await.map_err(|e| VfsError::Connection {
        message: format!("failed to send OSS ListBuckets request: {e}"),
    })?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(VfsError::Connection {
            message: format!("OSS ListBuckets returned status {status}: {body}"),
        });
    }

    let xml = resp.text().await.map_err(|e| VfsError::Connection {
        message: format!("failed to read OSS ListBuckets response: {e}"),
    })?;

    parse_bucket_names(&xml)
}

fn parse_bucket_names(xml: &str) -> Result<Vec<String>, VfsError> {
    let re = Regex::new(r"<Bucket>[\s\S]*?<Name>([^<]+)</Name>").map_err(|e| VfsError::Backend {
        path: VfsPath::root(),
        source: std::io::Error::other(e.to_string()),
    })?;

    let mut names = Vec::new();
    for cap in re.captures_iter(xml) {
        if let Some(m) = cap.get(1) {
            names.push(m.as_str().to_string());
        }
    }

    if names.is_empty() {
        let name_re = Regex::new(r"<Name>([^<]+)</Name>").map_err(|e| VfsError::Backend {
            path: VfsPath::root(),
            source: std::io::Error::other(e.to_string()),
        })?;
        for cap in name_re.captures_iter(xml) {
            if let Some(m) = cap.get(1) {
                let name = m.as_str().to_string();
                if !names.contains(&name) {
                    names.push(name);
                }
            }
        }
    }

    names.sort();
    Ok(names)
}

type CachedBucketList = Option<(Vec<String>, Instant)>;

pub struct MultiBucketFs {
    config: RemoteConfig,
    kind: LocationKind,
    operators: Arc<RwLock<HashMap<String, Arc<OpendalFs>>>>,
    bucket_list_cache: Arc<RwLock<CachedBucketList>>,
}

impl MultiBucketFs {
    pub fn new(config: &RemoteConfig) -> Self {
        Self {
            config: config.clone(),
            kind: config.kind,
            operators: Arc::new(RwLock::new(HashMap::new())),
            bucket_list_cache: Arc::new(RwLock::new(None)),
        }
    }

    pub async fn get_bucket_names(&self) -> VfsResult<Vec<String>> {
        // First check if buckets are explicitly provided in config (e.g. comma-separated)
        if let Some(buckets) = parse_configured_buckets(self.config.bucket.as_deref()) {
            if buckets.len() > 1 || (buckets.len() == 1 && !self.config.bucket.as_deref().unwrap_or("").trim().is_empty()) {
                return Ok(buckets);
            }
        }

        // Check cache (valid for 30s)
        {
            let guard = self.bucket_list_cache.read();
            if let Some((buckets, timestamp)) = &*guard {
                if timestamp.elapsed() < Duration::from_secs(30) {
                    return Ok(buckets.clone());
                }
            }
        }

        let buckets = match self.kind {
            LocationKind::S3 => list_s3_buckets(&self.config).await?,
            LocationKind::Oss => list_oss_buckets(&self.config).await?,
            _ => {
                return Err(VfsError::Unsupported {
                    operation: "multi-bucket listing only supported for S3 and OSS",
                })
            }
        };

        *self.bucket_list_cache.write() = Some((buckets.clone(), Instant::now()));
        Ok(buckets)
    }

    fn get_or_create_bucket_fs(&self, bucket: &str) -> VfsResult<Arc<OpendalFs>> {
        if let Some(fs) = self.operators.read().get(bucket) {
            return Ok(fs.clone());
        }

        let mut cfg = self.config.clone();
        cfg.bucket = Some(bucket.to_string());

        let fs = match self.kind {
            LocationKind::S3 => OpendalFs::new_s3(&cfg)?,
            LocationKind::Oss => OpendalFs::new_oss(&cfg)?,
            _ => {
                return Err(VfsError::Unsupported {
                    operation: "multi-bucket only supported for S3 and OSS",
                })
            }
        };

        let arc_fs = Arc::new(fs);
        self.operators
            .write()
            .insert(bucket.to_string(), arc_fs.clone());
        Ok(arc_fs)
    }

    fn split_path<'a>(&self, path: &'a VfsPath) -> Option<(&'a str, VfsPath)> {
        let segs = path.segments();
        if segs.is_empty() {
            None
        } else {
            let bucket = segs[0].as_str();
            let sub = if segs.len() > 1 {
                VfsPath::new(segs[1..].iter().map(|s| s.as_str()))
            } else {
                VfsPath::root()
            };
            Some((bucket, sub))
        }
    }
}

#[async_trait]
impl Vfs for MultiBucketFs {
    fn capabilities(&self) -> Capabilities {
        Capabilities {
            read: true,
            write: true,
            rename: true,
            copy: true,
            mkdir: true,
            remove: true,
            serve_http: false,
            serve_ftp: false,
        }
    }

    async fn list(&self, dir: &VfsPath) -> VfsResult<Vec<Entry>> {
        if dir.is_root() {
            let buckets = self.get_bucket_names().await?;
            let entries = buckets
                .into_iter()
                .map(|b| Entry {
                    name: b.clone(),
                    path: VfsPath::root().join(&b),
                    kind: EntryKind::Dir,
                    size: None,
                    modified: None,
                    mode: None,
                    hidden: false,
                    is_symlink: false,
                    mime: None,
                })
                .collect();
            Ok(entries)
        } else {
            let (bucket, subpath) = self.split_path(dir).ok_or_else(|| VfsError::NotFound {
                path: dir.clone(),
            })?;
            let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
            let mut entries = bucket_fs.list(&subpath).await?;
            for e in &mut entries {
                e.path = dir.join(&e.name);
            }
            Ok(entries)
        }
    }

    async fn list_paged(
        &self,
        dir: &VfsPath,
        page: u32,
        page_size: u32,
    ) -> VfsResult<(Vec<Entry>, bool)> {
        if dir.is_root() {
            let all = self.list(dir).await?;
            let page = page.max(1);
            let page_size = page_size.max(1);
            let skip = ((page - 1) as usize).saturating_mul(page_size as usize);
            let total = all.len();
            let has_more = skip + (page_size as usize) < total;
            let entries = all.into_iter().skip(skip).take(page_size as usize).collect();
            Ok((entries, has_more))
        } else {
            let (bucket, subpath) = self.split_path(dir).ok_or_else(|| VfsError::NotFound {
                path: dir.clone(),
            })?;
            let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
            let (mut entries, has_more) = bucket_fs.list_paged(&subpath, page, page_size).await?;
            for e in &mut entries {
                e.path = dir.join(&e.name);
            }
            Ok((entries, has_more))
        }
    }

    async fn stat(&self, path: &VfsPath) -> VfsResult<Entry> {
        if path.is_root() {
            Ok(Entry {
                name: String::new(),
                path: VfsPath::root(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                is_symlink: false,
                mime: None,
            })
        } else if path.segments().len() == 1 {
            let bucket = &path.segments()[0];
            Ok(Entry {
                name: bucket.clone(),
                path: path.clone(),
                kind: EntryKind::Dir,
                size: None,
                modified: None,
                mode: None,
                hidden: false,
                is_symlink: false,
                mime: None,
            })
        } else {
            let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
                path: path.clone(),
            })?;
            let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
            let mut entry = bucket_fs.stat(&subpath).await?;
            entry.path = path.clone();
            Ok(entry)
        }
    }

    async fn open_read(&self, path: &VfsPath) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;
        if subpath.is_root() {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(
                    std::io::ErrorKind::IsADirectory,
                    "cannot read bucket root as file",
                ),
            });
        }
        let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
        bucket_fs.open_read(&subpath).await
    }

    async fn open_read_range(
        &self,
        path: &VfsPath,
        offset: u64,
        length: Option<u64>,
    ) -> VfsResult<Box<dyn AsyncRead + Send + Unpin>> {
        let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;
        if subpath.is_root() {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(
                    std::io::ErrorKind::IsADirectory,
                    "cannot read bucket root as file",
                ),
            });
        }
        let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
        bucket_fs.open_read_range(&subpath, offset, length).await
    }

    async fn open_write(
        &self,
        path: &VfsPath,
        mode: WriteMode,
    ) -> VfsResult<Box<dyn AsyncWrite + Send + Unpin>> {
        let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;
        if subpath.is_root() {
            return Err(VfsError::Backend {
                path: path.clone(),
                source: std::io::Error::new(
                    std::io::ErrorKind::IsADirectory,
                    "cannot write to bucket root",
                ),
            });
        }
        let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
        bucket_fs.open_write(&subpath, mode).await
    }

    async fn mkdir(&self, path: &VfsPath) -> VfsResult<()> {
        if path.is_root() {
            return Ok(());
        }
        let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;
        if subpath.is_root() {
            if self.kind == LocationKind::S3 {
                create_s3_bucket(&self.config, bucket).await?;
                *self.bucket_list_cache.write() = None;
                return Ok(());
            }
            return Err(VfsError::Unsupported {
                operation: "creating an OSS bucket from the app",
            });
        }
        let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
        bucket_fs.mkdir(&subpath).await
    }

    async fn remove(&self, path: &VfsPath) -> VfsResult<()> {
        let (bucket, subpath) = self.split_path(path).ok_or_else(|| VfsError::NotFound {
            path: path.clone(),
        })?;
        if subpath.is_root()
            && self.kind == LocationKind::S3 {
                delete_s3_bucket(&self.config, bucket).await?;
                *self.bucket_list_cache.write() = None;
                return Ok(());
            }
        let bucket_fs = self.get_or_create_bucket_fs(bucket)?;
        bucket_fs.remove(&subpath).await
    }

    async fn rename(&self, from: &VfsPath, to: &VfsPath) -> VfsResult<()> {
        let (from_bucket, from_sub) =
            self.split_path(from).ok_or_else(|| VfsError::NotFound {
                path: from.clone(),
            })?;
        let (to_bucket, to_sub) = self.split_path(to).ok_or_else(|| VfsError::NotFound {
            path: to.clone(),
        })?;

        if from_bucket != to_bucket {
            return Err(VfsError::Unsupported {
                operation: "cross-bucket rename not supported",
            });
        }

        let bucket_fs = self.get_or_create_bucket_fs(from_bucket)?;
        bucket_fs.rename(&from_sub, &to_sub).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_configured_buckets() {
        assert_eq!(
            parse_configured_buckets(Some("bucket1,bucket2, bucket3")),
            Some(vec!["bucket1".into(), "bucket2".into(), "bucket3".into()])
        );
        assert_eq!(
            parse_configured_buckets(Some("alpha beta gamma")),
            Some(vec!["alpha".into(), "beta".into(), "gamma".into()])
        );
        assert_eq!(parse_configured_buckets(Some("")), None);
        assert_eq!(parse_configured_buckets(None), None);
    }

    #[test]
    fn test_parse_s3_bucket_names() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Buckets>
    <Bucket>
      <Name>my-bucket-zeta</Name>
      <CreationDate>2020-01-01T00:00:00.000Z</CreationDate>
    </Bucket>
    <Bucket>
      <Name>my-bucket-alpha</Name>
      <CreationDate>2020-01-02T00:00:00.000Z</CreationDate>
    </Bucket>
  </Buckets>
</ListAllMyBucketsResult>"#;
        let buckets = parse_bucket_names(xml).unwrap();
        assert_eq!(buckets, vec!["my-bucket-alpha", "my-bucket-zeta"]);
    }

    #[test]
    fn test_parse_oss_bucket_names() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<ListAllMyBucketsResult>
  <Owner>
    <ID>12345</ID>
    <DisplayName>test</DisplayName>
  </Owner>
  <Buckets>
    <Bucket>
      <CreationDate>2014-02-17T11:28:00.000Z</CreationDate>
      <ExtranetEndpoint>oss-cn-hangzhou.aliyuncs.com</ExtranetEndpoint>
      <Location>oss-cn-hangzhou</Location>
      <Name>oss-bucket-2</Name>
      <StorageClass>Standard</StorageClass>
    </Bucket>
    <Bucket>
      <CreationDate>2014-02-17T11:28:00.000Z</CreationDate>
      <ExtranetEndpoint>oss-cn-hangzhou.aliyuncs.com</ExtranetEndpoint>
      <Location>oss-cn-hangzhou</Location>
      <Name>oss-bucket-1</Name>
      <StorageClass>Standard</StorageClass>
    </Bucket>
  </Buckets>
</ListAllMyBucketsResult>"#;
        let buckets = parse_bucket_names(xml).unwrap();
        assert_eq!(buckets, vec!["oss-bucket-1", "oss-bucket-2"]);
    }
}
