import 'dart:io';

import 'package:flutter/material.dart';

/// Host OS taxonomy used for central platform-capability gating.
enum HostPlatform { ios, android, macos, windows, linux }

/// Centralized platform capability matrix so unsupported or platform-irrelevant
/// features are automatically hidden on each OS / form factor.
class PlatformCapabilities {
  PlatformCapabilities._();

  /// Optional test hook to simulate any host OS inside unit/widget tests.
  @visibleForTesting
  static HostPlatform? debugPlatformOverride;

  static HostPlatform get current {
    final override = debugPlatformOverride;
    if (override != null) return override;
    if (Platform.isIOS) return HostPlatform.ios;
    if (Platform.isAndroid) return HostPlatform.android;
    if (Platform.isMacOS) return HostPlatform.macos;
    if (Platform.isWindows) return HostPlatform.windows;
    return HostPlatform.linux;
  }

  static bool get isIOS => current == HostPlatform.ios;
  static bool get isAndroid => current == HostPlatform.android;
  static bool get isMacOS => current == HostPlatform.macos;
  static bool get isWindows => current == HostPlatform.windows;
  static bool get isLinux => current == HostPlatform.linux;

  static bool get isMobile => isIOS || isAndroid;
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Smart "Installers / Packages" quick category & search filter.
  /// Hidden on iOS because iOS apps are sandboxed and cannot sideload
  /// `.apk` / `.dmg` / `.deb` / `.exe` installers.
  static bool get supportsInstallersCategory => !isIOS;

  /// Home screen smart file-category shortcut cards (Documents, Videos, Audio,
  /// Archives, Installers). Hidden on iOS because iOS apps cannot scan full
  /// device storage (only their own sandbox), making full-disk category cards
  /// low value while Gallery remains available via PhotoKit.
  static bool get supportsHomeSmartCategories => !isIOS;

  /// Platform-appropriate icon for the Installers category card.
  static IconData get installerCategoryIcon =>
      isAndroid ? Icons.android_outlined : Icons.install_desktop_outlined;

  /// Platform-appropriate extension hint for the Installers category card.
  static String get installerCategorySubtitle {
    switch (current) {
      case HostPlatform.android:
        return 'APK · APKS';
      case HostPlatform.macos:
        return 'DMG · PKG';
      case HostPlatform.windows:
        return 'EXE · MSI';
      case HostPlatform.linux:
        return 'DEB · RPM';
      case HostPlatform.ios:
        return '';
    }
  }

  /// System Material You / Dynamic Color theming.
  /// Unsupported on iOS (`DynamicColorBuilder` always yields null palettes).
  static bool get supportsDynamicColor => !isIOS;

  /// One-handed bottom browser address/toolbar ergonomic toggle.
  /// Only relevant on mobile touchscreens (iOS / Android).
  static bool get supportsBottomToolbar => isMobile;

  /// "Delete original file after importing to privacy vault" option in the
  /// Share Receiver sheet. Hidden on iOS because Share Extensions always hand
  /// over temporary sandbox Inbox copies (which are already auto-cleaned) and
  /// iOS forbids deleting the user's original item in Photos / other apps.
  static bool get supportsDeleteSharedOriginal => !isIOS;

  /// Native OS file share sheet (`share_plus`).
  /// Linux desktop has no native `shareXFiles` implementation in `share_plus`;
  /// users use "Open With" or "Share via LAN" instead.
  static bool get supportsNativeShareSheet => !isLinux;

  /// Local filesystem Unix permission (`chmod`) viewing & editing.
  /// Meaningful on Linux and macOS local roots; SFTP remotes stay supported
  /// on every platform regardless of local OS.
  static bool get supportsLocalUnixPermissions => isLinux || isMacOS;

  /// Video thumbnail extraction for privacy vaults (disabled on iOS).
  static bool get supportsVaultVideoThumbnails => !isIOS;

  /// Android MANAGE_EXTERNAL_STORAGE permission banner.
  static bool get supportsStoragePermissionBanner => isAndroid;

  /// iOS AVPictureInPictureController native PiP support.
  static bool get supportsNativePip => isIOS;

  /// Multi-tab desktop/tablet browser workspace (`Open in New Tab`).
  /// Hidden on compact phones where tab bars waste space.
  static bool supportsMultiTab(BuildContext context) =>
      isDesktop || MediaQuery.sizeOf(context).width >= 680;

  /// Side-by-side dual-pane workspace toggle (`Row` split).
  /// Hidden on narrow phones where side-by-side columns are unreadable.
  static bool supportsSideBySideSplit(BuildContext context) =>
      isDesktop || MediaQuery.sizeOf(context).width >= 680;
}
