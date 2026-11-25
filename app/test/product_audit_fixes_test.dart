import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/advanced_search_dialog.dart';
import 'package:filemanager/src/dialogs/batch_rename_dialog.dart';
import 'package:filemanager/src/pages/peer_transfer_page.dart';
import 'package:filemanager/src/pages/structured_viewer_page.dart';
import 'package:filemanager/src/rust/api/pool.dart';
import 'package:filemanager/src/services/photo_backup_service.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/semantic_colors.dart';
import 'package:filemanager/src/widgets/app_empty_state.dart';
import 'package:filemanager/src/widgets/browser/browser_bottom_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrapLocalized(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  group('Product audit fixes regression tests', () {
    test('SemanticColors exposes high-contrast dark onSuccess and onWarning', () {
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      expect(dark.onSuccess, const Color(0xFF0A2E0D));
      expect(dark.onWarning, const Color(0xFF2B1700));
    });

    testWidgets('AppEmptyState renders in 240x120 viewport without overflow',
        (tester) async {
      await tester.pumpWidget(
        _wrapLocalized(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 120,
                child: AppEmptyState(
                  icon: Icons.folder_open_outlined,
                  title: 'No files here',
                  subtitle:
                      'A longer explanatory subtitle that previously overflowed small panes.',
                  action: FilledButton(
                    onPressed: () {},
                    child: const Text('Add Item'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('No files here'), findsOneWidget);
    });

    test('BatchRenameDialog.planRenames detects case-insensitive collisions', () {
      final dup = BatchRenameDialog.planRenames(
        paths: const ['/dir/Alpha.txt', '/dir/Beta.txt'],
        newNames: const ['same.txt', 'SAME.txt'],
        caseInsensitive: true,
      );
      expect(dup.isValid, isFalse);
      expect(dup.errorKind, BatchRenameValidationErrorKind.duplicateTarget);
      expect(dup.invalidIndices, containsAll(<int>[0, 1]));

      final sibling = BatchRenameDialog.planRenames(
        paths: const ['/dir/One.txt'],
        newNames: const ['readme.txt'],
        existingSiblingNames: const {'README.txt'},
        caseInsensitive: true,
      );
      expect(sibling.isValid, isFalse);
      expect(sibling.errorKind, BatchRenameValidationErrorKind.targetExists);
      expect(sibling.invalidIndices, contains(0));
    });

    testWidgets(
        'BrowserBottomActionBar disables 0-selection actions and guards read-only paste',
        (tester) async {
      var copyCalls = 0;
      var cutCalls = 0;
      var deleteCalls = 0;
      var compressCalls = 0;

      await tester.pumpWidget(
        _wrapLocalized(
          Scaffold(
            bottomNavigationBar: BrowserBottomActionBar(
              isSelecting: true,
              isRemoteOrArchive: false,
              canWrite: true,
              canArchive: true,
              selectedCount: 0,
              selectedBytes: BigInt.zero,
              formatBytes: (b) => '$b B',
              onCopy: () => copyCalls++,
              onCut: () => cutCalls++,
              onDelete: () => deleteCalls++,
              onCompress: () => compressCalls++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Copy'));
      await tester.tap(find.text('Cut'));
      await tester.tap(find.text('Delete'));
      await tester.tap(find.text('Compress'));
      await tester.pump();

      expect(copyCalls, 0);
      expect(cutCalls, 0);
      expect(deleteCalls, 0);
      expect(compressCalls, 0);

      await tester.pumpWidget(
        _wrapLocalized(
          Scaffold(
            bottomNavigationBar: BrowserBottomActionBar(
              isSelecting: false,
              isRemoteOrArchive: true,
              canWrite: false,
              canArchive: false,
              selectedCount: 0,
              selectedBytes: BigInt.zero,
              formatBytes: (b) => '$b B',
              clipboardCount: 3,
              onPaste: () {},
              onClearClipboard: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Clipboard: 3 item(s) ready (read-only folder)'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.paste), findsNothing);
    });

    test(
        'PhotoBackupService reports scanning, supports cancelBackup, and clearLedger clears lastBackupMs',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final prefs = PreferencesService.instance;
      addTearDown(() {
        prefs.remove(PhotoBackupService.prefTargetRoot);
        prefs.remove(PhotoBackupService.prefTargetDir);
        prefs.remove(PhotoBackupService.prefWifiOnly);
        prefs.remove(PhotoBackupService.prefBackedUpIds);
        prefs.remove(PhotoBackupService.prefLastBackupMs);
      });

      prefs.setString(PhotoBackupService.prefTargetRoot, 'local');
      prefs.setString(PhotoBackupService.prefTargetDir, '/tmp/backup_dst');
      prefs.setBool(PhotoBackupService.prefWifiOnly, false);

      final scanGate = Completer<List<PhotoBackupAsset>>();
      final cancelService = PhotoBackupService(
        assetFetcher: () => scanGate.future,
        wifiChecker: () async => true,
        uploader: ({
          required asset,
          required dstRoot,
          required dstDir,
        }) async {},
      );

      final future = cancelService.runBackup(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(cancelService.progressNotifier.value.running, isTrue);
      expect(cancelService.progressNotifier.value.scanning, isTrue);

      cancelService.cancelBackup();
      scanGate.complete([
        PhotoBackupAsset(
          id: 'asset-1',
          filePath: '/tmp/a.jpg',
          fileName: 'a.jpg',
          modified: DateTime(2026, 1, 1),
        ),
      ]);

      final cancelledCount = await future;
      expect(cancelledCount, 0);
      expect(cancelService.progressNotifier.value.running, isFalse);
      expect(cancelService.progressNotifier.value.cancelled, isTrue);

      final uploadService = PhotoBackupService(
        assetFetcher: () async => [
          PhotoBackupAsset(
            id: 'asset-2',
            filePath: '/tmp/b.jpg',
            fileName: 'b.jpg',
            modified: DateTime(2026, 1, 2),
          ),
        ],
        wifiChecker: () async => true,
        uploader: ({
          required asset,
          required dstRoot,
          required dstDir,
        }) async {},
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final uploaded = await uploadService.runBackup(force: true);
      expect(uploaded, 1);
      expect(
        prefs.getString(PhotoBackupService.prefLastBackupMs),
        '1700000000000',
      );
      expect(uploadService.loadBackedUpIds(), contains('asset-2'));

      uploadService.clearLedger();
      expect(prefs.getString(PhotoBackupService.prefLastBackupMs), isNull);
      expect(uploadService.loadBackedUpIds(), isEmpty);
    });

    testWidgets(
        'PeerTransferPage switches between tabs at 360x800 without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrapLocalized(const PeerTransferPage()));
      await tester.pumpAndSettle();

      expect(find.text('Direct Transfer'), findsOneWidget);
      expect(find.text('WebDAV / Browser Share'), findsOneWidget);

      await tester.tap(find.text('WebDAV / Browser Share'));
      await tester.pumpAndSettle();

      expect(find.text('LAN WebDAV Server'), findsAtLeastNWidgets(1));
    });

    test('GlobalSearchMatcher matches pools and hides metadata with date filter',
        () {
      final pool = PoolSummaryDto(
        id: 'pool-alpha',
        name: 'Media Archive Pool',
        chunkSize: 4096,
        replicationFactor: 2,
        encrypted: false,
        totalPhysicalQuota: BigInt.from(1000),
        effectiveLogicalCapacity: BigInt.from(500),
        totalPhysicalUsed: BigInt.from(100),
        logicalUsedBytes: BigInt.from(50),
        fileCount: BigInt.from(10),
        dirCount: BigInt.from(2),
        degradedChunks: BigInt.zero,
        pendingGcCount: BigInt.zero,
        metaVersion: BigInt.one,
        dirty: false,
        nodes: const [],
      );
      final sources = GlobalSearchSources(pools: [pool]);

      final hit = GlobalSearchMatcher.match(
        sources: sources,
        query: 'Media Archive',
      );
      expect(hit.pools, hasLength(1));
      expect(hit.pools.first.id, 'pool-alpha');

      final filteredByDate = GlobalSearchMatcher.match(
        sources: sources,
        query: 'Media Archive',
        hasDateFilter: true,
      );
      expect(filteredByDate.isEmpty, isTrue);
    });

    testWidgets(
        'StructuredViewerPage supports bottom-up JSON/XML filtering and XML root collapse',
        (tester) async {
      await tester.pumpWidget(
        _wrapLocalized(
          const StructuredViewerPage(
            key: ValueKey('json_viewer'),
            root: 'local',
            path: '/tmp/data.json',
            fileName: 'data.json',
            initialJsonMode: JsonPreviewMode.tree,
            initialContent:
                '{"group":{"leaf":"needle","other":"skip"},"unrelated":{"a":1}}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'needle');
      await tester.pumpAndSettle();

      expect(find.textContaining('group'), findsOneWidget);
      expect(find.textContaining('leaf'), findsOneWidget);
      expect(find.textContaining('unrelated'), findsNothing);
      expect(find.textContaining('other'), findsNothing);

      await tester.pumpWidget(
        _wrapLocalized(
          const StructuredViewerPage(
            key: ValueKey('xml_viewer'),
            root: 'local',
            path: '/tmp/data.xml',
            fileName: 'data.xml',
            initialContent:
                '<root><child name="hit">match</child><other>skip</other></root>',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Root node starts expanded so child elements are visible initially.
      expect(find.textContaining('<root>'), findsOneWidget);
      expect(find.textContaining('<child>'), findsOneWidget);
      expect(find.textContaining('<other>'), findsOneWidget);

      // Tapping root collapses its subtree when no filter is active.
      await tester.tap(find.textContaining('<root>'));
      await tester.pumpAndSettle();
      expect(find.textContaining('<child>'), findsNothing);
      expect(find.textContaining('<other>'), findsNothing);

      // Searching retains the ancestor <root> and matching <child>.
      await tester.enterText(find.byType(TextField).first, 'match');
      await tester.pumpAndSettle();
      expect(find.textContaining('<root>'), findsOneWidget);
      expect(find.textContaining('<child>'), findsOneWidget);
      expect(find.textContaining('<other>'), findsNothing);
    });
  });
}
