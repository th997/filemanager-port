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

  /// No description provided for @playWithMediaKit.
  ///
  /// In en, this message translates to:
  /// **'Play with MediaKit Engine'**
  String get playWithMediaKit;

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

  /// No description provided for @quickInbox.
  ///
  /// In en, this message translates to:
  /// **'My Space'**
  String get quickInbox;

  /// No description provided for @privateInboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App-private · Hidden from other apps'**
  String get privateInboxSubtitle;

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

  /// No description provided for @pickerItemCounts.
  ///
  /// In en, this message translates to:
  /// **'{folders, plural, =1{1 folder} other{{folders} folders}}, {files, plural, =1{1 file} other{{files} files}}'**
  String pickerItemCounts(int folders, int files);

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

  /// No description provided for @openAsText.
  ///
  /// In en, this message translates to:
  /// **'Open as Text'**
  String get openAsText;

  /// No description provided for @openAsTextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open with built-in text editor'**
  String get openAsTextSubtitle;

  /// No description provided for @openWithOtherApp.
  ///
  /// In en, this message translates to:
  /// **'Open with Another App'**
  String get openWithOtherApp;

  /// No description provided for @openWithOtherAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use system default or third-party apps'**
  String get openWithOtherAppSubtitle;

  /// No description provided for @openAsMedia.
  ///
  /// In en, this message translates to:
  /// **'Open as Media'**
  String get openAsMedia;

  /// No description provided for @openAsMediaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play with built-in media player'**
  String get openAsMediaSubtitle;

  /// No description provided for @openAsImage.
  ///
  /// In en, this message translates to:
  /// **'Open as Image'**
  String get openAsImage;

  /// No description provided for @openAsImageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View with built-in image viewer'**
  String get openAsImageSubtitle;

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
  /// **'Privacy folders & cache cleanup'**
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

  /// No description provided for @receivedShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Received Shared Files'**
  String get receivedShareTitle;

  /// No description provided for @receivedShareSingle.
  ///
  /// In en, this message translates to:
  /// **'Received 1 file'**
  String get receivedShareSingle;

  /// No description provided for @receivedShareCount.
  ///
  /// In en, this message translates to:
  /// **'Received {count} files'**
  String receivedShareCount(int count);

  /// No description provided for @saveToLocal.
  ///
  /// In en, this message translates to:
  /// **'Save to Local'**
  String get saveToLocal;

  /// No description provided for @saveToLocalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a local folder to save'**
  String get saveToLocalSubtitle;

  /// No description provided for @saveToRemote.
  ///
  /// In en, this message translates to:
  /// **'Save to Remote'**
  String get saveToRemote;

  /// No description provided for @saveToRemoteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload to cloud storage, WebDAV or SFTP'**
  String get saveToRemoteSubtitle;

  /// No description provided for @openDirectly.
  ///
  /// In en, this message translates to:
  /// **'Open Directly'**
  String get openDirectly;

  /// No description provided for @openDirectlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View or play directly in app'**
  String get openDirectlySubtitle;

  /// No description provided for @selectRemoteStorage.
  ///
  /// In en, this message translates to:
  /// **'Select Remote Storage'**
  String get selectRemoteStorage;

  /// No description provided for @noRemotesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No Remote Storage'**
  String get noRemotesConfigured;

  /// No description provided for @noRemotesPrompt.
  ///
  /// In en, this message translates to:
  /// **'No remote storage configured yet. Would you like to add one?'**
  String get noRemotesPrompt;

  /// No description provided for @savingSharedFiles.
  ///
  /// In en, this message translates to:
  /// **'Saving shared files...'**
  String get savingSharedFiles;

  /// No description provided for @savedSharedFilesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Shared files saved successfully'**
  String get savedSharedFilesSuccess;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @invalidFileNameError.
  ///
  /// In en, this message translates to:
  /// **'Name cannot contain \"/\", \"\\\", or be \".\" or \"..\"'**
  String get invalidFileNameError;

  /// No description provided for @batchRename.
  ///
  /// In en, this message translates to:
  /// **'Batch Rename'**
  String get batchRename;

  /// No description provided for @batchRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Rename ({count} items)'**
  String batchRenameTitle(int count);

  /// No description provided for @batchRenameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add prefix/suffix, find & replace, or sequential numbering'**
  String get batchRenameSubtitle;

  /// No description provided for @batchRenameModePrefixSuffix.
  ///
  /// In en, this message translates to:
  /// **'Prefix / Suffix'**
  String get batchRenameModePrefixSuffix;

  /// No description provided for @batchRenameModeFindReplace.
  ///
  /// In en, this message translates to:
  /// **'Find & Replace'**
  String get batchRenameModeFindReplace;

  /// No description provided for @batchRenameModeNumbering.
  ///
  /// In en, this message translates to:
  /// **'Numbering'**
  String get batchRenameModeNumbering;

  /// No description provided for @batchRenamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Prefix'**
  String get batchRenamePrefix;

  /// No description provided for @batchRenamePrefixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. [2026] '**
  String get batchRenamePrefixHint;

  /// No description provided for @batchRenameSuffix.
  ///
  /// In en, this message translates to:
  /// **'Suffix'**
  String get batchRenameSuffix;

  /// No description provided for @batchRenameSuffixHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. _final'**
  String get batchRenameSuffixHint;

  /// No description provided for @batchRenameFindText.
  ///
  /// In en, this message translates to:
  /// **'Find text'**
  String get batchRenameFindText;

  /// No description provided for @batchRenameReplaceWith.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get batchRenameReplaceWith;

  /// No description provided for @batchRenameBaseName.
  ///
  /// In en, this message translates to:
  /// **'Base name'**
  String get batchRenameBaseName;

  /// No description provided for @batchRenameStartNumber.
  ///
  /// In en, this message translates to:
  /// **'Start number'**
  String get batchRenameStartNumber;

  /// No description provided for @batchRenamePaddingDigits.
  ///
  /// In en, this message translates to:
  /// **'Digits'**
  String get batchRenamePaddingDigits;

  /// No description provided for @batchRenameDigitsOption.
  ///
  /// In en, this message translates to:
  /// **'{digits} digits ({example})'**
  String batchRenameDigitsOption(int digits, String example);

  /// No description provided for @batchRenameKeepExtension.
  ///
  /// In en, this message translates to:
  /// **'Keep file extension'**
  String get batchRenameKeepExtension;

  /// No description provided for @batchRenamePreview.
  ///
  /// In en, this message translates to:
  /// **'Live Preview'**
  String get batchRenamePreview;

  /// No description provided for @batchRenameEmptyName.
  ///
  /// In en, this message translates to:
  /// **'(empty name)'**
  String get batchRenameEmptyName;

  /// No description provided for @batchRenameProgress.
  ///
  /// In en, this message translates to:
  /// **'Renaming {done} / {total}...'**
  String batchRenameProgress(int done, int total);

  /// No description provided for @batchRenameApply.
  ///
  /// In en, this message translates to:
  /// **'Apply Rename ({count})'**
  String batchRenameApply(int count);

  /// No description provided for @batchRenameComplete.
  ///
  /// In en, this message translates to:
  /// **'Batch rename complete'**
  String get batchRenameComplete;

  /// No description provided for @batchRenameNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No filenames will change'**
  String get batchRenameNoChanges;

  /// No description provided for @batchRenameErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'One or more target names are empty'**
  String get batchRenameErrorEmpty;

  /// No description provided for @batchRenameErrorDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate target name: \"{name}\"'**
  String batchRenameErrorDuplicate(String name);

  /// No description provided for @batchRenameErrorExists.
  ///
  /// In en, this message translates to:
  /// **'Target already exists: \"{name}\"'**
  String batchRenameErrorExists(String name);

  /// No description provided for @selectedItemsDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} selected items'**
  String selectedItemsDetailsTitle(int count);

  /// No description provided for @selectedFilesSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected files size'**
  String get selectedFilesSizeLabel;

  /// No description provided for @currentDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Current directory'**
  String get currentDirectoryLabel;

  /// No description provided for @bookmarkSortModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort order'**
  String get bookmarkSortModeTooltip;

  /// No description provided for @bookmarkSortCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom (drag to reorder)'**
  String get bookmarkSortCustom;

  /// No description provided for @bookmarkSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name ascending (A–Z)'**
  String get bookmarkSortNameAsc;

  /// No description provided for @bookmarkSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Name descending (Z–A)'**
  String get bookmarkSortNameDesc;

  /// No description provided for @videoFitLabel.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get videoFitLabel;

  /// No description provided for @videoFitContain.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get videoFitContain;

  /// No description provided for @videoFitCover.
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get videoFitCover;

  /// No description provided for @videoFitFill.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get videoFitFill;

  /// No description provided for @videoFitChanged.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio: {mode}'**
  String videoFitChanged(String mode);

  /// No description provided for @audioTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio Tracks ({count})'**
  String audioTracksTitle(int count);

  /// No description provided for @audioTrackMenu.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get audioTrackMenu;

  /// No description provided for @noAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'No selectable audio tracks'**
  String get noAudioTracks;

  /// No description provided for @audioTrackDefault.
  ///
  /// In en, this message translates to:
  /// **'Auto (Default)'**
  String get audioTrackDefault;

  /// No description provided for @audioTrackItem.
  ///
  /// In en, this message translates to:
  /// **'Audio track {id}'**
  String audioTrackItem(String id);

  /// No description provided for @subtitleTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitles ({count})'**
  String subtitleTracksTitle(int count);

  /// No description provided for @subtitleTrackMenu.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitleTrackMenu;

  /// No description provided for @subtitlesOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get subtitlesOff;

  /// No description provided for @subtitleTrackItem.
  ///
  /// In en, this message translates to:
  /// **'Subtitle {id}'**
  String subtitleTrackItem(String id);

  /// No description provided for @sleepTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep Timer'**
  String get sleepTimerTitle;

  /// No description provided for @sleepTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get sleepTimerOff;

  /// No description provided for @sleepTimerOffToast.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer turned off'**
  String get sleepTimerOffToast;

  /// No description provided for @sleepTimerMinutes.
  ///
  /// In en, this message translates to:
  /// **'Stop in {minutes} min'**
  String sleepTimerMinutes(int minutes);

  /// No description provided for @sleepTimerMinutesToast.
  ///
  /// In en, this message translates to:
  /// **'Playback will stop in {minutes} min'**
  String sleepTimerMinutesToast(int minutes);

  /// No description provided for @sleepTimerEndOfTrack.
  ///
  /// In en, this message translates to:
  /// **'Stop at end of current track'**
  String get sleepTimerEndOfTrack;

  /// No description provided for @sleepTimerEndOfTrackToast.
  ///
  /// In en, this message translates to:
  /// **'Playback will stop after current track'**
  String get sleepTimerEndOfTrackToast;

  /// No description provided for @sleepTimerEndOfTrackShort.
  ///
  /// In en, this message translates to:
  /// **'End of track'**
  String get sleepTimerEndOfTrackShort;

  /// No description provided for @sleepTimerMenuRemaining.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer ({remaining})'**
  String sleepTimerMenuRemaining(String remaining);

  /// No description provided for @readOnlyViewMode.
  ///
  /// In en, this message translates to:
  /// **'Read-only view'**
  String get readOnlyViewMode;

  /// No description provided for @privacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Privacy Folder'**
  String get privacyFolder;

  /// No description provided for @privacyFolders.
  ///
  /// In en, this message translates to:
  /// **'Privacy Folders'**
  String get privacyFolders;

  /// No description provided for @privacyFoldersDesc.
  ///
  /// In en, this message translates to:
  /// **'Create, unlock, back up, or import isolated privacy folders'**
  String get privacyFoldersDesc;

  /// No description provided for @createPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Create Privacy Folder'**
  String get createPrivacyFolder;

  /// No description provided for @openPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Privacy Folder'**
  String get openPrivacyFolder;

  /// No description provided for @backupPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Back Up Privacy Folder'**
  String get backupPrivacyFolder;

  /// No description provided for @importPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Import Privacy Folder'**
  String get importPrivacyFolder;

  /// No description provided for @privacyFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get privacyFolderName;

  /// No description provided for @privacyFolderNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter exact folder name'**
  String get privacyFolderNameHint;

  /// No description provided for @privacyFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder does not exist'**
  String get privacyFolderNotFound;

  /// No description provided for @privacyFolderAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A privacy folder with this name already exists'**
  String get privacyFolderAlreadyExists;

  /// No description provided for @credentialMethod.
  ///
  /// In en, this message translates to:
  /// **'Unlock Credential'**
  String get credentialMethod;

  /// No description provided for @credentialPassword.
  ///
  /// In en, this message translates to:
  /// **'Standalone Password (8–128 chars)'**
  String get credentialPassword;

  /// No description provided for @credentialSystem.
  ///
  /// In en, this message translates to:
  /// **'System Unlock (Passcode / Biometrics)'**
  String get credentialSystem;

  /// No description provided for @credentialSystemUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System unlock is not supported on this device'**
  String get credentialSystemUnavailable;

  /// No description provided for @encryptionAlgorithm.
  ///
  /// In en, this message translates to:
  /// **'Encryption Method'**
  String get encryptionAlgorithm;

  /// No description provided for @cipherNone.
  ///
  /// In en, this message translates to:
  /// **'No Encryption'**
  String get cipherNone;

  /// No description provided for @cipherAes128Gcm.
  ///
  /// In en, this message translates to:
  /// **'AES-128-GCM (Default, hardware accelerated)'**
  String get cipherAes128Gcm;

  /// No description provided for @cipherAes256Gcm.
  ///
  /// In en, this message translates to:
  /// **'AES-256-GCM (Hardware accelerated)'**
  String get cipherAes256Gcm;

  /// No description provided for @storageLocation.
  ///
  /// In en, this message translates to:
  /// **'Storage Location'**
  String get storageLocation;

  /// No description provided for @useDefaultLocation.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get useDefaultLocation;

  /// No description provided for @changeLocation.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeLocation;

  /// No description provided for @privacyPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password (8–128 chars, symbols allowed)'**
  String get privacyPasswordLabel;

  /// No description provided for @privacyConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get privacyConfirmPasswordLabel;

  /// No description provided for @passwordLengthError.
  ///
  /// In en, this message translates to:
  /// **'Password must be 8 to 128 characters'**
  String get passwordLengthError;

  /// No description provided for @passwordMismatchError.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatchError;

  /// No description provided for @privacyUnlockedLabel.
  ///
  /// In en, this message translates to:
  /// **'Unlocked privacy folder • Auto-hides on exit or 10m background'**
  String get privacyUnlockedLabel;

  /// No description provided for @lockAndHide.
  ///
  /// In en, this message translates to:
  /// **'Lock & Hide'**
  String get lockAndHide;

  /// No description provided for @lockAllPrivacyFolders.
  ///
  /// In en, this message translates to:
  /// **'Lock & Hide All ({count})'**
  String lockAllPrivacyFolders(int count);

  /// No description provided for @vaultLockedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" locked and hidden'**
  String vaultLockedNotice(String name);

  /// No description provided for @nextStep.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextStep;

  /// No description provided for @unlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockAction;

  /// No description provided for @unlockWithSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to unlock privacy folder \"{name}\"'**
  String unlockWithSystemPrompt(String name);

  /// No description provided for @setupSystemAuthPrompt.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to set up system unlock for privacy folder'**
  String get setupSystemAuthPrompt;

  /// No description provided for @wrongCredentialError.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or credential'**
  String get wrongCredentialError;

  /// No description provided for @cooldownRetryError.
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts, retry in {seconds}s'**
  String cooldownRetryError(int seconds);

  /// No description provided for @selectBackupSourceVault.
  ///
  /// In en, this message translates to:
  /// **'Select unlocked folder or enter name'**
  String get selectBackupSourceVault;

  /// No description provided for @backupPasswordRequiredNotice.
  ///
  /// In en, this message translates to:
  /// **'This folder uses system unlock. Set an 8–128 char backup password so the archive can be imported on any device.'**
  String get backupPasswordRequiredNotice;

  /// No description provided for @backupPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup Password (8–128 chars)'**
  String get backupPasswordLabel;

  /// No description provided for @selectBackupDestFile.
  ///
  /// In en, this message translates to:
  /// **'Choose Backup Output Folder'**
  String get selectBackupDestFile;

  /// No description provided for @backupExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup exported to: {path}'**
  String backupExportSuccess(String path);

  /// No description provided for @selectBackupArchive.
  ///
  /// In en, this message translates to:
  /// **'Select .fpmvault Backup File'**
  String get selectBackupArchive;

  /// No description provided for @backupArchiveSummary.
  ///
  /// In en, this message translates to:
  /// **'Cipher: {cipher} • Objects: {count}'**
  String backupArchiveSummary(String cipher, int count);

  /// No description provided for @backupPasswordToVerify.
  ///
  /// In en, this message translates to:
  /// **'Backup / Vault Password'**
  String get backupPasswordToVerify;

  /// No description provided for @localUnlockAfterImport.
  ///
  /// In en, this message translates to:
  /// **'Unlock Method After Import'**
  String get localUnlockAfterImport;

  /// No description provided for @newLocalPasswordOptional.
  ///
  /// In en, this message translates to:
  /// **'New Local Password (blank to reuse backup password)'**
  String get newLocalPasswordOptional;

  /// No description provided for @importSuccessNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" imported and unlocked'**
  String importSuccessNotice(String name);

  /// No description provided for @saveToPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Save to Privacy Folder'**
  String get saveToPrivacyFolder;

  /// No description provided for @saveToPrivacyFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypt and save into an unlocked privacy folder'**
  String get saveToPrivacyFolderSubtitle;

  /// No description provided for @selectPrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Privacy Folder'**
  String get selectPrivacyFolder;

  /// No description provided for @privacyFolderNoHistoryBookmark.
  ///
  /// In en, this message translates to:
  /// **'History and public bookmarks are disabled inside privacy folders'**
  String get privacyFolderNoHistoryBookmark;

  /// No description provided for @unlockedBadge.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlockedBadge;

  /// No description provided for @importKeepOriginalName.
  ///
  /// In en, this message translates to:
  /// **'Original folder name will be kept: \"{name}\"'**
  String importKeepOriginalName(String name);

  /// No description provided for @importWillKeepOriginalName.
  ///
  /// In en, this message translates to:
  /// **'Original folder name will be preserved automatically. If it already exists, you will be prompted to enter a new name.'**
  String get importWillKeepOriginalName;

  /// No description provided for @importNameExistsEnterNew.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" already exists. Please enter a new folder name.'**
  String importNameExistsEnterNew(String name);

  /// No description provided for @importNewFolderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'New Privacy Folder Name'**
  String get importNewFolderNameLabel;

  /// No description provided for @importEnterFolderNamePrompt.
  ///
  /// In en, this message translates to:
  /// **'This backup does not contain the original folder name. Please enter a folder name.'**
  String get importEnterFolderNamePrompt;

  /// No description provided for @renamePrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Privacy Folder'**
  String get renamePrivacyFolder;

  /// No description provided for @privacyFolderRenamedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder renamed to \"{name}\"'**
  String privacyFolderRenamedNotice(String name);

  /// No description provided for @largeFilePagedNotice.
  ///
  /// In en, this message translates to:
  /// **'Large file read-only mode ({start} – {end} / {total})'**
  String largeFilePagedNotice(String start, String end, String total);

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get nextPage;

  /// No description provided for @jumpToPosition.
  ///
  /// In en, this message translates to:
  /// **'Jump to Position'**
  String get jumpToPosition;

  /// No description provided for @deletePrivacyFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Privacy Folder'**
  String get deletePrivacyFolder;

  /// No description provided for @deletePrivacyFolderWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete privacy folder \"{name}\" and all encrypted files inside it, along with its stored key on this device. This action cannot be undone.'**
  String deletePrivacyFolderWarning(String name);

  /// No description provided for @deletePrivacyFolderConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Type \"{name}\" to confirm deletion'**
  String deletePrivacyFolderConfirmLabel(String name);

  /// No description provided for @privacyFolderDeletedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" has been permanently deleted'**
  String privacyFolderDeletedNotice(String name);

  /// No description provided for @privacyMediaAudio.
  ///
  /// In en, this message translates to:
  /// **'Private Audio'**
  String get privacyMediaAudio;

  /// No description provided for @privacyMediaVideo.
  ///
  /// In en, this message translates to:
  /// **'Private Video'**
  String get privacyMediaVideo;

  /// No description provided for @vaultAutoLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock in background'**
  String get vaultAutoLockTitle;

  /// No description provided for @vaultAutoLockImmediate.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get vaultAutoLockImmediate;

  /// No description provided for @vaultAutoLockMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String vaultAutoLockMinutes(int minutes);

  /// No description provided for @vaultAutoLockNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get vaultAutoLockNever;

  /// No description provided for @vaultConfirmExternalOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm before external open & share'**
  String get vaultConfirmExternalOpenTitle;

  /// No description provided for @vaultConfirmExternalOpenDesc.
  ///
  /// In en, this message translates to:
  /// **'Warn before exporting a decrypted temporary copy to other apps'**
  String get vaultConfirmExternalOpenDesc;

  /// No description provided for @vaultExternalOpenWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Open with external app?'**
  String get vaultExternalOpenWarningTitle;

  /// No description provided for @vaultExternalOpenWarningBody.
  ///
  /// In en, this message translates to:
  /// **'This file will be temporarily decrypted and passed to another app outside the privacy folder. Remove any saved copy in that app afterward if needed.'**
  String get vaultExternalOpenWarningBody;

  /// No description provided for @dontAskAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get dontAskAgain;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @vaultVideoThumbnailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder video thumbnails'**
  String get vaultVideoThumbnailsTitle;

  /// No description provided for @vaultVideoThumbnailsDesc.
  ///
  /// In en, this message translates to:
  /// **'Decode and cache encrypted video preview frames on demand (off by default to save battery)'**
  String get vaultVideoThumbnailsDesc;

  /// No description provided for @vaultSecuritySettings.
  ///
  /// In en, this message translates to:
  /// **'Password & Unlock Method'**
  String get vaultSecuritySettings;

  /// No description provided for @vaultChangePasswordOption.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get vaultChangePasswordOption;

  /// No description provided for @vaultSwitchToSystemOption.
  ///
  /// In en, this message translates to:
  /// **'Switch to system unlock'**
  String get vaultSwitchToSystemOption;

  /// No description provided for @vaultSwitchToPasswordOption.
  ///
  /// In en, this message translates to:
  /// **'Switch to separate password'**
  String get vaultSwitchToPasswordOption;

  /// No description provided for @vaultCurrentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get vaultCurrentPasswordLabel;

  /// No description provided for @vaultNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New password (8–128 chars)'**
  String get vaultNewPasswordLabel;

  /// No description provided for @vaultOldBackupsPasswordNotice.
  ///
  /// In en, this message translates to:
  /// **'Existing .fpmvault backup archives exported earlier still require the password used when they were created.'**
  String get vaultOldBackupsPasswordNotice;

  /// No description provided for @vaultSwitchToSystemBackupNotice.
  ///
  /// In en, this message translates to:
  /// **'Keep a .fpmvault backup in a safe place. If you move to another device, Keychain/Keystore keys will not migrate encrypted folders.'**
  String get vaultSwitchToSystemBackupNotice;

  /// No description provided for @vaultSecurityUpdatedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder security settings updated'**
  String get vaultSecurityUpdatedNotice;

  /// No description provided for @vaultFolderInfo.
  ///
  /// In en, this message translates to:
  /// **'Folder Info & Storage'**
  String get vaultFolderInfo;

  /// No description provided for @vaultStatsFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get vaultStatsFiles;

  /// No description provided for @vaultStatsFolders.
  ///
  /// In en, this message translates to:
  /// **'Subfolders'**
  String get vaultStatsFolders;

  /// No description provided for @vaultStatsPlainSize.
  ///
  /// In en, this message translates to:
  /// **'Content Size'**
  String get vaultStatsPlainSize;

  /// No description provided for @vaultStatsDiskUsage.
  ///
  /// In en, this message translates to:
  /// **'Disk Usage'**
  String get vaultStatsDiskUsage;

  /// No description provided for @vaultStatsOrphaned.
  ///
  /// In en, this message translates to:
  /// **'Reclaimable Orphaned Data'**
  String get vaultStatsOrphaned;

  /// No description provided for @vaultStatsOrphanDetail.
  ///
  /// In en, this message translates to:
  /// **'{count} items ({size})'**
  String vaultStatsOrphanDetail(int count, String size);

  /// No description provided for @vaultCleanupOrphansAction.
  ///
  /// In en, this message translates to:
  /// **'Clean Up Orphaned Space'**
  String get vaultCleanupOrphansAction;

  /// No description provided for @vaultCleanupResultNotice.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} orphaned files and freed {size}'**
  String vaultCleanupResultNotice(int count, String size);

  /// No description provided for @backupProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} ({percent}%)'**
  String backupProgressLabel(String done, String total, int percent);

  /// No description provided for @backupCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get backupCancelling;

  /// No description provided for @backupCancelledNotice.
  ///
  /// In en, this message translates to:
  /// **'Backup operation cancelled'**
  String get backupCancelledNotice;

  /// No description provided for @deleteVaultPermanentWarning.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the selected items from the privacy folder without moving them to the Recycle Bin.'**
  String get deleteVaultPermanentWarning;

  /// No description provided for @showQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR Code'**
  String get showQrCode;

  /// No description provided for @scanQrToConnect.
  ///
  /// In en, this message translates to:
  /// **'Scan with your phone to open in browser'**
  String get scanQrToConnect;

  /// No description provided for @newTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get newTab;

  /// No description provided for @closeTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get closeTab;

  /// No description provided for @openInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in New Tab'**
  String get openInNewTab;

  /// No description provided for @copyToOtherPane.
  ///
  /// In en, this message translates to:
  /// **'Copy to Other Pane'**
  String get copyToOtherPane;

  /// No description provided for @moveToOtherPane.
  ///
  /// In en, this message translates to:
  /// **'Move to Other Pane'**
  String get moveToOtherPane;

  /// No description provided for @pdfViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'PDF Viewer'**
  String get pdfViewerTitle;

  /// No description provided for @pdfPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {current} / {total}'**
  String pdfPageOf(int current, int total);

  /// No description provided for @pdfSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search text in PDF…'**
  String get pdfSearchHint;

  /// No description provided for @pdfJumpToPage.
  ///
  /// In en, this message translates to:
  /// **'Jump to page'**
  String get pdfJumpToPage;

  /// No description provided for @pdfOutline.
  ///
  /// In en, this message translates to:
  /// **'Table of Contents'**
  String get pdfOutline;

  /// No description provided for @pdfNoOutline.
  ///
  /// In en, this message translates to:
  /// **'No outline in this document'**
  String get pdfNoOutline;

  /// No description provided for @pdfZeroDiskBadge.
  ///
  /// In en, this message translates to:
  /// **'In-Memory · Zero Disk'**
  String get pdfZeroDiskBadge;

  /// No description provided for @scanLanDevices.
  ///
  /// In en, this message translates to:
  /// **'Scan LAN Devices'**
  String get scanLanDevices;

  /// No description provided for @scanningLan.
  ///
  /// In en, this message translates to:
  /// **'Scanning local network…'**
  String get scanningLan;

  /// No description provided for @noLanDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No SMB / SFTP / WebDAV / FTP devices found on LAN'**
  String get noLanDevicesFound;

  /// No description provided for @storageAnalyzer.
  ///
  /// In en, this message translates to:
  /// **'Storage Analyzer'**
  String get storageAnalyzer;

  /// No description provided for @storageAnalyzerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Folder size ranking, file types & largest files'**
  String get storageAnalyzerSubtitle;

  /// No description provided for @topFolders.
  ///
  /// In en, this message translates to:
  /// **'Largest Folders'**
  String get topFolders;

  /// No description provided for @topFiles.
  ///
  /// In en, this message translates to:
  /// **'Largest Files'**
  String get topFiles;

  /// No description provided for @fileTypesBreakdown.
  ///
  /// In en, this message translates to:
  /// **'By File Type'**
  String get fileTypesBreakdown;

  /// No description provided for @storageUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} used of {total} ({free} free)'**
  String storageUsedOf(String used, String total, String free);

  /// No description provided for @duplicateFinder.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Finder'**
  String get duplicateFinder;

  /// No description provided for @duplicateFinderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'3-stage SHA-256 duplicate scan & cleanup'**
  String get duplicateFinderSubtitle;

  /// No description provided for @keepNewest.
  ///
  /// In en, this message translates to:
  /// **'Keep Newest'**
  String get keepNewest;

  /// No description provided for @keepOldest.
  ///
  /// In en, this message translates to:
  /// **'Keep Oldest'**
  String get keepOldest;

  /// No description provided for @keepShortestPath.
  ///
  /// In en, this message translates to:
  /// **'Keep Shortest Path'**
  String get keepShortestPath;

  /// No description provided for @cleanSelectedDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Clean Selected ({count})'**
  String cleanSelectedDuplicates(int count);

  /// No description provided for @wastedSpace.
  ///
  /// In en, this message translates to:
  /// **'Reclaimable: {size}'**
  String wastedSpace(String size);

  /// No description provided for @noDuplicatesFound.
  ///
  /// In en, this message translates to:
  /// **'No duplicate files found'**
  String get noDuplicatesFound;

  /// No description provided for @categoryDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get categoryDocuments;

  /// No description provided for @categoryVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get categoryVideos;

  /// No description provided for @categoryAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get categoryAudio;

  /// No description provided for @categoryArchives.
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get categoryArchives;

  /// No description provided for @categoryDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get categoryDownloads;

  /// No description provided for @categoryApks.
  ///
  /// In en, this message translates to:
  /// **'Installers'**
  String get categoryApks;

  /// No description provided for @globalSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files, bookmarks & recent…'**
  String get globalSearchHint;

  /// No description provided for @advancedSearch.
  ///
  /// In en, this message translates to:
  /// **'Advanced Search'**
  String get advancedSearch;

  /// No description provided for @grepContentSearch.
  ///
  /// In en, this message translates to:
  /// **'Content Search (Grep)'**
  String get grepContentSearch;

  /// No description provided for @matchContains.
  ///
  /// In en, this message translates to:
  /// **'Contains'**
  String get matchContains;

  /// No description provided for @matchWildcard.
  ///
  /// In en, this message translates to:
  /// **'Wildcard (* ?)'**
  String get matchWildcard;

  /// No description provided for @matchRegex.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get matchRegex;

  /// No description provided for @minSizeMb.
  ///
  /// In en, this message translates to:
  /// **'Min size (MB)'**
  String get minSizeMb;

  /// No description provided for @maxSizeMb.
  ///
  /// In en, this message translates to:
  /// **'Max size (MB)'**
  String get maxSizeMb;

  /// No description provided for @modifiedDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Modified within (days)'**
  String get modifiedDaysAgo;

  /// No description provided for @pauseTask.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseTask;

  /// No description provided for @resumeTask.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeTask;

  /// No description provided for @retryFailedItems.
  ///
  /// In en, this message translates to:
  /// **'Retry Failed ({count})'**
  String retryFailedItems(int count);

  /// No description provided for @taskPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get taskPaused;

  /// No description provided for @rateLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Speed Limit'**
  String get rateLimitLabel;

  /// No description provided for @rateLimitUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get rateLimitUnlimited;

  /// No description provided for @encryptWithPassword.
  ///
  /// In en, this message translates to:
  /// **'Encrypt with password (AES-256)'**
  String get encryptWithPassword;

  /// No description provided for @archivePasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Archive Password Required'**
  String get archivePasswordRequired;

  /// No description provided for @archivePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter archive password'**
  String get archivePasswordHint;

  /// No description provided for @archiveWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect archive password'**
  String get archiveWrongPassword;

  /// No description provided for @subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitles;

  /// No description provided for @subtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get subtitleOff;

  /// No description provided for @loadExternalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load Subtitle from Files…'**
  String get loadExternalSubtitle;

  /// No description provided for @subtitleAutoLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded subtitle: {name}'**
  String subtitleAutoLoaded(String name);

  /// No description provided for @pictureInPicture.
  ///
  /// In en, this message translates to:
  /// **'Picture in Picture'**
  String get pictureInPicture;

  /// No description provided for @directorySync.
  ///
  /// In en, this message translates to:
  /// **'Directory Sync & Backup'**
  String get directorySync;

  /// No description provided for @directorySyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Incremental, mirror or two-way sync across local & remote'**
  String get directorySyncSubtitle;

  /// No description provided for @syncModeIncremental.
  ///
  /// In en, this message translates to:
  /// **'Incremental (Copy new & updated)'**
  String get syncModeIncremental;

  /// No description provided for @syncModeMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror (Exact copy, deletes extra files)'**
  String get syncModeMirror;

  /// No description provided for @syncModeBidirectional.
  ///
  /// In en, this message translates to:
  /// **'Two-Way Sync'**
  String get syncModeBidirectional;

  /// No description provided for @syncPreviewChanges.
  ///
  /// In en, this message translates to:
  /// **'Preview Changes'**
  String get syncPreviewChanges;

  /// No description provided for @syncStart.
  ///
  /// In en, this message translates to:
  /// **'Start Sync'**
  String get syncStart;

  /// No description provided for @syncNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Directories are already in sync'**
  String get syncNoChanges;

  /// No description provided for @offlinePinned.
  ///
  /// In en, this message translates to:
  /// **'Offline Pinned Files'**
  String get offlinePinned;

  /// No description provided for @offlinePinnedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Managed offline copies of remote files'**
  String get offlinePinnedSubtitle;

  /// No description provided for @pinOffline.
  ///
  /// In en, this message translates to:
  /// **'Pin for Offline'**
  String get pinOffline;

  /// No description provided for @unpinOffline.
  ///
  /// In en, this message translates to:
  /// **'Remove Offline Pin'**
  String get unpinOffline;

  /// No description provided for @pinnedOfflineNotice.
  ///
  /// In en, this message translates to:
  /// **'Pinned \"{name}\" for offline access'**
  String pinnedOfflineNotice(String name);

  /// No description provided for @checksumsTitle.
  ///
  /// In en, this message translates to:
  /// **'Checksums (MD5 / SHA-1 / SHA-256)'**
  String get checksumsTitle;

  /// No description provided for @computeChecksums.
  ///
  /// In en, this message translates to:
  /// **'Compute Checksums'**
  String get computeChecksums;

  /// No description provided for @expectedHashHint.
  ///
  /// In en, this message translates to:
  /// **'Paste expected hash to verify…'**
  String get expectedHashHint;

  /// No description provided for @hashMatches.
  ///
  /// In en, this message translates to:
  /// **'Checksum matches'**
  String get hashMatches;

  /// No description provided for @hashMismatch.
  ///
  /// In en, this message translates to:
  /// **'Checksum does NOT match'**
  String get hashMismatch;

  /// No description provided for @structuredView.
  ///
  /// In en, this message translates to:
  /// **'Structured View'**
  String get structuredView;

  /// No description provided for @rawTextView.
  ///
  /// In en, this message translates to:
  /// **'Raw Text'**
  String get rawTextView;

  /// No description provided for @copyJsonPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyJsonPath;

  /// No description provided for @compareDiff.
  ///
  /// In en, this message translates to:
  /// **'Compare Diff'**
  String get compareDiff;

  /// No description provided for @diffUnified.
  ///
  /// In en, this message translates to:
  /// **'Unified'**
  String get diffUnified;

  /// No description provided for @diffSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side-by-Side'**
  String get diffSideBySide;

  /// No description provided for @diffOnlyInLeft.
  ///
  /// In en, this message translates to:
  /// **'Only in Left'**
  String get diffOnlyInLeft;

  /// No description provided for @diffOnlyInRight.
  ///
  /// In en, this message translates to:
  /// **'Only in Right'**
  String get diffOnlyInRight;

  /// No description provided for @diffModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get diffModified;

  /// No description provided for @diffIdentical.
  ///
  /// In en, this message translates to:
  /// **'Identical'**
  String get diffIdentical;

  /// No description provided for @unixPermissions.
  ///
  /// In en, this message translates to:
  /// **'Unix Permissions (chmod)'**
  String get unixPermissions;

  /// No description provided for @permOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get permOwner;

  /// No description provided for @permGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get permGroup;

  /// No description provided for @permOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get permOther;

  /// No description provided for @applyPermissions.
  ///
  /// In en, this message translates to:
  /// **'Apply Permissions'**
  String get applyPermissions;

  /// No description provided for @permissionsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Permissions updated to {mode}'**
  String permissionsUpdated(String mode);

  /// No description provided for @lockVaultNow.
  ///
  /// In en, this message translates to:
  /// **'Lock Now'**
  String get lockVaultNow;

  /// No description provided for @deleteOriginalAfterImport.
  ///
  /// In en, this message translates to:
  /// **'Delete original file after importing to vault'**
  String get deleteOriginalAfterImport;

  /// No description provided for @vaultExternalOpenNotice.
  ///
  /// In en, this message translates to:
  /// **'Opening this file in an external app writes a temporary plaintext copy. Locking the privacy folder automatically deletes all temporary plaintext copies.'**
  String get vaultExternalOpenNotice;

  /// No description provided for @shareViaLan.
  ///
  /// In en, this message translates to:
  /// **'Share via LAN'**
  String get shareViaLan;

  /// No description provided for @calculateDirSize.
  ///
  /// In en, this message translates to:
  /// **'Calculate'**
  String get calculateDirSize;

  /// No description provided for @activeTasksBanner.
  ///
  /// In en, this message translates to:
  /// **'{count} active transfer(s)'**
  String activeTasksBanner(int count);

  /// No description provided for @jsonFormattedPreview.
  ///
  /// In en, this message translates to:
  /// **'Formatted'**
  String get jsonFormattedPreview;

  /// No description provided for @jsonTreeView.
  ///
  /// In en, this message translates to:
  /// **'Tree'**
  String get jsonTreeView;

  /// No description provided for @jsonIndentSpaces.
  ///
  /// In en, this message translates to:
  /// **'{count} spaces'**
  String jsonIndentSpaces(int count);

  /// No description provided for @jsonSortKeys.
  ///
  /// In en, this message translates to:
  /// **'Sort keys'**
  String get jsonSortKeys;

  /// No description provided for @jsonCopyFormatted.
  ///
  /// In en, this message translates to:
  /// **'Copy formatted JSON'**
  String get jsonCopyFormatted;

  /// No description provided for @jsonCopyMinified.
  ///
  /// In en, this message translates to:
  /// **'Copy minified JSON'**
  String get jsonCopyMinified;

  /// No description provided for @jsonCopiedFormatted.
  ///
  /// In en, this message translates to:
  /// **'Formatted JSON copied'**
  String get jsonCopiedFormatted;

  /// No description provided for @jsonCopiedMinified.
  ///
  /// In en, this message translates to:
  /// **'Minified JSON copied'**
  String get jsonCopiedMinified;

  /// No description provided for @jsonInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON format'**
  String get jsonInvalidFormat;

  /// No description provided for @jsonExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all'**
  String get jsonExpandAll;

  /// No description provided for @jsonCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse all'**
  String get jsonCollapseAll;

  /// No description provided for @jsonFormatInEditor.
  ///
  /// In en, this message translates to:
  /// **'Format JSON'**
  String get jsonFormatInEditor;

  /// No description provided for @jsonLinesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String jsonLinesCount(int count);

  /// No description provided for @jsonMatchesCount.
  ///
  /// In en, this message translates to:
  /// **'{current}/{total} matches'**
  String jsonMatchesCount(int current, int total);

  /// No description provided for @vaultAlwaysVisibleTitle.
  ///
  /// In en, this message translates to:
  /// **'Always Show'**
  String get vaultAlwaysVisibleTitle;

  /// No description provided for @vaultAlwaysVisibleDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep this privacy folder visible when locked. Opening it still requires authentication and respects auto-lock timeout.'**
  String get vaultAlwaysVisibleDesc;

  /// No description provided for @lockedBadge.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedBadge;

  /// No description provided for @vaultUnlockToOpen.
  ///
  /// In en, this message translates to:
  /// **'Unlock & Open'**
  String get vaultUnlockToOpen;

  /// No description provided for @vaultUnpinAlwaysVisible.
  ///
  /// In en, this message translates to:
  /// **'Stop Always Showing'**
  String get vaultUnpinAlwaysVisible;

  /// No description provided for @vaultPinnedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" set to always show'**
  String vaultPinnedNotice(String name);

  /// No description provided for @vaultUnpinnedNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" will hide when locked'**
  String vaultUnpinnedNotice(String name);

  /// No description provided for @vaultLockedKeepVisibleNotice.
  ///
  /// In en, this message translates to:
  /// **'Privacy folder \"{name}\" locked'**
  String vaultLockedKeepVisibleNotice(String name);

  /// No description provided for @searchCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get searchCategoryAll;

  /// No description provided for @searchCategoryCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get searchCategoryCode;

  /// No description provided for @searchCategoryFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get searchCategoryFolders;

  /// No description provided for @searchFilesAndFolders.
  ///
  /// In en, this message translates to:
  /// **'Files & Folders'**
  String get searchFilesAndFolders;

  /// No description provided for @searchEnterQueryHint.
  ///
  /// In en, this message translates to:
  /// **'Type to search files, folders, bookmarks, remotes & history'**
  String get searchEnterQueryHint;

  /// No description provided for @searchingFilesProgress.
  ///
  /// In en, this message translates to:
  /// **'Searching files…'**
  String get searchingFilesProgress;

  /// No description provided for @collapseSidebar.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get collapseSidebar;

  /// No description provided for @expandSidebar.
  ///
  /// In en, this message translates to:
  /// **'Expand sidebar'**
  String get expandSidebar;

  /// No description provided for @categoryAllFilter.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get categoryAllFilter;

  /// No description provided for @categorySummary.
  ///
  /// In en, this message translates to:
  /// **'{count} items · {size}'**
  String categorySummary(int count, String size);

  /// No description provided for @categoryScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning {category}…'**
  String categoryScanning(String category);

  /// No description provided for @categoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No {category} found'**
  String categoryEmptyTitle(String category);

  /// No description provided for @categoryEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Files in this category will appear here automatically.'**
  String get categoryEmptySubtitle;

  /// No description provided for @locateInFolder.
  ///
  /// In en, this message translates to:
  /// **'Locate in folder'**
  String get locateInFolder;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @filterCategoryHint.
  ///
  /// In en, this message translates to:
  /// **'Filter in {category}…'**
  String filterCategoryHint(String category);

  /// No description provided for @historyRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'History retention'**
  String get historyRetentionTitle;

  /// No description provided for @historyRetentionDesc.
  ///
  /// In en, this message translates to:
  /// **'Entries older than this are automatically removed. Set to 0 to disable history.'**
  String get historyRetentionDesc;

  /// No description provided for @historyRetentionDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Keep for {days} days'**
  String historyRetentionDaysLabel(int days);

  /// No description provided for @historyRetentionDaysShort.
  ///
  /// In en, this message translates to:
  /// **'{days}d'**
  String historyRetentionDaysShort(int days);

  /// No description provided for @historyRetentionDisabled.
  ///
  /// In en, this message translates to:
  /// **'Do not retain (0 days)'**
  String get historyRetentionDisabled;

  /// No description provided for @historyRetentionDisabledShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get historyRetentionDisabledShort;

  /// No description provided for @historyRetentionInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Retention days (0 = do not retain)'**
  String get historyRetentionInputLabel;

  /// No description provided for @historyRetentionInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-negative whole number'**
  String get historyRetentionInvalidInput;

  /// No description provided for @historyRetentionUpdatedDays.
  ///
  /// In en, this message translates to:
  /// **'History retention set to {days} days'**
  String historyRetentionUpdatedDays(int days);

  /// No description provided for @historyRetentionUpdatedOff.
  ///
  /// In en, this message translates to:
  /// **'History retention disabled and existing history cleared'**
  String get historyRetentionUpdatedOff;

  /// No description provided for @historyDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'History is disabled'**
  String get historyDisabledTitle;

  /// No description provided for @historyDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Retention is set to 0 days, so visited folders are not saved.'**
  String get historyDisabledSubtitle;

  /// No description provided for @historyRetentionChange.
  ///
  /// In en, this message translates to:
  /// **'Change retention'**
  String get historyRetentionChange;

  /// No description provided for @errorSftpHostKey.
  ///
  /// In en, this message translates to:
  /// **'SSH host key verification failed. Confirm the server identity or re-save the SFTP connection.\n({raw})'**
  String errorSftpHostKey(String raw);

  /// No description provided for @errorObjectStorageConfig.
  ///
  /// In en, this message translates to:
  /// **'Object storage configuration error. Check the bucket name, endpoint, region, and access keys.\n({raw})'**
  String errorObjectStorageConfig(String raw);

  /// No description provided for @errorSmbConnection.
  ///
  /// In en, this message translates to:
  /// **'SMB share connection failed. Verify the share name, username/password, and SMB port (445).\n({raw})'**
  String errorSmbConnection(String raw);

  /// No description provided for @errorArchivePassword.
  ///
  /// In en, this message translates to:
  /// **'Archive password is missing or incorrect. Re-enter the password and try again.\n({raw})'**
  String errorArchivePassword(String raw);

  /// No description provided for @errorDiskFull.
  ///
  /// In en, this message translates to:
  /// **'Not enough free storage space on the destination volume.\n({raw})'**
  String errorDiskFull(String raw);

  /// No description provided for @recoveryGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get recoveryGrantPermission;

  /// No description provided for @recoveryEditConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get recoveryEditConnection;

  /// No description provided for @recoveryEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter Password'**
  String get recoveryEnterPassword;

  /// No description provided for @recoveryFreeUpSpace.
  ///
  /// In en, this message translates to:
  /// **'Analyze Space'**
  String get recoveryFreeUpSpace;

  /// No description provided for @navDomainStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get navDomainStorage;

  /// No description provided for @navDomainDiscover.
  ///
  /// In en, this message translates to:
  /// **'Search & Library'**
  String get navDomainDiscover;

  /// No description provided for @navDomainTools.
  ///
  /// In en, this message translates to:
  /// **'Tools & Tasks'**
  String get navDomainTools;

  /// No description provided for @autoSyncIntervalLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync schedule'**
  String get autoSyncIntervalLabel;

  /// No description provided for @autoSyncOff.
  ///
  /// In en, this message translates to:
  /// **'Manual only'**
  String get autoSyncOff;

  /// No description provided for @autoSyncEveryMinutes.
  ///
  /// In en, this message translates to:
  /// **'Every {minutes} min'**
  String autoSyncEveryMinutes(int minutes);

  /// No description provided for @offlineAutoSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-check & push on resume'**
  String get offlineAutoSyncTitle;

  /// No description provided for @providerCrypt.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Cloud Vault (Crypt)'**
  String get providerCrypt;

  /// No description provided for @cryptBackingRootLabel.
  ///
  /// In en, this message translates to:
  /// **'Backing Storage Root'**
  String get cryptBackingRootLabel;

  /// No description provided for @cryptBackingRootHint.
  ///
  /// In en, this message translates to:
  /// **'remote://my_s3 or /local/folder'**
  String get cryptBackingRootHint;

  /// No description provided for @cryptBasePrefixLabel.
  ///
  /// In en, this message translates to:
  /// **'Encrypted Subfolder Prefix'**
  String get cryptBasePrefixLabel;

  /// No description provided for @cryptPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Master Encryption Password'**
  String get cryptPasswordLabel;

  /// No description provided for @cryptPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Encryption password is required'**
  String get cryptPasswordRequired;

  /// No description provided for @cryptSaltOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional Salt / Passphrase'**
  String get cryptSaltOptionalLabel;

  /// No description provided for @cryptSaltHint.
  ///
  /// In en, this message translates to:
  /// **'Optional salt for key derivation'**
  String get cryptSaltHint;

  /// No description provided for @cryptInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Filenames and 64 KiB file chunks are end-to-end encrypted locally before uploading to the backing remote or folder.'**
  String get cryptInfoBanner;

  /// No description provided for @lanWebdavShareTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN WebDAV Server'**
  String get lanWebdavShareTitle;

  /// No description provided for @lanWebdavShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mount phone or remote storage from Finder, Explorer, or Infuse/Kodi'**
  String get lanWebdavShareSubtitle;

  /// No description provided for @shareViaLanWebdav.
  ///
  /// In en, this message translates to:
  /// **'Share via LAN WebDAV'**
  String get shareViaLanWebdav;

  /// No description provided for @webdavUsernameOptional.
  ///
  /// In en, this message translates to:
  /// **'Username (Optional)'**
  String get webdavUsernameOptional;

  /// No description provided for @webdavUrlCopied.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL copied to clipboard'**
  String get webdavUrlCopied;

  /// No description provided for @webdavServerRunning.
  ///
  /// In en, this message translates to:
  /// **'WebDAV server active at {url}'**
  String webdavServerRunning(String url);

  /// No description provided for @lanPeerTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN Direct Drop'**
  String get lanPeerTransferTitle;

  /// No description provided for @lanPeerTransferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover nearby FP File Manager devices and transfer files or clipboard text'**
  String get lanPeerTransferSubtitle;

  /// No description provided for @peerReceiveMode.
  ///
  /// In en, this message translates to:
  /// **'Receive Mode (Discoverable)'**
  String get peerReceiveMode;

  /// No description provided for @peerDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device Name'**
  String get peerDeviceName;

  /// No description provided for @peerScanDevices.
  ///
  /// In en, this message translates to:
  /// **'Scan LAN Devices'**
  String get peerScanDevices;

  /// No description provided for @peerScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning nearby devices...'**
  String get peerScanning;

  /// No description provided for @peerNoDevicesFound.
  ///
  /// In en, this message translates to:
  /// **'No FP File Manager receivers found on LAN'**
  String get peerNoDevicesFound;

  /// No description provided for @peerSendFiles.
  ///
  /// In en, this message translates to:
  /// **'Send Files'**
  String get peerSendFiles;

  /// No description provided for @peerSendClipboard.
  ///
  /// In en, this message translates to:
  /// **'Send Clipboard Text'**
  String get peerSendClipboard;

  /// No description provided for @peerManualAddressHint.
  ///
  /// In en, this message translates to:
  /// **'http://<LAN IP>:port'**
  String get peerManualAddressHint;

  /// No description provided for @peerIncomingOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming transfer from {sender}'**
  String peerIncomingOfferTitle(String sender);

  /// No description provided for @peerAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get peerAccept;

  /// No description provided for @peerReject.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get peerReject;

  /// No description provided for @peerSentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Sent {count} file(s)'**
  String peerSentSuccess(int count);

  /// No description provided for @peerOfferSent.
  ///
  /// In en, this message translates to:
  /// **'Text sent to device'**
  String get peerOfferSent;

  /// No description provided for @sendToLanDevice.
  ///
  /// In en, this message translates to:
  /// **'Send to LAN Device'**
  String get sendToLanDevice;

  /// No description provided for @fastIndexReady.
  ///
  /// In en, this message translates to:
  /// **'Fast index: {count} items'**
  String fastIndexReady(int count);

  /// No description provided for @fastIndexNotBuilt.
  ///
  /// In en, this message translates to:
  /// **'Fast index not built for this folder'**
  String get fastIndexNotBuilt;

  /// No description provided for @fastIndexBuild.
  ///
  /// In en, this message translates to:
  /// **'Build Index'**
  String get fastIndexBuild;

  /// No description provided for @fastIndexRebuild.
  ///
  /// In en, this message translates to:
  /// **'Rebuild Index'**
  String get fastIndexRebuild;

  /// No description provided for @fastIndexBuilding.
  ///
  /// In en, this message translates to:
  /// **'Indexing...'**
  String get fastIndexBuilding;

  /// No description provided for @fastIndexClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Index'**
  String get fastIndexClear;

  /// No description provided for @fastIndexCleared.
  ///
  /// In en, this message translates to:
  /// **'Fast index cleared'**
  String get fastIndexCleared;

  /// No description provided for @readingModeSingle.
  ///
  /// In en, this message translates to:
  /// **'Single Page'**
  String get readingModeSingle;

  /// No description provided for @readingModeWebtoon.
  ///
  /// In en, this message translates to:
  /// **'Webtoon Scroll'**
  String get readingModeWebtoon;

  /// No description provided for @readingModeDouble.
  ///
  /// In en, this message translates to:
  /// **'Double Page'**
  String get readingModeDouble;

  /// No description provided for @stripExifAction.
  ///
  /// In en, this message translates to:
  /// **'Strip EXIF & Save Copy'**
  String get stripExifAction;

  /// No description provided for @stripExifDone.
  ///
  /// In en, this message translates to:
  /// **'Saved privacy-clean copy: {path}'**
  String stripExifDone(String path);

  /// No description provided for @stripExifBatchAction.
  ///
  /// In en, this message translates to:
  /// **'Strip EXIF'**
  String get stripExifBatchAction;

  /// No description provided for @stripExifBatchDone.
  ///
  /// In en, this message translates to:
  /// **'Saved EXIF-stripped copies for {count} image(s)'**
  String stripExifBatchDone(int count);

  /// No description provided for @openInTerminal.
  ///
  /// In en, this message translates to:
  /// **'Open in Terminal'**
  String get openInTerminal;

  /// No description provided for @openInEditor.
  ///
  /// In en, this message translates to:
  /// **'Open in Editor'**
  String get openInEditor;

  /// No description provided for @copyFullPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Full Path'**
  String get copyFullPath;

  /// No description provided for @copyVfsPath.
  ///
  /// In en, this message translates to:
  /// **'Copy VFS Path'**
  String get copyVfsPath;

  /// No description provided for @photoBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo Auto Backup'**
  String get photoBackupTitle;

  /// No description provided for @photoBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Incrementally back up new photos to NAS, S3, WebDAV, or Privacy Vault'**
  String get photoBackupSubtitle;

  /// No description provided for @photoBackupEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Automatic Incremental Backup'**
  String get photoBackupEnable;

  /// No description provided for @photoBackupWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Back up on Wi-Fi only'**
  String get photoBackupWifiOnly;

  /// No description provided for @photoBackupTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup Destination'**
  String get photoBackupTargetLabel;

  /// No description provided for @photoBackupSelectTarget.
  ///
  /// In en, this message translates to:
  /// **'Select Destination'**
  String get photoBackupSelectTarget;

  /// No description provided for @photoBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Back Up Now'**
  String get photoBackupNow;

  /// No description provided for @photoBackupRunning.
  ///
  /// In en, this message translates to:
  /// **'Backing up new photos...'**
  String get photoBackupRunning;

  /// No description provided for @photoBackupStats.
  ///
  /// In en, this message translates to:
  /// **'{count} photos backed up'**
  String photoBackupStats(int count);

  /// No description provided for @photoBackupNoTarget.
  ///
  /// In en, this message translates to:
  /// **'Please choose a backup destination first'**
  String get photoBackupNoTarget;

  /// No description provided for @photoBackupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Backed up {count} new photo(s)'**
  String photoBackupCompleted(int count);

  /// No description provided for @pinToHomeScreen.
  ///
  /// In en, this message translates to:
  /// **'Pin to Home Screen'**
  String get pinToHomeScreen;

  /// No description provided for @pinToHomeScreenSuccess.
  ///
  /// In en, this message translates to:
  /// **'Shortcut \"{name}\" pinned to Home Screen'**
  String pinToHomeScreenSuccess(String name);

  /// No description provided for @pinToHomeScreenUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Home screen pinning is not supported on this platform'**
  String get pinToHomeScreenUnsupported;

  /// No description provided for @storagePools.
  ///
  /// In en, this message translates to:
  /// **'Storage Pools'**
  String get storagePools;

  /// No description provided for @storagePoolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Aggregate SFTP, S3 & WebDAV into one replicated pool'**
  String get storagePoolsSubtitle;

  /// No description provided for @createStoragePool.
  ///
  /// In en, this message translates to:
  /// **'Create Storage Pool'**
  String get createStoragePool;

  /// No description provided for @editStoragePool.
  ///
  /// In en, this message translates to:
  /// **'Edit Storage Pool'**
  String get editStoragePool;

  /// No description provided for @noStoragePools.
  ///
  /// In en, this message translates to:
  /// **'No storage pools configured'**
  String get noStoragePools;

  /// No description provided for @noStoragePoolsDesc.
  ///
  /// In en, this message translates to:
  /// **'Combine multiple SFTP, S3, or WebDAV connections with failure-domain 2x replication, chunking, and optional encryption.'**
  String get noStoragePoolsDesc;

  /// No description provided for @poolName.
  ///
  /// In en, this message translates to:
  /// **'Pool Name'**
  String get poolName;

  /// No description provided for @poolNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Media Aggregate Pool'**
  String get poolNameHint;

  /// No description provided for @poolChunkSize.
  ///
  /// In en, this message translates to:
  /// **'Chunk Size'**
  String get poolChunkSize;

  /// No description provided for @poolEncryptEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Client-Side AES-GCM Encryption'**
  String get poolEncryptEnable;

  /// No description provided for @poolEncryptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypts chunk payloads and metadata snapshots before upload'**
  String get poolEncryptSubtitle;

  /// No description provided for @poolPassphrase.
  ///
  /// In en, this message translates to:
  /// **'Encryption Passphrase'**
  String get poolPassphrase;

  /// No description provided for @poolPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep existing passphrase'**
  String get poolPassphraseHint;

  /// No description provided for @poolSelectNodes.
  ///
  /// In en, this message translates to:
  /// **'Member Storage Nodes'**
  String get poolSelectNodes;

  /// No description provided for @poolNeedRemotesFirst.
  ///
  /// In en, this message translates to:
  /// **'Add SFTP, S3, or WebDAV connections in Remote first.'**
  String get poolNeedRemotesFirst;

  /// No description provided for @poolFailureDomain.
  ///
  /// In en, this message translates to:
  /// **'Failure Domain'**
  String get poolFailureDomain;

  /// No description provided for @poolQuotaGb.
  ///
  /// In en, this message translates to:
  /// **'Quota (GB)'**
  String get poolQuotaGb;

  /// No description provided for @poolPrefix.
  ///
  /// In en, this message translates to:
  /// **'Remote Prefix'**
  String get poolPrefix;

  /// No description provided for @poolRoleRw.
  ///
  /// In en, this message translates to:
  /// **'Read/Write'**
  String get poolRoleRw;

  /// No description provided for @poolRoleRo.
  ///
  /// In en, this message translates to:
  /// **'Read-Only'**
  String get poolRoleRo;

  /// No description provided for @poolRoleDraining.
  ///
  /// In en, this message translates to:
  /// **'Draining'**
  String get poolRoleDraining;

  /// No description provided for @poolRoleOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get poolRoleOffline;

  /// No description provided for @poolMetaBackup.
  ///
  /// In en, this message translates to:
  /// **'Meta Backup'**
  String get poolMetaBackup;

  /// No description provided for @poolBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get poolBrowse;

  /// No description provided for @poolProbeHealth.
  ///
  /// In en, this message translates to:
  /// **'Probe Health'**
  String get poolProbeHealth;

  /// No description provided for @poolSyncMeta.
  ///
  /// In en, this message translates to:
  /// **'Sync Meta'**
  String get poolSyncMeta;

  /// No description provided for @poolHeal.
  ///
  /// In en, this message translates to:
  /// **'Heal'**
  String get poolHeal;

  /// No description provided for @poolGc.
  ///
  /// In en, this message translates to:
  /// **'Run GC'**
  String get poolGc;

  /// No description provided for @poolDrainNode.
  ///
  /// In en, this message translates to:
  /// **'Drain'**
  String get poolDrainNode;

  /// No description provided for @poolLogicalCapacity.
  ///
  /// In en, this message translates to:
  /// **'Effective Logical Capacity'**
  String get poolLogicalCapacity;

  /// No description provided for @poolPhysicalCapacity.
  ///
  /// In en, this message translates to:
  /// **'Total Physical Quota'**
  String get poolPhysicalCapacity;

  /// No description provided for @poolDegradedWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} chunk(s) below 2 replicas — run Heal to restore redundancy'**
  String poolDegradedWarning(int count);

  /// No description provided for @poolEncryptedBadge.
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get poolEncryptedBadge;

  /// No description provided for @poolPlaintextBadge.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get poolPlaintextBadge;

  /// No description provided for @poolMetaVersionBadge.
  ///
  /// In en, this message translates to:
  /// **'Meta v{version}'**
  String poolMetaVersionBadge(int version);

  /// No description provided for @poolDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove pool \"{name}\" from local configuration? Remote blob data will not be deleted.'**
  String poolDeleteConfirm(String name);

  /// No description provided for @poolDrainConfirm.
  ///
  /// In en, this message translates to:
  /// **'Migrate all chunks off \"{node}\" to other healthy nodes before taking it offline?'**
  String poolDrainConfirm(String node);

  /// No description provided for @poolSyncDone.
  ///
  /// In en, this message translates to:
  /// **'Metadata sync: {action} (v{version}, {uploaded} backup(s), {conflicts} conflict(s))'**
  String poolSyncDone(String action, int version, int uploaded, int conflicts);

  /// No description provided for @poolNodesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} node(s)'**
  String poolNodesCount(int count);

  /// No description provided for @lanTransferAndShareTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN Transfer & WebDAV Share'**
  String get lanTransferAndShareTitle;

  /// No description provided for @lanTransferAndShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Direct LAN drop, WebDAV mount, and browser upload/download'**
  String get lanTransferAndShareSubtitle;

  /// No description provided for @lanWebdavBrowserHint.
  ///
  /// In en, this message translates to:
  /// **'Open in any browser to upload/download files, or mount via Finder, Explorer, Infuse, or Kodi.'**
  String get lanWebdavBrowserHint;

  /// No description provided for @lanWebdavReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Disable read-only to allow browser uploads, new folders, and edits'**
  String get lanWebdavReadOnlyHint;

  /// No description provided for @photoBackupSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Backup Source Folders'**
  String get photoBackupSourceLabel;

  /// No description provided for @photoBackupSelectSource.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get photoBackupSelectSource;

  /// No description provided for @photoBackupSelectAlbums.
  ///
  /// In en, this message translates to:
  /// **'Select Albums'**
  String get photoBackupSelectAlbums;

  /// No description provided for @photoBackupDefaultSources.
  ///
  /// In en, this message translates to:
  /// **'Default gallery folders'**
  String get photoBackupDefaultSources;

  /// No description provided for @photoBackupAllAlbums.
  ///
  /// In en, this message translates to:
  /// **'All Photos & Videos'**
  String get photoBackupAllAlbums;

  /// No description provided for @photoBackupSelectedAlbumsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} album(s) selected'**
  String photoBackupSelectedAlbumsCount(int count);

  /// No description provided for @photoBackupResetSources.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get photoBackupResetSources;

  /// No description provided for @syncExcludeRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exclusion Rules'**
  String get syncExcludeRulesTitle;

  /// No description provided for @syncExcludeExtensionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Excluded File Types (Extensions)'**
  String get syncExcludeExtensionsLabel;

  /// No description provided for @syncExcludeExtensionsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. tmp, log, bak'**
  String get syncExcludeExtensionsHint;

  /// No description provided for @syncExcludeNamesLabel.
  ///
  /// In en, this message translates to:
  /// **'Excluded File Names'**
  String get syncExcludeNamesLabel;

  /// No description provided for @syncExcludeNamesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. .DS_Store, Thumbs.db, ~\$*'**
  String get syncExcludeNamesHint;

  /// No description provided for @syncExcludeDirsLabel.
  ///
  /// In en, this message translates to:
  /// **'Excluded Folders'**
  String get syncExcludeDirsLabel;

  /// No description provided for @syncExcludeDirsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. node_modules, .git, build/cache'**
  String get syncExcludeDirsHint;

  /// No description provided for @syncExcludePresets.
  ///
  /// In en, this message translates to:
  /// **'Quick Presets'**
  String get syncExcludePresets;

  /// No description provided for @syncPickExcludeDir.
  ///
  /// In en, this message translates to:
  /// **'Pick Folder'**
  String get syncPickExcludeDir;

  /// No description provided for @syncExcludedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} excluded'**
  String syncExcludedCount(int count);

  /// No description provided for @syncAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get syncAddRule;

  /// No description provided for @peerManualAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Device Address (Manual)'**
  String get peerManualAddressLabel;

  /// No description provided for @peerManualAddressExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. http://{hostPlaceholder}:port'**
  String peerManualAddressExample(String hostPlaceholder);

  /// No description provided for @emptyLabel.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get emptyLabel;

  /// No description provided for @itemCountConnections.
  ///
  /// In en, this message translates to:
  /// **'{count} connection(s)'**
  String itemCountConnections(int count);

  /// No description provided for @itemCountPools.
  ///
  /// In en, this message translates to:
  /// **'{count} pool(s)'**
  String itemCountPools(int count);

  /// No description provided for @itemCountBookmarks.
  ///
  /// In en, this message translates to:
  /// **'{count} bookmark(s)'**
  String itemCountBookmarks(int count);

  /// No description provided for @itemCountLocations.
  ///
  /// In en, this message translates to:
  /// **'{count} location(s)'**
  String itemCountLocations(int count);

  /// No description provided for @activeTasksRunningCount.
  ///
  /// In en, this message translates to:
  /// **'{count} running'**
  String activeTasksRunningCount(int count);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeDaysAgo(int count);

  /// No description provided for @deletedRelativeTime.
  ///
  /// In en, this message translates to:
  /// **'deleted {time}'**
  String deletedRelativeTime(String time);

  /// No description provided for @stopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop Sharing'**
  String get stopSharing;

  /// No description provided for @manageRemotes.
  ///
  /// In en, this message translates to:
  /// **'Manage Remotes'**
  String get manageRemotes;

  /// No description provided for @manageStoragePools.
  ///
  /// In en, this message translates to:
  /// **'Manage Storage Pools'**
  String get manageStoragePools;

  /// No description provided for @backupRestoreConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore Configuration'**
  String get backupRestoreConfigTitle;

  /// No description provided for @backupRestoreConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export or import remote connections, bookmarks, and preferences (optional AES-256 encrypted .fmbak)'**
  String get backupRestoreConfigSubtitle;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// No description provided for @exportMigrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Device Migration Backup'**
  String get exportMigrationTitle;

  /// No description provided for @exportMigrationPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Encryption Password (recommended)'**
  String get exportMigrationPasswordLabel;

  /// No description provided for @exportMigrationPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for plain JSON without credentials'**
  String get exportMigrationPasswordHint;

  /// No description provided for @exportIncludeCredentials.
  ///
  /// In en, this message translates to:
  /// **'Include passwords / keys (requires password)'**
  String get exportIncludeCredentials;

  /// No description provided for @copyJsonAction.
  ///
  /// In en, this message translates to:
  /// **'Copy JSON'**
  String get copyJsonAction;

  /// No description provided for @copyEncryptedAction.
  ///
  /// In en, this message translates to:
  /// **'Copy Encrypted'**
  String get copyEncryptedAction;

  /// No description provided for @saveBackupFileAction.
  ///
  /// In en, this message translates to:
  /// **'Save .fmbak'**
  String get saveBackupFileAction;

  /// No description provided for @saveJsonFileAction.
  ///
  /// In en, this message translates to:
  /// **'Save .json'**
  String get saveJsonFileAction;

  /// No description provided for @importMigrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Device Configuration'**
  String get importMigrationTitle;

  /// No description provided for @chooseBackupFileAction.
  ///
  /// In en, this message translates to:
  /// **'Choose .fmbak or .json File'**
  String get chooseBackupFileAction;

  /// No description provided for @importPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Or paste JSON / .fmbak text...'**
  String get importPasteHint;

  /// No description provided for @importPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Decryption Password (if encrypted)'**
  String get importPasswordLabel;

  /// No description provided for @importPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Required for .fmbak files with credentials'**
  String get importPasswordHint;

  /// No description provided for @importPasswordRequiredError.
  ///
  /// In en, this message translates to:
  /// **'Please enter the decryption password for this encrypted .fmbak backup.'**
  String get importPasswordRequiredError;

  /// No description provided for @exportSavedNotice.
  ///
  /// In en, this message translates to:
  /// **'Backup saved to {path}'**
  String exportSavedNotice(String path);

  /// No description provided for @exportCopiedNotice.
  ///
  /// In en, this message translates to:
  /// **'Backup copied to clipboard'**
  String get exportCopiedNotice;

  /// No description provided for @importSummaryNotice.
  ///
  /// In en, this message translates to:
  /// **'Imported {remotes} remote(s), {bookmarks} bookmark(s), {prefs} preference(s)'**
  String importSummaryNotice(int remotes, int bookmarks, int prefs);

  /// No description provided for @unencryptedCredentialsBanner.
  ///
  /// In en, this message translates to:
  /// **'Warning: OS secure keyring unavailable; remote passwords are saved in plaintext.'**
  String get unencryptedCredentialsBanner;

  /// No description provided for @remoteTestTimedOut.
  ///
  /// In en, this message translates to:
  /// **'timed out after 8 seconds'**
  String get remoteTestTimedOut;

  /// No description provided for @remoteImportFailedSummary.
  ///
  /// In en, this message translates to:
  /// **'; {count} failed: {details}'**
  String remoteImportFailedSummary(int count, String details);

  /// No description provided for @remoteBucketLabel.
  ///
  /// In en, this message translates to:
  /// **'Bucket: {bucket}'**
  String remoteBucketLabel(String bucket);

  /// No description provided for @keyringUnavailableBanner.
  ///
  /// In en, this message translates to:
  /// **'OS Keyring unavailable ({detail}). Credentials may not persist safely.'**
  String keyringUnavailableBanner(String detail);

  /// No description provided for @deleteRemotePoolWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: This remote is used by storage pool(s): {pools}. Deleting it will degrade those pools.'**
  String deleteRemotePoolWarning(String pools);

  /// No description provided for @poolConfirmGcTitle.
  ///
  /// In en, this message translates to:
  /// **'Run Garbage Collection?'**
  String get poolConfirmGcTitle;

  /// No description provided for @poolConfirmGcBody.
  ///
  /// In en, this message translates to:
  /// **'Purge unreferenced/deleted chunks from pool \"{name}\"? Deleted chunks cannot be recovered.'**
  String poolConfirmGcBody(String name);

  /// No description provided for @poolReplicationFactorLabel.
  ///
  /// In en, this message translates to:
  /// **'Replication Factor'**
  String get poolReplicationFactorLabel;

  /// No description provided for @poolMinNodesError.
  ///
  /// In en, this message translates to:
  /// **'Select at least {count} member node(s) for {count}x replication.'**
  String poolMinNodesError(int count);

  /// No description provided for @poolInvalidQuotaError.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid node quota (> 0 GB).'**
  String get poolInvalidQuotaError;

  /// No description provided for @poolPassphraseConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Encryption Passphrase'**
  String get poolPassphraseConfirmLabel;

  /// No description provided for @poolPassphraseMismatchError.
  ///
  /// In en, this message translates to:
  /// **'Encryption passphrases do not match.'**
  String get poolPassphraseMismatchError;

  /// No description provided for @poolEditLockedHint.
  ///
  /// In en, this message translates to:
  /// **'Chunk size and encryption cannot be changed after pool creation.'**
  String get poolEditLockedHint;

  /// No description provided for @poolNodeHealthSummary.
  ///
  /// In en, this message translates to:
  /// **'Health {pct}% · {ms} ms · {state}'**
  String poolNodeHealthSummary(int pct, int ms, String state);

  /// No description provided for @poolRoleShortRw.
  ///
  /// In en, this message translates to:
  /// **'RW'**
  String get poolRoleShortRw;

  /// No description provided for @poolRoleShortRo.
  ///
  /// In en, this message translates to:
  /// **'RO'**
  String get poolRoleShortRo;

  /// No description provided for @poolRoleShortDraining.
  ///
  /// In en, this message translates to:
  /// **'DRAINING'**
  String get poolRoleShortDraining;

  /// No description provided for @poolRoleShortOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get poolRoleShortOffline;

  /// No description provided for @poolCircuitClosed.
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get poolCircuitClosed;

  /// No description provided for @poolCircuitOpen.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get poolCircuitOpen;

  /// No description provided for @poolCircuitHalfOpen.
  ///
  /// In en, this message translates to:
  /// **'half-open'**
  String get poolCircuitHalfOpen;

  /// No description provided for @cryptChooseBackingRemote.
  ///
  /// In en, this message translates to:
  /// **'Choose Existing Remote / Local Folder'**
  String get cryptChooseBackingRemote;

  /// No description provided for @cryptLocalFolderOption.
  ///
  /// In en, this message translates to:
  /// **'Pick Local Folder...'**
  String get cryptLocalFolderOption;

  /// No description provided for @fileConflictBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" already exists in this folder. What should happen to it?'**
  String fileConflictBody(String name);

  /// No description provided for @filesConflictBody.
  ///
  /// In en, this message translates to:
  /// **'{count} items already exist in this folder. What should happen to them?'**
  String filesConflictBody(int count);

  /// No description provided for @offlineOverwriteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwrite remote changes?'**
  String get offlineOverwriteConfirmTitle;

  /// No description provided for @offlineOverwriteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" was also modified remotely. Overwrite the remote version with your local changes?'**
  String offlineOverwriteConfirmBody(String name);

  /// No description provided for @offlineDiscardLocalConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard local offline edits?'**
  String get offlineDiscardLocalConfirmTitle;

  /// No description provided for @offlineDiscardLocalConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" has un-synced local modifications or conflicts. Continuing will overwrite or remove the local changes.'**
  String offlineDiscardLocalConfirmBody(String name);

  /// No description provided for @offlineUploadedNotice.
  ///
  /// In en, this message translates to:
  /// **'Uploaded \"{name}\" to remote.'**
  String offlineUploadedNotice(String name);

  /// No description provided for @offlineCheckUpdatesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Check Updates'**
  String get offlineCheckUpdatesTooltip;

  /// No description provided for @offlineSyncAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sync All'**
  String get offlineSyncAllTooltip;

  /// No description provided for @offlineLruCapTooltip.
  ///
  /// In en, this message translates to:
  /// **'LRU Cache Cap'**
  String get offlineLruCapTooltip;

  /// No description provided for @offlineLruCapOption.
  ///
  /// In en, this message translates to:
  /// **'LRU Cap: {size}'**
  String offlineLruCapOption(String size);

  /// No description provided for @offlineUploadLocalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Upload local changes to remote'**
  String get offlineUploadLocalTooltip;

  /// No description provided for @offlineBannerSummary.
  ///
  /// In en, this message translates to:
  /// **'{count} pinned · {used} / {cap}'**
  String offlineBannerSummary(int count, String used, String cap);

  /// No description provided for @offlineStatusLocalModified.
  ///
  /// In en, this message translates to:
  /// **'Local Modified'**
  String get offlineStatusLocalModified;

  /// No description provided for @offlineStatusRemoteNewer.
  ///
  /// In en, this message translates to:
  /// **'Remote Newer'**
  String get offlineStatusRemoteNewer;

  /// No description provided for @offlineStatusConflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get offlineStatusConflict;

  /// No description provided for @offlineStatusSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get offlineStatusSynced;

  /// No description provided for @offlineStatusMissingLocal.
  ///
  /// In en, this message translates to:
  /// **'Missing Local'**
  String get offlineStatusMissingLocal;

  /// No description provided for @offlineStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offlineStatusOffline;

  /// No description provided for @browserSelectItemsFirst.
  ///
  /// In en, this message translates to:
  /// **'Select at least one item first.'**
  String get browserSelectItemsFirst;

  /// No description provided for @clipboardReadOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Clipboard: {count} item(s) ready (read-only folder)'**
  String clipboardReadOnlyHint(int count);

  /// No description provided for @peerTabDirectTransfer.
  ///
  /// In en, this message translates to:
  /// **'Direct Transfer'**
  String get peerTabDirectTransfer;

  /// No description provided for @peerTabWebdavShare.
  ///
  /// In en, this message translates to:
  /// **'WebDAV / Browser Share'**
  String get peerTabWebdavShare;

  /// No description provided for @peerPendingItemsToSend.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) ready to send'**
  String peerPendingItemsToSend(int count);

  /// No description provided for @peerReceiveFolderMustBeLocal.
  ///
  /// In en, this message translates to:
  /// **'Receive folder must be on local storage.'**
  String get peerReceiveFolderMustBeLocal;

  /// No description provided for @peerOpenReceivedFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get peerOpenReceivedFolder;

  /// No description provided for @peerCopyReceivedText.
  ///
  /// In en, this message translates to:
  /// **'Copy Text'**
  String get peerCopyReceivedText;

  /// No description provided for @peerTextCopied.
  ///
  /// In en, this message translates to:
  /// **'Received text copied to clipboard.'**
  String get peerTextCopied;

  /// No description provided for @peerWaitingForAccept.
  ///
  /// In en, this message translates to:
  /// **'Sending / waiting for peer to accept...'**
  String get peerWaitingForAccept;

  /// No description provided for @peerOfferStatusAccepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get peerOfferStatusAccepted;

  /// No description provided for @peerOfferStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get peerOfferStatusCompleted;

  /// No description provided for @peerOfferStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get peerOfferStatusRejected;

  /// No description provided for @peerOfferStatusReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get peerOfferStatusReceiving;

  /// No description provided for @photoBackupScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning photos & folders...'**
  String get photoBackupScanning;

  /// No description provided for @photoBackupCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get photoBackupCancel;

  /// No description provided for @photoBackupCancelledNotice.
  ///
  /// In en, this message translates to:
  /// **'Photo backup cancelled (uploaded {count}).'**
  String photoBackupCancelledNotice(int count);

  /// No description provided for @photoBackupResetHistory.
  ///
  /// In en, this message translates to:
  /// **'Reset Backup History'**
  String get photoBackupResetHistory;

  /// No description provided for @photoBackupResetHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear local backup history so previously backed-up photos will be uploaded again?'**
  String get photoBackupResetHistoryConfirm;

  /// No description provided for @photoBackupLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {time}'**
  String photoBackupLastRun(String time);

  /// No description provided for @photoBackupProgressCount.
  ///
  /// In en, this message translates to:
  /// **'{uploaded} / {total} uploaded'**
  String photoBackupProgressCount(int uploaded, int total);

  /// No description provided for @photoBackupOpenDestination.
  ///
  /// In en, this message translates to:
  /// **'Open Destination'**
  String get photoBackupOpenDestination;

  /// No description provided for @photoBackupVaultLocked.
  ///
  /// In en, this message translates to:
  /// **'Target Privacy Folder is locked'**
  String get photoBackupVaultLocked;

  /// No description provided for @photoBackupPermissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo Library Permission Needed'**
  String get photoBackupPermissionDeniedTitle;

  /// No description provided for @photoBackupPermissionDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Allow photo library access in system settings to choose albums or back up photos.'**
  String get photoBackupPermissionDeniedBody;

  /// No description provided for @photoBackupOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get photoBackupOpenSettings;

  /// No description provided for @syncSaveProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Sync Profile'**
  String get syncSaveProfileTitle;

  /// No description provided for @syncProfileNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Profile name'**
  String get syncProfileNameLabel;

  /// No description provided for @syncSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get syncSourceLabel;

  /// No description provided for @syncDestinationLabel.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get syncDestinationLabel;

  /// No description provided for @syncScanLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Scan limit reached; preview is truncated.'**
  String get syncScanLimitReached;

  /// No description provided for @syncSummaryChanges.
  ///
  /// In en, this message translates to:
  /// **'{changes} change(s) · {unchanged} unchanged'**
  String syncSummaryChanges(int changes, int unchanged);

  /// No description provided for @syncConfirmMirrorDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Mirror Deletions'**
  String get syncConfirmMirrorDeleteTitle;

  /// No description provided for @syncConfirmMirrorDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This sync will delete {count} extra file(s)/folder(s) from the destination. Continue?'**
  String syncConfirmMirrorDeleteBody(int count);

  /// No description provided for @syncConfirmDeleteProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Delete saved sync profile \"{name}\"?'**
  String syncConfirmDeleteProfileBody(String name);

  /// No description provided for @syncSwapFoldersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Swap source and destination'**
  String get syncSwapFoldersTooltip;

  /// No description provided for @syncSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get syncSelectAll;

  /// No description provided for @syncDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get syncDeselectAll;

  /// No description provided for @syncActionCopy.
  ///
  /// In en, this message translates to:
  /// **'COPY'**
  String get syncActionCopy;

  /// No description provided for @syncActionUpdate.
  ///
  /// In en, this message translates to:
  /// **'UPDATE'**
  String get syncActionUpdate;

  /// No description provided for @syncActionDelete.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get syncActionDelete;

  /// No description provided for @syncActionPullUpdate.
  ///
  /// In en, this message translates to:
  /// **'PULL UPDATE'**
  String get syncActionPullUpdate;

  /// No description provided for @syncEditConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit Folders'**
  String get syncEditConfig;

  /// No description provided for @syncAutoSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Last auto-sync failed: {error}'**
  String syncAutoSyncFailed(String error);

  /// No description provided for @taskStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get taskStatusPaused;

  /// No description provided for @taskRateLimitActive.
  ///
  /// In en, this message translates to:
  /// **'Limit: {limit}'**
  String taskRateLimitActive(String limit);

  /// No description provided for @taskFailedItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed items ({count})'**
  String taskFailedItemsTitle(int count);

  /// No description provided for @taskRetryStarted.
  ///
  /// In en, this message translates to:
  /// **'Retrying failed items in background.'**
  String get taskRetryStarted;

  /// No description provided for @analyzerStatsSummary.
  ///
  /// In en, this message translates to:
  /// **'{files} files · {folders} folders'**
  String analyzerStatsSummary(int files, int folders);

  /// No description provided for @analyzerScanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Analysis cancelled (showing partial results).'**
  String get analyzerScanCancelled;

  /// No description provided for @analyzerScanTruncated.
  ///
  /// In en, this message translates to:
  /// **'Reached scan limit; totals may exclude deeper folders.'**
  String get analyzerScanTruncated;

  /// No description provided for @analyzerRescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get analyzerRescan;

  /// No description provided for @duplicatesGroupCount.
  ///
  /// In en, this message translates to:
  /// **'{count} group(s)'**
  String duplicatesGroupCount(int count);

  /// No description provided for @duplicatesCopiesCount.
  ///
  /// In en, this message translates to:
  /// **'({count} copies)'**
  String duplicatesCopiesCount(int count);

  /// No description provided for @duplicatesEachSize.
  ///
  /// In en, this message translates to:
  /// **'{size} each'**
  String duplicatesEachSize(String size);

  /// No description provided for @duplicatesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) failed to delete'**
  String duplicatesDeleteFailed(int count);

  /// No description provided for @duplicatesAllCopiesWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} group(s) have ALL copies selected for deletion!'**
  String duplicatesAllCopiesWarning(int count);

  /// No description provided for @duplicatesClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get duplicatesClearSelection;

  /// No description provided for @duplicatesScanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Duplicate scan was cancelled.'**
  String get duplicatesScanCancelled;

  /// No description provided for @duplicatesTrashConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Move {count} duplicate item(s) to the Recycle Bin?'**
  String duplicatesTrashConfirmBody(int count);

  /// No description provided for @categoryTruncatedBanner.
  ///
  /// In en, this message translates to:
  /// **'Showing first {count} matching files (result limit reached).'**
  String categoryTruncatedBanner(int count);

  /// No description provided for @galleryLocateInFolder.
  ///
  /// In en, this message translates to:
  /// **'Locate in Folder'**
  String get galleryLocateInFolder;

  /// No description provided for @galleryUnsupportedFormatForPick.
  ///
  /// In en, this message translates to:
  /// **'This file type is not accepted by the caller.'**
  String get galleryUnsupportedFormatForPick;

  /// No description provided for @galleryExifSkippedNonJpeg.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} non-JPEG photo(s) (EXIF strip supports JPEG).'**
  String galleryExifSkippedNonJpeg(int count);

  /// No description provided for @searchFiltersLabel.
  ///
  /// In en, this message translates to:
  /// **'Filters ({count})'**
  String searchFiltersLabel(int count);

  /// No description provided for @searchAllTypes.
  ///
  /// In en, this message translates to:
  /// **'All Types'**
  String get searchAllTypes;

  /// No description provided for @pdfEncryptedError.
  ///
  /// In en, this message translates to:
  /// **'This PDF is encrypted or password-protected.'**
  String get pdfEncryptedError;

  /// No description provided for @pdfPageTextTitle.
  ///
  /// In en, this message translates to:
  /// **'Page {page} Text'**
  String pdfPageTextTitle(int page);

  /// No description provided for @pdfPageTextCopied.
  ///
  /// In en, this message translates to:
  /// **'Page text copied to clipboard.'**
  String get pdfPageTextCopied;

  /// No description provided for @pdfNoSelectableText.
  ///
  /// In en, this message translates to:
  /// **'No selectable text detected on this page (it may be a scanned image).'**
  String get pdfNoSelectableText;

  /// No description provided for @pdfSelectCopyPageText.
  ///
  /// In en, this message translates to:
  /// **'Select / Copy Page Text'**
  String get pdfSelectCopyPageText;

  /// No description provided for @pdfRenderPageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to render page {page}.'**
  String pdfRenderPageFailed(int page);

  /// No description provided for @structuredEmptyValue.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get structuredEmptyValue;

  /// No description provided for @structuredCsvTruncated.
  ///
  /// In en, this message translates to:
  /// **'Showing first {shown} of {total} rows.'**
  String structuredCsvTruncated(int shown, int total);

  /// No description provided for @copyXPath.
  ///
  /// In en, this message translates to:
  /// **'Copy XPath'**
  String get copyXPath;

  /// No description provided for @subtitleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unsupported or unreadable subtitle file.'**
  String get subtitleLoadFailed;

  /// No description provided for @diffTruncatedNotice.
  ///
  /// In en, this message translates to:
  /// **'Directory diff reached the entry limit; some deeper entries were omitted.'**
  String get diffTruncatedNotice;

  /// No description provided for @diffSyncFoldersAction.
  ///
  /// In en, this message translates to:
  /// **'Open in Sync'**
  String get diffSyncFoldersAction;

  /// No description provided for @vaultHtmlBrowserWarning.
  ///
  /// In en, this message translates to:
  /// **'Cannot open decrypted Privacy Folder HTML in an external browser (zero-disk policy).'**
  String get vaultHtmlBrowserWarning;

  /// No description provided for @poolStorageDirectory.
  ///
  /// In en, this message translates to:
  /// **'Storage Directory'**
  String get poolStorageDirectory;

  /// No description provided for @poolPickDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose Folder'**
  String get poolPickDirectory;

  /// No description provided for @poolReplicationBadge.
  ///
  /// In en, this message translates to:
  /// **'{count}x Replicas'**
  String poolReplicationBadge(int count);

  /// No description provided for @poolSetReplicationTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Replication Factor'**
  String get poolSetReplicationTitle;

  /// No description provided for @poolSetReplicationHint.
  ///
  /// In en, this message translates to:
  /// **'Applies immediately to new writes; run Heal to replicate existing files up to the new target.'**
  String get poolSetReplicationHint;

  /// No description provided for @poolNodeRealFreeWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Free {free} / {total}'**
  String poolNodeRealFreeWithTotal(String free, String total);

  /// No description provided for @poolNodeRealFreeOnly.
  ///
  /// In en, this message translates to:
  /// **'Free {free}'**
  String poolNodeRealFreeOnly(String free);

  /// No description provided for @poolNodeSpaceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Free space unavailable'**
  String get poolNodeSpaceUnavailable;

  /// No description provided for @poolNodeSpaceProbing.
  ///
  /// In en, this message translates to:
  /// **'Checking free space…'**
  String get poolNodeSpaceProbing;

  /// No description provided for @poolNodePoolUsed.
  ///
  /// In en, this message translates to:
  /// **'Pool used: {used}'**
  String poolNodePoolUsed(String used);

  /// No description provided for @poolNodeDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Dir: {dir}'**
  String poolNodeDirectoryLabel(String dir);

  /// No description provided for @remoteBatchExportAction.
  ///
  /// In en, this message translates to:
  /// **'Batch Encrypted Export'**
  String get remoteBatchExportAction;

  /// No description provided for @remoteBatchImportAction.
  ///
  /// In en, this message translates to:
  /// **'Batch Encrypted Import'**
  String get remoteBatchImportAction;

  /// No description provided for @remoteBatchExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Export Connections'**
  String get remoteBatchExportTitle;

  /// No description provided for @remoteBatchExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connections and credentials are encrypted with AES-256-GCM using your password.'**
  String get remoteBatchExportSubtitle;

  /// No description provided for @remoteBatchSelectCount.
  ///
  /// In en, this message translates to:
  /// **'Selected {selected} / {total}'**
  String remoteBatchSelectCount(int selected, int total);

  /// No description provided for @remoteBatchSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get remoteBatchSelectAll;

  /// No description provided for @remoteBatchDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get remoteBatchDeselectAll;

  /// No description provided for @remoteBatchUnreadableSkipped.
  ///
  /// In en, this message translates to:
  /// **'Unreadable credentials (cannot be exported)'**
  String get remoteBatchUnreadableSkipped;

  /// No description provided for @remoteBatchNoReadableToExport.
  ///
  /// In en, this message translates to:
  /// **'No readable remote connections available to export.'**
  String get remoteBatchNoReadableToExport;

  /// No description provided for @remoteBatchExportPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Encryption Password (Required)'**
  String get remoteBatchExportPasswordLabel;

  /// No description provided for @remoteBatchExportPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least {min} characters'**
  String remoteBatchExportPasswordHint(int min);

  /// No description provided for @remoteBatchExportPasswordConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm Encryption Password'**
  String get remoteBatchExportPasswordConfirmLabel;

  /// No description provided for @remoteBatchPasswordRequiredNote.
  ///
  /// In en, this message translates to:
  /// **'Remember this password — it is required when importing these connections.'**
  String get remoteBatchPasswordRequiredNote;

  /// No description provided for @remoteBatchPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters.'**
  String remoteBatchPasswordTooShort(int min);

  /// No description provided for @remoteBatchPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get remoteBatchPasswordMismatch;

  /// No description provided for @remoteBatchSaveFileAction.
  ///
  /// In en, this message translates to:
  /// **'Save Encrypted File'**
  String get remoteBatchSaveFileAction;

  /// No description provided for @remoteBatchShareFileAction.
  ///
  /// In en, this message translates to:
  /// **'Export / Share File'**
  String get remoteBatchShareFileAction;

  /// No description provided for @remoteBatchExportSavedNotice.
  ///
  /// In en, this message translates to:
  /// **'Encrypted {count} connection(s) to {path}'**
  String remoteBatchExportSavedNotice(int count, String path);

  /// No description provided for @remoteBatchExportSharedNotice.
  ///
  /// In en, this message translates to:
  /// **'Prepared encrypted backup for {count} connection(s).'**
  String remoteBatchExportSharedNotice(int count);

  /// No description provided for @remoteBatchExportCopiedNotice.
  ///
  /// In en, this message translates to:
  /// **'Copied encrypted backup of {count} connection(s) to clipboard.'**
  String remoteBatchExportCopiedNotice(int count);

  /// No description provided for @remoteBatchImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Import Connections'**
  String get remoteBatchImportTitle;

  /// No description provided for @remoteBatchChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose Backup File'**
  String get remoteBatchChooseFile;

  /// No description provided for @remoteBatchPasteClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from Clipboard'**
  String get remoteBatchPasteClipboard;

  /// No description provided for @remoteBatchClipboardDetected.
  ///
  /// In en, this message translates to:
  /// **'Encrypted backup detected in clipboard.'**
  String get remoteBatchClipboardDetected;

  /// No description provided for @remoteBatchClipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty.'**
  String get remoteBatchClipboardEmpty;

  /// No description provided for @remoteBatchSelectedFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected file: {name}'**
  String remoteBatchSelectedFileLabel(String name);

  /// No description provided for @remoteBatchPasteFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Or paste encrypted .fmremotes / .fmbak content…'**
  String get remoteBatchPasteFieldHint;

  /// No description provided for @remoteBatchImportPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Decryption Password (Required)'**
  String get remoteBatchImportPasswordLabel;

  /// No description provided for @remoteBatchImportPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the password set during export'**
  String get remoteBatchImportPasswordHint;

  /// No description provided for @remoteBatchDecryptAction.
  ///
  /// In en, this message translates to:
  /// **'Decrypt & Preview'**
  String get remoteBatchDecryptAction;

  /// No description provided for @remoteBatchPreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'Decrypted {count} connection(s)'**
  String remoteBatchPreviewSummary(int count);

  /// No description provided for @remoteBatchConflictSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'When connection already exists:'**
  String get remoteBatchConflictSectionLabel;

  /// No description provided for @remoteBatchConflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get remoteBatchConflictSkip;

  /// No description provided for @remoteBatchConflictOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get remoteBatchConflictOverwrite;

  /// No description provided for @remoteBatchConflictKeepBoth.
  ///
  /// In en, this message translates to:
  /// **'Keep Both'**
  String get remoteBatchConflictKeepBoth;

  /// No description provided for @remoteBatchBadgeNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get remoteBatchBadgeNew;

  /// No description provided for @remoteBatchBadgeExists.
  ///
  /// In en, this message translates to:
  /// **'Exists'**
  String get remoteBatchBadgeExists;

  /// No description provided for @remoteBatchAllSkippedHint.
  ///
  /// In en, this message translates to:
  /// **'All selected connections already exist and will be skipped. Switch to Overwrite or Keep Both to import them.'**
  String get remoteBatchAllSkippedHint;

  /// No description provided for @remoteBatchImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import ({count})'**
  String remoteBatchImportConfirm(int count);

  /// No description provided for @remoteBatchImportSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} connection(s) ({added} new, {overwritten} updated, {duplicated} copied, {skipped} skipped){detail}'**
  String remoteBatchImportSummary(
    int imported,
    int added,
    int overwritten,
    int duplicated,
    int skipped,
    String detail,
  );

  /// No description provided for @remoteBatchErrorNotEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted plaintext data is not allowed. Please select a password-encrypted backup.'**
  String get remoteBatchErrorNotEncrypted;

  /// No description provided for @remoteBatchErrorInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid backup file format.'**
  String get remoteBatchErrorInvalidFormat;

  /// No description provided for @remoteBatchErrorWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or corrupted backup file.'**
  String get remoteBatchErrorWrongPassword;

  /// No description provided for @remoteBatchErrorEmptyBundle.
  ///
  /// In en, this message translates to:
  /// **'This backup contains no valid remote connections.'**
  String get remoteBatchErrorEmptyBundle;

  /// No description provided for @remoteBatchErrorFileTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Selected file is too large to be a connection backup.'**
  String get remoteBatchErrorFileTooLarge;

  /// No description provided for @remoteBatchBackStep.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get remoteBatchBackStep;

  /// No description provided for @poolNodeWeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get poolNodeWeightLabel;

  /// No description provided for @poolNodeWeightBadge.
  ///
  /// In en, this message translates to:
  /// **'Weight {weight}'**
  String poolNodeWeightBadge(int weight);

  /// No description provided for @poolSetNodeWeightTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Node Weight'**
  String get poolSetNodeWeightTitle;

  /// No description provided for @poolSetNodeWeightHint.
  ///
  /// In en, this message translates to:
  /// **'Higher weight (1–1000) receives more write traffic when free space and health are similar.'**
  String get poolSetNodeWeightHint;

  /// No description provided for @poolInvalidWeightError.
  ///
  /// In en, this message translates to:
  /// **'Weight must be an integer between 1 and 1000.'**
  String get poolInvalidWeightError;

  /// No description provided for @poolNodeUsedAndQuota.
  ///
  /// In en, this message translates to:
  /// **'Used {used} / Quota {quota}'**
  String poolNodeUsedAndQuota(String used, String quota);

  /// No description provided for @poolNodeSystemFreeWithTotal.
  ///
  /// In en, this message translates to:
  /// **'System free {free} / {total}'**
  String poolNodeSystemFreeWithTotal(String free, String total);

  /// No description provided for @poolNodeSystemFreeOnly.
  ///
  /// In en, this message translates to:
  /// **'System free {free}'**
  String poolNodeSystemFreeOnly(String free);

  /// No description provided for @poolNodeSystemSpaceUnsupported.
  ///
  /// In en, this message translates to:
  /// **'System free space: not supported by protocol'**
  String get poolNodeSystemSpaceUnsupported;

  /// No description provided for @poolNodeSystemSpaceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'System free space: unavailable'**
  String get poolNodeSystemSpaceUnavailable;

  /// No description provided for @poolNodeSystemSpaceProbing.
  ///
  /// In en, this message translates to:
  /// **'System free space: checking…'**
  String get poolNodeSystemSpaceProbing;

  /// No description provided for @poolDeleteRemoteDataOption.
  ///
  /// In en, this message translates to:
  /// **'Also delete remote pool data on member nodes'**
  String get poolDeleteRemoteDataOption;

  /// No description provided for @poolDeleteRemoteDataWarning.
  ///
  /// In en, this message translates to:
  /// **'Permanently deletes blobs/ and meta/ folders under each node\'s storage directory. This cannot be undone.'**
  String get poolDeleteRemoteDataWarning;

  /// No description provided for @poolDeleteNodeRemoteDataOption.
  ///
  /// In en, this message translates to:
  /// **'Also delete remote data on this node'**
  String get poolDeleteNodeRemoteDataOption;

  /// No description provided for @poolDeleteNodeRemoteDataWarning.
  ///
  /// In en, this message translates to:
  /// **'Permanently removes pool chunks and metadata backups stored on this node.'**
  String get poolDeleteNodeRemoteDataWarning;

  /// No description provided for @poolOfflineNode.
  ///
  /// In en, this message translates to:
  /// **'Take Offline'**
  String get poolOfflineNode;

  /// No description provided for @poolOnlineNode.
  ///
  /// In en, this message translates to:
  /// **'Bring Online'**
  String get poolOnlineNode;

  /// No description provided for @poolRemoveNode.
  ///
  /// In en, this message translates to:
  /// **'Remove Node'**
  String get poolRemoveNode;

  /// No description provided for @poolOfflineConfirm.
  ///
  /// In en, this message translates to:
  /// **'Take node \"{node}\" offline immediately? Active chunks on this node will no longer be served until brought back online or healed.'**
  String poolOfflineConfirm(String node);

  /// No description provided for @poolRemoveNodeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove node \"{node}\" from this storage pool?'**
  String poolRemoveNodeConfirm(String node);

  /// No description provided for @poolRemoteCleanupDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted {deleted} remote item(s).'**
  String poolRemoteCleanupDone(int deleted);

  /// No description provided for @poolRemoteCleanupPartial.
  ///
  /// In en, this message translates to:
  /// **'Deleted {deleted} remote item(s); {failed} failed ({nodes}).'**
  String poolRemoteCleanupPartial(int deleted, int failed, String nodes);

  /// No description provided for @analyzerSelectedCountAndSize.
  ///
  /// In en, this message translates to:
  /// **'{count} selected ({size})'**
  String analyzerSelectedCountAndSize(int count, String size);

  /// No description provided for @analyzerBatchDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} file(s)?'**
  String analyzerBatchDeleteConfirmTitle(int count);

  /// No description provided for @analyzerBatchDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} file(s), freed {size}.'**
  String analyzerBatchDeleteDone(int count, String size);

  /// No description provided for @analyzerBatchDeletePartial.
  ///
  /// In en, this message translates to:
  /// **'Deleted {deleted} file(s); {failed} failed.'**
  String analyzerBatchDeletePartial(int deleted, int failed);

  /// No description provided for @analyzerMultiSelectTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select files'**
  String get analyzerMultiSelectTooltip;
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
