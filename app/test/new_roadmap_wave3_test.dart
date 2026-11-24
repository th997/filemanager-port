import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/remote_wizard_dialog.dart';
import 'package:filemanager/src/pages/image_viewer_page.dart';
import 'package:filemanager/src/services/desktop_dev_actions.dart';
import 'package:filemanager/src/services/error_text.dart';
import 'package:filemanager/src/services/image_privacy_service.dart';
import 'package:filemanager/src/services/photo_backup_service.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/shortcut_service.dart';
import 'package:filemanager/src/widgets/desktop_sidebar_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 transparent PNG so Image.file decodes cleanly in widget tests.
final List<int> _minimalPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Uint8List _buildSyntheticJpegWithExifAndComment() {
  final out = BytesBuilder(copy: false);
  // SOI
  out.add(const [0xFF, 0xD8]);
  // APP0 JFIF (length 16 = 2 + 14) -> MUST be preserved
  out.add(const [0xFF, 0xE0, 0x00, 0x10]);
  out.add(List<int>.filled(14, 0x01));
  // APP1 EXIF (length 10 = 2 + 8) -> MUST be stripped
  out.add(const [0xFF, 0xE1, 0x00, 0x0A]);
  out.add('Exif\x00\x00MM'.codeUnits);
  // COM (length 6 = 2 + 4) -> MUST be stripped
  out.add(const [0xFF, 0xFE, 0x00, 0x06, 0x41, 0x42, 0x43, 0x44]);
  // SOF0 (length 5 = 2 + 3) -> MUST be preserved
  out.add(const [0xFF, 0xC0, 0x00, 0x05, 0x08, 0x00, 0x01]);
  // SOS + scan data + EOI -> MUST be preserved verbatim
  out.add(const [0xFF, 0xDA, 0x00, 0x03, 0x01, 0xAA, 0xBB, 0xFF, 0xD9]);
  return out.takeBytes();
}

Widget _wrapWithL10n(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 3 Roadmap Features', () {
    test('ImagePrivacyService strips APP1 EXIF and COM losslessly while keeping JFIF/SOF/SOS',
        () async {
      final rawJpeg = _buildSyntheticJpegWithExifAndComment();
      final cleaned = ImagePrivacyService.stripJpegMetadataLossless(rawJpeg);

      expect(cleaned.sublist(0, 2), equals(const [0xFF, 0xD8]));
      // APP0 JFIF preserved (0xFF 0xE0), APP1 (0xFF 0xE1) & COM (0xFF 0xFE) removed.
      final str = latin1.decode(cleaned, allowInvalid: true);
      expect(str.contains('Exif'), isFalse);
      expect(str.contains('ABCD'), isFalse);
      expect(cleaned.length, lessThan(rawJpeg.length));
      // Ends with scan data + EOI
      expect(
        cleaned.sublist(cleaned.length - 4),
        equals(const [0xAA, 0xBB, 0xFF, 0xD9]),
      );

      // Non-JPEG data must be returned untouched
      final png = Uint8List.fromList(_minimalPngBytes);
      expect(ImagePrivacyService.stripJpegMetadataLossless(png), equals(png));

      // File copy helper writes `<name>_clean.jpg`
      final tmp = await Directory.systemTemp.createTemp('fm_exif_test_');
      try {
        final src = File('${tmp.path}/photo.jpg');
        await src.writeAsBytes(rawJpeg);
        final outPath = await ImagePrivacyService.stripExifAndSaveCopy(src.path);
        expect(outPath, endsWith('photo_clean.jpg'));
        final saved = await File(outPath).readAsBytes();
        expect(saved, equals(cleaned));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    testWidgets('ImageViewerPage cycles Single -> Webtoon -> Double Page -> Single',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('fm_comic_test_');
      try {
        final p1 = File('${tmp.path}/01.png')..writeAsBytesSync(_minimalPngBytes);
        final p2 = File('${tmp.path}/02.png')..writeAsBytesSync(_minimalPngBytes);
        final p3 = File('${tmp.path}/03.png')..writeAsBytesSync(_minimalPngBytes);

        await tester.pumpWidget(
          _wrapWithL10n(
            ImageViewerPage(
              filePath: p1.path,
              fileName: '01.png',
              siblings: [
                ImageViewerEntry(name: '01.png', localPath: p1.path),
                ImageViewerEntry(name: '02.png', localPath: p2.path),
                ImageViewerEntry(name: '03.png', localPath: p3.path),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(find.byKey(const ValueKey('image_webtoon_list')), findsNothing);
        expect(find.byKey(const ValueKey('image_double_page_view')), findsNothing);

        final modeBtn = find.byKey(const ValueKey('image_reading_mode_btn'));
        expect(modeBtn, findsOneWidget);

        // Single -> Webtoon (ListView)
        await tester.tap(modeBtn);
        await tester.pump();
        expect(find.byKey(const ValueKey('image_webtoon_list')), findsOneWidget);

        // Webtoon -> Double Page
        await tester.tap(modeBtn);
        await tester.pump();
        expect(find.byKey(const ValueKey('image_double_page_view')), findsOneWidget);

        // Double Page -> Single
        await tester.tap(modeBtn);
        await tester.pump();
        expect(find.byKey(const ValueKey('image_webtoon_list')), findsNothing);
        expect(find.byKey(const ValueKey('image_double_page_view')), findsNothing);
      } finally {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
      }
    });

    test('DesktopDevActions resolves terminal and editor commands across OS targets',
        () {
      final macTerm = DesktopDevActions.resolveTerminalCommand(
        '/Users/dev/app',
        operatingSystem: 'macos',
      );
      expect(macTerm?.executable, 'open');
      expect(macTerm?.arguments, containsAll(['-a', 'Terminal', '/Users/dev/app']));

      final winTerm = DesktopDevActions.resolveTerminalCommand(
        r'D:\proj',
        operatingSystem: 'windows',
        commandExists: (bin) => bin == 'wt',
      );
      expect(winTerm?.executable, 'wt');
      expect(winTerm?.arguments, equals(['-d', r'D:\proj']));

      final linuxTerm = DesktopDevActions.resolveTerminalCommand(
        '/home/dev/proj',
        operatingSystem: 'linux',
        commandExists: (bin) => bin == 'konsole',
      );
      expect(linuxTerm?.executable, 'konsole');
      expect(linuxTerm?.arguments, equals(['--workdir', '/home/dev/proj']));

      final ed = DesktopDevActions.resolveEditorCommand(
        '/home/dev/proj',
        operatingSystem: 'linux',
        commandExists: (bin) => bin == 'code',
      );
      expect(ed?.executable, 'code');
      expect(ed?.arguments, equals(['/home/dev/proj']));
    });

    test('PhotoBackupService increments only new asset IDs and honors Wi-Fi gate',
        () async {
      final uploadedIds = <String>[];
      var onlineWifi = false;
      var available = [
        PhotoBackupAsset(
          id: 'img_1',
          filePath: '/tmp/a.jpg',
          fileName: 'a.jpg',
          modified: DateTime(2026, 1, 1),
        ),
        PhotoBackupAsset(
          id: 'img_2',
          filePath: '/tmp/b.jpg',
          fileName: 'b.jpg',
          modified: DateTime(2026, 1, 2),
        ),
      ];

      final svc = PhotoBackupService(
        assetFetcher: () async => available,
        wifiChecker: () async => onlineWifi,
        uploader: ({required asset, required dstRoot, required dstDir}) async {
          uploadedIds.add('$dstRoot:$dstDir:${asset.id}');
        },
      );
      svc.clearLedger();
      svc.isEnabled = true;
      svc.wifiOnly = true;
      svc.setTarget(root: 'remote://nas', dir: 'Camera');

      // Wi-Fi offline & not forced -> skipped
      expect(await svc.runBackup(force: false), 0);
      expect(uploadedIds, isEmpty);

      // Wi-Fi online -> uploads img_1 & img_2
      onlineWifi = true;
      expect(await svc.runBackup(force: false), 2);
      expect(uploadedIds, equals(['remote://nas:Camera:img_1', 'remote://nas:Camera:img_2']));

      // Second run with same assets -> uploads 0
      expect(await svc.runBackup(force: false), 0);

      // Third run with 1 new asset -> uploads only img_3
      available = [
        ...available,
        PhotoBackupAsset(
          id: 'img_3',
          filePath: '/tmp/c.jpg',
          fileName: 'c.jpg',
          modified: DateTime(2026, 1, 3),
        ),
      ];
      expect(await svc.runBackup(force: false), 1);
      expect(uploadedIds.last, 'remote://nas:Camera:img_3');
      svc.clearLedger();
    });

    test('ShortcutService pins shortcuts, reads initial launch target, and emits live events',
        () async {
      const channel = MethodChannel('com.github.th997.filemanager/shortcuts_test');
      final recordedCalls = <MethodCall>[];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        recordedCalls.add(call);
        switch (call.method) {
          case 'isSupported':
            return true;
          case 'pinShortcut':
            return true;
          case 'getInitialShortcut':
            return {
              'id': 'nas_home',
              'label': 'Home NAS',
              'targetType': 'remote',
              'root': 'remote://nas1',
              'path': 'Photos',
            };
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final svc = ShortcutService(
        channel: channel,
        platformSupportedOverride: () => true,
      );

      expect(await svc.isSupported(), isTrue);
      final pinned = await svc.pinShortcut(
        const ShortcutTarget(
          type: 'folder',
          id: 'dl',
          label: 'Downloads',
          root: '/tmp/dl',
        ),
      );
      expect(pinned, isTrue);
      expect(recordedCalls.last.method, 'pinShortcut');
      expect((recordedCalls.last.arguments as Map)['label'], 'Downloads');

      final initial = await svc.consumeInitialShortcut();
      expect(initial?.type, 'remote');
      expect(initial?.root, 'remote://nas1');
      expect(initial?.path, 'Photos');

      final completer = Completer<ShortcutTarget>();
      final sub = svc.onShortcutOpened.listen(completer.complete);
      addTearDown(sub.cancel);

      final codec = const StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(const MethodCall('onShortcutOpened', {
          'id': 'sync_1',
          'label': 'Nightly Sync',
          'targetType': 'sync',
          'root': '',
          'path': '',
        })),
        (_) {},
      );
      final live = await completer.future;
      expect(live.type, 'sync');
      expect(live.label, 'Nightly Sync');
    });

    testWidgets('RemoteWizardDialog supports Crypt Zero-Knowledge Vault configuration',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithL10n(
          const Scaffold(body: RemoteWizardDialog()),
        ),
      );
      await tester.pump();

      // Open protocol dropdown and select 'crypt'
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encrypted Cloud Vault (Crypt)').last);
      await tester.pumpAndSettle();

      // Verify Crypt fields appear
      expect(find.text('Backing Storage Root'), findsOneWidget);
      expect(find.text('Encrypted Subfolder Prefix'), findsOneWidget);
      expect(find.text('Master Encryption Password'), findsOneWidget);
      expect(find.text('Optional Salt / Passphrase'), findsOneWidget);

      // Submitting without required password/endpoint triggers validation errors
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Encryption password is required'), findsOneWidget);
    });

    test('ImagePrivacyService rejects non-JPEG on save and strips post-EOI trailing metadata',
        () async {
      final tmpDir = Directory.systemTemp.createTempSync('exif_privacy_test_');
      try {
        final pngFile = File('${tmpDir.path}/sample.png')
          ..writeAsBytesSync(_minimalPngBytes);
        await expectLater(
          ImagePrivacyService.stripExifAndSaveCopy(pngFile.path),
          throwsA(isA<UnsupportedError>()),
        );

        final rawJpeg = _buildSyntheticJpegWithExifAndComment();
        final withTrailer = Uint8List.fromList([
          ...rawJpeg,
          ...'TRAILER_SECRET_GPS'.codeUnits,
        ]);
        final cleaned = ImagePrivacyService.stripJpegMetadataLossless(withTrailer);
        final decoded = latin1.decode(cleaned, allowInvalid: true);
        expect(decoded.contains('TRAILER_SECRET_GPS'), isFalse);
        expect(cleaned.sublist(cleaned.length - 2), equals(const [0xFF, 0xD9]));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('PhotoBackupService preserves lastError and skips ledger/timestamp on failure',
        () async {
      PreferencesService.instance.remove(PhotoBackupService.prefLastBackupMs);
      final svc = PhotoBackupService(
        assetFetcher: () async => [
          PhotoBackupAsset(
            id: 'fail_asset_1',
            filePath: '/tmp/fail.jpg',
            fileName: 'fail.jpg',
            modified: DateTime(2026, 2, 1),
          ),
        ],
        wifiChecker: () async => true,
        uploader: ({required asset, required dstRoot, required dstDir}) async {
          throw StateError('simulated upload error');
        },
        clock: () => DateTime(2026, 2, 2),
      );
      svc.clearLedger();
      svc.setTarget(root: 'remote://nas', dir: 'Camera');

      final uploaded = await svc.runBackup(force: true);
      expect(uploaded, 0);
      expect(svc.loadBackedUpIds(), isEmpty);
      expect(svc.lastBackupMillis, 0);
      expect(svc.progressNotifier.value.running, isFalse);
      expect(svc.progressNotifier.value.lastError, contains('simulated upload error'));
    });

    test('detectErrorRecovery handles SSH host key, SFTP auth, and cancelled auth accurately',
        () {
      expect(
        detectErrorRecovery('SSH host key verification failed'),
        ErrorRecoveryKind.hostKeyTrust,
      );
      expect(
        detectErrorRecovery('SFTP error: Permission denied (publickey)'),
        ErrorRecoveryKind.remoteCredentials,
      );
      expect(
        detectErrorRecovery('Authentication cancelled'),
        ErrorRecoveryKind.none,
      );
    });

    test('PreferencesService export/import excludes device-local backup, vault pins, and upload recents',
        () {
      final prefs = PreferencesService.instance;
      prefs.setString('app.language', 'en');
      prefs.setString('photo_backup.backed_up_ids_v1', '["a1"]');
      prefs.setString('vault.pinned_entries', '[{"id":"v1","name":"Secret"}]');
      prefs.setString('upload.recent_directories', '["/tmp/local"]');

      final exported = prefs.exportPreferencesMap();
      expect(exported['app.language'], 'en');
      expect(exported.containsKey('photo_backup.backed_up_ids_v1'), isFalse);
      expect(exported.containsKey('vault.pinned_entries'), isFalse);
      expect(exported.containsKey('upload.recent_directories'), isFalse);

      prefs.remove('app.language');
      prefs.remove('photo_backup.backed_up_ids_v1');
      prefs.remove('vault.pinned_entries');
      prefs.remove('upload.recent_directories');

      final imported = prefs.importPreferencesMap({
        'app.language': 'zh',
        'photo_backup.backed_up_ids_v1': '["rogue"]',
        'vault.pinned_entries': '[{"id":"v9","name":"Rogue"}]',
        'upload.recent_directories': '["/rogue"]',
      });
      expect(imported, 1);
      expect(prefs.getString('app.language'), 'zh');
      expect(prefs.getString('photo_backup.backed_up_ids_v1'), isNull);
      expect(prefs.getString('vault.pinned_entries'), isNull);
      expect(prefs.getString('upload.recent_directories'), isNull);
    });

    testWidgets('DesktopSidebarShell exposes create vault action even when zero vaults are unlocked or pinned',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: DesktopSidebarShell(
            remotes: const [],
            bookmarks: const [],
            history: const [],
            trashCount: 0,
            activeTaskCount: 0,
            diskSpace: null,
            themeMode: ThemeMode.system,
            onRefreshMetadata: () {},
            onOpenGlobalSearch: ({root, relPath, onNavigate}) async {},
            workspaceOverride: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar_create_vault_btn')), findsOneWidget);
      expect(find.text('Open Privacy Folder'), findsOneWidget);
      expect(find.text('Create Privacy Folder'), findsOneWidget);
    });
  });
}
