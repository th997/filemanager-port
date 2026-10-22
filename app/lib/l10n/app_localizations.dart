import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. The generated localizations are used by the
/// `MaterialApp` in this project; see `main.dart`.
///
/// This file is generated from the ARB files in lib/l10n and checked in so
/// the project builds even before `flutter gen-l10n` runs; regenerating
/// overwrites it with identical output.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// About & System
  String get aboutSection;

  /// All photos
  String get allPhotos;

  /// File Manager
  String get appTitle;

  /// Appearance
  String get appearance;

  /// Bookmarks
  String get bookmarks;

  /// Browser
  String get browserSection;

  /// Cancel
  String get cancel;

  /// Cancel task
  String get cancelTask;

  /// Cancelled
  String get cancelled;

  /// Clear finished
  String get clearFinished;

  /// Close
  String get close;

  /// Cloud & Remote Storage
  String get cloudRemoteStorage;

  /// Cloud, Tools & Settings
  String get cloudToolsSettings;

  /// Completed
  String get completed;

  /// Connect a server
  String get connectServer;

  /// Dark theme
  String get darkTheme;

  /// Delete
  String get delete;

  /// Dismiss
  String get dismiss;

  /// Failed
  String get failed;

  /// Follow system settings
  String get followSystemSettings;

  /// Gallery
  String get gallery;

  /// In progress
  String get inProgress;

  /// LAN HTTP Web Sharing
  String get lanSharing;

  /// Language
  String get language;

  /// Follow system
  String get languageSystem;

  /// Light theme
  String get lightTheme;

  /// Local Storage
  String get localStorage;

  /// No tasks yet
  String get noTasksYet;

  /// Recent
  String get recent;

  /// Recycle Bin
  String get recycleBin;

  /// Remote
  String get remote;

  /// Retry
  String get retry;

  /// Save
  String get save;

  /// Settings
  String get settings;

  /// Theme, System info, About
  String get settingsCardSubtitle;

  /// Storage & Cache
  String get storageAndCache;

  /// Supported Protocols
  String get supportedProtocols;

  /// Tasks
  String get tasks;

  /// Theme
  String get theme;

  /// Dark
  String get themeDark;

  /// Light
  String get themeLight;

  /// System
  String get themeSystem;

  /// Toolbar at bottom
  String get toolbarAtBottom;

  /// Move the address bar and icons below the file list
  String get toolbarAtBottomDesc;

  /// Utilities
  String get utilities;

  /// Browse local folders right away, or connect a server — SFTP, WebDAV, S3, SMB and more — to manage files anywhere.
  String get welcomeBody;

  /// Welcome to File Manager
  String get welcomeTitle;

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
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale".');
}
