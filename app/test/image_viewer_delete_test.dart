import 'dart:convert';
import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/image_viewer_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _samplePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  Widget wrapLauncher({
    required String filePath,
    required String fileName,
    required List<ImageViewerEntry> siblings,
    required VoidCallback onDeleted,
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => ImageViewerPage(
                      filePath: filePath,
                      fileName: fileName,
                      siblings: siblings,
                      onDeleted: onDeleted,
                    ),
                  ),
                );
              },
              child: const Text('OpenViewer'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('long-press deletes local image and advances to next sibling',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('img_del_lp_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final img1 = File('${tempDir.path}/a.png')..writeAsBytesSync(_samplePngBytes);
    final img2 = File('${tempDir.path}/b.png')..writeAsBytesSync(_samplePngBytes);
    bool deletedCalled = false;

    await tester.pumpWidget(
      wrapLauncher(
        filePath: img1.path,
        fileName: 'a.png',
        siblings: [
          ImageViewerEntry(name: 'a.png', localPath: img1.path),
          ImageViewerEntry(name: 'b.png', localPath: img2.path),
        ],
        onDeleted: () => deletedCalled = true,
      ),
    );

    await tester.tap(find.text('OpenViewer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a.png'), findsOneWidget);

    await tester.longPress(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();

    expect(find.text('删除图片'), findsOneWidget);
    await tester.tap(find.text('删除图片'));
    await tester.pumpAndSettle();

    // Confirm alert dialog.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(img1.existsSync(), isFalse);
    expect(img2.existsSync(), isTrue);
    expect(deletedCalled, isTrue);
    expect(find.text('b.png'), findsOneWidget);
  });

  testWidgets('right-click context menu deletes local image and pops when empty',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('img_del_rc_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final img1 = File('${tempDir.path}/only.png')..writeAsBytesSync(_samplePngBytes);
    bool deletedCalled = false;

    await tester.pumpWidget(
      wrapLauncher(
        filePath: img1.path,
        fileName: 'only.png',
        siblings: [
          ImageViewerEntry(name: 'only.png', localPath: img1.path),
        ],
        onDeleted: () => deletedCalled = true,
      ),
    );

    await tester.tap(find.text('OpenViewer'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('删除图片'), findsOneWidget);
    await tester.tap(find.text('删除图片'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(img1.existsSync(), isFalse);
    expect(deletedCalled, isTrue);
    expect(find.text('OpenViewer'), findsOneWidget);
  });

  testWidgets('custom deleteHandler supports deleting library photo assets',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('img_del_custom_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final img1 = File('${tempDir.path}/photo.png')..writeAsBytesSync(_samplePngBytes);
    bool handlerInvoked = false;
    bool deletedCalled = false;

    final entry = ImageViewerEntry(
      name: 'photo.png',
      resolvePath: () async => img1.path,
      deleteHandler: () async {
        handlerInvoked = true;
        return true;
      },
    );
    expect(entry.canDelete, isTrue);

    await tester.pumpWidget(
      wrapLauncher(
        filePath: img1.path,
        fileName: 'photo.png',
        siblings: [entry],
        onDeleted: () => deletedCalled = true,
      ),
    );

    await tester.tap(find.text('OpenViewer'));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(handlerInvoked, isTrue);
    expect(deletedCalled, isTrue);
    // Custom handler was responsible for deletion, so local file itself wasn't directly touched.
    expect(img1.existsSync(), isTrue);
  });
}
