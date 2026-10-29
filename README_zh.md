# 跨平台高性能文件管理器 (Rust + Flutter)

[English](README.md) | [简体中文](README_zh.md) | [日本語](README_ja.md)

基于 Rust 和 Flutter 构建的高性能、本地优先（Local-First）跨平台文件管理器，原生支持 iOS、Android、macOS、Windows 和 Linux。

项目底层采用纯 Rust 编写的高并发领域服务与存储协议驱动（`fm-*`），通过 `flutter_rust_bridge` 2.13 高效桥接至 Flutter 3.47（Material 3）现代化界面，兼具原生级别的执行性能、深度的云存储协议支持与多端统一的交互体验。

---

## 核心特性

### 1. 云存储与网络协议栈 (`fm-remote`)
- **Amazon S3 与兼容协议**：基于 Apache OpenDAL 驱动，原生支持 AWS S3、MinIO、Cloudflare R2、Ceph 等对象存储，支持路径风格（Path-Style）与虚拟主机风格寻址、AWS SigV4 认证及自定义终端节点（Endpoint）。
- **阿里云对象存储 (Aliyun OSS)**：集成 OpenDAL 原生 OSS 驱动，完美支持国内各大地域节点（`oss-cn-*.aliyuncs.com`）、OSS-HMAC 签名算法、Bucket 存取与自定义 CDN 加速域名。
- **WebDAV**：深度适配 Nextcloud、ownCloud、坚果云、InfiniCLOUD 及各类通用 WebDAV 服务器，支持 Basic 与 Digest 认证机制。
- **SFTP**：基于 `russh` 与 `russh-sftp` 实现的纯 Rust 异步 SSH 安全文件传输。
- **FTP / FTPS**：基于 `suppaftp` 实现的异步 FTP 客户端，支持显式 TLS 加密传输与被动传输模式（EPSV / PASV）。
- **SMB2 / SMB3**：基于 `smb2` 原生对接 Windows 网络共享及局域网 Samba 服务器。

### 2. 压缩包虚拟文件系统 (`fm-archive`)
- **压缩包免解压穿透浏览 (`archive://`)**：将 `.zip`、`.tar`、`.tar.gz`、`.tar.bz2`、`.tar.xz` 和 `.7z` 等归档文件虚拟化为文件系统目录，无需提前解压至磁盘即可直接深入浏览、读取文件。
- **流式解压与压缩**：采用 64 KB 分块流式管道处理压缩与解压，具备实时进度回调、速度预估与随时取消能力。

### 3. Markdown 与富文本文档引擎
- **实时预览与代码编辑**：支持 Markdown 与 HTML 双模式渲染预览，内置带行号、语法高亮、查找/替换与“跳转到行”的专业级编辑器。
- **6 套深度定制色彩主题**：GitHub（浅色/深色）、Dracula（吸血鬼）、Sepia（复古羊皮纸）、Solarized Dark、Nord（极地冷色）、Vibrant（活力高亮），代码块高亮风格与文档主题深度联动。
- **专业级 PDF 导出引擎**：
  - 内置高质量中文字体加载，彻底根除 CJK 乱码与文字溢出问题。
  - 基于 AST 语法的行内样式递归解析，支持粗体、斜体、粗斜体、行内代码、删除线与超链接。
  - GitHub 风格 Markdown 表格渲染，包含主题化边框、表头底色与交替斑马纹。
  - 支持引用块与 GitHub 提示卡片（`[!NOTE]`、`[!TIP]`、`[!IMPORTANT]`、`[!WARNING]`、`[!CAUTION]`）。
  - 可选 3 档精准页面边距预设：紧凑（16 pt）、标准（36 pt）、宽松（54 pt）。

### 4. 影音多媒体播放器
- **多平台双引擎架构**：
  - **iOS 端**：采用 Apple 原生硬件加速 `AVPlayer` / `AVPlayerLayer`（`video_player`），解决远程网络流微小抖动时底层 mpv 驱动引起的自动暂停与断音问题，支持锁屏后台音频播放与低延迟自适应流缓冲。
  - **桌面端及其他平台**：基于 `media_kit`（libmpv），支持全格式硬解与外挂音轨/字幕。
- **完备播放控制**：目录媒体列表自动拉取、自动连播下一曲、倍速微调（0.5x – 2.0x）、历史进度记忆续播、手势快进/快退与横竖屏旋转适配。

### 5. 交互式图片画廊
- 支持双指缩放（Pinch-to-zoom）、平移拖拽与手势恢复。
- 支持同一目录下图片左右滑动手势无缝切图。
- 远程云端与压缩包内图片采用智能异步流式导出与缓存机制。

### 6. 全平台外部文件“用其他应用打开”系统集成
- 完美支持从微信、系统“文件”App、AirDrop、邮件附件或浏览器分享到本应用并直接打开：
  - **iOS**：配置 `CFBundleDocumentTypes` 绑定 `public.item`、`public.content` 与 `public.data`，自动通过沙盒 `Inbox` 进行安全隔离转存，赋予应用完整的 POSIX 读写权限。
  - **Android**：注册 `ACTION_VIEW` 与 `ACTION_SEND` 意图过滤器，支持 `file://` 与 `content://` 流式内容解析。
  - **macOS**：配置文档类型关联并监听 `NSApplicationDelegate.application(_:openFile:)`。
  - **Windows & Linux**：支持通过命令行传参启动解析（`main(List<String> args)`）。
- 依据文件扩展名智能分流至内置文本编辑器、影音播放器、图片浏览器或压缩包穿透视图，未知格式无缝移交系统默认应用打开。

### 7. 局域网 HTTP 文件共享服务器 (`fm-server`)
- **Axum 0.8 原生 HTTP 服务**：一键开启局域网共享，将本地任意目录映射为 Web 站点。
- **现代化响应式 Web 控制台**：局域网内任意手机、平板或 PC 浏览器扫码即可直接访问并下载文件。
- **分段范围请求（Range Requests）**：完整支持 HTTP 206 Partial Content，可在浏览器中边下边播高清视音频。
- **访问控制**：支持自定义服务端口、访问密码鉴权、只读保护开关与局域网本机 IP 自动探测。

### 8. 数据持久化与系统级安全 (`fm-index`)
- **嵌入式 SQLite (`~/.filemanager/filemanager.db`)**：安全存储远程连接配置、收藏夹书签、LRU 路径访问历史与回收站元数据。
- **本地回收站**：删除操作默认转移至安全回收站目录（`~/.filemanager/trash/`），支持一键还原与永久粉碎。
- **iOS Keychain 安全存储**：通过原生 Keychain 存储加密凭据，保障远端连接鉴权信息的安全。

---

## 项目工程架构

```
filemanager-port/
├── app/                  # Flutter 3.47 客户端工程 (Material 3)
│   ├── android/          # Android 原生配置与 Intent 意图处理
│   ├── ios/              # iOS 原生工程 (SceneDelegate, AVPlayer 驱动, Keychain)
│   ├── macos/            # macOS 原生工程与文档类型关联
│   ├── linux/            # Linux 桌面宿主工程
│   ├── windows/          # Windows 桌面宿主工程
│   ├── lib/
│   │   ├── src/
│   │   │   ├── dialogs/  # 远端连接向导、任务进度弹窗、压缩解压面板
│   │   │   ├── models/   # 核心实体类、权限能力模型、DTO 转换适配器
│   │   │   ├── pages/    # 目录浏览页、文本编辑器、多媒体播放器、图片查看器、系统设置
│   │   │   ├── rust/     # flutter_rust_bridge 自动生成的桥接接口代码
│   │   │   ├── services/ # 外部文件调度服务、存储管理、Markdown PDF 导出服务
│   │   │   └── theme/    # Dynamic Color 动态取色、强调色盘、Markdown 主题定义
│   │   └── main.dart     # 入口文件、窗口尺寸持久化与全局路由调度
│   └── test/             # 单元测试（模型解析、PDF 导出、路径转换、主题令牌）
└── rust/                 # 纯 Rust 后端 Crate 组织
    └── crates/
        ├── fm-core       # 核心领域实体 (VfsPath, Entry, LocationKind, Capabilities)
        ├── fm-vfs        # Vfs 统一抽象 Trait、元数据定义与通用错误处理
        ├── fm-local      # 本地文件系统实现
        ├── fm-remote     # OpenDAL (S3, OSS, WebDAV)、SFTP、FTP、SMB 驱动实现
        ├── fm-archive    # Zip, Tar, 7z 虚拟文件系统与流式压缩引擎
        ├── fm-index      # 嵌入式 SQLite 持久化 (远端配置、书签、历史记录)
        ├── fm-ops        # 异步任务调度调度引擎与流式传输管道
        ├── fm-server     # 基于 Axum 的局域网 HTTP Web 共享服务与 IP 探测
        └── fm-ffi        # 导出给 Flutter 的 FFI 接口与全局 VfsRegistry 注册中心
```

---

## 编译与运行指南

### 环境要求
- Flutter 3.47+ (Dart 3.13+)
- Rust 1.80+
- `flutter_rust_bridge_codegen` 2.13.0: `cargo install 'flutter_rust_bridge_codegen@2.13.0'`

### iOS 真机运行与打包
```bash
cd app
# 连接真机调试运行
flutter run -d <device-id>

# 签名打包 Release 版本
flutter build ios --release --no-pub
```

### Android 打包
```bash
cd app
flutter build apk --release
# 生成文件位置: app/build/app/outputs/flutter-apk/app-release.apk
```

### macOS 桌面端
```bash
cd app
flutter run -d macos
```

### Linux 桌面端
```bash
cd app
flutter run -d linux
```

### Windows 桌面端
```bash
cd app
flutter run -d windows
```

---

## 测试验证

```bash
# 运行 Rust 全局工作区单元测试
cd rust && cargo test --workspace

# 运行 Flutter 单元与回归测试
cd app && flutter test --no-pub
```

---

## 开源协议

本项目采用 Apache-2.0 / MIT 双重许可授权。
