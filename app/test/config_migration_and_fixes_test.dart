import 'dart:convert';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/config_migration_dialogs.dart';
import 'package:filemanager/src/pages/home_page.dart';
import 'package:filemanager/src/pages/recent_page.dart';
import 'package:filemanager/src/pages/remotes_page.dart';
import 'package:filemanager/src/rust/api/metadata.dart';
import 'package:filemanager/src/rust/api/pool.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/services/config_migration_service.dart';
import 'package:filemanager/src/services/platform_capabilities.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/remote_transfer_service.dart';
import 'package:filemanager/src/widgets/desktop_sidebar_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _mockEncrypt({
  required String plaintextJson,
  required String password,
}) {
  final salt = base64Encode(utf8.encode('mock-salt-$password'));
  final nonce = base64Encode(utf8.encode('mock-nonce-1'));
  final ct = base64Encode(utf8.encode(plaintextJson));
  return jsonEncode({
    'format': ConfigMigrationService.envelopeFormat,
    'salt': salt,
    'nonce': nonce,
    'ciphertext': ct,
  });
}

String _mockDecrypt({
  required String envelopeJson,
  required String password,
}) {
  final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
  final expectedSalt = base64Encode(utf8.encode('mock-salt-$password'));
  if (map['salt'] != expectedSalt) {
    throw StateError('incorrect password or corrupted migration bundle');
  }
  return utf8.decode(base64Decode(map['ciphertext'] as String));
}

RemoteConfigDto _remote({
  required String id,
  required String name,
  String kind = 's3',
}) =>
    RemoteConfigDto(
      id: id,
      name: name,
      kind: kind,
      endpoint: kind == 's3' ? 'https://s3.example.com' : 'https://dav.example.com',
      bucket: kind == 's3' ? 'bucket-$id' : null,
      accessKeyId: kind == 's3' ? 'AKIA-$id' : null,
      secretAccessKey: kind == 's3' ? 'secret-$id' : null,
      username: kind == 'webdav' ? 'user-$id' : null,
      password: kind == 'webdav' ? 'pass-$id' : null,
      rootPath: '/',
      pathStyle: kind == 's3',
    );

PoolConfigDto _poolConfig({
  required String id,
  required String name,
  required List<String> remoteIds,
  bool encrypt = true,
  String? passphrase = 'pool-passphrase',
}) =>
    PoolConfigDto(
      id: id,
      name: name,
      chunkSize: 4 * 1024 * 1024,
      replicationFactor: remoteIds.length > 1 ? 2 : 1,
      encrypt: encrypt,
      passphrase: passphrase,
      kdfSalt: encrypt ? 'c2FsdA==' : null,
      nodes: [
        for (var i = 0; i < remoteIds.length; i++)
          PoolNodeConfigDto(
            nodeId: 'node_${i + 1}',
            remoteId: remoteIds[i],
            basePrefix: 'pool_data',
            failureDomain: 'rack_${i + 1}',
            quotaBytes: BigInt.parse('50000000000'),
            weight: 120 - i * 10,
            role: 'data_and_meta',
            isMetaBackup: i == 0,
          ),
      ],
    );

Widget _wrapL10n(
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    final prefs = PreferencesService.instance;
    prefs.sidebarCollapsed = false;
    prefs.sidebarCollapsedGroups = const {};
    prefs.sidebarWidth = 240.0;
  });

  group('ConfigMigrationService unit rules', () {
    test('poolConfigToMap / poolConfigFromMap round-trips passphrase, salt, quotaBytes and weight', () {
      final orig = _poolConfig(
        id: 'pool-1',
        name: 'Primary Pool',
        remoteIds: ['r1', 'r2'],
      );
      final encoded = ConfigMigrationService.poolConfigToMap(orig);
      final decoded = ConfigMigrationService.poolConfigFromMap(encoded);

      expect(decoded.id, 'pool-1');
      expect(decoded.name, 'Primary Pool');
      expect(decoded.encrypt, isTrue);
      expect(decoded.passphrase, 'pool-passphrase');
      expect(decoded.kdfSalt, 'c2FsdA==');
      expect(decoded.nodes, hasLength(2));
      expect(decoded.nodes[0].remoteId, 'r1');
      expect(decoded.nodes[0].quotaBytes, BigInt.parse('50000000000'));
      expect(decoded.nodes[0].weight, 120);
      expect(decoded.nodes[0].isMetaBackup, isTrue);
    });

    test('computes pool->remote dependencies and password requirement accurately', () {
      final pools = [
        PoolRefInfo(id: 'p1', name: 'Main Pool', remoteIds: ['r1', 'r2']),
        PoolRefInfo(id: 'p2', name: 'Archive Pool', remoteIds: ['r2', 'r3']),
      ];

      expect(
        ConfigMigrationService.requiredRemoteIdsForRefs(
          selectedPoolIds: ['p1'],
          pools: pools,
        ),
        {'r1', 'r2'},
      );
      expect(
        ConfigMigrationService.dependentPoolNamesByRemoteForRefs(
          selectedPoolIds: ['p1', 'p2'],
          pools: pools,
        ),
        {
          'r1': ['Main Pool'],
          'r2': ['Main Pool', 'Archive Pool'],
          'r3': ['Archive Pool'],
        },
      );

      expect(
        ConfigMigrationService.requiresPassword(
          selectedRemoteIds: ['r1'],
          selectedPoolIds: const [],
        ),
        isTrue,
      );
      expect(
        ConfigMigrationService.requiresPassword(
          selectedRemoteIds: const [],
          selectedPoolIds: ['p1'],
        ),
        isTrue,
      );
      expect(
        ConfigMigrationService.requiresPassword(
          selectedRemoteIds: const [],
          selectedPoolIds: const [],
        ),
        isFalse,
      );
    });

    test('encodeSelectiveBundle enforces password and pool dependencies, and decodeBundle supports v3 + legacy .fmremotes', () {
      final r1 = _remote(id: 'r1', name: 'S3 Primary');
      final r2 = _remote(id: 'r2', name: 'WebDAV Spare', kind: 'webdav');
      final p1 = _poolConfig(id: 'p1', name: 'Main Pool', remoteIds: ['r1']);
      const bm = BookmarkDto(id: 'b1', name: 'Docs', root: '/tmp', path: 'docs');

      // Remotes/pools present without password -> rejected.
      expect(
        () => ConfigMigrationService.encodeSelectiveBundle(
          remotes: [r1],
          pools: [p1],
          bookmarks: const [bm],
          preferences: const {'app.language': 'en'},
          includeBookmarks: true,
          includePreferences: true,
          password: '',
          encryptFn: _mockEncrypt,
        ),
        throwsArgumentError,
      );

      // Even if caller omitted r1 from remotes list when pool p1 uses r1, only passed remotes are kept unless required is in remotes.
      final encryptedExport = ConfigMigrationService.encodeSelectiveBundle(
        remotes: [r1, r2],
        pools: [p1],
        bookmarks: const [bm],
        preferences: const {'app.language': 'zh'},
        includeBookmarks: true,
        includePreferences: true,
        password: 'vault-password',
        encryptFn: _mockEncrypt,
      );
      expect(encryptedExport.encrypted, isTrue);
      expect(encryptedExport.suggestedFilename, 'filemanager_backup.fmbak');
      expect(encryptedExport.remotesCount, 2);
      expect(encryptedExport.poolsCount, 1);

      final parsedV3 = ConfigMigrationService.decodeBundle(
        encryptedExport.payload,
        password: 'vault-password',
        decryptFn: _mockDecrypt,
      );
      expect(parsedV3.remotes.map((r) => r.id), ['r1', 'r2']);
      expect(parsedV3.pools.single.passphrase, 'pool-passphrase');
      expect(parsedV3.bookmarks.single.name, 'Docs');
      expect(parsedV3.preferences['app.language'], 'zh');

      // Plaintext export with only bookmarks + preferences succeeds without password.
      final plainExport = ConfigMigrationService.encodeSelectiveBundle(
        remotes: const [],
        pools: const [],
        bookmarks: const [bm],
        preferences: const {'app.language': 'ja'},
        includeBookmarks: true,
        includePreferences: true,
        password: '',
      );
      expect(plainExport.encrypted, isFalse);
      expect(plainExport.suggestedFilename, 'filemanager_config.json');
      final parsedPlain = ConfigMigrationService.decodeBundle(plainExport.payload);
      expect(parsedPlain.remotes, isEmpty);
      expect(parsedPlain.pools, isEmpty);
      expect(parsedPlain.bookmarks.single.name, 'Docs');
      expect(parsedPlain.preferences['app.language'], 'ja');

      // Legacy .fmremotes envelope compatibility.
      final legacyPayload = RemoteTransferService.encryptRemotesBundle(
        [r2],
        password: 'legacy-pass-1',
        encryptFn: _mockEncrypt,
      );
      final parsedLegacy = ConfigMigrationService.decodeBundle(
        legacyPayload,
        password: 'legacy-pass-1',
        decryptFn: _mockDecrypt,
      );
      expect(parsedLegacy.remotes.single.id, 'r2');
      expect(parsedLegacy.pools, isEmpty);
    });
  });

  group('ConfigExportDialog & ConfigImportDialog widgets', () {
    testWidgets('defaults all checked, locks pool-required remotes, requires password only when remotes/pools checked', (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final remotes = [
        _remote(id: 'r1', name: 'Pool Node S3'),
        _remote(id: 'r2', name: 'Standalone WebDAV', kind: 'webdav'),
      ];
      final pools = [
        const PoolRefInfo(
          id: 'p1',
          name: 'Main Pool',
          remoteIds: ['r1'],
          replicationFactor: 1,
          encrypted: true,
        ),
      ];

      Set<String>? exportedRemotes;
      Set<String>? exportedPools;
      bool? exportedBookmarks;
      bool? exportedPrefs;
      ConfigExportOutcome? outcome;

      await tester.pumpWidget(
        _wrapL10n(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                outcome = await showDialog<ConfigExportOutcome>(
                  context: ctx,
                  builder: (_) => ConfigExportDialog(
                    remotesOverride: remotes,
                    poolsOverride: pools,
                    bookmarksCountOverride: 2,
                    preferencesCountOverride: 5,
                    exportBundleFn: ({
                      required selectedRemoteIds,
                      required selectedPoolIds,
                      required includeBookmarks,
                      required includePreferences,
                      required password,
                    }) async {
                      exportedRemotes = selectedRemoteIds;
                      exportedPools = selectedPoolIds;
                      exportedBookmarks = includeBookmarks;
                      exportedPrefs = includePreferences;
                      return ConfigExportResult(
                        payload: '{"ok":true}',
                        encrypted: password.isNotEmpty,
                        suggestedFilename: password.isNotEmpty
                            ? 'filemanager_backup.fmbak'
                            : 'filemanager_config.json',
                        remotesCount: selectedRemoteIds.length,
                        poolsCount: selectedPoolIds.length,
                        bookmarksCount: includeBookmarks ? 2 : 0,
                        preferencesCount: includePreferences ? 5 : 0,
                      );
                    },
                    canUseSystemAuthFn: () async => true,
                    authenticateSystemFn: (reason) async => true,
                    saveFileFn: (name, payload, encrypted) async => '/tmp/$name',
                  ),
                );
              },
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      // All 4 sections default checked; r1 is locked because Main Pool uses it.
      CheckboxListTile remoteTile(String id) => tester.widget<CheckboxListTile>(
            find.byKey(ValueKey('config_remote_cb_$id')),
          );
      CheckboxListTile poolTile(String id) => tester.widget<CheckboxListTile>(
            find.byKey(ValueKey('config_pool_cb_$id')),
          );
      FilledButton fileBtn() => tester.widget<FilledButton>(
            find.byKey(const ValueKey('config_export_file_btn')),
          );

      expect(remoteTile('r1').value, isTrue);
      expect(remoteTile('r1').onChanged, isNull); // locked!
      expect(find.text('Required by pool: Main Pool'), findsOneWidget);
      expect(remoteTile('r2').value, isTrue);
      expect(remoteTile('r2').onChanged, isNotNull);
      expect(poolTile('p1').value, isTrue);

      // Export button disabled while password is empty.
      expect(fileBtn().onPressed, isNull);
      expect(
        find.text(
          'Setting an encryption password is required when exporting remote connections or storage pools.',
        ),
        findsOneWidget,
      );

      // Tapping locked remote r1 keeps it checked.
      await tester.ensureVisible(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.tap(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.pump();
      expect(remoteTile('r1').value, isTrue);

      // Uncheck Main Pool -> r1 immediately unlocks!
      await tester.ensureVisible(find.byKey(const ValueKey('config_pool_cb_p1')));
      await tester.tap(find.byKey(const ValueKey('config_pool_cb_p1')));
      await tester.pump();
      expect(poolTile('p1').value, isFalse);
      expect(remoteTile('r1').onChanged, isNotNull);

      // Uncheck r1 & r2 -> password is now optional -> Save .json enabled!
      await tester.ensureVisible(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.tap(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.ensureVisible(find.byKey(const ValueKey('config_remote_cb_r2')));
      await tester.tap(find.byKey(const ValueKey('config_remote_cb_r2')));
      await tester.pump();
      expect(fileBtn().onPressed, isNotNull);

      // Re-check Main Pool -> automatically re-checks AND locks r1, requiring password again!
      await tester.ensureVisible(find.byKey(const ValueKey('config_pool_cb_p1')));
      await tester.tap(find.byKey(const ValueKey('config_pool_cb_p1')));
      await tester.pump();
      expect(poolTile('p1').value, isTrue);
      expect(remoteTile('r1').value, isTrue);
      expect(remoteTile('r1').onChanged, isNull);
      expect(fileBtn().onPressed, isNull);

      // Enter matching password -> export enabled & succeeds.
      await tester.ensureVisible(find.byKey(const ValueKey('config_export_password')));
      await tester.enterText(
        find.byKey(const ValueKey('config_export_password')),
        'secret-pw',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('config_export_confirm_password')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('config_export_confirm_password')),
        'secret-pw',
      );
      await tester.pump();
      expect(fileBtn().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('config_export_file_btn')));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.method, ConfigExportMethod.saveFile);
      expect(exportedRemotes, {'r1'});
      expect(exportedPools, {'p1'});
      expect(exportedBookmarks, isTrue);
      expect(exportedPrefs, isTrue);
    });

    testWidgets('ConfigExportDialog enforces system auth on remote/pool export and skips it for bookmarks/settings only', (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final remotes = [_remote(id: 'r1', name: 'Pool Node S3')];
      var allowAuth = false;
      final authPrompts = <String>[];
      var exportCalls = 0;
      ConfigExportOutcome? outcome;

      await tester.pumpWidget(
        _wrapL10n(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                outcome = await showDialog<ConfigExportOutcome>(
                  context: ctx,
                  builder: (_) => ConfigExportDialog(
                    remotesOverride: remotes,
                    poolsOverride: const [],
                    bookmarksCountOverride: 1,
                    preferencesCountOverride: 2,
                    canUseSystemAuthFn: () async => true,
                    authenticateSystemFn: (reason) async {
                      authPrompts.add(reason);
                      return allowAuth;
                    },
                    exportBundleFn: ({
                      required selectedRemoteIds,
                      required selectedPoolIds,
                      required includeBookmarks,
                      required includePreferences,
                      required password,
                    }) async {
                      exportCalls += 1;
                      final hasPw = password.isNotEmpty;
                      return ConfigExportResult(
                        payload: 'mock-payload',
                        encrypted: hasPw,
                        suggestedFilename:
                            hasPw ? 'filemanager-config.fmbak' : 'filemanager-config.json',
                        remotesCount: selectedRemoteIds.length,
                        poolsCount: selectedPoolIds.length,
                        bookmarksCount: includeBookmarks ? 1 : 0,
                        preferencesCount: includePreferences ? 2 : 0,
                      );
                    },
                    saveFileFn: (name, payload, encrypted) async => '/tmp/$name',
                  ),
                );
              },
              child: const Text('Open Auth Test'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Auth Test'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('config_export_password')));
      await tester.enterText(
        find.byKey(const ValueKey('config_export_password')),
        'secret-pw',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('config_export_confirm_password')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('config_export_confirm_password')),
        'secret-pw',
      );
      await tester.pump();

      // Denied / cancelled system auth aborts export without invoking exportBundleFn.
      await tester.tap(find.byKey(const ValueKey('config_export_file_btn')));
      await tester.pumpAndSettle();
      expect(authPrompts, hasLength(1));
      expect(authPrompts.single, isNotEmpty);
      expect(exportCalls, 0);
      expect(outcome, isNull);
      expect(
        find.text('System authentication was cancelled or failed. Export aborted.'),
        findsOneWidget,
      );

      // Retrying with approved system auth succeeds.
      allowAuth = true;
      await tester.tap(find.byKey(const ValueKey('config_export_file_btn')));
      await tester.pumpAndSettle();
      expect(authPrompts, hasLength(2));
      expect(exportCalls, 1);
      expect(outcome, isNotNull);
      expect(outcome!.method, ConfigExportMethod.saveFile);

      // Re-open and uncheck remote r1 -> only bookmarks/settings exported, no system auth.
      outcome = null;
      await tester.tap(find.text('Open Auth Test'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.tap(find.byKey(const ValueKey('config_remote_cb_r1')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('config_export_file_btn')));
      await tester.pumpAndSettle();
      expect(authPrompts, hasLength(2));
      expect(exportCalls, 2);
      expect(outcome, isNotNull);
    });

    testWidgets('ConfigImportDialog decrypts bundle into selective picker with pool dependency lock', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final r1 = _remote(id: 'r1', name: 'Imported S3');
      final p1 = _poolConfig(id: 'p1', name: 'Imported Pool', remoteIds: ['r1']);
      const bm = BookmarkDto(id: 'b1', name: 'Work', root: '/tmp', path: 'work');
      final bundleText = ConfigMigrationService.encodeSelectiveBundle(
        remotes: [r1],
        pools: [p1],
        bookmarks: const [bm],
        preferences: const {'app.language': 'zh'},
        includeBookmarks: true,
        includePreferences: true,
        password: 'pw123',
        encryptFn: _mockEncrypt,
      ).payload;

      ConfigImportResult? importRes;
      await tester.pumpWidget(
        _wrapL10n(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                importRes = await showDialog<ConfigImportResult>(
                  context: ctx,
                  builder: (_) => ConfigImportDialog(
                    decryptFn: _mockDecrypt,
                    applyImportFn: ({
                      required bundle,
                      required selectedRemoteIds,
                      required selectedPoolIds,
                      required includeBookmarks,
                      required includePreferences,
                    }) async =>
                        ConfigImportResult(
                      remotes: selectedRemoteIds.length,
                      pools: selectedPoolIds.length,
                      bookmarks: includeBookmarks ? 1 : 0,
                      preferences: includePreferences ? 1 : 0,
                    ),
                  ),
                );
              },
              child: const Text('Open Import'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Import'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('config_import_content')),
        bundleText,
      );
      await tester.enterText(
        find.byKey(const ValueKey('config_import_password')),
        'pw123',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('config_import_parse_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Select Items to Import'), findsOneWidget);
      final r1Tile = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('config_remote_cb_r1')),
      );
      expect(r1Tile.value, isTrue);
      expect(r1Tile.onChanged, isNull); // locked by Imported Pool

      await tester.tap(find.byKey(const ValueKey('config_import_confirm_btn')));
      await tester.pumpAndSettle();

      expect(importRes, isNotNull);
      expect(importRes!.remotes, 1);
      expect(importRes!.pools, 1);
      expect(importRes!.bookmarks, 1);
      expect(importRes!.preferences, 1);
    });
  });

  group('RemotesPage & SnackBar fixes', () {
    testWidgets('RemotesPage no longer exposes standalone import/export actions', (tester) async {
      await tester.pumpWidget(_wrapL10n(const RemotesPage()));
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('Export Connections…'), findsNothing);
      expect(find.text('Import Connections…'), findsNothing);
      expect(find.text('Add Remote Storage'), findsOneWidget);
    });

    testWidgets('Action SnackBar with persist: false auto-dismisses after duration (RecentPage pattern)', (tester) async {
      await tester.pumpWidget(
        _wrapL10n(
          Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    persist: false,
                    duration: const Duration(seconds: 4),
                    content: const Text('Cleared 3 recent locations'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () {},
                    ),
                  ),
                );
              },
              child: const Text('Show Undo Bar'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Undo Bar'));
      await tester.pumpAndSettle();
      expect(find.text('Cleared 3 recent locations'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Cleared 3 recent locations'), findsNothing);

      // Smoke-instantiate RecentPage widget to verify it mounts without exception.
      await tester.pumpWidget(_wrapL10n(const RecentPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Desktop and Mobile menu order parity', () {
    testWidgets('DesktopSidebarShell expanded & collapsed rail follow unified 1:1 menu order', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrapL10n(
          DesktopSidebarShell(
            remotes: [_remote(id: 'r1', name: 'Office NAS')],
            bookmarks: const [
              BookmarkDto(id: 'bm1', name: 'Project Docs', root: '/tmp', path: 'docs'),
            ],
            history: const [],
            trashCount: 1,
            activeTaskCount: 1,
            diskSpace: null,
            themeMode: ThemeMode.system,
            onRefreshMetadata: () {},
            onOpenGlobalSearch: ({root, relPath, onNavigate}) async {},
            workspaceOverride: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expanded sidebar order:
      // Local (with Gallery, Recycle Bin) -> Remotes -> Storage Pools -> Privacy Space -> Favorites -> Transfer & Sync (Sync, LAN, Photo Backup, Offline Files, Tasks) -> Settings
      final orderedExpandedLabels = [
        'LOCAL FILES',
        'Gallery',
        'Recycle Bin',
        'REMOTES',
        'STORAGE POOLS',
        'PRIVACY SPACE',
        'FAVORITES',
        'Folder Sync',
        'LAN Transfer',
        'Photo Backup',
        'Offline Files',
        'Tasks',
        'Settings',
      ];
      double prevY = -1;
      for (final label in orderedExpandedLabels) {
        final y = tester.getTopLeft(find.text(label).first).dy;
        expect(y, greaterThan(prevY), reason: '$label should appear below previous entry');
        prevY = y;
      }

      // Folding LOCAL FILES hides both Gallery and Recycle Bin, proving both are children of Local Files.
      await tester.tap(find.byKey(const ValueKey('sidebar_group_local')));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsNothing);
      expect(find.text('Recycle Bin'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar_group_local')));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Recycle Bin'), findsOneWidget);

      // Collapse to 52px rail and verify only top-level menus appear in unified order.
      await tester.tap(find.byKey(const ValueKey('sidebar_collapse_btn')));
      await tester.pumpAndSettle();

      final orderedRailTooltips = [
        'Local Files',
        'Remotes',
        'Storage Pools',
        'Privacy Space',
        'Favorites',
        'Transfer & Sync',
        'Settings',
      ];
      double prevRailY = -1;
      for (final tip in orderedRailTooltips) {
        final y = tester.getTopLeft(find.byTooltip(tip).first).dy;
        expect(y, greaterThan(prevRailY), reason: 'Collapsed rail tooltip "$tip" out of order');
        prevRailY = y;
      }
      for (final subTip in const [
        'Gallery',
        'Recycle Bin',
        'Folder Sync',
        'LAN Transfer',
        'Photo Backup',
        'Offline Files',
        'Tasks',
      ]) {
        expect(find.byTooltip(subTip), findsNothing);
      }

      // Tapping Transfer & Sync on collapsed rail opens the transfer flyout menu.
      await tester.tap(find.byTooltip('Transfer & Sync'));
      await tester.pumpAndSettle();
      expect(find.text('Folder Sync'), findsOneWidget);
      expect(find.text('Tasks (1)'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('Mobile HomePage non-iOS Favorites tab renders Favorites and File Categories, and Transfer tab follows unified order', (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.android;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);
      tester.view.physicalSize = const Size(420, 960);
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

      await tester.tap(find.byKey(const ValueKey('home_nav_discover')));
      await tester.pumpAndSettle();
      expect(find.text('收藏夹'), findsNothing);
      expect(find.byKey(const ValueKey('home_manage_bookmarks_btn')), findsOneWidget);
      expect(find.text('文件类型'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home_nav_tools')));
      await tester.pumpAndSettle();
      final transferOrder = [
        '目录同步',
        '局域网传输',
        '相册备份',
        '离线文件',
        '任务队列',
      ];
      double prevOrderScore = -1;
      for (final label in transferOrder) {
        final pos = tester.getTopLeft(find.text(label));
        final orderScore = pos.dy * 10000 + pos.dx;
        expect(
          orderScore,
          greaterThan(prevOrderScore),
          reason: '$label out of reading order in Transfer tab (pos=$pos)',
        );
        prevOrderScore = orderScore;
      }
    });
  });
}
