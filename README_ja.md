# クロスプラットフォーム高性能ファイルマネージャー (Rust + Flutter)

[English](README.md) | [简体中文](README_zh.md) | [日本語](README_ja.md)

iOS、Android、macOS、Windows、および Linux にネイティブ対応した、高性能かつローカルファースト（Local-First）なクロスプラットフォームファイルマネージャーです。

純粋な Rust で記述された高並行性ドメインサービス・プロトコルドライバ（`fm-*`）と、`flutter_rust_bridge` 2.13 を通じて統合された Flutter 3.47（Material 3）ユーザーインターフェースを採用。ネイティブ級の実行速度、高度なクラウドストレージプロトコル対応、そしてマルチプラットフォームで統一された操作感を提供します。

---

## 主な機能

### 1. クラウドおよびリモートストレージプロトコル (`fm-remote`)
- **Amazon S3 および互換プロトコル**: Apache OpenDAL 駆動。AWS S3、MinIO、Cloudflare R2、Ceph などのオブジェクトストレージ、Path-Style / Virtual-Host アドレッシング、AWS SigV4 認証、カスタムエンドポイントを標準サポート。
- **Alibaba Cloud OSS (Aliyun OSS)**: OpenDAL ネイティブ OSS ドライバを統合。各リージョン（`oss-cn-*.aliyuncs.com`）、OSS-HMAC 署名アルゴリズム、バケット操作、カスタムドメインエンドポイントに対応。
- **WebDAV**: Nextcloud、ownCloud、InfiniCLOUD、一般的な WebDAV サーバーに対応（Basic 認証および Digest 認証をサポート）。
- **SFTP**: `russh` と `russh-sftp` を基盤とした純粋な Rust 非同期 SSH 安全ファイル転送。
- **FTP / FTPS**: `suppaftp` に基づく非同期 FTP クライアント。明示的 TLS 暗号化とパッシブモード（EPSV / PASV）をサポート。
- **SMB2 / SMB3**: `smb2` による Windows 共有および Samba サーバー接続。

### 2. アーカイブ仮想ファイルシステム (`fm-archive`)
- **解凍不要のアーカイブ直接閲覧 (`archive://`)**: `.zip`、`.tar`、`.tar.gz`、`.tar.bz2`、`.tar.xz`、`.7z` などのアーカイブファイルを仮想フォルダとしてマウント。ストレージに解凍することなく、中身を直接閲覧・表示可能。
- **ストリーミング圧縮・解凍**: 64 KB チャンクによるストリーミング処理。リアルタイム進捗表示、速度計算、中断（キャンセル）に対応。

### 3. Markdown およびリッチドキュメントエンジン
- **ライブプレビュー＆コードエディタ**: Markdown および HTML のリアルタイムプレビューとソースコード編集。行番号、シンタックスハイライト、検索／置換、指定行ジャンプ機能を搭載。
- **6 種類の洗練されたテーマ**: GitHub（ライト／ダーク）、Dracula、Sepia、Solarized Dark、Nord、Vibrant。コードブロックのハイライトスタイルもドキュメントテーマと連動。
- **プロ仕様の PDF エクスポートエンジン**:
  - 中国語・日本語（CJK）フォントの正確なレンダリングに対応。
  - インライン AST 構文解析（太字、斜体、太字斜体、インラインコード、打ち消し線、リンク）。
  - GitHub スタイルの Markdown テーブル描画（テーマに連動した境界線、ヘッダー背景色、ゼブラストライプ）。
  - 引用ブロックおよび GitHub アラートボックス（`[!NOTE]`、`[!TIP]`、`[!IMPORTANT]`、`[!WARNING]`、`[!CAUTION]`）。
  - 3 段階のマージン（余白）プリセット：コンパクト（16 pt）、標準（36 pt）、ゆったり（54 pt）。

### 4. メディアプレイヤー（音声・動画）
- **マルチプラットフォーム・デュアルエンジン設計**:
  - **iOS 版**: Apple ネイティブのハードウェアアクセラレーション `AVPlayer` / `AVPlayerLayer`（`video_player`）を採用。リモートストリーミング時のバッファ最適化、自動復帰、画面ロック時のバックグラウンド再生に対応。
  - **デスクトップおよび他プラットフォーム**: `media_kit`（libmpv）により、幅広い動画フォーマットのハードウェア再生をサポート。
- **多彩な再生機能**: フォルダ内メディアの自動プレイリスト化、自動連続再生、再生速度調整（0.5x ～ 2.0x）、再生履歴・レジューム記憶、ジェスチャーによるシーク、縦横画面回転。

### 5. インタラクティブ画像ビューア
- ピンチズーム（Pinch-to-zoom）およびドラッグ移動。
- フォルダ内の前後の画像へ左右スワイプでシームレスに切り替え。
- クラウドおよびアーカイブ内の画像を非同期ストリーミング＆キャッシュ表示。

### 6. 全プラットフォーム外部ファイル連携（「このアプリで開く」）
- 他のアプリ（ファイル管理、メッセージアプリ、AirDrop、共有シートなど）から本アプリで直接ファイルを開く機能に対応：
  - **iOS**: `CFBundleDocumentTypes`（`public.item`、`public.content`、`public.data`）を設定。サンドボックス内の `Inbox` に安全に転送し、完全な POSIX 読み書きアクセスを確保。
  - **Android**: `ACTION_VIEW` および `ACTION_SEND` インテントフィルタを設定し、`file://` および `content://` の両形式に対応。
  - **macOS**: ドキュメントタイプ関連付けおよび `NSApplicationDelegate.application(_:openFile:)` 連携。
  - **Windows & Linux**: コマンドライン引数による起動時ファイル解析（`main(List<String> args)`）。
- 拡張子に応じて、テキストエディタ、メディアプレイヤー、画像ビューア、アーカイブブラウザへ自動ルーティング。

### 7. LAN 内 HTTP ファイル共有サーバー (`fm-server`)
- **Axum 0.8 組み込み Web サーバー**: ワンタップでローカルフォルダを Wi-Fi / LAN 内に Web 公開。
- **レスポンシブ Web UI**: ネットワーク内の任意の PC やスマートフォンからブラウザ経由でアクセス・ダウンロード可能。
- **Range Requests (HTTP 206 Partial Content)**: ブラウザ上での動画・音楽のシーク再生に対応。
- **セキュリティ**: ポート番号変更、パスワード認証、読み取り専用モード、ローカル IP アドレス自動検出。

### 8. データ永続化とセキュリティ (`fm-index`)
- **組み込み SQLite (`~/.filemanager/filemanager.db`)**: リモート接続プロファイル、ブックマーク、閲覧履歴、ゴミ箱メタデータを安全に保存。
- **ローカルゴミ箱**: ファイルをゴミ箱（`~/.filemanager/trash/`）へ移動し、ワンクリックでの復元や完全削除が可能。
- **iOS Keychain 連携**: ネイティブ Keychain サービス（`com.github.th997.filemanager.keychain`）により、認証情報を暗号化して安全に保持。

---

## アーキテクチャ構成

```
filemanager-port/
├── app/                  # Flutter 3.47 クライアントアプリ (Material 3)
│   ├── android/          # Android ネイティブ設定および Intent 処理
│   ├── ios/              # iOS ネイティブコード (SceneDelegate, AVPlayer, Keychain)
│   ├── macos/            # macOS ネイティブコードおよびドキュメント関連付け
│   ├── linux/            # Linux デスクトップランナー
│   ├── windows/          # Windows デスクトップランナー
│   ├── lib/
│   │   ├── src/
│   │   │   ├── dialogs/  # リモート接続ウィザード、タスク進捗、圧縮・解凍
│   │   │   ├── models/   # モデル定義、権限機能モデル、DTO アダプタ
│   │   │   ├── pages/    # ファイル一覧、エディタ、プレイヤー、画像ビューア、設定
│   │   │   ├── rust/     # flutter_rust_bridge 自動生成コード
│   │   │   ├── services/ # 外部ファイル受付、ストレージ管理、PDF 生成サービス
│   │   │   └── theme/    # Dynamic Color、アクセントカラー、Markdown テーマ
│   │   └── main.dart     # エントリーポイント、ウィンドウ管理、グローバルルーティング
│   └── test/             # ユニットテスト (モデル、PDF 生成、パス変換など)
└── rust/                 # 純粋な Rust バックエンドクレート
    └── crates/
        ├── fm-core       # コアドメイン型 (VfsPath, Entry, LocationKind, Capabilities)
        ├── fm-vfs        # Vfs 抽象トレイト、メタデータ型、エラー処理
        ├── fm-local      # ローカルファイルシステム実装
        ├── fm-remote     # OpenDAL (S3, OSS, WebDAV)、SFTP、FTP、SMB 実装
        ├── fm-archive    # Zip, Tar, 7z 仮想ファイルシステムおよび圧縮エンジン
        ├── fm-index      # 組み込み SQLite 永続化 (接続設定、ブックマーク、履歴)
        ├── fm-ops        # 非同期タスクエンジンおよびストリーミングパイプ
        ├── fm-server     # Axum LAN HTTP 共有サーバーおよび IP 検出
        └── fm-ffi        # Flutter 用 FFI エクスポートおよび VfsRegistry
```

---

## ビルドおよび実行方法

### 動作環境
- Flutter 3.47+ (Dart 3.13+)
- Rust 1.80+
- `flutter_rust_bridge_codegen` 2.13.0: `cargo install 'flutter_rust_bridge_codegen@2.13.0'`

### iOS 実機実行およびビルド
```bash
cd app
# 実機でのデバッグ実行
flutter run -d <device-id>

# リリースビルド
flutter build ios --release --no-pub
```

### Android ビルド
```bash
cd app
flutter build apk --release
# 生成ファイル: app/build/app/outputs/flutter-apk/app-release.apk
```

### macOS デスクトップ
```bash
cd app
flutter run -d macos
```

### Linux デスクトップ
```bash
cd app
flutter run -d linux
```

### Windows デスクトップ
```bash
cd app
flutter run -d windows
```

---

## テストの実行

```bash
# Rust ワークスペースのユニットテスト実行
cd rust && cargo test --workspace

# Flutter ユニットテストの実行
cd app && flutter test --no-pub
```

---

## ライセンス

本プロジェクトは Apache-2.0 / MIT デュアルライセンスのもとで公開されています。
