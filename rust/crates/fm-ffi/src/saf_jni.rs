//! Synchronous JNI bridge for the Android SAF DocumentsProvider.
//!
//! The provider runs in the app process without a Flutter engine, so it cannot
//! reach the Dart services. These exports reuse the same async VFS API the UI
//! uses, blocked on a dedicated runtime. Only listing/stat/read-export are
//! exposed; remote roots stay read-only through SAF.

use jni::objects::{JClass, JString};
use jni::sys::jstring;
use jni::JNIEnv;
use serde_json::{json, Value};
use std::sync::OnceLock;
use tokio::runtime::Runtime;

use crate::api::{file_manager, metadata, remotes};
use crate::registry::VfsRegistry;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();

fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("failed to build SAF bridge runtime")
    })
}

fn entry_json(e: &file_manager::EntryDto) -> Value {
    json!({
        "name": e.name,
        "path": e.path,
        "is_dir": e.is_dir,
        "size": e.size,
        "modified_millis": e.modified_millis,
        "hidden": e.hidden,
    })
}

// docIds arrive from untrusted intents; a ".." segment must not climb out of
// the configured remote root on the server side.
fn safe_rel(path: &str) -> bool {
    path.split('/').all(|s| s != "..")
}

fn safe_root(root: &str) -> bool {
    match root.strip_prefix("remote://") {
        Some(id) => {
            !id.is_empty()
                && id
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        }
        None => false,
    }
}

fn dispatch(db_path: &str, req: &Value) -> Result<Value, String> {
    let method = req["method"].as_str().ok_or("missing method")?;
    VfsRegistry::global().set_database_path(db_path.to_string());
    match method {
        "remotes" => {
            let list = runtime().block_on(remotes::list_remotes(db_path.to_string()))?;
            // Credentials never cross into the provider: roots only need identity.
            Ok(Value::Array(
                list.iter()
                    .map(|r| json!({"id": r.id, "name": r.name, "kind": r.kind}))
                    .collect(),
            ))
        }
        "bookmarks" => {
            let list = runtime().block_on(metadata::list_bookmarks(db_path.to_string()))?;
            Ok(Value::Array(
                list.iter()
                    .map(|b| json!({
                        "id": b.id,
                        "name": b.name,
                        "root": b.root,
                        "path": b.path,
                    }))
                    .collect(),
            ))
        }
        "list" | "stat" | "export" => {
            let root = req["root"].as_str().ok_or("missing root")?;
            let path = req["path"].as_str().ok_or("missing path")?;
            if !safe_root(root) || !safe_rel(path) {
                return Err("invalid remote root or path".to_string());
            }
            match method {
                "list" => {
                    let entries =
                        runtime().block_on(file_manager::list_dir(root.to_string(), path.to_string()))?;
                    Ok(Value::Array(entries.iter().map(entry_json).collect()))
                }
                "stat" => {
                    let e = runtime()
                        .block_on(file_manager::stat_entry(root.to_string(), path.to_string()))?;
                    Ok(entry_json(&e))
                }
                _ => {
                    let cache_dir = req["cache_dir"].as_str().ok_or("missing cache_dir")?;
                    let native = runtime().block_on(file_manager::export_to_native(
                        root.to_string(),
                        path.to_string(),
                        cache_dir.to_string(),
                    ))?;
                    Ok(Value::String(native))
                }
            }
        }
        other => Err(format!("unknown method: {other}")),
    }
}

#[no_mangle]
pub extern "system" fn Java_com_github_th997_filemanager_SafBridge_nativeCall<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    db_path: JString<'local>,
    request: JString<'local>,
) -> jstring {
    let response = (|| -> Result<Value, String> {
        let db: String = env
            .get_string(&db_path)
            .map_err(|e| e.to_string())?
            .into();
        let req: String = env
            .get_string(&request)
            .map_err(|e| e.to_string())?
            .into();
        let req: Value = serde_json::from_str(&req).map_err(|e| e.to_string())?;
        dispatch(&db, &req)
    })();
    let body = match response {
        Ok(data) => json!({"ok": true, "data": data}),
        Err(error) => json!({"ok": false, "error": error}),
    };
    env.new_string(body.to_string())
        .expect("failed to allocate JNI response string")
        .into_raw()
}