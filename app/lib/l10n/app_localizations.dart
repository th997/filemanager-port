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

  /// No description provided for @actionInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get actionInfo;

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
  String cannotClearFinishedTasks(int count);

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
  String compressFailed(String error);

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
  String copyFailed(String error);

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
  String createdCandidate(String name);

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
  String deleteFailed(String error);

  /// No description provided for @deletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} items'**
  String deletedCount(int count);

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
  String downloadFailed(String error);

  /// No description provided for @downloadedTo.
  ///
  /// In en, this message translates to:
  /// **'Downloaded to {path}'**
  String downloadedTo(String path);

  /// No description provided for @downloadingFile.
  ///
  /// In en, this message translates to:
  /// **'Downloading {file}…'**
  String downloadingFile(String file);

  /// No description provided for @downloadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Downloading files…'**
  String get downloadingFiles;

  /// No description provided for @downloadingItem.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}…'**
  String downloadingItem(String name);

  /// No description provided for @duplicateFailed.
  ///
  /// In en, this message translates to:
  /// **'Duplicate failed: {error}'**
  String duplicateFailed(String error);

  /// No description provided for @emptyRecycleBin.
  ///
  /// In en, this message translates to:
  /// **'Empty Recycle Bin'**
  String get emptyRecycleBin;

  /// No description provided for @endpointHintS3.
  ///
  /// In en, this message translates to:
  /// **'Endpoint (Optional for AWS, required for MinIO/R2)'**
  String get endpointHintS3;

  /// No description provided for @endpointHintGeneric.
  ///
  /// In en, this message translates to:
  /// **'Endpoint (e.g. https://oss-cn-hangzhou.aliyuncs.com)'**
  String get endpointHintGeneric;

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
  String extractFailed(String error);

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
  String failedToCreate(String error);

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
  String hoursLeft(int hours);

  /// No description provided for @hoursMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'About {hours} hr {minutes} min left'**
  String hoursMinutesLeft(int hours, int minutes);

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
  String itemsCount(int count);

  /// No description provided for @itemsOutOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} items'**
  String itemsOutOfTotal(int completed, int total);

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
  String minutesLeft(int minutes);

  /// No description provided for @monthYearLabel.
  ///
  /// In en, this message translates to:
  /// **'{month} {year}'**
  String monthYearLabel(String month, int year);

  /// No description provided for @monthSeptember.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get monthSeptember;

  /// No description provided for @monthOctober.
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get monthOctober;

  /// No description provided for @monthNovember.
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get monthNovember;

  /// No description provided for @monthMay.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthMay;

  /// No description provided for @monthMarch.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get monthMarch;

  /// No description provided for @monthJune.
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get monthJune;

  /// No description provided for @monthJuly.
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get monthJuly;

  /// No description provided for @monthJanuary.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get monthJanuary;

  /// No description provided for @monthFebruary.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get monthFebruary;

  /// No description provided for @monthDecember.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get monthDecember;

  /// No description provided for @monthAugust.
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get monthAugust;

  /// No description provided for @monthApril.
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get monthApril;

  /// No description provided for @moveFailed.
  ///
  /// In en, this message translates to:
  /// **'Move failed: {error}'**
  String moveFailed(String error);

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

  /// No description provided for @pdfMarginStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard (36pt)'**
  String get pdfMarginStandard;

  /// No description provided for @pdfMarginRelaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed (54pt)'**
  String get pdfMarginRelaxed;

  /// No description provided for @pdfMarginCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact (16pt)'**
  String get pdfMarginCompact;

  /// No description provided for @pickFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get pickFileTitle;

  /// No description provided for @pickFilesTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Files'**
  String get pickFilesTitle;

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

  /// No description provided for @quickVolumes.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get quickVolumes;

  /// No description provided for @quickRoot.
  ///
  /// In en, this message translates to:
  /// **'Root /'**
  String get quickRoot;

  /// No description provided for @quickPictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures'**
  String get quickPictures;

  /// No description provided for @quickHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get quickHome;

  /// No description provided for @quickDrive.
  ///
  /// In en, this message translates to:
  /// **'Drive ({letter}:)'**
  String quickDrive(String letter);

  /// No description provided for @quickDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get quickDownloads;

  /// No description provided for @quickDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get quickDownload;

  /// No description provided for @quickDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get quickDesktop;

  /// No description provided for @quickDcim.
  ///
  /// In en, this message translates to:
  /// **'DCIM (Photos)'**
  String get quickDcim;

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
  String retryFailed(String error);

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
  String secondsLeft(int seconds);

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @selectCount.
  ///
  /// In en, this message translates to:
  /// **'Select ({count})'**
  String selectCount(int count);

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

  /// No description provided for @selectedCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCountLabel(int count);

  /// No description provided for @selectedCountBytesLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} selected ({size})'**
  String selectedCountBytesLabel(int count, String size);

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
  String sharePasswordNotice(String pwd);

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
  String skippedAlreadyExists(int count);

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

  /// No description provided for @toolbarUpOneLevel.
  ///
  /// In en, this message translates to:
  /// **'Up one level'**
  String get toolbarUpOneLevel;

  /// No description provided for @toolbarJump.
  ///
  /// In en, this message translates to:
  /// **'Jump'**
  String get toolbarJump;

  /// No description provided for @toolbarForwardHistory.
  ///
  /// In en, this message translates to:
  /// **'Forward in history (Alt+→)'**
  String get toolbarForwardHistory;

  /// No description provided for @toolbarEditAddress.
  ///
  /// In en, this message translates to:
  /// **'Edit address (Cmd/Ctrl+L)'**
  String get toolbarEditAddress;

  /// No description provided for @toolbarBackHistory.
  ///
  /// In en, this message translates to:
  /// **'Back in history (Alt+←)'**
  String get toolbarBackHistory;

  /// No description provided for @transferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring…'**
  String get transferring;

  /// No description provided for @trashCountNotice.
  ///
  /// In en, this message translates to:
  /// **'{count} items in trash'**
  String trashCountNotice(int count);

  /// No description provided for @unknownDate.
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get unknownDate;

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
  String uploadingFolder(String folder);

  /// No description provided for @uploadingItems.
  ///
  /// In en, this message translates to:
  /// **'Uploading {count} items…'**
  String uploadingItems(int count);

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

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @openWith.
  ///
  /// In en, this message translates to:
  /// **'Open with'**
  String get openWith;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloadToLocal.
  ///
  /// In en, this message translates to:
  /// **'Download to local'**
  String get downloadToLocal;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @pasteCount.
  ///
  /// In en, this message translates to:
  /// **'Paste ({count})'**
  String pasteCount(int count);

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyPath;

  /// No description provided for @copyFolderPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Folder Path'**
  String get copyFolderPath;

  /// No description provided for @copyFilePath.
  ///
  /// In en, this message translates to:
  /// **'Copy File Path'**
  String get copyFilePath;

  /// No description provided for @copyOriginalPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Original Path'**
  String get copyOriginalPath;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied to clipboard'**
  String get pathCopied;

  /// No description provided for @folderPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Folder path copied to clipboard'**
  String get folderPathCopied;

  /// No description provided for @copiedPathValue.
  ///
  /// In en, this message translates to:
  /// **'Copied path: {path}'**
  String copiedPathValue(String path);

  /// No description provided for @copiedValue.
  ///
  /// In en, this message translates to:
  /// **'Copied: {value}'**
  String copiedValue(String value);

  /// No description provided for @copiedItemToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied {name} to clipboard'**
  String copiedItemToClipboard(String name);

  /// No description provided for @cutItemToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Cut {name} to clipboard'**
  String cutItemToClipboard(String name);

  /// No description provided for @copiedItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items copied to clipboard'**
  String copiedItemsCount(int count);

  /// No description provided for @cutItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items cut to clipboard'**
  String cutItemsCount(int count);

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @newName.
  ///
  /// In en, this message translates to:
  /// **'New Name'**
  String get newName;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @properties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get properties;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @extractHere.
  ///
  /// In en, this message translates to:
  /// **'Extract Here'**
  String get extractHere;

  /// No description provided for @compress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compress;

  /// No description provided for @compressToZip.
  ///
  /// In en, this message translates to:
  /// **'Compress to ZIP'**
  String get compressToZip;

  /// No description provided for @archiveName.
  ///
  /// In en, this message translates to:
  /// **'Archive Name'**
  String get archiveName;

  /// No description provided for @bookmarkThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Bookmark This Folder'**
  String get bookmarkThisFolder;

  /// No description provided for @bookmarkLocation.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Location'**
  String get bookmarkLocation;

  /// No description provided for @bookmarkedName.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked \"{name}\"'**
  String bookmarkedName(String name);

  /// No description provided for @alreadyBookmarked.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is already bookmarked'**
  String alreadyBookmarked(String name);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @go.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get go;

  /// No description provided for @goUp.
  ///
  /// In en, this message translates to:
  /// **'Go Up'**
  String get goUp;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @clearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear Filter'**
  String get clearFilter;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @searchAction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchAction;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @removedName.
  ///
  /// In en, this message translates to:
  /// **'Removed \"{name}\"'**
  String removedName(String name);

  /// No description provided for @unknownSize.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownSize;

  /// No description provided for @wrapIndicator.
  ///
  /// In en, this message translates to:
  /// **'Wrap'**
  String get wrapIndicator;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @pathLabel.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get pathLabel;

  /// No description provided for @extensionLabel.
  ///
  /// In en, this message translates to:
  /// **'Extension'**
  String get extensionLabel;

  /// No description provided for @sizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sizeLabel;

  /// No description provided for @modifiedLabel.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get modifiedLabel;

  /// No description provided for @hiddenLabel.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hiddenLabel;

  /// No description provided for @hiddenFilesOff.
  ///
  /// In en, this message translates to:
  /// **'hidden files off'**
  String get hiddenFilesOff;

  /// No description provided for @symlinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Symlink'**
  String get symlinkLabel;

  /// No description provided for @directoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Directory'**
  String get directoryLabel;

  /// No description provided for @directoryEmptyLabel.
  ///
  /// In en, this message translates to:
  /// **'Directory (empty)'**
  String get directoryEmptyLabel;

  /// No description provided for @fileLabel.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileLabel;

  /// No description provided for @archiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveLabel;

  /// No description provided for @measuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get measuring;

  /// No description provided for @bytesUnit.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String bytesUnit(String count);

  /// No description provided for @yesBytes.
  ///
  /// In en, this message translates to:
  /// **'{formatted} ({raw} bytes)'**
  String yesBytes(String formatted, String raw);

  /// No description provided for @downloadFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Download file?'**
  String get downloadFileTitle;

  /// No description provided for @downloadFileStreamHint.
  ///
  /// In en, this message translates to:
  /// **'This file cannot be previewed while streaming, so it has to be downloaded first.'**
  String get downloadFileStreamHint;

  /// No description provided for @saveDestination.
  ///
  /// In en, this message translates to:
  /// **'Save destination'**
  String get saveDestination;

  /// No description provided for @chooseDownloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose download folder'**
  String get chooseDownloadFolder;

  /// No description provided for @folderIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get folderIsEmpty;

  /// No description provided for @noMatchingItems.
  ///
  /// In en, this message translates to:
  /// **'No matching items'**
  String get noMatchingItems;

  /// No description provided for @openFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolderTooltip;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @filterFilesFoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Filter files & folders...'**
  String get filterFilesFoldersHint;

  /// No description provided for @noSubfolders.
  ///
  /// In en, this message translates to:
  /// **'No subfolders'**
  String get noSubfolders;

  /// No description provided for @noMatchingSubfolders.
  ///
  /// In en, this message translates to:
  /// **'No matching subfolders'**
  String get noMatchingSubfolders;

  /// No description provided for @hideHiddenFolders.
  ///
  /// In en, this message translates to:
  /// **'Hide hidden folders'**
  String get hideHiddenFolders;

  /// No description provided for @showAllFileTypes.
  ///
  /// In en, this message translates to:
  /// **'All files'**
  String get showAllFileTypes;

  /// No description provided for @showHiddenFolders.
  ///
  /// In en, this message translates to:
  /// **'Show hidden folders'**
  String get showHiddenFolders;

  /// No description provided for @hideHiddenFiles.
  ///
  /// In en, this message translates to:
  /// **'Hide hidden files'**
  String get hideHiddenFiles;

  /// No description provided for @filterSubfoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Filter subfolders...'**
  String get filterSubfoldersHint;

  /// No description provided for @cannotReadFolderPrefix.
  ///
  /// In en, this message translates to:
  /// **'Cannot read this folder: '**
  String get cannotReadFolderPrefix;

  /// No description provided for @failedCreateFolder.
  ///
  /// In en, this message translates to:
  /// **'Failed to create folder: {error}'**
  String failedCreateFolder(String error);

  /// No description provided for @filterEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Filter...'**
  String get filterEllipsis;

  /// No description provided for @parentFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Parent folder'**
  String get parentFolderTooltip;

  /// No description provided for @clickToCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Click to copy path'**
  String get clickToCopyPath;

  /// No description provided for @folderNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Documents'**
  String get folderNameHint;

  /// No description provided for @folderNameInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderNameInputLabel;

  /// No description provided for @couldNotRequestFileAccess.
  ///
  /// In en, this message translates to:
  /// **'Could not request file access: {error}'**
  String couldNotRequestFileAccess(String error);

  /// No description provided for @couldNotRefreshHome.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh home data: {error}'**
  String couldNotRefreshHome(String error);

  /// No description provided for @storagePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission is required to browse files. Grant \"All files access\" in the next screen.'**
  String get storagePermissionRequired;

  /// No description provided for @requesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting…'**
  String get requesting;

  /// No description provided for @grant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grant;

  /// No description provided for @remoteProtocolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'S3, OSS, SFTP, WebDAV...'**
  String get remoteProtocolsSubtitle;

  /// No description provided for @utilitiesTrashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} in trash • Web share'**
  String utilitiesTrashSubtitle(int count);

  /// No description provided for @utilitiesDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin, Web share, Cache'**
  String get utilitiesDefaultSubtitle;

  /// No description provided for @tasksDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers and operations'**
  String get tasksDefaultSubtitle;

  /// No description provided for @bookmarksDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saved folders'**
  String get bookmarksDefaultSubtitle;

  /// No description provided for @recentDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browsing history'**
  String get recentDefaultSubtitle;

  /// No description provided for @sortLabelName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortLabelName;

  /// No description provided for @sortLabelSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortLabelSize;

  /// No description provided for @sortLabelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get sortLabelDate;

  /// No description provided for @sortLabelType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortLabelType;

  /// No description provided for @couldNotLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Could not load more: {error}'**
  String couldNotLoadMore(String error);

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed: {error}'**
  String refreshFailed(String error);

  /// No description provided for @downloadedNoAppToOpen.
  ///
  /// In en, this message translates to:
  /// **'Downloaded, but no installed app can open {name}'**
  String downloadedNoAppToOpen(String name);

  /// No description provided for @allowInstallApkPrompt.
  ///
  /// In en, this message translates to:
  /// **'Allow installing unknown apps to open APK files'**
  String get allowInstallApkPrompt;

  /// No description provided for @noAppToOpenFile.
  ///
  /// In en, this message translates to:
  /// **'No installed app can open {name}'**
  String noAppToOpenFile(String name);

  /// No description provided for @cannotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot open file: {error}'**
  String cannotOpenFile(String error);

  /// No description provided for @cannotShareFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot share file: {error}'**
  String cannotShareFile(String error);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(String error);

  /// No description provided for @noSearchResultsFor.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String noSearchResultsFor(String query);

  /// No description provided for @searchedThisAndSubfolders.
  ///
  /// In en, this message translates to:
  /// **'Searched this folder and its subfolders.'**
  String get searchedThisAndSubfolders;

  /// No description provided for @first200Results.
  ///
  /// In en, this message translates to:
  /// **'First 200 results (narrow the search to see more)'**
  String get first200Results;

  /// No description provided for @searchResultsInFolder.
  ///
  /// In en, this message translates to:
  /// **'Results in this folder and subfolders: {count}'**
  String searchResultsInFolder(int count);

  /// No description provided for @searchFoundCount.
  ///
  /// In en, this message translates to:
  /// **'{count} found'**
  String searchFoundCount(int count);

  /// No description provided for @currentFolder.
  ///
  /// In en, this message translates to:
  /// **'Current folder'**
  String get currentFolder;

  /// No description provided for @fileBeyondFirstPage.
  ///
  /// In en, this message translates to:
  /// **'File is beyond the first page of \"{parent}\"; open the folder to view it.'**
  String fileBeyondFirstPage(String parent);

  /// No description provided for @tooManyItemsSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Too many items to select all at once ({count})'**
  String tooManyItemsSelectAll(int count);

  /// No description provided for @couldNotLoadAllItems.
  ///
  /// In en, this message translates to:
  /// **'Could not load all items: {error}'**
  String couldNotLoadAllItems(String error);

  /// No description provided for @alreadyLocalUseCopy.
  ///
  /// In en, this message translates to:
  /// **'Already local: use Copy to place these files elsewhere.'**
  String get alreadyLocalUseCopy;

  /// No description provided for @fileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get fileNameLabel;

  /// No description provided for @fileNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. notes.txt'**
  String get fileNameHint;

  /// No description provided for @failedToCreateFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to create file: {error}'**
  String failedToCreateFile(String error);

  /// No description provided for @alreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Already exists'**
  String get alreadyExists;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @keepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get keepBoth;

  /// No description provided for @replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replace;

  /// No description provided for @readOnlyCannotDrop.
  ///
  /// In en, this message translates to:
  /// **'This location is read-only — cannot drop files here'**
  String get readOnlyCannotDrop;

  /// No description provided for @cannotDropFolderIntoSelf.
  ///
  /// In en, this message translates to:
  /// **'Cannot drop a folder onto itself or into its own subfolder'**
  String get cannotDropFolderIntoSelf;

  /// No description provided for @deleteSingleConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteSingleConfirmTitle(String name);

  /// No description provided for @deleteMultipleConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} items?'**
  String deleteMultipleConfirmTitle(int count);

  /// No description provided for @deleteChoiceTrashOrPermanent.
  ///
  /// In en, this message translates to:
  /// **'Choose whether to move to Recycle Bin or delete permanently.'**
  String get deleteChoiceTrashOrPermanent;

  /// No description provided for @deletePermanentWarning.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently? This cannot be undone.'**
  String get deletePermanentWarning;

  /// No description provided for @deleteRemotePermanentWarning.
  ///
  /// In en, this message translates to:
  /// **'This item is on a remote server and cannot be moved to the local Recycle Bin. It will be deleted permanently.'**
  String get deleteRemotePermanentWarning;

  /// No description provided for @permanentDelete.
  ///
  /// In en, this message translates to:
  /// **'Permanent Delete'**
  String get permanentDelete;

  /// No description provided for @couldNotMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Could not move {failed} of {total} items to Recycle Bin:\n{details}'**
  String couldNotMoveToTrash(int failed, int total, String details);

  /// No description provided for @movedOneToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved 1 item to Recycle Bin'**
  String get movedOneToTrash;

  /// No description provided for @movedManyToTrash.
  ///
  /// In en, this message translates to:
  /// **'Moved {count} items to Recycle Bin'**
  String movedManyToTrash(int count);

  /// No description provided for @couldNotRestoreItems.
  ///
  /// In en, this message translates to:
  /// **'Could not restore {count} item(s)'**
  String couldNotRestoreItems(int count);

  /// No description provided for @nameCannotContainSlash.
  ///
  /// In en, this message translates to:
  /// **'A name cannot contain \"/\" or \"\\\"'**
  String get nameCannotContainSlash;

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String renameFailed(String error);

  /// No description provided for @rootLabel.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get rootLabel;

  /// No description provided for @exitSplitView.
  ///
  /// In en, this message translates to:
  /// **'Exit split view'**
  String get exitSplitView;

  /// No description provided for @cancelSelectionEsc.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection (Esc)'**
  String get cancelSelectionEsc;

  /// No description provided for @backToPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Back to previous page'**
  String get backToPreviousPage;

  /// No description provided for @backToTop.
  ///
  /// In en, this message translates to:
  /// **'Back to top'**
  String get backToTop;

  /// No description provided for @searchFilesSubfoldersHint.
  ///
  /// In en, this message translates to:
  /// **'Search files & subfolders…'**
  String get searchFilesSubfoldersHint;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @sortStatusTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort: {field} {arrow}'**
  String sortStatusTooltip(String field, String arrow);

  /// No description provided for @internalStorage.
  ///
  /// In en, this message translates to:
  /// **'Internal Storage'**
  String get internalStorage;

  /// No description provided for @capabilitiesPrefix.
  ///
  /// In en, this message translates to:
  /// **'Capabilities: '**
  String get capabilitiesPrefix;

  /// No description provided for @failedToLoadDir.
  ///
  /// In en, this message translates to:
  /// **'Failed to load directory'**
  String get failedToLoadDir;

  /// No description provided for @noFilesMatching.
  ///
  /// In en, this message translates to:
  /// **'No files matching \"{query}\"'**
  String noFilesMatching(String query);

  /// No description provided for @onlyHiddenFilesHere.
  ///
  /// In en, this message translates to:
  /// **'Only hidden files here'**
  String get onlyHiddenFilesHere;

  /// No description provided for @directoryIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Directory is empty'**
  String get directoryIsEmpty;

  /// No description provided for @enterPathToJumpHint.
  ///
  /// In en, this message translates to:
  /// **'Enter path to jump...'**
  String get enterPathToJumpHint;

  /// No description provided for @goToLine.
  ///
  /// In en, this message translates to:
  /// **'Go to Line'**
  String get goToLine;

  /// No description provided for @lineNumberRange.
  ///
  /// In en, this message translates to:
  /// **'Line number (1 - {total})'**
  String lineNumberRange(int total);

  /// No description provided for @enterLineNumberBetween.
  ///
  /// In en, this message translates to:
  /// **'Enter a line number between 1 and {total}'**
  String enterLineNumberBetween(int total);

  /// No description provided for @replacedOccurrences.
  ///
  /// In en, this message translates to:
  /// **'Replaced {count} occurrence(s)'**
  String replacedOccurrences(int count);

  /// No description provided for @reloadFile.
  ///
  /// In en, this message translates to:
  /// **'Reload File'**
  String get reloadFile;

  /// No description provided for @reloadFileConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes and reload the file from disk?'**
  String get reloadFileConfirm;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @fileSavedSuccess.
  ///
  /// In en, this message translates to:
  /// **'File saved successfully'**
  String get fileSavedSuccess;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @pdfExportFailed.
  ///
  /// In en, this message translates to:
  /// **'PDF Export failed: {error}'**
  String pdfExportFailed(String error);

  /// No description provided for @saveChangesQuestion.
  ///
  /// In en, this message translates to:
  /// **'Save Changes?'**
  String get saveChangesQuestion;

  /// No description provided for @saveBeforeBrowserPrompt.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save your changes before opening in the external browser?'**
  String get saveBeforeBrowserPrompt;

  /// No description provided for @openWithoutSaving.
  ///
  /// In en, this message translates to:
  /// **'Open without Saving'**
  String get openWithoutSaving;

  /// No description provided for @saveAndOpen.
  ///
  /// In en, this message translates to:
  /// **'Save and Open'**
  String get saveAndOpen;

  /// No description provided for @failedOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Failed to open in browser: {error}'**
  String failedOpenInBrowser(String error);

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get unsavedChanges;

  /// No description provided for @saveBeforeClosingPrompt.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Save them before closing?'**
  String get saveBeforeClosingPrompt;

  /// No description provided for @findInFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Find in file (Ctrl+F)'**
  String get findInFileTooltip;

  /// No description provided for @showSource.
  ///
  /// In en, this message translates to:
  /// **'Show source'**
  String get showSource;

  /// No description provided for @showPreview.
  ///
  /// In en, this message translates to:
  /// **'Show preview'**
  String get showPreview;

  /// No description provided for @markdownTheme.
  ///
  /// In en, this message translates to:
  /// **'Markdown Theme'**
  String get markdownTheme;

  /// No description provided for @exportToPdf.
  ///
  /// In en, this message translates to:
  /// **'Export to PDF'**
  String get exportToPdf;

  /// No description provided for @printPreviewPdf.
  ///
  /// In en, this message translates to:
  /// **'Print / Preview PDF'**
  String get printPreviewPdf;

  /// No description provided for @shareSavePdf.
  ///
  /// In en, this message translates to:
  /// **'Share / Save PDF'**
  String get shareSavePdf;

  /// No description provided for @marginsSpacing.
  ///
  /// In en, this message translates to:
  /// **'Margins / Spacing'**
  String get marginsSpacing;

  /// No description provided for @readOnlyCannotEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Read-only location — this file cannot be edited here'**
  String get readOnlyCannotEditTooltip;

  /// No description provided for @saveChangesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save changes (Ctrl+S)'**
  String get saveChangesTooltip;

  /// No description provided for @saveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get saveAs;

  /// No description provided for @saveToThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Save to this folder'**
  String get saveToThisFolder;

  /// No description provided for @savedToCachePrompt.
  ///
  /// In en, this message translates to:
  /// **'Saved to app cache. Tap Save As to save to device storage.'**
  String get savedToCachePrompt;

  /// No description provided for @savedLabel.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedLabel;

  /// No description provided for @editLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editLabel;

  /// No description provided for @textOptions.
  ///
  /// In en, this message translates to:
  /// **'Text Options'**
  String get textOptions;

  /// No description provided for @allTextCopied.
  ///
  /// In en, this message translates to:
  /// **'All text copied to clipboard'**
  String get allTextCopied;

  /// No description provided for @reloadFromDiskShortcut.
  ///
  /// In en, this message translates to:
  /// **'Reload from Disk (Ctrl+R)'**
  String get reloadFromDiskShortcut;

  /// No description provided for @copyAllText.
  ///
  /// In en, this message translates to:
  /// **'Copy All Text'**
  String get copyAllText;

  /// No description provided for @goToLineShortcut.
  ///
  /// In en, this message translates to:
  /// **'Go to Line... (Ctrl+G)'**
  String get goToLineShortcut;

  /// No description provided for @largerFontShortcut.
  ///
  /// In en, this message translates to:
  /// **'Larger (Ctrl+=) ({pt} pt)'**
  String largerFontShortcut(int pt);

  /// No description provided for @smallerFontShortcut.
  ///
  /// In en, this message translates to:
  /// **'Smaller (Ctrl+-) ({pt} pt)'**
  String smallerFontShortcut(int pt);

  /// No description provided for @resetFontShortcut.
  ///
  /// In en, this message translates to:
  /// **'Reset Size (Ctrl+0) (13pt)'**
  String get resetFontShortcut;

  /// No description provided for @wordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get wordWrap;

  /// No description provided for @undoShortcut.
  ///
  /// In en, this message translates to:
  /// **'Undo (Ctrl+Z)'**
  String get undoShortcut;

  /// No description provided for @redoShortcut.
  ///
  /// In en, this message translates to:
  /// **'Redo (Ctrl+Y)'**
  String get redoShortcut;

  /// No description provided for @failedToOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to open file: {error}'**
  String failedToOpenFile(String error);

  /// No description provided for @readOnlyCannotSave.
  ///
  /// In en, this message translates to:
  /// **'Read-only location — changes cannot be saved here.'**
  String get readOnlyCannotSave;

  /// No description provided for @findInFileHint.
  ///
  /// In en, this message translates to:
  /// **'Find in file...'**
  String get findInFileHint;

  /// No description provided for @previousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get previousMatch;

  /// No description provided for @nextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get nextMatch;

  /// No description provided for @toggleReplaceShortcut.
  ///
  /// In en, this message translates to:
  /// **'Toggle replace (Ctrl+H)'**
  String get toggleReplaceShortcut;

  /// No description provided for @closeFindShortcut.
  ///
  /// In en, this message translates to:
  /// **'Close find (Esc)'**
  String get closeFindShortcut;

  /// No description provided for @replaceWithHint.
  ///
  /// In en, this message translates to:
  /// **'Replace with...'**
  String get replaceWithHint;

  /// No description provided for @replaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace All'**
  String get replaceAll;

  /// No description provided for @documentDetails.
  ///
  /// In en, this message translates to:
  /// **'Document Details'**
  String get documentDetails;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get copyAll;

  /// No description provided for @documentCopied.
  ///
  /// In en, this message translates to:
  /// **'Document copied to clipboard'**
  String get documentCopied;

  /// No description provided for @linesLabel.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get linesLabel;

  /// No description provided for @wordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get wordsLabel;

  /// No description provided for @charactersLabel.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get charactersLabel;

  /// No description provided for @byteSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Byte Size'**
  String get byteSizeLabel;

  /// No description provided for @lineEndingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Line Endings'**
  String get lineEndingsLabel;

  /// No description provided for @cursorPositionLabel.
  ///
  /// In en, this message translates to:
  /// **'Cursor Position'**
  String get cursorPositionLabel;

  /// No description provided for @cursorLineCol.
  ///
  /// In en, this message translates to:
  /// **'Line {line}, Col {col}'**
  String cursorLineCol(int line, int col);

  /// No description provided for @readOnlyLocation.
  ///
  /// In en, this message translates to:
  /// **'Read-only location'**
  String get readOnlyLocation;

  /// No description provided for @previewModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewModeLabel;

  /// No description provided for @viewingSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Viewing source'**
  String get viewingSourceLabel;

  /// No description provided for @editingModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Editing'**
  String get editingModeLabel;

  /// No description provided for @editorStatusLine.
  ///
  /// In en, this message translates to:
  /// **'Ln {line}, Col {col}  •  Lines: {lines}  •  '**
  String editorStatusLine(int line, int col, int lines);

  /// No description provided for @editorStatusWords.
  ///
  /// In en, this message translates to:
  /// **'Words: {words}  •  '**
  String editorStatusWords(int words);

  /// No description provided for @editorStatusChars.
  ///
  /// In en, this message translates to:
  /// **'Chars: {chars}  •  '**
  String editorStatusChars(int chars);

  /// No description provided for @documentIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Document is empty'**
  String get documentIsEmpty;

  /// No description provided for @editInSourceMode.
  ///
  /// In en, this message translates to:
  /// **'Edit in Source Mode'**
  String get editInSourceMode;

  /// No description provided for @couldNotScanPhotos.
  ///
  /// In en, this message translates to:
  /// **'Could not scan for photos.\n{error}'**
  String couldNotScanPhotos(String error);

  /// No description provided for @photoLibraryDenied.
  ///
  /// In en, this message translates to:
  /// **'Photo library access denied.\nEnable it in Settings → Privacy → Photos.'**
  String get photoLibraryDenied;

  /// No description provided for @couldNotLoadMorePhotos.
  ///
  /// In en, this message translates to:
  /// **'Could not load more photos: {error}'**
  String couldNotLoadMorePhotos(String error);

  /// No description provided for @cannotOpenPhoto.
  ///
  /// In en, this message translates to:
  /// **'Cannot open photo: {error}'**
  String cannotOpenPhoto(String error);

  /// No description provided for @photoNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'Photo is no longer available'**
  String get photoNoLongerAvailable;

  /// No description provided for @openInViewer.
  ///
  /// In en, this message translates to:
  /// **'Open in Viewer'**
  String get openInViewer;

  /// No description provided for @sharePhoto.
  ///
  /// In en, this message translates to:
  /// **'Share Photo'**
  String get sharePhoto;

  /// No description provided for @photosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photosTitle;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// No description provided for @scrollToTop.
  ///
  /// In en, this message translates to:
  /// **'Scroll to top'**
  String get scrollToTop;

  /// No description provided for @noPhotosFound.
  ///
  /// In en, this message translates to:
  /// **'No photos found'**
  String get noPhotosFound;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @cannotReadImageDetails.
  ///
  /// In en, this message translates to:
  /// **'Cannot read image details: {error}'**
  String cannotReadImageDetails(String error);

  /// No description provided for @imageDetailsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Image details are no longer available'**
  String get imageDetailsUnavailable;

  /// No description provided for @imageDetails.
  ///
  /// In en, this message translates to:
  /// **'Image Details'**
  String get imageDetails;

  /// No description provided for @dimensionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get dimensionsLabel;

  /// No description provided for @dateTakenLabel.
  ///
  /// In en, this message translates to:
  /// **'Date taken'**
  String get dateTakenLabel;

  /// No description provided for @cameraLabel.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get cameraLabel;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @cannotLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Cannot load image: {error}'**
  String cannotLoadImage(String error);

  /// No description provided for @imageFileNotFoundLocally.
  ///
  /// In en, this message translates to:
  /// **'Image file not found locally'**
  String get imageFileNotFoundLocally;

  /// No description provided for @failedToLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get failedToLoadImage;

  /// No description provided for @imagePathCopied.
  ///
  /// In en, this message translates to:
  /// **'Image path copied'**
  String get imagePathCopied;

  /// No description provided for @cannotCopyPath.
  ///
  /// In en, this message translates to:
  /// **'Cannot copy path: {error}'**
  String cannotCopyPath(String error);

  /// No description provided for @cannotShareImage.
  ///
  /// In en, this message translates to:
  /// **'Cannot share image: {error}'**
  String cannotShareImage(String error);

  /// No description provided for @deleteImageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this image? This action cannot be undone.'**
  String get deleteImageConfirm;

  /// No description provided for @deletedItem.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedItem(String name);

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String failedToDelete(String error);

  /// No description provided for @shareImage.
  ///
  /// In en, this message translates to:
  /// **'Share Image'**
  String get shareImage;

  /// No description provided for @rotate90.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90°'**
  String get rotate90;

  /// No description provided for @rotate90Shortcut.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90° (R)'**
  String get rotate90Shortcut;

  /// No description provided for @deleteImage.
  ///
  /// In en, this message translates to:
  /// **'Delete Image'**
  String get deleteImage;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @moreBelow.
  ///
  /// In en, this message translates to:
  /// **'more below'**
  String get moreBelow;

  /// No description provided for @zoomInShortcut.
  ///
  /// In en, this message translates to:
  /// **'Zoom in (+)'**
  String get zoomInShortcut;

  /// No description provided for @zoomOutShortcut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out (-)'**
  String get zoomOutShortcut;

  /// No description provided for @resetZoomShortcut.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom (0)'**
  String get resetZoomShortcut;

  /// No description provided for @previousImage.
  ///
  /// In en, this message translates to:
  /// **'Previous image'**
  String get previousImage;

  /// No description provided for @nextImage.
  ///
  /// In en, this message translates to:
  /// **'Next image'**
  String get nextImage;

  /// No description provided for @autoPlayingNext.
  ///
  /// In en, this message translates to:
  /// **'Auto-playing next: {name}'**
  String autoPlayingNext(String name);

  /// No description provided for @nextEpisodeShortcut.
  ///
  /// In en, this message translates to:
  /// **'Next episode (N)'**
  String get nextEpisodeShortcut;

  /// No description provided for @playlistProgress.
  ///
  /// In en, this message translates to:
  /// **'Playlist ({current}/{total})'**
  String playlistProgress(int current, int total);

  /// No description provided for @autoNextOn.
  ///
  /// In en, this message translates to:
  /// **'Auto-next: On'**
  String get autoNextOn;

  /// No description provided for @autoNextOff.
  ///
  /// In en, this message translates to:
  /// **'Auto-next: Off'**
  String get autoNextOff;

  /// No description provided for @loopSingle.
  ///
  /// In en, this message translates to:
  /// **'Loop: Single'**
  String get loopSingle;

  /// No description provided for @loopOff.
  ///
  /// In en, this message translates to:
  /// **'Loop: Off'**
  String get loopOff;

  /// No description provided for @fullscreenShortcut.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen (F)'**
  String get fullscreenShortcut;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// No description provided for @exitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get exitFullscreen;

  /// No description provided for @playbackOptions.
  ///
  /// In en, this message translates to:
  /// **'Playback options'**
  String get playbackOptions;

  /// No description provided for @unmuteShortcut.
  ///
  /// In en, this message translates to:
  /// **'Unmute (M)'**
  String get unmuteShortcut;

  /// No description provided for @muteShortcut.
  ///
  /// In en, this message translates to:
  /// **'Mute (M) ({percent}%)'**
  String muteShortcut(int percent);

  /// No description provided for @rewind10s.
  ///
  /// In en, this message translates to:
  /// **'Rewind 10s'**
  String get rewind10s;

  /// No description provided for @forward10s.
  ///
  /// In en, this message translates to:
  /// **'Forward 10s'**
  String get forward10s;

  /// No description provided for @autoNextMenuOn.
  ///
  /// In en, this message translates to:
  /// **'Auto-next (On)'**
  String get autoNextMenuOn;

  /// No description provided for @autoNextMenuOff.
  ///
  /// In en, this message translates to:
  /// **'Auto-next (Off)'**
  String get autoNextMenuOff;

  /// No description provided for @previousShortcut.
  ///
  /// In en, this message translates to:
  /// **'Previous (P)'**
  String get previousShortcut;

  /// No description provided for @nextShortcut.
  ///
  /// In en, this message translates to:
  /// **'Next (N)'**
  String get nextShortcut;

  /// No description provided for @cannotPlayFile.
  ///
  /// In en, this message translates to:
  /// **'Cannot play this file'**
  String get cannotPlayFile;

  /// No description provided for @unknownPlaybackError.
  ///
  /// In en, this message translates to:
  /// **'Unknown playback error'**
  String get unknownPlaybackError;

  /// No description provided for @couldNotLoadBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Could not load bookmarks: {error}'**
  String couldNotLoadBookmarks(String error);

  /// No description provided for @renameBookmark.
  ///
  /// In en, this message translates to:
  /// **'Rename Bookmark'**
  String get renameBookmark;

  /// No description provided for @bookmarkNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Name'**
  String get bookmarkNameLabel;

  /// No description provided for @couldNotRenameBookmark.
  ///
  /// In en, this message translates to:
  /// **'Could not rename bookmark: {error}'**
  String couldNotRenameBookmark(String error);

  /// No description provided for @couldNotRemoveBookmark.
  ///
  /// In en, this message translates to:
  /// **'Could not remove bookmark: {error}'**
  String couldNotRemoveBookmark(String error);

  /// No description provided for @couldNotRestoreBookmark.
  ///
  /// In en, this message translates to:
  /// **'Could not restore bookmark: {error}'**
  String couldNotRestoreBookmark(String error);

  /// No description provided for @searchBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Search Bookmarks'**
  String get searchBookmarks;

  /// No description provided for @filterBookmarksHint.
  ///
  /// In en, this message translates to:
  /// **'Filter bookmarks...'**
  String get filterBookmarksHint;

  /// No description provided for @noBookmarksSaved.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks saved yet'**
  String get noBookmarksSaved;

  /// No description provided for @noMatchingBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No matching bookmarks'**
  String get noMatchingBookmarks;

  /// No description provided for @bookmarksEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'In the file browser, long-press a folder (or right-click it) and choose \"Bookmark This Folder\".'**
  String get bookmarksEmptyHint;

  /// No description provided for @nothingMatchesQuery.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\".'**
  String nothingMatchesQuery(String query);

  /// No description provided for @bookmarkActions.
  ///
  /// In en, this message translates to:
  /// **'Bookmark actions'**
  String get bookmarkActions;

  /// No description provided for @couldNotLoadRecent.
  ///
  /// In en, this message translates to:
  /// **'Could not load recent locations: {error}'**
  String couldNotLoadRecent(String error);

  /// No description provided for @failedToBookmark.
  ///
  /// In en, this message translates to:
  /// **'Failed to bookmark: {error}'**
  String failedToBookmark(String error);

  /// No description provided for @couldNotRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Could not remove \"{name}\": {error}'**
  String couldNotRemoveItem(String name, String error);

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove all recent locations? Bookmarks are kept.'**
  String get clearHistoryConfirm;

  /// No description provided for @couldNotClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Could not clear history: {error}'**
  String couldNotClearHistory(String error);

  /// No description provided for @clearedRecentLocations.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} recent locations'**
  String clearedRecentLocations(int count);

  /// No description provided for @removeFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Remove from History'**
  String get removeFromHistory;

  /// No description provided for @recentHistory.
  ///
  /// In en, this message translates to:
  /// **'Recent History'**
  String get recentHistory;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search History'**
  String get searchHistory;

  /// No description provided for @filterRecentHint.
  ///
  /// In en, this message translates to:
  /// **'Filter recent locations...'**
  String get filterRecentHint;

  /// No description provided for @noRecentHistory.
  ///
  /// In en, this message translates to:
  /// **'No recent browsing history'**
  String get noRecentHistory;

  /// No description provided for @noMatchingLocations.
  ///
  /// In en, this message translates to:
  /// **'No matching locations'**
  String get noMatchingLocations;

  /// No description provided for @recentEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Directories and files you browse will show up here.'**
  String get recentEmptyHint;

  /// No description provided for @actionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actionsTooltip;

  /// No description provided for @couldNotLoadTrash.
  ///
  /// In en, this message translates to:
  /// **'Could not load the Recycle Bin: {error}'**
  String couldNotLoadTrash(String error);

  /// No description provided for @recycledItemDetails.
  ///
  /// In en, this message translates to:
  /// **'Recycled Item Details'**
  String get recycledItemDetails;

  /// No description provided for @originalPathColon.
  ///
  /// In en, this message translates to:
  /// **'Original Path:'**
  String get originalPathColon;

  /// No description provided for @originalPathCopied.
  ///
  /// In en, this message translates to:
  /// **'Original path copied to clipboard'**
  String get originalPathCopied;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreItem.
  ///
  /// In en, this message translates to:
  /// **'Restore Item'**
  String get restoreItem;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get deletePermanently;

  /// No description provided for @couldNotRestoreNamed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore \"{name}\": {error}'**
  String couldNotRestoreNamed(String name, String error);

  /// No description provided for @restoredNamed.
  ///
  /// In en, this message translates to:
  /// **'Restored \"{name}\"'**
  String restoredNamed(String name);

  /// No description provided for @permanentlyDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete \"{name}\"?'**
  String permanentlyDeleteConfirm(String name);

  /// No description provided for @couldNotDeleteNamed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete \"{name}\": {error}'**
  String couldNotDeleteNamed(String name, String error);

  /// No description provided for @emptyAll.
  ///
  /// In en, this message translates to:
  /// **'Empty All'**
  String get emptyAll;

  /// No description provided for @permanentlyDeleteAllTrash.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all {count} items ({size})? This cannot be undone.'**
  String permanentlyDeleteAllTrash(int count, String size);

  /// No description provided for @couldNotEmptyTrash.
  ///
  /// In en, this message translates to:
  /// **'Could not empty recycle bin: {error}'**
  String couldNotEmptyTrash(String error);

  /// No description provided for @recycleBinEmptied.
  ///
  /// In en, this message translates to:
  /// **'Recycle bin emptied'**
  String get recycleBinEmptied;

  /// No description provided for @restoreAllItems.
  ///
  /// In en, this message translates to:
  /// **'Restore All Items'**
  String get restoreAllItems;

  /// No description provided for @restoreAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore all {count} items to their original locations?'**
  String restoreAllConfirm(int count);

  /// No description provided for @restoreAll.
  ///
  /// In en, this message translates to:
  /// **'Restore All'**
  String get restoreAll;

  /// No description provided for @restoredCountOfTotal.
  ///
  /// In en, this message translates to:
  /// **'Restored {done} of {total} items'**
  String restoredCountOfTotal(int done, int total);

  /// No description provided for @restoredPartialTrash.
  ///
  /// In en, this message translates to:
  /// **'Restored {done} of {total}. Still in trash: {failed} ({sample})'**
  String restoredPartialTrash(int done, int total, int failed, String sample);

  /// No description provided for @restoringProgress.
  ///
  /// In en, this message translates to:
  /// **'Restoring {done} / {total}…'**
  String restoringProgress(int done, int total);

  /// No description provided for @recycleBinSummary.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin • {count} items, {size}'**
  String recycleBinSummary(int count, String size);

  /// No description provided for @searchTrash.
  ///
  /// In en, this message translates to:
  /// **'Search Trash'**
  String get searchTrash;

  /// No description provided for @filterRecycledHint.
  ///
  /// In en, this message translates to:
  /// **'Filter recycled files...'**
  String get filterRecycledHint;

  /// No description provided for @recycleBinIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Recycle Bin is empty'**
  String get recycleBinIsEmpty;

  /// No description provided for @noMatchingItemsTrash.
  ///
  /// In en, this message translates to:
  /// **'No matching items in trash'**
  String get noMatchingItemsTrash;

  /// No description provided for @trashEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Deleted files and folders will appear here.'**
  String get trashEmptyHint;

  /// No description provided for @connectAndBrowse.
  ///
  /// In en, this message translates to:
  /// **'Connect & Browse'**
  String get connectAndBrowse;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @copyUri.
  ///
  /// In en, this message translates to:
  /// **'Copy URI'**
  String get copyUri;

  /// No description provided for @editConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Edit Configuration'**
  String get editConfiguration;

  /// No description provided for @deleteRemote.
  ///
  /// In en, this message translates to:
  /// **'Delete Remote'**
  String get deleteRemote;

  /// No description provided for @addedRemote.
  ///
  /// In en, this message translates to:
  /// **'Added remote: {name}'**
  String addedRemote(String name);

  /// No description provided for @deleteRemoteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"?\n\nThis only removes the saved connection from this app. Files on the remote server are not touched.'**
  String deleteRemoteConfirm(String name);

  /// No description provided for @connectionNoReadableDetails.
  ///
  /// In en, this message translates to:
  /// **'This connection has no readable details. Edit it to re-enter them.'**
  String get connectionNoReadableDetails;

  /// No description provided for @testingRemote.
  ///
  /// In en, this message translates to:
  /// **'Testing \"{name}\"…'**
  String testingRemote(String name);

  /// No description provided for @connectedToRemote.
  ///
  /// In en, this message translates to:
  /// **'Connected to \"{name}\"'**
  String connectedToRemote(String name);

  /// No description provided for @cannotReachRemote.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach \"{name}\"'**
  String cannotReachRemote(String name);

  /// No description provided for @noConnectionsToExport.
  ///
  /// In en, this message translates to:
  /// **'No connections to export'**
  String get noConnectionsToExport;

  /// No description provided for @backupConnectionsCount.
  ///
  /// In en, this message translates to:
  /// **'Backup Connections ({count})'**
  String backupConnectionsCount(int count);

  /// No description provided for @backupConnectionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Export your configured connections as JSON. You can copy it or share/save to Files.'**
  String get backupConnectionsDesc;

  /// No description provided for @copyToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get copyToClipboard;

  /// No description provided for @connectionsCopied.
  ///
  /// In en, this message translates to:
  /// **'Connections copied to clipboard'**
  String get connectionsCopied;

  /// No description provided for @shareSaveToFiles.
  ///
  /// In en, this message translates to:
  /// **'Share / Save to Files'**
  String get shareSaveToFiles;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @restoreConnections.
  ///
  /// In en, this message translates to:
  /// **'Restore Connections'**
  String get restoreConnections;

  /// No description provided for @pasteJsonBackupHint.
  ///
  /// In en, this message translates to:
  /// **'Paste JSON backup text below:'**
  String get pasteJsonBackupHint;

  /// No description provided for @importedConnections.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} connection(s){detail}'**
  String importedConnections(int count, String detail);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @searchRemotes.
  ///
  /// In en, this message translates to:
  /// **'Search Remotes'**
  String get searchRemotes;

  /// No description provided for @addConnection.
  ///
  /// In en, this message translates to:
  /// **'Add Connection'**
  String get addConnection;

  /// No description provided for @backupRestore.
  ///
  /// In en, this message translates to:
  /// **'Backup / Restore'**
  String get backupRestore;

  /// No description provided for @backupExport.
  ///
  /// In en, this message translates to:
  /// **'Backup / Export'**
  String get backupExport;

  /// No description provided for @restoreImport.
  ///
  /// In en, this message translates to:
  /// **'Restore / Import'**
  String get restoreImport;

  /// No description provided for @filterRemotesHint.
  ///
  /// In en, this message translates to:
  /// **'Filter remote connections...'**
  String get filterRemotesHint;

  /// No description provided for @noRemoteConnections.
  ///
  /// In en, this message translates to:
  /// **'No remote connections configured'**
  String get noRemoteConnections;

  /// No description provided for @noRemoteConnectionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP or SMB network storage.'**
  String get noRemoteConnectionsDesc;

  /// No description provided for @addRemoteStorage.
  ///
  /// In en, this message translates to:
  /// **'Add Remote Storage'**
  String get addRemoteStorage;

  /// No description provided for @editRemoteStorage.
  ///
  /// In en, this message translates to:
  /// **'Edit Remote Storage'**
  String get editRemoteStorage;

  /// No description provided for @noMatchingConnections.
  ///
  /// In en, this message translates to:
  /// **'No matching connections'**
  String get noMatchingConnections;

  /// No description provided for @addAnotherRemote.
  ///
  /// In en, this message translates to:
  /// **'Add Another Remote'**
  String get addAnotherRemote;

  /// No description provided for @detailsUnavailableReconnect.
  ///
  /// In en, this message translates to:
  /// **'Details unavailable — re-enter to reconnect'**
  String get detailsUnavailableReconnect;

  /// No description provided for @remoteActions.
  ///
  /// In en, this message translates to:
  /// **'Remote actions'**
  String get remoteActions;

  /// No description provided for @couldNotLoadConnections.
  ///
  /// In en, this message translates to:
  /// **'Could not load connections: {error}'**
  String couldNotLoadConnections(String error);

  /// No description provided for @portMustBeNumber.
  ///
  /// In en, this message translates to:
  /// **'Port must be a number.'**
  String get portMustBeNumber;

  /// No description provided for @portRangeError.
  ///
  /// In en, this message translates to:
  /// **'Port must be between 1 and 65535.'**
  String get portRangeError;

  /// No description provided for @connectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get connectionSuccessful;

  /// No description provided for @connectionReturnedFalse.
  ///
  /// In en, this message translates to:
  /// **'Connection returned false'**
  String get connectionReturnedFalse;

  /// No description provided for @connectionFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailedWithError(String error);

  /// No description provided for @idAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'ID \"{id}\" is already used by \"{name}\"'**
  String idAlreadyUsed(String id, String name);

  /// No description provided for @savedOldEntryRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved, but the old entry \"{oldId}\" could not be removed: {error}'**
  String savedOldEntryRemoveFailed(String oldId, String error);

  /// No description provided for @couldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String couldNotSave(String error);

  /// No description provided for @protocolProvider.
  ///
  /// In en, this message translates to:
  /// **'Protocol / Provider'**
  String get protocolProvider;

  /// No description provided for @providerS3.
  ///
  /// In en, this message translates to:
  /// **'Amazon S3 / S3-Compatible (MinIO, R2)'**
  String get providerS3;

  /// No description provided for @providerOss.
  ///
  /// In en, this message translates to:
  /// **'Aliyun OSS'**
  String get providerOss;

  /// No description provided for @providerWebdav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV (Nextcloud, OwnCloud)'**
  String get providerWebdav;

  /// No description provided for @providerSftp.
  ///
  /// In en, this message translates to:
  /// **'SFTP (SSH File Transfer)'**
  String get providerSftp;

  /// No description provided for @providerFtp.
  ///
  /// In en, this message translates to:
  /// **'FTP / FTPS'**
  String get providerFtp;

  /// No description provided for @providerSmb.
  ///
  /// In en, this message translates to:
  /// **'SMB / Windows Share (Samba)'**
  String get providerSmb;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get pleaseEnterName;

  /// No description provided for @identifierLabel.
  ///
  /// In en, this message translates to:
  /// **'Identifier / ID (e.g. sftp_mac, my_nas)'**
  String get identifierLabel;

  /// No description provided for @identifierHint.
  ///
  /// In en, this message translates to:
  /// **'Used in remote paths: remote://id/...'**
  String get identifierHint;

  /// No description provided for @generateIdTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate clean ID from Name'**
  String get generateIdTooltip;

  /// No description provided for @pleaseEnterId.
  ///
  /// In en, this message translates to:
  /// **'Please enter an identifier'**
  String get pleaseEnterId;

  /// No description provided for @idCharsetError.
  ///
  /// In en, this message translates to:
  /// **'Identifier may only contain letters, numbers, hyphens and underscores'**
  String get idCharsetError;

  /// No description provided for @bucketNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Bucket Name (Optional, empty for all buckets)'**
  String get bucketNameOptional;

  /// No description provided for @bucketNameOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to browse all buckets, or comma-separated'**
  String get bucketNameOptionalHint;

  /// No description provided for @regionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region (e.g. us-east-1, auto)'**
  String get regionLabel;

  /// No description provided for @usePathStyle.
  ///
  /// In en, this message translates to:
  /// **'Use Path-Style (for MinIO / local S3)'**
  String get usePathStyle;

  /// No description provided for @accessKeyId.
  ///
  /// In en, this message translates to:
  /// **'Access Key ID'**
  String get accessKeyId;

  /// No description provided for @secretAccessKey.
  ///
  /// In en, this message translates to:
  /// **'Secret Access Key'**
  String get secretAccessKey;

  /// No description provided for @showSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Show secret key'**
  String get showSecretKey;

  /// No description provided for @hideSecretKey.
  ///
  /// In en, this message translates to:
  /// **'Hide secret key'**
  String get hideSecretKey;

  /// No description provided for @webdavUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL (e.g. https://example.com/dav)'**
  String get webdavUrlLabel;

  /// No description provided for @urlRequired.
  ///
  /// In en, this message translates to:
  /// **'URL is required'**
  String get urlRequired;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @authMethod.
  ///
  /// In en, this message translates to:
  /// **'Authentication Method'**
  String get authMethod;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authPrivateKey.
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get authPrivateKey;

  /// No description provided for @privateKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get privateKeyLabel;

  /// No description provided for @privateKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste OpenSSH / PEM private key content here'**
  String get privateKeyHint;

  /// No description provided for @privateKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Private key is required'**
  String get privateKeyRequired;

  /// No description provided for @selectKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Select Key File'**
  String get selectKeyFile;

  /// No description provided for @passphraseLabel.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (Optional)'**
  String get passphraseLabel;

  /// No description provided for @passphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty if key is not encrypted'**
  String get passphraseHint;

  /// No description provided for @showPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Show passphrase'**
  String get showPassphrase;

  /// No description provided for @hidePassphrase.
  ///
  /// In en, this message translates to:
  /// **'Hide passphrase'**
  String get hidePassphrase;

  /// No description provided for @failedToReadKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to read key file: {error}'**
  String failedToReadKeyFile(String error);

  /// No description provided for @hostIp.
  ///
  /// In en, this message translates to:
  /// **'Host / IP'**
  String get hostIp;

  /// No description provided for @hostRequired.
  ///
  /// In en, this message translates to:
  /// **'Host is required'**
  String get hostRequired;

  /// No description provided for @numbersOnly.
  ///
  /// In en, this message translates to:
  /// **'Numbers only'**
  String get numbersOnly;

  /// No description provided for @portRangeShort.
  ///
  /// In en, this message translates to:
  /// **'Use 1–65535'**
  String get portRangeShort;

  /// No description provided for @remoteRootPath.
  ///
  /// In en, this message translates to:
  /// **'Remote Root Path'**
  String get remoteRootPath;

  /// No description provided for @ftpCleartextWarning.
  ///
  /// In en, this message translates to:
  /// **'FTP is not encrypted: the password and files travel in cleartext. Use SFTP or FTPS on untrusted networks.'**
  String get ftpCleartextWarning;

  /// No description provided for @clearTempCacheQuestion.
  ///
  /// In en, this message translates to:
  /// **'Clear Temporary Cache?'**
  String get clearTempCacheQuestion;

  /// No description provided for @clearTempCacheDesc.
  ///
  /// In en, this message translates to:
  /// **'This will delete {size} of temporary thumbnail, media, and preview cache. Your saved files and connections are safe.'**
  String clearTempCacheDesc(String size);

  /// No description provided for @tempCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Temporary cache cleared'**
  String get tempCacheCleared;

  /// No description provided for @couldNotClearCache.
  ///
  /// In en, this message translates to:
  /// **'Could not clear cache: {error}'**
  String couldNotClearCache(String error);

  /// No description provided for @temporaryCache.
  ///
  /// In en, this message translates to:
  /// **'Temporary Cache'**
  String get temporaryCache;

  /// No description provided for @appInfoCopied.
  ///
  /// In en, this message translates to:
  /// **'App info copied to clipboard'**
  String get appInfoCopied;

  /// No description provided for @supportedProtocolsCopied.
  ///
  /// In en, this message translates to:
  /// **'Supported protocols copied to clipboard'**
  String get supportedProtocolsCopied;

  /// No description provided for @buildLabel.
  ///
  /// In en, this message translates to:
  /// **'Build: {time}'**
  String buildLabel(String time);

  /// No description provided for @platformLabel.
  ///
  /// In en, this message translates to:
  /// **'Platform: {platform}'**
  String platformLabel(String platform);

  /// No description provided for @couldNotReadStorageStats.
  ///
  /// In en, this message translates to:
  /// **'Could not read storage stats: {error}'**
  String couldNotReadStorageStats(String error);

  /// No description provided for @couldNotClearArchiveCache.
  ///
  /// In en, this message translates to:
  /// **'Could not clear archive cache: {error}'**
  String couldNotClearArchiveCache(String error);

  /// No description provided for @archiveCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Archive cache cleared'**
  String get archiveCacheCleared;

  /// No description provided for @emptyTrashUtilityConfirm.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all {count} items? This cannot be undone.'**
  String emptyTrashUtilityConfirm(int count);

  /// No description provided for @couldNotEmptyTrashError.
  ///
  /// In en, this message translates to:
  /// **'Could not empty trash: {error}'**
  String couldNotEmptyTrashError(String error);

  /// No description provided for @chooseSharedFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose shared folder'**
  String get chooseSharedFolder;

  /// No description provided for @portValidationError.
  ///
  /// In en, this message translates to:
  /// **'Port must be a number between 1 and 65535 (got \"{port}\")'**
  String portValidationError(String port);

  /// No description provided for @failedToStartServer.
  ///
  /// In en, this message translates to:
  /// **'Failed to start server: {error}'**
  String failedToStartServer(String error);

  /// No description provided for @couldNotStopLanServer.
  ///
  /// In en, this message translates to:
  /// **'Could not stop the LAN server'**
  String get couldNotStopLanServer;

  /// No description provided for @documentsDir.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentsDir;

  /// No description provided for @errorFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'This folder no longer exists. It may have been deleted or renamed.\n({raw})'**
  String errorFolderNotFound(String raw);

  /// No description provided for @errorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. Grant storage access or pick another folder.\n({raw})'**
  String errorPermissionDenied(String raw);

  /// No description provided for @errorSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check the username and password.\n({raw})'**
  String errorSignInFailed(String raw);

  /// No description provided for @errorServerTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server took too long to respond. Check the address and your network.\n({raw})'**
  String errorServerTimeout(String raw);

  /// No description provided for @errorCannotReachServer.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check the address, port and your network.\n({raw})'**
  String errorCannotReachServer(String raw);

  /// No description provided for @playLabel.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playLabel;

  /// No description provided for @pauseLabel.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseLabel;

  /// No description provided for @webdavCleartextWarning.
  ///
  /// In en, this message translates to:
  /// **'This URL uses http:// — the password and files travel unencrypted. Use https:// if the server supports it.'**
  String get webdavCleartextWarning;

  /// No description provided for @selectThisFolder.
  ///
  /// In en, this message translates to:
  /// **'Select this folder'**
  String get selectThisFolder;

  /// No description provided for @selectFolderAction.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectFolderAction;

  /// No description provided for @lanSharingDesc.
  ///
  /// In en, this message translates to:
  /// **'Share a local folder over Wi-Fi so any browser on the same network can browse or download files.'**
  String get lanSharingDesc;
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
