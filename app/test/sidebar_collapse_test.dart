import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/rust/api/metadata.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/widgets/desktop_sidebar_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    final prefs = PreferencesService.instance;
    prefs.sidebarCollapsed = false;
    prefs.sidebarCollapsedGroups = const {};
    prefs.sidebarWidth = 240.0;
  });

  tearDown(() {
    final prefs = PreferencesService.instance;
    prefs.sidebarCollapsed = false;
    prefs.sidebarCollapsedGroups = const {};
    prefs.sidebarWidth = 240.0;
  });

  Widget buildShell({
    List<RemoteConfigDto> remotes = const [
      RemoteConfigDto(
        id: 'r1',
        name: 'Office NAS',
        kind: 'smb',
        host: '192.168.1.20',
        pathStyle: false,
      ),
    ],
    List<BookmarkDto> bookmarks = const [
      BookmarkDto(
        id: 'bm1',
        name: 'Work Docs',
        root: '/home/user',
        path: 'Documents',
      ),
    ],
  }) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DesktopSidebarShell(
        remotes: remotes,
        bookmarks: bookmarks,
        history: const [],
        trashCount: 2,
        activeTaskCount: 1,
        diskSpace: null,
        themeMode: ThemeMode.system,
        onRefreshMetadata: () {},
        onOpenGlobalSearch: ({root, relPath, onNavigate}) async {},
        workspaceOverride: const SizedBox.expand(),
      ),
    );
  }

  testWidgets('collapses entire sidebar to 52px rail and expands back with persistence',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sidebar_collapse_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_expand_btn')), findsNothing);
    expect(find.text('Work Docs'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Collapse sidebar -> shrinks to 52px icon rail and persists setting.
    await tester.tap(find.byKey(const ValueKey('sidebar_collapse_btn')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(PreferencesService.instance.sidebarCollapsed, isTrue);
    expect(find.byKey(const ValueKey('sidebar_expand_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar_collapse_btn')), findsNothing);
    final railBox = tester.getSize(find.byType(AnimatedContainer).first);
    expect(railBox.width, 52.0);
    // Task/trash badges still surface on the compact icon rail.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    // Expand back -> restores full width and group list.
    await tester.tap(find.byKey(const ValueKey('sidebar_expand_btn')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(PreferencesService.instance.sidebarCollapsed, isFalse);
    expect(find.byKey(const ValueKey('sidebar_collapse_btn')), findsOneWidget);
    expect(find.text('Work Docs'), findsOneWidget);
  });

  testWidgets('folds and unfolds individual sidebar section groups with count badge',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.text('Work Docs'), findsOneWidget);
    expect(find.text('Office NAS'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);

    // Fold bookmarks group -> hides Work Docs and shows item count '1'.
    await tester.tap(find.byKey(const ValueKey('sidebar_group_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.text('Work Docs'), findsNothing);
    expect(PreferencesService.instance.sidebarCollapsedGroups.contains('bookmarks'), isTrue);

    // Fold remotes and tools groups -> hides Office NAS and 回收站.
    await tester.tap(find.byKey(const ValueKey('sidebar_group_remotes')));
    await tester.pumpAndSettle();
    expect(find.text('Office NAS'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar_group_tools')));
    await tester.pumpAndSettle();
    expect(find.text('回收站'), findsNothing);

    expect(
      PreferencesService.instance.sidebarCollapsedGroups,
      containsAll(['bookmarks', 'remotes', 'tools']),
    );

    // Unfold bookmarks -> Work Docs reappears.
    await tester.tap(find.byKey(const ValueKey('sidebar_group_bookmarks')));
    await tester.pumpAndSettle();
    expect(find.text('Work Docs'), findsOneWidget);
    expect(PreferencesService.instance.sidebarCollapsedGroups.contains('bookmarks'), isFalse);
  });

  testWidgets('trailing add button in remotes header switches section without folding remotes group',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sidebar_add_remote_btn')));
    await tester.pumpAndSettle();

    expect(find.text('Office NAS'), findsOneWidget);
    expect(PreferencesService.instance.sidebarCollapsedGroups.contains('remotes'), isFalse);
  });

  testWidgets('bookmarks header uses clean edit icon and switches section without folding group',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildShell());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.tune_outlined), findsNothing);
    final manageBtn = find.byKey(const ValueKey('sidebar_manage_bookmarks_btn'));
    expect(manageBtn, findsOneWidget);
    expect(
      find.descendant(of: manageBtn, matching: find.byIcon(Icons.edit_outlined)),
      findsOneWidget,
    );

    await tester.tap(manageBtn);
    await tester.pumpAndSettle();

    expect(find.text('Work Docs'), findsOneWidget);
    expect(PreferencesService.instance.sidebarCollapsedGroups.contains('bookmarks'), isFalse);
  });
}
