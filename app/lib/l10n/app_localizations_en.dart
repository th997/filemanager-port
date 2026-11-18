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
  String get cancelling => 'Cancelling…';

  @override
  String get cannotCancelTask => 'This task cannot be cancelled';

  @override
  String cannotClearFinishedTasks(Object count) {
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
  String compressFailed(Object error) {
    return 'Compress failed: $error';
  }

  @override
  String get compressing => 'Compressing…';

  @override
  String get connectServer => 'Connect a server';

  @override
  String get copyError => 'Copy Error';

  @override
  String copyFailed(Object error) {
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
  String createdCandidate(Object name) {
    return 'Created \"$name\"';
  }

  @override
  String get creatingCopy => 'Creating copy…';

  @override
  String get darkTheme => 'Dark theme';

  @override
  String get delete => 'Delete';

  @override
  String deleteFailed(Object error) {
    return 'Delete failed: $error';
  }

  @override
  String deletedCount(Object count) {
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
  String downloadFailed(Object error) {
    return 'Download failed: $error';
  }

  @override
  String downloadedTo(Object path) {
    return 'Downloaded to $path';
  }

  @override
  String downloadingFile(Object file) {
    return 'Downloading $file…';
  }

  @override
  String get downloadingFiles => 'Downloading files…';

  @override
  String downloadingItem(Object name) {
    return 'Downloading $name…';
  }

  @override
  String duplicateFailed(Object error) {
    return 'Duplicate failed: $error';
  }

  @override
  String get emptyRecycleBin => 'Empty Recycle Bin';

  @override
  String get errorCopied => 'Error copied to clipboard';

  @override
  String get exportPreviewCache => 'Export & Preview Cache';

  @override
  String extractFailed(Object error) {
    return 'Extract failed: $error';
  }

  @override
  String get extracting => 'Extracting…';

  @override
  String get failed => 'Failed';

  @override
  String failedToCreate(Object error) {
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
  String hoursLeft(Object hours) {
    return 'About $hours hours left';
  }

  @override
  String hoursMinutesLeft(Object hours, Object minutes) {
    return 'About $hours hr $minutes min left';
  }

  @override
  String get inProgress => 'In progress';

  @override
  String get invertSelection => 'Invert Selection';

  @override
  String itemsCount(Object count) {
    return '$count items';
  }

  @override
  String itemsOutOfTotal(Object completed, Object total) {
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
  String minutesLeft(Object minutes) {
    return 'About $minutes min left';
  }

  @override
  String moveFailed(Object error) {
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
  String retryFailed(Object error) {
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
  String secondsLeft(Object seconds) {
    return 'About $seconds sec left';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get selectFolderToUpload => 'Select Folder to Upload';

  @override
  String get selectItems => 'Select items';

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
  String sharePasswordNotice(Object pwd) {
    return 'Generated share password: $pwd';
  }

  @override
  String get shared => 'Shared';

  @override
  String get sharedPathCopied => 'Shared path copied';

  @override
  String get showHiddenFiles => 'Show hidden files';

  @override
  String skippedAlreadyExists(Object count) {
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
  String get transferring => 'Transferring…';

  @override
  String trashCountNotice(Object count) {
    return '$count items in trash';
  }

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
  String uploadingFolder(Object folder) {
    return 'Uploading folder \"$folder\"…';
  }

  @override
  String uploadingItems(Object count) {
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
}
