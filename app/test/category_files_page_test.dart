import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/category_files_page.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/rust/api/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

EntryDto _file(
  String name,
  String path, {
  int size = 1024,
  int modifiedMillis = 1700000000000,
}) {
  return EntryDto(
    name: name,
    path: path,
    isDir: false,
    size: BigInt.from(size),
    modifiedMillis: PlatformInt64Util.from(modifiedMillis),
    hidden: false,
    isSymlink: false,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: child,
  );
}

void main() {
  testWidgets(
    'CategoryFilesPage opens without autofocused TextField and shows summary & chips',
    (tester) async {
      final entries = [
        _file('QuarterlyReport.pdf', '/Documents/QuarterlyReport.pdf', size: 2048),
        _file('MeetingNotes.docx', '/Documents/Work/MeetingNotes.docx', size: 1024),
        _file('Readme.md', '/Projects/Readme.md', size: 512),
      ];

      await tester.pumpWidget(
        _wrap(
          CategoryFilesPage(
            category: 'document',
            root: '/tmp',
            searchEntriesFn: ({
              required String root,
              required String path,
              required AdvancedSearchQueryDto options,
            }) async =>
                entries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero TextFields / focused text input on initial open.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('文档'), findsWidgets);
      expect(find.textContaining('3 项'), findsOneWidget);
      expect(find.text('全部 (3)'), findsOneWidget);
      expect(find.text('PDF (1)'), findsOneWidget);
      expect(find.text('DOCX (1)'), findsOneWidget);
      expect(find.text('MD (1)'), findsOneWidget);
      expect(find.text('QuarterlyReport.pdf'), findsOneWidget);
      expect(find.text('MeetingNotes.docx'), findsOneWidget);
    },
  );

  testWidgets(
    'Extension filter chips and Clear filters filter and restore items cleanly',
    (tester) async {
      final entries = [
        _file('Spec.pdf', '/Docs/Spec.pdf', size: 4096),
        _file('Plan.docx', '/Docs/Plan.docx', size: 2048),
        _file('Budget.pdf', '/Finance/Budget.pdf', size: 1024),
      ];

      await tester.pumpWidget(
        _wrap(
          CategoryFilesPage(
            category: 'document',
            root: '/tmp',
            searchEntriesFn: ({
              required String root,
              required String path,
              required AdvancedSearchQueryDto options,
            }) async =>
                entries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('PDF (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Spec.pdf'), findsOneWidget);
      expect(find.text('Budget.pdf'), findsOneWidget);
      expect(find.text('Plan.docx'), findsNothing);
      expect(find.textContaining('2 项'), findsOneWidget);
      expect(find.text('清除筛选'), findsOneWidget);

      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();

      expect(find.text('Plan.docx'), findsOneWidget);
      expect(find.textContaining('3 项'), findsOneWidget);
    },
  );

  testWidgets(
    'On-demand search toggles cleanly and sort menu reorders files',
    (tester) async {
      final entries = [
        _file('Alpha.pdf', '/Docs/Alpha.pdf', size: 100, modifiedMillis: 1000),
        _file('Zulu.pdf', '/Docs/Zulu.pdf', size: 5000, modifiedMillis: 3000),
        _file('Bravo.pdf', '/Docs/Bravo.pdf', size: 2000, modifiedMillis: 2000),
      ];

      await tester.pumpWidget(
        _wrap(
          CategoryFilesPage(
            category: 'document',
            root: '/tmp',
            searchEntriesFn: ({
              required String root,
              required String path,
              required AdvancedSearchQueryDto options,
            }) async =>
                entries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default sort is date descending: Zulu (3000) above Alpha (1000).
      expect(
        tester.getTopLeft(find.text('Zulu.pdf')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha.pdf')).dy),
      );

      // Sort by name (first tap sorts ascending: Alpha before Zulu).
      await tester.tap(find.byIcon(Icons.sort_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按名称'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Alpha.pdf')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu.pdf')).dy),
      );

      // Activate inline search on demand.
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bravo');
      await tester.pumpAndSettle();
      expect(find.text('Bravo.pdf'), findsOneWidget);
      expect(find.text('Alpha.pdf'), findsNothing);

      // Close search restores full list and removes TextField.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Alpha.pdf'), findsOneWidget);
    },
  );

  testWidgets(
    'Video category defaults to grid view and toggles to list view',
    (tester) async {
      final entries = [
        _file('ClipA.mp4', '/Movies/ClipA.mp4', size: 1024 * 1024),
        _file('ClipB.mkv', '/Movies/ClipB.mkv', size: 2048 * 1024),
      ];

      await tester.pumpWidget(
        _wrap(
          CategoryFilesPage(
            category: 'video',
            root: '/tmp',
            searchEntriesFn: ({
              required String root,
              required String path,
              required AdvancedSearchQueryDto options,
            }) async =>
                entries,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(SliverGrid), findsNothing);
      expect(find.byType(SliverList), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'Context menu delete removes file after confirmation',
    (tester) async {
      final deleted = <EntryItem>[];
      final entries = [
        _file('Installer.apk', '/Downloads/Installer.apk', size: 8192),
        _file('Patch.apks', '/Downloads/Patch.apks', size: 4096),
      ];

      await tester.pumpWidget(
        _wrap(
          CategoryFilesPage(
            category: 'apk',
            root: '/tmp',
            searchEntriesFn: ({
              required String root,
              required String path,
              required AdvancedSearchQueryDto options,
            }) async =>
                entries,
            onDeleteFileOverride: (item) async {
              deleted.add(item);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // Confirm deletion in dialog.
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(deleted, hasLength(1));
      expect(deleted.single.name, 'Installer.apk');
      expect(find.text('Installer.apk'), findsNothing);
      expect(find.text('Patch.apks'), findsOneWidget);
      expect(find.textContaining('1 项'), findsOneWidget);
    },
  );
}
