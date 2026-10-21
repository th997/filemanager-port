//! Archive extraction and compression utilities.

use fm_vfs::{VfsError, VfsResult};
use std::fs::File;
use std::io::Write;
use std::path::Path;
use zip::write::SimpleFileOptions;

use crate::ArchiveFormat;

pub fn extract_archive(archive_path: &Path, destination_dir: &Path) -> VfsResult<()> {
    std::fs::create_dir_all(destination_dir).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;

    let name = archive_path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");
    let format = ArchiveFormat::from_name(name).ok_or(VfsError::Unsupported {
        operation: "unknown archive format for extraction",
    })?;

    match format {
        ArchiveFormat::Zip | ArchiveFormat::Epub => {
            let file = File::open(archive_path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut zip = zip::ZipArchive::new(file).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidData, e.to_string()),
            })?;
            zip.extract(destination_dir)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
        }
        ArchiveFormat::Tar => {
            let file = File::open(archive_path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut archive = tar::Archive::new(file);
            archive.unpack(destination_dir).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        }
        ArchiveFormat::TarGz => {
            let file = File::open(archive_path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let gz = flate2::read::GzDecoder::new(file);
            let mut archive = tar::Archive::new(gz);
            archive.unpack(destination_dir).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        }
        ArchiveFormat::SevenZip => {
            // sevenz-rust joins entry names onto the destination without
            // sanitising them, so a crafted archive can write outside it.
            sevenz_rust::decompress_file_with_extract_fn(
                archive_path,
                destination_dir,
                |entry, reader, _dest| {
                    let target = safe_join(destination_dir, entry.name()).ok_or_else(|| {
                        sevenz_rust::Error::other(format!(
                            "unsafe archive entry path: {}",
                            entry.name()
                        ))
                    })?;
                    if entry.is_directory() {
                        std::fs::create_dir_all(&target).map_err(sevenz_rust::Error::io)?;
                    } else {
                        if let Some(parent) = target.parent() {
                            std::fs::create_dir_all(parent).map_err(sevenz_rust::Error::io)?;
                        }
                        let mut file =
                            File::create(&target).map_err(sevenz_rust::Error::io)?;
                        std::io::copy(reader, &mut file).map_err(sevenz_rust::Error::io)?;
                    }
                    Ok(true)
                },
            )
            .map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: std::io::Error::other(e.to_string()),
            })?;
        }
    }

    Ok(())
}

/// Join an archive entry name onto `base`, rejecting absolute paths and any
/// component that would escape it.
fn safe_join(base: &Path, entry_name: &str) -> Option<std::path::PathBuf> {
    let normalized = entry_name.replace('\\', "/");
    let mut out = base.to_path_buf();
    for component in normalized.split('/') {
        match component {
            "" | "." => continue,
            ".." => return None,
            _ => out.push(component),
        }
    }
    if out.starts_with(base) {
        Some(out)
    } else {
        None
    }
}

pub fn create_zip(sources: &[impl AsRef<Path>], destination_zip: &Path) -> VfsResult<()> {
    let file = File::create(destination_zip).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);

    let dest_canon = destination_zip.canonicalize().ok();

    for source_ref in sources {
        let source = source_ref.as_ref();
        if let Some(ref dc) = dest_canon {
            if let Ok(sc) = source.canonicalize() {
                if sc == *dc {
                    continue;
                }
            }
        }
        if source.is_file() {
            let file_name = source
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("file");
            zip.start_file(file_name, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            let mut f = File::open(source).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            std::io::copy(&mut f, &mut zip).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        } else if source.is_dir() {
            add_dir_to_zip(&mut zip, source, source, options, dest_canon.as_deref())?;
        }
    }

    zip.finish().map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: std::io::Error::other(e.to_string()),
    })?;

    Ok(())
}

fn add_dir_to_zip<W: Write + std::io::Seek>(
    zip: &mut zip::ZipWriter<W>,
    base_dir: &Path,
    current_dir: &Path,
    options: SimpleFileOptions,
    dest_canon: Option<&Path>,
) -> VfsResult<()> {
    let read_dir = std::fs::read_dir(current_dir).map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: e,
    })?;

    for entry_res in read_dir {
        let entry = entry_res.map_err(|e| VfsError::Backend {
            path: fm_core::VfsPath::root(),
            source: e,
        })?;
        let path = entry.path();
        if let Some(dc) = dest_canon {
            if let Ok(pc) = path.canonicalize() {
                if pc == dc {
                    continue;
                }
            }
        }
        let rel_path = path
            .strip_prefix(base_dir)
            .map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidInput, e.to_string()),
            })?;
        let rel_path_str = rel_path.to_string_lossy().replace('\\', "/");

        let file_type = entry.file_type().map_err(|e| VfsError::Backend {
            path: fm_core::VfsPath::root(),
            source: e,
        })?;
        if file_type.is_symlink() {
            // Avoid cyclic symlink recursion and directory traversal
            continue;
        }

        if file_type.is_dir() {
            zip.add_directory(format!("{rel_path_str}/"), options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            add_dir_to_zip(zip, base_dir, &path, options, dest_canon)?;
        } else if file_type.is_file() {
            zip.start_file(&rel_path_str, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::other(e.to_string()),
                })?;
            let mut f = File::open(&path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            std::io::copy(&mut f, zip).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_create_zip_skips_destination_inside_source() {
        let dir = tempdir().unwrap();
        let src_folder = dir.path().join("my_folder");
        std::fs::create_dir(&src_folder).unwrap();
        std::fs::write(src_folder.join("file1.txt"), "hello world").unwrap();

        // Put destination zip INSIDE the folder being compressed
        let dest_zip = src_folder.join("archive.zip");
        create_zip(&[&src_folder], &dest_zip).unwrap();

        assert!(dest_zip.exists());
        let file = File::open(&dest_zip).unwrap();
        let mut zip = zip::ZipArchive::new(file).unwrap();
        let names: Vec<String> = (0..zip.len())
            .map(|i| zip.by_index(i).unwrap().name().unwrap().to_string())
            .collect();
        assert!(names.iter().any(|n| n.ends_with("file1.txt")));
        assert!(!names.iter().any(|n| n.ends_with("archive.zip")));
    }
}

