use std::sync::Arc;

use fm_core::VfsPath;
use fm_local::LocalFs;
use fm_server::start_webdav_server;
use fm_vfs::Vfs;
use reqwest::Method;

#[tokio::test]
async fn webdav_server_supports_propfind_range_put_mkcol_move_delete_and_auth() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path().join("Docs")).unwrap();
    std::fs::write(dir.path().join("hello.txt"), b"0123456789ABCDEF").unwrap();

    let vfs: Arc<dyn Vfs> = Arc::new(LocalFs::new(dir.path()));
    let srv = start_webdav_server(
        Arc::clone(&vfs),
        VfsPath::root(),
        None,
        Some("admin".into()),
        Some("secret".into()),
        false,
    )
    .await
    .unwrap();
    let base = format!("http://127.0.0.1:{}", srv.port);
    let client = reqwest::Client::new();

    // Missing auth must return 401.
    let unauth = client
        .request(Method::from_bytes(b"PROPFIND").unwrap(), format!("{base}/"))
        .header("Depth", "1")
        .send()
        .await
        .unwrap();
    assert_eq!(unauth.status(), 401);

    // PROPFIND Depth 1 lists children.
    let prop = client
        .request(Method::from_bytes(b"PROPFIND").unwrap(), format!("{base}/"))
        .basic_auth("admin", Some("secret"))
        .header("Depth", "1")
        .send()
        .await
        .unwrap();
    assert_eq!(prop.status(), 207);
    let xml = prop.text().await.unwrap();
    assert!(xml.contains("hello.txt"));
    assert!(xml.contains("<D:collection/>"));

    // GET with Range returns 206 partial content.
    let partial = client
        .get(format!("{base}/hello.txt"))
        .basic_auth("admin", Some("secret"))
        .header("Range", "bytes=4-9")
        .send()
        .await
        .unwrap();
    assert_eq!(partial.status(), 206);
    assert_eq!(partial.bytes().await.unwrap().as_ref(), b"456789");

    // MKCOL + PUT + MOVE + DELETE work.
    let mkcol = client
        .request(Method::from_bytes(b"MKCOL").unwrap(), format!("{base}/NewDir"))
        .basic_auth("admin", Some("secret"))
        .send()
        .await
        .unwrap();
    assert_eq!(mkcol.status(), 201);

    let put = client
        .put(format!("{base}/NewDir/note.txt"))
        .basic_auth("admin", Some("secret"))
        .body("webdav uploaded")
        .send()
        .await
        .unwrap();
    assert_eq!(put.status(), 201);

    let mv = client
        .request(Method::from_bytes(b"MOVE").unwrap(), format!("{base}/NewDir/note.txt"))
        .basic_auth("admin", Some("secret"))
        .header("Destination", format!("{base}/NewDir/note2.txt"))
        .send()
        .await
        .unwrap();
    assert_eq!(mv.status(), 201);
    assert!(dir.path().join("NewDir/note2.txt").exists());

    let del = client
        .delete(format!("{base}/NewDir/note2.txt"))
        .basic_auth("admin", Some("secret"))
        .send()
        .await
        .unwrap();
    assert_eq!(del.status(), 204);
    assert!(!dir.path().join("NewDir/note2.txt").exists());

    let _ = srv.shutdown_tx.send(());

    // Read-only mode blocks writes.
    let ro_srv = start_webdav_server(Arc::clone(&vfs), VfsPath::root(), None, None, None, true)
        .await
        .unwrap();
    let ro_put = client
        .put(format!("http://127.0.0.1:{}/ro.txt", ro_srv.port))
        .body("denied")
        .send()
        .await
        .unwrap();
    assert_eq!(ro_put.status(), 403);
    let _ = ro_srv.shutdown_tx.send(());

    // Self-COPY must fail with 403 without truncating source, and username without password must fail startup.
    let no_pass = start_webdav_server(
        Arc::clone(&vfs),
        VfsPath::root(),
        None,
        Some("admin".into()),
        None,
        false,
    )
    .await;
    assert!(no_pass.is_err());

    let rw_srv = start_webdav_server(Arc::clone(&vfs), VfsPath::root(), None, None, None, false)
        .await
        .unwrap();
    let self_copy = client
        .request(Method::from_bytes(b"COPY").unwrap(), format!("http://127.0.0.1:{}/hello.txt", rw_srv.port))
        .header("Destination", format!("http://127.0.0.1:{}/hello.txt", rw_srv.port))
        .send()
        .await
        .unwrap();
    assert_eq!(self_copy.status(), 403);
    assert_eq!(std::fs::read(dir.path().join("hello.txt")).unwrap(), b"0123456789ABCDEF");
    let _ = rw_srv.shutdown_tx.send(());
}
