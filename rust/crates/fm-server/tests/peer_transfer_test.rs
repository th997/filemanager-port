use std::sync::Arc;
use std::time::Duration;

use fm_core::VfsPath;
use fm_local::LocalFs;
use fm_server::{send_peer_files, send_peer_text, start_peer_receiver};
use fm_vfs::Vfs;

#[tokio::test]
async fn peer_receiver_accepts_file_and_text_offers_end_to_end() {
    let src_dir = tempfile::tempdir().unwrap();
    let dst_dir = tempfile::tempdir().unwrap();
    std::fs::write(src_dir.path().join("photo.jpg"), b"JPEG_MOCK_DATA").unwrap();

    let receiver = Arc::new(
        start_peer_receiver("DeskPC".into(), dst_dir.path().to_path_buf(), None)
            .await
            .unwrap(),
    );
    let url = format!("http://127.0.0.1:{}", receiver.port);

    // 1. File transfer offer -> accept -> uploaded to dst_dir.
    let vfs: Arc<dyn Vfs> = Arc::new(LocalFs::new(src_dir.path()));
    let send_url = url.clone();
    let send_handle = tokio::spawn(async move {
        send_peer_files(
            &send_url,
            "Phone",
            vfs,
            vec![(VfsPath::from_slash_path("/photo.jpg"), "photo.jpg".into())],
        )
        .await
    });

    // Wait for pending offer & accept it.
    let mut accepted = false;
    for _ in 0..40 {
        let offers = receiver.list_offers();
        if let Some(pending) = offers.iter().find(|o| o.status == "pending") {
            assert_eq!(pending.sender_name, "Phone");
            accepted = receiver.respond_offer(&pending.offer_id, true, None);
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert!(accepted);
    let sent_count = send_handle.await.unwrap().unwrap();
    assert_eq!(sent_count, 1);
    assert_eq!(
        std::fs::read(dst_dir.path().join("photo.jpg")).unwrap(),
        b"JPEG_MOCK_DATA"
    );

    // 2. Text offer -> accept.
    let text_url = url.clone();
    let text_handle = tokio::spawn(async move {
        send_peer_text(&text_url, "Phone", "hello lan clipboard").await
    });

    let mut text_accepted = false;
    for _ in 0..40 {
        let offers = receiver.list_offers();
        if let Some(pending) = offers
            .iter()
            .find(|o| o.status == "pending" && o.kind == "text")
        {
            text_accepted = receiver.respond_offer(&pending.offer_id, true, None);
            assert_eq!(
                pending.text_payload.as_deref(),
                Some("hello lan clipboard")
            );
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert!(text_accepted);
    text_handle.await.unwrap().unwrap();

    // Uploading files to an accepted/completed text offer must be rejected.
    let offers = receiver.list_offers();
    let text_offer_id = offers
        .iter()
        .find(|o| o.kind == "text")
        .unwrap()
        .offer_id
        .clone();
    let bogus_upload = reqwest::Client::new()
        .post(format!("{url}/api/v1/peer/upload/{text_offer_id}"))
        .header("x-relative-path", "evil.txt")
        .body("payload")
        .send()
        .await
        .unwrap();
    assert_eq!(bogus_upload.status(), 403);
    assert!(!dst_dir.path().join("evil.txt").exists());

    // 3. CJK filename round-trip.
    std::fs::write(src_dir.path().join("测试照片.jpg"), b"CJK_JPG").unwrap();
    let url_cjk = url.clone();
    let src_vfs_cjk: Arc<dyn Vfs> = Arc::new(LocalFs::new(src_dir.path()));
    let cjk_handle = tokio::spawn(async move {
        send_peer_files(
            &url_cjk,
            "Phone",
            src_vfs_cjk,
            vec![(VfsPath::from_slash_path("/测试照片.jpg"), "测试照片.jpg".into())],
        )
        .await
    });
    let mut cjk_accepted = false;
    for _ in 0..40 {
        let offers = receiver.list_offers();
        if let Some(pending) = offers
            .iter()
            .find(|o| o.status == "pending" && o.kind == "files")
        {
            cjk_accepted = receiver.respond_offer(&pending.offer_id, true, None);
            break;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    assert!(cjk_accepted);
    assert_eq!(cjk_handle.await.unwrap().unwrap(), 1);
    assert_eq!(
        std::fs::read(dst_dir.path().join("测试照片.jpg")).unwrap(),
        b"CJK_JPG"
    );
}
