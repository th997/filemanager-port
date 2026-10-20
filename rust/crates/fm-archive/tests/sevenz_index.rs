use fm_archive::ArchiveFs;
use fm_core::VfsPath;
use fm_vfs::Vfs;

#[tokio::test]
async fn sevenz_index_lists_entries() {
    let dir = tempfile::tempdir().unwrap();
    let archive_path = dir.path().join("sample.7z");

    {
        let mut writer = sevenz_rust::SevenZWriter::create(&archive_path).unwrap();
        let mut file = sevenz_rust::SevenZArchiveEntry::new();
        file.name = "docs/readme.txt".to_string();
        file.has_stream = true;
        writer
            .push_archive_entry(file, Some(&b"hello 7z"[..]))
            .unwrap();
        writer.finish().unwrap();
    }

    let fs = ArchiveFs::open(&archive_path).unwrap();
    let root = fs.list(&VfsPath::root()).await.unwrap();
    assert!(root.iter().any(|e| e.name == "docs" && e.kind == fm_core::EntryKind::Dir));

    let docs = fs.list(&VfsPath::from_slash_path("/docs")).await.unwrap();
    assert_eq!(docs.len(), 1);
    assert_eq!(docs[0].name, "readme.txt");
    assert_eq!(docs[0].size, Some(8));
}
