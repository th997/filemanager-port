import 'dart:convert';
import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/gallery_page.dart';
import 'package:filemanager/src/services/external_file_service.dart';
import 'package:filemanager/src/services/platform_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 transparent PNG so Image.file decodes without error logs.
final List<int> _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

File _createTempImage(Directory dir, String name, {DateTime? modified}) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(_tinyPng, flush: true);
  if (modified != null) {
    file.setLastModifiedSync(modified);
  }
  return file;
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
  tearDown(() {
    PlatformCapabilities.debugPlatformOverride = null;
  });

  testWidgets(
    'Toolbar select mode toggles tiles, select all/deselect all, and exits cleanly',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('gallery_ms_1_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final files = [
        _createTempImage(dir, 'a.png', modified: DateTime(2026, 2, 10)),
        _createTempImage(dir, 'b.png', modified: DateTime(2026, 2, 9)),
        _createTempImage(dir, 'c.png', modified: DateTime(2026, 2, 8)),
      ];

      await tester.pumpWidget(
        _wrap(GalleryPage(scanFilesOverride: () async => files)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gallery_select_mode_btn')));
      await tester.pumpAndSettle();

      expect(find.text('已选 0 项'), findsOneWidget);

      final tiles = find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(tiles.at(0));
      await tester.pumpAndSettle();
      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_select_all_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_select_all_btn')));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_exit_select_btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gallery_select_mode_btn')), findsOneWidget);
      expect(find.textContaining('照片 (3)'), findsOneWidget);
    },
  );

  testWidgets(
    'Long-press enters selection mode and batch delete removes selected photos',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('gallery_ms_2_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final files = [
        _createTempImage(dir, 'p1.png', modified: DateTime(2026, 2, 10)),
        _createTempImage(dir, 'p2.png', modified: DateTime(2026, 2, 9)),
        _createTempImage(dir, 'p3.png', modified: DateTime(2026, 2, 8)),
      ];
      final deletedPaths = <String>[];

      await tester.pumpWidget(
        _wrap(
          GalleryPage(
            scanFilesOverride: () async => files,
            deleteFilesOverride: (toDelete) async {
              deletedPaths.addAll(toDelete.map((f) => f.path));
              return toDelete.length;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridTiles = find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(InkWell),
      );
      await tester.longPress(gridTiles.first);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.tap(gridTiles.at(1));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_batch_delete_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(deletedPaths, [files[0].path, files[1].path]);
      expect(find.textContaining('照片 (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('gallery_select_mode_btn')), findsOneWidget);
    },
  );

  testWidgets(
    'Month header selects entire month and batch share passes selected paths',
    (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.android;
      final dir = Directory.systemTemp.createTempSync('gallery_ms_3_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final files = [
        _createTempImage(dir, 'feb1.png', modified: DateTime(2026, 2, 12)),
        _createTempImage(dir, 'feb2.png', modified: DateTime(2026, 2, 3)),
        _createTempImage(dir, 'jan1.png', modified: DateTime(2026, 1, 20)),
      ];
      final shared = <String>[];

      await tester.pumpWidget(
        _wrap(
          GalleryPage(
            scanFilesOverride: () async => files,
            shareFilesOverride: (paths) async {
              shared.addAll(paths);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gallery_select_mode_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gallery_month_select_2026年2月')));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_batch_share_btn')));
      await tester.pumpAndSettle();

      expect(shared, [files[0].path, files[1].path]);
    },
  );

  testWidgets(
    'External multi-pick mode starts in selection mode and pops selected file paths',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('gallery_ms_4_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final files = [
        _createTempImage(dir, 'pick1.png', modified: DateTime(2026, 2, 5)),
        _createTempImage(dir, 'pick2.png', modified: DateTime(2026, 2, 4)),
        _createTempImage(dir, 'pick3.png', modified: DateTime(2026, 2, 3)),
      ];
      List<String>? poppedResult;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (ctx) => Center(
              child: FilledButton(
                onPressed: () async {
                  poppedResult = await Navigator.of(ctx).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => GalleryPage(
                        pickRequest: const ExternalPickRequest(
                          allowMultiple: true,
                          mimeType: 'image/*',
                        ),
                        scanFilesOverride: () async => files,
                      ),
                    ),
                  );
                },
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();

      expect(find.text('已选 0 项'), findsOneWidget);

      final gridTiles = find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(gridTiles.at(0));
      await tester.pumpAndSettle();
      await tester.tap(gridTiles.at(2));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 项'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gallery_confirm_pick_btn')));
      await tester.pumpAndSettle();

      expect(poppedResult, [files[0].path, files[2].path]);
    },
  );
}
