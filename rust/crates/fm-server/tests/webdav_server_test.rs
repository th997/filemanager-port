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
    assert!(xml.contains("<D:quota-available-bytes>"));
    assert!(xml.contains("<D:quota-used-bytes>"));

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

#[tokio::test]
async fn webdav_server_serves_browser_ui_json_download_and_multipart_upload() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path().join("Docs")).unwrap();
    std::fs::write(dir.path().join("hello.txt"), b"0123456789ABCDEF").unwrap();
    std::fs::write(dir.path().join("测试文档.txt"), b"CJK_BODY").unwrap();

    let vfs: Arc<dyn Vfs> = Arc::new(LocalFs::new(dir.path()));
    let srv = start_webdav_server(
        Arc::clone(&vfs),
        VfsPath::root(),
        None,
        None,
        None,
        false,
    )
    .await
    .unwrap();
    let base = format!("http://127.0.0.1:{}", srv.port);
    let client = reqwest::Client::new();

    // GET / returns browser HTML UI
    let html_resp = client.get(format!("{base}/")).send().await.unwrap();
    assert_eq!(html_resp.status(), 200);
    assert!(html_resp
        .headers()
        .get("content-type")
        .unwrap()
        .to_str()
        .unwrap()
        .contains("text/html"));
    let html = html_resp.text().await.unwrap();
    assert!(html.contains("FM_WebDAV") || html.contains("FP File Manager - WebDAV"));

    // GET /?fm_json=1 returns sorted directory entries
    let json_resp = client.get(format!("{base}/?fm_json=1")).send().await.unwrap();
    assert_eq!(json_resp.status(), 200);
    let json_bytes = json_resp.bytes().await.unwrap();
    let json_val: serde_json::Value = serde_json::from_slice(&json_bytes).unwrap();
    assert_eq!(json_val["read_only"], false);
    let items = json_val["items"].as_array().unwrap();
    assert!(items.iter().any(|it| it["name"] == "Docs" && it["is_dir"] == true));
    assert!(items.iter().any(|it| it["name"] == "hello.txt" && it["is_dir"] == false));

    // GET /测试文档.txt?download=1 returns Content-Disposition attachment
    let dl_resp = client
        .get(format!("{base}/%E6%B5%8B%E8%AF%95%E6%96%87%E6%A1%A3.txt?download=1"))
        .send()
        .await
        .unwrap();
    assert_eq!(dl_resp.status(), 200);
    let cd = dl_resp
        .headers()
        .get("content-disposition")
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();
    assert!(cd.starts_with("attachment;"));
    assert_eq!(dl_resp.bytes().await.unwrap().as_ref(), b"CJK_BODY");

    // POST / multipart upload writes nested files cleanly
    let boundary = "----FMBoundary123";
    let multipart_body = format!(
        "--{boundary}\r\n\
         Content-Disposition: form-data; name=\"files\"; filename=\"Sub/nested.txt\"\r\n\
         Content-Type: application/octet-stream\r\n\r\n\
         uploaded via browser\r\n\
         --{boundary}--\r\n"
    );
    let post_resp = client
        .post(format!("{base}/"))
        .header("content-type", format!("multipart/form-data; boundary={boundary}"))
        .body(multipart_body)
        .send()
        .await
        .unwrap();
    assert_eq!(post_resp.status(), 200);
    assert_eq!(
        std::fs::read(dir.path().join("Sub/nested.txt")).unwrap(),
        b"uploaded via browser"
    );

    let _ = srv.shutdown_tx.send(());

    // Single-file WebDAV share serves HTML & JSON at / and downloads the single file
    let single_srv = start_webdav_server(
        Arc::clone(&vfs),
        VfsPath::from_slash_path("/hello.txt"),
        None,
        None,
        None,
        false,
    )
    .await
    .unwrap();
    let single_base = format!("http://127.0.0.1:{}", single_srv.port);
    let single_bytes = client
        .get(format!("{single_base}/?fm_json=1"))
        .send()
        .await
        .unwrap()
        .bytes()
        .await
        .unwrap();
    let single_json: serde_json::Value = serde_json::from_slice(&single_bytes).unwrap();
    assert_eq!(single_json["single_file"], true);
    assert_eq!(single_json["read_only"], true);
    assert_eq!(single_json["items"][0]["name"], "hello.txt");

    let single_dl = client
        .get(format!("{single_base}/hello.txt?download=1"))
        .send()
        .await
        .unwrap();
    assert_eq!(single_dl.status(), 200);
    assert_eq!(single_dl.bytes().await.unwrap().as_ref(), b"0123456789ABCDEF");

    // Read-only / single-file rejects POST upload with 403
    let ro_body = format!(
        "--{boundary}\r\n\
         Content-Disposition: form-data; name=\"files\"; filename=\"x.txt\"\r\n\r\n\
         denied\r\n\
         --{boundary}--\r\n"
    );
    let ro_post = client
        .post(format!("{single_base}/"))
        .header("content-type", format!("multipart/form-data; boundary={boundary}"))
        .body(ro_body)
        .send()
        .await
        .unwrap();
    assert_eq!(ro_post.status(), 403);

    let _ = single_srv.shutdown_tx.send(());
}
