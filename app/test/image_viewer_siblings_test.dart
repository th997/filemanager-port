import 'dart:io';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/image_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageViewerPage Siblings Discovery Tests', () {
    test('EntryItem.isImageExtension detects image extensions correctly', () {
      expect(EntryItem.isImageExtension('jpg'), isTrue);
      expect(EntryItem.isImageExtension('jpeg'), isTrue);
      expect(EntryItem.isImageExtension('png'), isTrue);
      expect(EntryItem.isImageExtension('gif'), isTrue);
      expect(EntryItem.isImageExtension('webp'), isTrue);
      expect(EntryItem.isImageExtension('bmp'), isTrue);
      expect(EntryItem.isImageExtension('avif'), isTrue);
      expect(EntryItem.isImageExtension('txt'), isFalse);
      expect(EntryItem.isImageExtension('mp4'), isFalse);
      expect(EntryItem.isImageExtension('pdf'), isFalse);
    });

    testWidgets('ImageViewerPage auto-discovers sibling images in parent directory and navigates next/previous', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('image_viewer_test_');
      File('${tempDir.path}/a.png').writeAsStringSync('a');
      final imgB = File('${tempDir.path}/b.png')..writeAsStringSync('b');
      File('${tempDir.path}/c.png').writeAsStringSync('c');
      File('${tempDir.path}/notes.txt').writeAsStringSync('not an image');

      try {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ImageViewerPage(
              filePath: imgB.path,
              fileName: 'b.png',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('2 / 3'), findsOneWidget);
        expect(find.textContaining('b.png'), findsWidgets);

        // Tap the forward button in the bottom pill
        await tester.tap(find.byIcon(Icons.arrow_forward_ios));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('3 / 3'), findsOneWidget);
        expect(find.textContaining('c.png'), findsWidgets);

        // Tap the back button in the bottom pill
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('2 / 3'), findsOneWidget);
        expect(find.textContaining('b.png'), findsWidgets);

        // Tap the left floating side button
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('1 / 3'), findsOneWidget);
        expect(find.textContaining('a.png'), findsWidgets);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
