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
  String get actionInfo => '情報';

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
  String get playWithMediaKit => 'MediaKitエンジンで再生';

  @override
  String get cancelling => 'キャンセル中…';

  @override
  String get cannotCancelTask => 'このタスクはキャンセルできません';

  @override
  String cannotClearFinishedTasks(int count) {
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
  String compressFailed(String error) {
    return '圧縮失敗: $error';
  }

  @override
  String get compressing => '圧縮中…';

  @override
  String get connectServer => 'サーバーに接続';

  @override
  String get copyError => 'エラーをコピー';

  @override
  String copyFailed(String error) {
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
  String createdCandidate(String name) {
    return '「$name」を作成しました';
  }

  @override
  String get creatingCopy => 'コピーを作成中…';

  @override
  String get darkTheme => 'ダークテーマ';

  @override
  String get delete => '削除';

  @override
  String deleteFailed(String error) {
    return '削除失敗: $error';
  }

  @override
  String deletedCount(int count) {
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
  String downloadFailed(String error) {
    return 'ダウンロード失敗: $error';
  }

  @override
  String downloadedTo(String path) {
    return '$path にダウンロードしました';
  }

  @override
  String downloadingFile(String file) {
    return '$file をダウンロード中…';
  }

  @override
  String get downloadingFiles => 'ファイルをダウンロード中…';

  @override
  String downloadingItem(String name) {
    return '$name をダウンロード中…';
  }

  @override
  String duplicateFailed(String error) {
    return '複製失敗: $error';
  }

  @override
  String get emptyRecycleBin => 'ごみ箱を空にする';

  @override
  String get endpointHintS3 => 'エンドポイント（AWS は任意、MinIO/R2 は必須）';

  @override
  String get endpointHintGeneric =>
      'エンドポイント（例: https://oss-cn-hangzhou.aliyuncs.com）';

  @override
  String get errorCopied => 'エラー情報をクリップボードにコピーしました';

  @override
  String get exportPreviewCache => 'エクスポートとプレビューのキャッシュ';

  @override
  String extractFailed(String error) {
    return '展開失敗: $error';
  }

  @override
  String get extracting => '展開中…';

  @override
  String get failed => '失敗';

  @override
  String failedToCreate(String error) {
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
  String hoursLeft(int hours) {
    return '残り約 $hours 時間';
  }

  @override
  String hoursMinutesLeft(int hours, int minutes) {
    return '残り約 $hours 時間 $minutes 分';
  }

  @override
  String get inProgress => '進行中';

  @override
  String get invertSelection => '選択を反転';

  @override
  String itemsCount(int count) {
    return '$count 項目';
  }

  @override
  String itemsOutOfTotal(int completed, int total) {
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
  String minutesLeft(int minutes) {
    return '残り約 $minutes 分';
  }

  @override
  String monthYearLabel(String month, int year) {
    return '$year年$month';
  }

  @override
  String get monthSeptember => '9月';

  @override
  String get monthOctober => '10月';

  @override
  String get monthNovember => '11月';

  @override
  String get monthMay => '5月';

  @override
  String get monthMarch => '3月';

  @override
  String get monthJune => '6月';

  @override
  String get monthJuly => '7月';

  @override
  String get monthJanuary => '1月';

  @override
  String get monthFebruary => '2月';

  @override
  String get monthDecember => '12月';

  @override
  String get monthAugust => '8月';

  @override
  String get monthApril => '4月';

  @override
  String moveFailed(String error) {
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
  String get pdfMarginStandard => '標準 (36pt)';

  @override
  String get pdfMarginRelaxed => 'ゆったり (54pt)';

  @override
  String get pdfMarginCompact => 'コンパクト (16pt)';

  @override
  String get pickFileTitle => 'ファイルを選択';

  @override
  String get pickFilesTitle => 'ファイルを選択';

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
  String get quickVolumes => 'ボリューム';

  @override
  String get quickRoot => 'ルート /';

  @override
  String get quickPictures => '画像';

  @override
  String get quickHome => 'ホーム';

  @override
  String get quickInbox => '専用スペース';

  @override
  String get privateInboxSubtitle => 'アプリ専用 · 他アプリから非公開';

  @override
  String quickDrive(String letter) {
    return 'ドライブ ($letter:)';
  }

  @override
  String get quickDownloads => 'ダウンロード';

  @override
  String get quickDownload => 'ダウンロード';

  @override
  String get quickDesktop => 'デスクトップ';

  @override
  String get quickDcim => 'DCIM（写真）';

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
  String retryFailed(String error) {
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
  String secondsLeft(int seconds) {
    return '残り約 $seconds 秒';
  }

  @override
  String get selectAll => 'すべて選択';

  @override
  String selectCount(int count) {
    return '選択 ($count)';
  }

  @override
  String get selectFolderToUpload => 'アップロードするフォルダーを選択';

  @override
  String get selectItems => '複数選択';

  @override
  String pickerItemCounts(int folders, int files) {
    return '$folders 件のフォルダ、$files 件のファイル';
  }

  @override
  String selectedCountLabel(int count) {
    return '$count 件選択';
  }

  @override
  String selectedCountBytesLabel(int count, String size) {
    return '$count 件選択 ($size)';
  }

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
  String sharePasswordNotice(String pwd) {
    return '共有パスワードを自動生成しました: $pwd';
  }

  @override
  String get shared => '共有フォルダー';

  @override
  String get sharedPathCopied => '共有フォルダーのパスをコピーしました';

  @override
  String get showHiddenFiles => '隠しファイルを表示';

  @override
  String skippedAlreadyExists(int count) {
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
  String get toolbarUpOneLevel => '1つ上の階層へ';

  @override
  String get toolbarJump => 'ジャンプ';

  @override
  String get toolbarForwardHistory => '履歴を進む (Alt+→)';

  @override
  String get toolbarEditAddress => 'アドレスを編集 (Cmd/Ctrl+L)';

  @override
  String get toolbarBackHistory => '履歴を戻る (Alt+←)';

  @override
  String get transferring => '転送中…';

  @override
  String trashCountNotice(int count) {
    return 'ごみ箱に $count 項目あります';
  }

  @override
  String get unknownDate => '日付不明';

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
  String uploadingFolder(String folder) {
    return 'フォルダー「$folder」をアップロード中…';
  }

  @override
  String uploadingItems(int count) {
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

  @override
  String get open => '開く';

  @override
  String get openWith => '他のアプリで開く';

  @override
  String get openAsText => 'テキストとして開く';

  @override
  String get openAsTextSubtitle => '内蔵テキストエディタで開く';

  @override
  String get openWithOtherApp => '外部アプリで開く';

  @override
  String get openWithOtherAppSubtitle => 'システム標準または外部アプリを使用';

  @override
  String get openAsMedia => 'メディアとして開く';

  @override
  String get openAsMediaSubtitle => '内蔵メディアプレーヤーで再生';

  @override
  String get openAsImage => '画像として開く';

  @override
  String get openAsImageSubtitle => '内蔵画像ビューアで表示';

  @override
  String get download => 'ダウンロード';

  @override
  String get downloadToLocal => 'ローカルにダウンロード';

  @override
  String get copy => 'コピー';

  @override
  String get cut => '切り取り';

  @override
  String pasteCount(int count) {
    return '貼り付け ($count)';
  }

  @override
  String get copyPath => 'パスをコピー';

  @override
  String get copyFolderPath => 'フォルダのパスをコピー';

  @override
  String get copyFilePath => 'ファイルのパスをコピー';

  @override
  String get copyOriginalPath => '元のパスをコピー';

  @override
  String get pathCopied => 'パスをクリップボードにコピーしました';

  @override
  String get folderPathCopied => 'フォルダのパスをクリップボードにコピーしました';

  @override
  String copiedPathValue(String path) {
    return 'パスをコピーしました: $path';
  }

  @override
  String copiedValue(String value) {
    return 'コピーしました: $value';
  }

  @override
  String copiedItemToClipboard(String name) {
    return '$name をクリップボードにコピーしました';
  }

  @override
  String cutItemToClipboard(String name) {
    return '$name を切り取りました';
  }

  @override
  String copiedItemsCount(int count) {
    return '$count 個の項目をクリップボードにコピーしました';
  }

  @override
  String cutItemsCount(int count) {
    return '$count 個の項目を切り取りました';
  }

  @override
  String get rename => '名前を変更';

  @override
  String get newName => '新しい名前';

  @override
  String get duplicate => '複製';

  @override
  String get share => '共有';

  @override
  String get properties => 'プロパティ';

  @override
  String get details => '詳細';

  @override
  String get extractHere => 'ここに展開';

  @override
  String get compress => '圧縮';

  @override
  String get compressToZip => 'ZIP に圧縮';

  @override
  String get archiveName => 'アーカイブ名';

  @override
  String get bookmarkThisFolder => 'このフォルダをブックマーク';

  @override
  String get bookmarkLocation => '場所をブックマーク';

  @override
  String bookmarkedName(String name) {
    return '「$name」をブックマークしました';
  }

  @override
  String alreadyBookmarked(String name) {
    return '「$name」は既にブックマークされています';
  }

  @override
  String get refresh => '更新';

  @override
  String get undo => '元に戻す';

  @override
  String get discard => '破棄';

  @override
  String get go => '移動';

  @override
  String get goUp => '上へ';

  @override
  String get loadMore => 'さらに読み込む';

  @override
  String get clearFilter => 'フィルターをクリア';

  @override
  String get clearSearch => '検索をクリア';

  @override
  String get searchAction => '検索';

  @override
  String get remove => '削除';

  @override
  String removedName(String name) {
    return '「$name」を削除しました';
  }

  @override
  String get unknownSize => '不明';

  @override
  String get wrapIndicator => '折り返し';

  @override
  String get yes => 'はい';

  @override
  String get no => 'いいえ';

  @override
  String get ok => 'OK';

  @override
  String get typeLabel => '種類';

  @override
  String get nameLabel => '名前';

  @override
  String get pathLabel => 'パス';

  @override
  String get extensionLabel => '拡張子';

  @override
  String get sizeLabel => 'サイズ';

  @override
  String get modifiedLabel => '変更済み';

  @override
  String get hiddenLabel => '隠しファイル';

  @override
  String get hiddenFilesOff => '非表示ファイルを除く';

  @override
  String get symlinkLabel => 'シンボリックリンク';

  @override
  String get directoryLabel => 'ディレクトリ';

  @override
  String get directoryEmptyLabel => 'ディレクトリ（空）';

  @override
  String get fileLabel => 'ファイル';

  @override
  String get archiveLabel => 'アーカイブ';

  @override
  String get measuring => '計測中…';

  @override
  String bytesUnit(String count) {
    return '$count バイト';
  }

  @override
  String yesBytes(String formatted, String raw) {
    return '$formatted ($raw バイト)';
  }

  @override
  String get downloadFileTitle => 'ファイルをダウンロードしますか？';

  @override
  String get downloadFileStreamHint =>
      'このファイルはストリーミングプレビューに対応していないため、先にダウンロードする必要があります。';

  @override
  String get saveDestination => '保存先';

  @override
  String get chooseDownloadFolder => 'ダウンロード先フォルダを選択';

  @override
  String get folderIsEmpty => 'フォルダは空です';

  @override
  String get noMatchingItems => '一致する項目がありません';

  @override
  String get openFolderTooltip => 'フォルダを開く';

  @override
  String get deselectAll => 'すべて選択解除';

  @override
  String get filterFilesFoldersHint => 'ファイルとフォルダを絞り込む...';

  @override
  String get noSubfolders => 'サブフォルダはありません';

  @override
  String get noMatchingSubfolders => '一致するサブフォルダがありません';

  @override
  String get hideHiddenFolders => '隠しフォルダを非表示';

  @override
  String get showAllFileTypes => 'すべてのファイル';

  @override
  String get showHiddenFolders => '隠しフォルダを表示';

  @override
  String get hideHiddenFiles => '隠しファイルを非表示';

  @override
  String get filterSubfoldersHint => 'サブフォルダを絞り込む...';

  @override
  String get cannotReadFolderPrefix => 'このフォルダを読み取れません: ';

  @override
  String failedCreateFolder(String error) {
    return 'フォルダの作成に失敗しました: $error';
  }

  @override
  String get filterEllipsis => '絞り込み...';

  @override
  String get parentFolderTooltip => '親フォルダ';

  @override
  String get clickToCopyPath => 'クリックしてパスをコピー';

  @override
  String get folderNameHint => '例: Documents';

  @override
  String get folderNameInputLabel => 'フォルダ名';

  @override
  String couldNotRequestFileAccess(String error) {
    return 'ファイルアクセス権をリクエストできませんでした: $error';
  }

  @override
  String couldNotRefreshHome(String error) {
    return 'ホームデータを更新できませんでした: $error';
  }

  @override
  String get storagePermissionRequired =>
      'ファイルを閲覧するにはストレージ権限が必要です。次の画面で「すべてのファイルへのアクセス」を許可してください。';

  @override
  String get requesting => 'リクエスト中…';

  @override
  String get grant => '許可';

  @override
  String get remoteProtocolsSubtitle => 'S3、OSS、SFTP、WebDAV...';

  @override
  String utilitiesTrashSubtitle(int count) {
    return 'ゴミ箱に $count 件 • Web 共有';
  }

  @override
  String get utilitiesDefaultSubtitle => 'ゴミ箱、Web 共有、キャッシュ';

  @override
  String get tasksDefaultSubtitle => '転送と操作';

  @override
  String get bookmarksDefaultSubtitle => '保存済みフォルダ';

  @override
  String get recentDefaultSubtitle => '閲覧履歴';

  @override
  String get sortLabelName => '名前';

  @override
  String get sortLabelSize => 'サイズ';

  @override
  String get sortLabelDate => '日時';

  @override
  String get sortLabelType => '種類';

  @override
  String couldNotLoadMore(String error) {
    return 'さらに読み込めませんでした: $error';
  }

  @override
  String refreshFailed(String error) {
    return '更新に失敗しました: $error';
  }

  @override
  String downloadedNoAppToOpen(String name) {
    return 'ダウンロードしましたが、$name を開けるアプリがありません';
  }

  @override
  String get allowInstallApkPrompt => 'APK ファイルを開くには不明なアプリのインストールを許可してください';

  @override
  String noAppToOpenFile(String name) {
    return '$name を開けるアプリがインストールされていません';
  }

  @override
  String cannotOpenFile(String error) {
    return 'ファイルを開けません: $error';
  }

  @override
  String cannotShareFile(String error) {
    return 'ファイルを共有できません: $error';
  }

  @override
  String searchFailed(String error) {
    return '検索に失敗しました: $error';
  }

  @override
  String noSearchResultsFor(String query) {
    return '「$query」に一致する結果はありません';
  }

  @override
  String get searchedThisAndSubfolders => 'このフォルダとサブフォルダを検索しました。';

  @override
  String get first200Results => '最初の 200 件を表示中（さらに表示するには検索を絞り込んでください）';

  @override
  String searchResultsInFolder(int count) {
    return 'このフォルダーとサブフォルダー内の結果：$count';
  }

  @override
  String searchFoundCount(int count) {
    return '$count 件見つかりました';
  }

  @override
  String get currentFolder => '現在のフォルダ';

  @override
  String fileBeyondFirstPage(String parent) {
    return 'ファイルは「$parent」の2ページ目以降にあります。フォルダを開いて確認してください。';
  }

  @override
  String tooManyItemsSelectAll(int count) {
    return '項目が多すぎるため一度にすべて選択できません（$count 件）';
  }

  @override
  String couldNotLoadAllItems(String error) {
    return 'すべての項目を読み込めませんでした: $error';
  }

  @override
  String get alreadyLocalUseCopy => 'すでにローカルにあります。別の場所に配置するには「コピー」を使用してください。';

  @override
  String get fileNameLabel => 'ファイル名';

  @override
  String get fileNameHint => '例: notes.txt';

  @override
  String failedToCreateFile(String error) {
    return 'ファイルの作成に失敗しました: $error';
  }

  @override
  String get alreadyExists => 'すでに存在します';

  @override
  String get skip => 'スキップ';

  @override
  String get keepBoth => '両方残す';

  @override
  String get replace => '置き換える';

  @override
  String get readOnlyCannotDrop => 'この場所は読み取り専用のため、ファイルをドロップできません';

  @override
  String get cannotDropFolderIntoSelf => 'フォルダを自身またはそのサブフォルダにドロップすることはできません';

  @override
  String deleteSingleConfirmTitle(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String deleteMultipleConfirmTitle(int count) {
    return '$count 個の項目を削除しますか？';
  }

  @override
  String get deleteChoiceTrashOrPermanent => 'ゴミ箱に移動するか、完全に削除するかを選択してください。';

  @override
  String get deletePermanentWarning => '完全に削除しますか？この操作は取り消せません。';

  @override
  String get deleteRemotePermanentWarning =>
      'この項目はリモートサーバー上にあるため、ローカルのゴミ箱に移動できません。完全に削除されます。';

  @override
  String get permanentDelete => '完全に削除';

  @override
  String couldNotMoveToTrash(int failed, int total, String details) {
    return '$total 件中 $failed 件をゴミ箱に移動できませんでした:\n$details';
  }

  @override
  String get movedOneToTrash => '1 件をゴミ箱に移動しました';

  @override
  String movedManyToTrash(int count) {
    return '$count 件をゴミ箱に移動しました';
  }

  @override
  String couldNotRestoreItems(int count) {
    return '$count 件を復元できませんでした';
  }

  @override
  String get nameCannotContainSlash => '名前に「/」または「\\」を含めることはできません';

  @override
  String renameFailed(String error) {
    return '名前の変更に失敗しました: $error';
  }

  @override
  String get rootLabel => 'ルート';

  @override
  String get exitSplitView => '分割表示を終了';

  @override
  String get cancelSelectionEsc => '選択を解除 (Esc)';

  @override
  String get backToPreviousPage => '前のページに戻る';

  @override
  String get backToTop => 'トップへ戻る';

  @override
  String get searchFilesSubfoldersHint => 'ファイルとサブフォルダを検索…';

  @override
  String get listView => 'リスト表示';

  @override
  String get gridView => 'グリッド表示';

  @override
  String sortStatusTooltip(String field, String arrow) {
    return '並び替え: $field $arrow';
  }

  @override
  String get internalStorage => '内部ストレージ';

  @override
  String get capabilitiesPrefix => '機能: ';

  @override
  String get failedToLoadDir => 'ディレクトリの読み込みに失敗しました';

  @override
  String noFilesMatching(String query) {
    return '「$query」に一致するファイルはありません';
  }

  @override
  String get onlyHiddenFilesHere => 'ここには隠しファイルのみがあります';

  @override
  String get directoryIsEmpty => 'ディレクトリは空です';

  @override
  String get enterPathToJumpHint => '移動先のパスを入力...';

  @override
  String get goToLine => '指定行へ移動';

  @override
  String lineNumberRange(int total) {
    return '行番号 (1 - $total)';
  }

  @override
  String enterLineNumberBetween(int total) {
    return '1 から $total の間の行番号を入力してください';
  }

  @override
  String replacedOccurrences(int count) {
    return '$count 件を置換しました';
  }

  @override
  String get reloadFile => 'ファイルを再読み込み';

  @override
  String get reloadFileConfirm => '未保存の変更を破棄してディスクから再読み込みしますか？';

  @override
  String get reload => '再読み込み';

  @override
  String get fileSavedSuccess => 'ファイルを保存しました';

  @override
  String saveFailed(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String pdfExportFailed(String error) {
    return 'PDF の書き出しに失敗しました: $error';
  }

  @override
  String get saveChangesQuestion => '変更を保存しますか？';

  @override
  String get saveBeforeBrowserPrompt => '外部ブラウザで開く前に変更を保存しますか？';

  @override
  String get openWithoutSaving => '保存せずに開く';

  @override
  String get saveAndOpen => '保存して開く';

  @override
  String failedOpenInBrowser(String error) {
    return 'ブラウザで開けませんでした: $error';
  }

  @override
  String get unsavedChanges => '未保存の変更';

  @override
  String get saveBeforeClosingPrompt => '未保存の変更があります。閉じる前に保存しますか？';

  @override
  String get findInFileTooltip => 'ファイル内を検索 (Ctrl+F)';

  @override
  String get showSource => 'ソースを表示';

  @override
  String get showPreview => 'プレビューを表示';

  @override
  String get markdownTheme => 'Markdown テーマ';

  @override
  String get exportToPdf => 'PDF に書き出す';

  @override
  String get printPreviewPdf => 'PDF を印刷 / プレビュー';

  @override
  String get shareSavePdf => 'PDF を共有 / 保存';

  @override
  String get marginsSpacing => '余白 / 間隔';

  @override
  String get readOnlyCannotEditTooltip => '読み取り専用の場所 — このファイルはここで編集できません';

  @override
  String get saveChangesTooltip => '変更を保存 (Ctrl+S)';

  @override
  String get saveAs => '名前を付けて保存...';

  @override
  String get saveToThisFolder => 'このフォルダに保存';

  @override
  String get savedToCachePrompt => 'アプリキャッシュに保存されました。「名前を付けて保存」で端末に保存できます';

  @override
  String get savedLabel => '保存済み';

  @override
  String get editLabel => '編集';

  @override
  String get textOptions => 'テキストオプション';

  @override
  String get allTextCopied => 'すべてのテキストをクリップボードにコピーしました';

  @override
  String get reloadFromDiskShortcut => 'ディスクから再読み込み (Ctrl+R)';

  @override
  String get copyAllText => 'すべてのテキストをコピー';

  @override
  String get goToLineShortcut => '指定行へ移動... (Ctrl+G)';

  @override
  String largerFontShortcut(int pt) {
    return '文字を大きく (Ctrl+=) ($pt pt)';
  }

  @override
  String smallerFontShortcut(int pt) {
    return '文字を小さく (Ctrl+-) ($pt pt)';
  }

  @override
  String get resetFontShortcut => 'サイズをリセット (Ctrl+0) (13pt)';

  @override
  String get wordWrap => '折り返し';

  @override
  String get undoShortcut => '元に戻す (Ctrl+Z)';

  @override
  String get redoShortcut => 'やり直す (Ctrl+Y)';

  @override
  String failedToOpenFile(String error) {
    return 'ファイルを開けませんでした: $error';
  }

  @override
  String get readOnlyCannotSave => '読み取り専用の場所 — 変更は保存できません。';

  @override
  String get findInFileHint => 'ファイル内を検索...';

  @override
  String get previousMatch => '前の一致';

  @override
  String get nextMatch => '次の一致';

  @override
  String get toggleReplaceShortcut => '置換を表示/非表示 (Ctrl+H)';

  @override
  String get closeFindShortcut => '検索を閉じる (Esc)';

  @override
  String get replaceWithHint => '置換後の文字列...';

  @override
  String get replaceAll => 'すべて置換';

  @override
  String get documentDetails => 'ドキュメントの詳細';

  @override
  String get copyAll => 'すべてコピー';

  @override
  String get documentCopied => 'ドキュメントをクリップボードにコピーしました';

  @override
  String get linesLabel => '行数';

  @override
  String get wordsLabel => '単語数';

  @override
  String get charactersLabel => '文字数';

  @override
  String get byteSizeLabel => 'バイトサイズ';

  @override
  String get lineEndingsLabel => '改行コード';

  @override
  String get cursorPositionLabel => 'カーソル位置';

  @override
  String cursorLineCol(int line, int col) {
    return '$line 行目, $col 列目';
  }

  @override
  String get readOnlyLocation => '読み取り専用の場所';

  @override
  String get previewModeLabel => 'プレビュー';

  @override
  String get viewingSourceLabel => 'ソース表示';

  @override
  String get editingModeLabel => '編集中';

  @override
  String editorStatusLine(int line, int col, int lines) {
    return '行 $line, 列 $col  •  行数: $lines  •  ';
  }

  @override
  String editorStatusWords(int words) {
    return '単語: $words  •  ';
  }

  @override
  String editorStatusChars(int chars) {
    return '文字: $chars  •  ';
  }

  @override
  String get documentIsEmpty => 'ドキュメントは空です';

  @override
  String get editInSourceMode => 'ソースモードで編集';

  @override
  String couldNotScanPhotos(String error) {
    return '写真をスキャンできませんでした。\n$error';
  }

  @override
  String get photoLibraryDenied =>
      '写真ライブラリへのアクセスが拒否されました。\n「設定 → プライバシー → 写真」で許可してください。';

  @override
  String couldNotLoadMorePhotos(String error) {
    return 'さらに写真を読み込めませんでした: $error';
  }

  @override
  String cannotOpenPhoto(String error) {
    return '写真を開けません: $error';
  }

  @override
  String get photoNoLongerAvailable => '写真は利用できなくなりました';

  @override
  String get openInViewer => 'ビューアーで開く';

  @override
  String get sharePhoto => '写真を共有';

  @override
  String get photosTitle => '写真';

  @override
  String get rescan => '再スキャン';

  @override
  String get scrollToTop => 'トップへスクロール';

  @override
  String get noPhotosFound => '写真が見つかりません';

  @override
  String get openSettings => '設定を開く';

  @override
  String cannotReadImageDetails(String error) {
    return '画像の詳細を読み取れません: $error';
  }

  @override
  String get imageDetailsUnavailable => '画像の詳細は利用できなくなりました';

  @override
  String get imageDetails => '画像の詳細';

  @override
  String get dimensionsLabel => '解像度';

  @override
  String get dateTakenLabel => '撮影日時';

  @override
  String get cameraLabel => 'カメラ';

  @override
  String get locationLabel => '場所';

  @override
  String cannotLoadImage(String error) {
    return '画像を読み込めません: $error';
  }

  @override
  String get imageFileNotFoundLocally => 'ローカルに画像ファイルが見つかりません';

  @override
  String get failedToLoadImage => '画像の読み込みに失敗しました';

  @override
  String get imagePathCopied => '画像のパスをコピーしました';

  @override
  String cannotCopyPath(String error) {
    return 'パスをコピーできません: $error';
  }

  @override
  String cannotShareImage(String error) {
    return '画像を共有できません: $error';
  }

  @override
  String get deleteImageConfirm => 'この画像を削除してもよろしいですか？この操作は取り消せません。';

  @override
  String deletedItem(String name) {
    return '$name を削除しました';
  }

  @override
  String failedToDelete(String error) {
    return '削除に失敗しました: $error';
  }

  @override
  String get shareImage => '画像を共有';

  @override
  String get rotate90 => '90° 回転';

  @override
  String get rotate90Shortcut => '90° 回転 (R)';

  @override
  String get deleteImage => '画像を削除';

  @override
  String get moreOptions => 'その他のオプション';

  @override
  String get moreBelow => '下に続きあり';

  @override
  String get zoomInShortcut => '拡大 (+)';

  @override
  String get zoomOutShortcut => '縮小 (-)';

  @override
  String get resetZoomShortcut => 'ズームをリセット (0)';

  @override
  String get previousImage => '前の画像';

  @override
  String get nextImage => '次の画像';

  @override
  String autoPlayingNext(String name) {
    return '次の曲を自動再生: $name';
  }

  @override
  String get nextEpisodeShortcut => '次へ (N)';

  @override
  String playlistProgress(int current, int total) {
    return 'プレイリスト ($current/$total)';
  }

  @override
  String get autoNextOn => '連続再生: オン';

  @override
  String get autoNextOff => '連続再生: オフ';

  @override
  String get loopSingle => 'ループ: 1曲';

  @override
  String get loopOff => 'ループ: オフ';

  @override
  String get fullscreenShortcut => '全画面 (F)';

  @override
  String get fullscreen => '全画面';

  @override
  String get exitFullscreen => '全画面を終了';

  @override
  String get playbackOptions => '再生オプション';

  @override
  String get unmuteShortcut => 'ミュート解除 (M)';

  @override
  String muteShortcut(int percent) {
    return 'ミュート (M) ($percent%)';
  }

  @override
  String get rewind10s => '10秒戻す';

  @override
  String get forward10s => '10秒送る';

  @override
  String get autoNextMenuOn => '連続再生（オン）';

  @override
  String get autoNextMenuOff => '連続再生（オフ）';

  @override
  String get previousShortcut => '前へ (P)';

  @override
  String get nextShortcut => '次へ (N)';

  @override
  String get cannotPlayFile => 'このファイルを再生できません';

  @override
  String get unknownPlaybackError => '不明な再生エラー';

  @override
  String couldNotLoadBookmarks(String error) {
    return 'ブックマークを読み込めませんでした: $error';
  }

  @override
  String get renameBookmark => 'ブックマークの名前を変更';

  @override
  String get bookmarkNameLabel => 'ブックマーク名';

  @override
  String couldNotRenameBookmark(String error) {
    return 'ブックマーク名を変更できませんでした: $error';
  }

  @override
  String couldNotRemoveBookmark(String error) {
    return 'ブックマークを削除できませんでした: $error';
  }

  @override
  String couldNotRestoreBookmark(String error) {
    return 'ブックマークを復元できませんでした: $error';
  }

  @override
  String get searchBookmarks => 'ブックマークを検索';

  @override
  String get filterBookmarksHint => 'ブックマークを絞り込む...';

  @override
  String get noBookmarksSaved => '保存されたブックマークはありません';

  @override
  String get noMatchingBookmarks => '一致するブックマークはありません';

  @override
  String get bookmarksEmptyHint =>
      'ファイルブラウザでフォルダを長押し（または右クリック）して「このフォルダをブックマーク」を選択してください。';

  @override
  String nothingMatchesQuery(String query) {
    return '「$query」に一致する項目はありません。';
  }

  @override
  String get bookmarkActions => 'ブックマーク操作';

  @override
  String couldNotLoadRecent(String error) {
    return '最近の履歴を読み込めませんでした: $error';
  }

  @override
  String failedToBookmark(String error) {
    return 'ブックマークに失敗しました: $error';
  }

  @override
  String couldNotRemoveItem(String name, String error) {
    return '「$name」を削除できませんでした: $error';
  }

  @override
  String get clearHistory => '履歴を消去';

  @override
  String get clearHistoryConfirm => '最近のアクセス履歴をすべて消去しますか？ブックマークは保持されます。';

  @override
  String couldNotClearHistory(String error) {
    return '履歴を消去できませんでした: $error';
  }

  @override
  String clearedRecentLocations(int count) {
    return '$count 件の履歴を消去しました';
  }

  @override
  String get removeFromHistory => '履歴から削除';

  @override
  String get recentHistory => '最近の履歴';

  @override
  String get searchHistory => '履歴を検索';

  @override
  String get filterRecentHint => '履歴を絞り込む...';

  @override
  String get noRecentHistory => '最近の閲覧履歴はありません';

  @override
  String get noMatchingLocations => '一致する場所はありません';

  @override
  String get recentEmptyHint => '閲覧したディレクトリやファイルがここに表示されます。';

  @override
  String get actionsTooltip => '操作';

  @override
  String couldNotLoadTrash(String error) {
    return 'ゴミ箱を読み込めませんでした: $error';
  }

  @override
  String get recycledItemDetails => 'ゴミ箱の項目の詳細';

  @override
  String get originalPathColon => '元のパス:';

  @override
  String get originalPathCopied => '元のパスをクリップボードにコピーしました';

  @override
  String get restore => '復元';

  @override
  String get restoreItem => '項目を復元';

  @override
  String get viewDetails => '詳細を表示';

  @override
  String get deletePermanently => '完全に削除';

  @override
  String couldNotRestoreNamed(String name, String error) {
    return '「$name」を復元できませんでした: $error';
  }

  @override
  String restoredNamed(String name) {
    return '「$name」を復元しました';
  }

  @override
  String permanentlyDeleteConfirm(String name) {
    return '「$name」を完全に削除しますか？';
  }

  @override
  String couldNotDeleteNamed(String name, String error) {
    return '「$name」を削除できませんでした: $error';
  }

  @override
  String get emptyAll => 'すべて空にする';

  @override
  String permanentlyDeleteAllTrash(int count, String size) {
    return '全 $count 件（$size）を完全に削除しますか？この操作は取り消せません。';
  }

  @override
  String couldNotEmptyTrash(String error) {
    return 'ゴミ箱を空にできませんでした: $error';
  }

  @override
  String get recycleBinEmptied => 'ゴミ箱を空にしました';

  @override
  String get restoreAllItems => 'すべて復元';

  @override
  String restoreAllConfirm(int count) {
    return '全 $count 件を元の場所に復元しますか？';
  }

  @override
  String get restoreAll => 'すべて復元';

  @override
  String restoredCountOfTotal(int done, int total) {
    return '$total 件中 $done 件を復元しました';
  }

  @override
  String restoredPartialTrash(int done, int total, int failed, String sample) {
    return '$total 件中 $done 件を復元しました。残り $failed 件（$sample）';
  }

  @override
  String restoringProgress(int done, int total) {
    return '復元中 $done / $total…';
  }

  @override
  String recycleBinSummary(int count, String size) {
    return 'ゴミ箱 • $count 件, $size';
  }

  @override
  String get searchTrash => 'ゴミ箱を検索';

  @override
  String get filterRecycledHint => 'ゴミ箱のファイルを絞り込む...';

  @override
  String get recycleBinIsEmpty => 'ゴミ箱は空です';

  @override
  String get noMatchingItemsTrash => 'ゴミ箱に一致する項目がありません';

  @override
  String get trashEmptyHint => '削除されたファイルやフォルダはここに表示されます。';

  @override
  String get connectAndBrowse => '接続して閲覧';

  @override
  String get testConnection => '接続テスト';

  @override
  String get copyUri => 'URI をコピー';

  @override
  String get editConfiguration => '設定を編集';

  @override
  String get deleteRemote => 'リモート接続を削除';

  @override
  String addedRemote(String name) {
    return 'リモート接続を追加しました: $name';
  }

  @override
  String deleteRemoteConfirm(String name) {
    return '「$name」を削除しますか？\n\nアプリに保存された接続設定のみが削除され、リモートサーバー上のファイルには影響しません。';
  }

  @override
  String get connectionNoReadableDetails =>
      'この接続には読み取り可能な詳細がありません。編集して再入力してください。';

  @override
  String testingRemote(String name) {
    return '「$name」をテスト中…';
  }

  @override
  String connectedToRemote(String name) {
    return '「$name」に接続しました';
  }

  @override
  String cannotReachRemote(String name) {
    return '「$name」に接続できません';
  }

  @override
  String get noConnectionsToExport => 'エクスポートする接続がありません';

  @override
  String backupConnectionsCount(int count) {
    return '接続のバックアップ ($count)';
  }

  @override
  String get backupConnectionsDesc =>
      '設定済みの接続を JSON としてエクスポートします。コピーまたはファイルへ共有・保存できます。';

  @override
  String get copyToClipboard => 'クリップボードにコピー';

  @override
  String get connectionsCopied => '接続をクリップボードにコピーしました';

  @override
  String get shareSaveToFiles => '共有 / ファイルに保存';

  @override
  String exportFailed(String error) {
    return 'エクスポートに失敗しました: $error';
  }

  @override
  String get restoreConnections => '接続を復元';

  @override
  String get pasteJsonBackupHint => '以下に JSON バックアップテキストを貼り付けてください:';

  @override
  String importedConnections(int count, String detail) {
    return '$count 件の接続をインポートしました$detail';
  }

  @override
  String importFailed(String error) {
    return 'インポートに失敗しました: $error';
  }

  @override
  String get importAction => 'インポート';

  @override
  String get searchRemotes => 'リモート接続を検索';

  @override
  String get addConnection => '接続を追加';

  @override
  String get backupRestore => 'バックアップ / 復元';

  @override
  String get backupExport => 'バックアップ / エクスポート';

  @override
  String get restoreImport => '復元 / インポート';

  @override
  String get filterRemotesHint => 'リモート接続を絞り込む...';

  @override
  String get noRemoteConnections => 'リモート接続が設定されていません';

  @override
  String get noRemoteConnectionsDesc =>
      'Amazon S3、Aliyun OSS、WebDAV、SFTP、FTP、または SMB ネットワークストレージに接続します。';

  @override
  String get addRemoteStorage => 'リモートストレージを追加';

  @override
  String get editRemoteStorage => 'リモートストレージを編集';

  @override
  String get noMatchingConnections => '一致する接続がありません';

  @override
  String get addAnotherRemote => '別のリモートを追加';

  @override
  String get detailsUnavailableReconnect => '詳細を取得できません — 再入力して接続してください';

  @override
  String get remoteActions => 'リモート操作';

  @override
  String couldNotLoadConnections(String error) {
    return '接続を読み込めませんでした: $error';
  }

  @override
  String get portMustBeNumber => 'ポートは数値で入力してください。';

  @override
  String get portRangeError => 'ポートは 1 から 65535 の間で指定してください。';

  @override
  String get connectionSuccessful => '接続に成功しました！';

  @override
  String get connectionReturnedFalse => '接続テストに失敗しました';

  @override
  String connectionFailedWithError(String error) {
    return '接続に失敗しました: $error';
  }

  @override
  String idAlreadyUsed(String id, String name) {
    return 'ID「$id」は「$name」ですでに使用されています';
  }

  @override
  String savedOldEntryRemoveFailed(String oldId, String error) {
    return '保存されましたが、古い項目「$oldId」を削除できませんでした: $error';
  }

  @override
  String couldNotSave(String error) {
    return '保存できませんでした: $error';
  }

  @override
  String get protocolProvider => 'プロトコル / プロバイダー';

  @override
  String get providerS3 => 'Amazon S3 / S3 互換 (MinIO, R2)';

  @override
  String get providerOss => 'Aliyun OSS';

  @override
  String get providerWebdav => 'WebDAV (Nextcloud, OwnCloud)';

  @override
  String get providerSftp => 'SFTP (SSH ファイル転送)';

  @override
  String get providerFtp => 'FTP / FTPS';

  @override
  String get providerSmb => 'SMB / Windows 共有 (Samba)';

  @override
  String get displayName => '表示名';

  @override
  String get pleaseEnterName => '名前を入力してください';

  @override
  String get identifierLabel => '識別子 / ID (例: sftp_mac, my_nas)';

  @override
  String get identifierHint => 'リモートパスで使用: remote://id/...';

  @override
  String get generateIdTooltip => '名前から ID を生成';

  @override
  String get pleaseEnterId => '識別子を入力してください';

  @override
  String get idCharsetError => '識別子には英数字、ハイフン、アンダースコアのみ使用できます';

  @override
  String get bucketNameOptional => 'バケット名（任意、空欄で全バケット表示）';

  @override
  String get bucketNameOptionalHint => '空欄で全バケットを表示、またはカンマ区切りで指定';

  @override
  String get regionLabel => 'リージョン (例: us-east-1, auto)';

  @override
  String get usePathStyle => 'パススタイルを使用（MinIO / ローカル S3 向け）';

  @override
  String get accessKeyId => 'アクセスキー ID';

  @override
  String get secretAccessKey => 'シークレットアクセスキー';

  @override
  String get showSecretKey => 'シークレットキーを表示';

  @override
  String get hideSecretKey => 'シークレットキーを非表示';

  @override
  String get webdavUrlLabel => 'WebDAV URL (例: https://example.com/dav)';

  @override
  String get urlRequired => 'URL は必須です';

  @override
  String get username => 'ユーザー名';

  @override
  String get password => 'パスワード';

  @override
  String get showPassword => 'パスワードを表示';

  @override
  String get hidePassword => 'パスワードを非表示';

  @override
  String get authMethod => '認証方式';

  @override
  String get authPassword => 'パスワード';

  @override
  String get authPrivateKey => '秘密鍵';

  @override
  String get privateKeyLabel => '秘密鍵';

  @override
  String get privateKeyHint => 'ここにOpenSSH / PEM形式の秘密鍵を貼り付けます';

  @override
  String get privateKeyRequired => '秘密鍵を入力してください';

  @override
  String get selectKeyFile => '鍵ファイルを選択';

  @override
  String get passphraseLabel => 'パスフレーズ（任意）';

  @override
  String get passphraseHint => '鍵が暗号化されていない場合は空欄';

  @override
  String get showPassphrase => 'パスフレーズを表示';

  @override
  String get hidePassphrase => 'パスフレーズを非表示';

  @override
  String failedToReadKeyFile(String error) {
    return '鍵ファイルの読み込みに失敗しました: $error';
  }

  @override
  String get hostIp => 'ホスト / IP';

  @override
  String get hostRequired => 'ホストは必須です';

  @override
  String get numbersOnly => '数字のみ';

  @override
  String get portRangeShort => '1–65535';

  @override
  String get remoteRootPath => 'リモートルートパス';

  @override
  String get ftpCleartextWarning =>
      'FTP は暗号化されません。パスワードとファイルは平文で送信されます。信頼できないネットワークでは SFTP または FTPS を使用してください。';

  @override
  String get clearTempCacheQuestion => '一時キャッシュを消去しますか？';

  @override
  String clearTempCacheDesc(String size) {
    return '$size の一時サムネイル、メディア、プレビューキャッシュを削除します。保存済みのファイルや接続設定は安全です。';
  }

  @override
  String get tempCacheCleared => '一時キャッシュを消去しました';

  @override
  String couldNotClearCache(String error) {
    return 'キャッシュを消去できませんでした: $error';
  }

  @override
  String get temporaryCache => '一時キャッシュ';

  @override
  String get appInfoCopied => 'アプリ情報をクリップボードにコピーしました';

  @override
  String get supportedProtocolsCopied => '対応プロトコルをクリップボードにコピーしました';

  @override
  String buildLabel(String time) {
    return 'ビルド: $time';
  }

  @override
  String platformLabel(String platform) {
    return 'プラットフォーム: $platform';
  }

  @override
  String couldNotReadStorageStats(String error) {
    return 'ストレージ統計を読み取れませんでした: $error';
  }

  @override
  String couldNotClearArchiveCache(String error) {
    return 'アーカイブキャッシュを消去できませんでした: $error';
  }

  @override
  String get archiveCacheCleared => 'アーカイブキャッシュを消去しました';

  @override
  String emptyTrashUtilityConfirm(int count) {
    return '全 $count 件を完全に削除しますか？この操作は取り消せません。';
  }

  @override
  String couldNotEmptyTrashError(String error) {
    return 'ゴミ箱を空にできませんでした: $error';
  }

  @override
  String get chooseSharedFolder => '共有フォルダを選択';

  @override
  String portValidationError(String port) {
    return 'ポートは 1 から 65535 の間の数値である必要があります（入力: \"$port\"）';
  }

  @override
  String failedToStartServer(String error) {
    return 'サーバーの起動に失敗しました: $error';
  }

  @override
  String get couldNotStopLanServer => 'LAN サーバーを停止できませんでした';

  @override
  String get documentsDir => 'ドキュメント';

  @override
  String errorFolderNotFound(String raw) {
    return 'このフォルダは存在しません。削除または名前が変更された可能性があります。\n($raw)';
  }

  @override
  String errorPermissionDenied(String raw) {
    return 'アクセス権限がありません。ストレージ権限を許可するか別のフォルダを選択してください。\n($raw)';
  }

  @override
  String errorSignInFailed(String raw) {
    return 'サインインに失敗しました。ユーザー名とパスワードを確認してください。\n($raw)';
  }

  @override
  String errorServerTimeout(String raw) {
    return 'サーバーの応答がタイムアウトしました。アドレスとネットワークを確認してください。\n($raw)';
  }

  @override
  String errorCannotReachServer(String raw) {
    return 'サーバーに到達できません。アドレス、ポート、ネットワークを確認してください。\n($raw)';
  }

  @override
  String get playLabel => '再生';

  @override
  String get pauseLabel => '一時停止';

  @override
  String get webdavCleartextWarning =>
      'このURLは http:// を使用しているため、パスワードとファイルが暗号化されずに送信されます。サーバーが対応している場合は https:// を使用してください。';

  @override
  String get selectThisFolder => 'このフォルダを選択';

  @override
  String get selectFolderAction => '選択';

  @override
  String get lanSharingDesc =>
      'Wi-Fi 経由でローカルフォルダを共有し、同じネットワーク内の任意のブラウザから閲覧・ダウンロードできます。';

  @override
  String get receivedShareTitle => '共有ファイルを受信';

  @override
  String get receivedShareSingle => '1件のファイルを受信';

  @override
  String receivedShareCount(int count) {
    return '$count件のファイルを受信';
  }

  @override
  String get saveToLocal => 'ローカルに保存';

  @override
  String get saveToLocalSubtitle => 'ローカルフォルダを選択して保存';

  @override
  String get saveToRemote => 'リモートに保存';

  @override
  String get saveToRemoteSubtitle => 'クラウドストレージ、WebDAV、SFTPにアップロード';

  @override
  String get openDirectly => '直接開く';

  @override
  String get openDirectlySubtitle => 'アプリ内で直接表示または再生';

  @override
  String get selectRemoteStorage => 'リモートストレージを選択';

  @override
  String get noRemotesConfigured => 'リモートストレージがありません';

  @override
  String get noRemotesPrompt => 'リモートストレージが設定されていません。新しく追加しますか？';

  @override
  String get savingSharedFiles => '共有ファイルを保存中...';

  @override
  String get savedSharedFilesSuccess => '共有ファイルを保存しました';

  @override
  String get view => '表示';

  @override
  String get invalidFileNameError => '名前に \"/\"、\"\\\"、\".\"、\"..\" は使用できません';

  @override
  String get batchRename => '一括名前変更';

  @override
  String batchRenameTitle(int count) {
    return '一括名前変更 ($count 件)';
  }

  @override
  String get batchRenameSubtitle => '接頭辞・接尾辞、検索置換、連番を指定';

  @override
  String get batchRenameModePrefixSuffix => '接頭・接尾辞';

  @override
  String get batchRenameModeFindReplace => '検索と置換';

  @override
  String get batchRenameModeNumbering => '連番';

  @override
  String get batchRenamePrefix => '接頭辞';

  @override
  String get batchRenamePrefixHint => '例: [2026] ';

  @override
  String get batchRenameSuffix => '接尾辞';

  @override
  String get batchRenameSuffixHint => '例: _final';

  @override
  String get batchRenameFindText => '検索文字列';

  @override
  String get batchRenameReplaceWith => '置換後';

  @override
  String get batchRenameBaseName => 'ベース名';

  @override
  String get batchRenameStartNumber => '開始番号';

  @override
  String get batchRenamePaddingDigits => '桁数';

  @override
  String batchRenameDigitsOption(int digits, String example) {
    return '$digits 桁 ($example)';
  }

  @override
  String get batchRenameKeepExtension => '拡張子を保持';

  @override
  String get batchRenamePreview => 'リアルタイムプレビュー';

  @override
  String get batchRenameEmptyName => '(空の名前)';

  @override
  String batchRenameProgress(int done, int total) {
    return '名前を変更中 $done / $total...';
  }

  @override
  String batchRenameApply(int count) {
    return '名前変更を適用 ($count)';
  }

  @override
  String get batchRenameComplete => '一括名前変更が完了しました';

  @override
  String get batchRenameNoChanges => '変更されるファイル名はありません';

  @override
  String get batchRenameErrorEmpty => '空のファイル名が含まれています';

  @override
  String batchRenameErrorDuplicate(String name) {
    return '重複するファイル名があります: \"$name\"';
  }

  @override
  String batchRenameErrorExists(String name) {
    return '同名の項目が既に存在します: \"$name\"';
  }

  @override
  String selectedItemsDetailsTitle(int count) {
    return '選択中の $count 件の詳細';
  }

  @override
  String get selectedFilesSizeLabel => '選択ファイルサイズ';

  @override
  String get currentDirectoryLabel => '現在のディレクトリ';

  @override
  String get bookmarkSortModeTooltip => '並び替え';

  @override
  String get bookmarkSortCustom => 'カスタム（ドラッグで並び替え）';

  @override
  String get bookmarkSortNameAsc => '名前昇順 (A-Z)';

  @override
  String get bookmarkSortNameDesc => '名前降順 (Z-A)';

  @override
  String get videoFitLabel => '画面比率';

  @override
  String get videoFitContain => '画面に合わせる';

  @override
  String get videoFitCover => '切り抜き';

  @override
  String get videoFitFill => '引き伸ばし';

  @override
  String videoFitChanged(String mode) {
    return '画面比率: $mode';
  }

  @override
  String audioTracksTitle(int count) {
    return '音声トラック ($count)';
  }

  @override
  String get audioTrackMenu => '音声トラック';

  @override
  String get noAudioTracks => '選択可能な音声トラックがありません';

  @override
  String get audioTrackDefault => '自動（デフォルト）';

  @override
  String audioTrackItem(String id) {
    return '音声トラック $id';
  }

  @override
  String subtitleTracksTitle(int count) {
    return '字幕 ($count)';
  }

  @override
  String get subtitleTrackMenu => '字幕';

  @override
  String get subtitlesOff => '字幕オフ';

  @override
  String subtitleTrackItem(String id) {
    return '字幕 $id';
  }

  @override
  String get sleepTimerTitle => 'スリープタイマー';

  @override
  String get sleepTimerOff => 'オフ';

  @override
  String get sleepTimerOffToast => 'スリープタイマーをオフにしました';

  @override
  String sleepTimerMinutes(int minutes) {
    return '$minutes 分後に停止';
  }

  @override
  String sleepTimerMinutesToast(int minutes) {
    return '$minutes 分後に再生を停止します';
  }

  @override
  String get sleepTimerEndOfTrack => '現在のトラック終了後に停止';

  @override
  String get sleepTimerEndOfTrackToast => '現在のトラック終了後に停止します';

  @override
  String get sleepTimerEndOfTrackShort => 'トラック終了時';

  @override
  String sleepTimerMenuRemaining(String remaining) {
    return 'スリープタイマー ($remaining)';
  }

  @override
  String get readOnlyViewMode => '読み取り専用表示';

  @override
  String get privacyFolder => 'プライバシーフォルダ';

  @override
  String get privacyFolders => 'プライバシーフォルダ';

  @override
  String get privacyFoldersDesc => '独立したプライバシーフォルダの作成・解除・バックアップ・インポート';

  @override
  String get createPrivacyFolder => 'プライバシーフォルダを作成';

  @override
  String get openPrivacyFolder => 'プライバシーフォルダを開く';

  @override
  String get backupPrivacyFolder => 'プライバシーフォルダをバックアップ';

  @override
  String get importPrivacyFolder => 'プライバシーフォルダをインポート';

  @override
  String get privacyFolderName => 'フォルダ名';

  @override
  String get privacyFolderNameHint => '正確なフォルダ名を入力';

  @override
  String get privacyFolderNotFound => 'プライバシーフォルダが存在しません';

  @override
  String get privacyFolderAlreadyExists => '同じ名前のプライバシーフォルダが既に存在します';

  @override
  String get credentialMethod => '認証方式';

  @override
  String get credentialPassword => '個別パスワード（8〜128文字・記号可）';

  @override
  String get credentialSystem => 'システム認証（パスコード / 生体認証）';

  @override
  String get credentialSystemUnavailable => 'この端末ではシステム認証を利用できません';

  @override
  String get encryptionAlgorithm => '暗号化方式';

  @override
  String get cipherNone => '暗号化なし';

  @override
  String get cipherAes128Gcm => 'AES-128-GCM（デフォルト・HWアクセラレーション）';

  @override
  String get cipherAes256Gcm => 'AES-256-GCM（HWアクセラレーション）';

  @override
  String get storageLocation => '保存先';

  @override
  String get useDefaultLocation => 'デフォルト';

  @override
  String get changeLocation => '変更';

  @override
  String get privacyPasswordLabel => 'パスワード（8〜128文字・記号可）';

  @override
  String get privacyConfirmPasswordLabel => 'パスワード（確認）';

  @override
  String get passwordLengthError => 'パスワードは8〜128文字で入力してください';

  @override
  String get passwordMismatchError => 'パスワードが一致しません';

  @override
  String get privacyUnlockedLabel => '解除済み • 終了またはバックグラウンド10分で自動非表示';

  @override
  String get lockAndHide => 'ロックして非表示';

  @override
  String lockAllPrivacyFolders(int count) {
    return 'すべてロックして非表示 ($count)';
  }

  @override
  String vaultLockedNotice(String name) {
    return 'プライバシーフォルダ「$name」をロックして非表示にしました';
  }

  @override
  String get nextStep => '次へ';

  @override
  String get unlockAction => 'ロック解除';

  @override
  String unlockWithSystemPrompt(String name) {
    return '「$name」のロックを解除するため認証してください';
  }

  @override
  String get setupSystemAuthPrompt => 'システム認証を設定するため認証してください';

  @override
  String get wrongCredentialError => 'パスワードまたは認証情報が正しくありません';

  @override
  String cooldownRetryError(int seconds) {
    return '失敗回数が多すぎます。$seconds 秒後に再試行してください';
  }

  @override
  String get selectBackupSourceVault => '解除済みフォルダを選択または名前を入力';

  @override
  String get backupPasswordRequiredNotice =>
      'システム認証フォルダのため、他端末へのインポート用に8〜128文字のバックアップパスワードを設定してください。';

  @override
  String get backupPasswordLabel => 'バックアップパスワード（8〜128文字）';

  @override
  String get selectBackupDestFile => 'バックアップ保存先フォルダを選択';

  @override
  String backupExportSuccess(String path) {
    return 'バックアップをエクスポートしました: $path';
  }

  @override
  String get selectBackupArchive => '.fpmvault バックアップファイルを選択';

  @override
  String backupArchiveSummary(String cipher, int count) {
    return '暗号方式: $cipher • オブジェクト: $count';
  }

  @override
  String get backupPasswordToVerify => 'バックアップ / フォルダパスワード';

  @override
  String get localUnlockAfterImport => 'インポート後の認証方式';

  @override
  String get newLocalPasswordOptional => '新しいローカルパスワード（空欄で元のパスワードを継続）';

  @override
  String importSuccessNotice(String name) {
    return 'プライバシーフォルダ「$name」をインポートし解除しました';
  }

  @override
  String get saveToPrivacyFolder => 'プライバシーフォルダに保存';

  @override
  String get saveToPrivacyFolderSubtitle => '暗号化して解除済みのプライバシーフォルダに保存';

  @override
  String get selectPrivacyFolder => 'プライバシーフォルダを選択';

  @override
  String get privacyFolderNoHistoryBookmark => 'プライバシーフォルダ内では履歴とブックマークは無効です';

  @override
  String get unlockedBadge => '解除中';

  @override
  String importKeepOriginalName(String name) {
    return '元のフォルダ名を維持します：「$name」';
  }

  @override
  String get importWillKeepOriginalName =>
      '元のフォルダ名がそのまま維持されます。すでに同名のフォルダがある場合は、新しい名前の入力を求められます。';

  @override
  String importNameExistsEnterNew(String name) {
    return 'プライバシーフォルダ「$name」はすでに存在します。新しいフォルダ名を手動で入力してください。';
  }

  @override
  String get importNewFolderNameLabel => '新しいプライバシーフォルダ名';

  @override
  String get importEnterFolderNamePrompt =>
      'このバックアップに元のフォルダ名が含まれていません。フォルダ名を入力してください。';

  @override
  String get renamePrivacyFolder => 'プライバシーフォルダの名前を変更';

  @override
  String privacyFolderRenamedNotice(String name) {
    return 'プライバシーフォルダ名を「$name」に変更しました';
  }

  @override
  String largeFilePagedNotice(String start, String end, String total) {
    return '大容量ファイル読み取り専用（$start – $end / $total）';
  }

  @override
  String get previousPage => '前のページ';

  @override
  String get nextPage => '次のページ';

  @override
  String get jumpToPosition => '位置へ移動';

  @override
  String get deletePrivacyFolder => 'プライバシーフォルダを削除';

  @override
  String deletePrivacyFolderWarning(String name) {
    return 'プライバシーフォルダ「$name」と内部のすべての暗号化ファイル、およびこの端末に保存された鍵を完全に削除します。この操作は元に戻せません。';
  }

  @override
  String deletePrivacyFolderConfirmLabel(String name) {
    return '削除を確認するため「$name」と入力してください';
  }

  @override
  String privacyFolderDeletedNotice(String name) {
    return 'プライバシーフォルダ「$name」を完全に削除しました';
  }

  @override
  String get privacyMediaAudio => 'プライベート音声';

  @override
  String get privacyMediaVideo => 'プライベート動画';

  @override
  String get vaultAutoLockTitle => 'バックグラウンド自動ロック';

  @override
  String get vaultAutoLockImmediate => 'すぐにロック';

  @override
  String vaultAutoLockMinutes(int minutes) {
    return '$minutes 分';
  }

  @override
  String get vaultAutoLockNever => '自動ロックしない';

  @override
  String get vaultConfirmExternalOpenTitle => '外部共有・開く前に確認';

  @override
  String get vaultConfirmExternalOpenDesc => '一時的に復号して外部アプリへ渡す前に確認ダイアログを表示します';

  @override
  String get vaultExternalOpenWarningTitle => '外部アプリで開きますか？';

  @override
  String get vaultExternalOpenWarningBody =>
      'このファイルは一時的に復号され、プライバシーフォルダ外のアプリへ渡されます。必要に応じて外部アプリ側のコピーも削除してください。';

  @override
  String get dontAskAgain => '次回から表示しない';

  @override
  String get continueAction => '続行';

  @override
  String get vaultVideoThumbnailsTitle => 'プライバシーフォルダの動画サムネイル';

  @override
  String get vaultVideoThumbnailsDesc =>
      '動画プレビューをオンデマンドで生成し暗号化キャッシュに保存します（省電力のため既定はオフ）';

  @override
  String get vaultSecuritySettings => 'パスワードとロック解除方法';

  @override
  String get vaultChangePasswordOption => 'パスワードを変更';

  @override
  String get vaultSwitchToSystemOption => 'システム認証へ切り替え';

  @override
  String get vaultSwitchToPasswordOption => '個別パスワードへ切り替え';

  @override
  String get vaultCurrentPasswordLabel => '現在のパスワード';

  @override
  String get vaultNewPasswordLabel => '新しいパスワード（8〜128文字）';

  @override
  String get vaultOldBackupsPasswordNotice =>
      '以前に書き出した .fpmvault バックアップの復元には、作成時の古いパスワードが必要です。';

  @override
  String get vaultSwitchToSystemBackupNotice =>
      'システム認証へ切り替えた後は .fpmvault バックアップを大切に保管してください。端末移行時にキーチェーンの鍵は引き継がれません。';

  @override
  String get vaultSecurityUpdatedNotice => 'プライバシーフォルダのセキュリティ設定を更新しました';

  @override
  String get vaultFolderInfo => 'フォルダ情報とストレージ';

  @override
  String get vaultStatsFiles => 'ファイル数';

  @override
  String get vaultStatsFolders => 'サブフォルダ';

  @override
  String get vaultStatsPlainSize => 'データ合計';

  @override
  String get vaultStatsDiskUsage => 'ディスク使用量';

  @override
  String get vaultStatsOrphaned => '回収可能な孤立データ';

  @override
  String vaultStatsOrphanDetail(int count, String size) {
    return '$count 件（$size）';
  }

  @override
  String get vaultCleanupOrphansAction => '孤立データを整理';

  @override
  String vaultCleanupResultNotice(int count, String size) {
    return '$count 件の孤立ファイルを削除し、$size を解放しました';
  }

  @override
  String backupProgressLabel(String done, String total, int percent) {
    return '$done / $total ($percent%)';
  }

  @override
  String get backupCancelling => 'キャンセル中…';

  @override
  String get backupCancelledNotice => 'バックアップ操作をキャンセルしました';

  @override
  String get deleteVaultPermanentWarning =>
      '選択した項目をプライバシーフォルダから完全に削除します（ゴミ箱からは復元できません）。';

  @override
  String get showQrCode => 'QRコードを表示';

  @override
  String get scanQrToConnect => 'スマートフォンで読み取ってブラウザで開く';

  @override
  String get newTab => '新しいタブ';

  @override
  String get closeTab => 'タブを閉じる';

  @override
  String get openInNewTab => '新しいタブで開く';

  @override
  String get copyToOtherPane => '反対のペインへコピー';

  @override
  String get moveToOtherPane => '反対のペインへ移動';

  @override
  String get pdfViewerTitle => 'PDF ビューアー';

  @override
  String pdfPageOf(int current, int total) {
    return '$current / $total ページ';
  }

  @override
  String get pdfSearchHint => 'PDF 内を検索…';

  @override
  String get pdfJumpToPage => 'ページへ移動';

  @override
  String get pdfOutline => '目次';

  @override
  String get pdfNoOutline => 'この文書には目次がありません';

  @override
  String get pdfZeroDiskBadge => 'メモリ描画・ディスク書出なし';

  @override
  String get scanLanDevices => 'LAN デバイスをスキャン';

  @override
  String get scanningLan => 'ローカルネットワークをスキャン中…';

  @override
  String get noLanDevicesFound =>
      'LAN 内に SMB / SFTP / WebDAV / FTP が見つかりませんでした';

  @override
  String get storageAnalyzer => 'ストレージ分析';

  @override
  String get storageAnalyzerSubtitle => 'フォルダ容量ランキング、種別内訳、大容量ファイル';

  @override
  String get topFolders => '大容量フォルダ';

  @override
  String get topFiles => '大容量ファイル';

  @override
  String get fileTypesBreakdown => 'ファイル種別';

  @override
  String storageUsedOf(String used, String total, String free) {
    return '$total 中 $used 使用（空き $free）';
  }

  @override
  String get duplicateFinder => '重複ファイル検索';

  @override
  String get duplicateFinderSubtitle => '3段階 SHA-256 スキャンと一括整理';

  @override
  String get keepNewest => '最新を残す';

  @override
  String get keepOldest => '最古を残す';

  @override
  String get keepShortestPath => '最短パスを残す';

  @override
  String cleanSelectedDuplicates(int count) {
    return '選択項目を削除 ($count)';
  }

  @override
  String wastedSpace(String size) {
    return '解放可能：$size';
  }

  @override
  String get noDuplicatesFound => '重複ファイルは見つかりませんでした';

  @override
  String get categoryDocuments => 'ドキュメント';

  @override
  String get categoryVideos => '動画';

  @override
  String get categoryAudio => '音楽';

  @override
  String get categoryArchives => 'アーカイブ';

  @override
  String get categoryDownloads => 'ダウンロード';

  @override
  String get categoryApks => 'インストーラー';

  @override
  String get globalSearchHint => 'ファイル・ブックマーク・履歴を検索…';

  @override
  String get advancedSearch => '詳細検索';

  @override
  String get grepContentSearch => '全文検索 (Grep)';

  @override
  String get matchContains => '部分一致';

  @override
  String get matchWildcard => 'ワイルドカード (* ?)';

  @override
  String get matchRegex => '正規表現';

  @override
  String get minSizeMb => '最小サイズ (MB)';

  @override
  String get maxSizeMb => '最大サイズ (MB)';

  @override
  String get modifiedDaysAgo => '更新日数以内';

  @override
  String get pauseTask => '一時停止';

  @override
  String get resumeTask => '再開';

  @override
  String retryFailedItems(int count) {
    return '失敗項目を再試行 ($count)';
  }

  @override
  String get taskPaused => '一時停止中';

  @override
  String get rateLimitLabel => '速度制限';

  @override
  String get rateLimitUnlimited => '無制限';

  @override
  String get encryptWithPassword => 'パスワードで暗号化 (AES-256)';

  @override
  String get archivePasswordRequired => 'アーカイブのパスワードが必要です';

  @override
  String get archivePasswordHint => 'パスワードを入力';

  @override
  String get archiveWrongPassword => 'パスワードが正しくありません';

  @override
  String get subtitles => '字幕';

  @override
  String get subtitleOff => 'オフ';

  @override
  String get loadExternalSubtitle => 'ファイルから字幕を読み込む…';

  @override
  String subtitleAutoLoaded(String name) {
    return '字幕を読み込みました：$name';
  }

  @override
  String get pictureInPicture => 'ピクチャ・イン・ピクチャ';

  @override
  String get directorySync => 'フォルダ同期・バックアップ';

  @override
  String get directorySyncSubtitle => 'ローカルとリモートの増分・ミラー・双方向同期';

  @override
  String get syncModeIncremental => '増分同期（新規・更新のみコピー）';

  @override
  String get syncModeMirror => 'ミラー同期（余分なファイルを削除）';

  @override
  String get syncModeBidirectional => '双方向同期';

  @override
  String get syncPreviewChanges => '差分をプレビュー';

  @override
  String get syncStart => '同期を開始';

  @override
  String get syncNoChanges => 'フォルダはすでに同期されています';

  @override
  String get offlinePinned => 'オフライン固定ファイル';

  @override
  String get offlinePinnedSubtitle => 'リモートファイルのオフラインキャッシュ管理';

  @override
  String get pinOffline => 'オフラインに固定';

  @override
  String get unpinOffline => 'オフライン固定を解除';

  @override
  String pinnedOfflineNotice(String name) {
    return '「$name」をオフラインに固定しました';
  }

  @override
  String get checksumsTitle => 'チェックサム (MD5 / SHA-1 / SHA-256)';

  @override
  String get computeChecksums => 'チェックサムを計算';

  @override
  String get expectedHashHint => '期待されるハッシュ値を貼り付けて検証…';

  @override
  String get hashMatches => 'チェックサムが一致しました';

  @override
  String get hashMismatch => 'チェックサムが一致しません';

  @override
  String get structuredView => '構造化ビュー';

  @override
  String get rawTextView => 'テキスト表示';

  @override
  String get copyJsonPath => 'パスをコピー';

  @override
  String get compareDiff => '差分を比較';

  @override
  String get diffUnified => '統合表示';

  @override
  String get diffSideBySide => '並列表示';

  @override
  String get diffOnlyInLeft => '左側のみ';

  @override
  String get diffOnlyInRight => '右側のみ';

  @override
  String get diffModified => '変更あり';

  @override
  String get diffIdentical => '一致';

  @override
  String get unixPermissions => 'Unix パーミッション (chmod)';

  @override
  String get permOwner => '所有者';

  @override
  String get permGroup => 'グループ';

  @override
  String get permOther => 'その他';

  @override
  String get applyPermissions => '権限を適用';

  @override
  String permissionsUpdated(String mode) {
    return '権限を $mode に更新しました';
  }

  @override
  String get lockVaultNow => '今すぐロック';

  @override
  String get deleteOriginalAfterImport => 'インポート後に元のファイルを削除';

  @override
  String get vaultExternalOpenNotice =>
      '外部アプリで開くと一時的な平文コピーが作成されます。プライバシーフォルダをロックすると自動的に削除されます。';

  @override
  String get shareViaLan => 'LAN で共有';

  @override
  String get calculateDirSize => '計算する';

  @override
  String activeTasksBanner(int count) {
    return '$count 件の転送が進行中';
  }

  @override
  String get jsonFormattedPreview => '整形プレビュー';

  @override
  String get jsonTreeView => 'ツリー表示';

  @override
  String jsonIndentSpaces(int count) {
    return '$count スペース';
  }

  @override
  String get jsonSortKeys => 'キーを並べ替え';

  @override
  String get jsonCopyFormatted => '整形 JSON をコピー';

  @override
  String get jsonCopyMinified => '圧縮 JSON をコピー';

  @override
  String get jsonCopiedFormatted => '整形済み JSON をコピーしました';

  @override
  String get jsonCopiedMinified => '圧縮済み JSON をコピーしました';

  @override
  String get jsonInvalidFormat => '無効な JSON 形式';

  @override
  String get jsonExpandAll => 'すべて展開';

  @override
  String get jsonCollapseAll => 'すべて折りたたむ';

  @override
  String get jsonFormatInEditor => 'JSON を整形';

  @override
  String jsonLinesCount(int count) {
    return '$count 行';
  }

  @override
  String jsonMatchesCount(int current, int total) {
    return '$current/$total 件一致';
  }

  @override
  String get vaultAlwaysVisibleTitle => '常に表示';

  @override
  String get vaultAlwaysVisibleDesc =>
      'ロック後もホームやサイドバーに表示を残します。開く際は従来どおり認証が必要で、自動ロックも有効です。';

  @override
  String get lockedBadge => 'ロック中';

  @override
  String get vaultUnlockToOpen => 'ロック解除して開く';

  @override
  String get vaultUnpinAlwaysVisible => '常時表示を解除';

  @override
  String vaultPinnedNotice(String name) {
    return 'プライバシーフォルダ「$name」を常時表示にしました';
  }

  @override
  String vaultUnpinnedNotice(String name) {
    return 'プライバシーフォルダ「$name」の常時表示を解除しました';
  }

  @override
  String vaultLockedKeepVisibleNotice(String name) {
    return 'プライバシーフォルダ「$name」をロックしました';
  }

  @override
  String get searchCategoryAll => 'すべて';

  @override
  String get searchCategoryCode => 'コード';

  @override
  String get searchCategoryFolders => 'フォルダ';

  @override
  String get searchFilesAndFolders => 'ファイルとフォルダ';

  @override
  String get searchEnterQueryHint => 'キーワードを入力してファイル・フォルダ・ブックマーク・履歴を検索';

  @override
  String get searchingFilesProgress => 'ファイルを検索中…';

  @override
  String get collapseSidebar => 'サイドバーを折りたたむ';

  @override
  String get expandSidebar => 'サイドバーを展開';

  @override
  String get categoryAllFilter => 'すべて';

  @override
  String categorySummary(int count, String size) {
    return '$count 件 · $size';
  }

  @override
  String categoryScanning(String category) {
    return '$categoryをスキャン中…';
  }

  @override
  String categoryEmptyTitle(String category) {
    return '$categoryが見つかりません';
  }

  @override
  String get categoryEmptySubtitle => 'このカテゴリのファイルがここに自動的に表示されます。';

  @override
  String get locateInFolder => 'フォルダで表示';

  @override
  String get clearFilters => 'フィルターをクリア';

  @override
  String filterCategoryHint(String category) {
    return '$category内を絞り込み…';
  }

  @override
  String get historyRetentionTitle => '履歴の保持日数';

  @override
  String get historyRetentionDesc => '指定日数を超えた履歴は自動削除されます。0 を設定すると履歴を保存しません。';

  @override
  String historyRetentionDaysLabel(int days) {
    return '$days 日間保持';
  }

  @override
  String historyRetentionDaysShort(int days) {
    return '$days 日';
  }

  @override
  String get historyRetentionDisabled => '保持しない（0 日）';

  @override
  String get historyRetentionDisabledShort => '保存しない';

  @override
  String get historyRetentionInputLabel => '保持日数（0 = 保持しない）';

  @override
  String get historyRetentionInvalidInput => '0 以上の整数を入力してください';

  @override
  String historyRetentionUpdatedDays(int days) {
    return '履歴の保持日数を $days 日に設定しました';
  }

  @override
  String get historyRetentionUpdatedOff => '履歴の保存を無効にし、既存の履歴を消去しました';

  @override
  String get historyDisabledTitle => '履歴の保存が無効です';

  @override
  String get historyDisabledSubtitle => '保持日数が 0 日に設定されているため、アクセス履歴は保存されません。';

  @override
  String get historyRetentionChange => '保持日数を変更';

  @override
  String errorSftpHostKey(String raw) {
    return 'SSH ホスト鍵の検証に失敗しました。サーバーの身元を確認するか、SFTP 接続を再保存してください。\n($raw)';
  }

  @override
  String errorObjectStorageConfig(String raw) {
    return 'オブジェクトストレージの設定エラーです。バケット名・エンドポイント・リージョン・アクセスキーを確認してください。\n($raw)';
  }

  @override
  String errorSmbConnection(String raw) {
    return 'SMB 共有への接続に失敗しました。共有名・認証情報・SMB ポート (445) を確認してください。\n($raw)';
  }

  @override
  String errorArchivePassword(String raw) {
    return 'アーカイブのパスワードが不足しているか誤っています。再入力してやり直してください。\n($raw)';
  }

  @override
  String errorDiskFull(String raw) {
    return '保存先ボリュームの空き容量が不足しています。\n($raw)';
  }

  @override
  String get recoveryGrantPermission => '権限を許可';

  @override
  String get recoveryEditConnection => '接続設定を編集';

  @override
  String get recoveryEnterPassword => 'パスワードを入力';

  @override
  String get recoveryFreeUpSpace => '空き容量を確保';

  @override
  String get navDomainStorage => 'ストレージ';

  @override
  String get navDomainDiscover => '検索・ライブラリ';

  @override
  String get navDomainTools => 'ツール・タスク';

  @override
  String get autoSyncIntervalLabel => '自動同期スケジュール';

  @override
  String get autoSyncOff => '手動のみ';

  @override
  String autoSyncEveryMinutes(int minutes) {
    return '$minutes 分ごと';
  }

  @override
  String get offlineAutoSyncTitle => '復帰時に自動確認・同期';

  @override
  String get providerCrypt => 'ゼロ知識暗号化クラウド Vault (Crypt)';

  @override
  String get cryptBackingRootLabel => 'ベース保存先ルート';

  @override
  String get cryptBackingRootHint => 'remote://my_s3 またはローカルパス';

  @override
  String get cryptBasePrefixLabel => '暗号化サブフォルダ接頭辞';

  @override
  String get cryptPasswordLabel => 'マスター暗号化パスワード';

  @override
  String get cryptPasswordRequired => '暗号化パスワードを入力してください';

  @override
  String get cryptSaltOptionalLabel => '任意ソルト / パスフレーズ';

  @override
  String get cryptSaltHint => '鍵導出用の任意のソルト';

  @override
  String get cryptInfoBanner =>
      'ファイル名と 64 KiB チャンクはアップロード前にローカルで AES-256-GCM エンドツーエンド暗号化されます。';

  @override
  String get lanWebdavShareTitle => 'LAN WebDAV サーバー';

  @override
  String get lanWebdavShareSubtitle => 'Finder・エクスプローラー・Infuse/Kodi から直接マウント';

  @override
  String get shareViaLanWebdav => 'LAN WebDAV で共有';

  @override
  String get webdavUsernameOptional => 'ユーザー名（任意）';

  @override
  String get webdavUrlCopied => 'WebDAV URL をクリップボードにコピーしました';

  @override
  String webdavServerRunning(String url) {
    return 'WebDAV サーバー稼働中: $url';
  }

  @override
  String get lanPeerTransferTitle => 'LAN ダイレクト転送';

  @override
  String get lanPeerTransferSubtitle =>
      '近くの FP File Manager 端末を検出してファイルやテキストを直接送信';

  @override
  String get peerReceiveMode => '受信モード（検出可能）';

  @override
  String get peerDeviceName => 'デバイス名';

  @override
  String get peerScanDevices => 'LAN デバイスをスキャン';

  @override
  String get peerScanning => '近くのデバイスを検索中…';

  @override
  String get peerNoDevicesFound => 'LAN 内に受信可能なデバイスが見つかりません';

  @override
  String get peerSendFiles => 'ファイルを送信';

  @override
  String get peerSendClipboard => 'クリップボードテキストを送信';

  @override
  String get peerManualAddressHint => 'http://<LAN IP>:ポート';

  @override
  String peerIncomingOfferTitle(String sender) {
    return '$sender からの受信リクエスト';
  }

  @override
  String get peerAccept => '承認';

  @override
  String get peerReject => '拒否';

  @override
  String peerSentSuccess(int count) {
    return '$count 件のファイルを送信しました';
  }

  @override
  String get peerOfferSent => 'テキストを送信しました';

  @override
  String get sendToLanDevice => 'LAN デバイスへ送信';

  @override
  String fastIndexReady(int count) {
    return '高速インデックス: $count 件';
  }

  @override
  String get fastIndexNotBuilt => 'このフォルダの高速インデックスは未作成です';

  @override
  String get fastIndexBuild => 'インデックス作成';

  @override
  String get fastIndexRebuild => 'インデックス再構築';

  @override
  String get fastIndexBuilding => 'インデックス作成中…';

  @override
  String get fastIndexClear => 'インデックス削除';

  @override
  String get fastIndexCleared => '高速インデックスを削除しました';

  @override
  String get readingModeSingle => '単ページ';

  @override
  String get readingModeWebtoon => '縦スクロール (Webtoon)';

  @override
  String get readingModeDouble => '見開き 2 ページ';

  @override
  String get stripExifAction => 'EXIF 削除してコピー保存';

  @override
  String stripExifDone(String path) {
    return 'メタデータ削除済みコピーを保存しました: $path';
  }

  @override
  String get stripExifBatchAction => 'EXIF 削除';

  @override
  String stripExifBatchDone(int count) {
    return '$count 枚の画像の EXIF 削除コピーを保存しました';
  }

  @override
  String get openInTerminal => 'ターミナルで開く';

  @override
  String get openInEditor => 'エディタで開く';

  @override
  String get copyFullPath => '絶対パスをコピー';

  @override
  String get copyVfsPath => 'VFS パスをコピー';

  @override
  String get photoBackupTitle => '写真自動増分バックアップ';

  @override
  String get photoBackupSubtitle =>
      '新しい写真や動画を NAS・S3・WebDAV・Privacy Vault へ増分バックアップ';

  @override
  String get photoBackupEnable => '自動増分バックアップを有効にする';

  @override
  String get photoBackupWifiOnly => 'Wi-Fi 接続時のみバックアップ';

  @override
  String get photoBackupTargetLabel => 'バックアップ保存先';

  @override
  String get photoBackupSelectTarget => '保存先を選択';

  @override
  String get photoBackupNow => '今すぐバックアップ';

  @override
  String get photoBackupRunning => '新しい写真をバックアップ中…';

  @override
  String photoBackupStats(int count) {
    return '$count 件をバックアップ済み';
  }

  @override
  String get photoBackupNoTarget => '先にバックアップ先を選択してください';

  @override
  String photoBackupCompleted(int count) {
    return '$count 件の新規メディアをバックアップしました';
  }

  @override
  String get pinToHomeScreen => 'ホーム画面に固定';

  @override
  String pinToHomeScreenSuccess(String name) {
    return 'ショートカット「$name」をホーム画面に追加しました';
  }

  @override
  String get pinToHomeScreenUnsupported => 'このプラットフォームではホーム画面への固定に対応していません';

  @override
  String get storagePools => 'ストレージプール';

  @override
  String get storagePoolsSubtitle => 'SFTP・S3・WebDAV を 2 重化仮想ストレージに統合';

  @override
  String get createStoragePool => 'ストレージプールを作成';

  @override
  String get editStoragePool => 'ストレージプールを編集';

  @override
  String get noStoragePools => 'ストレージプールはありません';

  @override
  String get noStoragePoolsDesc =>
      '複数の SFTP・S3・WebDAV 接続を障害ドメイン分離の 2 レプリカ構成、チャンク分割、暗号化付き仮想ドライブとして統合します。';

  @override
  String get poolName => 'プール名';

  @override
  String get poolNameHint => '例: メディア統合プール';

  @override
  String get poolChunkSize => 'チャンクサイズ';

  @override
  String get poolEncryptEnable => 'クライアント側 AES-GCM 暗号化を有効にする';

  @override
  String get poolEncryptSubtitle => 'アップロード前にチャンクとメタデータスナップショットを暗号化';

  @override
  String get poolPassphrase => '暗号化パスフレーズ';

  @override
  String get poolPassphraseHint => '空欄のままにすると既存のパスフレーズを保持';

  @override
  String get poolSelectNodes => 'メンバーノードを選択';

  @override
  String get poolNeedRemotesFirst => '先にリモート接続で SFTP・S3・WebDAV を追加してください。';

  @override
  String get poolFailureDomain => '障害ドメイン';

  @override
  String get poolQuotaGb => 'クォータ (GB)';

  @override
  String get poolPrefix => 'リモートプレフィックス';

  @override
  String get poolRoleRw => '読み書き (RW)';

  @override
  String get poolRoleRo => '読み取り専用';

  @override
  String get poolRoleDraining => '退避中 (Drain)';

  @override
  String get poolRoleOffline => 'オフライン';

  @override
  String get poolMetaBackup => 'メタデータバックアップ';

  @override
  String get poolBrowse => 'ファイルを開く';

  @override
  String get poolProbeHealth => 'ヘルス計測';

  @override
  String get poolSyncMeta => 'メタ同期';

  @override
  String get poolHeal => '修復 (Heal)';

  @override
  String get poolGc => 'GC 実行';

  @override
  String get poolDrainNode => '退避 (Drain)';

  @override
  String get poolLogicalCapacity => '実効論理容量';

  @override
  String get poolPhysicalCapacity => '物理クォータ合計';

  @override
  String poolDegradedWarning(int count) {
    return '$count 個のチャンクが 2 レプリカ未満です — 修復 (Heal) を実行してください';
  }

  @override
  String get poolEncryptedBadge => '暗号化';

  @override
  String get poolPlaintextBadge => '標準';

  @override
  String poolMetaVersionBadge(int version) {
    return 'メタ v$version';
  }

  @override
  String poolDeleteConfirm(String name) {
    return 'ストレージプール「$name」を削除しますか？リモートのチャンクデータは削除されません。';
  }

  @override
  String poolDrainConfirm(String node) {
    return 'ノード「$node」のすべてのチャンクを他の健全なノードへ退避しますか？';
  }

  @override
  String poolSyncDone(String action, int version, int uploaded, int conflicts) {
    return 'メタ同期完了: $action (v$version, $uploaded バックアップ, 競合 $conflicts)';
  }

  @override
  String poolNodesCount(int count) {
    return '$count ノード';
  }

  @override
  String get lanTransferAndShareTitle => 'LAN 転送と WebDAV 共有';

  @override
  String get lanTransferAndShareSubtitle =>
      'LAN 直接転送・WebDAV マウント・ブラウザでのアップロード/ダウンロード';

  @override
  String get lanWebdavBrowserHint =>
      'ブラウザで直接開いてアップロード/ダウンロードできるほか、Finder・エクスプローラー・Infuse・Kodi からマウント可能です。';

  @override
  String get lanWebdavReadOnlyHint => '読み取り専用をオフにすると、ブラウザからのアップロードや編集が可能になります';

  @override
  String get photoBackupSourceLabel => 'バックアップ元フォルダ / アルバム';

  @override
  String get photoBackupSelectSource => 'フォルダを追加';

  @override
  String get photoBackupSelectAlbums => 'アルバムを選択';

  @override
  String get photoBackupDefaultSources => 'デフォルトの写真フォルダ';

  @override
  String get photoBackupAllAlbums => 'すべての写真と動画';

  @override
  String photoBackupSelectedAlbumsCount(int count) {
    return '$count 件のアルバムを選択中';
  }

  @override
  String get photoBackupResetSources => 'デフォルトに戻す';

  @override
  String get syncExcludeRulesTitle => '除外ルール';

  @override
  String get syncExcludeExtensionsLabel => '除外するファイル形式（拡張子）';

  @override
  String get syncExcludeExtensionsHint => '例: tmp, log, bak';

  @override
  String get syncExcludeNamesLabel => '除外するファイル名';

  @override
  String get syncExcludeNamesHint => '例: .DS_Store, Thumbs.db, ~\$*';

  @override
  String get syncExcludeDirsLabel => '除外するフォルダ';

  @override
  String get syncExcludeDirsHint => '例: node_modules, .git, build/cache';

  @override
  String get syncExcludePresets => 'よく使うプリセット';

  @override
  String get syncPickExcludeDir => 'フォルダ選択';

  @override
  String syncExcludedCount(int count) {
    return '$count 件を除外';
  }

  @override
  String get syncAddRule => '追加';

  @override
  String get peerManualAddressLabel => '送信先アドレス（手動入力）';

  @override
  String peerManualAddressExample(String hostPlaceholder) {
    return '例: http://$hostPlaceholder:ポート';
  }

  @override
  String get emptyLabel => '空';

  @override
  String itemCountConnections(int count) {
    return '$count 件の接続';
  }

  @override
  String itemCountPools(int count) {
    return '$count 個のプール';
  }

  @override
  String itemCountBookmarks(int count) {
    return '$count 件のブックマーク';
  }

  @override
  String itemCountLocations(int count) {
    return '$count 件の履歴';
  }

  @override
  String activeTasksRunningCount(int count) {
    return '$count 件実行中';
  }

  @override
  String get timeJustNow => 'たった今';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 時間前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 日前';
  }

  @override
  String deletedRelativeTime(String time) {
    return '$time に削除';
  }

  @override
  String get stopSharing => '共有を停止';

  @override
  String get manageRemotes => 'リモート管理';

  @override
  String get manageStoragePools => 'ストレージプール管理';

  @override
  String get backupRestoreConfigTitle => '設定のバックアップと復元';

  @override
  String get backupRestoreConfigSubtitle =>
      'リモート接続・ブックマーク・設定をエクスポートまたはインポート（AES-256 暗号化 .fmbak 対応）';

  @override
  String get exportAction => 'エクスポート';

  @override
  String get exportMigrationTitle => '移行用バックアップのエクスポート';

  @override
  String get exportMigrationPasswordLabel => '暗号化パスワード（推奨）';

  @override
  String get exportMigrationPasswordHint => '空欄の場合は資格情報なしの平文 JSON';

  @override
  String get exportIncludeCredentials => 'パスワードと鍵を含める（暗号化必須）';

  @override
  String get copyJsonAction => 'JSON をコピー';

  @override
  String get copyEncryptedAction => '暗号化データをコピー';

  @override
  String get saveBackupFileAction => '.fmbak を保存';

  @override
  String get saveJsonFileAction => '.json を保存';

  @override
  String get importMigrationTitle => 'デバイス設定をインポート';

  @override
  String get chooseBackupFileAction => '.fmbak または .json を選択';

  @override
  String get importPasteHint => 'または JSON / .fmbak テキストを貼り付け…';

  @override
  String get importPasswordLabel => '復号パスワード（暗号化時）';

  @override
  String get importPasswordHint => '資格情報付き .fmbak ファイルに必要';

  @override
  String get importPasswordRequiredError =>
      '暗号化された .fmbak バックアップの復号パスワードを入力してください。';

  @override
  String exportSavedNotice(String path) {
    return 'バックアップを $path に保存しました';
  }

  @override
  String get exportCopiedNotice => 'バックアップをクリップボードにコピーしました';

  @override
  String importSummaryNotice(int remotes, int bookmarks, int prefs) {
    return '$remotes 件のリモート、$bookmarks 件のブックマーク、$prefs 件の設定をインポートしました';
  }

  @override
  String get unencryptedCredentialsBanner =>
      '警告: OS キーチェーンが利用できないため、資格情報は平文で保存されます。';

  @override
  String get remoteTestTimedOut => '8 秒でタイムアウトしました';

  @override
  String remoteImportFailedSummary(int count, String details) {
    return '；$count 件失敗: $details';
  }

  @override
  String remoteBucketLabel(String bucket) {
    return 'バケット: $bucket';
  }

  @override
  String keyringUnavailableBanner(String detail) {
    return 'OS キーチェーンが利用できません（$detail）。資格情報が安全に保持されない場合があります。';
  }

  @override
  String deleteRemotePoolWarning(String pools) {
    return '警告: このリモートはストレージプール ($pools) で使用されています。削除するとプールが劣化・利用不可になります。';
  }

  @override
  String get poolConfirmGcTitle => 'ガベージコレクションを実行しますか？';

  @override
  String poolConfirmGcBody(String name) {
    return 'プール「$name」の未参照チャンクを完全に削除しますか？削除後は復元できません。';
  }

  @override
  String get poolReplicationFactorLabel => 'レプリケーション数';

  @override
  String poolMinNodesError(int count) {
    return '$count 倍レプリケーションには少なくとも $count 個のノードが必要です。';
  }

  @override
  String get poolInvalidQuotaError => '有効なクォータ（0 GB 超）を入力してください。';

  @override
  String get poolPassphraseConfirmLabel => '暗号化パスフレーズ（確認）';

  @override
  String get poolPassphraseMismatchError => 'パスフレーズが一致しません。';

  @override
  String get poolEditLockedHint => 'チャンクサイズと暗号化設定は作成後に変更できません。';

  @override
  String poolNodeHealthSummary(int pct, int ms, String state) {
    return '健全性 $pct% · $ms ms · $state';
  }

  @override
  String get poolRoleShortRw => '読み書き';

  @override
  String get poolRoleShortRo => '読み取り専用';

  @override
  String get poolRoleShortDraining => '排出中';

  @override
  String get poolRoleShortOffline => 'オフライン';

  @override
  String get poolCircuitClosed => '正常';

  @override
  String get poolCircuitOpen => '遮断';

  @override
  String get poolCircuitHalfOpen => '半開';

  @override
  String get cryptChooseBackingRemote => '既存のリモートまたはローカルフォルダを選択';

  @override
  String get cryptLocalFolderOption => 'ローカルフォルダを選択…';

  @override
  String fileConflictBody(String name) {
    return '「$name」はこのフォルダに既に存在します。どう処理しますか？';
  }

  @override
  String filesConflictBody(int count) {
    return '$count 件の同名の項目が既に存在します。どう処理しますか？';
  }

  @override
  String get offlineOverwriteConfirmTitle => 'リモートの変更を上書きしますか？';

  @override
  String offlineOverwriteConfirmBody(String name) {
    return 'リモート側の「$name」も更新されています。ローカルの変更で上書きしますか？';
  }

  @override
  String get offlineDiscardLocalConfirmTitle => 'ローカルのオフライン編集を破棄しますか？';

  @override
  String offlineDiscardLocalConfirmBody(String name) {
    return '「$name」には未同期のローカル変更または競合があります。続行すると上書きまたは削除されます。';
  }

  @override
  String offlineUploadedNotice(String name) {
    return '「$name」をリモートへアップロードしました。';
  }

  @override
  String get offlineCheckUpdatesTooltip => '更新を確認';

  @override
  String get offlineSyncAllTooltip => 'すべて同期';

  @override
  String get offlineLruCapTooltip => 'LRU キャッシュ上限';

  @override
  String offlineLruCapOption(String size) {
    return 'キャッシュ上限: $size';
  }

  @override
  String get offlineUploadLocalTooltip => 'ローカル変更をリモートにアップロード';

  @override
  String offlineBannerSummary(int count, String used, String cap) {
    return '固定 $count 件 · $used / $cap';
  }

  @override
  String get offlineStatusLocalModified => 'ローカル変更あり';

  @override
  String get offlineStatusRemoteNewer => 'リモートに更新あり';

  @override
  String get offlineStatusConflict => '競合';

  @override
  String get offlineStatusSynced => '同期済み';

  @override
  String get offlineStatusMissingLocal => 'ローカル欠損';

  @override
  String get offlineStatusOffline => 'オフライン';

  @override
  String get browserSelectItemsFirst => '先に 1 つ以上の項目を選択してください。';

  @override
  String clipboardReadOnlyHint(int count) {
    return 'クリップボード: $count 件（読み取り専用フォルダ）';
  }

  @override
  String get peerTabDirectTransfer => 'LAN ダイレクト転送';

  @override
  String get peerTabWebdavShare => 'WebDAV / ブラウザ共有';

  @override
  String peerPendingItemsToSend(int count) {
    return '送信準備完了: $count 件';
  }

  @override
  String get peerReceiveFolderMustBeLocal => '受信フォルダはローカルストレージ上に設定してください。';

  @override
  String get peerOpenReceivedFolder => 'フォルダを開く';

  @override
  String get peerCopyReceivedText => 'テキストをコピー';

  @override
  String get peerTextCopied => '受信テキストをクリップボードにコピーしました。';

  @override
  String get peerWaitingForAccept => '送信中・相手の承認を待機しています…';

  @override
  String get peerOfferStatusAccepted => '承認済み';

  @override
  String get peerOfferStatusCompleted => '完了';

  @override
  String get peerOfferStatusRejected => '拒否';

  @override
  String get peerOfferStatusReceiving => '受信中';

  @override
  String get photoBackupScanning => '写真とフォルダをスキャン中…';

  @override
  String get photoBackupCancel => 'キャンセル';

  @override
  String photoBackupCancelledNotice(int count) {
    return 'バックアップをキャンセルしました（$count 件アップロード済み）。';
  }

  @override
  String get photoBackupResetHistory => 'バックアップ履歴をリセット';

  @override
  String get photoBackupResetHistoryConfirm =>
      'ローカルのバックアップ履歴をクリアしますか？次回は再度チェック・アップロードされます。';

  @override
  String photoBackupLastRun(String time) {
    return '前回: $time';
  }

  @override
  String photoBackupProgressCount(int uploaded, int total) {
    return '$uploaded / $total 完了';
  }

  @override
  String get photoBackupOpenDestination => '保存先を開く';

  @override
  String get photoBackupVaultLocked => '保存先のプライバシーフォルダがロックされています';

  @override
  String get photoBackupPermissionDeniedTitle => '写真ライブラリのアクセス許可が必要です';

  @override
  String get photoBackupPermissionDeniedBody =>
      'システム設定で写真ライブラリへのアクセスを許可してください。';

  @override
  String get photoBackupOpenSettings => '設定を開く';

  @override
  String get syncSaveProfileTitle => '同期プロファイルを保存';

  @override
  String get syncProfileNameLabel => 'プロファイル名';

  @override
  String get syncSourceLabel => '同期元';

  @override
  String get syncDestinationLabel => '同期先';

  @override
  String get syncScanLimitReached => 'スキャン上限に達したためプレビューが省略されています。';

  @override
  String syncSummaryChanges(int changes, int unchanged) {
    return '$changes 件の変更 · $unchanged 件変更なし';
  }

  @override
  String get syncConfirmMirrorDeleteTitle => 'ミラー削除の確認';

  @override
  String syncConfirmMirrorDeleteBody(int count) {
    return '同期により同期先の不要なファイル/フォルダ $count 件が削除されます。続行しますか？';
  }

  @override
  String syncConfirmDeleteProfileBody(String name) {
    return '同期プロファイル「$name」を削除しますか？';
  }

  @override
  String get syncSwapFoldersTooltip => '同期元と同期先を入れ替え';

  @override
  String get syncSelectAll => 'すべて選択';

  @override
  String get syncDeselectAll => '選択解除';

  @override
  String get syncActionCopy => 'コピー';

  @override
  String get syncActionUpdate => '更新';

  @override
  String get syncActionDelete => '削除';

  @override
  String get syncActionPullUpdate => 'プル更新';

  @override
  String get syncEditConfig => 'フォルダ変更';

  @override
  String syncAutoSyncFailed(String error) {
    return '前回の自動同期に失敗: $error';
  }

  @override
  String get taskStatusPaused => '一時停止';

  @override
  String taskRateLimitActive(String limit) {
    return '制限: $limit';
  }

  @override
  String taskFailedItemsTitle(int count) {
    return '失敗詳細 ($count 件)';
  }

  @override
  String get taskRetryStarted => '失敗項目の再試行を開始しました。';

  @override
  String analyzerStatsSummary(int files, int folders) {
    return '$files ファイル · $folders フォルダ';
  }

  @override
  String get analyzerScanCancelled => '分析がキャンセルされました（部分結果）。';

  @override
  String get analyzerScanTruncated => 'スキャン上限に達しました。一部の深い階層は含まれません。';

  @override
  String get analyzerRescan => '再スキャン';

  @override
  String duplicatesGroupCount(int count) {
    return '$count グループ';
  }

  @override
  String duplicatesCopiesCount(int count) {
    return '($count 件)';
  }

  @override
  String duplicatesEachSize(String size) {
    return '各 $size';
  }

  @override
  String duplicatesDeleteFailed(int count) {
    return '$count 件の削除に失敗しました';
  }

  @override
  String duplicatesAllCopiesWarning(int count) {
    return '警告: $count グループですべてのコピーが削除対象に選択されています！';
  }

  @override
  String get duplicatesClearSelection => '選択クリア';

  @override
  String get duplicatesScanCancelled => '重複スキャンをキャンセルしました。';

  @override
  String duplicatesTrashConfirmBody(int count) {
    return '選択した $count 件をごみ箱へ移動しますか？';
  }

  @override
  String categoryTruncatedBanner(int count) {
    return '最初の $count 件のみ表示しています（上限到達）。';
  }

  @override
  String get galleryLocateInFolder => 'フォルダで開く';

  @override
  String get galleryUnsupportedFormatForPick => '要求された形式に一致しないファイルです。';

  @override
  String galleryExifSkippedNonJpeg(int count) {
    return 'JPEG 以外の $count 枚をスキップしました。';
  }

  @override
  String searchFiltersLabel(int count) {
    return 'フィルター ($count)';
  }

  @override
  String get searchAllTypes => 'すべて';

  @override
  String get pdfEncryptedError => 'この PDF は暗号化またはパスワード保護されています。';

  @override
  String pdfPageTextTitle(int page) {
    return '$page ページのテキスト';
  }

  @override
  String get pdfPageTextCopied => 'ページのテキストをクリップボードにコピーしました。';

  @override
  String get pdfNoSelectableText => '選択可能なテキストが見つかりません（スキャン画像の可能性があります）。';

  @override
  String get pdfSelectCopyPageText => 'テキストを選択 / コピー';

  @override
  String pdfRenderPageFailed(int page) {
    return '$page ページのレンダリングに失敗しました。';
  }

  @override
  String get structuredEmptyValue => '(空)';

  @override
  String structuredCsvTruncated(int shown, int total) {
    return '全 $total 行のうち最初の $shown 行を表示しています。';
  }

  @override
  String get copyXPath => 'XPath をコピー';

  @override
  String get subtitleLoadFailed => '非対応または読み込めない字幕ファイルです。';

  @override
  String get diffTruncatedNotice => 'ディレクトリ比較が上限に達したため一部省略されました。';

  @override
  String get diffSyncFoldersAction => '同期で開く';

  @override
  String get vaultHtmlBrowserWarning =>
      'ゼロディスク保護のため、プライバシーフォルダ内の HTML は外部ブラウザで開けません。';

  @override
  String get poolStorageDirectory => '保存先ディレクトリ';

  @override
  String get poolPickDirectory => 'フォルダを選択';

  @override
  String poolReplicationBadge(int count) {
    return '$count レプリカ';
  }

  @override
  String get poolSetReplicationTitle => 'レプリカ数の設定';

  @override
  String get poolSetReplicationHint => '新規書き込みに即時適用されます。既存ファイルは「修復」で補完できます。';

  @override
  String poolNodeRealFreeWithTotal(String free, String total) {
    return '空き $free / 合計 $total';
  }

  @override
  String poolNodeRealFreeOnly(String free) {
    return '空き $free';
  }

  @override
  String get poolNodeSpaceUnavailable => '空き容量を取得できません';

  @override
  String get poolNodeSpaceProbing => '空き容量を確認中…';

  @override
  String poolNodePoolUsed(String used) {
    return 'プール使用量: $used';
  }

  @override
  String poolNodeDirectoryLabel(String dir) {
    return 'ディレクトリ: $dir';
  }

  @override
  String get remoteBatchExportAction => '暗号化一括エクスポート';

  @override
  String get remoteBatchImportAction => '暗号化一括インポート';

  @override
  String get remoteBatchExportTitle => 'リモート接続を一括エクスポート';

  @override
  String get remoteBatchExportSubtitle =>
      '接続設定と資格情報は設定したパスワードで AES-256-GCM 暗号化されます。';

  @override
  String remoteBatchSelectCount(int selected, int total) {
    return '$selected / $total 件を選択中';
  }

  @override
  String get remoteBatchSelectAll => 'すべて選択';

  @override
  String get remoteBatchDeselectAll => '選択解除';

  @override
  String get remoteBatchUnreadableSkipped => '資格情報を読み取れないためエクスポート不可';

  @override
  String get remoteBatchNoReadableToExport => 'エクスポート可能なリモート接続がありません。';

  @override
  String get remoteBatchExportPasswordLabel => '暗号化パスワード（必須）';

  @override
  String remoteBatchExportPasswordHint(int min) {
    return '$min 文字以上';
  }

  @override
  String get remoteBatchExportPasswordConfirmLabel => '暗号化パスワード（確認）';

  @override
  String get remoteBatchPasswordRequiredNote =>
      'このパスワードはインポート時の復号に必要です。忘れないように保管してください。';

  @override
  String remoteBatchPasswordTooShort(int min) {
    return 'パスワードは $min 文字以上で入力してください。';
  }

  @override
  String get remoteBatchPasswordMismatch => 'パスワードが一致しません。';

  @override
  String get remoteBatchSaveFileAction => '暗号化ファイルを保存';

  @override
  String get remoteBatchShareFileAction => 'ファイルを書き出し / 共有';

  @override
  String remoteBatchExportSavedNotice(int count, String path) {
    return '$count 件の接続を $path に暗号化保存しました';
  }

  @override
  String remoteBatchExportSharedNotice(int count) {
    return '$count 件の接続の暗号化バックアップを作成しました。';
  }

  @override
  String remoteBatchExportCopiedNotice(int count) {
    return '$count 件の接続の暗号化バックアップをクリップボードにコピーしました。';
  }

  @override
  String get remoteBatchImportTitle => 'リモート接続を一括インポート';

  @override
  String get remoteBatchChooseFile => 'バックアップファイルを選択';

  @override
  String get remoteBatchPasteClipboard => 'クリップボードから貼り付け';

  @override
  String get remoteBatchClipboardDetected => 'クリップボードから暗号化バックアップを検出しました。';

  @override
  String get remoteBatchClipboardEmpty => 'クリップボードは空です。';

  @override
  String remoteBatchSelectedFileLabel(String name) {
    return '選択ファイル: $name';
  }

  @override
  String get remoteBatchPasteFieldHint =>
      'または暗号化された .fmremotes / .fmbak の内容を貼り付け…';

  @override
  String get remoteBatchImportPasswordLabel => '復号パスワード（必須）';

  @override
  String get remoteBatchImportPasswordHint => 'エクスポート時に設定したパスワードを入力';

  @override
  String get remoteBatchDecryptAction => '復号してプレビュー';

  @override
  String remoteBatchPreviewSummary(int count) {
    return '復号完了（$count 件の接続）';
  }

  @override
  String get remoteBatchConflictSectionLabel => '既存の接続と重複する場合:';

  @override
  String get remoteBatchConflictSkip => 'スキップ';

  @override
  String get remoteBatchConflictOverwrite => '上書き';

  @override
  String get remoteBatchConflictKeepBoth => '両方保持';

  @override
  String get remoteBatchBadgeNew => '新規';

  @override
  String get remoteBatchBadgeExists => '既存';

  @override
  String get remoteBatchAllSkippedHint =>
      '選択した接続はすべて既に存在しスキップされます。「上書き」または「両方保持」を選択してください。';

  @override
  String remoteBatchImportConfirm(int count) {
    return 'インポート ($count)';
  }

  @override
  String remoteBatchImportSummary(
    int imported,
    int added,
    int overwritten,
    int duplicated,
    int skipped,
    String detail,
  ) {
    return '$imported 件の接続をインポートしました（新規 $added・更新 $overwritten・複製 $duplicated・スキップ $skipped）$detail';
  }

  @override
  String get remoteBatchErrorNotEncrypted =>
      '暗号化されていない平文データは利用できません。パスワード保護されたバックアップを選択してください。';

  @override
  String get remoteBatchErrorInvalidFormat => 'バックアップファイルの形式が無効です。';

  @override
  String get remoteBatchErrorWrongPassword =>
      'パスワードが間違っているか、バックアップファイルが破損しています。';

  @override
  String get remoteBatchErrorEmptyBundle => 'このバックアップには有効なリモート接続が含まれていません。';

  @override
  String get remoteBatchErrorFileTooLarge => '選択したファイルが大きすぎるため読み込めません。';

  @override
  String get remoteBatchBackStep => '戻る';
}
