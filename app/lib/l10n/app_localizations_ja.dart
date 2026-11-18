// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get aboutSection => 'アプリ情報とシステム';

  @override
  String get accentClassicBlue => 'クラシックブルー';

  @override
  String get accentColor => 'アクセントカラー';

  @override
  String get accentDeepTeal => 'ディープティール';

  @override
  String get accentDynamic => 'システム動的カラー';

  @override
  String get accentForest => 'フォレストグリーン';

  @override
  String get accentGrape => 'グレープパープル';

  @override
  String get accentIndigo => 'インディゴ';

  @override
  String get accentSunset => 'サンセットオレンジ';

  @override
  String get allPhotos => 'すべての写真';

  @override
  String get almostDone => 'まもなく完了';

  @override
  String get appTitle => 'FPファイルマネージャー';

  @override
  String get appearance => '外観';

  @override
  String get ascending => '昇順';

  @override
  String get bookmarks => 'ブックマーク';

  @override
  String get browseInAppUpload => 'アプリ内で選択してアップロード…';

  @override
  String get browserSection => 'ブラウザー';

  @override
  String get bucketName => 'バケット名';

  @override
  String get bucketNameHint => '小文字、数字、ハイフンのみ対応（3〜63文字）';

  @override
  String get bucketRootFolderUploadError =>
      '複数バケットのルートです。フォルダーをアップロードする前にバケットを開いてください。';

  @override
  String get bucketRootTransferError => '複数バケットのルートです。転送する前にバケットを開いてください。';

  @override
  String get bucketRootUploadError =>
      '複数バケットのルートです。ファイルをアップロードする前にバケットを開いてください。';

  @override
  String get bufferDuration => 'バッファ時間';

  @override
  String get bufferSize => 'バッファサイズ';

  @override
  String get cancel => 'キャンセル';

  @override
  String get cancelTask => 'タスクをキャンセル';

  @override
  String get cancelled => 'キャンセル済み';

  @override
  String get cancelling => 'キャンセル中…';

  @override
  String get cannotCancelTask => 'このタスクはキャンセルできません';

  @override
  String cannotClearFinishedTasks(Object count) {
    return '$count 件の完了タスクを消去できません';
  }

  @override
  String get cannotDismissTask => 'このタスクを消去できません';

  @override
  String get change => '変更';

  @override
  String get clear => 'クリア';

  @override
  String get clearFinished => '完了項目を消去';

  @override
  String get close => '閉じる';

  @override
  String get closeSearch => '検索を閉じる';

  @override
  String get cloudRemoteStorage => 'クラウド・リモートストレージ';

  @override
  String get cloudToolsSettings => 'クラウド、ツールと設定';

  @override
  String get completed => '完了';

  @override
  String compressFailed(Object error) {
    return '圧縮失敗: $error';
  }

  @override
  String get compressing => '圧縮中…';

  @override
  String get connectServer => 'サーバーに接続';

  @override
  String get copyError => 'エラーをコピー';

  @override
  String copyFailed(Object error) {
    return 'コピー失敗: $error';
  }

  @override
  String get copyPassword => 'パスワードをコピー';

  @override
  String get copyUrl => 'URLをコピー';

  @override
  String get copyingFiles => 'ファイルをコピー中…';

  @override
  String get create => '作成';

  @override
  String createdCandidate(Object name) {
    return '「$name」を作成しました';
  }

  @override
  String get creatingCopy => 'コピーを作成中…';

  @override
  String get darkTheme => 'ダークテーマ';

  @override
  String get delete => '削除';

  @override
  String deleteFailed(Object error) {
    return '削除失敗: $error';
  }

  @override
  String deletedCount(Object count) {
    return '$count 項目を削除しました';
  }

  @override
  String get deleting => '削除中…';

  @override
  String get descending => '降順';

  @override
  String get desktopHtmlPreviewHint =>
      'デスクトップ版は簡易HTMLプレビューです。完全なJS/CSS効果を表示するにはブラウザーで開いてください。';

  @override
  String get dismiss => '閉じる';

  @override
  String get downloadDestination => 'ダウンロード先フォルダーを選択';

  @override
  String downloadFailed(Object error) {
    return 'ダウンロード失敗: $error';
  }

  @override
  String downloadedTo(Object path) {
    return '$path にダウンロードしました';
  }

  @override
  String downloadingFile(Object file) {
    return '$file をダウンロード中…';
  }

  @override
  String get downloadingFiles => 'ファイルをダウンロード中…';

  @override
  String downloadingItem(Object name) {
    return '$name をダウンロード中…';
  }

  @override
  String duplicateFailed(Object error) {
    return '複製失敗: $error';
  }

  @override
  String get emptyRecycleBin => 'ごみ箱を空にする';

  @override
  String get errorCopied => 'エラー情報をクリップボードにコピーしました';

  @override
  String get exportPreviewCache => 'エクスポートとプレビューのキャッシュ';

  @override
  String extractFailed(Object error) {
    return '展開失敗: $error';
  }

  @override
  String get extracting => '展開中…';

  @override
  String get failed => '失敗';

  @override
  String failedToCreate(Object error) {
    return '作成に失敗しました: $error';
  }

  @override
  String get finalizingServer => '完了処理中（サーバー処理中）…';

  @override
  String get folderLabel => 'フォルダー';

  @override
  String get folderName => 'フォルダー名';

  @override
  String get followSystemSettings => 'システム設定に従う';

  @override
  String get gallery => 'ギャラリー';

  @override
  String get homeDashboard => 'ホームに戻る';

  @override
  String hoursLeft(Object hours) {
    return '残り約 $hours 時間';
  }

  @override
  String hoursMinutesLeft(Object hours, Object minutes) {
    return '残り約 $hours 時間 $minutes 分';
  }

  @override
  String get inProgress => '進行中';

  @override
  String get invertSelection => '選択を反転';

  @override
  String itemsCount(Object count) {
    return '$count 項目';
  }

  @override
  String itemsOutOfTotal(Object completed, Object total) {
    return '$completed / $total 項目';
  }

  @override
  String get lanSharing => 'LAN HTTP Web共有';

  @override
  String get language => '言語';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get lightTheme => 'ライトテーマ';

  @override
  String get localStorage => 'ローカルストレージ';

  @override
  String get mediaPlayback => 'メディア再生（リモートバッファ）';

  @override
  String get minimize => '最小化';

  @override
  String minutesLeft(Object minutes) {
    return '残り約 $minutes 分';
  }

  @override
  String moveFailed(Object error) {
    return '移動失敗: $error';
  }

  @override
  String get movingFiles => 'ファイルを移動中…';

  @override
  String get newBucket => '新規バケット';

  @override
  String get newFile => '新規ファイル';

  @override
  String get newFolder => '新規フォルダー';

  @override
  String get newTextFile => '新規テキストファイル';

  @override
  String get noLanIpFound => 'LAN IPが検出されませんでした。Wi-Fiまたは有線LANに接続してください。';

  @override
  String get noTasksYet => 'タスクはありません';

  @override
  String get openInBrowser => 'ブラウザーで開く';

  @override
  String get options => 'オプション';

  @override
  String get passwordCopied => 'パスワードをクリップボードにコピーしました';

  @override
  String get passwordFieldHelper =>
      '空欄の場合はToken付きリンクで直接アクセス（パスワード不要）；設定するとパスワードログインも可能';

  @override
  String get passwordFieldLabel => 'アクセスパスワード（任意）';

  @override
  String get playbackSpeed => '再生速度';

  @override
  String get pleaseSelectSpecificFolder => 'アップロードする具体的なフォルダーを選択してください';

  @override
  String get port => 'ポート';

  @override
  String get previewImage => '画像をプレビュー';

  @override
  String get processingPercent => '100% (処理中)';

  @override
  String get readOnly => ' (読み取り専用)';

  @override
  String get readOnlyMode => '読み取り専用モード（Webからのアップロード禁止）';

  @override
  String get recent => '履歴';

  @override
  String get recentDirs => '最近のフォルダー:';

  @override
  String get recycleBin => 'ごみ箱';

  @override
  String get remote => 'リモート';

  @override
  String get remoteArchiveCache => 'リモートとアーカイブのキャッシュ';

  @override
  String get retry => '再試行';

  @override
  String retryFailed(Object error) {
    return '再試行に失敗しました: $error';
  }

  @override
  String get runInBackground => 'バックグラウンド';

  @override
  String get runningOnLan => '🟢 LANで稼働中';

  @override
  String get save => '保存';

  @override
  String get scriptDisabledTooltip => 'スクリプト無効（安全なデフォルト）。クリックして有効化';

  @override
  String get scriptEnabledTooltip =>
      'スクリプト有効: ページコードは共有フォルダー内のファイルにアクセスできます。クリックして無効化';

  @override
  String get searchFiles => 'ファイルを検索';

  @override
  String secondsLeft(Object seconds) {
    return '残り約 $seconds 秒';
  }

  @override
  String get selectAll => 'すべて選択';

  @override
  String get selectFolderToUpload => 'アップロードするフォルダーを選択';

  @override
  String get selectItems => '複数選択';

  @override
  String get settings => '設定';

  @override
  String get settingsCardSubtitle => 'テーマ、システム情報、アプリ情報';

  @override
  String get shareInstructions =>
      '同一Wi-Fi環境のブラウザーで以下のアドレスを開いてアクセスできます（トークンが含まれるため公開共有しないでください）:';

  @override
  String get sharePasswordLabel => 'アクセスパスワード';

  @override
  String sharePasswordNotice(Object pwd) {
    return '共有パスワードを自動生成しました: $pwd';
  }

  @override
  String get shared => '共有フォルダー';

  @override
  String get sharedPathCopied => '共有フォルダーのパスをコピーしました';

  @override
  String get showHiddenFiles => '隠しファイルを表示';

  @override
  String skippedAlreadyExists(Object count) {
    return '$count 項目をスキップしました（既に存在）';
  }

  @override
  String get sortBy => '並べ替え';

  @override
  String get splitView => '2画面表示';

  @override
  String get stopped => '⚪ 停止';

  @override
  String get storageAndCache => 'ストレージとキャッシュ';

  @override
  String get supportedProtocols => '対応プロトコル';

  @override
  String get switchToGrid => 'グリッド表示に切り替え';

  @override
  String get switchToList => 'リスト表示に切り替え';

  @override
  String get switchedToBackground => 'バックグラウンドで実行中 — ホーム → タスクで進捗を確認できます';

  @override
  String get systemPicker => 'システムピッカー';

  @override
  String get taskCompress => '圧縮';

  @override
  String get taskCopy => 'コピー';

  @override
  String get taskDelete => '削除';

  @override
  String get taskExtract => '展開';

  @override
  String get taskGeneric => 'タスク';

  @override
  String get taskMove => '移動';

  @override
  String get tasks => 'タスク';

  @override
  String get tasksEmptySubtitle => 'コピー、移動、その他の実行時間の長い操作がここに表示されます。';

  @override
  String get theme => 'テーマ';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeSystem => 'システムに従う';

  @override
  String get toolbarAtBottom => 'ツールバーを下部に配置';

  @override
  String get toolbarAtBottomDesc => 'アドレスバーとアイコンをファイル一覧の下に移動します';

  @override
  String get transferring => '転送中…';

  @override
  String trashCountNotice(Object count) {
    return 'ごみ箱に $count 項目あります';
  }

  @override
  String get upload => 'アップロード';

  @override
  String get uploadFiles => 'ファイルをアップロード';

  @override
  String get uploadFolder => 'フォルダーをアップロード';

  @override
  String get uploadItemsToCurrentFolder => '現在のフォルダーにファイル/フォルダーをアップロード';

  @override
  String get uploadThisFolder => 'このフォルダーをアップロード';

  @override
  String get uploadWithSystemPicker => 'アップロードにシステムピッカーを使用';

  @override
  String get uploadWithSystemPickerDesc => 'OS標準のファイル選択ダイアログを呼び出します';

  @override
  String uploadingFolder(Object folder) {
    return 'フォルダー「$folder」をアップロード中…';
  }

  @override
  String uploadingItems(Object count) {
    return '$count 項目をアップロード中…';
  }

  @override
  String get urlCopied => 'URLをクリップボードにコピーしました';

  @override
  String get utilities => 'ユーティリティ';

  @override
  String get waiting => '待機中…';

  @override
  String get waitingServerVerify => 'データ送信完了、サーバー側の検証と統合を待機中…';

  @override
  String get webSharingServer => 'LAN Web共有サーバー';

  @override
  String get welcomeBody =>
      'ローカルフォルダーをすぐに閲覧するか、サーバー（SFTP、WebDAV、S3、SMBなど）に接続してどこからでもファイルを管理できます。';

  @override
  String get welcomeTitle => 'FPファイルマネージャーへようこそ';

  @override
  String get invalidBucketName => '無効なバケット名です。3〜63文字で、英小文字、数字、ハイフンのみ使用できます。';

  @override
  String get sortByName => '名前順';

  @override
  String get sortBySize => 'サイズ順';

  @override
  String get sortByDate => '更新日時順';

  @override
  String get sortByType => '種類順';

  @override
  String get openSourceLicenses => 'オープンソースライセンス';

  @override
  String get openSourceLicensesSubtitle => 'サードパーティ製オープンソースソフトウェアのライセンス';
}
