import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/advanced_search_dialog.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/rust/api/metadata.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/rust/api/vault.dart';
import 'package:filemanager/src/services/platform_paths.dart';
import 'package:filemanager/src/services/vault_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GlobalSearchSources buildSampleSources() {
    return GlobalSearchSources(
      bookmarks: const [
        BookmarkDto(
          id: 'bm1',
          name: '工作文档收藏',
          root: '/home/user',
          path: 'Documents/Work',
        ),
        BookmarkDto(
          id: 'bm2',
          name: 'NAS Media',
          root: 'remote://r1',
          path: 'Movies',
        ),
      ],
      history: const [
        // Duplicates bm1's root + path: should be deduplicated out when bm1 matches.
        HistoryDto(
          id: 'h1',
          root: '/home/user',
          path: 'Documents/Work',
          visitedMillis: 1000,
        ),
        HistoryDto(
          id: 'h2',
          root: '/home/user',
          path: 'Projects/AlphaFolder',
          visitedMillis: 2000,
        ),
      ],
      remotes: const [
        RemoteConfigDto(
          id: 'r1',
          name: 'Office SFTP',
          kind: 'sftp',
          host: '192.168.1.50',
          pathStyle: false,
        ),
      ],
      quickTargets: const [
        QuickTarget(
          name: 'Downloads',
          kind: 'downloads',
          path: '/home/user/Downloads',
          root: '/home/user',
          relPath: 'Downloads',
        ),
      ],
      unlockedVaults: const [
        UnlockedVaultDto(
          id: 'v1',
          name: 'PrivateTax',
          dirPath: '/home/user/.vault/v1',
          cipher: 'xchacha20poly1305',
          authMode: 'password',
          createdAtMs: 1000,
        ),
      ],
      lockedPinnedVaults: const [
        PinnedVaultEntry(id: 'v2', name: 'LockedSecret'),
      ],
    );
  }

  group('GlobalSearchMatcher', () {
    test('matches bookmarks in Chinese and English with contains, wildcard, and regex', () {
      final sources = buildSampleSources();

      final zhHits = GlobalSearchMatcher.match(
        sources: sources,
        query: '文档',
      );
      expect(zhHits.bookmarks.map((b) => b.id), ['bm1']);
      expect(zhHits.history, isEmpty);

      final wildHits = GlobalSearchMatcher.match(
        sources: sources,
        query: '*SFTP',
        matchMode: 'wildcard',
      );
      expect(wildHits.remotes.map((r) => r.id), ['r1']);

      final regexHits = GlobalSearchMatcher.match(
        sources: sources,
        query: r'^Locked.*$',
        matchMode: 'regex',
      );
      expect(regexHits.lockedPinnedVaults.map((v) => v.id), ['v2']);
    });

    test('matches remotes, quick targets, vaults, and deduplicates history', () {
      final sources = buildSampleSources();

      final ipHits = GlobalSearchMatcher.match(sources: sources, query: '192.168');
      expect(ipHits.remotes.map((r) => r.id), ['r1']);

      final targetHits = GlobalSearchMatcher.match(sources: sources, query: 'downloads');
      expect(targetHits.quickTargets.map((t) => t.kind), ['downloads']);

      final vaultHits = GlobalSearchMatcher.match(sources: sources, query: 'privatetax');
      expect(vaultHits.unlockedVaults.map((v) => v.id), ['v1']);

      // 'Documents/Work' matches both bm1 and h1 -> history deduplicates it,
      // whereas 'Projects/AlphaFolder' stays in history.
      final dedupHits = GlobalSearchMatcher.match(sources: sources, query: 'Work');
      expect(dedupHits.bookmarks.map((b) => b.id), ['bm1']);
      expect(dedupHits.history, isEmpty);

      final historyOnly = GlobalSearchMatcher.match(sources: sources, query: 'AlphaFolder');
      expect(historyOnly.history.map((h) => h.id), ['h2']);
    });

    test('filters out non-file metadata when file category or size filter is active', () {
      final sources = buildSampleSources();

      final imageCat = GlobalSearchMatcher.match(
        sources: sources,
        query: 'Work',
        category: 'image',
      );
      expect(imageCat.isEmpty, isTrue);

      final sizeFiltered = GlobalSearchMatcher.match(
        sources: sources,
        query: 'Work',
        category: 'all',
        hasSizeFilter: true,
      );
      expect(sizeFiltered.isEmpty, isTrue);

      final folderCat = GlobalSearchMatcher.match(
        sources: sources,
        query: 'Work',
        category: 'folder',
      );
      expect(folderCat.bookmarks.map((b) => b.id), ['bm1']);
    });
  });

  group('AdvancedSearchDialog widget behavior', () {
    Future<void> openTestDialog(
      WidgetTester tester, {
      required ValueSetter<AdvancedSearchSelection?> onResult,
      GlobalSearchSources? globalSources,
      List<({String root, String relPath})> extraSearchScopes = const [],
      SearchEntriesAdvancedFn? searchEntriesFn,
      GrepTextFilesFn? grepTextFilesFn,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  final res = await showAdvancedSearchDialog(
                    ctx,
                    root: '/home/user',
                    relPath: '',
                    globalSources: globalSources,
                    extraSearchScopes: extraSearchScopes,
                    searchEntriesFn: searchEntriesFn,
                    grepTextFilesFn: grepTextFilesFn,
                  );
                  onResult(res);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('empty dialog shows prompt hint instead of no-results error', (tester) async {
      AdvancedSearchSelection? selection;
      await openTestDialog(
        tester,
        globalSources: buildSampleSources(),
        onResult: (r) => selection = r,
        searchEntriesFn: ({required root, required path, required options}) async => [],
      );

      expect(find.text('输入关键字搜索文件、文件夹、收藏夹、远程连接与历史'), findsOneWidget);
      expect(find.textContaining('没有找到'), findsNothing);
      expect(selection, isNull);
    });

    testWidgets('typing bookmark name immediately shows and returns bookmark selection', (tester) async {
      AdvancedSearchSelection? selection;
      await openTestDialog(
        tester,
        globalSources: buildSampleSources(),
        onResult: (r) => selection = r,
        searchEntriesFn: ({required root, required path, required options}) async => [],
      );

      await tester.enterText(find.byType(TextField).first, '工作文档');
      // Only a minimal frame pump is needed: metadata results render immediately before debounce!
      await tester.pump();

      expect(find.text('工作文档收藏'), findsOneWidget);
      await tester.tap(find.text('工作文档收藏'));
      await tester.pumpAndSettle();

      expect(selection, isNotNull);
      expect(selection!.kind, AdvancedSearchSelectionKind.bookmark);
      expect(selection!.bookmark!.id, 'bm1');
    });

    testWidgets('searches folder names across extraSearchScopes and pops folder selection', (tester) async {
      AdvancedSearchSelection? selection;
      await openTestDialog(
        tester,
        globalSources: buildSampleSources(),
        extraSearchScopes: const [(root: '/mnt/usb', relPath: '')],
        onResult: (r) => selection = r,
        searchEntriesFn: ({required root, required path, required options}) async {
          if (root == '/mnt/usb') {
            return const [
              EntryDto(
                name: 'ProjectPhotos',
                path: '/ProjectPhotos',
                isDir: true,
                hidden: false,
                isSymlink: false,
              ),
            ];
          }
          return const [];
        },
      );

      await tester.enterText(find.byType(TextField).first, 'ProjectPhotos');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final resultTile = find.descendant(
        of: find.byType(ListTile),
        matching: find.text('ProjectPhotos'),
      );
      expect(resultTile, findsOneWidget);
      await tester.tap(resultTile);
      await tester.pumpAndSettle();

      expect(selection, isNotNull);
      expect(selection!.kind, AdvancedSearchSelectionKind.entry);
      expect(selection!.entry!.isDir, isTrue);
      expect(selection!.entryRoot, '/mnt/usb');
    });

    testWidgets('switching from wildcard mode to grep resets match mode cleanly without crash', (tester) async {
      await openTestDialog(
        tester,
        globalSources: buildSampleSources(),
        onResult: (_) {},
        searchEntriesFn: ({required root, required path, required options}) async => [],
        grepTextFilesFn: ({
          required root,
          required path,
          required pattern,
          required useRegex,
          required caseSensitive,
          required includeHidden,
          required maxMatches,
        }) async =>
            [],
      );

      // Select wildcard in dropdown
      await tester.tap(find.text('包含'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通配符 (* ?)').last);
      await tester.pumpAndSettle();
      expect(find.text('通配符 (* ?)'), findsOneWidget);

      // Switch SegmentedButton to Grep mode: must not throw DropdownButton assertion
      await tester.tap(find.text('内容全文搜索 (Grep)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('包含'), findsOneWidget);
    });
  });
}
