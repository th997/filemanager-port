// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutSection => 'About & System';

  @override
  String get accentClassicBlue => 'Classic blue';

  @override
  String get accentColor => 'Accent color';

  @override
  String get accentDeepTeal => 'Deep teal';

  @override
  String get accentDynamic => 'System dynamic';

  @override
  String get accentForest => 'Forest';

  @override
  String get accentGrape => 'Grape';

  @override
  String get accentIndigo => 'Indigo';

  @override
  String get accentSunset => 'Sunset';

  @override
  String get actionInfo => 'Info';

  @override
  String get allPhotos => 'All photos';

  @override
  String get almostDone => 'Almost done';

  @override
  String get appTitle => 'FP File Manager';

  @override
  String get appearance => 'Appearance';

  @override
  String get ascending => 'Ascending';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get browseInAppUpload => 'Browse In-App to Upload…';

  @override
  String get browserSection => 'Browser';

  @override
  String get bucketName => 'Bucket Name';

  @override
  String get bucketNameHint =>
      'Lowercase letters, numbers, hyphens (3-63 chars)';

  @override
  String get bucketRootFolderUploadError =>
      'You are at the multi-bucket root. Please enter a bucket first before uploading a folder.';

  @override
  String get bucketRootTransferError =>
      'You are at the multi-bucket root. Please enter a bucket first before transferring items.';

  @override
  String get bucketRootUploadError =>
      'You are at the multi-bucket root. Please enter a bucket first before uploading files.';

  @override
  String get bufferDuration => 'Buffer Duration';

  @override
  String get bufferSize => 'Buffer Size';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelTask => 'Cancel task';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get playWithMediaKit => 'Play with MediaKit Engine';

  @override
  String get cancelling => 'Cancelling…';

  @override
  String get cannotCancelTask => 'This task cannot be cancelled';

  @override
  String cannotClearFinishedTasks(int count) {
    return '$count finished task(s) could not be cleared';
  }

  @override
  String get cannotDismissTask => 'Could not dismiss task';

  @override
  String get change => 'Change';

  @override
  String get clear => 'Clear';

  @override
  String get clearFinished => 'Clear finished';

  @override
  String get close => 'Close';

  @override
  String get closeSearch => 'Close search';

  @override
  String get cloudRemoteStorage => 'Cloud & Remote Storage';

  @override
  String get cloudToolsSettings => 'Cloud, Tools & Settings';

  @override
  String get completed => 'Completed';

  @override
  String compressFailed(String error) {
    return 'Compress failed: $error';
  }

  @override
  String get compressing => 'Compressing…';

  @override
  String get connectServer => 'Connect a server';

  @override
  String get copyError => 'Copy Error';

  @override
  String copyFailed(String error) {
    return 'Copy failed: $error';
  }

  @override
  String get copyPassword => 'Copy password';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get copyingFiles => 'Copying files…';

  @override
  String get create => 'Create';

  @override
  String createdCandidate(String name) {
    return 'Created \"$name\"';
  }

  @override
  String get creatingCopy => 'Creating copy…';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get delete => 'Delete';

  @override
  String deleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String deletedCount(int count) {
    return 'Deleted $count items';
  }

  @override
  String get deleting => 'Deleting…';

  @override
  String get descending => 'Descending';

  @override
  String get desktopHtmlPreviewHint =>
      'Desktop HTML preview is simplified. For full JS/CSS styling, open in browser.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get downloadDestination => 'Select Download Destination';

  @override
  String downloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String downloadedTo(String path) {
    return 'Downloaded to $path';
  }

  @override
  String downloadingFile(String file) {
    return 'Downloading $file…';
  }

  @override
  String get downloadingFiles => 'Downloading files…';

  @override
  String downloadingItem(String name) {
    return 'Downloading $name…';
  }

  @override
  String duplicateFailed(String error) {
    return 'Duplicate failed: $error';
  }

  @override
  String get emptyRecycleBin => 'Empty Recycle Bin';

  @override
  String get endpointHintS3 =>
      'Endpoint (Optional for AWS, required for MinIO/R2)';

  @override
  String get endpointHintGeneric =>
      'Endpoint (e.g. https://oss-cn-hangzhou.aliyuncs.com)';

  @override
  String get errorCopied => 'Error copied to clipboard';

  @override
  String get exportPreviewCache => 'Export & Preview Cache';

  @override
  String extractFailed(String error) {
    return 'Extract failed: $error';
  }

  @override
  String get extracting => 'Extracting…';

  @override
  String get failed => 'Failed';

  @override
  String failedToCreate(String error) {
    return 'Failed to create: $error';
  }

  @override
  String get finalizingServer => 'Finalizing (server processing)…';

  @override
  String get folderLabel => 'Folder';

  @override
  String get folderName => 'Folder Name';

  @override
  String get followSystemSettings => 'Follow system settings';

  @override
  String get gallery => 'Gallery';

  @override
  String get homeDashboard => 'Home Dashboard';

  @override
  String hoursLeft(int hours) {
    return 'About $hours hours left';
  }

  @override
  String hoursMinutesLeft(int hours, int minutes) {
    return 'About $hours hr $minutes min left';
  }

  @override
  String get inProgress => 'In progress';

  @override
  String get invertSelection => 'Invert Selection';

  @override
  String itemsCount(int count) {
    return '$count items';
  }

  @override
  String itemsOutOfTotal(int completed, int total) {
    return '$completed of $total items';
  }

  @override
  String get lanSharing => 'LAN HTTP Web Sharing';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get lightTheme => 'Light theme';

  @override
  String get localStorage => 'Local Storage';

  @override
  String get mediaPlayback => 'Media Playback (Remote Buffer)';

  @override
  String get minimize => 'Minimize';

  @override
  String minutesLeft(int minutes) {
    return 'About $minutes min left';
  }

  @override
  String monthYearLabel(String month, int year) {
    return '$month $year';
  }

  @override
  String get monthSeptember => 'September';

  @override
  String get monthOctober => 'October';

  @override
  String get monthNovember => 'November';

  @override
  String get monthMay => 'May';

  @override
  String get monthMarch => 'March';

  @override
  String get monthJune => 'June';

  @override
  String get monthJuly => 'July';

  @override
  String get monthJanuary => 'January';

  @override
  String get monthFebruary => 'February';

  @override
  String get monthDecember => 'December';

  @override
  String get monthAugust => 'August';

  @override
  String get monthApril => 'April';

  @override
  String moveFailed(String error) {
    return 'Move failed: $error';
  }

  @override
  String get movingFiles => 'Moving files…';

  @override
  String get newBucket => 'New Bucket';

  @override
  String get newFile => 'New File';

  @override
  String get newFolder => 'New Folder';

  @override
  String get newTextFile => 'New Text File';

  @override
  String get noLanIpFound =>
      'No LAN IP detected, please connect to Wi-Fi or Ethernet.';

  @override
  String get noTasksYet => 'No tasks yet';

  @override
  String get openInBrowser => 'Open in Browser';

  @override
  String get options => 'Options';

  @override
  String get passwordCopied => 'Password copied to clipboard';

  @override
  String get passwordFieldHelper =>
      'Leave empty to access via token link without password; set to also allow password login';

  @override
  String get passwordFieldLabel => 'Password (Optional)';

  @override
  String get pdfMarginStandard => 'Standard (36pt)';

  @override
  String get pdfMarginRelaxed => 'Relaxed (54pt)';

  @override
  String get pdfMarginCompact => 'Compact (16pt)';

  @override
  String get pickFileTitle => 'Select File';

  @override
  String get pickFilesTitle => 'Select Files';

  @override
  String get playbackSpeed => 'Playback Speed';

  @override
  String get pleaseSelectSpecificFolder =>
      'Please select a specific folder to upload';

  @override
  String get port => 'Port';

  @override
  String get previewImage => 'Preview Image';

  @override
  String get processingPercent => '100% (processing)';

  @override
  String get quickVolumes => 'Volumes';

  @override
  String get quickRoot => 'Root /';

  @override
  String get quickPictures => 'Pictures';

  @override
  String get quickHome => 'Home';

  @override
  String get quickInbox => 'My Space';

  @override
  String get privateInboxSubtitle => 'App-private · Hidden from other apps';

  @override
  String quickDrive(String letter) {
    return 'Drive ($letter:)';
  }

  @override
  String get quickDownloads => 'Downloads';

  @override
  String get quickDownload => 'Download';

  @override
  String get quickDesktop => 'Desktop';

  @override
  String get quickDcim => 'DCIM (Photos)';

  @override
  String get readOnly => ' (read-only)';

  @override
  String get readOnlyMode => 'Read Only (disallow web uploads)';

  @override
  String get recent => 'Recent';

  @override
  String get recentDirs => 'Recent:';

  @override
  String get recycleBin => 'Recycle Bin';

  @override
  String get remote => 'Remote';

  @override
  String get remoteArchiveCache => 'Remote Archive Cache';

  @override
  String get retry => 'Retry';

  @override
  String retryFailed(String error) {
    return 'Retry failed: $error';
  }

  @override
  String get runInBackground => 'Background';

  @override
  String get runningOnLan => '🟢 Running on LAN';

  @override
  String get save => 'Save';

  @override
  String get scriptDisabledTooltip =>
      'Scripts disabled (safe default), click to enable';

  @override
  String get scriptEnabledTooltip =>
      'Scripts enabled: page can access files in shared dir, click to disable';

  @override
  String get searchFiles => 'Search files';

  @override
  String secondsLeft(int seconds) {
    return 'About $seconds sec left';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String selectCount(int count) {
    return 'Select ($count)';
  }

  @override
  String get selectFolderToUpload => 'Select Folder to Upload';

  @override
  String get selectItems => 'Select items';

  @override
  String pickerItemCounts(int folders, int files) {
    String _temp0 = intl.Intl.pluralLogic(
      folders,
      locale: localeName,
      other: '$folders folders',
      one: '1 folder',
    );
    String _temp1 = intl.Intl.pluralLogic(
      files,
      locale: localeName,
      other: '$files files',
      one: '1 file',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String selectedCountLabel(int count) {
    return '$count selected';
  }

  @override
  String selectedCountBytesLabel(int count, String size) {
    return '$count selected ($size)';
  }

  @override
  String get settings => 'Settings';

  @override
  String get settingsCardSubtitle => 'Theme, System info, About';

  @override
  String get shareInstructions =>
      'Open the following URL in a browser on the same Wi-Fi to access (contains token, do not share publicly):';

  @override
  String get sharePasswordLabel => 'Password';

  @override
  String sharePasswordNotice(String pwd) {
    return 'Generated share password: $pwd';
  }

  @override
  String get shared => 'Shared';

  @override
  String get sharedPathCopied => 'Shared path copied';

  @override
  String get showHiddenFiles => 'Show hidden files';

  @override
  String skippedAlreadyExists(int count) {
    return '$count items skipped (already exist)';
  }

  @override
  String get sortBy => 'Sort By';

  @override
  String get splitView => 'Split view';

  @override
  String get stopped => '⚪ Stopped';

  @override
  String get storageAndCache => 'Storage & Cache';

  @override
  String get supportedProtocols => 'Supported Protocols';

  @override
  String get switchToGrid => 'Switch to Grid';

  @override
  String get switchToList => 'Switch to List';

  @override
  String get switchedToBackground =>
      'Moved to background — check progress in Home → Tasks';

  @override
  String get systemPicker => 'System Picker';

  @override
  String get taskCompress => 'Compress';

  @override
  String get taskCopy => 'Copy';

  @override
  String get taskDelete => 'Delete';

  @override
  String get taskExtract => 'Extract';

  @override
  String get taskGeneric => 'Task';

  @override
  String get taskMove => 'Move';

  @override
  String get tasks => 'Tasks';

  @override
  String get tasksEmptySubtitle =>
      'Copies, moves and other long operations will appear here.';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System';

  @override
  String get toolbarAtBottom => 'Toolbar at bottom';

  @override
  String get toolbarAtBottomDesc =>
      'Move the address bar and icons below the file list';

  @override
  String get toolbarUpOneLevel => 'Up one level';

  @override
  String get toolbarJump => 'Jump';

  @override
  String get toolbarForwardHistory => 'Forward in history (Alt+→)';

  @override
  String get toolbarEditAddress => 'Edit address (Cmd/Ctrl+L)';

  @override
  String get toolbarBackHistory => 'Back in history (Alt+←)';

  @override
  String get transferring => 'Transferring…';

  @override
  String trashCountNotice(int count) {
    return '$count items in trash';
  }

  @override
  String get unknownDate => 'Unknown date';

  @override
  String get upload => 'Upload';

  @override
  String get uploadFiles => 'Upload Files';

  @override
  String get uploadFolder => 'Upload Folder';

  @override
  String get uploadItemsToCurrentFolder => 'Upload Items to Current Folder';

  @override
  String get uploadThisFolder => 'Upload folder';

  @override
  String get uploadWithSystemPicker => 'Upload using system file picker';

  @override
  String get uploadWithSystemPickerDesc =>
      'Directly invokes native OS file picker, supporting system bookmarks and path paste';

  @override
  String uploadingFolder(String folder) {
    return 'Uploading folder \"$folder\"…';
  }

  @override
  String uploadingItems(int count) {
    return 'Uploading $count items…';
  }

  @override
  String get urlCopied => 'URL copied to clipboard';

  @override
  String get utilities => 'Utilities';

  @override
  String get waiting => 'Waiting…';

  @override
  String get waitingServerVerify =>
      'All data sent, waiting for server verification and merge…';

  @override
  String get webSharingServer => 'Web Sharing Server';

  @override
  String get welcomeBody =>
      'Browse local folders right away, or connect a server — SFTP, WebDAV, S3, SMB and more — to manage files anywhere.';

  @override
  String get welcomeTitle => 'Welcome to FP File Manager';

  @override
  String get invalidBucketName =>
      'Invalid bucket name. Must be 3-63 characters, only lowercase letters, numbers, and hyphens, and start/end with a letter or digit.';

  @override
  String get sortByName => 'Name';

  @override
  String get sortBySize => 'Size';

  @override
  String get sortByDate => 'Date modified';

  @override
  String get sortByType => 'Type';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get openSourceLicensesSubtitle =>
      'Licenses and notices of third-party open-source software';

  @override
  String get open => 'Open';

  @override
  String get openWith => 'Open with';

  @override
  String get openAsText => 'Open as Text';

  @override
  String get openAsTextSubtitle => 'Open with built-in text editor';

  @override
  String get openWithOtherApp => 'Open with Another App';

  @override
  String get openWithOtherAppSubtitle =>
      'Use system default or third-party apps';

  @override
  String get openAsMedia => 'Open as Media';

  @override
  String get openAsMediaSubtitle => 'Play with built-in media player';

  @override
  String get openAsImage => 'Open as Image';

  @override
  String get openAsImageSubtitle => 'View with built-in image viewer';

  @override
  String get download => 'Download';

  @override
  String get downloadToLocal => 'Download to local';

  @override
  String get copy => 'Copy';

  @override
  String get cut => 'Cut';

  @override
  String pasteCount(int count) {
    return 'Paste ($count)';
  }

  @override
  String get copyPath => 'Copy Path';

  @override
  String get copyFolderPath => 'Copy Folder Path';

  @override
  String get copyFilePath => 'Copy File Path';

  @override
  String get copyOriginalPath => 'Copy Original Path';

  @override
  String get pathCopied => 'Path copied to clipboard';

  @override
  String get folderPathCopied => 'Folder path copied to clipboard';

  @override
  String copiedPathValue(String path) {
    return 'Copied path: $path';
  }

  @override
  String copiedValue(String value) {
    return 'Copied: $value';
  }

  @override
  String copiedItemToClipboard(String name) {
    return 'Copied $name to clipboard';
  }

  @override
  String cutItemToClipboard(String name) {
    return 'Cut $name to clipboard';
  }

  @override
  String copiedItemsCount(int count) {
    return '$count items copied to clipboard';
  }

  @override
  String cutItemsCount(int count) {
    return '$count items cut to clipboard';
  }

  @override
  String get rename => 'Rename';

  @override
  String get newName => 'New Name';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get share => 'Share';

  @override
  String get properties => 'Properties';

  @override
  String get details => 'Details';

  @override
  String get extractHere => 'Extract Here';

  @override
  String get compress => 'Compress';

  @override
  String get compressToZip => 'Compress to ZIP';

  @override
  String get archiveName => 'Archive Name';

  @override
  String get bookmarkThisFolder => 'Bookmark This Folder';

  @override
  String get bookmarkLocation => 'Bookmark Location';

  @override
  String bookmarkedName(String name) {
    return 'Bookmarked \"$name\"';
  }

  @override
  String alreadyBookmarked(String name) {
    return '\"$name\" is already bookmarked';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get undo => 'Undo';

  @override
  String get discard => 'Discard';

  @override
  String get go => 'Go';

  @override
  String get goUp => 'Go Up';

  @override
  String get loadMore => 'Load more';

  @override
  String get clearFilter => 'Clear Filter';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get searchAction => 'Search';

  @override
  String get remove => 'Remove';

  @override
  String removedName(String name) {
    return 'Removed \"$name\"';
  }

  @override
  String get unknownSize => 'Unknown';

  @override
  String get wrapIndicator => 'Wrap';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get ok => 'OK';

  @override
  String get typeLabel => 'Type';

  @override
  String get nameLabel => 'Name';

  @override
  String get pathLabel => 'Path';

  @override
  String get extensionLabel => 'Extension';

  @override
  String get sizeLabel => 'Size';

  @override
  String get modifiedLabel => 'Modified';

  @override
  String get hiddenLabel => 'Hidden';

  @override
  String get hiddenFilesOff => 'hidden files off';

  @override
  String get symlinkLabel => 'Symlink';

  @override
  String get directoryLabel => 'Directory';

  @override
  String get directoryEmptyLabel => 'Directory (empty)';

  @override
  String get fileLabel => 'File';

  @override
  String get archiveLabel => 'Archive';

  @override
  String get measuring => 'Measuring…';

  @override
  String bytesUnit(String count) {
    return '$count bytes';
  }

  @override
  String yesBytes(String formatted, String raw) {
    return '$formatted ($raw bytes)';
  }

  @override
  String get downloadFileTitle => 'Download file?';

  @override
  String get downloadFileStreamHint =>
      'This file cannot be previewed while streaming, so it has to be downloaded first.';

  @override
  String get saveDestination => 'Save destination';

  @override
  String get chooseDownloadFolder => 'Choose download folder';

  @override
  String get folderIsEmpty => 'Folder is empty';

  @override
  String get noMatchingItems => 'No matching items';

  @override
  String get openFolderTooltip => 'Open folder';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String get filterFilesFoldersHint => 'Filter files & folders...';

  @override
  String get noSubfolders => 'No subfolders';

  @override
  String get noMatchingSubfolders => 'No matching subfolders';

  @override
  String get hideHiddenFolders => 'Hide hidden folders';

  @override
  String get showAllFileTypes => 'All files';

  @override
  String get showHiddenFolders => 'Show hidden folders';

  @override
  String get hideHiddenFiles => 'Hide hidden files';

  @override
  String get filterSubfoldersHint => 'Filter subfolders...';

  @override
  String get cannotReadFolderPrefix => 'Cannot read this folder: ';

  @override
  String failedCreateFolder(String error) {
    return 'Failed to create folder: $error';
  }

  @override
  String get filterEllipsis => 'Filter...';

  @override
  String get parentFolderTooltip => 'Parent folder';

  @override
  String get clickToCopyPath => 'Click to copy path';

  @override
  String get folderNameHint => 'e.g. Documents';

  @override
  String get folderNameInputLabel => 'Folder name';

  @override
  String couldNotRequestFileAccess(String error) {
    return 'Could not request file access: $error';
  }

  @override
  String couldNotRefreshHome(String error) {
    return 'Could not refresh home data: $error';
  }

  @override
  String get storagePermissionRequired =>
      'Storage permission is required to browse files. Grant \"All files access\" in the next screen.';

  @override
  String get requesting => 'Requesting…';

  @override
  String get grant => 'Grant';

  @override
  String get remoteProtocolsSubtitle => 'S3, OSS, SFTP, WebDAV...';

  @override
  String utilitiesTrashSubtitle(int count) {
    return '$count in trash • Web share';
  }

  @override
  String get utilitiesDefaultSubtitle => 'Recycle bin, Web share, Cache';

  @override
  String get tasksDefaultSubtitle => 'Transfers and operations';

  @override
  String get bookmarksDefaultSubtitle => 'Saved folders';

  @override
  String get recentDefaultSubtitle => 'Browsing history';

  @override
  String get sortLabelName => 'Name';

  @override
  String get sortLabelSize => 'Size';

  @override
  String get sortLabelDate => 'Date';

  @override
  String get sortLabelType => 'Type';

  @override
  String couldNotLoadMore(String error) {
    return 'Could not load more: $error';
  }

  @override
  String refreshFailed(String error) {
    return 'Refresh failed: $error';
  }

  @override
  String downloadedNoAppToOpen(String name) {
    return 'Downloaded, but no installed app can open $name';
  }

  @override
  String get allowInstallApkPrompt =>
      'Allow installing unknown apps to open APK files';

  @override
  String noAppToOpenFile(String name) {
    return 'No installed app can open $name';
  }

  @override
  String cannotOpenFile(String error) {
    return 'Cannot open file: $error';
  }

  @override
  String cannotShareFile(String error) {
    return 'Cannot share file: $error';
  }

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String noSearchResultsFor(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get searchedThisAndSubfolders =>
      'Searched this folder and its subfolders.';

  @override
  String get first200Results =>
      'First 200 results (narrow the search to see more)';

  @override
  String searchResultsInFolder(int count) {
    return 'Results in this folder and subfolders: $count';
  }

  @override
  String searchFoundCount(int count) {
    return '$count found';
  }

  @override
  String get currentFolder => 'Current folder';

  @override
  String fileBeyondFirstPage(String parent) {
    return 'File is beyond the first page of \"$parent\"; open the folder to view it.';
  }

  @override
  String tooManyItemsSelectAll(int count) {
    return 'Too many items to select all at once ($count)';
  }

  @override
  String couldNotLoadAllItems(String error) {
    return 'Could not load all items: $error';
  }

  @override
  String get alreadyLocalUseCopy =>
      'Already local: use Copy to place these files elsewhere.';

  @override
  String get fileNameLabel => 'File Name';

  @override
  String get fileNameHint => 'e.g. notes.txt';

  @override
  String failedToCreateFile(String error) {
    return 'Failed to create file: $error';
  }

  @override
  String get alreadyExists => 'Already exists';

  @override
  String get skip => 'Skip';

  @override
  String get keepBoth => 'Keep both';

  @override
  String get replace => 'Replace';

  @override
  String get readOnlyCannotDrop =>
      'This location is read-only — cannot drop files here';

  @override
  String get cannotDropFolderIntoSelf =>
      'Cannot drop a folder onto itself or into its own subfolder';

  @override
  String deleteSingleConfirmTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String deleteMultipleConfirmTitle(int count) {
    return 'Delete $count items?';
  }

  @override
  String get deleteChoiceTrashOrPermanent =>
      'Choose whether to move to Recycle Bin or delete permanently.';

  @override
  String get deletePermanentWarning =>
      'Delete permanently? This cannot be undone.';

  @override
  String get deleteRemotePermanentWarning =>
      'This item is on a remote server and cannot be moved to the local Recycle Bin. It will be deleted permanently.';

  @override
  String get permanentDelete => 'Permanent Delete';

  @override
  String couldNotMoveToTrash(int failed, int total, String details) {
    return 'Could not move $failed of $total items to Recycle Bin:\n$details';
  }

  @override
  String get movedOneToTrash => 'Moved 1 item to Recycle Bin';

  @override
  String movedManyToTrash(int count) {
    return 'Moved $count items to Recycle Bin';
  }

  @override
  String couldNotRestoreItems(int count) {
    return 'Could not restore $count item(s)';
  }

  @override
  String get nameCannotContainSlash => 'A name cannot contain \"/\" or \"\\\"';

  @override
  String renameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String get rootLabel => 'Root';

  @override
  String get exitSplitView => 'Exit split view';

  @override
  String get cancelSelectionEsc => 'Cancel selection (Esc)';

  @override
  String get backToPreviousPage => 'Back to previous page';

  @override
  String get backToTop => 'Back to top';

  @override
  String get searchFilesSubfoldersHint => 'Search files & subfolders…';

  @override
  String get listView => 'List view';

  @override
  String get gridView => 'Grid view';

  @override
  String sortStatusTooltip(String field, String arrow) {
    return 'Sort: $field $arrow';
  }

  @override
  String get internalStorage => 'Internal Storage';

  @override
  String get capabilitiesPrefix => 'Capabilities: ';

  @override
  String get failedToLoadDir => 'Failed to load directory';

  @override
  String noFilesMatching(String query) {
    return 'No files matching \"$query\"';
  }

  @override
  String get onlyHiddenFilesHere => 'Only hidden files here';

  @override
  String get directoryIsEmpty => 'Directory is empty';

  @override
  String get enterPathToJumpHint => 'Enter path to jump...';

  @override
  String get goToLine => 'Go to Line';

  @override
  String lineNumberRange(int total) {
    return 'Line number (1 - $total)';
  }

  @override
  String enterLineNumberBetween(int total) {
    return 'Enter a line number between 1 and $total';
  }

  @override
  String replacedOccurrences(int count) {
    return 'Replaced $count occurrence(s)';
  }

  @override
  String get reloadFile => 'Reload File';

  @override
  String get reloadFileConfirm =>
      'Discard unsaved changes and reload the file from disk?';

  @override
  String get reload => 'Reload';

  @override
  String get fileSavedSuccess => 'File saved successfully';

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String pdfExportFailed(String error) {
    return 'PDF Export failed: $error';
  }

  @override
  String get saveChangesQuestion => 'Save Changes?';

  @override
  String get saveBeforeBrowserPrompt =>
      'Do you want to save your changes before opening in the external browser?';

  @override
  String get openWithoutSaving => 'Open without Saving';

  @override
  String get saveAndOpen => 'Save and Open';

  @override
  String failedOpenInBrowser(String error) {
    return 'Failed to open in browser: $error';
  }

  @override
  String get unsavedChanges => 'Unsaved Changes';

  @override
  String get saveBeforeClosingPrompt =>
      'You have unsaved changes. Save them before closing?';

  @override
  String get findInFileTooltip => 'Find in file (Ctrl+F)';

  @override
  String get showSource => 'Show source';

  @override
  String get showPreview => 'Show preview';

  @override
  String get markdownTheme => 'Markdown Theme';

  @override
  String get exportToPdf => 'Export to PDF';

  @override
  String get printPreviewPdf => 'Print / Preview PDF';

  @override
  String get shareSavePdf => 'Share / Save PDF';

  @override
  String get marginsSpacing => 'Margins / Spacing';

  @override
  String get readOnlyCannotEditTooltip =>
      'Read-only location — this file cannot be edited here';

  @override
  String get saveChangesTooltip => 'Save changes (Ctrl+S)';

  @override
  String get saveAs => 'Save As...';

  @override
  String get saveToThisFolder => 'Save to this folder';

  @override
  String get savedToCachePrompt =>
      'Saved to app cache. Tap Save As to save to device storage.';

  @override
  String get savedLabel => 'Saved';

  @override
  String get editLabel => 'Edit';

  @override
  String get textOptions => 'Text Options';

  @override
  String get allTextCopied => 'All text copied to clipboard';

  @override
  String get reloadFromDiskShortcut => 'Reload from Disk (Ctrl+R)';

  @override
  String get copyAllText => 'Copy All Text';

  @override
  String get goToLineShortcut => 'Go to Line... (Ctrl+G)';

  @override
  String largerFontShortcut(int pt) {
    return 'Larger (Ctrl+=) ($pt pt)';
  }

  @override
  String smallerFontShortcut(int pt) {
    return 'Smaller (Ctrl+-) ($pt pt)';
  }

  @override
  String get resetFontShortcut => 'Reset Size (Ctrl+0) (13pt)';

  @override
  String get wordWrap => 'Word Wrap';

  @override
  String get undoShortcut => 'Undo (Ctrl+Z)';

  @override
  String get redoShortcut => 'Redo (Ctrl+Y)';

  @override
  String failedToOpenFile(String error) {
    return 'Failed to open file: $error';
  }

  @override
  String get readOnlyCannotSave =>
      'Read-only location — changes cannot be saved here.';

  @override
  String get findInFileHint => 'Find in file...';

  @override
  String get previousMatch => 'Previous match';

  @override
  String get nextMatch => 'Next match';

  @override
  String get toggleReplaceShortcut => 'Toggle replace (Ctrl+H)';

  @override
  String get closeFindShortcut => 'Close find (Esc)';

  @override
  String get replaceWithHint => 'Replace with...';

  @override
  String get replaceAll => 'Replace All';

  @override
  String get documentDetails => 'Document Details';

  @override
  String get copyAll => 'Copy All';

  @override
  String get documentCopied => 'Document copied to clipboard';

  @override
  String get linesLabel => 'Lines';

  @override
  String get wordsLabel => 'Words';

  @override
  String get charactersLabel => 'Characters';

  @override
  String get byteSizeLabel => 'Byte Size';

  @override
  String get lineEndingsLabel => 'Line Endings';

  @override
  String get cursorPositionLabel => 'Cursor Position';

  @override
  String cursorLineCol(int line, int col) {
    return 'Line $line, Col $col';
  }

  @override
  String get readOnlyLocation => 'Read-only location';

  @override
  String get previewModeLabel => 'Preview';

  @override
  String get viewingSourceLabel => 'Viewing source';

  @override
  String get editingModeLabel => 'Editing';

  @override
  String editorStatusLine(int line, int col, int lines) {
    return 'Ln $line, Col $col  •  Lines: $lines  •  ';
  }

  @override
  String editorStatusWords(int words) {
    return 'Words: $words  •  ';
  }

  @override
  String editorStatusChars(int chars) {
    return 'Chars: $chars  •  ';
  }

  @override
  String get documentIsEmpty => 'Document is empty';

  @override
  String get editInSourceMode => 'Edit in Source Mode';

  @override
  String couldNotScanPhotos(String error) {
    return 'Could not scan for photos.\n$error';
  }

  @override
  String get photoLibraryDenied =>
      'Photo library access denied.\nEnable it in Settings → Privacy → Photos.';

  @override
  String couldNotLoadMorePhotos(String error) {
    return 'Could not load more photos: $error';
  }

  @override
  String cannotOpenPhoto(String error) {
    return 'Cannot open photo: $error';
  }

  @override
  String get photoNoLongerAvailable => 'Photo is no longer available';

  @override
  String get openInViewer => 'Open in Viewer';

  @override
  String get sharePhoto => 'Share Photo';

  @override
  String get photosTitle => 'Photos';

  @override
  String get rescan => 'Rescan';

  @override
  String get scrollToTop => 'Scroll to top';

  @override
  String get noPhotosFound => 'No photos found';

  @override
  String get openSettings => 'Open Settings';

  @override
  String cannotReadImageDetails(String error) {
    return 'Cannot read image details: $error';
  }

  @override
  String get imageDetailsUnavailable => 'Image details are no longer available';

  @override
  String get imageDetails => 'Image Details';

  @override
  String get dimensionsLabel => 'Dimensions';

  @override
  String get dateTakenLabel => 'Date taken';

  @override
  String get cameraLabel => 'Camera';

  @override
  String get locationLabel => 'Location';

  @override
  String cannotLoadImage(String error) {
    return 'Cannot load image: $error';
  }

  @override
  String get imageFileNotFoundLocally => 'Image file not found locally';

  @override
  String get failedToLoadImage => 'Failed to load image';

  @override
  String get imagePathCopied => 'Image path copied';

  @override
  String cannotCopyPath(String error) {
    return 'Cannot copy path: $error';
  }

  @override
  String cannotShareImage(String error) {
    return 'Cannot share image: $error';
  }

  @override
  String get deleteImageConfirm =>
      'Are you sure you want to delete this image? This action cannot be undone.';

  @override
  String deletedItem(String name) {
    return 'Deleted $name';
  }

  @override
  String failedToDelete(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String get shareImage => 'Share Image';

  @override
  String get rotate90 => 'Rotate 90°';

  @override
  String get rotate90Shortcut => 'Rotate 90° (R)';

  @override
  String get deleteImage => 'Delete Image';

  @override
  String get moreOptions => 'More options';

  @override
  String get moreBelow => 'more below';

  @override
  String get zoomInShortcut => 'Zoom in (+)';

  @override
  String get zoomOutShortcut => 'Zoom out (-)';

  @override
  String get resetZoomShortcut => 'Reset zoom (0)';

  @override
  String get previousImage => 'Previous image';

  @override
  String get nextImage => 'Next image';

  @override
  String autoPlayingNext(String name) {
    return 'Auto-playing next: $name';
  }

  @override
  String get nextEpisodeShortcut => 'Next episode (N)';

  @override
  String playlistProgress(int current, int total) {
    return 'Playlist ($current/$total)';
  }

  @override
  String get autoNextOn => 'Auto-next: On';

  @override
  String get autoNextOff => 'Auto-next: Off';

  @override
  String get loopSingle => 'Loop: Single';

  @override
  String get loopOff => 'Loop: Off';

  @override
  String get fullscreenShortcut => 'Fullscreen (F)';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get exitFullscreen => 'Exit Fullscreen';

  @override
  String get playbackOptions => 'Playback options';

  @override
  String get unmuteShortcut => 'Unmute (M)';

  @override
  String muteShortcut(int percent) {
    return 'Mute (M) ($percent%)';
  }

  @override
  String get rewind10s => 'Rewind 10s';

  @override
  String get forward10s => 'Forward 10s';

  @override
  String get autoNextMenuOn => 'Auto-next (On)';

  @override
  String get autoNextMenuOff => 'Auto-next (Off)';

  @override
  String get previousShortcut => 'Previous (P)';

  @override
  String get nextShortcut => 'Next (N)';

  @override
  String get cannotPlayFile => 'Cannot play this file';

  @override
  String get unknownPlaybackError => 'Unknown playback error';

  @override
  String couldNotLoadBookmarks(String error) {
    return 'Could not load bookmarks: $error';
  }

  @override
  String get renameBookmark => 'Rename Bookmark';

  @override
  String get bookmarkNameLabel => 'Bookmark Name';

  @override
  String couldNotRenameBookmark(String error) {
    return 'Could not rename bookmark: $error';
  }

  @override
  String couldNotRemoveBookmark(String error) {
    return 'Could not remove bookmark: $error';
  }

  @override
  String couldNotRestoreBookmark(String error) {
    return 'Could not restore bookmark: $error';
  }

  @override
  String get searchBookmarks => 'Search Bookmarks';

  @override
  String get filterBookmarksHint => 'Filter bookmarks...';

  @override
  String get noBookmarksSaved => 'No bookmarks saved yet';

  @override
  String get noMatchingBookmarks => 'No matching bookmarks';

  @override
  String get bookmarksEmptyHint =>
      'In the file browser, long-press a folder (or right-click it) and choose \"Bookmark This Folder\".';

  @override
  String nothingMatchesQuery(String query) {
    return 'Nothing matches \"$query\".';
  }

  @override
  String get bookmarkActions => 'Bookmark actions';

  @override
  String couldNotLoadRecent(String error) {
    return 'Could not load recent locations: $error';
  }

  @override
  String failedToBookmark(String error) {
    return 'Failed to bookmark: $error';
  }

  @override
  String couldNotRemoveItem(String name, String error) {
    return 'Could not remove \"$name\": $error';
  }

  @override
  String get clearHistory => 'Clear History';

  @override
  String get clearHistoryConfirm =>
      'Remove all recent locations? Bookmarks are kept.';

  @override
  String couldNotClearHistory(String error) {
    return 'Could not clear history: $error';
  }

  @override
  String clearedRecentLocations(int count) {
    return 'Cleared $count recent locations';
  }

  @override
  String get removeFromHistory => 'Remove from History';

  @override
  String get recentHistory => 'Recent History';

  @override
  String get searchHistory => 'Search History';

  @override
  String get filterRecentHint => 'Filter recent locations...';

  @override
  String get noRecentHistory => 'No recent browsing history';

  @override
  String get noMatchingLocations => 'No matching locations';

  @override
  String get recentEmptyHint =>
      'Directories and files you browse will show up here.';

  @override
  String get actionsTooltip => 'Actions';

  @override
  String couldNotLoadTrash(String error) {
    return 'Could not load the Recycle Bin: $error';
  }

  @override
  String get recycledItemDetails => 'Recycled Item Details';

  @override
  String get originalPathColon => 'Original Path:';

  @override
  String get originalPathCopied => 'Original path copied to clipboard';

  @override
  String get restore => 'Restore';

  @override
  String get restoreItem => 'Restore Item';

  @override
  String get viewDetails => 'View Details';

  @override
  String get deletePermanently => 'Delete Permanently';

  @override
  String couldNotRestoreNamed(String name, String error) {
    return 'Could not restore \"$name\": $error';
  }

  @override
  String restoredNamed(String name) {
    return 'Restored \"$name\"';
  }

  @override
  String permanentlyDeleteConfirm(String name) {
    return 'Permanently delete \"$name\"?';
  }

  @override
  String couldNotDeleteNamed(String name, String error) {
    return 'Could not delete \"$name\": $error';
  }

  @override
  String get emptyAll => 'Empty All';

  @override
  String permanentlyDeleteAllTrash(int count, String size) {
    return 'Permanently delete all $count items ($size)? This cannot be undone.';
  }

  @override
  String couldNotEmptyTrash(String error) {
    return 'Could not empty recycle bin: $error';
  }

  @override
  String get recycleBinEmptied => 'Recycle bin emptied';

  @override
  String get restoreAllItems => 'Restore All Items';

  @override
  String restoreAllConfirm(int count) {
    return 'Restore all $count items to their original locations?';
  }

  @override
  String get restoreAll => 'Restore All';

  @override
  String restoredCountOfTotal(int done, int total) {
    return 'Restored $done of $total items';
  }

  @override
  String restoredPartialTrash(int done, int total, int failed, String sample) {
    return 'Restored $done of $total. Still in trash: $failed ($sample)';
  }

  @override
  String restoringProgress(int done, int total) {
    return 'Restoring $done / $total…';
  }

  @override
  String recycleBinSummary(int count, String size) {
    return 'Recycle Bin • $count items, $size';
  }

  @override
  String get searchTrash => 'Search Trash';

  @override
  String get filterRecycledHint => 'Filter recycled files...';

  @override
  String get recycleBinIsEmpty => 'Recycle Bin is empty';

  @override
  String get noMatchingItemsTrash => 'No matching items in trash';

  @override
  String get trashEmptyHint => 'Deleted files and folders will appear here.';

  @override
  String get connectAndBrowse => 'Connect & Browse';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get copyUri => 'Copy URI';

  @override
  String get editConfiguration => 'Edit Configuration';

  @override
  String get deleteRemote => 'Delete Remote';

  @override
  String addedRemote(String name) {
    return 'Added remote: $name';
  }

  @override
  String deleteRemoteConfirm(String name) {
    return 'Remove \"$name\"?\n\nThis only removes the saved connection from this app. Files on the remote server are not touched.';
  }

  @override
  String get connectionNoReadableDetails =>
      'This connection has no readable details. Edit it to re-enter them.';

  @override
  String testingRemote(String name) {
    return 'Testing \"$name\"…';
  }

  @override
  String connectedToRemote(String name) {
    return 'Connected to \"$name\"';
  }

  @override
  String cannotReachRemote(String name) {
    return 'Cannot reach \"$name\"';
  }

  @override
  String get noConnectionsToExport => 'No connections to export';

  @override
  String backupConnectionsCount(int count) {
    return 'Backup Connections ($count)';
  }

  @override
  String get backupConnectionsDesc =>
      'Export your configured connections as JSON. You can copy it or share/save to Files.';

  @override
  String get copyToClipboard => 'Copy to Clipboard';

  @override
  String get connectionsCopied => 'Connections copied to clipboard';

  @override
  String get shareSaveToFiles => 'Share / Save to Files';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get restoreConnections => 'Restore Connections';

  @override
  String get pasteJsonBackupHint => 'Paste JSON backup text below:';

  @override
  String importedConnections(int count, String detail) {
    return 'Imported $count connection(s)$detail';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get importAction => 'Import';

  @override
  String get searchRemotes => 'Search Remotes';

  @override
  String get addConnection => 'Add Connection';

  @override
  String get backupRestore => 'Backup / Restore';

  @override
  String get backupExport => 'Backup / Export';

  @override
  String get restoreImport => 'Restore / Import';

  @override
  String get filterRemotesHint => 'Filter remote connections...';

  @override
  String get noRemoteConnections => 'No remote connections configured';

  @override
  String get noRemoteConnectionsDesc =>
      'Connect Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP or SMB network storage.';

  @override
  String get addRemoteStorage => 'Add Remote Storage';

  @override
  String get editRemoteStorage => 'Edit Remote Storage';

  @override
  String get noMatchingConnections => 'No matching connections';

  @override
  String get addAnotherRemote => 'Add Another Remote';

  @override
  String get detailsUnavailableReconnect =>
      'Details unavailable — re-enter to reconnect';

  @override
  String get remoteActions => 'Remote actions';

  @override
  String couldNotLoadConnections(String error) {
    return 'Could not load connections: $error';
  }

  @override
  String get portMustBeNumber => 'Port must be a number.';

  @override
  String get portRangeError => 'Port must be between 1 and 65535.';

  @override
  String get connectionSuccessful => 'Connection successful!';

  @override
  String get connectionReturnedFalse => 'Connection returned false';

  @override
  String connectionFailedWithError(String error) {
    return 'Connection failed: $error';
  }

  @override
  String idAlreadyUsed(String id, String name) {
    return 'ID \"$id\" is already used by \"$name\"';
  }

  @override
  String savedOldEntryRemoveFailed(String oldId, String error) {
    return 'Saved, but the old entry \"$oldId\" could not be removed: $error';
  }

  @override
  String couldNotSave(String error) {
    return 'Could not save: $error';
  }

  @override
  String get protocolProvider => 'Protocol / Provider';

  @override
  String get providerS3 => 'Amazon S3 / S3-Compatible (MinIO, R2)';

  @override
  String get providerOss => 'Aliyun OSS';

  @override
  String get providerWebdav => 'WebDAV (Nextcloud, OwnCloud)';

  @override
  String get providerSftp => 'SFTP (SSH File Transfer)';

  @override
  String get providerFtp => 'FTP / FTPS';

  @override
  String get providerSmb => 'SMB / Windows Share (Samba)';

  @override
  String get displayName => 'Display Name';

  @override
  String get pleaseEnterName => 'Please enter a name';

  @override
  String get identifierLabel => 'Identifier / ID (e.g. sftp_mac, my_nas)';

  @override
  String get identifierHint => 'Used in remote paths: remote://id/...';

  @override
  String get generateIdTooltip => 'Generate clean ID from Name';

  @override
  String get pleaseEnterId => 'Please enter an identifier';

  @override
  String get idCharsetError =>
      'Identifier may only contain letters, numbers, hyphens and underscores';

  @override
  String get bucketNameOptional =>
      'Bucket Name (Optional, empty for all buckets)';

  @override
  String get bucketNameOptionalHint =>
      'Leave empty to browse all buckets, or comma-separated';

  @override
  String get regionLabel => 'Region (e.g. us-east-1, auto)';

  @override
  String get usePathStyle => 'Use Path-Style (for MinIO / local S3)';

  @override
  String get accessKeyId => 'Access Key ID';

  @override
  String get secretAccessKey => 'Secret Access Key';

  @override
  String get showSecretKey => 'Show secret key';

  @override
  String get hideSecretKey => 'Hide secret key';

  @override
  String get webdavUrlLabel => 'WebDAV URL (e.g. https://example.com/dav)';

  @override
  String get urlRequired => 'URL is required';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get authMethod => 'Authentication Method';

  @override
  String get authPassword => 'Password';

  @override
  String get authPrivateKey => 'Private Key';

  @override
  String get privateKeyLabel => 'Private Key';

  @override
  String get privateKeyHint => 'Paste OpenSSH / PEM private key content here';

  @override
  String get privateKeyRequired => 'Private key is required';

  @override
  String get selectKeyFile => 'Select Key File';

  @override
  String get passphraseLabel => 'Passphrase (Optional)';

  @override
  String get passphraseHint => 'Leave empty if key is not encrypted';

  @override
  String get showPassphrase => 'Show passphrase';

  @override
  String get hidePassphrase => 'Hide passphrase';

  @override
  String failedToReadKeyFile(String error) {
    return 'Failed to read key file: $error';
  }

  @override
  String get hostIp => 'Host / IP';

  @override
  String get hostRequired => 'Host is required';

  @override
  String get numbersOnly => 'Numbers only';

  @override
  String get portRangeShort => 'Use 1–65535';

  @override
  String get remoteRootPath => 'Remote Root Path';

  @override
  String get ftpCleartextWarning =>
      'FTP is not encrypted: the password and files travel in cleartext. Use SFTP or FTPS on untrusted networks.';

  @override
  String get clearTempCacheQuestion => 'Clear Temporary Cache?';

  @override
  String clearTempCacheDesc(String size) {
    return 'This will delete $size of temporary thumbnail, media, and preview cache. Your saved files and connections are safe.';
  }

  @override
  String get tempCacheCleared => 'Temporary cache cleared';

  @override
  String couldNotClearCache(String error) {
    return 'Could not clear cache: $error';
  }

  @override
  String get temporaryCache => 'Temporary Cache';

  @override
  String get appInfoCopied => 'App info copied to clipboard';

  @override
  String get supportedProtocolsCopied =>
      'Supported protocols copied to clipboard';

  @override
  String buildLabel(String time) {
    return 'Build: $time';
  }

  @override
  String platformLabel(String platform) {
    return 'Platform: $platform';
  }

  @override
  String couldNotReadStorageStats(String error) {
    return 'Could not read storage stats: $error';
  }

  @override
  String couldNotClearArchiveCache(String error) {
    return 'Could not clear archive cache: $error';
  }

  @override
  String get archiveCacheCleared => 'Archive cache cleared';

  @override
  String emptyTrashUtilityConfirm(int count) {
    return 'Permanently delete all $count items? This cannot be undone.';
  }

  @override
  String couldNotEmptyTrashError(String error) {
    return 'Could not empty trash: $error';
  }

  @override
  String get chooseSharedFolder => 'Choose shared folder';

  @override
  String portValidationError(String port) {
    return 'Port must be a number between 1 and 65535 (got \"$port\")';
  }

  @override
  String failedToStartServer(String error) {
    return 'Failed to start server: $error';
  }

  @override
  String get couldNotStopLanServer => 'Could not stop the LAN server';

  @override
  String get documentsDir => 'Documents';

  @override
  String errorFolderNotFound(String raw) {
    return 'This folder no longer exists. It may have been deleted or renamed.\n($raw)';
  }

  @override
  String errorPermissionDenied(String raw) {
    return 'Permission denied. Grant storage access or pick another folder.\n($raw)';
  }

  @override
  String errorSignInFailed(String raw) {
    return 'Sign-in failed. Check the username and password.\n($raw)';
  }

  @override
  String errorServerTimeout(String raw) {
    return 'The server took too long to respond. Check the address and your network.\n($raw)';
  }

  @override
  String errorCannotReachServer(String raw) {
    return 'Cannot reach the server. Check the address, port and your network.\n($raw)';
  }

  @override
  String get playLabel => 'Play';

  @override
  String get pauseLabel => 'Pause';

  @override
  String get webdavCleartextWarning =>
      'This URL uses http:// — the password and files travel unencrypted. Use https:// if the server supports it.';

  @override
  String get selectThisFolder => 'Select this folder';

  @override
  String get selectFolderAction => 'Select';

  @override
  String get lanSharingDesc =>
      'Share a local folder over Wi-Fi so any browser on the same network can browse or download files.';

  @override
  String get receivedShareTitle => 'Received Shared Files';

  @override
  String get receivedShareSingle => 'Received 1 file';

  @override
  String receivedShareCount(int count) {
    return 'Received $count files';
  }

  @override
  String get saveToLocal => 'Save to Local';

  @override
  String get saveToLocalSubtitle => 'Choose a local folder to save';

  @override
  String get saveToRemote => 'Save to Remote';

  @override
  String get saveToRemoteSubtitle => 'Upload to cloud storage, WebDAV or SFTP';

  @override
  String get openDirectly => 'Open Directly';

  @override
  String get openDirectlySubtitle => 'View or play directly in app';

  @override
  String get selectRemoteStorage => 'Select Remote Storage';

  @override
  String get noRemotesConfigured => 'No Remote Storage';

  @override
  String get noRemotesPrompt =>
      'No remote storage configured yet. Would you like to add one?';

  @override
  String get savingSharedFiles => 'Saving shared files...';

  @override
  String get savedSharedFilesSuccess => 'Shared files saved successfully';

  @override
  String get view => 'View';

  @override
  String get invalidFileNameError =>
      'Name cannot contain \"/\", \"\\\", or be \".\" or \"..\"';

  @override
  String get batchRename => 'Batch Rename';

  @override
  String batchRenameTitle(int count) {
    return 'Batch Rename ($count items)';
  }

  @override
  String get batchRenameSubtitle =>
      'Add prefix/suffix, find & replace, or sequential numbering';

  @override
  String get batchRenameModePrefixSuffix => 'Prefix / Suffix';

  @override
  String get batchRenameModeFindReplace => 'Find & Replace';

  @override
  String get batchRenameModeNumbering => 'Numbering';

  @override
  String get batchRenamePrefix => 'Prefix';

  @override
  String get batchRenamePrefixHint => 'e.g. [2026] ';

  @override
  String get batchRenameSuffix => 'Suffix';

  @override
  String get batchRenameSuffixHint => 'e.g. _final';

  @override
  String get batchRenameFindText => 'Find text';

  @override
  String get batchRenameReplaceWith => 'Replace with';

  @override
  String get batchRenameBaseName => 'Base name';

  @override
  String get batchRenameStartNumber => 'Start number';

  @override
  String get batchRenamePaddingDigits => 'Digits';

  @override
  String batchRenameDigitsOption(int digits, String example) {
    return '$digits digits ($example)';
  }

  @override
  String get batchRenameKeepExtension => 'Keep file extension';

  @override
  String get batchRenamePreview => 'Live Preview';

  @override
  String get batchRenameEmptyName => '(empty name)';

  @override
  String batchRenameProgress(int done, int total) {
    return 'Renaming $done / $total...';
  }

  @override
  String batchRenameApply(int count) {
    return 'Apply Rename ($count)';
  }

  @override
  String get batchRenameComplete => 'Batch rename complete';

  @override
  String get batchRenameNoChanges => 'No filenames will change';

  @override
  String get batchRenameErrorEmpty => 'One or more target names are empty';

  @override
  String batchRenameErrorDuplicate(String name) {
    return 'Duplicate target name: \"$name\"';
  }

  @override
  String batchRenameErrorExists(String name) {
    return 'Target already exists: \"$name\"';
  }

  @override
  String selectedItemsDetailsTitle(int count) {
    return '$count selected items';
  }

  @override
  String get selectedFilesSizeLabel => 'Selected files size';

  @override
  String get currentDirectoryLabel => 'Current directory';

  @override
  String get bookmarkSortModeTooltip => 'Sort order';

  @override
  String get bookmarkSortCustom => 'Custom (drag to reorder)';

  @override
  String get bookmarkSortNameAsc => 'Name ascending (A–Z)';

  @override
  String get bookmarkSortNameDesc => 'Name descending (Z–A)';

  @override
  String get videoFitLabel => 'Aspect ratio';

  @override
  String get videoFitContain => 'Fit';

  @override
  String get videoFitCover => 'Crop';

  @override
  String get videoFitFill => 'Stretch';

  @override
  String videoFitChanged(String mode) {
    return 'Aspect ratio: $mode';
  }

  @override
  String audioTracksTitle(int count) {
    return 'Audio Tracks ($count)';
  }

  @override
  String get audioTrackMenu => 'Audio track';

  @override
  String get noAudioTracks => 'No selectable audio tracks';

  @override
  String get audioTrackDefault => 'Auto (Default)';

  @override
  String audioTrackItem(String id) {
    return 'Audio track $id';
  }

  @override
  String subtitleTracksTitle(int count) {
    return 'Subtitles ($count)';
  }

  @override
  String get subtitleTrackMenu => 'Subtitles';

  @override
  String get subtitlesOff => 'Off';

  @override
  String subtitleTrackItem(String id) {
    return 'Subtitle $id';
  }

  @override
  String get sleepTimerTitle => 'Sleep Timer';

  @override
  String get sleepTimerOff => 'Off';

  @override
  String get sleepTimerOffToast => 'Sleep timer turned off';

  @override
  String sleepTimerMinutes(int minutes) {
    return 'Stop in $minutes min';
  }

  @override
  String sleepTimerMinutesToast(int minutes) {
    return 'Playback will stop in $minutes min';
  }

  @override
  String get sleepTimerEndOfTrack => 'Stop at end of current track';

  @override
  String get sleepTimerEndOfTrackToast =>
      'Playback will stop after current track';

  @override
  String get sleepTimerEndOfTrackShort => 'End of track';

  @override
  String sleepTimerMenuRemaining(String remaining) {
    return 'Sleep timer ($remaining)';
  }

  @override
  String get readOnlyViewMode => 'Read-only view';

  @override
  String get privacyFolder => 'Privacy Folder';

  @override
  String get privacyFolders => 'Privacy Folders';

  @override
  String get privacyFoldersDesc =>
      'Create, unlock, back up, or import isolated privacy folders';

  @override
  String get createPrivacyFolder => 'Create Privacy Folder';

  @override
  String get openPrivacyFolder => 'Open Privacy Folder';

  @override
  String get backupPrivacyFolder => 'Back Up Privacy Folder';

  @override
  String get importPrivacyFolder => 'Import Privacy Folder';

  @override
  String get privacyFolderName => 'Folder Name';

  @override
  String get privacyFolderNameHint => 'Enter exact folder name';

  @override
  String get privacyFolderNotFound => 'Privacy folder does not exist';

  @override
  String get privacyFolderAlreadyExists =>
      'A privacy folder with this name already exists';

  @override
  String get credentialMethod => 'Unlock Credential';

  @override
  String get credentialPassword => 'Standalone Password (8–128 chars)';

  @override
  String get credentialSystem => 'System Unlock (Passcode / Biometrics)';

  @override
  String get credentialSystemUnavailable =>
      'System unlock is not supported on this device';

  @override
  String get encryptionAlgorithm => 'Encryption Method';

  @override
  String get cipherNone => 'No Encryption';

  @override
  String get cipherAes128Gcm => 'AES-128-GCM (Default, hardware accelerated)';

  @override
  String get cipherAes256Gcm => 'AES-256-GCM (Hardware accelerated)';

  @override
  String get storageLocation => 'Storage Location';

  @override
  String get useDefaultLocation => 'Default';

  @override
  String get changeLocation => 'Change';

  @override
  String get privacyPasswordLabel => 'Password (8–128 chars, symbols allowed)';

  @override
  String get privacyConfirmPasswordLabel => 'Confirm Password';

  @override
  String get passwordLengthError => 'Password must be 8 to 128 characters';

  @override
  String get passwordMismatchError => 'Passwords do not match';

  @override
  String get privacyUnlockedLabel =>
      'Unlocked privacy folder • Auto-hides on exit or 10m background';

  @override
  String get lockAndHide => 'Lock & Hide';

  @override
  String lockAllPrivacyFolders(int count) {
    return 'Lock & Hide All ($count)';
  }

  @override
  String vaultLockedNotice(String name) {
    return 'Privacy folder \"$name\" locked and hidden';
  }

  @override
  String get nextStep => 'Next';

  @override
  String get unlockAction => 'Unlock';

  @override
  String unlockWithSystemPrompt(String name) {
    return 'Authenticate to unlock privacy folder \"$name\"';
  }

  @override
  String get setupSystemAuthPrompt =>
      'Authenticate to set up system unlock for privacy folder';

  @override
  String get wrongCredentialError => 'Incorrect password or credential';

  @override
  String cooldownRetryError(int seconds) {
    return 'Too many failed attempts, retry in ${seconds}s';
  }

  @override
  String get selectBackupSourceVault => 'Select unlocked folder or enter name';

  @override
  String get backupPasswordRequiredNotice =>
      'This folder uses system unlock. Set an 8–128 char backup password so the archive can be imported on any device.';

  @override
  String get backupPasswordLabel => 'Backup Password (8–128 chars)';

  @override
  String get selectBackupDestFile => 'Choose Backup Output Folder';

  @override
  String backupExportSuccess(String path) {
    return 'Backup exported to: $path';
  }

  @override
  String get selectBackupArchive => 'Select .fpmvault Backup File';

  @override
  String backupArchiveSummary(String cipher, int count) {
    return 'Cipher: $cipher • Objects: $count';
  }

  @override
  String get backupPasswordToVerify => 'Backup / Vault Password';

  @override
  String get localUnlockAfterImport => 'Unlock Method After Import';

  @override
  String get newLocalPasswordOptional =>
      'New Local Password (blank to reuse backup password)';

  @override
  String importSuccessNotice(String name) {
    return 'Privacy folder \"$name\" imported and unlocked';
  }

  @override
  String get saveToPrivacyFolder => 'Save to Privacy Folder';

  @override
  String get saveToPrivacyFolderSubtitle =>
      'Encrypt and save into an unlocked privacy folder';

  @override
  String get selectPrivacyFolder => 'Select Privacy Folder';

  @override
  String get privacyFolderNoHistoryBookmark =>
      'History and public bookmarks are disabled inside privacy folders';

  @override
  String get unlockedBadge => 'Unlocked';

  @override
  String importKeepOriginalName(String name) {
    return 'Original folder name will be kept: \"$name\"';
  }

  @override
  String get importWillKeepOriginalName =>
      'Original folder name will be preserved automatically. If it already exists, you will be prompted to enter a new name.';

  @override
  String importNameExistsEnterNew(String name) {
    return 'Privacy folder \"$name\" already exists. Please enter a new folder name.';
  }

  @override
  String get importNewFolderNameLabel => 'New Privacy Folder Name';

  @override
  String get importEnterFolderNamePrompt =>
      'This backup does not contain the original folder name. Please enter a folder name.';

  @override
  String get renamePrivacyFolder => 'Rename Privacy Folder';

  @override
  String privacyFolderRenamedNotice(String name) {
    return 'Privacy folder renamed to \"$name\"';
  }

  @override
  String largeFilePagedNotice(String start, String end, String total) {
    return 'Large file read-only mode ($start – $end / $total)';
  }

  @override
  String get previousPage => 'Previous Page';

  @override
  String get nextPage => 'Next Page';

  @override
  String get jumpToPosition => 'Jump to Position';

  @override
  String get deletePrivacyFolder => 'Delete Privacy Folder';

  @override
  String deletePrivacyFolderWarning(String name) {
    return 'This will permanently delete privacy folder \"$name\" and all encrypted files inside it, along with its stored key on this device. This action cannot be undone.';
  }

  @override
  String deletePrivacyFolderConfirmLabel(String name) {
    return 'Type \"$name\" to confirm deletion';
  }

  @override
  String privacyFolderDeletedNotice(String name) {
    return 'Privacy folder \"$name\" has been permanently deleted';
  }

  @override
  String get privacyMediaAudio => 'Private Audio';

  @override
  String get privacyMediaVideo => 'Private Video';

  @override
  String get vaultAutoLockTitle => 'Auto-lock in background';

  @override
  String get vaultAutoLockImmediate => 'Immediately';

  @override
  String vaultAutoLockMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get vaultAutoLockNever => 'Never';

  @override
  String get vaultConfirmExternalOpenTitle =>
      'Confirm before external open & share';

  @override
  String get vaultConfirmExternalOpenDesc =>
      'Warn before exporting a decrypted temporary copy to other apps';

  @override
  String get vaultExternalOpenWarningTitle => 'Open with external app?';

  @override
  String get vaultExternalOpenWarningBody =>
      'This file will be temporarily decrypted and passed to another app outside the privacy folder. Remove any saved copy in that app afterward if needed.';

  @override
  String get dontAskAgain => 'Don\'t ask again';

  @override
  String get continueAction => 'Continue';

  @override
  String get vaultVideoThumbnailsTitle => 'Privacy folder video thumbnails';

  @override
  String get vaultVideoThumbnailsDesc =>
      'Decode and cache encrypted video preview frames on demand (off by default to save battery)';

  @override
  String get vaultSecuritySettings => 'Password & Unlock Method';

  @override
  String get vaultChangePasswordOption => 'Change password';

  @override
  String get vaultSwitchToSystemOption => 'Switch to system unlock';

  @override
  String get vaultSwitchToPasswordOption => 'Switch to separate password';

  @override
  String get vaultCurrentPasswordLabel => 'Current password';

  @override
  String get vaultNewPasswordLabel => 'New password (8–128 chars)';

  @override
  String get vaultOldBackupsPasswordNotice =>
      'Existing .fpmvault backup archives exported earlier still require the password used when they were created.';

  @override
  String get vaultSwitchToSystemBackupNotice =>
      'Keep a .fpmvault backup in a safe place. If you move to another device, Keychain/Keystore keys will not migrate encrypted folders.';

  @override
  String get vaultSecurityUpdatedNotice =>
      'Privacy folder security settings updated';

  @override
  String get vaultFolderInfo => 'Folder Info & Storage';

  @override
  String get vaultStatsFiles => 'Files';

  @override
  String get vaultStatsFolders => 'Subfolders';

  @override
  String get vaultStatsPlainSize => 'Content Size';

  @override
  String get vaultStatsDiskUsage => 'Disk Usage';

  @override
  String get vaultStatsOrphaned => 'Reclaimable Orphaned Data';

  @override
  String vaultStatsOrphanDetail(int count, String size) {
    return '$count items ($size)';
  }

  @override
  String get vaultCleanupOrphansAction => 'Clean Up Orphaned Space';

  @override
  String vaultCleanupResultNotice(int count, String size) {
    return 'Removed $count orphaned files and freed $size';
  }

  @override
  String backupProgressLabel(String done, String total, int percent) {
    return '$done / $total ($percent%)';
  }

  @override
  String get backupCancelling => 'Cancelling…';

  @override
  String get backupCancelledNotice => 'Backup operation cancelled';

  @override
  String get deleteVaultPermanentWarning =>
      'This will permanently delete the selected items from the privacy folder without moving them to the Recycle Bin.';

  @override
  String get showQrCode => 'Show QR Code';

  @override
  String get scanQrToConnect => 'Scan with your phone to open in browser';

  @override
  String get newTab => 'New Tab';

  @override
  String get closeTab => 'Close Tab';

  @override
  String get openInNewTab => 'Open in New Tab';

  @override
  String get copyToOtherPane => 'Copy to Other Pane';

  @override
  String get moveToOtherPane => 'Move to Other Pane';

  @override
  String get pdfViewerTitle => 'PDF Viewer';

  @override
  String pdfPageOf(int current, int total) {
    return 'Page $current / $total';
  }

  @override
  String get pdfSearchHint => 'Search text in PDF…';

  @override
  String get pdfJumpToPage => 'Jump to page';

  @override
  String get pdfOutline => 'Table of Contents';

  @override
  String get pdfNoOutline => 'No outline in this document';

  @override
  String get pdfZeroDiskBadge => 'In-Memory · Zero Disk';

  @override
  String get scanLanDevices => 'Scan LAN Devices';

  @override
  String get scanningLan => 'Scanning local network…';

  @override
  String get noLanDevicesFound =>
      'No SMB / SFTP / WebDAV / FTP devices found on LAN';

  @override
  String get storageAnalyzer => 'Storage Analyzer';

  @override
  String get storageAnalyzerSubtitle =>
      'Folder size ranking, file types & largest files';

  @override
  String get topFolders => 'Largest Folders';

  @override
  String get topFiles => 'Largest Files';

  @override
  String get fileTypesBreakdown => 'By File Type';

  @override
  String storageUsedOf(String used, String total, String free) {
    return '$used used of $total ($free free)';
  }

  @override
  String get duplicateFinder => 'Duplicate Finder';

  @override
  String get duplicateFinderSubtitle =>
      '3-stage SHA-256 duplicate scan & cleanup';

  @override
  String get keepNewest => 'Keep Newest';

  @override
  String get keepOldest => 'Keep Oldest';

  @override
  String get keepShortestPath => 'Keep Shortest Path';

  @override
  String cleanSelectedDuplicates(int count) {
    return 'Clean Selected ($count)';
  }

  @override
  String wastedSpace(String size) {
    return 'Reclaimable: $size';
  }

  @override
  String get noDuplicatesFound => 'No duplicate files found';

  @override
  String get categoryDocuments => 'Documents';

  @override
  String get categoryVideos => 'Videos';

  @override
  String get categoryAudio => 'Audio';

  @override
  String get categoryArchives => 'Archives';

  @override
  String get categoryDownloads => 'Downloads';

  @override
  String get categoryApks => 'Installers';

  @override
  String get globalSearchHint => 'Search files, bookmarks & recent…';

  @override
  String get advancedSearch => 'Advanced Search';

  @override
  String get grepContentSearch => 'Content Search (Grep)';

  @override
  String get matchContains => 'Contains';

  @override
  String get matchWildcard => 'Wildcard (* ?)';

  @override
  String get matchRegex => 'Regex';

  @override
  String get minSizeMb => 'Min size (MB)';

  @override
  String get maxSizeMb => 'Max size (MB)';

  @override
  String get modifiedDaysAgo => 'Modified within (days)';

  @override
  String get pauseTask => 'Pause';

  @override
  String get resumeTask => 'Resume';

  @override
  String retryFailedItems(int count) {
    return 'Retry Failed ($count)';
  }

  @override
  String get taskPaused => 'Paused';

  @override
  String get rateLimitLabel => 'Speed Limit';

  @override
  String get rateLimitUnlimited => 'Unlimited';

  @override
  String get encryptWithPassword => 'Encrypt with password (AES-256)';

  @override
  String get archivePasswordRequired => 'Archive Password Required';

  @override
  String get archivePasswordHint => 'Enter archive password';

  @override
  String get archiveWrongPassword => 'Incorrect archive password';

  @override
  String get subtitles => 'Subtitles';

  @override
  String get subtitleOff => 'Off';

  @override
  String get loadExternalSubtitle => 'Load Subtitle from Files…';

  @override
  String subtitleAutoLoaded(String name) {
    return 'Loaded subtitle: $name';
  }

  @override
  String get pictureInPicture => 'Picture in Picture';

  @override
  String get directorySync => 'Directory Sync & Backup';

  @override
  String get directorySyncSubtitle =>
      'Incremental, mirror or two-way sync across local & remote';

  @override
  String get syncModeIncremental => 'Incremental (Copy new & updated)';

  @override
  String get syncModeMirror => 'Mirror (Exact copy, deletes extra files)';

  @override
  String get syncModeBidirectional => 'Two-Way Sync';

  @override
  String get syncPreviewChanges => 'Preview Changes';

  @override
  String get syncStart => 'Start Sync';

  @override
  String get syncNoChanges => 'Directories are already in sync';

  @override
  String get offlinePinned => 'Offline Pinned Files';

  @override
  String get offlinePinnedSubtitle => 'Managed offline copies of remote files';

  @override
  String get pinOffline => 'Pin for Offline';

  @override
  String get unpinOffline => 'Remove Offline Pin';

  @override
  String pinnedOfflineNotice(String name) {
    return 'Pinned \"$name\" for offline access';
  }

  @override
  String get checksumsTitle => 'Checksums (MD5 / SHA-1 / SHA-256)';

  @override
  String get computeChecksums => 'Compute Checksums';

  @override
  String get expectedHashHint => 'Paste expected hash to verify…';

  @override
  String get hashMatches => 'Checksum matches';

  @override
  String get hashMismatch => 'Checksum does NOT match';

  @override
  String get structuredView => 'Structured View';

  @override
  String get rawTextView => 'Raw Text';

  @override
  String get copyJsonPath => 'Copy Path';

  @override
  String get compareDiff => 'Compare Diff';

  @override
  String get diffUnified => 'Unified';

  @override
  String get diffSideBySide => 'Side-by-Side';

  @override
  String get diffOnlyInLeft => 'Only in Left';

  @override
  String get diffOnlyInRight => 'Only in Right';

  @override
  String get diffModified => 'Modified';

  @override
  String get diffIdentical => 'Identical';

  @override
  String get unixPermissions => 'Unix Permissions (chmod)';

  @override
  String get permOwner => 'Owner';

  @override
  String get permGroup => 'Group';

  @override
  String get permOther => 'Other';

  @override
  String get applyPermissions => 'Apply Permissions';

  @override
  String permissionsUpdated(String mode) {
    return 'Permissions updated to $mode';
  }

  @override
  String get lockVaultNow => 'Lock Now';

  @override
  String get deleteOriginalAfterImport =>
      'Delete original file after importing to vault';

  @override
  String get vaultExternalOpenNotice =>
      'Opening this file in an external app writes a temporary plaintext copy. Locking the privacy folder automatically deletes all temporary plaintext copies.';

  @override
  String get shareViaLan => 'Share via LAN';

  @override
  String get calculateDirSize => 'Calculate';

  @override
  String activeTasksBanner(int count) {
    return '$count active transfer(s)';
  }

  @override
  String get jsonFormattedPreview => 'Formatted';

  @override
  String get jsonTreeView => 'Tree';

  @override
  String jsonIndentSpaces(int count) {
    return '$count spaces';
  }

  @override
  String get jsonSortKeys => 'Sort keys';

  @override
  String get jsonCopyFormatted => 'Copy formatted JSON';

  @override
  String get jsonCopyMinified => 'Copy minified JSON';

  @override
  String get jsonCopiedFormatted => 'Formatted JSON copied';

  @override
  String get jsonCopiedMinified => 'Minified JSON copied';

  @override
  String get jsonInvalidFormat => 'Invalid JSON format';

  @override
  String get jsonExpandAll => 'Expand all';

  @override
  String get jsonCollapseAll => 'Collapse all';

  @override
  String get jsonFormatInEditor => 'Format JSON';

  @override
  String jsonLinesCount(int count) {
    return '$count lines';
  }

  @override
  String jsonMatchesCount(int current, int total) {
    return '$current/$total matches';
  }

  @override
  String get vaultAlwaysVisibleTitle => 'Always Show';

  @override
  String get vaultAlwaysVisibleDesc =>
      'Keep this privacy folder visible when locked. Opening it still requires authentication and respects auto-lock timeout.';

  @override
  String get lockedBadge => 'Locked';

  @override
  String get vaultUnlockToOpen => 'Unlock & Open';

  @override
  String get vaultUnpinAlwaysVisible => 'Stop Always Showing';

  @override
  String vaultPinnedNotice(String name) {
    return 'Privacy folder \"$name\" set to always show';
  }

  @override
  String vaultUnpinnedNotice(String name) {
    return 'Privacy folder \"$name\" will hide when locked';
  }

  @override
  String vaultLockedKeepVisibleNotice(String name) {
    return 'Privacy folder \"$name\" locked';
  }

  @override
  String get searchCategoryAll => 'All Types';

  @override
  String get searchCategoryCode => 'Code';

  @override
  String get searchCategoryFolders => 'Folders';

  @override
  String get searchFilesAndFolders => 'Files & Folders';

  @override
  String get searchEnterQueryHint =>
      'Type to search files, folders, bookmarks, remotes & history';

  @override
  String get searchingFilesProgress => 'Searching files…';

  @override
  String get collapseSidebar => 'Collapse sidebar';

  @override
  String get expandSidebar => 'Expand sidebar';

  @override
  String get categoryAllFilter => 'All';

  @override
  String categorySummary(int count, String size) {
    return '$count items · $size';
  }

  @override
  String categoryScanning(String category) {
    return 'Scanning $category…';
  }

  @override
  String categoryEmptyTitle(String category) {
    return 'No $category found';
  }

  @override
  String get categoryEmptySubtitle =>
      'Files in this category will appear here automatically.';

  @override
  String get locateInFolder => 'Locate in folder';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String filterCategoryHint(String category) {
    return 'Filter in $category…';
  }

  @override
  String get historyRetentionTitle => 'History retention';

  @override
  String get historyRetentionDesc =>
      'Entries older than this are automatically removed. Set to 0 to disable history.';

  @override
  String historyRetentionDaysLabel(int days) {
    return 'Keep for $days days';
  }

  @override
  String historyRetentionDaysShort(int days) {
    return '${days}d';
  }

  @override
  String get historyRetentionDisabled => 'Do not retain (0 days)';

  @override
  String get historyRetentionDisabledShort => 'Off';

  @override
  String get historyRetentionInputLabel => 'Retention days (0 = do not retain)';

  @override
  String get historyRetentionInvalidInput =>
      'Enter a non-negative whole number';

  @override
  String historyRetentionUpdatedDays(int days) {
    return 'History retention set to $days days';
  }

  @override
  String get historyRetentionUpdatedOff =>
      'History retention disabled and existing history cleared';

  @override
  String get historyDisabledTitle => 'History is disabled';

  @override
  String get historyDisabledSubtitle =>
      'Retention is set to 0 days, so visited folders are not saved.';

  @override
  String get historyRetentionChange => 'Change retention';
}
