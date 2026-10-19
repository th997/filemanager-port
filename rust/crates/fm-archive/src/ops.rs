//! Archive extraction and compression utilities.

use fm_vfs::{VfsError, VfsResult};
use std::fs::File;
use std::io::{Read, Write};
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
    let format = ArchiveFormat::from_name(name).ok_or_else(|| VfsError::Unsupported {
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
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
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
            sevenz_rust::decompress_file(archive_path, destination_dir).map_err(|e| {
                VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                }
            })?;
        }
    }

    Ok(())
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

    for source_ref in sources {
        let source = source_ref.as_ref();
        if source.is_file() {
            let file_name = source
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("file");
            zip.start_file(file_name, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                })?;
            let mut f = File::open(source).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut buffer = Vec::new();
            f.read_to_end(&mut buffer).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            zip.write_all(&buffer).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        } else if source.is_dir() {
            add_dir_to_zip(&mut zip, source, source, options)?;
        }
    }

    zip.finish().map_err(|e| VfsError::Backend {
        path: fm_core::VfsPath::root(),
        source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
    })?;

    Ok(())
}

fn add_dir_to_zip<W: Write + std::io::Seek>(
    zip: &mut zip::ZipWriter<W>,
    base_dir: &Path,
    current_dir: &Path,
    options: SimpleFileOptions,
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
        let rel_path = path
            .strip_prefix(base_dir)
            .map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: std::io::Error::new(std::io::ErrorKind::InvalidInput, e.to_string()),
            })?;
        let rel_path_str = rel_path.to_string_lossy().replace('\\', "/");

        if path.is_dir() {
            zip.add_directory(&format!("{rel_path_str}/"), options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                })?;
            add_dir_to_zip(zip, base_dir, &path, options)?;
        } else if path.is_file() {
            zip.start_file(&rel_path_str, options)
                .map_err(|e| VfsError::Backend {
                    path: fm_core::VfsPath::root(),
                    source: std::io::Error::new(std::io::ErrorKind::Other, e.to_string()),
                })?;
            let mut f = File::open(&path).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            let mut buffer = Vec::new();
            f.read_to_end(&mut buffer).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
            zip.write_all(&buffer).map_err(|e| VfsError::Backend {
                path: fm_core::VfsPath::root(),
                source: e,
            })?;
        }
    }

    Ok(())
}
