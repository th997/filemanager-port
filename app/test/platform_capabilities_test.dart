import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/share_receiver_dialog.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/settings_page.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/rust/api/vault.dart';
import 'package:filemanager/src/services/platform_capabilities.dart';
import 'package:filemanager/src/widgets/browser/browser_action_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PlatformCapabilities.debugPlatformOverride = null;
  });

  group('PlatformCapabilities matrix', () {
    test('iOS hides installers, dynamic color, delete-original, local chmod, video thumbs, storage banner', () {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.ios;

      expect(PlatformCapabilities.isIOS, isTrue);
      expect(PlatformCapabilities.isMobile, isTrue);
      expect(PlatformCapabilities.isDesktop, isFalse);

      expect(PlatformCapabilities.supportsHomeSmartCategories, isFalse);
      expect(PlatformCapabilities.supportsInstallersCategory, isFalse);
      expect(PlatformCapabilities.supportsDynamicColor, isFalse);
      expect(PlatformCapabilities.supportsBottomToolbar, isTrue);
      expect(PlatformCapabilities.supportsDeleteSharedOriginal, isFalse);
      expect(PlatformCapabilities.supportsNativeShareSheet, isTrue);
      expect(PlatformCapabilities.supportsLocalUnixPermissions, isFalse);
      expect(PlatformCapabilities.supportsVaultVideoThumbnails, isFalse);
      expect(PlatformCapabilities.supportsStoragePermissionBanner, isFalse);
      expect(PlatformCapabilities.supportsNativePip, isTrue);
    });

    test('Android enables APK installers, dynamic color, bottom toolbar, delete-original, storage banner', () {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.android;

      expect(PlatformCapabilities.isAndroid, isTrue);
      expect(PlatformCapabilities.isMobile, isTrue);
      expect(PlatformCapabilities.isDesktop, isFalse);

      expect(PlatformCapabilities.supportsHomeSmartCategories, isTrue);
      expect(PlatformCapabilities.supportsInstallersCategory, isTrue);
      expect(PlatformCapabilities.installerCategoryIcon, Icons.android_outlined);
      expect(PlatformCapabilities.installerCategorySubtitle, 'APK · APKS');
      expect(PlatformCapabilities.supportsDynamicColor, isTrue);
      expect(PlatformCapabilities.supportsBottomToolbar, isTrue);
      expect(PlatformCapabilities.supportsDeleteSharedOriginal, isTrue);
      expect(PlatformCapabilities.supportsNativeShareSheet, isTrue);
      expect(PlatformCapabilities.supportsLocalUnixPermissions, isFalse);
      expect(PlatformCapabilities.supportsVaultVideoThumbnails, isTrue);
      expect(PlatformCapabilities.supportsStoragePermissionBanner, isTrue);
      expect(PlatformCapabilities.supportsNativePip, isFalse);
    });

    test('Linux enables DEB/RPM installers, local chmod, dynamic color; hides bottom toolbar & share sheet', () {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.linux;

      expect(PlatformCapabilities.isLinux, isTrue);
      expect(PlatformCapabilities.isDesktop, isTrue);
      expect(PlatformCapabilities.isMobile, isFalse);

      expect(PlatformCapabilities.supportsHomeSmartCategories, isTrue);
      expect(PlatformCapabilities.supportsInstallersCategory, isTrue);
      expect(PlatformCapabilities.installerCategoryIcon, Icons.install_desktop_outlined);
      expect(PlatformCapabilities.installerCategorySubtitle, 'DEB · RPM');
      expect(PlatformCapabilities.supportsDynamicColor, isTrue);
      expect(PlatformCapabilities.supportsBottomToolbar, isFalse);
      expect(PlatformCapabilities.supportsDeleteSharedOriginal, isTrue);
      expect(PlatformCapabilities.supportsNativeShareSheet, isFalse);
      expect(PlatformCapabilities.supportsLocalUnixPermissions, isTrue);
      expect(PlatformCapabilities.supportsVaultVideoThumbnails, isTrue);
      expect(PlatformCapabilities.supportsStoragePermissionBanner, isFalse);
      expect(PlatformCapabilities.supportsNativePip, isFalse);
    });

    test('macOS enables DMG/PKG installers, local chmod, native share; hides bottom toolbar', () {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;

      expect(PlatformCapabilities.isMacOS, isTrue);
      expect(PlatformCapabilities.isDesktop, isTrue);

      expect(PlatformCapabilities.supportsHomeSmartCategories, isTrue);
      expect(PlatformCapabilities.supportsInstallersCategory, isTrue);
      expect(PlatformCapabilities.installerCategoryIcon, Icons.install_desktop_outlined);
      expect(PlatformCapabilities.installerCategorySubtitle, 'DMG · PKG');
      expect(PlatformCapabilities.supportsBottomToolbar, isFalse);
      expect(PlatformCapabilities.supportsNativeShareSheet, isTrue);
      expect(PlatformCapabilities.supportsLocalUnixPermissions, isTrue);
    });

    test('Windows enables EXE/MSI installers & native share; hides local chmod & bottom toolbar', () {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.windows;

      expect(PlatformCapabilities.isWindows, isTrue);
      expect(PlatformCapabilities.isDesktop, isTrue);

      expect(PlatformCapabilities.supportsHomeSmartCategories, isTrue);
      expect(PlatformCapabilities.supportsInstallersCategory, isTrue);
      expect(PlatformCapabilities.installerCategoryIcon, Icons.install_desktop_outlined);
      expect(PlatformCapabilities.installerCategorySubtitle, 'EXE · MSI');
      expect(PlatformCapabilities.supportsBottomToolbar, isFalse);
      expect(PlatformCapabilities.supportsNativeShareSheet, isTrue);
      expect(PlatformCapabilities.supportsLocalUnixPermissions, isFalse);
    });
  });

  group('Platform-gated UI widgets', () {
    Widget wrapZh(Widget child, {Size? size}) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: size == null
            ? child
            : MediaQuery(
                data: MediaQueryData(size: size),
                child: child,
              ),
      );
    }

    testWidgets('SettingsPage on simulated iOS hides Dynamic Color even when accentCode=dynamic, and shows bottom toolbar',
        (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.ios;

      await tester.pumpWidget(
        wrapZh(
          SettingsPage(
            currentThemeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            localeCode: 'zh',
            onLocaleChanged: (_) {},
            accentCode: 'dynamic',
            onAccentChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Normalized to deepTeal without throwing DropdownButton assertion
      expect(find.text('系统动态色'), findsNothing);
      expect(find.text('深海青'), findsWidgets);
      await tester.scrollUntilVisible(find.text('工具栏置底'), 200);
      expect(find.text('工具栏置底'), findsOneWidget);
    });

    testWidgets('SettingsPage on simulated Linux hides bottom toolbar and shows Dynamic Color',
        (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.linux;

      await tester.pumpWidget(
        wrapZh(
          SettingsPage(
            currentThemeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            localeCode: 'zh',
            onLocaleChanged: (_) {},
            accentCode: 'dynamic',
            onAccentChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('系统动态色'), findsWidgets);
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('工具栏置底'), findsNothing);
    });

    testWidgets('ShareReceiverContent hides delete-original checkbox on iOS and shows it on Android',
        (tester) async {
      const vault = UnlockedVaultDto(
        id: 'v-plat-1',
        name: 'Secret',
        dirPath: '/tmp/v-plat-1',
        cipher: 'aes128gcm',
        authMode: 'password',
        createdAtMs: 1700000000000,
      );

      PlatformCapabilities.debugPlatformOverride = HostPlatform.ios;
      await tester.pumpWidget(
        wrapZh(
          Scaffold(
            body: ShareReceiverContent(
              filePaths: const ['/tmp/doc.pdf'],
              unlockedVaultsOverride: const [vault],
              onAction: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('保存到隐私文件夹'), findsOneWidget);
      expect(find.text('导入隐私保险箱后删除原文件'), findsNothing);

      PlatformCapabilities.debugPlatformOverride = HostPlatform.android;
      await tester.pumpWidget(
        wrapZh(
          Scaffold(
            body: ShareReceiverContent(
              filePaths: const ['/tmp/doc.pdf'],
              unlockedVaultsOverride: const [vault],
              onAction: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('导入隐私保险箱后删除原文件'), findsOneWidget);
    });

    testWidgets('showBrowserEntryModalBottomSheet respects canOpenInNewTab and canShare flags',
        (tester) async {
      final folder = EntryItem(
        const EntryDto(
          name: 'Docs',
          path: 'Docs',
          isDir: true,
          hidden: false,
          isSymlink: false,
        ),
      );
      final file = EntryItem(
        const EntryDto(
          name: 'notes.txt',
          path: 'notes.txt',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );

      await tester.pumpWidget(
        wrapZh(
          Scaffold(
            body: Builder(
              builder: (ctx) => Column(
                children: [
                  TextButton(
                    onPressed: () => showBrowserEntryModalBottomSheet(
                      context: ctx,
                      item: folder,
                      isRemoteOrArchive: false,
                      canWrite: true,
                      canArchive: true,
                      canOpenInNewTab: false,
                    ),
                    child: const Text('open-folder-sheet'),
                  ),
                  TextButton(
                    onPressed: () => showBrowserEntryModalBottomSheet(
                      context: ctx,
                      item: file,
                      isRemoteOrArchive: false,
                      canWrite: true,
                      canArchive: true,
                      canShare: false,
                    ),
                    child: const Text('open-file-sheet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-folder-sheet'));
      await tester.pumpAndSettle();
      expect(find.text('在新标签页中打开'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open-file-sheet'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsNothing);
    });
  });
}
