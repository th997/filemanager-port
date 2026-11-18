import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About & System'**
  String get aboutSection;

  /// No description provided for @accentClassicBlue.
  ///
  /// In en, this message translates to:
  /// **'Classic blue'**
  String get accentClassicBlue;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get accentColor;

  /// No description provided for @accentDeepTeal.
  ///
  /// In en, this message translates to:
  /// **'Deep teal'**
  String get accentDeepTeal;

  /// No description provided for @accentDynamic.
  ///
  /// In en, this message translates to:
  /// **'System dynamic'**
  String get accentDynamic;

  /// No description provided for @accentForest.
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get accentForest;

  /// No description provided for @accentGrape.
  ///
  /// In en, this message translates to:
  /// **'Grape'**
  String get accentGrape;

  /// No description provided for @accentIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get accentIndigo;

  /// No description provided for @accentSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get accentSunset;

  /// No description provided for @allPhotos.
  ///
  /// In en, this message translates to:
  /// **'All photos'**
  String get allPhotos;

  /// No description provided for @almostDone.
  ///
  /// In en, this message translates to:
  /// **'Almost done'**
  String get almostDone;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'FP File Manager'**
  String get appTitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @ascending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @browseInAppUpload.
  ///
  /// In en, this message translates to:
  /// **'Browse In-App to Upload…'**
  String get browseInAppUpload;

  /// No description provided for @browserSection.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get browserSection;

  /// No description provided for @bucketName.
  ///
  /// In en, this message translates to:
  /// **'Bucket Name'**
  String get bucketName;

  /// No description provided for @bucketNameHint.
  ///
  /// In en, this message translates to:
  /// **'Lowercase letters, numbers, hyphens (3-63 chars)'**
  String get bucketNameHint;

  /// No description provided for @bucketRootFolderUploadError.
  ///
  /// In en, this message translates to:
  /// **'You are at the multi-bucket root. Please enter a bucket first before uploading a folder.'**
  String get bucketRootFolderUploadError;

  /// No description provided for @bucketRootTransferError.
  ///
  /// In en, this message translates to:
  /// **'You are at the multi-bucket root. Please enter a bucket first before transferring items.'**
  String get bucketRootTransferError;

  /// No description provided for @bucketRootUploadError.
  ///
  /// In en, this message translates to:
  /// **'You are at the multi-bucket root. Please enter a bucket first before uploading files.'**
  String get bucketRootUploadError;

  /// No description provided for @bufferDuration.
  ///
  /// In en, this message translates to:
  /// **'Buffer Duration'**
  String get bufferDuration;

  /// No description provided for @bufferSize.
  ///
  /// In en, this message translates to:
  /// **'Buffer Size'**
  String get bufferSize;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelTask.
  ///
  /// In en, this message translates to:
  /// **'Cancel task'**
  String get cancelTask;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @cancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get cancelling;

  /// No description provided for @cannotCancelTask.
  ///
  /// In en, this message translates to:
  /// **'This task cannot be cancelled'**
  String get cannotCancelTask;

  /// No description provided for @cannotClearFinishedTasks.
  ///
  /// In en, this message translates to:
  /// **'{count} finished task(s) could not be cleared'**
  String cannotClearFinishedTasks(Object count);

  /// No description provided for @cannotDismissTask.
  ///
  /// In en, this message translates to:
  /// **'Could not dismiss task'**
  String get cannotDismissTask;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get clearFinished;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @cloudRemoteStorage.
  ///
  /// In en, this message translates to:
  /// **'Cloud & Remote Storage'**
  String get cloudRemoteStorage;

  /// No description provided for @cloudToolsSettings.
  ///
  /// In en, this message translates to:
  /// **'Cloud, Tools & Settings'**
  String get cloudToolsSettings;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @compressFailed.
  ///
  /// In en, this message translates to:
  /// **'Compress failed: {error}'**
  String compressFailed(Object error);

  /// No description provided for @compressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing…'**
  String get compressing;

  /// No description provided for @connectServer.
  ///
  /// In en, this message translates to:
  /// **'Connect a server'**
  String get connectServer;

  /// No description provided for @copyError.
  ///
  /// In en, this message translates to:
  /// **'Copy Error'**
  String get copyError;

  /// No description provided for @copyFailed.
  ///
  /// In en, this message translates to:
  /// **'Copy failed: {error}'**
  String copyFailed(Object error);

  /// No description provided for @copyPassword.
  ///
  /// In en, this message translates to:
  /// **'Copy password'**
  String get copyPassword;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @copyingFiles.
  ///
  /// In en, this message translates to:
  /// **'Copying files…'**
  String get copyingFiles;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createdCandidate.
  ///
  /// In en, this message translates to:
  /// **'Created \"{name}\"'**
  String createdCandidate(Object name);

  /// No description provided for @creatingCopy.
  ///
  /// In en, this message translates to:
  /// **'Creating copy…'**
  String get creatingCopy;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkTheme;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @deletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} items'**
  String deletedCount(Object count);

  /// No description provided for @deleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get deleting;

  /// No description provided for @descending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descending;

  /// No description provided for @desktopHtmlPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Desktop HTML preview is simplified. For full JS/CSS styling, open in browser.'**
  String get desktopHtmlPreviewHint;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @downloadDestination.
  ///
  /// In en, this message translates to:
  /// **'Select Download Destination'**
  String get downloadDestination;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailed(Object error);

  /// No description provided for @downloadedTo.
  ///
  /// In en, this message translates to:
  /// **'Downloaded to {path}'**
  String downloadedTo(Object path);

  /// No description provided for @downloadingFile.
  ///
  /// In en, this message translates to:
  /// **'Downloading {file}…'**
  String downloadingFile(Object file);

  /// No description provided for @downloadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Downloading files…'**
  String get downloadingFiles;

  /// No description provided for @downloadingItem.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}…'**
  String downloadingItem(Object name);

  /// No description provided for @duplicateFailed.
  ///
  /// In en, this message translates to:
  /// **'Duplicate failed: {error}'**
  String duplicateFailed(Object error);

  /// No description provided for @emptyRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Empty Recycle Bin'**
  String get emptyRecycleBin;

  /// No description provided for @errorCopied.
  ///
  /// In en, this message translates to:
  /// **'Error copied to clipboard'**
  String get errorCopied;

  /// No description provided for @exportPreviewCache.
  ///
  /// In en, this message translates to:
  /// **'Export & Preview Cache'**
  String get exportPreviewCache;

  /// No description provided for @extractFailed.
  ///
  /// In en, this message translates to:
  /// **'Extract failed: {error}'**
  String extractFailed(Object error);

  /// No description provided for @extracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get extracting;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @failedToCreate.
  ///
  /// In en, this message translates to:
  /// **'Failed to create: {error}'**
  String failedToCreate(Object error);

  /// No description provided for @finalizingServer.
  ///
  /// In en, this message translates to:
  /// **'Finalizing (server processing)…'**
  String get finalizingServer;

  /// No description provided for @folderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folderLabel;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// No description provided for @followSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Follow system settings'**
  String get followSystemSettings;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @homeDashboard.
  ///
  /// In en, this message translates to:
  /// **'Home Dashboard'**
  String get homeDashboard;

  /// No description provided for @hoursLeft.
  ///
  /// In en, this message translates to:
  /// **'About {hours} hours left'**
  String hoursLeft(Object hours);

  /// No description provided for @hoursMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'About {hours} hr {minutes} min left'**
  String hoursMinutesLeft(Object hours, Object minutes);

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get inProgress;

  /// No description provided for @invertSelection.
  ///
  /// In en, this message translates to:
  /// **'Invert Selection'**
  String get invertSelection;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(Object count);

  /// No description provided for @itemsOutOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} items'**
  String itemsOutOfTotal(Object completed, Object total);

  /// No description provided for @lanSharing.
  ///
  /// In en, this message translates to:
  /// **'LAN HTTP Web Sharing'**
  String get lanSharing;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get lightTheme;

  /// No description provided for @localStorage.
  ///
  /// In en, this message translates to:
  /// **'Local Storage'**
  String get localStorage;

  /// No description provided for @mediaPlayback.
  ///
  /// In en, this message translates to:
  /// **'Media Playback (Remote Buffer)'**
  String get mediaPlayback;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @minutesLeft.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} min left'**
  String minutesLeft(Object minutes);

  /// No description provided for @moveFailed.
  ///
  /// In en, this message translates to:
  /// **'Move failed: {error}'**
  String moveFailed(Object error);

  /// No description provided for @movingFiles.
  ///
  /// In en, this message translates to:
  /// **'Moving files…'**
  String get movingFiles;

  /// No description provided for @newBucket.
  ///
  /// In en, this message translates to:
  /// **'New Bucket'**
  String get newBucket;

  /// No description provided for @newFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get newFile;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @newTextFile.
  ///
  /// In en, this message translates to:
  /// **'New Text File'**
  String get newTextFile;

  /// No description provided for @noLanIpFound.
  ///
  /// In en, this message translates to:
  /// **'No LAN IP detected, please connect to Wi-Fi or Ethernet.'**
  String get noLanIpFound;

  /// No description provided for @noTasksYet.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get noTasksYet;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get openInBrowser;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @passwordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied to clipboard'**
  String get passwordCopied;

  /// No description provided for @passwordFieldHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to access via token link without password; set to also allow password login'**
  String get passwordFieldHelper;

  /// No description provided for @passwordFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Password (Optional)'**
  String get passwordFieldLabel;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playbackSpeed;

  /// No description provided for @pleaseSelectSpecificFolder.
  ///
  /// In en, this message translates to:
  /// **'Please select a specific folder to upload'**
  String get pleaseSelectSpecificFolder;

  /// No description provided for @port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port;

  /// No description provided for @previewImage.
  ///
  /// In en, this message translates to:
  /// **'Preview Image'**
  String get previewImage;

  /// No description provided for @processingPercent.
  ///
  /// In en, this message translates to:
  /// **'100% (processing)'**
  String get processingPercent;

  /// No description provided for @readOnly.
  ///
  /// In en, this message translates to:
  /// **' (read-only)'**
  String get readOnly;

  /// No description provided for @readOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Read Only (disallow web uploads)'**
  String get readOnlyMode;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @recentDirs.
  ///
  /// In en, this message translates to:
  /// **'Recent:'**
  String get recentDirs;

  /// No description provided for @recycleBin.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin'**
  String get recycleBin;

  /// No description provided for @remote.
  ///
  /// In en, this message translates to:
  /// **'Remote'**
  String get remote;

  /// No description provided for @remoteArchiveCache.
  ///
  /// In en, this message translates to:
  /// **'Remote Archive Cache'**
  String get remoteArchiveCache;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @retryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed: {error}'**
  String retryFailed(Object error);

  /// No description provided for @runInBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get runInBackground;

  /// No description provided for @runningOnLan.
  ///
  /// In en, this message translates to:
  /// **'🟢 Running on LAN'**
  String get runningOnLan;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @scriptDisabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'Scripts disabled (safe default), click to enable'**
  String get scriptDisabledTooltip;

  /// No description provided for @scriptEnabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'Scripts enabled: page can access files in shared dir, click to disable'**
  String get scriptEnabledTooltip;

  /// No description provided for @searchFiles.
  ///
  /// In en, this message translates to:
  /// **'Search files'**
  String get searchFiles;

  /// No description provided for @secondsLeft.
  ///
  /// In en, this message translates to:
  /// **'About {seconds} sec left'**
  String secondsLeft(Object seconds);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @selectFolderToUpload.
  ///
  /// In en, this message translates to:
  /// **'Select Folder to Upload'**
  String get selectFolderToUpload;

  /// No description provided for @selectItems.
  ///
  /// In en, this message translates to:
  /// **'Select items'**
  String get selectItems;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Theme, System info, About'**
  String get settingsCardSubtitle;

  /// No description provided for @shareInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open the following URL in a browser on the same Wi-Fi to access (contains token, do not share publicly):'**
  String get shareInstructions;

  /// No description provided for @sharePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sharePasswordLabel;

  /// No description provided for @sharePasswordNotice.
  ///
  /// In en, this message translates to:
  /// **'Generated share password: {pwd}'**
  String sharePasswordNotice(Object pwd);

  /// No description provided for @shared.
  ///
  /// In en, this message translates to:
  /// **'Shared'**
  String get shared;

  /// No description provided for @sharedPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Shared path copied'**
  String get sharedPathCopied;

  /// No description provided for @showHiddenFiles.
  ///
  /// In en, this message translates to:
  /// **'Show hidden files'**
  String get showHiddenFiles;

  /// No description provided for @skippedAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'{count} items skipped (already exist)'**
  String skippedAlreadyExists(Object count);

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortBy;

  /// No description provided for @splitView.
  ///
  /// In en, this message translates to:
  /// **'Split view'**
  String get splitView;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'⚪ Stopped'**
  String get stopped;

  /// No description provided for @storageAndCache.
  ///
  /// In en, this message translates to:
  /// **'Storage & Cache'**
  String get storageAndCache;

  /// No description provided for @supportedProtocols.
  ///
  /// In en, this message translates to:
  /// **'Supported Protocols'**
  String get supportedProtocols;

  /// No description provided for @switchToGrid.
  ///
  /// In en, this message translates to:
  /// **'Switch to Grid'**
  String get switchToGrid;

  /// No description provided for @switchToList.
  ///
  /// In en, this message translates to:
  /// **'Switch to List'**
  String get switchToList;

  /// No description provided for @switchedToBackground.
  ///
  /// In en, this message translates to:
  /// **'Moved to background — check progress in Home → Tasks'**
  String get switchedToBackground;

  /// No description provided for @systemPicker.
  ///
  /// In en, this message translates to:
  /// **'System Picker'**
  String get systemPicker;

  /// No description provided for @taskCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get taskCompress;

  /// No description provided for @taskCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get taskCopy;

  /// No description provided for @taskDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get taskDelete;

  /// No description provided for @taskExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get taskExtract;

  /// No description provided for @taskGeneric.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get taskGeneric;

  /// No description provided for @taskMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get taskMove;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @tasksEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Copies, moves and other long operations will appear here.'**
  String get tasksEmptySubtitle;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @toolbarAtBottom.
  ///
  /// In en, this message translates to:
  /// **'Toolbar at bottom'**
  String get toolbarAtBottom;

  /// No description provided for @toolbarAtBottomDesc.
  ///
  /// In en, this message translates to:
  /// **'Move the address bar and icons below the file list'**
  String get toolbarAtBottomDesc;

  /// No description provided for @transferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring…'**
  String get transferring;

  /// No description provided for @trashCountNotice.
  ///
  /// In en, this message translates to:
  /// **'{count} items in trash'**
  String trashCountNotice(Object count);

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @uploadFiles.
  ///
  /// In en, this message translates to:
  /// **'Upload Files'**
  String get uploadFiles;

  /// No description provided for @uploadFolder.
  ///
  /// In en, this message translates to:
  /// **'Upload Folder'**
  String get uploadFolder;

  /// No description provided for @uploadItemsToCurrentFolder.
  ///
  /// In en, this message translates to:
  /// **'Upload Items to Current Folder'**
  String get uploadItemsToCurrentFolder;

  /// No description provided for @uploadThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Upload folder'**
  String get uploadThisFolder;

  /// No description provided for @uploadWithSystemPicker.
  ///
  /// In en, this message translates to:
  /// **'Upload using system file picker'**
  String get uploadWithSystemPicker;

  /// No description provided for @uploadWithSystemPickerDesc.
  ///
  /// In en, this message translates to:
  /// **'Directly invokes native OS file picker, supporting system bookmarks and path paste'**
  String get uploadWithSystemPickerDesc;

  /// No description provided for @uploadingFolder.
  ///
  /// In en, this message translates to:
  /// **'Uploading folder \"{folder}\"…'**
  String uploadingFolder(Object folder);

  /// No description provided for @uploadingItems.
  ///
  /// In en, this message translates to:
  /// **'Uploading {count} items…'**
  String uploadingItems(Object count);

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied to clipboard'**
  String get urlCopied;

  /// No description provided for @utilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get utilities;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get waiting;

  /// No description provided for @waitingServerVerify.
  ///
  /// In en, this message translates to:
  /// **'All data sent, waiting for server verification and merge…'**
  String get waitingServerVerify;

  /// No description provided for @webSharingServer.
  ///
  /// In en, this message translates to:
  /// **'Web Sharing Server'**
  String get webSharingServer;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Browse local folders right away, or connect a server — SFTP, WebDAV, S3, SMB and more — to manage files anywhere.'**
  String get welcomeBody;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to FP File Manager'**
  String get welcomeTitle;

  /// No description provided for @invalidBucketName.
  ///
  /// In en, this message translates to:
  /// **'Invalid bucket name. Must be 3-63 characters, only lowercase letters, numbers, and hyphens, and start/end with a letter or digit.'**
  String get invalidBucketName;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortBySize;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Date modified'**
  String get sortByDate;

  /// No description provided for @sortByType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortByType;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @openSourceLicensesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Licenses and notices of third-party open-source software'**
  String get openSourceLicensesSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
