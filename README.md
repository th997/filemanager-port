# Cross-Platform File Manager (Rust + Flutter)

A high-performance, local-first file manager ported across Android, iOS, Linux, macOS, and Windows.

Architecture: Pure Rust domain services and network protocol drivers (`fm-*`) bridged via `flutter_rust_bridge` 2.13.0 to a responsive Flutter 3.47 (Material 3) user interface.

## Supported Protocols & Features

### 1. Cloud & Remote Protocols (`fm-remote`)
- **Amazon S3 / S3-Compatible**: Powered by Apache OpenDAL. Supports AWS S3, MinIO, Cloudflare R2, Ceph Object Gateway, path-style and virtual-host addressing, AWS SigV4, and custom regions/endpoints.
- **Aliyun OSS (阿里云对象存储)**: Powered by Apache OpenDAL. Native support for Alibaba Cloud OSS endpoints (`oss-cn-*.aliyuncs.com`), OSS-HMAC signatures, bucket operations, and custom endpoints.
- **WebDAV**: Nextcloud, ownCloud, and generic WebDAV servers with digest/basic auth.
- **SFTP**: Pure-Rust SSH file transfer via `russh` and `russh-sftp`.
- **FTP / FTPS**: Pure-Rust asynchronous FTP via `suppaftp` with TLS encryption and EPSV support.
- **SMB2/SMB3**: Windows network file sharing and Samba shares via `smb2`.

### 2. Archive Virtual Filesystem (`fm-archive`)
- **Virtual Drill-Down (`archive://`)**: Browse inside `.zip`, `.tar`, `.tar.gz`, and `.7z` archives just like regular folders without extracting to disk first.
- **Streaming Extract & Compress**: 64KB chunked stream compression/decompression with progress tracking and cancellation tokens.

### 3. Application Services & Persistence (`fm-index`, `fm-ops`)
- **Embedded SQLite (`fm-index`)**: Bundled SQLite database (`~/.filemanager/filemanager.db`) storing remote connection profiles, bookmarks, LRU navigation history (up to 100 entries), and recycle bin metadata.
- **Recycle Bin**: Move files to the local trash folder (`~/.filemanager/trash/`) with one-click restore and permanent purge capabilities.
- **Task Runner (`fm-ops`)**: Asynchronous, cancellable cross-VFS streaming copy, move, and recursive delete engine.

### 4. LAN Sharing Server (`fm-server`)
- **HTTP Web File Manager**: Built with Axum 0.8. Serves a responsive HTML5 web manager on the local network with file listing, direct downloads, and range requests (HTTP 206 Partial Content).
- **Security & Modes**: Configurable port, optional password authentication, read-only toggle, and automatic LAN IP address enumeration.

### 5. Viewers & Editors
- **Built-in Text/Code Editor**: View and edit plain text, source code, and configuration files directly in-app, saving back to local or remote storage.
- **Built-in Image Viewer**: Pinch-to-zoom interactive viewer with gesture navigation.

---

## Workspace Structure

```
filemanager-port/
├── app/                  # Flutter 3.47 client application
│   ├── lib/
│   │   ├── src/
│   │   │   ├── dialogs/  # Remote wizard, task progress, compress dialogs
│   │   │   ├── models/   # Entry items, capabilities, DTO adapters
│   │   │   ├── pages/    # Browser, Locations/Cloud, Settings, Text Editor, Trash
│   │   │   ├── rust/     # flutter_rust_bridge generated bridge files
│   │   │   └── services/ # StorageService, TaskService, SharingService
│   │   └── main.dart
│   └── test/             # Unit tests for models, paths, and VFS
└── rust/                 # Pure Rust backend crates
    └── crates/
        ├── fm-core       # Domain types (VfsPath, Entry, LocationKind, Capabilities)
        ├── fm-vfs        # Vfs trait, metadata, and error types
        ├── fm-local      # Local filesystem Vfs implementation
        ├── fm-remote     # OpenDAL (S3, OSS, WebDAV), SFTP, FTP, SMB drivers
        ├── fm-archive    # Zip, Tar, 7z virtual filesystem and compression engine
        ├── fm-index      # Embedded SQLite persistence (remotes, bookmarks, history, trash)
        ├── fm-ops        # Asynchronous task engine and stream pipe
        ├── fm-server     # Axum LAN HTTP sharing server and IP discovery
        └── fm-ffi        # flutter_rust_bridge exported API and VfsRegistry
```

---

## Building and Running

### Prerequisites
- Flutter 3.47+ (Dart 3.13+)
- Rust 1.80+
- `flutter_rust_bridge_codegen` 2.13.0: `cargo install 'flutter_rust_bridge_codegen@2.13.0'`

### Linux Desktop
```bash
cd app
flutter run -d linux
# Binary produced at: app/build/linux/x64/debug/bundle/filemanager
```

### Android
```bash
cd app
flutter build apk --debug
# APK produced at: app/build/app/outputs/flutter-apk/app-debug.apk
```

### Running Tests
```bash
# Rust workspace unit tests
cd rust && cargo test --workspace

# Flutter unit & model tests
cd app && flutter test test/models_test.dart
```
