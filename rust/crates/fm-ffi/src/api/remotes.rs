use fm_core::LocationKind;
use fm_index::{Database, RemoteRecord};
use fm_remote::RemoteConfig;
use std::path::Path;

#[derive(Debug, Clone)]
pub struct RemoteConfigDto {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub endpoint: Option<String>,
    pub bucket: Option<String>,
    pub region: Option<String>,
    pub access_key_id: Option<String>,
    pub secret_access_key: Option<String>,
    pub host: Option<String>,
    pub port: Option<u16>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub root_path: Option<String>,
    pub path_style: bool,
}

fn parse_kind(s: &str) -> LocationKind {
    match s.to_lowercase().as_str() {
        "s3" => LocationKind::S3,
        "oss" => LocationKind::Oss,
        "webdav" => LocationKind::WebDav,
        "sftp" => LocationKind::Sftp,
        "ftp" => LocationKind::Ftp,
        "ftps" => LocationKind::Ftps,
        "smb" => LocationKind::Smb,
        _ => LocationKind::Local,
    }
}

fn kind_to_str(k: LocationKind) -> String {
    match k {
        LocationKind::S3 => "s3",
        LocationKind::Oss => "oss",
        LocationKind::WebDav => "webdav",
        LocationKind::Sftp => "sftp",
        LocationKind::Ftp => "ftp",
        LocationKind::Ftps => "ftps",
        LocationKind::Smb => "smb",
        LocationKind::Archive => "archive",
        LocationKind::Local => "local",
    }
    .to_string()
}

impl From<RemoteConfigDto> for RemoteConfig {
    fn from(d: RemoteConfigDto) -> Self {
        Self {
            id: d.id,
            kind: parse_kind(&d.kind),
            display_name: d.name,
            endpoint: d.endpoint,
            region: d.region,
            bucket: d.bucket,
            host: d.host,
            port: d.port,
            root: d.root_path.unwrap_or_else(|| "/".to_string()),
            username: d.username,
            password: d.password,
            key_id: d.access_key_id,
            key_secret: d.secret_access_key,
            private_key: None,
            path_style: d.path_style,
            // Managed by the connection layer, never by the UI: save_remote
            // re-attaches the stored pin when a remote is edited.
            host_key_fingerprint: None,
        }
    }
}

impl From<RemoteConfig> for RemoteConfigDto {
    fn from(c: RemoteConfig) -> Self {
        Self {
            id: c.id,
            name: c.display_name,
            kind: kind_to_str(c.kind),
            endpoint: c.endpoint,
            bucket: c.bucket,
            region: c.region,
            access_key_id: c.key_id,
            secret_access_key: c.key_secret,
            host: c.host,
            port: c.port,
            username: c.username,
            password: c.password,
            root_path: Some(c.root),
            path_style: c.path_style,
        }
    }
}

pub async fn test_remote_connection(config: RemoteConfigDto) -> Result<bool, String> {
    let cfg: RemoteConfig = config.into();
    cfg.test_connection().await
}

pub async fn list_remotes(db_path: String) -> Result<Vec<RemoteConfigDto>, String> {
    let db = Database::open(Path::new(&db_path), Path::new(&db_path).parent().unwrap_or(Path::new(".")))
        .map_err(|e| e.to_string())?;
    let records = db.list_remotes().map_err(|e| e.to_string())?;

    let mut list = Vec::new();
    for r in records {
        if let Ok(cfg) = serde_json::from_str::<RemoteConfig>(&r.config_json) {
            list.push(RemoteConfigDto::from(cfg));
        }
    }
    Ok(list)
}

pub async fn save_remote(db_path: String, config: RemoteConfigDto) -> Result<(), String> {
    let db = Database::open(Path::new(&db_path), Path::new(&db_path).parent().unwrap_or(Path::new(".")))
        .map_err(|e| e.to_string())?;
    let mut cfg: RemoteConfig = config.into();
    // The host key pin is managed by the connection layer and never shown
    // in the UI; re-attach the stored one so editing a remote does not
    // silently drop its server verification.
    if cfg.host_key_fingerprint.is_none() {
        if let Ok(records) = db.list_remotes() {
            if let Some(existing) = records.iter().find(|r| r.id == cfg.id) {
                if let Ok(stored) =
                    serde_json::from_str::<RemoteConfig>(&existing.config_json)
                {
                    cfg.host_key_fingerprint = stored.host_key_fingerprint;
                }
            }
        }
    }
    let json = serde_json::to_string(&cfg).map_err(|e| e.to_string())?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;

    let record = RemoteRecord {
        id: cfg.id,
        kind: kind_to_str(cfg.kind),
        display_name: cfg.display_name,
        config_json: json,
        created_at: now,
    };
    db.save_remote(&record).map_err(|e| e.to_string())
}

pub async fn delete_remote(db_path: String, id: String) -> Result<(), String> {
    let db = Database::open(Path::new(&db_path), Path::new(&db_path).parent().unwrap_or(Path::new(".")))
        .map_err(|e| e.to_string())?;
    db.delete_remote(&id).map_err(|e| e.to_string())
}
