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
  String cannotClearFinishedTasks(Object count) {
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
  String compressFailed(Object error) {
    return '压缩失败: $error';
  }

  @override
  String get compressing => '正在压缩…';

  @override
  String get connectServer => '连接服务器';

  @override
  String get copyError => '复制错误';

  @override
  String copyFailed(Object error) {
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
  String createdCandidate(Object name) {
    return '已创建 \"$name\"';
  }

  @override
  String get creatingCopy => '正在创建副本…';

  @override
  String get darkTheme => '深色主题';

  @override
  String get delete => '删除';

  @override
  String deleteFailed(Object error) {
    return '删除失败: $error';
  }

  @override
  String deletedCount(Object count) {
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
  String downloadFailed(Object error) {
    return '下载失败: $error';
  }

  @override
  String downloadedTo(Object path) {
    return '已下载到 $path';
  }

  @override
  String downloadingFile(Object file) {
    return '正在下载 $file…';
  }

  @override
  String get downloadingFiles => '正在下载文件…';

  @override
  String downloadingItem(Object name) {
    return '正在下载 $name…';
  }

  @override
  String duplicateFailed(Object error) {
    return '创建副本失败: $error';
  }

  @override
  String get emptyRecycleBin => '清空回收站';

  @override
  String get errorCopied => '错误信息已复制到剪贴板';

  @override
  String get exportPreviewCache => '导出与预览缓存';

  @override
  String extractFailed(Object error) {
    return '解压失败: $error';
  }

  @override
  String get extracting => '正在解压…';

  @override
  String get failed => '失败';

  @override
  String failedToCreate(Object error) {
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
  String hoursLeft(Object hours) {
    return '剩余约 $hours 小时';
  }

  @override
  String hoursMinutesLeft(Object hours, Object minutes) {
    return '剩余约 $hours 小时 $minutes 分钟';
  }

  @override
  String get inProgress => '进行中';

  @override
  String get invertSelection => '反选';

  @override
  String itemsCount(Object count) {
    return '$count 项';
  }

  @override
  String itemsOutOfTotal(Object completed, Object total) {
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
  String minutesLeft(Object minutes) {
    return '剩余约 $minutes 分钟';
  }

  @override
  String moveFailed(Object error) {
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
  String retryFailed(Object error) {
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
  String secondsLeft(Object seconds) {
    return '剩余约 $seconds 秒';
  }

  @override
  String get selectAll => '全选';

  @override
  String get selectFolderToUpload => '选择要上传的文件夹';

  @override
  String get selectItems => '多选模式';

  @override
  String get settings => '设置';

  @override
  String get settingsCardSubtitle => '主题、系统信息、关于';

  @override
  String get shareInstructions => '同一 Wi-Fi 下浏览器打开以下地址即可访问（链接含访问令牌，请勿公开分享）：';

  @override
  String get sharePasswordLabel => '访问密码';

  @override
  String sharePasswordNotice(Object pwd) {
    return '已自动生成访问密码：$pwd';
  }

  @override
  String get shared => '共享目录';

  @override
  String get sharedPathCopied => '共享目录路径已复制';

  @override
  String get showHiddenFiles => '显示隐藏文件';

  @override
  String skippedAlreadyExists(Object count) {
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
  String get transferring => '正在传输…';

  @override
  String trashCountNotice(Object count) {
    return '回收站共有 $count 项';
  }

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
  String uploadingFolder(Object folder) {
    return '正在上传文件夹 \"$folder\"…';
  }

  @override
  String uploadingItems(Object count) {
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
}
