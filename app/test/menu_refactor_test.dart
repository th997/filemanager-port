import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/settings_page.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/widgets/browser/browser_action_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapLocalized(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  group('Browser entry bottom sheet refactor', () {
    EntryItem buildSampleFile() {
      return EntryItem(
        EntryDto(
          name: 'report.pdf',
          path: 'report.pdf',
          isDir: false,
          size: BigInt.from(2048),
          hidden: false,
          isSymlink: false,
        ),
      );
    }

    testWidgets(
        'renders top 4 quick actions, grouped sections, and single Share entry when writable',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final item = buildSampleFile();
      await tester.pumpWidget(
        wrapLocalized(
          Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showBrowserEntryModalBottomSheet(
                      context: ctx,
                      item: item,
                      isRemoteOrArchive: true,
                      canWrite: true,
                      canArchive: true,
                      canPinOffline: true,
                      canShareLan: true,
                      canShare: true,
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Cut'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Open & Transfer'), findsOneWidget);
      expect(find.text('Organize & Info'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save Offline'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows single Share entry when read-only', (tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final item = buildSampleFile();
      await tester.pumpWidget(
        wrapLocalized(
          Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showBrowserEntryModalBottomSheet(
                      context: ctx,
                      item: item,
                      isRemoteOrArchive: true,
                      canWrite: false,
                      canArchive: false,
                      canPinOffline: false,
                      canShareLan: false,
                      canShare: true,
                    );
                  },
                  child: const Text('Open ReadOnly Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open ReadOnly Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Properties'), findsOneWidget);
      expect(find.text('Download to local'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Embedded SettingsPage in 4-Tab HomePage', () {
    testWidgets('renders without AppBar and exposes temporary cache cleanup',
        (tester) async {
      await tester.pumpWidget(
        wrapLocalized(
          Scaffold(
            body: SettingsPage(
              embedded: true,
              currentThemeMode: ThemeMode.system,
              onThemeModeChanged: (_) {},
              localeCode: 'en',
              onLocaleChanged: (_) {},
              accentCode: 'deepTeal',
              onAccentChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      final recentFinder = find.byKey(const ValueKey('settings_recent_tile'));
      await tester.scrollUntilVisible(
        recentFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Temporary Cache'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Recent')).dy,
        greaterThan(tester.getTopLeft(find.text('Temporary Cache')).dy),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
