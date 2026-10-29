# Cross-Platform File Manager (Rust + Flutter)

[English](README.md) | [简体中文](README_zh.md) | [日本語](README_ja.md)

A high-performance, local-first cross-platform file manager built for iOS, Android, macOS, Windows, and Linux.

It pairs a high-concurrency Rust domain backend (`fm-*`) with a modern Flutter 3.47 (Material 3) user interface via `flutter_rust_bridge` 2.13, delivering native speed, deep protocol support, and unified UX across desktop and mobile.

---

## Key Features

### 1. Cloud & Remote Storage Protocols (`fm-remote`)
- **Amazon S3 & S3-Compatible**: Powered by Apache OpenDAL. Supports AWS S3, MinIO, Cloudflare R2, Ceph Object Gateway, path-style/virtual-host addressing, and AWS SigV4.
- **Aliyun OSS (Alibaba Cloud OSS)**: Native OpenDAL integration supporting standard regions, OSS-HMAC signatures, bucket operations, and custom domain endpoints.
- **WebDAV**: Nextcloud, ownCloud, InfiniCLOUD, and generic WebDAV servers with Basic and Digest authentication.
- **SFTP**: Pure-Rust asynchronous SSH file transfer via `russh` and `russh-sftp`.
- **FTP / FTPS**: Pure-Rust asynchronous FTP via `suppaftp` with explicit TLS encryption and passive mode (EPSV/PASV).
- **SMB2 / SMB3**: Windows network file sharing and Samba shares via `smb2`.

### 2. Virtual Archive Filesystem (`fm-archive`)
- **Virtual Drill-Down (`archive://`)**: Browse inside `.zip`, `.tar`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, and `.7z` archives directly like normal folders without extracting to disk.
- **Streaming Compression & Extraction**: 64 KB chunked streaming compression and extraction with real-time progress monitoring and cancellation tokens.

### 3. Markdown & Document Engine
- **Live Preview & Editor**: Split and preview modes for Markdown and HTML documents with line numbers, syntax highlighting, search/replace, and jump-to-line.
- **6 Themed Color Palettes**: GitHub (Light/Dark), Dracula, Sepia, Solarized Dark, Nord, and Vibrant, with code block highlight schemes synchronized to document themes.
- **Professional PDF Export**:
  - Custom font loading with full Chinese/CJK typography support.
  - Native Markdown inline AST styling (bold, italic, bold-italic, code, strikethrough, links).
  - GitHub-flavored Markdown tables with themed borders, header backgrounds, and alternating row colors.
  - Blockquotes and GitHub alerts (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`).
  - Configurable page margins with 3 gear presets: Compact (16 pt), Standard (36 pt), and Relaxed (54 pt).

### 4. Audio & Video Media Player
- **Dual-Engine Architecture**:
  - **iOS**: Native hardware-accelerated `AVPlayer` / `AVPlayerLayer` (`video_player`) with low-latency HTTP streaming, automatic buffer stall recovery, and lock-screen / background audio support.
  - **Desktop & Other Platforms**: Powered by `media_kit` (libmpv) with hardware-accelerated rendering and broad codec compatibility.
- **Media Features**: Folder playlist auto-discovery, auto-play next track, playback speed control (0.5x – 2.0x), resume progress memory, swipe-to-seek, and full-screen landscape rotation.

### 5. Interactive Image Viewer
- Interactive pinch-to-zoom and pan viewer.
- Horizontal swipe navigation between sibling images in the same folder.
- Lazy remote and archive image caching and export.

### 6. Universal "Open With..." External File Association
- Associate and open files directly from system file browsers, AirDrop, messaging apps, and share sheets across all platforms:
  - **iOS**: `CFBundleDocumentTypes` bound to `public.item`, `public.content`, and `public.data`; staged through sandbox `Inbox` for full POSIX read/write access.
  - **Android**: `ACTION_VIEW` and `ACTION_SEND` intent filters handling both `file://` and `content://` URIs with automatic content streaming.
  - **macOS**: `CFBundleDocumentTypes` and `NSApplicationDelegate.application(_:openFile:)`.
  - **Windows & Linux**: Command-line launch arguments (`main(List<String> args)`).
- Automatic routing to Text Editor, Media Player, Image Viewer, or Archive Explorer based on file type, with fallback to system handlers.

### 7. LAN HTTP Web File Sharing (`fm-server`)
- **Axum 0.8 Web Server**: Built-in HTTP server sharing any local folder across the local network (Wi-Fi/LAN).
- **Responsive Web UI**: Access, browse, and download files from any mobile or desktop web browser.
- **Streaming & Range Requests**: Supports HTTP 206 Partial Content for in-browser video and audio scrubbing.
- **Security**: Configurable port, optional password protection, read-only toggle, and automatic local IP enumeration.

### 8. Persistence & Security (`fm-index`)
- **Embedded SQLite (`~/.filemanager/filemanager.db`)**: Stores remote profiles, bookmarks, LRU navigation history, and trash metadata.
- **Recycle Bin**: Move files to local trash (`~/.filemanager/trash/`) with one-click restore and permanent purge.
- **Keychain Integration**: Native iOS Keychain service (`com.github.th997.filemanager.keychain`) for encrypted credential storage.

---

## Architecture

```
filemanager-port/
├── app/                  # Flutter 3.47 client application (Material 3)
│   ├── android/          # Android native wrapper & intent handlers
│   ├── ios/              # iOS native wrapper (SceneDelegate, AVPlayer, Keychain)
│   ├── macos/            # macOS native wrapper & document associations
│   ├── linux/            # Linux desktop host runner
│   ├── windows/          # Windows desktop host runner
│   ├── lib/
│   │   ├── src/
│   │   │   ├── dialogs/  # Remote connection wizard, tasks, compression
│   │   │   ├── models/   # Entry items, capabilities, DTO adapters
│   │   │   ├── pages/    # Browser, Text Editor, Media Player, Image Viewer, Settings
│   │   │   ├── rust/     # flutter_rust_bridge generated bridge code
│   │   │   ├── services/ # ExternalFileService, StorageService, MarkdownPdfService
│   │   │   └── theme/    # Dynamic Color, accent seeds, Markdown themes
│   │   └── main.dart
│   └── test/             # Unit tests for models, PDF generation, paths, tokens
└── rust/                 # Pure Rust backend crates
    └── crates/
        ├── fm-core       # Domain types (VfsPath, Entry, LocationKind, Capabilities)
        ├── fm-vfs        # Vfs trait, metadata, and error types
        ├── fm-local      # Local filesystem Vfs implementation
        ├── fm-remote     # OpenDAL (S3, OSS, WebDAV), SFTP, FTP, SMB drivers
        ├── fm-archive    # Zip, Tar, 7z virtual filesystem and compression engine
        ├── fm-index      # Embedded SQLite persistence (remotes, bookmarks, history)
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

### iOS Device (Development & Release)
```bash
cd app
# Debug run on connected device
flutter run -d <device-id>

# Release build
flutter build ios --release --no-pub
```

### Android
```bash
cd app
flutter build apk --release
# Output: app/build/app/outputs/flutter-apk/app-release.apk
```

### macOS Desktop
```bash
cd app
flutter run -d macos
```

### Linux Desktop
```bash
cd app
flutter run -d linux
```

### Windows Desktop
```bash
cd app
flutter run -d windows
```

---

## Testing

```bash
# Run Rust workspace unit tests
cd rust && cargo test --workspace

# Run Flutter unit and regression tests
cd app && flutter test --no-pub
```

---

## License

This project is licensed under the Apache-2.0 / MIT Dual License.
