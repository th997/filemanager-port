import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/controllers/browser_pane_controller.dart';
import 'package:filemanager/src/pages/home_page.dart';
import 'package:filemanager/src/services/auto_sync_service.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/theme/markdown_themes.dart';
import 'package:filemanager/src/widgets/editor/editor_preview_pane.dart';
import 'package:filemanager/src/widgets/error_recovery_action.dart';
import 'package:filemanager/src/widgets/media_player/media_player_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PreferencesService.instance.setString(AutoSyncService.prefSyncProfiles, '[]');
    PreferencesService.instance.setBool(AutoSyncService.prefOfflineAutoSync, true);
  });

  group('ErrorRecoveryActionButton', () {
    testWidgets('renders targeted recovery buttons for permission, credentials, archive, and space',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                ErrorRecoveryActionButton(
                  rawError: 'permission denied: /storage/emulated/0',
                  onOverrideAction: () => tapped++,
                ),
                ErrorRecoveryActionButton(
                  rawError: 'InvalidAccessKeyId from S3',
                  root: 'remote://s3-main',
                  onOverrideAction: () => tapped++,
                ),
                ErrorRecoveryActionButton(
                  rawError: 'encrypted archive wrong password',
                  root: 'archive:///tmp/a.zip',
                  onOverrideAction: () => tapped++,
                ),
                ErrorRecoveryActionButton(
                  rawError: 'No space left on device',
                  onOverrideAction: () => tapped++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('error_recovery_storagePermission')), findsOneWidget);
      expect(find.byKey(const ValueKey('error_recovery_remoteCredentials')), findsOneWidget);
      expect(find.byKey(const ValueKey('error_recovery_archivePassword')), findsOneWidget);
      expect(find.byKey(const ValueKey('error_recovery_storageSpace')), findsOneWidget);
      expect(find.text('前往授权'), findsOneWidget);
      expect(find.text('修改连接配置'), findsOneWidget);
      expect(find.text('输入解压密码'), findsOneWidget);
      expect(find.text('清理存储空间'), findsOneWidget);

      await tester.tap(find.text('修改连接配置'));
      expect(tapped, 1);
      expect(extractRemoteIdFromRoot('archive://remote://nas-01/backup.zip'), 'nas-01');
    });
  });

  group('AutoSyncService scheduler & resume reconciliation', () {
    test('executes only due scheduled profiles and respects offline resume cooldown', () async {
      var now = DateTime.utc(2026, 11, 24, 10, 0);
      final executedProfiles = <String>[];
      var offlineCheckRuns = 0;

      final svc = AutoSyncService(
        clock: () => now,
        profileRunner: (p) async {
          executedProfiles.add(p.name);
        },
        offlinePinRunner: () async {
          offlineCheckRuns++;
          return (pushed: 1, pulled: 0, conflicts: 0);
        },
      );

      svc.saveProfiles([
        const SyncProfile(
          name: 'ManualOnly',
          srcRoot: '/src',
          srcPath: '',
          dstRoot: '/dst',
          dstPath: '',
          mode: 'incremental',
          autoIntervalMinutes: 0,
        ),
        SyncProfile(
          name: 'DueBackup',
          srcRoot: '/src',
          srcPath: 'docs',
          dstRoot: '/dst',
          dstPath: 'docs',
          mode: 'incremental',
          autoIntervalMinutes: 30,
          lastAutoSyncMs:
              now.subtract(const Duration(minutes: 31)).millisecondsSinceEpoch,
        ),
        SyncProfile(
          name: 'RecentBackup',
          srcRoot: '/src',
          srcPath: 'pics',
          dstRoot: '/dst',
          dstPath: 'pics',
          mode: 'mirror',
          autoIntervalMinutes: 60,
          lastAutoSyncMs:
              now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
        ),
      ]);

      await svc.onAppResumed();
      expect(executedProfiles, ['DueBackup']);
      expect(offlineCheckRuns, 1);

      // Immediate second resume within 60s cooldown skips redundant remote checks
      // and already-synced profile.
      now = now.add(const Duration(seconds: 20));
      await svc.onAppResumed();
      expect(executedProfiles, ['DueBackup']);
      expect(offlineCheckRuns, 1);

      // After 65s cooldown, offline pin check runs again on resume.
      now = now.add(const Duration(seconds: 65));
      await svc.onAppResumed();
      expect(offlineCheckRuns, 2);
    });
  });

  group('Three-domain HomePage navigation on compact screens', () {
    testWidgets('renders Storage, Search & Library, and Tools & Tasks domains cleanly',
        (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('home_nav_storage')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_nav_discover')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_nav_tools')), findsOneWidget);
      expect(find.byKey(const ValueKey('home_nav_settings')), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('相册'), findsOneWidget);
      expect(find.text('回收站'), findsOneWidget);

      // Gallery and Recycle Bin should sit inside Local Files below its header and above Remote Connections.
      final localTop = tester.getTopLeft(find.text('本机文件').first).dy;
      final galleryTop = tester.getTopLeft(find.text('相册').first).dy;
      final trashTop = tester.getTopLeft(find.text('回收站').first).dy;
      final remoteTop = tester.getTopLeft(find.text('远程连接').first).dy;
      expect(galleryTop, greaterThan(localTop));
      expect(galleryTop, lessThan(remoteTop));
      expect(trashTop, greaterThan(localTop));
      expect(trashTop, lessThan(remoteTop));

      await tester.scrollUntilVisible(
        find.text('解锁、新建、备份或导入加密空间'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('隐私空间'), findsAtLeastNWidgets(1));

      // Switch to Favorites tab -> shows empty state and manage button without duplicate 收藏夹 card.
      await tester.tap(find.byKey(const ValueKey('home_nav_discover')));
      await tester.pumpAndSettle();
      expect(find.text('收藏夹'), findsNothing);
      expect(find.byKey(const ValueKey('home_manage_bookmarks_btn')), findsOneWidget);
      expect(find.text('暂无保存的书签'), findsOneWidget);
      expect(find.text('离线文件'), findsNothing);
      expect(find.text('最近访问'), findsNothing);
      expect(find.text('相册'), findsNothing);

      // Switch to Transfer tab -> shows Folder Sync and Offline Files without duplicate analyzer entries.
      await tester.tap(find.byKey(const ValueKey('home_nav_tools')));
      await tester.pumpAndSettle();
      expect(find.text('目录同步'), findsOneWidget);
      expect(find.text('离线文件'), findsOneWidget);
      expect(find.text('存储空间分析'), findsNothing);
      expect(find.text('重复文件清理'), findsNothing);

      // Switch to Settings tab -> shows Temporary Cache followed below by Recent.
      await tester.tap(find.byKey(const ValueKey('home_nav_settings')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings_recent_tile')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('临时缓存'), findsOneWidget);
      expect(find.text('最近访问'), findsOneWidget);
      final tempCacheTop = tester.getTopLeft(find.text('临时缓存')).dy;
      final recentTop = tester.getTopLeft(find.text('最近访问')).dy;
      expect(recentTop, greaterThan(tempCacheTop));
    });
  });

  group('BrowserPaneController host binding & address parser', () {
    test('attachHost delegates selection/location/refresh without GlobalKey', () {
      var refreshCalls = 0;
      var hostSelection = <String>['a.txt', 'b.txt'];
      final ctrl = BrowserPaneController(
        root: '/home/user',
        initialRelPath: 'Docs',
        title: 'Docs',
      );
      addTearDown(ctrl.dispose);

      ctrl.attachHost(
        root: '/home/user',
        relPath: 'Docs',
        onRefresh: () => refreshCalls++,
        onSelectedPathsGetter: () => hostSelection,
      );
      expect(ctrl.selectedPaths, {'a.txt', 'b.txt'});
      expect(ctrl.hasSelection, isTrue);

      ctrl.syncHostLocation('remote://nas', 'Movies');
      expect(ctrl.root, 'remote://nas');
      expect(ctrl.relPath, 'Movies');

      ctrl.requestRefresh();
      expect(refreshCalls, 1);

      hostSelection = const [];
      expect(ctrl.hasSelection, isFalse);
    });

    test('parseJumpAddress resolves remote, archive, Unix, Windows, and relative paths', () {
      expect(
        BrowserPaneController.parseJumpAddress(
          'remote://OfficeNAS/Shared/2026',
          currentRoot: '/tmp',
          currentRelPath: '',
          resolveRemoteId: (n) => n == 'OfficeNAS' ? 'r42' : null,
        ),
        (root: 'remote://r42', relPath: 'Shared/2026'),
      );
      expect(
        BrowserPaneController.parseJumpAddress(
          'archive:///tmp/pack.tar.gz/inner/readme.md',
          currentRoot: '/tmp',
          currentRelPath: '',
        ),
        (root: 'archive:///tmp/pack.tar.gz', relPath: 'inner/readme.md'),
      );
      expect(
        BrowserPaneController.parseJumpAddress(
          r'D:\Projects\App',
          currentRoot: 'C:/',
          currentRelPath: '',
        ),
        (root: 'D:/', relPath: 'Projects/App'),
      );
      expect(
        BrowserPaneController.parseJumpAddress(
          'sub/folder',
          currentRoot: '/home/th',
          currentRelPath: 'work',
        ),
        (root: '/home/th', relPath: 'work/sub/folder'),
      );
    });
  });

  group('Extracted EditorPreviewPane, EditorStatusBar & seek math', () {
    testWidgets('renders Markdown preview and EditorStatusBar cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: EditorPreviewPane(
                    isMarkdown: true,
                    isJson: false,
                    readOnly: false,
                    root: '/tmp',
                    path: 'note.md',
                    text: '# Heading One\n\nHello modular preview!',
                    isDirty: true,
                    fontSize: 14,
                    markdownTheme: MarkdownThemeType.github,
                    filterQuery: '',
                    onEditSource: () {},
                    onOpenRawCode: () {},
                    onHtmlControllerCreated: (_) {},
                    onOpenHtmlInBrowser: () {},
                  ),
                ),
                EditorStatusBar(
                  modeLabel: 'Preview',
                  isDirty: true,
                  cursorLine: 2,
                  cursorCol: 5,
                  lines: 3,
                  words: 5,
                  chars: 36,
                  largeFileMode: false,
                  chunkEncoding: 'utf-8',
                  fontSize: 14,
                  wordWrap: true,
                  onTapStats: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Heading One'), findsOneWidget);
      expect(find.textContaining('Hello modular preview!'), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(
        computeDragSeekDeltaSeconds(
          accumulatedDx: 100,
          screenWidth: 400,
          totalDuration: const Duration(minutes: 40),
        ),
        75,
      );
    });
  });
}
