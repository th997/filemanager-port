//! Directory synchronization / lightweight backup (Incremental, Mirror, Bidirectional).

use crate::api::file_manager::invalidate_dir_cache;
use crate::api::tasks::{finish_sync_task, register_sync_task};
use crate::registry::VfsRegistry;
use fm_core::{EntryKind, VfsPath};
use fm_ops::{copy_recursive_with_control, delete_recursive, ConflictPolicy, FailedTaskItem};
use fm_vfs::Vfs;
use std::collections::{BTreeMap, HashSet};

#[derive(Debug, Clone)]
pub struct SyncDiffItemDto {
    /// Relative slash path beneath the sync root.
    pub rel_path: String,
    /// Action: `"add"`, `"update"`, `"delete"`, `"pull_add"`, `"pull_update"`.
    pub action: String,
    pub src_size: Option<u64>,
    pub dst_size: Option<u64>,
    pub src_modified_millis: Option<i64>,
    pub dst_modified_millis: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct SyncPlanDto {
    pub mode: String,
    pub items: Vec<SyncDiffItemDto>,
    pub unchanged_count: u64,
    pub transfer_bytes: u64,
    pub truncated: bool,
    pub scanned_files: u64,
}

struct FileMeta {
    size: u64,
    modified_millis: Option<i64>,
}

async fn collect_files(
    vfs: &dyn Vfs,
    base: &VfsPath,
) -> Result<(BTreeMap<String, FileMeta>, bool), fm_vfs::VfsError> {
    let mut map = BTreeMap::new();
    let base_seg_len = base.segments().len();
    let mut stack: Vec<(VfsPath, usize)> = vec![(base.clone(), 0)];
    let mut first = true;
    let mut truncated = false;
    const MAX_DEPTH: usize = 64;
    const MAX_FILES: usize = 200_000;

    while let Some((dir, depth)) = stack.pop() {
        if map.len() >= MAX_FILES {
            truncated = true;
            break;
        }
        let children = match vfs.list(&dir).await {
            Ok(c) => c,
            Err(e) => {
                if first {
                    return Err(e);
                }
                continue;
            }
        };
        first = false;
        for child in children {
            if child.is_symlink {
                continue;
            }
            if child.kind == EntryKind::Dir {
                if depth < MAX_DEPTH {
                    stack.push((child.path, depth + 1));
                } else {
                    truncated = true;
                }
            } else if child.kind == EntryKind::File {
                if map.len() >= MAX_FILES {
                    truncated = true;
                    break;
                }
                let segs = child.path.segments();
                let rel = if segs.len() > base_seg_len {
                    segs[base_seg_len..].join("/")
                } else {
                    child.name.clone()
                };
                let modified_millis = child
                    .modified
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64);
                map.insert(
                    rel,
                    FileMeta {
                        size: child.size.unwrap_or(0),
                        modified_millis,
                    },
                );
            }
        }
    }
    Ok((map, truncated))
}

fn differs(a: &FileMeta, b: &FileMeta) -> bool {
    if a.size != b.size {
        return true;
    }
    match (a.modified_millis, b.modified_millis) {
        // Allow 2s clock/FAT mtime skew tolerance.
        (Some(am), Some(bm)) => (am - bm).abs() > 2000,
        _ => false,
    }
}

/// Compute a dry-run diff plan between `(src_root, src_path)` and `(dst_root, dst_path)`.
/// `mode`: `"incremental"` (copy new & newer), `"mirror"` (also delete extra dst files),
/// or `"bidirectional"` (sync newer changes both ways).
pub async fn preview_directory_sync(
    src_root: String,
    src_path: String,
    dst_root: String,
    dst_path: String,
    mode: String,
) -> Result<SyncPlanDto, String> {
    let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
    let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
    let src_base = VfsPath::from_slash_path(&src_path);
    let dst_base = VfsPath::from_slash_path(&dst_path);

    let (src_files, src_truncated) = collect_files(src_vfs.as_ref(), &src_base)
        .await
        .map_err(|e| e.to_string())?;
    let (dst_files, dst_truncated) = match collect_files(dst_vfs.as_ref(), &dst_base).await {
        Ok(res) => res,
        Err(fm_vfs::VfsError::NotFound { .. }) => (BTreeMap::new(), false),
        Err(e) => return Err(e.to_string()),
    };
    let scanned_files = (src_files.len() + dst_files.len()) as u64;
    let truncated = src_truncated || dst_truncated;

    let mode_norm = match mode.to_ascii_lowercase().as_str() {
        "mirror" => "mirror",
        "bidirectional" => "bidirectional",
        _ => "incremental",
    };

    let mut items = Vec::new();
    let mut unchanged_count = 0u64;
    let mut transfer_bytes = 0u64;

    for (rel, sm) in &src_files {
        match dst_files.get(rel) {
            None => {
                transfer_bytes = transfer_bytes.saturating_add(sm.size);
                items.push(SyncDiffItemDto {
                    rel_path: rel.clone(),
                    action: "add".to_string(),
                    src_size: Some(sm.size),
                    dst_size: None,
                    src_modified_millis: sm.modified_millis,
                    dst_modified_millis: None,
                });
            }
            Some(dm) => {
                if !differs(sm, dm) {
                    unchanged_count += 1;
                } else if mode_norm == "bidirectional"
                    && dm.modified_millis.unwrap_or(0) > sm.modified_millis.unwrap_or(0) + 2000
                {
                    transfer_bytes = transfer_bytes.saturating_add(dm.size);
                    items.push(SyncDiffItemDto {
                        rel_path: rel.clone(),
                        action: "pull_update".to_string(),
                        src_size: Some(sm.size),
                        dst_size: Some(dm.size),
                        src_modified_millis: sm.modified_millis,
                        dst_modified_millis: dm.modified_millis,
                    });
                } else {
                    transfer_bytes = transfer_bytes.saturating_add(sm.size);
                    items.push(SyncDiffItemDto {
                        rel_path: rel.clone(),
                        action: "update".to_string(),
                        src_size: Some(sm.size),
                        dst_size: Some(dm.size),
                        src_modified_millis: sm.modified_millis,
                        dst_modified_millis: dm.modified_millis,
                    });
                }
            }
        }
    }

    for (rel, dm) in &dst_files {
        if src_files.contains_key(rel) {
            continue;
        }
        if mode_norm == "mirror" {
            items.push(SyncDiffItemDto {
                rel_path: rel.clone(),
                action: "delete".to_string(),
                src_size: None,
                dst_size: Some(dm.size),
                src_modified_millis: None,
                dst_modified_millis: dm.modified_millis,
            });
        } else if mode_norm == "bidirectional" {
            transfer_bytes = transfer_bytes.saturating_add(dm.size);
            items.push(SyncDiffItemDto {
                rel_path: rel.clone(),
                action: "pull_add".to_string(),
                src_size: None,
                dst_size: Some(dm.size),
                src_modified_millis: None,
                dst_modified_millis: dm.modified_millis,
            });
        }
    }

    Ok(SyncPlanDto {
        mode: mode_norm.to_string(),
        items,
        unchanged_count,
        transfer_bytes,
        truncated,
        scanned_files,
    })
}

async fn ensure_parent_dirs(vfs: &dyn Vfs, file_path: &VfsPath) {
    let mut ancestors = Vec::new();
    let mut cur = file_path.parent();
    while let Some(dir) = cur {
        if dir.is_root() {
            break;
        }
        ancestors.push(dir.clone());
        cur = dir.parent();
    }
    for dir in ancestors.into_iter().rev() {
        let _ = vfs.mkdir(&dir).await;
    }
}

/// Execute a directory sync plan in the background task manager, returning the task ID.
pub async fn start_directory_sync_task(
    src_root: String,
    src_path: String,
    dst_root: String,
    dst_path: String,
    mode: String,
    selected_rel_paths: Option<Vec<String>>,
) -> Result<String, String> {
    let plan = preview_directory_sync(
        src_root.clone(),
        src_path.clone(),
        dst_root.clone(),
        dst_path.clone(),
        mode.clone(),
    )
    .await?;

    let filter: Option<HashSet<String>> = selected_rel_paths.map(|v| v.into_iter().collect());
    let items: Vec<SyncDiffItemDto> = plan
        .items
        .into_iter()
        .filter(|it| match &filter {
            Some(set) => set.contains(&it.rel_path),
            None => true,
        })
        .collect();

    let (task_id, progress, cancel, control) = register_sync_task(&format!("Sync ({})", plan.mode));
    let total_bytes: u64 = items
        .iter()
        .map(|it| match it.action.as_str() {
            "add" | "update" => it.src_size.unwrap_or(0),
            "pull_add" | "pull_update" => it.dst_size.unwrap_or(0),
            _ => 0,
        })
        .sum();
    {
        let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
        p.total = Some(total_bytes);
        p.can_pause = true;
    }

    tokio::spawn(async move {
        let run = async {
            let src_vfs = VfsRegistry::global().get_or_create(&src_root).await?;
            let dst_vfs = VfsRegistry::global().get_or_create(&dst_root).await?;
            let src_base = VfsPath::from_slash_path(&src_path);
            let dst_base = VfsPath::from_slash_path(&dst_path);
            if !dst_base.is_root() {
                let _ = dst_vfs.mkdir(&dst_base).await;
            }

            let mut failures: Vec<FailedTaskItem> = Vec::new();
            for item in &items {
                if cancel.is_cancelled() {
                    return Err("cancelled".to_string());
                }
                let src_full = if src_base.is_root() {
                    VfsPath::from_slash_path(&item.rel_path)
                } else {
                    VfsPath::from_slash_path(&format!(
                        "{}/{}",
                        src_base.to_slash_string(),
                        item.rel_path
                    ))
                };
                let dst_full = if dst_base.is_root() {
                    VfsPath::from_slash_path(&item.rel_path)
                } else {
                    VfsPath::from_slash_path(&format!(
                        "{}/{}",
                        dst_base.to_slash_string(),
                        item.rel_path
                    ))
                };

                let res = match item.action.as_str() {
                    "add" | "update" => {
                        ensure_parent_dirs(dst_vfs.as_ref(), &dst_full).await;
                        copy_recursive_with_control(
                            src_vfs.as_ref(),
                            &src_full,
                            dst_vfs.as_ref(),
                            &dst_full,
                            &progress,
                            &cancel,
                            &control,
                            ConflictPolicy::Overwrite,
                        )
                        .await
                        .map_err(|e| e.to_string())
                    }
                    "pull_add" | "pull_update" => {
                        ensure_parent_dirs(src_vfs.as_ref(), &src_full).await;
                        copy_recursive_with_control(
                            dst_vfs.as_ref(),
                            &dst_full,
                            src_vfs.as_ref(),
                            &src_full,
                            &progress,
                            &cancel,
                            &control,
                            ConflictPolicy::Overwrite,
                        )
                        .await
                        .map_err(|e| e.to_string())
                    }
                    "delete" => delete_recursive(dst_vfs.as_ref(), &dst_full, &progress, &cancel)
                        .await
                        .map_err(|e| e.to_string()),
                    _ => Ok(()),
                };

                if let Err(err) = res {
                    if cancel.is_cancelled() {
                        return Err(err);
                    }
                    let (fr, fp, tr, tp) = if item.action.starts_with("pull_") {
                        (
                            dst_root.clone(),
                            dst_full.to_slash_string(),
                            src_root.clone(),
                            src_full.to_slash_string(),
                        )
                    } else {
                        (
                            src_root.clone(),
                            src_full.to_slash_string(),
                            dst_root.clone(),
                            dst_full.to_slash_string(),
                        )
                    };
                    failures.push(FailedTaskItem {
                        src_root: fr,
                        src_path: fp,
                        dst_root: tr,
                        dst_path: tp,
                        is_dir: false,
                        error: err,
                    });
                }
            }

            invalidate_dir_cache(&dst_root);
            invalidate_dir_cache(&src_root);

            if !failures.is_empty() {
                let msg = format!("{} of {} sync items failed", failures.len(), items.len());
                let only_copies = failures.iter().all(|f| f.dst_root != f.src_root || !f.error.is_empty())
                    && items.iter().all(|it| it.action != "delete");
                {
                    let mut p = progress.lock().unwrap_or_else(|e| e.into_inner());
                    p.failed_items = failures;
                    if only_copies {
                        p.retry_kind = Some("copy".to_string());
                        p.conflict_policy = Some("overwrite".to_string());
                    }
                }
                return Err(msg);
            }
            Ok(())
        }
        .await;

        finish_sync_task(&progress, &cancel, run);
    });

    Ok(task_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn preview_sync_matches_root_and_subdir_paths_cleanly() {
        let src = tempfile::tempdir().unwrap();
        let dst = tempfile::tempdir().unwrap();
        std::fs::write(src.path().join("same.txt"), b"hello").unwrap();
        std::fs::create_dir_all(dst.path().join("sub")).unwrap();
        std::fs::write(dst.path().join("sub/same.txt"), b"hello").unwrap();

        let plan = preview_directory_sync(
            src.path().to_string_lossy().to_string(),
            "/".into(),
            dst.path().to_string_lossy().to_string(),
            "/sub".into(),
            "mirror".into(),
        )
        .await
        .unwrap();

        assert_eq!(plan.unchanged_count, 1);
        assert!(plan.items.is_empty(), "expected zero diff items, got {:?}", plan.items.len());
    }
}
