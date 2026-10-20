use fm_archive::extract_archive;

#[test]
fn sevenz_extract_rejects_path_traversal() {
    let dir = tempfile::tempdir().unwrap();
    let archive_path = dir.path().join("evil.7z");

    {
        let mut writer = sevenz_rust::SevenZWriter::create(&archive_path).unwrap();
        let mut entry = sevenz_rust::SevenZArchiveEntry::new();
        entry.name = "../escaped.txt".to_string();
        entry.has_stream = true;
        writer
            .push_archive_entry(entry, Some(&b"pwned"[..]))
            .unwrap();
        writer.finish().unwrap();
    }

    let dest = dir.path().join("out");
    assert!(extract_archive(&archive_path, &dest).is_err());
    assert!(!dir.path().join("escaped.txt").exists());
}
