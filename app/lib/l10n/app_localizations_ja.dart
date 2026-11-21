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
}
