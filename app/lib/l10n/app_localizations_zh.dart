// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get aboutSection => '关于与系统';

  @override
  String get accentClassicBlue => '经典蓝';

  @override
  String get accentColor => '强调色';

  @override
  String get accentDeepTeal => '深海青';

  @override
  String get accentDynamic => '系统动态色';

  @override
  String get accentForest => '森林绿';

  @override
  String get accentGrape => '葡萄紫';

  @override
  String get accentIndigo => '靛蓝';

  @override
  String get accentSunset => '落日橙';

  @override
  String get actionInfo => '信息';

  @override
  String get allPhotos => '全部照片';

  @override
  String get almostDone => '即将完成';

  @override
  String get appTitle => 'FP文件管理器';

  @override
  String get appearance => '外观';

  @override
  String get ascending => '升序';

  @override
  String get bookmarks => '书签';

  @override
  String get browseInAppUpload => '应用内浏览上传…';

  @override
  String get browserSection => '浏览器';

  @override
  String get bucketName => '存储桶名称';

  @override
  String get bucketNameHint => '仅支持小写字母、数字和连字符 (3-63字符)';

  @override
  String get bucketRootFolderUploadError =>
      '当前处于多存储桶根目录，请先打开一个存储桶 (Bucket) 再上传文件夹。';

  @override
  String get bucketRootTransferError => '当前处于多存储桶根目录，请先打开一个存储桶 (Bucket) 再进行传输。';

  @override
  String get bucketRootUploadError => '当前处于多存储桶根目录，请先打开一个存储桶 (Bucket) 再上传文件。';

  @override
  String get bufferDuration => '缓冲时长';

  @override
  String get bufferSize => '缓冲大小';

  @override
  String get cancel => '取消';

  @override
  String get cancelTask => '取消任务';

  @override
  String get cancelled => '已取消';

  @override
  String get cancelling => '正在取消…';

  @override
  String get cannotCancelTask => '此任务无法取消';

  @override
  String cannotClearFinishedTasks(int count) {
    return '$count 个已完成的任务无法清除';
  }

  @override
  String get cannotDismissTask => '无法清除该任务';

  @override
  String get change => '更改';

  @override
  String get clear => '清理';

  @override
  String get clearFinished => '清除已完成';

  @override
  String get close => '关闭';

  @override
  String get closeSearch => '关闭搜索';

  @override
  String get cloudRemoteStorage => '云与远程存储';

  @override
  String get cloudToolsSettings => '云服务、工具与设置';

  @override
  String get completed => '已完成';

  @override
  String compressFailed(String error) {
    return '压缩失败: $error';
  }

  @override
  String get compressing => '正在压缩…';

  @override
  String get connectServer => '连接服务器';

  @override
  String get copyError => '复制错误';

  @override
  String copyFailed(String error) {
    return '复制失败: $error';
  }

  @override
  String get copyPassword => '复制密码';

  @override
  String get copyUrl => '复制网址';

  @override
  String get copyingFiles => '正在复制文件…';

  @override
  String get create => '创建';

  @override
  String createdCandidate(String name) {
    return '已创建 \"$name\"';
  }

  @override
  String get creatingCopy => '正在创建副本…';

  @override
  String get darkTheme => '深色主题';

  @override
  String get delete => '删除';

  @override
  String deleteFailed(String error) {
    return '删除失败: $error';
  }

  @override
  String deletedCount(int count) {
    return '已删除 $count 项';
  }

  @override
  String get deleting => '正在删除…';

  @override
  String get descending => '降序';

  @override
  String get desktopHtmlPreviewHint =>
      '桌面端为精简 HTML 预览。如需完整的 JS/CSS 样式效果，可在浏览器中打开。';

  @override
  String get dismiss => '关闭';

  @override
  String get downloadDestination => '选择下载目标文件夹';

  @override
  String downloadFailed(String error) {
    return '下载失败: $error';
  }

  @override
  String downloadedTo(String path) {
    return '已下载到 $path';
  }

  @override
  String downloadingFile(String file) {
    return '正在下载 $file…';
  }

  @override
  String get downloadingFiles => '正在下载文件…';

  @override
  String downloadingItem(String name) {
    return '正在下载 $name…';
  }

  @override
  String duplicateFailed(String error) {
    return '创建副本失败: $error';
  }

  @override
  String get emptyRecycleBin => '清空回收站';

  @override
  String get endpointHintS3 => '端点（AWS 可选，MinIO/R2 必填）';

  @override
  String get endpointHintGeneric =>
      '端点（例如 https://oss-cn-hangzhou.aliyuncs.com）';

  @override
  String get errorCopied => '错误信息已复制到剪贴板';

  @override
  String get exportPreviewCache => '导出与预览缓存';

  @override
  String extractFailed(String error) {
    return '解压失败: $error';
  }

  @override
  String get extracting => '正在解压…';

  @override
  String get failed => '失败';

  @override
  String failedToCreate(String error) {
    return '创建失败: $error';
  }

  @override
  String get finalizingServer => '正在完成（服务端处理中）…';

  @override
  String get folderLabel => '文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get followSystemSettings => '跟随系统设置';

  @override
  String get gallery => '相册';

  @override
  String get homeDashboard => '返回主页';

  @override
  String hoursLeft(int hours) {
    return '剩余约 $hours 小时';
  }

  @override
  String hoursMinutesLeft(int hours, int minutes) {
    return '剩余约 $hours 小时 $minutes 分钟';
  }

  @override
  String get inProgress => '进行中';

  @override
  String get invertSelection => '反选';

  @override
  String itemsCount(int count) {
    return '$count 项';
  }

  @override
  String itemsOutOfTotal(int completed, int total) {
    return '$completed / $total 项';
  }

  @override
  String get lanSharing => '局域网 HTTP 网页共享';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get lightTheme => '浅色主题';

  @override
  String get localStorage => '本地存储';

  @override
  String get mediaPlayback => '媒体播放 (远程缓冲)';

  @override
  String get minimize => '最小化';

  @override
  String minutesLeft(int minutes) {
    return '剩余约 $minutes 分钟';
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
    return '移动失败: $error';
  }

  @override
  String get movingFiles => '正在移动文件…';

  @override
  String get newBucket => '新建存储桶 (Bucket)';

  @override
  String get newFile => '新建文件';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get newTextFile => '新建文本文件';

  @override
  String get noLanIpFound => '未检测到局域网 IP，请连接 Wi-Fi 或网线。';

  @override
  String get noTasksYet => '暂无任务';

  @override
  String get openInBrowser => '用浏览器打开';

  @override
  String get options => '更多选项';

  @override
  String get passwordCopied => '密码已复制到剪贴板';

  @override
  String get passwordFieldHelper => '留空则仅凭带 Token 的链接直接访问，无需密码；设置后支持密码登录';

  @override
  String get passwordFieldLabel => '访问密码 (可选)';

  @override
  String get pdfMarginStandard => '标准 (36pt)';

  @override
  String get pdfMarginRelaxed => '宽松 (54pt)';

  @override
  String get pdfMarginCompact => '紧凑 (16pt)';

  @override
  String get pickFileTitle => '选择文件';

  @override
  String get pickFilesTitle => '选择文件';

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get pleaseSelectSpecificFolder => '请选择需要上传的具体文件夹';

  @override
  String get port => '端口';

  @override
  String get previewImage => '预览图片';

  @override
  String get processingPercent => '100% (处理中)';

  @override
  String get quickVolumes => '卷';

  @override
  String get quickRoot => '根目录 /';

  @override
  String get quickPictures => '图片';

  @override
  String get quickHome => '主目录';

  @override
  String quickDrive(String letter) {
    return '磁盘 ($letter:)';
  }

  @override
  String get quickDownloads => '下载';

  @override
  String get quickDownload => '下载';

  @override
  String get quickDesktop => '桌面';

  @override
  String get quickDcim => 'DCIM（照片）';

  @override
  String get readOnly => ' (只读)';

  @override
  String get readOnlyMode => '只读模式 (禁止网页端上传)';

  @override
  String get recent => '最近';

  @override
  String get recentDirs => '最近目录:';

  @override
  String get recycleBin => '回收站';

  @override
  String get remote => '远程';

  @override
  String get remoteArchiveCache => '远程与压缩包缓存';

  @override
  String get retry => '重试';

  @override
  String retryFailed(String error) {
    return '重试失败: $error';
  }

  @override
  String get runInBackground => '后台运行';

  @override
  String get runningOnLan => '🟢 局域网运行中';

  @override
  String get save => '保存';

  @override
  String get scriptDisabledTooltip => '脚本已禁用（安全默认），点击启用';

  @override
  String get scriptEnabledTooltip => '脚本已启用：页面代码可访问共享目录内的文件，点击禁用';

  @override
  String get searchFiles => '搜索文件';

  @override
  String secondsLeft(int seconds) {
    return '剩余约 $seconds 秒';
  }

  @override
  String get selectAll => '全选';

  @override
  String selectCount(int count) {
    return '选择 ($count)';
  }

  @override
  String get selectFolderToUpload => '选择要上传的文件夹';

  @override
  String get selectItems => '多选模式';

  @override
  String selectedCountLabel(int count) {
    return '已选 $count 项';
  }

  @override
  String selectedCountBytesLabel(int count, String size) {
    return '已选 $count 项（$size）';
  }

  @override
  String get settings => '设置';

  @override
  String get settingsCardSubtitle => '主题、系统信息、关于';

  @override
  String get shareInstructions => '同一 Wi-Fi 下浏览器打开以下地址即可访问（链接含访问令牌，请勿公开分享）：';

  @override
  String get sharePasswordLabel => '访问密码';

  @override
  String sharePasswordNotice(String pwd) {
    return '已自动生成访问密码：$pwd';
  }

  @override
  String get shared => '共享目录';

  @override
  String get sharedPathCopied => '共享目录路径已复制';

  @override
  String get showHiddenFiles => '显示隐藏文件';

  @override
  String skippedAlreadyExists(int count) {
    return '$count 项已跳过（已存在）';
  }

  @override
  String get sortBy => '排序方式';

  @override
  String get splitView => '分屏浏览';

  @override
  String get stopped => '⚪ 已停止';

  @override
  String get storageAndCache => '存储与缓存';

  @override
  String get supportedProtocols => '支持的协议';

  @override
  String get switchToGrid => '切换为网格视图';

  @override
  String get switchToList => '切换为列表视图';

  @override
  String get switchedToBackground => '已转入后台运行 — 可在 主页 → 任务 查看进度';

  @override
  String get systemPicker => '系统选择器';

  @override
  String get taskCompress => '压缩';

  @override
  String get taskCopy => '复制';

  @override
  String get taskDelete => '删除';

  @override
  String get taskExtract => '解压';

  @override
  String get taskGeneric => '任务';

  @override
  String get taskMove => '移动';

  @override
  String get tasks => '任务';

  @override
  String get tasksEmptySubtitle => '复制、移动以及其他长时间运行的操作将显示在此处。';

  @override
  String get theme => '主题';

  @override
  String get themeDark => '深色';

  @override
  String get themeLight => '浅色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get toolbarAtBottom => '工具栏置底';

  @override
  String get toolbarAtBottomDesc => '将地址栏和图标移到文件列表下方';

  @override
  String get toolbarUpOneLevel => '上一级目录';

  @override
  String get toolbarJump => '跳转';

  @override
  String get toolbarForwardHistory => '前进历史 (Alt+→)';

  @override
  String get toolbarEditAddress => '编辑地址 (Cmd/Ctrl+L)';

  @override
  String get toolbarBackHistory => '后退历史 (Alt+←)';

  @override
  String get transferring => '正在传输…';

  @override
  String trashCountNotice(int count) {
    return '回收站共有 $count 项';
  }

  @override
  String get unknownDate => '未知日期';

  @override
  String get upload => '上传';

  @override
  String get uploadFiles => '上传文件';

  @override
  String get uploadFolder => '上传文件夹';

  @override
  String get uploadItemsToCurrentFolder => '上传文件/文件夹到当前目录';

  @override
  String get uploadThisFolder => '上传此文件夹';

  @override
  String get uploadWithSystemPicker => '上传使用系统文件选择器';

  @override
  String get uploadWithSystemPickerDesc => '直接调用系统原生文件管理器，支持系统书签与路径粘贴';

  @override
  String uploadingFolder(String folder) {
    return '正在上传文件夹 \"$folder\"…';
  }

  @override
  String uploadingItems(int count) {
    return '正在上传 $count 项…';
  }

  @override
  String get urlCopied => '网址已复制到剪贴板';

  @override
  String get utilities => '工具';

  @override
  String get waiting => '等待中…';

  @override
  String get waitingServerVerify => '数据已全部发送，正在等待服务端校验与合并…';

  @override
  String get webSharingServer => '局域网网页共享服务';

  @override
  String get welcomeBody => '直接浏览本地文件夹，或连接服务器——SFTP、WebDAV、S3、SMB 等——随时随地管理文件。';

  @override
  String get welcomeTitle => '欢迎使用FP文件管理器';

  @override
  String get invalidBucketName =>
      '存储桶名称不符合规范。必须为 3-63 个字符，仅支持小写字母、数字和连字符 (-)，且必须以字母或数字开头和结尾。';

  @override
  String get sortByName => '按名称';

  @override
  String get sortBySize => '按大小';

  @override
  String get sortByDate => '按修改日期';

  @override
  String get sortByType => '按文件类型';

  @override
  String get openSourceLicenses => '开源许可声明';

  @override
  String get openSourceLicensesSubtitle => '第三方开源库授权协议及版权声明';

  @override
  String get open => '打开';

  @override
  String get openWith => '打开方式';

  @override
  String get download => '下载';

  @override
  String get downloadToLocal => '下载到本地';

  @override
  String get copy => '复制';

  @override
  String get cut => '剪切';

  @override
  String pasteCount(int count) {
    return '粘贴 ($count)';
  }

  @override
  String get copyPath => '复制路径';

  @override
  String get copyFolderPath => '复制文件夹路径';

  @override
  String get copyFilePath => '复制文件路径';

  @override
  String get copyOriginalPath => '复制原路径';

  @override
  String get pathCopied => '路径已复制到剪贴板';

  @override
  String get folderPathCopied => '文件夹路径已复制到剪贴板';

  @override
  String copiedPathValue(String path) {
    return '已复制路径：$path';
  }

  @override
  String copiedValue(String value) {
    return '已复制：$value';
  }

  @override
  String copiedItemToClipboard(String name) {
    return '已复制 $name 到剪贴板';
  }

  @override
  String cutItemToClipboard(String name) {
    return '已剪切 $name 到剪贴板';
  }

  @override
  String copiedItemsCount(int count) {
    return '已复制 $count 个项目到剪贴板';
  }

  @override
  String cutItemsCount(int count) {
    return '已剪切 $count 个项目到剪贴板';
  }

  @override
  String get rename => '重命名';

  @override
  String get newName => '新名称';

  @override
  String get duplicate => '创建副本';

  @override
  String get share => '分享';

  @override
  String get properties => '属性';

  @override
  String get details => '详情';

  @override
  String get extractHere => '解压到此处';

  @override
  String get compress => '压缩';

  @override
  String get compressToZip => '压缩为 ZIP';

  @override
  String get archiveName => '压缩包名称';

  @override
  String get bookmarkThisFolder => '收藏此文件夹';

  @override
  String get bookmarkLocation => '收藏此位置';

  @override
  String bookmarkedName(String name) {
    return '已收藏“$name”';
  }

  @override
  String alreadyBookmarked(String name) {
    return '“$name”已在收藏夹中';
  }

  @override
  String get refresh => '刷新';

  @override
  String get undo => '撤销';

  @override
  String get discard => '放弃';

  @override
  String get go => '跳转';

  @override
  String get goUp => '返回上级';

  @override
  String get loadMore => '加载更多';

  @override
  String get clearFilter => '清除筛选';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get searchAction => '搜索';

  @override
  String get remove => '移除';

  @override
  String removedName(String name) {
    return '已移除“$name”';
  }

  @override
  String get unknownSize => '未知';

  @override
  String get wrapIndicator => '换行';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get ok => '确定';

  @override
  String get typeLabel => '类型';

  @override
  String get nameLabel => '名称';

  @override
  String get pathLabel => '路径';

  @override
  String get extensionLabel => '扩展名';

  @override
  String get sizeLabel => '大小';

  @override
  String get modifiedLabel => '已修改';

  @override
  String get hiddenLabel => '隐藏';

  @override
  String get hiddenFilesOff => '隐藏文件未显示';

  @override
  String get symlinkLabel => '符号链接';

  @override
  String get directoryLabel => '目录';

  @override
  String get directoryEmptyLabel => '目录（空）';

  @override
  String get fileLabel => '文件';

  @override
  String get archiveLabel => '压缩包';

  @override
  String get measuring => '计算中…';

  @override
  String bytesUnit(String count) {
    return '$count 字节';
  }

  @override
  String yesBytes(String formatted, String raw) {
    return '$formatted（$raw 字节）';
  }

  @override
  String get downloadFileTitle => '下载文件？';

  @override
  String get downloadFileStreamHint => '此文件不支持在线流式预览，需要先下载到本地。';

  @override
  String get saveDestination => '保存位置';

  @override
  String get chooseDownloadFolder => '选择下载文件夹';

  @override
  String get folderIsEmpty => '文件夹为空';

  @override
  String get noMatchingItems => '没有匹配的项目';

  @override
  String get openFolderTooltip => '打开文件夹';

  @override
  String get deselectAll => '取消全选';

  @override
  String get filterFilesFoldersHint => '筛选文件与文件夹...';

  @override
  String get noSubfolders => '没有子文件夹';

  @override
  String get noMatchingSubfolders => '没有匹配的子文件夹';

  @override
  String get hideHiddenFolders => '隐藏隐藏文件夹';

  @override
  String get showAllFileTypes => '全部文件';

  @override
  String get showHiddenFolders => '显示隐藏文件夹';

  @override
  String get hideHiddenFiles => '隐藏隐藏文件';

  @override
  String get filterSubfoldersHint => '筛选子文件夹...';

  @override
  String get cannotReadFolderPrefix => '无法读取此文件夹：';

  @override
  String failedCreateFolder(String error) {
    return '创建文件夹失败：$error';
  }

  @override
  String get filterEllipsis => '筛选...';

  @override
  String get parentFolderTooltip => '上级文件夹';

  @override
  String get clickToCopyPath => '点击复制路径';

  @override
  String get folderNameHint => '例如 Documents';

  @override
  String get folderNameInputLabel => '文件夹名称';

  @override
  String couldNotRequestFileAccess(String error) {
    return '无法请求文件访问权限：$error';
  }

  @override
  String couldNotRefreshHome(String error) {
    return '无法刷新首页数据：$error';
  }

  @override
  String get storagePermissionRequired => '需要存储权限才能浏览文件，请在接下来的页面中授予“所有文件访问权限”。';

  @override
  String get requesting => '请求中…';

  @override
  String get grant => '授权';

  @override
  String get remoteProtocolsSubtitle => 'S3、OSS、SFTP、WebDAV...';

  @override
  String utilitiesTrashSubtitle(int count) {
    return '回收站 $count 项 • 局域网共享';
  }

  @override
  String get utilitiesDefaultSubtitle => '回收站、局域网共享、缓存';

  @override
  String get tasksDefaultSubtitle => '传输与文件操作';

  @override
  String get bookmarksDefaultSubtitle => '已收藏的文件夹';

  @override
  String get recentDefaultSubtitle => '浏览历史记录';

  @override
  String get sortLabelName => '名称';

  @override
  String get sortLabelSize => '大小';

  @override
  String get sortLabelDate => '日期';

  @override
  String get sortLabelType => '类型';

  @override
  String couldNotLoadMore(String error) {
    return '加载更多失败：$error';
  }

  @override
  String refreshFailed(String error) {
    return '刷新失败：$error';
  }

  @override
  String downloadedNoAppToOpen(String name) {
    return '已下载，但没有已安装的应用可打开 $name';
  }

  @override
  String get allowInstallApkPrompt => '请允许安装未知应用以打开 APK 文件';

  @override
  String noAppToOpenFile(String name) {
    return '没有已安装的应用可打开 $name';
  }

  @override
  String cannotOpenFile(String error) {
    return '无法打开文件：$error';
  }

  @override
  String cannotShareFile(String error) {
    return '无法分享文件：$error';
  }

  @override
  String searchFailed(String error) {
    return '搜索失败：$error';
  }

  @override
  String noSearchResultsFor(String query) {
    return '未找到与“$query”相关的结果';
  }

  @override
  String get searchedThisAndSubfolders => '已搜索当前文件夹及其子文件夹。';

  @override
  String get first200Results => '仅显示前 200 条结果（请缩小搜索范围以查看更多）';

  @override
  String searchResultsInFolder(int count) {
    return '此文件夹及子文件夹中的结果：$count';
  }

  @override
  String searchFoundCount(int count) {
    return '找到 $count 个';
  }

  @override
  String get currentFolder => '当前文件夹';

  @override
  String fileBeyondFirstPage(String parent) {
    return '文件位于“$parent”的后续分页中，请打开该文件夹查看。';
  }

  @override
  String tooManyItemsSelectAll(int count) {
    return '项目过多（$count 个），无法一次性全选';
  }

  @override
  String couldNotLoadAllItems(String error) {
    return '无法加载全部项目：$error';
  }

  @override
  String get alreadyLocalUseCopy => '文件已在本地，请使用“复制”将其放到其他位置。';

  @override
  String get fileNameLabel => '文件名';

  @override
  String get fileNameHint => '例如 notes.txt';

  @override
  String failedToCreateFile(String error) {
    return '创建文件失败：$error';
  }

  @override
  String get alreadyExists => '目标已存在';

  @override
  String get skip => '跳过';

  @override
  String get keepBoth => '保留两者';

  @override
  String get replace => '替换';

  @override
  String get readOnlyCannotDrop => '此位置为只读，无法拖放文件到此';

  @override
  String get cannotDropFolderIntoSelf => '不能将文件夹拖放到自身或其子文件夹中';

  @override
  String deleteSingleConfirmTitle(String name) {
    return '删除“$name”？';
  }

  @override
  String deleteMultipleConfirmTitle(int count) {
    return '删除 $count 个项目？';
  }

  @override
  String get deleteChoiceTrashOrPermanent => '选择移至回收站或永久删除。';

  @override
  String get deletePermanentWarning => '确定永久删除？此操作不可撤销。';

  @override
  String get deleteRemotePermanentWarning => '此项目位于远程服务器上，无法移至本地回收站，将被永久删除。';

  @override
  String get permanentDelete => '永久删除';

  @override
  String couldNotMoveToTrash(int failed, int total, String details) {
    return '$total 个项目中有 $failed 个无法移至回收站：\n$details';
  }

  @override
  String get movedOneToTrash => '已将 1 个项目移至回收站';

  @override
  String movedManyToTrash(int count) {
    return '已将 $count 个项目移至回收站';
  }

  @override
  String couldNotRestoreItems(int count) {
    return '无法还原 $count 个项目';
  }

  @override
  String get nameCannotContainSlash => '名称不能包含“/”或“\\”';

  @override
  String renameFailed(String error) {
    return '重命名失败：$error';
  }

  @override
  String get rootLabel => '根目录';

  @override
  String get exitSplitView => '退出分屏视图';

  @override
  String get cancelSelectionEsc => '取消选择 (Esc)';

  @override
  String get backToPreviousPage => '返回上一页';

  @override
  String get backToTop => '回到顶部';

  @override
  String get searchFilesSubfoldersHint => '搜索文件与子文件夹…';

  @override
  String get listView => '列表视图';

  @override
  String get gridView => '网格视图';

  @override
  String sortStatusTooltip(String field, String arrow) {
    return '排序：$field $arrow';
  }

  @override
  String get internalStorage => '内部存储';

  @override
  String get capabilitiesPrefix => '支持能力：';

  @override
  String get failedToLoadDir => '加载目录失败';

  @override
  String noFilesMatching(String query) {
    return '没有匹配“$query”的文件';
  }

  @override
  String get onlyHiddenFilesHere => '此目录仅包含隐藏文件';

  @override
  String get directoryIsEmpty => '目录为空';

  @override
  String get enterPathToJumpHint => '输入路径以跳转...';

  @override
  String get goToLine => '跳转到行';

  @override
  String lineNumberRange(int total) {
    return '行号 (1 - $total)';
  }

  @override
  String enterLineNumberBetween(int total) {
    return '请输入 1 到 $total 之间的行号';
  }

  @override
  String replacedOccurrences(int count) {
    return '已替换 $count 处';
  }

  @override
  String get reloadFile => '重新加载文件';

  @override
  String get reloadFileConfirm => '放弃未保存的更改并从磁盘重新加载文件？';

  @override
  String get reload => '重新加载';

  @override
  String get fileSavedSuccess => '文件保存成功';

  @override
  String saveFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String pdfExportFailed(String error) {
    return 'PDF 导出失败：$error';
  }

  @override
  String get saveChangesQuestion => '保存更改？';

  @override
  String get saveBeforeBrowserPrompt => '在外部浏览器中打开前，是否保存更改？';

  @override
  String get openWithoutSaving => '不保存直接打开';

  @override
  String get saveAndOpen => '保存并打开';

  @override
  String failedOpenInBrowser(String error) {
    return '在浏览器中打开失败：$error';
  }

  @override
  String get unsavedChanges => '未保存的更改';

  @override
  String get saveBeforeClosingPrompt => '有未保存的更改，关闭前是否保存？';

  @override
  String get findInFileTooltip => '在文件中查找 (Ctrl+F)';

  @override
  String get showSource => '显示源码';

  @override
  String get showPreview => '显示预览';

  @override
  String get markdownTheme => 'Markdown 主题';

  @override
  String get exportToPdf => '导出为 PDF';

  @override
  String get printPreviewPdf => '打印 / 预览 PDF';

  @override
  String get shareSavePdf => '分享 / 保存 PDF';

  @override
  String get marginsSpacing => '页边距 / 间距';

  @override
  String get readOnlyCannotEditTooltip => '只读位置 — 无法在此编辑此文件';

  @override
  String get saveChangesTooltip => '保存更改 (Ctrl+S)';

  @override
  String get saveAs => '另存为...';

  @override
  String get saveToThisFolder => '保存到此文件夹';

  @override
  String get savedToCachePrompt => '已保存到应用缓存，建议点击【另存为】存至手机存储';

  @override
  String get savedLabel => '已保存';

  @override
  String get editLabel => '编辑';

  @override
  String get textOptions => '文本选项';

  @override
  String get allTextCopied => '已复制全部文本到剪贴板';

  @override
  String get reloadFromDiskShortcut => '从磁盘重新加载 (Ctrl+R)';

  @override
  String get copyAllText => '复制全部文本';

  @override
  String get goToLineShortcut => '跳转到行... (Ctrl+G)';

  @override
  String largerFontShortcut(int pt) {
    return '放大字体 (Ctrl+=) ($pt pt)';
  }

  @override
  String smallerFontShortcut(int pt) {
    return '缩小字体 (Ctrl+-) ($pt pt)';
  }

  @override
  String get resetFontShortcut => '重置字号 (Ctrl+0) (13pt)';

  @override
  String get wordWrap => '自动换行';

  @override
  String get undoShortcut => '撤销 (Ctrl+Z)';

  @override
  String get redoShortcut => '重做 (Ctrl+Y)';

  @override
  String failedToOpenFile(String error) {
    return '打开文件失败：$error';
  }

  @override
  String get readOnlyCannotSave => '只读位置 — 更改无法保存在此处。';

  @override
  String get findInFileHint => '在文件中查找...';

  @override
  String get previousMatch => '上一个匹配项';

  @override
  String get nextMatch => '下一个匹配项';

  @override
  String get toggleReplaceShortcut => '切换替换栏 (Ctrl+H)';

  @override
  String get closeFindShortcut => '关闭查找 (Esc)';

  @override
  String get replaceWithHint => '替换为...';

  @override
  String get replaceAll => '全部替换';

  @override
  String get documentDetails => '文档详情';

  @override
  String get copyAll => '复制全部';

  @override
  String get documentCopied => '已复制文档内容到剪贴板';

  @override
  String get linesLabel => '行数';

  @override
  String get wordsLabel => '词数';

  @override
  String get charactersLabel => '字符数';

  @override
  String get byteSizeLabel => '字节大小';

  @override
  String get lineEndingsLabel => '换行符';

  @override
  String get cursorPositionLabel => '光标位置';

  @override
  String cursorLineCol(int line, int col) {
    return '第 $line 行，第 $col 列';
  }

  @override
  String get readOnlyLocation => '只读位置';

  @override
  String get previewModeLabel => '预览';

  @override
  String get viewingSourceLabel => '查看源码';

  @override
  String get editingModeLabel => '编辑中';

  @override
  String editorStatusLine(int line, int col, int lines) {
    return '行 $line, 列 $col  •  总行数：$lines  •  ';
  }

  @override
  String editorStatusWords(int words) {
    return '词数：$words  •  ';
  }

  @override
  String editorStatusChars(int chars) {
    return '字符：$chars  •  ';
  }

  @override
  String get documentIsEmpty => '文档为空';

  @override
  String get editInSourceMode => '在源码模式中编辑';

  @override
  String couldNotScanPhotos(String error) {
    return '无法扫描照片。\n$error';
  }

  @override
  String get photoLibraryDenied => '照片库访问权限被拒绝。\n请在“设置 → 隐私 → 照片”中开启权限。';

  @override
  String couldNotLoadMorePhotos(String error) {
    return '无法加载更多照片：$error';
  }

  @override
  String cannotOpenPhoto(String error) {
    return '无法打开照片：$error';
  }

  @override
  String get photoNoLongerAvailable => '照片已不可用';

  @override
  String get openInViewer => '在看图器中打开';

  @override
  String get sharePhoto => '分享照片';

  @override
  String get photosTitle => '照片';

  @override
  String get rescan => '重新扫描';

  @override
  String get scrollToTop => '回到顶部';

  @override
  String get noPhotosFound => '未找到照片';

  @override
  String get openSettings => '打开设置';

  @override
  String cannotReadImageDetails(String error) {
    return '无法读取图片详情：$error';
  }

  @override
  String get imageDetailsUnavailable => '图片详情已不可用';

  @override
  String get imageDetails => '图片详情';

  @override
  String get dimensionsLabel => '尺寸';

  @override
  String get dateTakenLabel => '拍摄日期';

  @override
  String get cameraLabel => '相机';

  @override
  String get locationLabel => '位置';

  @override
  String cannotLoadImage(String error) {
    return '无法加载图片：$error';
  }

  @override
  String get imageFileNotFoundLocally => '本地未找到图片文件';

  @override
  String get failedToLoadImage => '加载图片失败';

  @override
  String get imagePathCopied => '图片路径已复制';

  @override
  String cannotCopyPath(String error) {
    return '无法复制路径：$error';
  }

  @override
  String cannotShareImage(String error) {
    return '无法分享图片：$error';
  }

  @override
  String get deleteImageConfirm => '确定要删除这张图片吗？此操作无法撤销。';

  @override
  String deletedItem(String name) {
    return '已删除 $name';
  }

  @override
  String failedToDelete(String error) {
    return '删除失败：$error';
  }

  @override
  String get shareImage => '分享图片';

  @override
  String get rotate90 => '旋转 90°';

  @override
  String get rotate90Shortcut => '旋转 90° (R)';

  @override
  String get deleteImage => '删除图片';

  @override
  String get moreOptions => '更多选项';

  @override
  String get moreBelow => '下方还有更多';

  @override
  String get zoomInShortcut => '放大 (+)';

  @override
  String get zoomOutShortcut => '缩小 (-)';

  @override
  String get resetZoomShortcut => '重置缩放 (0)';

  @override
  String get previousImage => '上一张图片';

  @override
  String get nextImage => '下一张图片';

  @override
  String autoPlayingNext(String name) {
    return '即将自动播放：$name';
  }

  @override
  String get nextEpisodeShortcut => '下一集 / 下一首 (N)';

  @override
  String playlistProgress(int current, int total) {
    return '播放列表 ($current/$total)';
  }

  @override
  String get autoNextOn => '自动连播：开启';

  @override
  String get autoNextOff => '自动连播：关闭';

  @override
  String get loopSingle => '循环：单曲';

  @override
  String get loopOff => '循环：关闭';

  @override
  String get fullscreenShortcut => '全屏 (F)';

  @override
  String get fullscreen => '全屏';

  @override
  String get exitFullscreen => '退出全屏';

  @override
  String get playbackOptions => '播放选项';

  @override
  String get unmuteShortcut => '取消静音 (M)';

  @override
  String muteShortcut(int percent) {
    return '静音 (M) ($percent%)';
  }

  @override
  String get rewind10s => '快退 10 秒';

  @override
  String get forward10s => '快进 10 秒';

  @override
  String get autoNextMenuOn => '自动连播（开）';

  @override
  String get autoNextMenuOff => '自动连播（关）';

  @override
  String get previousShortcut => '上一个 (P)';

  @override
  String get nextShortcut => '下一个 (N)';

  @override
  String get cannotPlayFile => '无法播放此文件';

  @override
  String get unknownPlaybackError => '未知播放错误';

  @override
  String couldNotLoadBookmarks(String error) {
    return '无法加载收藏夹：$error';
  }

  @override
  String get renameBookmark => '重命名书签';

  @override
  String get bookmarkNameLabel => '书签名称';

  @override
  String couldNotRenameBookmark(String error) {
    return '无法重命名书签：$error';
  }

  @override
  String couldNotRemoveBookmark(String error) {
    return '无法移除书签：$error';
  }

  @override
  String couldNotRestoreBookmark(String error) {
    return '无法恢复书签：$error';
  }

  @override
  String get searchBookmarks => '搜索收藏夹';

  @override
  String get filterBookmarksHint => '筛选收藏夹...';

  @override
  String get noBookmarksSaved => '暂无保存的书签';

  @override
  String get noMatchingBookmarks => '没有匹配的书签';

  @override
  String get bookmarksEmptyHint => '在文件浏览器中长按或右键文件夹，选择“收藏此文件夹”即可添加。';

  @override
  String nothingMatchesQuery(String query) {
    return '没有匹配“$query”的内容。';
  }

  @override
  String get bookmarkActions => '书签操作';

  @override
  String couldNotLoadRecent(String error) {
    return '无法加载最近记录：$error';
  }

  @override
  String failedToBookmark(String error) {
    return '添加书签失败：$error';
  }

  @override
  String couldNotRemoveItem(String name, String error) {
    return '无法移除“$name”：$error';
  }

  @override
  String get clearHistory => '清除历史记录';

  @override
  String get clearHistoryConfirm => '确定移除所有最近访问的位置吗？书签将被保留。';

  @override
  String couldNotClearHistory(String error) {
    return '无法清除历史记录：$error';
  }

  @override
  String clearedRecentLocations(int count) {
    return '已清除 $count 条最近记录';
  }

  @override
  String get removeFromHistory => '从历史记录移除';

  @override
  String get recentHistory => '最近记录';

  @override
  String get searchHistory => '搜索历史记录';

  @override
  String get filterRecentHint => '筛选最近位置...';

  @override
  String get noRecentHistory => '暂无最近浏览记录';

  @override
  String get noMatchingLocations => '没有匹配的位置';

  @override
  String get recentEmptyHint => '您浏览过的目录和文件会显示在这里。';

  @override
  String get actionsTooltip => '操作';

  @override
  String couldNotLoadTrash(String error) {
    return '无法加载回收站：$error';
  }

  @override
  String get recycledItemDetails => '回收站项目详情';

  @override
  String get originalPathColon => '原路径：';

  @override
  String get originalPathCopied => '原路径已复制到剪贴板';

  @override
  String get restore => '还原';

  @override
  String get restoreItem => '还原项目';

  @override
  String get viewDetails => '查看详情';

  @override
  String get deletePermanently => '永久删除';

  @override
  String couldNotRestoreNamed(String name, String error) {
    return '无法还原“$name”：$error';
  }

  @override
  String restoredNamed(String name) {
    return '已还原“$name”';
  }

  @override
  String permanentlyDeleteConfirm(String name) {
    return '确定永久删除“$name”？';
  }

  @override
  String couldNotDeleteNamed(String name, String error) {
    return '无法删除“$name”：$error';
  }

  @override
  String get emptyAll => '全部清空';

  @override
  String permanentlyDeleteAllTrash(int count, String size) {
    return '确定永久删除全部 $count 个项目（$size）？此操作不可撤销。';
  }

  @override
  String couldNotEmptyTrash(String error) {
    return '无法清空回收站：$error';
  }

  @override
  String get recycleBinEmptied => '回收站已清空';

  @override
  String get restoreAllItems => '全部还原';

  @override
  String restoreAllConfirm(int count) {
    return '确定将全部 $count 个项目还原到原位置？';
  }

  @override
  String get restoreAll => '全部还原';

  @override
  String restoredCountOfTotal(int done, int total) {
    return '已还原 $done / $total 个项目';
  }

  @override
  String restoredPartialTrash(int done, int total, int failed, String sample) {
    return '已还原 $done / $total 项。仍在回收站：$failed 项（$sample）';
  }

  @override
  String restoringProgress(int done, int total) {
    return '正在还原 $done / $total…';
  }

  @override
  String recycleBinSummary(int count, String size) {
    return '回收站 • $count 项，$size';
  }

  @override
  String get searchTrash => '搜索回收站';

  @override
  String get filterRecycledHint => '筛选回收站文件...';

  @override
  String get recycleBinIsEmpty => '回收站为空';

  @override
  String get noMatchingItemsTrash => '回收站中没有匹配的项目';

  @override
  String get trashEmptyHint => '已删除的文件和文件夹会显示在这里。';

  @override
  String get connectAndBrowse => '连接并浏览';

  @override
  String get testConnection => '测试连接';

  @override
  String get copyUri => '复制 URI';

  @override
  String get editConfiguration => '编辑配置';

  @override
  String get deleteRemote => '删除远程连接';

  @override
  String addedRemote(String name) {
    return '已添加远程连接：$name';
  }

  @override
  String deleteRemoteConfirm(String name) {
    return '确定移除“$name”？\n\n这只会从本应用移除已保存的连接配置，不会影响远程服务器上的文件。';
  }

  @override
  String get connectionNoReadableDetails => '此连接没有可读取的详细信息，请编辑并重新输入。';

  @override
  String testingRemote(String name) {
    return '正在测试“$name”…';
  }

  @override
  String connectedToRemote(String name) {
    return '已成功连接到“$name”';
  }

  @override
  String cannotReachRemote(String name) {
    return '无法连接到“$name”';
  }

  @override
  String get noConnectionsToExport => '没有可导出的连接';

  @override
  String backupConnectionsCount(int count) {
    return '备份连接 ($count)';
  }

  @override
  String get backupConnectionsDesc => '将已配置的连接导出为 JSON，您可以复制或分享/保存到文件。';

  @override
  String get copyToClipboard => '复制到剪贴板';

  @override
  String get connectionsCopied => '连接配置已复制到剪贴板';

  @override
  String get shareSaveToFiles => '分享 / 保存到文件';

  @override
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get restoreConnections => '恢复连接';

  @override
  String get pasteJsonBackupHint => '请在下方粘贴 JSON 备份文本：';

  @override
  String importedConnections(int count, String detail) {
    return '已导入 $count 个连接$detail';
  }

  @override
  String importFailed(String error) {
    return '导入失败：$error';
  }

  @override
  String get importAction => '导入';

  @override
  String get searchRemotes => '搜索远程连接';

  @override
  String get addConnection => '添加连接';

  @override
  String get backupRestore => '备份 / 恢复';

  @override
  String get backupExport => '备份 / 导出';

  @override
  String get restoreImport => '恢复 / 导入';

  @override
  String get filterRemotesHint => '筛选远程连接...';

  @override
  String get noRemoteConnections => '尚未配置远程连接';

  @override
  String get noRemoteConnectionsDesc =>
      '连接 Amazon S3、阿里云 OSS、WebDAV、SFTP、FTP 或 SMB 网络存储。';

  @override
  String get addRemoteStorage => '添加远程存储';

  @override
  String get editRemoteStorage => '编辑远程存储';

  @override
  String get noMatchingConnections => '没有匹配的连接';

  @override
  String get addAnotherRemote => '添加更多远程存储';

  @override
  String get detailsUnavailableReconnect => '详情不可用 — 请重新输入凭据以连接';

  @override
  String get remoteActions => '远程连接操作';

  @override
  String couldNotLoadConnections(String error) {
    return '无法加载连接：$error';
  }

  @override
  String get portMustBeNumber => '端口必须为数字。';

  @override
  String get portRangeError => '端口必须在 1 到 65535 之间。';

  @override
  String get connectionSuccessful => '连接成功！';

  @override
  String get connectionReturnedFalse => '连接测试返回失败';

  @override
  String connectionFailedWithError(String error) {
    return '连接失败：$error';
  }

  @override
  String idAlreadyUsed(String id, String name) {
    return '标识符“$id”已被“$name”占用';
  }

  @override
  String savedOldEntryRemoveFailed(String oldId, String error) {
    return '已保存，但旧条目“$oldId”移除失败：$error';
  }

  @override
  String couldNotSave(String error) {
    return '无法保存：$error';
  }

  @override
  String get protocolProvider => '协议 / 服务商';

  @override
  String get providerS3 => 'Amazon S3 / S3 兼容 (MinIO, R2)';

  @override
  String get providerOss => '阿里云 OSS 对象存储';

  @override
  String get providerWebdav => 'WebDAV (Nextcloud, OwnCloud)';

  @override
  String get providerSftp => 'SFTP (SSH 文件传输)';

  @override
  String get providerFtp => 'FTP / FTPS';

  @override
  String get providerSmb => 'SMB / Windows 共享 (Samba)';

  @override
  String get displayName => '显示名称';

  @override
  String get pleaseEnterName => '请输入名称';

  @override
  String get identifierLabel => '标识符 / ID (如 sftp_mac, my_nas)';

  @override
  String get identifierHint => '用于远程路径：remote://id/...';

  @override
  String get generateIdTooltip => '根据名称自动生成 ID';

  @override
  String get pleaseEnterId => '请输入标识符';

  @override
  String get idCharsetError => '标识符只能包含字母、数字、连字符和下划线';

  @override
  String get bucketNameOptional => 'Bucket 名称（可选，留空浏览全部）';

  @override
  String get bucketNameOptionalHint => '留空以浏览全部 Bucket，或用逗号分隔多个';

  @override
  String get regionLabel => '区域 Region (如 us-east-1, auto)';

  @override
  String get usePathStyle => '使用 Path-Style（适用于 MinIO / 本地 S3）';

  @override
  String get accessKeyId => 'Access Key ID';

  @override
  String get secretAccessKey => 'Secret Access Key';

  @override
  String get showSecretKey => '显示密钥';

  @override
  String get hideSecretKey => '隐藏密钥';

  @override
  String get webdavUrlLabel => 'WebDAV 地址 (如 https://example.com/dav)';

  @override
  String get urlRequired => '请输入 URL';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get authMethod => '认证方式';

  @override
  String get authPassword => '密码';

  @override
  String get authPrivateKey => '私钥';

  @override
  String get privateKeyLabel => '私钥';

  @override
  String get privateKeyHint => '在此粘贴 OpenSSH / PEM 格式私钥内容';

  @override
  String get privateKeyRequired => '私钥内容不能为空';

  @override
  String get selectKeyFile => '选择密钥文件';

  @override
  String get passphraseLabel => '私钥密码（可选）';

  @override
  String get passphraseHint => '若私钥未加密请留空';

  @override
  String get showPassphrase => '显示私钥密码';

  @override
  String get hidePassphrase => '隐藏私钥密码';

  @override
  String failedToReadKeyFile(String error) {
    return '读取密钥文件失败: $error';
  }

  @override
  String get hostIp => '主机 / IP';

  @override
  String get hostRequired => '请输入主机地址';

  @override
  String get numbersOnly => '仅限数字';

  @override
  String get portRangeShort => '范围 1–65535';

  @override
  String get remoteRootPath => '远程根路径';

  @override
  String get ftpCleartextWarning =>
      'FTP 未加密：密码与文件均以明文传输。在不可信网络上请改用 SFTP 或 FTPS。';

  @override
  String get clearTempCacheQuestion => '清除临时缓存？';

  @override
  String clearTempCacheDesc(String size) {
    return '这将删除 $size 的临时缩略图、媒体和预览缓存。您保存的文件和连接配置不会受影响。';
  }

  @override
  String get tempCacheCleared => '临时缓存已清除';

  @override
  String couldNotClearCache(String error) {
    return '无法清除缓存：$error';
  }

  @override
  String get temporaryCache => '临时缓存';

  @override
  String get appInfoCopied => '应用信息已复制到剪贴板';

  @override
  String get supportedProtocolsCopied => '支持的协议列表已复制到剪贴板';

  @override
  String buildLabel(String time) {
    return '构建时间：$time';
  }

  @override
  String platformLabel(String platform) {
    return '平台：$platform';
  }

  @override
  String couldNotReadStorageStats(String error) {
    return '无法读取存储统计信息：$error';
  }

  @override
  String couldNotClearArchiveCache(String error) {
    return '无法清除压缩包缓存：$error';
  }

  @override
  String get archiveCacheCleared => '压缩包缓存已清除';

  @override
  String emptyTrashUtilityConfirm(int count) {
    return '确定永久删除全部 $count 个项目吗？此操作无法撤销。';
  }

  @override
  String couldNotEmptyTrashError(String error) {
    return '无法清空回收站：$error';
  }

  @override
  String get chooseSharedFolder => '选择共享文件夹';

  @override
  String portValidationError(String port) {
    return '端口必须是 1 到 65535 之间的数字（当前为“$port”）';
  }

  @override
  String failedToStartServer(String error) {
    return '启动服务器失败：$error';
  }

  @override
  String get couldNotStopLanServer => '无法停止局域网服务器';

  @override
  String get documentsDir => '文档';

  @override
  String errorFolderNotFound(String raw) {
    return '此文件夹已不存在，可能已被删除或重命名。\n($raw)';
  }

  @override
  String errorPermissionDenied(String raw) {
    return '权限被拒绝，请授予存储访问权限或选择其他文件夹。\n($raw)';
  }

  @override
  String errorSignInFailed(String raw) {
    return '登录失败，请检查用户名和密码。\n($raw)';
  }

  @override
  String errorServerTimeout(String raw) {
    return '服务器响应超时，请检查地址与网络连接。\n($raw)';
  }

  @override
  String errorCannotReachServer(String raw) {
    return '无法连接到服务器，请检查地址、端口与网络连接。\n($raw)';
  }

  @override
  String get playLabel => '播放';

  @override
  String get pauseLabel => '暂停';

  @override
  String get webdavCleartextWarning =>
      '此地址使用 http://，密码与文件将以明文传输。如服务器支持，请改用 https://。';

  @override
  String get selectThisFolder => '选择此文件夹';

  @override
  String get selectFolderAction => '选择';

  @override
  String get lanSharingDesc => '通过 Wi-Fi 共享本地文件夹，同一局域网内的任意浏览器均可访问或下载文件。';
}
