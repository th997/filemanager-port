import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/storage_analyzer_page.dart';
import 'package:filemanager/src/rust/api/inspect.dart';
import 'package:filemanager/src/services/platform_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageAnalyzerPage path helpers', () {
    test('normalizeRelPath strips leading, trailing, and duplicate slashes', () {
      expect(StorageAnalyzerPage.normalizeRelPath(''), '');
      expect(StorageAnalyzerPage.normalizeRelPath('/'), '');
      expect(StorageAnalyzerPage.normalizeRelPath('/Users/th/'), 'Users/th');
      expect(
        StorageAnalyzerPage.normalizeRelPath('///Downloads//2026/'),
        'Downloads/2026',
      );
    });

    test('formatDisplayPath formats native, friendly, and virtual roots cleanly', () {
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: '/',
          title: '/',
          relPath: '',
        ),
        '/',
      );
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: '/',
          title: '/',
          relPath: '/Users/th/',
        ),
        '/Users/th',
      );
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: '/Users/th',
          title: '/Users/th',
          relPath: '/Downloads/',
        ),
        '/Users/th/Downloads',
      );
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: '/Users/th',
          title: 'Local Storage',
          relPath: '/Downloads/2026',
        ),
        'Local Storage/Downloads/2026',
      );
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: 'remote://r1',
          title: 'remote://MyNAS',
          relPath: '/Media/Movies',
        ),
        'remote://MyNAS/Media/Movies',
      );
      expect(
        StorageAnalyzerPage.formatDisplayPath(
          root: 'pool://p1',
          title: 'pool://HomePool',
          relPath: '/Backups/',
        ),
        'pool://HomePool/Backups',
      );
    });
  });

  group('StorageAnalyzerPage widget & multi-select', () {
    Widget wrap(Widget child) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );
    }

    StorageAnalysisDto buildMockAnalysis() {
      return StorageAnalysisDto(
        totalBytes: BigInt.from(3 * 1024 * 1024),
        totalFiles: BigInt.from(2),
        totalDirs: BigInt.from(2),
        truncated: false,
        cancelled: false,
        folders: [
          StorageFolderRankDto(
            name: 'Downloads',
            path: '/Downloads',
            sizeBytes: BigInt.from(2 * 1024 * 1024),
            fileCount: BigInt.from(1),
          ),
          StorageFolderRankDto(
            name: 'Docs',
            path: '/Docs',
            sizeBytes: BigInt.from(1024 * 1024),
            fileCount: BigInt.from(1),
          ),
        ],
        largestFiles: [
          StorageFileRankDto(
            name: 'movie.mkv',
            path: '/Downloads/movie.mkv',
            sizeBytes: BigInt.from(2 * 1024 * 1024),
          ),
          StorageFileRankDto(
            name: 'archive.zip',
            path: '/Docs/archive.zip',
            sizeBytes: BigInt.from(1024 * 1024),
          ),
        ],
        categories: [
          StorageCategoryDto(
            category: 'video',
            sizeBytes: BigInt.from(2 * 1024 * 1024),
            fileCount: BigInt.from(1),
          ),
          StorageCategoryDto(
            category: 'archive',
            sizeBytes: BigInt.from(1024 * 1024),
            fileCount: BigInt.from(1),
          ),
        ],
      );
    }

    testWidgets(
        'renders clean header/subtitles, supports multi-select, batch delete, and clears on tab switch',
        (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);

      List<String>? deletedBatch;
      await tester.pumpWidget(
        wrap(
          StorageAnalyzerPage(
            root: '/Users/th',
            initialPath: '/Downloads/',
            title: '/Users/th',
            initialAnalysisOverride: buildMockAnalysis(),
            onBatchDeleteOverride: (paths) async {
              deletedBatch = List<String>.from(paths);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AppBar displays '/Users/th/Downloads' without duplicated segments or '//'.
      expect(find.text('/Users/th/Downloads'), findsOneWidget);
      expect(find.text('/Users/th//Downloads'), findsNothing);
      expect(find.byIcon(Icons.checklist), findsNothing);

      // Switch to Top Files tab.
      await tester.tap(find.text('Largest Files'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.checklist), findsOneWidget);
      expect(find.text('/Users/th/Downloads'), findsNWidgets(2));
      expect(find.text('/Users/th/Docs'), findsOneWidget);

      // Enter selection mode via long-press on first file, then switch tabs to verify reset.
      await tester.longPress(find.text('movie.mkv'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected (2.0 MB)'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Switching away from Largest Files exits selection mode and clears selection.
      await tester.tap(find.text('Largest Folders'));
      await tester.pumpAndSettle();
      expect(find.text('Move'), findsNothing);
      expect(find.byIcon(Icons.select_all), findsNothing);

      // Return to Largest Files and enter multi-select via AppBar checklist icon.
      await tester.tap(find.text('Largest Files'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.checklist));
      await tester.pumpAndSettle();
      expect(find.text('0 selected (0 B)'), findsOneWidget);

      // Select All & Deselect All toggle.
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      expect(find.text('2 selected (3.0 MB)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.deselect));
      await tester.pumpAndSettle();
      expect(find.text('0 selected (0 B)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      expect(find.text('2 selected (3.0 MB)'), findsOneWidget);

      // Trigger Batch Delete -> confirm -> invokes override, clears selection & removes rows.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 file(s)?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(deletedBatch, ['/Downloads/movie.mkv', '/Docs/archive.zip']);
      expect(find.text('movie.mkv'), findsNothing);
      expect(find.text('archive.zip'), findsNothing);
      expect(find.text('Move'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
