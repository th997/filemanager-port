# FP File Manager 产品功能清单与优化/重构清单

> 基线版本：`th997/filemanager-port`（commit `25e0a71`）
> 代码规模：Flutter 业务代码约 35,900 行，Rust 后端代码约 24,000 行
> 定位目标：以 **Rust 统一 VFS + 隐私保险箱 + 原生多媒体/文档无痕预览** 为核心护城河的跨平台专业文件管理器（iOS / Android / macOS / Windows / Linux）

## 一、新功能规划清单（Feature Backlog）

### P0：高感知与核心护城河

- [x] **桌面 / 平板端常驻侧边栏（Sidebar / NavigationRail）**

  * 宽屏（`width >= 900`）下将首页卡片转换为左侧常驻导航栏，分区展示：本地根目录、已解锁隐私保险箱、远程存储、收藏夹、最近访问、工具箱、传输任务、回收站与设置。

  * 支持侧边栏直接作为拖拽投放目标（将文件从右侧列表直接拖入左侧某个远程连接、收藏目录或保险箱）。

- [x] **多标签页浏览（Multi-Tab）**

  * 支持在桌面与平板端打开多个独立目录标签页（含本地、远程、压缩包、保险箱），支持 `Cmd/Ctrl+T` 新建标签、`Cmd/Ctrl+W` 关闭、`Cmd/Ctrl+Tab` 切换。

  * 支持将文件夹右键“在新标签页中打开”。

- [x] **双栏分屏模式（Dual-Pane Split View）**

  * 支持一键切换单栏/双栏视图，左右面板各自维护独立导航栈、排序与搜索状态。

  * 支持跨栏直接拖拽复制/移动，以及快捷键一键“复制到对侧面板 / 移动到对侧面板”，解决本地 ↔ NAS / S3 / 隐私保险箱高频跨源整理痛点。

- [x] **应用内 PDF 阅读器**

  * 内置跨平台 PDF 浏览（缩放、目录跳转、页码定位、文本搜索），直接通过 VFS 流式读取或内存缓冲渲染。

  * **核心价值**：打开远程存储、压缩包或**隐私保险箱**内的 PDF 时无需导出明文到系统临时目录即可查看，守住隐私零落盘闭环。

* [x] **局域网共享二维码与快速连接**

  * 在 `UtilitiesPage` 启动局域网 HTTP 共享后，自动生成并展示当前活跃 LAN IP 的二维码，手机扫码即可在浏览器直达共享页面。

  * 支持多网卡切换（Wi-Fi / 有线 / 热点）时实时更新二维码与一键复制链接。

- [x] **局域网服务自动发现（mDNS / Bonjour / SMB 扫描）**

  * 在 `RemoteWizardDialog` 中增加“扫描局域网设备”入口，自动发现局域网内的 SMB、SFTP、WebDAV、FTP 服务，点选即可预填主机与端口。

### P1：补齐专业文件管理器核心心智

- [x] **存储空间分析与大文件排行**

  * 在本地根目录与工具箱提供可视化磁盘占用分析（按文件夹大小排行、按文件类型占比分布、Top N 大文件列表），支持直接跳转定位或清理。

  * 在 `HomePage` 本地存储卡片上增加已用/可用空间进度条。

- [x] **重复文件检测与清理**

  * 基于“文件大小预筛 + 头尾采样哈希 + 完整 SHA-256 校验”的三阶段 Rust 扫描引擎，快速定位本地或指定目录下的重复文件，支持保留最新/最早并一键清理其余副本。

- [x] **首页智能分类与全局搜索**

  * 在 `HomePage` 补齐高频快捷分类入口（文档、视频、音频、压缩包、下载目录、APK 安装包），与现有“图库”并列。

  * 在 `HomePage` 顶部增加全局搜索栏，支持跨本地根目录、收藏夹与历史记录快速定位。

- [x] **高级搜索与多维筛选**

  * 扩展 `fm-ffi` 的 `search_entries` 接口，支持按文件类型（图片/视频/文档/压缩包等）、大小区间、修改时间范围、正则表达式/通配符筛选。

  * 支持本地及纯文本文件的**内容全文搜索（Grep 模式）**，命中后支持直接跳转到 `TextEditorPage` 对应行号。

- [x] **大文件传输暂停/恢复、失败重试与断点续传**

  * 在 `fm-ops` 任务引擎中增加 `Paused` 状态与单文件失败重试机制（无需重启整批任务）。

  * 针对 S3/OSS（Multipart Upload）、WebDAV/SFTP/FTP/HTTP 支持大文件断点续传与可选限速。

- [x] **加密压缩包支持（带密码 Zip / 7z）**

  * 在 `fm-archive` 中支持解密浏览与解压带密码的 `.zip`（AES / ZipCrypto）和 `.7z` 文件（弹窗提示输入密码并支持会话内记忆）。

  * 压缩对话框增加“设置密码加密”选项。

- [x] **外挂字幕自动加载与 iOS 播放器能力补齐**

  * 桌面/Android 端（`media_kit`）支持自动探测并加载同目录同名 `.srt` / `.ass` / `.vtt` 外挂字幕，并支持手动从 VFS 选取字幕文件。

  * iOS 端（`NativeMediaPlayerPage`）补齐外挂/内嵌字幕渲染及系统级画中画（PiP）支持。

### P2：差异化进阶能力

- [x] **目录同步与轻量备份（Sync / Mirror）**

  * 支持配置“本地目录 ↔ 远程目录（S3/OSS/WebDAV/SFTP/SMB）”的单向镜像或增量备份任务，执行前展示差异预览（新增/修改/删除清单）。

- [x] **远程文件离线固定（Pin Offline）**

  * 允许用户将远程存储中的高频文档、音频或参考资料标记为“离线可用”，自动同步到本地受管缓存并支持按空间上限 LRU 淘汰。

- [x] **文件完整性校验（MD5 / SHA-1 / SHA-256）**

  * 在文件属性弹窗中提供按需计算与一键比对校验和能力，支持粘贴预期哈希值即时校验是否一致。

- [x] **结构化数据预览（CSV / JSON / XML）**

  * 为 `.csv` / `.tsv` 提供可排序表格视图，为 `.json` 提供可折叠树形视图与节点路径复制。

- [x] **文本与目录差异对比（Diff）**

  * 多选两个文本文件或两个目录时，提供“对比差异”入口，直观展示行级改动或目录文件差异。

- [x] **类 Unix 文件权限查看与修改（chmod）**

  * 在 Linux / macOS 本地及 SFTP 远程属性页展示权限位（如 `rwxr-xr-x` / `0755`），支持可视化勾选修改。

- [x] **隐私保险箱进阶体验**

  * 浏览 `vault://` 目录时，在浏览器工具栏右上角常驻一键“立即锁定”按钮。

  * 支持从系统分享面板直接导入文件到隐私保险箱并在导入后可选删除原文件。

## 二、现有体验优化与问题修复清单（UX Polish & Bugfix）

| 优先级 | 模块 / 文件 | 现状问题 | 优化 / 修复目标 | 
| ----- | ----- | ----- | ----- | 
| **P0** | 文件属性弹窗 (`app/lib/src/pages/browser_page.dart`) | `_showFileInfo` 仅在 `isNativeRoot(_root)` 时触发 `_measureDirectory`，查看远程存储或隐私保险箱文件夹属性时，大小字段永远停留在“正在计算（measuring）” | 非本地目录改为支持通过 Rust VFS 递归统计（带取消令牌与超时/上限保护），或在不支持时明确显示“点击计算”按钮而非永久卡死 | 
| **P0** | 局域网共享 Web UI (`rust/crates/fm-server/src/http.rs`) | 内嵌网页界面全部硬编码为简体中文（如“筛选当前目录文件...”、“正在上传...”），未遵循 App 三语设计 | 支持根据 App 当前语言设置或浏览器 `Accept-Language` 自动切换简体中文 / English / 日本語，并允许页面右上角手动切换 | 
| **P0** | 浏览器键盘快捷键 (`app/lib/src/pages/browser_page.dart`) | 已支持全选/反选/查找/复制/剪切/粘贴/创建副本，但缺少桌面高频快捷键 | 补齐 `Cmd/Ctrl+L` 聚焦地址栏、`F2` 或 `Enter`（macOS）重命名、`Delete` / `Cmd+Backspace` 删除、`Backspace` / `Alt+Left` 返回上级、`Space` 快速预览、`Arrow Up/Down` 移动焦点项 | 
| **P1** | 局域网共享范围 (`app/lib/src/pages/utilities_page.dart`, `fm-server`) | 目前仅支持共享本地目录，且 `docs/capabilities.md` 提及的 FTP 共享服务未在 UI 暴露 | 支持在浏览器中右键直接“通过局域网共享此文件夹 / 单文件”；明确 FTP 共享的排期（实现或从能力矩阵移除） | 
| **P1** | 首页与导航效率 (`app/lib/src/pages/home_page.dart`) | 首页缺少本地存储余量提示、快速搜索入口与活跃传输任务的直接进度感知 | 为本地存储卡片增加容量条；将进行中的传输任务做成底部/顶部轻量状态条，不必每次切去 `TasksPage` 查看 | 
| **P1** | 拖拽与多选反馈 (`app/lib/src/widgets/browser/`) | 面包屑 `DragTarget` 缺少拖入悬停高亮视觉反馈；桌面端缺少 Shift 连续多选与框选（Marquee Selection） | 面包屑与文件夹列表项在拖入悬停时高亮边框并支持悬停自动展开；桌面端补齐 `Shift+Click` 区间多选和 `Cmd/Ctrl+Click` 离散多选 | 
| **P1** | 隐私保险箱外泄提示 (`app/lib/src/pages/browser_page.dart`, `file_open_service.dart`) | 用外部应用打开保险箱内文件会导出明文到 `open-with/vault_<id>` 缓存目录 | 在补齐内置 PDF 阅读器后优先走应用内无痕打开；仍需外置打开时，在确认弹窗中明确提示“锁定保险箱后会自动清理临时明文副本” | 
| **P2** | 文档与对外展示 (`README.md`, `README_zh.md`, `README_ja.md`, `docs/capabilities.md`) | `README` 遗漏隐私保险箱、批量重命名、图库、全局迷你播放条、桌面拖拽等核心卖点；`capabilities.md` 包含部分未开放功能 | 同步更新三语 README 功能章节与架构图（补上 `fm-vault` crate），对齐 `capabilities.md` 与实际 UI 交付状态 | 

## 三、架构与代码重构清单（Refactoring Checklist）

### 1. Flutter 前端核心拆分

- [ ] **拆解 `app/lib/src/pages/browser_page.dart`（进行中：`BrowserWorkspacePage` 的 `BrowserTabSpec` 已切换为持有 `BrowserPaneController` 并移除 `GlobalKey<BrowserPageState>`，地址解析等已迁入控制器，待继续迁移单体余下内部状态）— 最高优先级**

  * **痛点**：单文件耦合了目录加载与分页、剪贴板（`ClipboardState`）、搜索状态、全部文件 CRUD/上传/下载/压缩/解压流程、隐私保险箱管理、外部拖拽、文件选择器模式以及列表/网格渲染，直接阻碍多标签页和双栏分屏落地。

  * **拆分方案**：

    * `browser_pane_controller.dart`：独立的 `ChangeNotifier` 控制器，管理 `root`、`relPath`、历史栈、条目列表、分页、排序、筛选、多选集合。

    * `browser_clipboard_service.dart`：将 `ClipboardState` 提升为全局单例服务，天然支持跨标签页、跨双栏粘贴。

    * `browser_file_ops.dart`：抽离上传、下载、新建、重命名、复制/移动、删除、压缩/解压与外部拖拽处理逻辑。

    * `browser_vault_actions.dart`：抽离当前保险箱重命名、信息、安全设置、删除与锁定交互。

    * `browser_info_dialog.dart`：独立出文件/目录属性弹窗（便于后续扩展异步 VFS 大小测算、哈希校验与权限展示）。

    * `browser_pane.dart`：纯可复用浏览面板组件，供单栏、多标签和双栏分屏直接复用。

- [ ] **统一双引擎媒体播放器壳层（进行中：已抽取 `media_player_shared.dart` 共享速率持久化、时长格式化、横向拖拽定位与播放列表弹窗，待将 `MediaPlayerPage` 与 `NativeMediaPlayerPage` 合并至单一 UI 壳层）**

  * **痛点**：两套播放器合计超过 3,100 行，播放列表调度、进度记忆、倍速控制、手势调节亮度/音量/进度、全屏旋转、快捷键与 HUD 逻辑高度重复，导致新功能（如字幕、PiP）需要在两端分别维护。

  * **拆分方案**：

    * 定义统一抽象接口 `MediaPlayerEngine`（封装 play/pause/seek/rate/tracks/subtitles/streams）。

    * 提供 `MediaKitEngine` 与 `AvPlayerEngine` 两个轻量实现，共用一套 `UnifiedMediaPlayerPage` UI 壳层与控制栏组件。

- [x] **拆解 `app/lib/src/pages/text_editor_page.dart`（当前 2,586 行）**

  * 拆分为：`text_editor_controller.dart`（大文件分块读取、脏状态、撤销/重做、保存）、`editor_find_replace_bar.dart`（查找/替换与跳转行号）、`editor_preview_pane.dart`（Markdown/HTML 实时分屏预览与 PDF 导出调度）。

- [x] **拆分 `app/lib/src/dialogs/vault_dialogs.dart`（当前 2,254 行）**

  * 按业务场景拆分为 `app/lib/src/dialogs/vault/` 目录：`vault_create_dialog.dart`、`vault_unlock_dialog.dart`、`vault_security_dialog.dart`、`vault_info_gc_dialog.dart`、`vault_backup_dialogs.dart`。

- [x] **拆解 `app/lib/src/pages/image_viewer_page.dart`（当前 1,507 行）**

  * 将 EXIF 读取与 GPS 坐标解析抽离为 `app/lib/src/services/exif_service.dart`，将远程/压缩包图片预取缓存抽离为 `image_prefetch_controller.dart`，保留页面只关注手势交互与信息覆盖层。

### 2. Rust 后端模块化优化

* [x] **分离 `rust/crates/fm-server/src/http.rs` 中的前端静态资源（当前 1,553 行）**

  * 将内嵌的约 900 行 HTML/CSS/JS 字符串拆分为 `rust/crates/fm-server/assets/index.html`、`app.css`、`app.js` 及 `i18n/{en,zh,ja}.json`，通过 `include_str!` 编译期嵌入，大幅提升可维护性并为 Web UI 三语化与主题适配铺路。

- [x] **拆分 `rust/crates/fm-ffi/src/api/file_manager.rs`（当前 860 行）**

  * 将搜索与多维过滤逻辑拆出至 `api/search.rs`，将文件哈希校验与目录空间统计拆出至 `api/inspect.rs`，保持 FFI 边界按领域清晰隔离。

- [x] **增强 `rust/crates/fm-ops` 任务状态机与持久化**

  * 在 `TaskProgress` / `TaskManager` 中引入 `Paused` 状态、单条目失败列表（支持部分重试）与可选任务历史持久化，避免 App 重启后大任务状态完全丢失。

### 3. 测试与质量工程

- [x] **补齐重构护航测试**

  * 在拆解 `BrowserPage` 前，为 `BrowserPaneController`（导航栈、排序、搜索竞态、跨源剪贴板、选择状态）建立独立单元测试。

  * 为 `fm-server` 增加 HTTP Web UI 多语言响应头测试，为 `fm-ffi` 增加非本地目录大小统计取消测试与哈希校验测试。

## 四、建议分阶段迭代路线图

| 阶段 | 核心主题 | 包含的关键项 | 预期产品收益 | 
| ----- | ----- | ----- | ----- | 
| **M1（1–2 周）** | 速赢打磨与低成本高感知功能 | 修复非本地目录属性卡死；局域网共享二维码 + Web UI 三语化；补齐浏览器桌面快捷键与 Shift 多选；更新三语 README 与能力矩阵 | 零风险快速消除现有体验断点，显著提升日常口碑与开源仓库吸引力 | 
| **M2（2–4 周）** | 浏览器架构重构 + 桌面端体验跃升 | 拆解 `browser_page.dart` 为 `BrowserPaneController` + `BrowserPane`；上线宽屏常驻侧边栏、多标签页与双栏分屏；接入应用内 PDF 阅读器 | 产品形态从“移动端移植版”正式迈入“桌面级专业文件管理器”，打通隐私保险箱无痕文档闭环 | 
| **M3（3–5 周）** | 专业工具箱补齐 | 存储空间分析与重复文件清理；首页容量条、智能分类与全局搜索；高级搜索与内容检索；加密 Zip/7z；局域网 mDNS/SMB 自动发现；统一双引擎播放器壳层并补齐外挂字幕/PiP | 全面覆盖个人 NAS 运维、开发者与重度移动用户的高频刚需 | 
| **M4（按需演进）** | 传输韧性与离线同步 | `fm-ops` 暂停/恢复与断点续传；目录单向/双向同步；远程文件离线固定（Pin Offline）；文件哈希校验、Diff 与 CSV/JSON 结构化预览 | 从“文件浏览器”升级为“跨端文件工作台与轻量同步中心” | 
