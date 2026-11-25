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
  String get bookmarks => '收藏夹';

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
  String get playWithMediaKit => '使用通用解码引擎 (MediaKit) 播放';

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
  String get localStorage => '本机文件';

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
  String get quickInbox => '专属空间';

  @override
  String get privateInboxSubtitle => '应用私有 · 其他应用不可访问';

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
  String get recent => '最近访问';

  @override
  String get recentDirs => '最近目录:';

  @override
  String get recycleBin => '回收站';

  @override
  String get remote => '远程连接';

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
  String pickerItemCounts(int folders, int files) {
    return '$folders 个文件夹，$files 个文件';
  }

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
  String get tasks => '任务队列';

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
  String get openAsText => '作为文本打开';

  @override
  String get openAsTextSubtitle => '使用内置文本编辑器打开';

  @override
  String get openWithOtherApp => '使用其他应用打开';

  @override
  String get openWithOtherAppSubtitle => '调用系统应用或选择第三方程序';

  @override
  String get openAsMedia => '作为音视频打开';

  @override
  String get openAsMediaSubtitle => '使用内置播放器播放';

  @override
  String get openAsImage => '作为图片打开';

  @override
  String get openAsImageSubtitle => '使用内置图片查看器打开';

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
    return '$count 个已删除项目';
  }

  @override
  String get utilitiesDefaultSubtitle => '隐私文件夹与缓存清理';

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

  @override
  String get receivedShareTitle => '接收到分享文件';

  @override
  String get receivedShareSingle => '接收到 1 个文件';

  @override
  String receivedShareCount(int count) {
    return '接收到 $count 个文件';
  }

  @override
  String get saveToLocal => '保存到本地';

  @override
  String get saveToLocalSubtitle => '选择本地文件夹并保存';

  @override
  String get saveToRemote => '保存到远程';

  @override
  String get saveToRemoteSubtitle => '上传至云存储、WebDAV 或 SFTP';

  @override
  String get openDirectly => '直接打开';

  @override
  String get openDirectlySubtitle => '在应用内直接查看或播放';

  @override
  String get selectRemoteStorage => '选择远程存储';

  @override
  String get noRemotesConfigured => '没有远程存储';

  @override
  String get noRemotesPrompt => '当前尚未配置任何远程连接，是否前往添加？';

  @override
  String get savingSharedFiles => '正在保存分享的文件...';

  @override
  String get savedSharedFilesSuccess => '分享文件保存成功';

  @override
  String get view => '查看';

  @override
  String get invalidFileNameError => '文件名不能包含 \"/\"、\"\\\" 或为 \".\"、\"..\"';

  @override
  String get batchRename => '批量重命名';

  @override
  String batchRenameTitle(int count) {
    return '批量重命名 ($count 项)';
  }

  @override
  String get batchRenameSubtitle => '自定义前缀、后缀、替换或序号递增';

  @override
  String get batchRenameModePrefixSuffix => '前后缀';

  @override
  String get batchRenameModeFindReplace => '查找替换';

  @override
  String get batchRenameModeNumbering => '序号递增';

  @override
  String get batchRenamePrefix => '前缀';

  @override
  String get batchRenamePrefixHint => '如: [2026] ';

  @override
  String get batchRenameSuffix => '后缀';

  @override
  String get batchRenameSuffixHint => '如: _final';

  @override
  String get batchRenameFindText => '查找文本';

  @override
  String get batchRenameReplaceWith => '替换为';

  @override
  String get batchRenameBaseName => '基准名称';

  @override
  String get batchRenameStartNumber => '起始编号';

  @override
  String get batchRenamePaddingDigits => '编号位数';

  @override
  String batchRenameDigitsOption(int digits, String example) {
    return '$digits 位 ($example)';
  }

  @override
  String get batchRenameKeepExtension => '保留文件扩展名';

  @override
  String get batchRenamePreview => '效果实时预览';

  @override
  String get batchRenameEmptyName => '(空名称)';

  @override
  String batchRenameProgress(int done, int total) {
    return '正在重命名 $done / $total 项...';
  }

  @override
  String batchRenameApply(int count) {
    return '应用重命名 ($count)';
  }

  @override
  String get batchRenameComplete => '批量重命名完成';

  @override
  String get batchRenameNoChanges => '没有需要修改的名称';

  @override
  String get batchRenameErrorEmpty => '存在空的目标文件名';

  @override
  String batchRenameErrorDuplicate(String name) {
    return '目标文件名重复：“$name”';
  }

  @override
  String batchRenameErrorExists(String name) {
    return '目标文件已存在：“$name”';
  }

  @override
  String selectedItemsDetailsTitle(int count) {
    return '已选 $count 项详情';
  }

  @override
  String get selectedFilesSizeLabel => '所选文件大小';

  @override
  String get currentDirectoryLabel => '当前目录';

  @override
  String get bookmarkSortModeTooltip => '排序方式';

  @override
  String get bookmarkSortCustom => '自定义拖拽排序';

  @override
  String get bookmarkSortNameAsc => '名称升序 (A-Z)';

  @override
  String get bookmarkSortNameDesc => '名称降序 (Z-A)';

  @override
  String get videoFitLabel => '画面比例';

  @override
  String get videoFitContain => '适应';

  @override
  String get videoFitCover => '铺满';

  @override
  String get videoFitFill => '拉伸';

  @override
  String videoFitChanged(String mode) {
    return '画面比例：$mode';
  }

  @override
  String audioTracksTitle(int count) {
    return '音频轨道 ($count)';
  }

  @override
  String get audioTrackMenu => '音轨选择';

  @override
  String get noAudioTracks => '无可选音频轨道';

  @override
  String get audioTrackDefault => '自动（默认）';

  @override
  String audioTrackItem(String id) {
    return '音频流 $id';
  }

  @override
  String subtitleTracksTitle(int count) {
    return '字幕选择 ($count)';
  }

  @override
  String get subtitleTrackMenu => '字幕选择';

  @override
  String get subtitlesOff => '关闭字幕';

  @override
  String subtitleTrackItem(String id) {
    return '字幕 $id';
  }

  @override
  String get sleepTimerTitle => '睡眠定时';

  @override
  String get sleepTimerOff => '关闭';

  @override
  String get sleepTimerOffToast => '已关闭睡眠定时';

  @override
  String sleepTimerMinutes(int minutes) {
    return '$minutes 分钟后停止';
  }

  @override
  String sleepTimerMinutesToast(int minutes) {
    return '$minutes 分钟后停止播放';
  }

  @override
  String get sleepTimerEndOfTrack => '播完当前后停止';

  @override
  String get sleepTimerEndOfTrackToast => '播完当前后将停止播放';

  @override
  String get sleepTimerEndOfTrackShort => '播完当前';

  @override
  String sleepTimerMenuRemaining(String remaining) {
    return '睡眠定时 ($remaining)';
  }

  @override
  String get readOnlyViewMode => '只读查看模式';

  @override
  String get privacyFolder => '隐私空间';

  @override
  String get privacyFolders => '隐私空间';

  @override
  String get privacyFoldersDesc => '创建、解锁、备份或导入相互独立的隐私文件夹';

  @override
  String get createPrivacyFolder => '创建隐私文件夹';

  @override
  String get openPrivacyFolder => '打开隐私文件夹';

  @override
  String get backupPrivacyFolder => '备份隐私文件夹';

  @override
  String get importPrivacyFolder => '导入隐私文件夹';

  @override
  String get privacyFolderName => '文件夹名称';

  @override
  String get privacyFolderNameHint => '请输入准确的文件夹名称';

  @override
  String get privacyFolderNotFound => '隐私文件夹不存在';

  @override
  String get privacyFolderAlreadyExists => '该名称的隐私文件夹已存在';

  @override
  String get credentialMethod => '加密凭证';

  @override
  String get credentialPassword => '单独密码（8–128位，支持特殊符号）';

  @override
  String get credentialSystem => '系统解锁（锁屏密码或刷脸/指纹）';

  @override
  String get credentialSystemUnavailable => '当前设备不支持系统解锁';

  @override
  String get encryptionAlgorithm => '加密方式';

  @override
  String get cipherNone => '不加密';

  @override
  String get cipherAes128Gcm => 'AES-128-GCM（默认，支持硬件加速）';

  @override
  String get cipherAes256Gcm => 'AES-256-GCM（支持硬件加速）';

  @override
  String get storageLocation => '存放位置';

  @override
  String get useDefaultLocation => '默认位置';

  @override
  String get changeLocation => '更改';

  @override
  String get privacyPasswordLabel => '密码（8–128位，支持特殊符号）';

  @override
  String get privacyConfirmPasswordLabel => '确认密码';

  @override
  String get passwordLengthError => '密码长度必须为 8 到 128 位';

  @override
  String get passwordMismatchError => '两次输入的密码不一致';

  @override
  String get privacyUnlockedLabel => '已解锁隐私文件夹 • 退出或后台10分钟自动隐藏';

  @override
  String get lockAndHide => '锁定并隐藏';

  @override
  String lockAllPrivacyFolders(int count) {
    return '全部锁定并隐藏 ($count)';
  }

  @override
  String vaultLockedNotice(String name) {
    return '隐私文件夹“$name”已锁定并隐藏';
  }

  @override
  String get nextStep => '下一步';

  @override
  String get unlockAction => '解锁';

  @override
  String unlockWithSystemPrompt(String name) {
    return '验证身份以解锁隐私文件夹“$name”';
  }

  @override
  String get setupSystemAuthPrompt => '验证身份以启用隐私文件夹系统解锁';

  @override
  String get wrongCredentialError => '密码或凭据错误';

  @override
  String cooldownRetryError(int seconds) {
    return '失败次数过多，请在 $seconds 秒后重试';
  }

  @override
  String get selectBackupSourceVault => '选择已解锁的文件夹或输入名称';

  @override
  String get backupPasswordRequiredNotice =>
      '该文件夹使用系统解锁，请设置 8–128 位备份密码以便导入到其他设备。';

  @override
  String get backupPasswordLabel => '备份密码（8–128位）';

  @override
  String get selectBackupDestFile => '选择备份导出文件夹';

  @override
  String backupExportSuccess(String path) {
    return '加密备份已导出至：$path';
  }

  @override
  String get selectBackupArchive => '选择 .fpmvault 备份文件';

  @override
  String backupArchiveSummary(String cipher, int count) {
    return '加密方式：$cipher • 数据对象：$count 个';
  }

  @override
  String get backupPasswordToVerify => '备份密码 / 原密码';

  @override
  String get localUnlockAfterImport => '导入后的解锁方式';

  @override
  String get newLocalPasswordOptional => '新本地密码（留空则沿用备份密码）';

  @override
  String importSuccessNotice(String name) {
    return '隐私文件夹“$name”已导入并解锁';
  }

  @override
  String get saveToPrivacyFolder => '保存到隐私文件夹';

  @override
  String get saveToPrivacyFolderSubtitle => '自动加密并存入已解锁的隐私文件夹';

  @override
  String get selectPrivacyFolder => '选择隐私文件夹';

  @override
  String get privacyFolderNoHistoryBookmark => '隐私文件夹内已禁用访问历史与公开书签';

  @override
  String get unlockedBadge => '已解锁';

  @override
  String importKeepOriginalName(String name) {
    return '将保持原文件夹名称：“$name”';
  }

  @override
  String get importWillKeepOriginalName => '将自动保持原文件夹名称；若名称已存在，再提示手动输入新名称。';

  @override
  String importNameExistsEnterNew(String name) {
    return '隐私文件夹“$name”已存在，请手动输入新的文件夹名称。';
  }

  @override
  String get importNewFolderNameLabel => '新隐私文件夹名称';

  @override
  String get importEnterFolderNamePrompt => '此备份未包含原文件夹名称，请手动输入文件夹名称。';

  @override
  String get renamePrivacyFolder => '重命名隐私文件夹';

  @override
  String privacyFolderRenamedNotice(String name) {
    return '隐私文件夹已重命名为“$name”';
  }

  @override
  String largeFilePagedNotice(String start, String end, String total) {
    return '大文件只读分页模式（$start – $end / $total）';
  }

  @override
  String get previousPage => '上一页';

  @override
  String get nextPage => '下一页';

  @override
  String get jumpToPosition => '跳转位置';

  @override
  String get deletePrivacyFolder => '删除隐私文件夹';

  @override
  String deletePrivacyFolderWarning(String name) {
    return '将永久删除隐私文件夹“$name”及其中的所有加密文件，并清除本机保存的解锁密钥。此操作无法撤销，如有需要请先导出备份。';
  }

  @override
  String deletePrivacyFolderConfirmLabel(String name) {
    return '请输入“$name”以确认删除';
  }

  @override
  String privacyFolderDeletedNotice(String name) {
    return '隐私文件夹“$name”已永久删除';
  }

  @override
  String get privacyMediaAudio => '私密音频';

  @override
  String get privacyMediaVideo => '私密视频';

  @override
  String get vaultAutoLockTitle => '后台自动锁定时间';

  @override
  String get vaultAutoLockImmediate => '切到后台立即锁定';

  @override
  String vaultAutoLockMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get vaultAutoLockNever => '从不自动锁定';

  @override
  String get vaultConfirmExternalOpenTitle => '外部分享与打开前确认';

  @override
  String get vaultConfirmExternalOpenDesc => '将隐私文件解密导出给其他应用前弹出提醒';

  @override
  String get vaultExternalOpenWarningTitle => '以明文形式交给其他应用？';

  @override
  String get vaultExternalOpenWarningBody =>
      '该文件将被临时解密并传递给隐私文件夹之外的应用。如需保密，请在使用后留意清理外部应用保留的副本。';

  @override
  String get dontAskAgain => '不再提示';

  @override
  String get continueAction => '继续';

  @override
  String get vaultVideoThumbnailsTitle => '隐私文件夹视频缩略图';

  @override
  String get vaultVideoThumbnailsDesc => '按需解码并加密缓存视频首帧缩略图（默认关闭以节省电量）';

  @override
  String get vaultSecuritySettings => '密码与解锁方式';

  @override
  String get vaultChangePasswordOption => '修改密码';

  @override
  String get vaultSwitchToSystemOption => '切换为系统解锁';

  @override
  String get vaultSwitchToPasswordOption => '切换为单独密码';

  @override
  String get vaultCurrentPasswordLabel => '当前密码';

  @override
  String get vaultNewPasswordLabel => '新密码（8–128位，支持特殊符号）';

  @override
  String get vaultOldBackupsPasswordNotice =>
      '此前已导出的 .fpmvault 备份文件仍需使用导出时的旧密码进行恢复。';

  @override
  String get vaultSwitchToSystemBackupNotice =>
      '切换为系统解锁后，请妥善保存 .fpmvault 备份；更换设备时系统密钥不会自动迁移。';

  @override
  String get vaultSecurityUpdatedNotice => '隐私文件夹安全设置已更新';

  @override
  String get vaultFolderInfo => '文件夹信息与空间整理';

  @override
  String get vaultStatsFiles => '文件数';

  @override
  String get vaultStatsFolders => '子文件夹';

  @override
  String get vaultStatsPlainSize => '内容大小';

  @override
  String get vaultStatsDiskUsage => '实际占用磁盘';

  @override
  String get vaultStatsOrphaned => '可清理孤儿数据';

  @override
  String vaultStatsOrphanDetail(int count, String size) {
    return '$count 项（$size）';
  }

  @override
  String get vaultCleanupOrphansAction => '清理孤儿数据释放空间';

  @override
  String vaultCleanupResultNotice(int count, String size) {
    return '已清理 $count 个孤儿文件，释放 $size';
  }

  @override
  String backupProgressLabel(String done, String total, int percent) {
    return '$done / $total ($percent%)';
  }

  @override
  String get backupCancelling => '正在取消…';

  @override
  String get backupCancelledNotice => '已取消备份操作';

  @override
  String get deleteVaultPermanentWarning => '将从隐私文件夹中永久删除所选项目，不会进入回收站且无法恢复。';

  @override
  String get showQrCode => '显示二维码';

  @override
  String get scanQrToConnect => '使用手机扫码即可在浏览器中打开';

  @override
  String get newTab => '新建标签页';

  @override
  String get closeTab => '关闭标签页';

  @override
  String get openInNewTab => '在新标签页中打开';

  @override
  String get copyToOtherPane => '复制到对侧面板';

  @override
  String get moveToOtherPane => '移动到对侧面板';

  @override
  String get pdfViewerTitle => 'PDF 阅读器';

  @override
  String pdfPageOf(int current, int total) {
    return '第 $current / $total 页';
  }

  @override
  String get pdfSearchHint => '在 PDF 中搜索文本…';

  @override
  String get pdfJumpToPage => '跳转到页码';

  @override
  String get pdfOutline => '目录';

  @override
  String get pdfNoOutline => '此文档无目录';

  @override
  String get pdfZeroDiskBadge => '内存渲染 · 隐私零落盘';

  @override
  String get scanLanDevices => '扫描局域网设备';

  @override
  String get scanningLan => '正在扫描局域网服务…';

  @override
  String get noLanDevicesFound => '未在局域网中发现 SMB / SFTP / WebDAV / FTP 设备';

  @override
  String get storageAnalyzer => '存储空间分析';

  @override
  String get storageAnalyzerSubtitle => '文件夹占用排行、类型分布与大文件清理';

  @override
  String get topFolders => '大文件夹排行';

  @override
  String get topFiles => '大文件排行';

  @override
  String get fileTypesBreakdown => '文件类型占比';

  @override
  String storageUsedOf(String used, String total, String free) {
    return '已用 $used / 共 $total（可用 $free）';
  }

  @override
  String get duplicateFinder => '重复文件清理';

  @override
  String get duplicateFinderSubtitle => '三阶段 SHA-256 快速查重与一键清理';

  @override
  String get keepNewest => '保留最新';

  @override
  String get keepOldest => '保留最早';

  @override
  String get keepShortestPath => '保留最短路径';

  @override
  String cleanSelectedDuplicates(int count) {
    return '清理已选 ($count)';
  }

  @override
  String wastedSpace(String size) {
    return '可释放空间：$size';
  }

  @override
  String get noDuplicatesFound => '未发现重复文件';

  @override
  String get categoryDocuments => '文档';

  @override
  String get categoryVideos => '视频';

  @override
  String get categoryAudio => '音频';

  @override
  String get categoryArchives => '压缩包';

  @override
  String get categoryDownloads => '下载';

  @override
  String get categoryApks => '安装包';

  @override
  String get globalSearchHint => '全局搜索本地文件、收藏夹与最近访问…';

  @override
  String get advancedSearch => '高级搜索';

  @override
  String get grepContentSearch => '内容全文搜索 (Grep)';

  @override
  String get matchContains => '包含';

  @override
  String get matchWildcard => '通配符 (* ?)';

  @override
  String get matchRegex => '正则表达式';

  @override
  String get minSizeMb => '最小大小 (MB)';

  @override
  String get maxSizeMb => '最大大小 (MB)';

  @override
  String get modifiedDaysAgo => '最近修改天数';

  @override
  String get pauseTask => '暂停';

  @override
  String get resumeTask => '恢复';

  @override
  String retryFailedItems(int count) {
    return '重试失败项 ($count)';
  }

  @override
  String get taskPaused => '已暂停';

  @override
  String get rateLimitLabel => '传输限速';

  @override
  String get rateLimitUnlimited => '不限速';

  @override
  String get encryptWithPassword => '设置密码加密 (AES-256)';

  @override
  String get archivePasswordRequired => '需要压缩包密码';

  @override
  String get archivePasswordHint => '输入解压密码';

  @override
  String get archiveWrongPassword => '压缩包密码错误';

  @override
  String get subtitles => '字幕';

  @override
  String get subtitleOff => '关闭字幕';

  @override
  String get loadExternalSubtitle => '从文件选取外挂字幕…';

  @override
  String subtitleAutoLoaded(String name) {
    return '已加载外挂字幕：$name';
  }

  @override
  String get pictureInPicture => '画中画';

  @override
  String get directorySync => '目录同步';

  @override
  String get directorySyncSubtitle => '本地与远程目录增量、镜像或双向同步';

  @override
  String get syncModeIncremental => '增量同步（仅复制新增和更新）';

  @override
  String get syncModeMirror => '单向镜像（完全一致，删除多余文件）';

  @override
  String get syncModeBidirectional => '双向同步';

  @override
  String get syncPreviewChanges => '预览差异';

  @override
  String get syncStart => '开始同步';

  @override
  String get syncNoChanges => '两个目录内容已完全一致';

  @override
  String get offlinePinned => '离线文件';

  @override
  String get offlinePinnedSubtitle => '远程文件的本地离线缓存与 LRU 管理';

  @override
  String get pinOffline => '离线保存';

  @override
  String get unpinOffline => '取消离线固定';

  @override
  String pinnedOfflineNotice(String name) {
    return '已将「$name」固定为离线可用';
  }

  @override
  String get checksumsTitle => '完整性校验 (MD5 / SHA-1 / SHA-256)';

  @override
  String get computeChecksums => '计算校验和';

  @override
  String get expectedHashHint => '粘贴预期哈希值以即时比对…';

  @override
  String get hashMatches => '校验和一致';

  @override
  String get hashMismatch => '校验和不一致';

  @override
  String get structuredView => '结构化视图';

  @override
  String get rawTextView => '原始文本';

  @override
  String get copyJsonPath => '复制路径';

  @override
  String get compareDiff => '对比差异';

  @override
  String get diffUnified => '统一视图';

  @override
  String get diffSideBySide => '并排对比';

  @override
  String get diffOnlyInLeft => '仅在左侧';

  @override
  String get diffOnlyInRight => '仅在右侧';

  @override
  String get diffModified => '存在差异';

  @override
  String get diffIdentical => '完全一致';

  @override
  String get unixPermissions => 'Unix 权限 (chmod)';

  @override
  String get permOwner => '所有者';

  @override
  String get permGroup => '用户组';

  @override
  String get permOther => '其他用户';

  @override
  String get applyPermissions => '应用权限';

  @override
  String permissionsUpdated(String mode) {
    return '权限已更新为 $mode';
  }

  @override
  String get lockVaultNow => '立即锁定';

  @override
  String get deleteOriginalAfterImport => '导入隐私保险箱后删除原文件';

  @override
  String get vaultExternalOpenNotice =>
      '使用外部应用打开隐私保险箱文件会导出临时明文副本。锁定隐私保险箱后会自动清理全部临时明文副本。';

  @override
  String get shareViaLan => '通过局域网共享';

  @override
  String get calculateDirSize => '点击计算';

  @override
  String activeTasksBanner(int count) {
    return '$count 个传输任务进行中';
  }

  @override
  String get jsonFormattedPreview => '格式化预览';

  @override
  String get jsonTreeView => '树形视图';

  @override
  String jsonIndentSpaces(int count) {
    return '$count 空格';
  }

  @override
  String get jsonSortKeys => '按键排序';

  @override
  String get jsonCopyFormatted => '复制格式化 JSON';

  @override
  String get jsonCopyMinified => '复制压缩 JSON';

  @override
  String get jsonCopiedFormatted => '已复制格式化 JSON';

  @override
  String get jsonCopiedMinified => '已复制压缩 JSON';

  @override
  String get jsonInvalidFormat => 'JSON 格式无效';

  @override
  String get jsonExpandAll => '全部展开';

  @override
  String get jsonCollapseAll => '全部折叠';

  @override
  String get jsonFormatInEditor => '格式化 JSON';

  @override
  String jsonLinesCount(int count) {
    return '$count 行';
  }

  @override
  String jsonMatchesCount(int current, int total) {
    return '$current/$total 处匹配';
  }

  @override
  String get vaultAlwaysVisibleTitle => '常驻显示';

  @override
  String get vaultAlwaysVisibleDesc =>
      '锁定后仍在首页、侧边栏和工具箱保留入口，打开时仍需授权验证并遵循自动锁定超时机制。';

  @override
  String get lockedBadge => '已锁定';

  @override
  String get vaultUnlockToOpen => '解锁并打开';

  @override
  String get vaultUnpinAlwaysVisible => '取消常驻显示';

  @override
  String vaultPinnedNotice(String name) {
    return '已将隐私文件夹“$name”设为常驻显示';
  }

  @override
  String vaultUnpinnedNotice(String name) {
    return '隐私文件夹“$name”已取消常驻，锁定后将隐藏';
  }

  @override
  String vaultLockedKeepVisibleNotice(String name) {
    return '隐私文件夹“$name”已锁定';
  }

  @override
  String get searchCategoryAll => '全部类型';

  @override
  String get searchCategoryCode => '代码';

  @override
  String get searchCategoryFolders => '文件夹';

  @override
  String get searchFilesAndFolders => '文件与文件夹';

  @override
  String get searchEnterQueryHint => '输入关键字搜索文件、文件夹、收藏夹、远程连接与历史';

  @override
  String get searchingFilesProgress => '正在搜索文件…';

  @override
  String get collapseSidebar => '收起侧边栏';

  @override
  String get expandSidebar => '展开侧边栏';

  @override
  String get categoryAllFilter => '全部';

  @override
  String categorySummary(int count, String size) {
    return '$count 项 · $size';
  }

  @override
  String categoryScanning(String category) {
    return '正在扫描$category…';
  }

  @override
  String categoryEmptyTitle(String category) {
    return '未找到$category';
  }

  @override
  String get categoryEmptySubtitle => '设备上的此类文件会自动汇总在这里。';

  @override
  String get locateInFolder => '在文件夹中查看';

  @override
  String get clearFilters => '清除筛选';

  @override
  String filterCategoryHint(String category) {
    return '在$category中筛选…';
  }

  @override
  String get historyRetentionTitle => '历史记录保留天数';

  @override
  String get historyRetentionDesc => '超过保留天数的访问记录将自动清理；设为 0 表示不保留历史记录。';

  @override
  String historyRetentionDaysLabel(int days) {
    return '保留 $days 天';
  }

  @override
  String historyRetentionDaysShort(int days) {
    return '$days 天';
  }

  @override
  String get historyRetentionDisabled => '不保留（0 天）';

  @override
  String get historyRetentionDisabledShort => '不保留';

  @override
  String get historyRetentionInputLabel => '保留天数（0 表示不保留）';

  @override
  String get historyRetentionInvalidInput => '请输入大于或等于 0 的整数';

  @override
  String historyRetentionUpdatedDays(int days) {
    return '历史记录保留天数已设为 $days 天';
  }

  @override
  String get historyRetentionUpdatedOff => '已关闭历史记录保留并清空现有记录';

  @override
  String get historyDisabledTitle => '已关闭历史记录保留';

  @override
  String get historyDisabledSubtitle => '当前保留天数为 0 天，浏览目录时不会保存历史记录。';

  @override
  String get historyRetentionChange => '设置保留天数';

  @override
  String errorSftpHostKey(String raw) {
    return 'SSH 主机密钥验证失败，请确认服务器指纹或重新保存 SFTP 连接。\n($raw)';
  }

  @override
  String errorObjectStorageConfig(String raw) {
    return '对象存储配置错误，请检查存储桶名称、Endpoint、Region 与访问密钥。\n($raw)';
  }

  @override
  String errorSmbConnection(String raw) {
    return 'SMB 共享连接失败，请核对共享名、账号密码以及 SMB 端口（445）。\n($raw)';
  }

  @override
  String errorArchivePassword(String raw) {
    return '压缩包密码缺失或不正确，请重新输入后再试。\n($raw)';
  }

  @override
  String errorDiskFull(String raw) {
    return '目标存储卷剩余空间不足，请清理空间后重试。\n($raw)';
  }

  @override
  String get recoveryGrantPermission => '前往授权';

  @override
  String get recoveryEditConnection => '修改连接配置';

  @override
  String get recoveryEnterPassword => '输入解压密码';

  @override
  String get recoveryFreeUpSpace => '清理存储空间';

  @override
  String get navDomainStorage => '文件';

  @override
  String get navDomainDiscover => '收藏';

  @override
  String get navDomainTools => '传输';

  @override
  String get autoSyncIntervalLabel => '定时自动同步';

  @override
  String get autoSyncOff => '仅手动';

  @override
  String autoSyncEveryMinutes(int minutes) {
    return '每 $minutes 分钟';
  }

  @override
  String get offlineAutoSyncTitle => '恢复前台时自动检查与回写';

  @override
  String get providerCrypt => '零信任加密云保险箱 (Crypt)';

  @override
  String get cryptBackingRootLabel => '底层存储位置';

  @override
  String get cryptBackingRootHint => 'remote://my_s3 或本地路径';

  @override
  String get cryptBasePrefixLabel => '加密根目录前缀';

  @override
  String get cryptPasswordLabel => '主加密密码';

  @override
  String get cryptPasswordRequired => '请输入加密密码';

  @override
  String get cryptSaltOptionalLabel => '可选盐值 / 附加密钥';

  @override
  String get cryptSaltHint => '用于增强密钥派生的可选盐值';

  @override
  String get cryptInfoBanner =>
      '文件名与 64 KiB 文件分块均在本地完成端到端 AES-256-GCM 加密，再写入底层云存储或目录。';

  @override
  String get lanWebdavShareTitle => '局域网 WebDAV 共享';

  @override
  String get lanWebdavShareSubtitle => '让电脑访达 / 资源管理器或电视盒子（Infuse / Kodi）直接挂载';

  @override
  String get shareViaLanWebdav => '通过局域网 WebDAV 共享';

  @override
  String get webdavUsernameOptional => '用户名（可选）';

  @override
  String get webdavUrlCopied => 'WebDAV 地址已复制到剪贴板';

  @override
  String webdavServerRunning(String url) {
    return 'WebDAV 服务运行中：$url';
  }

  @override
  String get lanPeerTransferTitle => '局域网直传';

  @override
  String get lanPeerTransferSubtitle => '发现附近 FP File Manager 设备，一键直传文件或剪贴板文本';

  @override
  String get peerReceiveMode => '接收模式（可被发现）';

  @override
  String get peerDeviceName => '本机设备名称';

  @override
  String get peerScanDevices => '扫描局域网设备';

  @override
  String get peerScanning => '正在扫描附近设备…';

  @override
  String get peerNoDevicesFound => '未在局域网发现其他开启接收模式的设备';

  @override
  String get peerSendFiles => '发送文件';

  @override
  String get peerSendClipboard => '发送剪贴板文本';

  @override
  String get peerManualAddressHint => 'http://<局域网IP>:端口';

  @override
  String peerIncomingOfferTitle(String sender) {
    return '来自 $sender 的传输请求';
  }

  @override
  String get peerAccept => '接收';

  @override
  String get peerReject => '拒绝';

  @override
  String peerSentSuccess(int count) {
    return '已成功发送 $count 个文件';
  }

  @override
  String get peerOfferSent => '文本已发送到对方设备';

  @override
  String get sendToLanDevice => '发送到局域网设备';

  @override
  String fastIndexReady(int count) {
    return '快速索引：$count 项';
  }

  @override
  String get fastIndexNotBuilt => '当前目录尚未建立快速索引';

  @override
  String get fastIndexBuild => '建立索引';

  @override
  String get fastIndexRebuild => '重建索引';

  @override
  String get fastIndexBuilding => '正在索引…';

  @override
  String get fastIndexClear => '清除索引';

  @override
  String get fastIndexCleared => '快速索引已清除';

  @override
  String get readingModeSingle => '单页模式';

  @override
  String get readingModeWebtoon => '条漫连读';

  @override
  String get readingModeDouble => '双页模式';

  @override
  String get stripExifAction => '清除 EXIF 并另存副本';

  @override
  String stripExifDone(String path) {
    return '已生成无隐私元数据副本：$path';
  }

  @override
  String get stripExifBatchAction => '清除 EXIF';

  @override
  String stripExifBatchDone(int count) {
    return '已为 $count 张照片保存无 EXIF 副本';
  }

  @override
  String get openInTerminal => '在此处打开终端';

  @override
  String get openInEditor => '在外部编辑器打开';

  @override
  String get copyFullPath => '复制绝对路径';

  @override
  String get copyVfsPath => '复制 VFS 路径';

  @override
  String get photoBackupTitle => '相册备份';

  @override
  String get photoBackupSubtitle => '将新增照片/视频增量备份至 NAS、S3、WebDAV 或隐私保险箱';

  @override
  String get photoBackupEnable => '启用自动增量备份';

  @override
  String get photoBackupWifiOnly => '仅在 Wi-Fi 下备份';

  @override
  String get photoBackupTargetLabel => '备份目标位置';

  @override
  String get photoBackupSelectTarget => '选择备份目标';

  @override
  String get photoBackupNow => '立即备份';

  @override
  String get photoBackupRunning => '正在增量备份新增照片…';

  @override
  String photoBackupStats(int count) {
    return '已累计备份 $count 项照片/视频';
  }

  @override
  String get photoBackupNoTarget => '请先选择备份目标目录';

  @override
  String photoBackupCompleted(int count) {
    return '本次成功备份 $count 项新增媒体';
  }

  @override
  String get pinToHomeScreen => '固定到手机桌面';

  @override
  String pinToHomeScreenSuccess(String name) {
    return '已将快捷方式“$name”添加到桌面';
  }

  @override
  String get pinToHomeScreenUnsupported => '当前平台不支持桌面快捷方式';

  @override
  String get storagePools => '存储池';

  @override
  String get storagePoolsSubtitle => '聚合多个 SFTP / S3 / WebDAV 节点为统一 2 副本空间';

  @override
  String get createStoragePool => '新建存储池';

  @override
  String get editStoragePool => '编辑存储池';

  @override
  String get noStoragePools => '暂无分布式存储池';

  @override
  String get noStoragePoolsDesc =>
      '可将多个 SFTP、S3 或 WebDAV 节点聚合成支持跨故障域 2 副本、固定分块与端到端加密的虚拟文件系统。';

  @override
  String get poolName => '存储池名称';

  @override
  String get poolNameHint => '例如：影音聚合存储池';

  @override
  String get poolChunkSize => '分块大小';

  @override
  String get poolEncryptEnable => '开启客户端透明 AES-GCM 加密';

  @override
  String get poolEncryptSubtitle => '上传前在本地加密所有分块内容与元数据快照';

  @override
  String get poolPassphrase => '加密口令';

  @override
  String get poolPassphraseHint => '编辑时留空则保留原口令';

  @override
  String get poolSelectNodes => '选择成员节点';

  @override
  String get poolNeedRemotesFirst => '请先在“远程连接”中配置 SFTP、S3 或 WebDAV 节点。';

  @override
  String get poolFailureDomain => '故障域标签';

  @override
  String get poolQuotaGb => '配额 (GB)';

  @override
  String get poolPrefix => '远端目录前缀';

  @override
  String get poolRoleRw => '读写 (RW)';

  @override
  String get poolRoleRo => '只读 (RO)';

  @override
  String get poolRoleDraining => '迁移下线中';

  @override
  String get poolRoleOffline => '已离线';

  @override
  String get poolMetaBackup => '元数据备份节点';

  @override
  String get poolBrowse => '浏览文件';

  @override
  String get poolProbeHealth => '探测健康度';

  @override
  String get poolSyncMeta => '同步元数据';

  @override
  String get poolHeal => '一键修复副本';

  @override
  String get poolGc => '清理孤儿块';

  @override
  String get poolDrainNode => '下线迁移';

  @override
  String get poolLogicalCapacity => '有效逻辑容量';

  @override
  String get poolPhysicalCapacity => '物理总配额';

  @override
  String poolDegradedWarning(int count) {
    return '检测到 $count 个分块不足 2 副本，建议执行“一键修复副本”';
  }

  @override
  String get poolEncryptedBadge => '已加密';

  @override
  String get poolPlaintextBadge => '明文模式';

  @override
  String poolMetaVersionBadge(int version) {
    return '元数据 v$version';
  }

  @override
  String poolDeleteConfirm(String name) {
    return '确定移除存储池“$name”？默认仅删除本地配置，不会清理远端已写入的数据块。';
  }

  @override
  String poolDrainConfirm(String node) {
    return '确定将节点“$node”上的全部分块迁移至其他健康节点并下线？';
  }

  @override
  String poolSyncDone(String action, int version, int uploaded, int conflicts) {
    return '元数据同步：$action（v$version，备份 $uploaded 节点，冲突 $conflicts）';
  }

  @override
  String poolNodesCount(int count) {
    return '$count 个节点';
  }

  @override
  String get lanTransferAndShareTitle => '局域网传输';

  @override
  String get lanTransferAndShareSubtitle => '局域网点对点直传、WebDAV 挂载与浏览器上传下载';

  @override
  String get lanWebdavBrowserHint =>
      '支持浏览器直接打开上传/下载文件，也支持访达、资源管理器、Infuse、Kodi 挂载。';

  @override
  String get lanWebdavReadOnlyHint => '关闭只读模式后可允许浏览器上传、新建文件夹和修改文件';

  @override
  String get photoBackupSourceLabel => '要备份的目录 / 相册';

  @override
  String get photoBackupSelectSource => '添加备份目录';

  @override
  String get photoBackupSelectAlbums => '选择相册';

  @override
  String get photoBackupDefaultSources => '默认相册目录';

  @override
  String get photoBackupAllAlbums => '全部照片与视频';

  @override
  String photoBackupSelectedAlbumsCount(int count) {
    return '已选 $count 个相册';
  }

  @override
  String get photoBackupResetSources => '恢复默认';

  @override
  String get syncExcludeRulesTitle => '排除规则';

  @override
  String get syncExcludeExtensionsLabel => '排除的文件类型（扩展名）';

  @override
  String get syncExcludeExtensionsHint => '如 tmp, log, bak（逗号分隔）';

  @override
  String get syncExcludeNamesLabel => '排除的文件名称';

  @override
  String get syncExcludeNamesHint => '如 .DS_Store, Thumbs.db, ~\$*';

  @override
  String get syncExcludeDirsLabel => '排除的文件夹';

  @override
  String get syncExcludeDirsHint => '如 node_modules, .git, build/cache';

  @override
  String get syncExcludePresets => '常用预设';

  @override
  String get syncPickExcludeDir => '选择文件夹';

  @override
  String syncExcludedCount(int count) {
    return '已排除 $count 项';
  }

  @override
  String get syncAddRule => '添加';

  @override
  String get peerManualAddressLabel => '目标设备地址（可手动输入）';

  @override
  String peerManualAddressExample(String hostPlaceholder) {
    return '例如 http://$hostPlaceholder:端口';
  }

  @override
  String get emptyLabel => '空';

  @override
  String itemCountConnections(int count) {
    return '$count 个连接';
  }

  @override
  String itemCountPools(int count) {
    return '$count 个存储池';
  }

  @override
  String itemCountBookmarks(int count) {
    return '$count 个书签';
  }

  @override
  String itemCountLocations(int count) {
    return '$count 个位置';
  }

  @override
  String activeTasksRunningCount(int count) {
    return '$count 个任务运行中';
  }

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String timeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String deletedRelativeTime(String time) {
    return '删除于 $time';
  }

  @override
  String get stopSharing => '停止共享';

  @override
  String get manageRemotes => '管理远程连接';

  @override
  String get manageStoragePools => '管理存储池';

  @override
  String get backupRestoreConfigTitle => '备份与恢复配置';

  @override
  String get backupRestoreConfigSubtitle =>
      '导出或导入远程连接、存储池、收藏夹和设置（支持加密 .fmbak / .json）';

  @override
  String get exportAction => '导出';

  @override
  String get exportMigrationTitle => '导出设备迁移备份';

  @override
  String get exportMigrationPasswordLabel => '加密密码（建议设置）';

  @override
  String get exportMigrationPasswordHint => '留空将导出不含凭据的纯文本 JSON';

  @override
  String get exportIncludeCredentials => '包含密码与私钥（需设置加密密码）';

  @override
  String get copyJsonAction => '复制 JSON';

  @override
  String get copyEncryptedAction => '复制加密备份';

  @override
  String get saveBackupFileAction => '保存 .fmbak';

  @override
  String get saveJsonFileAction => '保存 .json';

  @override
  String get importMigrationTitle => '导入设备配置';

  @override
  String get chooseBackupFileAction => '选择 .fmbak 或 .json 文件';

  @override
  String get importPasteHint => '或直接粘贴 JSON / .fmbak 内容…';

  @override
  String get importPasswordLabel => '解密密码（如已加密）';

  @override
  String get importPasswordHint => '含凭据的 .fmbak 备份需要填写';

  @override
  String get importPasswordRequiredError => '请输入此加密 .fmbak 备份文件的解密密码。';

  @override
  String exportSavedNotice(String path) {
    return '备份已保存到 $path';
  }

  @override
  String get exportCopiedNotice => '备份内容已复制到剪贴板';

  @override
  String importSummaryNotice(int remotes, int bookmarks, int prefs) {
    return '已导入 $remotes 个远程、$bookmarks 个书签、$prefs 项偏好设置';
  }

  @override
  String get unencryptedCredentialsBanner => '警告：系统安全钥匙串不可用，远程密码将以明文保存。';

  @override
  String get remoteTestTimedOut => '连接测试超时（8 秒）';

  @override
  String remoteImportFailedSummary(int count, String details) {
    return '；$count 项失败：$details';
  }

  @override
  String remoteBucketLabel(String bucket) {
    return '存储桶: $bucket';
  }

  @override
  String keyringUnavailableBanner(String detail) {
    return '系统钥匙串不可用（$detail），凭据可能无法安全持久化。';
  }

  @override
  String deleteRemotePoolWarning(String pools) {
    return '警告：以下存储池正在使用此远程连接：$pools。删除会导致存储池降级或不可用。';
  }

  @override
  String get poolConfirmGcTitle => '执行垃圾回收？';

  @override
  String poolConfirmGcBody(String name) {
    return '确认立即清理存储池“$name”中未引用或已删除的数据块？清理后无法恢复。';
  }

  @override
  String get poolReplicationFactorLabel => '副本数（冗余份数）';

  @override
  String poolMinNodesError(int count) {
    return '$count 副本模式至少需要选择 $count 个存储节点。';
  }

  @override
  String get poolInvalidQuotaError => '请输入有效的节点配额（大于 0 GB）。';

  @override
  String get poolPassphraseConfirmLabel => '确认加密口令';

  @override
  String get poolPassphraseMismatchError => '两次输入的加密口令不一致。';

  @override
  String get poolEditLockedHint => '分块大小与加密开关在创建后不可修改。';

  @override
  String poolNodeHealthSummary(int pct, int ms, String state) {
    return '健康度 $pct% · $ms ms · $state';
  }

  @override
  String get poolRoleShortRw => '读写';

  @override
  String get poolRoleShortRo => '只读';

  @override
  String get poolRoleShortDraining => '排空中';

  @override
  String get poolRoleShortOffline => '离线';

  @override
  String get poolCircuitClosed => '正常';

  @override
  String get poolCircuitOpen => '熔断';

  @override
  String get poolCircuitHalfOpen => '半开探测';

  @override
  String get cryptChooseBackingRemote => '选择已有远程或本地目录';

  @override
  String get cryptLocalFolderOption => '选择本地文件夹…';

  @override
  String fileConflictBody(String name) {
    return '当前目录已存在“$name”，请选择处理方式：';
  }

  @override
  String filesConflictBody(int count) {
    return '当前目录已存在 $count 个同名项目，请选择处理方式：';
  }

  @override
  String get offlineOverwriteConfirmTitle => '覆盖远程更改？';

  @override
  String offlineOverwriteConfirmBody(String name) {
    return '远程“$name”也有新版本，确定要用本地离线修改覆盖远程文件吗？';
  }

  @override
  String get offlineDiscardLocalConfirmTitle => '丢弃本地离线修改？';

  @override
  String offlineDiscardLocalConfirmBody(String name) {
    return '“$name”包含未同步的本地修改或冲突，继续操作将覆盖或删除这些更改。';
  }

  @override
  String offlineUploadedNotice(String name) {
    return '已将“$name”上传到远程。';
  }

  @override
  String get offlineCheckUpdatesTooltip => '检查更新';

  @override
  String get offlineSyncAllTooltip => '全部同步';

  @override
  String get offlineLruCapTooltip => '缓存上限';

  @override
  String offlineLruCapOption(String size) {
    return '缓存上限：$size';
  }

  @override
  String get offlineUploadLocalTooltip => '上传本地修改到远程';

  @override
  String offlineBannerSummary(int count, String used, String cap) {
    return '已固定 $count 项 · $used / $cap';
  }

  @override
  String get offlineStatusLocalModified => '本地已修改';

  @override
  String get offlineStatusRemoteNewer => '远程有更新';

  @override
  String get offlineStatusConflict => '存在冲突';

  @override
  String get offlineStatusSynced => '已同步';

  @override
  String get offlineStatusMissingLocal => '本地缺失';

  @override
  String get offlineStatusOffline => '离线';

  @override
  String get browserSelectItemsFirst => '请先选择至少一个项目。';

  @override
  String clipboardReadOnlyHint(int count) {
    return '剪贴板已有 $count 项（当前目录只读）';
  }

  @override
  String get peerTabDirectTransfer => '局域网直传';

  @override
  String get peerTabWebdavShare => 'WebDAV / 网页共享';

  @override
  String peerPendingItemsToSend(int count) {
    return '已准备发送 $count 个项目';
  }

  @override
  String get peerReceiveFolderMustBeLocal => '接收保存目录必须位于本地存储。';

  @override
  String get peerOpenReceivedFolder => '打开目录';

  @override
  String get peerCopyReceivedText => '复制文本';

  @override
  String get peerTextCopied => '接收到的文本已复制到剪贴板。';

  @override
  String get peerWaitingForAccept => '正在发送，等待对方确认接收…';

  @override
  String get peerOfferStatusAccepted => '已同意';

  @override
  String get peerOfferStatusCompleted => '已完成';

  @override
  String get peerOfferStatusRejected => '已拒绝';

  @override
  String get peerOfferStatusReceiving => '接收中';

  @override
  String get photoBackupScanning => '正在扫描照片与目录…';

  @override
  String get photoBackupCancel => '取消';

  @override
  String photoBackupCancelledNotice(int count) {
    return '已取消相册备份（已上传 $count 张）。';
  }

  @override
  String get photoBackupResetHistory => '重置备份记录';

  @override
  String get photoBackupResetHistoryConfirm => '清空本地已备份记录？清空后下次备份将重新校验并上传照片。';

  @override
  String photoBackupLastRun(String time) {
    return '上次备份：$time';
  }

  @override
  String photoBackupProgressCount(int uploaded, int total) {
    return '已上传 $uploaded / $total';
  }

  @override
  String get photoBackupOpenDestination => '打开备份目录';

  @override
  String get photoBackupVaultLocked => '目标隐私文件夹尚未解锁';

  @override
  String get photoBackupPermissionDeniedTitle => '需要相册访问权限';

  @override
  String get photoBackupPermissionDeniedBody => '请在系统设置中允许访问照片图库，以选择相册或执行备份。';

  @override
  String get photoBackupOpenSettings => '前往设置';

  @override
  String get syncSaveProfileTitle => '保存同步配置';

  @override
  String get syncProfileNameLabel => '配置名称';

  @override
  String get syncSourceLabel => '源目录';

  @override
  String get syncDestinationLabel => '目标目录';

  @override
  String get syncScanLimitReached => '目录扫描达到上限，预览结果可能不完整。';

  @override
  String syncSummaryChanges(int changes, int unchanged) {
    return '$changes 项变更 · $unchanged 项一致';
  }

  @override
  String get syncConfirmMirrorDeleteTitle => '确认镜像删除';

  @override
  String syncConfirmMirrorDeleteBody(int count) {
    return '本次同步将在目标端删除 $count 个多余的文件或文件夹，确认继续？';
  }

  @override
  String syncConfirmDeleteProfileBody(String name) {
    return '确定删除已保存的同步配置“$name”？';
  }

  @override
  String get syncSwapFoldersTooltip => '交换源目录与目标目录';

  @override
  String get syncSelectAll => '全选';

  @override
  String get syncDeselectAll => '取消全选';

  @override
  String get syncActionCopy => '复制';

  @override
  String get syncActionUpdate => '更新';

  @override
  String get syncActionDelete => '删除';

  @override
  String get syncActionPullUpdate => '回拉更新';

  @override
  String get syncEditConfig => '调整目录';

  @override
  String syncAutoSyncFailed(String error) {
    return '上次自动同步失败：$error';
  }

  @override
  String get taskStatusPaused => '已暂停';

  @override
  String taskRateLimitActive(String limit) {
    return '限速：$limit';
  }

  @override
  String taskFailedItemsTitle(int count) {
    return '失败详情（$count 项）';
  }

  @override
  String get taskRetryStarted => '已重新提交失败项进行重试。';

  @override
  String analyzerStatsSummary(int files, int folders) {
    return '$files 个文件 · $folders 个文件夹';
  }

  @override
  String get analyzerScanCancelled => '扫描已取消（仅展示部分统计结果）。';

  @override
  String get analyzerScanTruncated => '扫描达到上限，更深层目录未计入统计。';

  @override
  String get analyzerRescan => '重新扫描';

  @override
  String duplicatesGroupCount(int count) {
    return '$count 组重复';
  }

  @override
  String duplicatesCopiesCount(int count) {
    return '（$count 份）';
  }

  @override
  String duplicatesEachSize(String size) {
    return '每份 $size';
  }

  @override
  String duplicatesDeleteFailed(int count) {
    return '有 $count 项删除失败';
  }

  @override
  String duplicatesAllCopiesWarning(int count) {
    return '警告：有 $count 组重复文件选中了全部副本，删除后将不留备份！';
  }

  @override
  String get duplicatesClearSelection => '清空选择';

  @override
  String get duplicatesScanCancelled => '重复文件扫描已取消。';

  @override
  String duplicatesTrashConfirmBody(int count) {
    return '确认将选中的 $count 个重复项目移入回收站？';
  }

  @override
  String categoryTruncatedBanner(int count) {
    return '仅展示前 $count 个匹配文件（已达上限）。';
  }

  @override
  String get galleryLocateInFolder => '在文件夹中定位';

  @override
  String get galleryUnsupportedFormatForPick => '当前选择的文件格式不符合外部请求要求。';

  @override
  String galleryExifSkippedNonJpeg(int count) {
    return '已跳过 $count 张非 JPEG 图片（去 EXIF 仅支持 JPEG）。';
  }

  @override
  String searchFiltersLabel(int count) {
    return '筛选条件 ($count)';
  }

  @override
  String get searchAllTypes => '全部类型';

  @override
  String get pdfEncryptedError => '该 PDF 已加密或受密码保护，无法直接渲染。';

  @override
  String pdfPageTextTitle(int page) {
    return '第 $page 页文本';
  }

  @override
  String get pdfPageTextCopied => '当前页文本已复制到剪贴板。';

  @override
  String get pdfNoSelectableText => '该页未检测到可选文本（可能是扫描图片）。';

  @override
  String get pdfSelectCopyPageText => '选择 / 复制本页文本';

  @override
  String pdfRenderPageFailed(int page) {
    return '第 $page 页渲染失败。';
  }

  @override
  String get structuredEmptyValue => '（空）';

  @override
  String structuredCsvTruncated(int shown, int total) {
    return '当前展示前 $shown 行（共 $total 行）。';
  }

  @override
  String get copyXPath => '复制 XPath';

  @override
  String get subtitleLoadFailed => '不支持或无法读取该字幕文件。';

  @override
  String get diffTruncatedNotice => '目录对比已达到条目上限，部分深层文件未显示。';

  @override
  String get diffSyncFoldersAction => '去同步目录';

  @override
  String get vaultHtmlBrowserWarning => '为遵守隐私空间零落盘原则，禁止在外部浏览器中打开解密后的 HTML。';

  @override
  String get poolStorageDirectory => '存储目录';

  @override
  String get poolPickDirectory => '选择目录';

  @override
  String poolReplicationBadge(int count) {
    return '$count 副本';
  }

  @override
  String get poolSetReplicationTitle => '设置副本数';

  @override
  String get poolSetReplicationHint => '新写入文件立即按此副本数存储；已有文件可通过“修复”补齐副本。';

  @override
  String poolNodeRealFreeWithTotal(String free, String total) {
    return '剩余 $free / 共 $total';
  }

  @override
  String poolNodeRealFreeOnly(String free) {
    return '剩余 $free';
  }

  @override
  String get poolNodeSpaceUnavailable => '剩余空间未知';

  @override
  String get poolNodeSpaceProbing => '正在探测剩余空间…';

  @override
  String poolNodePoolUsed(String used) {
    return '存储池已用: $used';
  }

  @override
  String poolNodeDirectoryLabel(String dir) {
    return '目录: $dir';
  }

  @override
  String get remoteBatchExportAction => '批量加密导出';

  @override
  String get remoteBatchImportAction => '批量加密导入';

  @override
  String get remoteBatchExportTitle => '批量导出远程连接';

  @override
  String get remoteBatchExportSubtitle =>
      '连接配置与凭据将使用您设置的密码通过 AES-256-GCM 加密保护。';

  @override
  String remoteBatchSelectCount(int selected, int total) {
    return '已选择 $selected / $total 个连接';
  }

  @override
  String get remoteBatchSelectAll => '全选';

  @override
  String get remoteBatchDeselectAll => '取消全选';

  @override
  String get remoteBatchUnreadableSkipped => '凭据无法读取（不可导出）';

  @override
  String get remoteBatchNoReadableToExport => '当前没有可读取的远程连接可供导出。';

  @override
  String get remoteBatchExportPasswordLabel => '加密密码（必填）';

  @override
  String remoteBatchExportPasswordHint(int min) {
    return '至少 $min 位字符';
  }

  @override
  String get remoteBatchExportPasswordConfirmLabel => '确认加密密码';

  @override
  String get remoteBatchPasswordRequiredNote => '请牢记此密码，批量导入远程连接时必须输入同一密码解密。';

  @override
  String remoteBatchPasswordTooShort(int min) {
    return '加密密码至少需要 $min 位字符。';
  }

  @override
  String get remoteBatchPasswordMismatch => '两次输入的密码不一致。';

  @override
  String get remoteBatchSaveFileAction => '保存加密文件';

  @override
  String get remoteBatchShareFileAction => '导出 / 分享文件';

  @override
  String remoteBatchExportSavedNotice(int count, String path) {
    return '已加密导出 $count 个连接到 $path';
  }

  @override
  String remoteBatchExportSharedNotice(int count) {
    return '已生成 $count 个连接的加密备份文件。';
  }

  @override
  String remoteBatchExportCopiedNotice(int count) {
    return '已复制 $count 个连接的加密备份到剪贴板。';
  }

  @override
  String get remoteBatchImportTitle => '批量导入远程连接';

  @override
  String get remoteBatchChooseFile => '选择备份文件';

  @override
  String get remoteBatchPasteClipboard => '粘贴剪贴板';

  @override
  String get remoteBatchClipboardDetected => '已检测到剪贴板中的加密备份。';

  @override
  String get remoteBatchClipboardEmpty => '剪贴板为空。';

  @override
  String remoteBatchSelectedFileLabel(String name) {
    return '已选文件：$name';
  }

  @override
  String get remoteBatchPasteFieldHint => '或直接粘贴加密的 .fmremotes / .fmbak 备份内容…';

  @override
  String get remoteBatchImportPasswordLabel => '解密密码（必填）';

  @override
  String get remoteBatchImportPasswordHint => '请输入导出时设置的密码';

  @override
  String get remoteBatchDecryptAction => '解密并预览';

  @override
  String remoteBatchPreviewSummary(int count) {
    return '解密成功，共 $count 个连接';
  }

  @override
  String get remoteBatchConflictSectionLabel => '遇到同名 ID 已有连接时：';

  @override
  String get remoteBatchConflictSkip => '跳过已有';

  @override
  String get remoteBatchConflictOverwrite => '覆盖已有';

  @override
  String get remoteBatchConflictKeepBoth => '保留两者';

  @override
  String get remoteBatchBadgeNew => '新增';

  @override
  String get remoteBatchBadgeExists => '已存在';

  @override
  String get remoteBatchAllSkippedHint => '所选连接均已存在且将被跳过，可切换为“覆盖已有”或“保留两者”。';

  @override
  String remoteBatchImportConfirm(int count) {
    return '导入 ($count)';
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
    return '已导入 $imported 个连接（新增 $added、更新 $overwritten、副本 $duplicated、跳过 $skipped）$detail';
  }

  @override
  String get remoteBatchErrorNotEncrypted => '不支持明文数据，请选择使用密码加密导出的备份文件或内容。';

  @override
  String get remoteBatchErrorInvalidFormat => '备份文件格式无效，无法解析。';

  @override
  String get remoteBatchErrorWrongPassword => '密码错误或备份文件已损坏，请检查密码后重试。';

  @override
  String get remoteBatchErrorEmptyBundle => '该加密备份中不包含有效的远程连接。';

  @override
  String get remoteBatchErrorFileTooLarge => '所选文件过大，不是有效的远程连接备份文件。';

  @override
  String get remoteBatchBackStep => '返回上一步';

  @override
  String get poolNodeWeightLabel => '权重';

  @override
  String poolNodeWeightBadge(int weight) {
    return '权重 $weight';
  }

  @override
  String get poolSetNodeWeightTitle => '设置节点权重';

  @override
  String get poolSetNodeWeightHint => '权重越高（1–1000），在剩余空间与健康度相近时优先写入更多数据。';

  @override
  String get poolInvalidWeightError => '节点权重必须是 1 到 1000 之间的整数。';

  @override
  String poolNodeUsedAndQuota(String used, String quota) {
    return '已用 $used / 配额 $quota';
  }

  @override
  String poolNodeSystemFreeWithTotal(String free, String total) {
    return '系统剩余 $free / 共 $total';
  }

  @override
  String poolNodeSystemFreeOnly(String free) {
    return '系统剩余 $free';
  }

  @override
  String get poolNodeSystemSpaceUnsupported => '系统剩余：当前协议不支持查询';

  @override
  String get poolNodeSystemSpaceUnavailable => '系统剩余：暂未获取';

  @override
  String get poolNodeSystemSpaceProbing => '系统剩余：正在探测…';

  @override
  String get poolDeleteRemoteDataOption => '同时删除远程节点上的存储池数据';

  @override
  String get poolDeleteRemoteDataWarning =>
      '将永久删除各节点存储目录下的 blobs/ 与 meta/ 数据，删除后无法恢复。';

  @override
  String get poolDeleteNodeRemoteDataOption => '同时删除该节点的远程数据';

  @override
  String get poolDeleteNodeRemoteDataWarning => '将永久删除存储在该节点上的分块数据与元数据备份。';

  @override
  String get poolOfflineNode => '直接下线';

  @override
  String get poolOnlineNode => '重新上线';

  @override
  String get poolRemoveNode => '移除节点';

  @override
  String poolOfflineConfirm(String node) {
    return '确定立即将节点“$node”下线？该节点上的分块在重新上线或修复前将不可读写。';
  }

  @override
  String poolRemoveNodeConfirm(String node) {
    return '确定将节点“$node”从当前存储池中移除？';
  }

  @override
  String poolRemoteCleanupDone(int deleted) {
    return '已删除 $deleted 个远程对象。';
  }

  @override
  String poolRemoteCleanupPartial(int deleted, int failed, String nodes) {
    return '已删除 $deleted 个远程对象，$failed 项失败（$nodes）。';
  }

  @override
  String analyzerSelectedCountAndSize(int count, String size) {
    return '已选 $count 项（$size）';
  }

  @override
  String analyzerBatchDeleteConfirmTitle(int count) {
    return '删除所选 $count 个文件？';
  }

  @override
  String analyzerBatchDeleteDone(int count, String size) {
    return '已删除 $count 个文件，释放 $size。';
  }

  @override
  String analyzerBatchDeletePartial(int deleted, int failed) {
    return '已删除 $deleted 个文件，$failed 个失败。';
  }

  @override
  String get analyzerMultiSelectTooltip => '多选文件';

  @override
  String get navDomainSettings => '设置';

  @override
  String get sidebarLocationsGroup => '位置';

  @override
  String get sidebarQuickViewsGroup => '快捷视图';

  @override
  String get sidebarTransferGroup => '传输与同步';

  @override
  String get importFiles => '导入文件';

  @override
  String get importFolder => '导入文件夹';

  @override
  String get browseInAppImport => '应用内浏览导入…';

  @override
  String get createAndImportTooltip => '新建 / 导入';

  @override
  String get createAndUploadTooltip => '新建 / 上传';

  @override
  String get menuGroupViewAndSelect => '视图与选择';

  @override
  String get menuGroupDirectoryTools => '目录工具';

  @override
  String get menuGroupDevAndPath => '开发者与路径';

  @override
  String get menuGroupOpenAndTransfer => '打开与传输';

  @override
  String get menuGroupOrganizeAndInfo => '整理与信息';

  @override
  String get lanShareMenu => '局域网共享…';

  @override
  String get managePrivacySpace => '隐私空间管理…';

  @override
  String get managePrivacySpaceSubtitle => '解锁、新建、备份或导入加密空间';

  @override
  String get viewAndSortMenu => '视图与排序';

  @override
  String get copyPathMenu => '复制路径';

  @override
  String get smartCategoriesHeader => '文件类型';

  @override
  String get configMigrationSettingsCategory => '设置';

  @override
  String configMigrationFavoritesCount(int count) {
    return '$count 个收藏夹';
  }

  @override
  String configMigrationSettingsCount(int count) {
    return '$count 项设置';
  }

  @override
  String configMigrationSelectedRatio(int selected, int total) {
    return '已选 $selected / $total';
  }

  @override
  String get configMigrationPasswordRequiredHint => '导出远程连接或存储池时必须设置加密密码。';

  @override
  String get configMigrationPasswordOptionalHint =>
      '可选密码：填写将加密导出为 .fmbak，留空将导出为明文 .json。';

  @override
  String get configMigrationConfirmPasswordLabel => '确认密码';

  @override
  String get configMigrationPasswordMismatch => '两次输入的密码不一致。';

  @override
  String configMigrationPoolDependencyBadge(String pools) {
    return '存储池依赖: $pools';
  }

  @override
  String get configMigrationPoolDependencyHint =>
      '已选存储池关联的远程连接会保持必选并锁定，取消对应存储池后方可取消。';

  @override
  String get configMigrationSelectAtLeastOne => '请至少选择一项再继续。';

  @override
  String get configMigrationShareBackupAction => '分享 .fmbak';

  @override
  String get configMigrationShareJsonAction => '分享 .json';

  @override
  String get configMigrationExportSharedNotice => '已调起系统分享导出备份。';

  @override
  String get configMigrationChooseBackupAction =>
      '选择 .fmbak / .fmremotes / .json 文件';

  @override
  String get configMigrationPasteOrPickHint => '请选择备份文件，或在下方粘贴 JSON / 加密文本内容。';

  @override
  String get configMigrationNextSelectAction => '解析并选择导入项';

  @override
  String get configMigrationImportSelectTitle => '选择要导入的配置项';

  @override
  String get configMigrationConfirmImportAction => '确认导入';

  @override
  String configMigrationSummaryNotice(
    int remotes,
    int pools,
    int bookmarks,
    int prefs,
  ) {
    return '已导入 $remotes 个远程连接、$pools 个存储池、$bookmarks 个收藏夹、$prefs 项设置';
  }

  @override
  String configMigrationPoolImportFailedSummary(int count, String names) {
    return '；$count 个存储池失败（$names）';
  }

  @override
  String get configMigrationNoRemotes => '暂无远程连接';

  @override
  String get configMigrationNoPools => '暂无存储池';

  @override
  String get configMigrationNoFavorites => '暂无收藏夹';

  @override
  String get configMigrationMissingPoolRemoteNotice =>
      '部分存储池节点关联的远程连接不在本次选择中，将依赖本机已有对应连接。';

  @override
  String get configMigrationInvalidBundleFormat => '无效的备份文件或 JSON 格式。';

  @override
  String get configMigrationWrongPassword => '密码错误或加密备份已损坏。';

  @override
  String get configMigrationDecryptAndPreview => '解密并继续';

  @override
  String get configMigrationSystemAuthPrompt => '请验证手机锁屏或电脑系统密码以导出远程连接';

  @override
  String get configMigrationSystemAuthRequiredNote => '导出远程连接时将验证手机锁屏或电脑系统密码。';

  @override
  String get configMigrationSystemAuthFailed => '系统认证已取消或失败，已取消导出。';

  @override
  String get configMigrationSystemAuthUnavailable =>
      '当前设备未设置锁屏密码或系统密码，请先开启后再导出远程连接。';

  @override
  String get quickFileProvider => 'FP（文件位置）';
}
