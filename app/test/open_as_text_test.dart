import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/widgets/browser/browser_action_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Open With Dialog and Open as Text Tests', () {
    test('Unrecognized file extensions fall under EntryCategory.other', () {
      final unrec = EntryItem(
        EntryDto(
          name: 'config.xyz',
          path: '/config.xyz',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(unrec.category, EntryCategory.other);
      expect(unrec.isDir, isFalse);
      expect(unrec.isText, isFalse);
      expect(unrec.isMedia, isFalse);
      expect(unrec.isImage, isFalse);
      expect(unrec.isArchive, isFalse);
    });

    testWidgets('showBrowserOpenWithDialog displays Open as Text option', (tester) async {
      final item = EntryItem(
        EntryDto(
          name: 'raw_payload.dat',
          path: '/raw_payload.dat',
          isDir: false,
          hidden: false,
          isSymlink: false,
          size: BigInt.from(1024),
        ),
      );

      String? selectedAction;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selectedAction = await showBrowserOpenWithDialog(
                        context: context,
                        item: item,
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Trigger the dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify options are present
      final l10n = AppLocalizations.of(tester.element(find.text('Open Dialog')));
      expect(find.text(l10n.openAsText), findsOneWidget);
      expect(find.text(l10n.openAsTextSubtitle), findsOneWidget);
      expect(find.text(l10n.openWithOtherApp), findsOneWidget);
      expect(find.text(l10n.openAsMedia), findsOneWidget);
      expect(find.text(l10n.openAsImage), findsOneWidget);

      // Tap "Open as Text"
      await tester.tap(find.text(l10n.openAsText));
      await tester.pumpAndSettle();

      // Verify the selected action is 'text'
      expect(selectedAction, 'text');
    });

    testWidgets('showBrowserEntryModalBottomSheet includes open_as_text for files', (tester) async {
      final item = EntryItem(
        EntryDto(
          name: 'unrecognized_file.bin',
          path: '/unrecognized_file.bin',
          isDir: false,
          hidden: false,
          isSymlink: false,
          size: BigInt.from(2048),
        ),
      );

      String? selectedAction;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      selectedAction = await showBrowserEntryModalBottomSheet(
                        context: context,
                        item: item,
                        isRemoteOrArchive: false,
                        canWrite: true,
                        canArchive: true,
                      );
                    },
                    child: const Text('Open Sheet'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Open the action sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.text('Open Sheet')));
      expect(find.text(l10n.openAsText), findsOneWidget);

      // Tap open as text
      await tester.tap(find.text(l10n.openAsText));
      await tester.pumpAndSettle();

      expect(selectedAction, 'open_as_text');
    });
  });
}
