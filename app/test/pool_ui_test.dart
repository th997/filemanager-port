import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/controllers/browser_pane_controller.dart';
import 'package:filemanager/src/dialogs/folder_picker_dialog.dart';
import 'package:filemanager/src/dialogs/pool_editor_dialog.dart';
import 'package:filemanager/src/pages/browser_workspace_page.dart';
import 'package:filemanager/src/pages/pool_dashboard_page.dart';
import 'package:filemanager/src/rust/api/pool.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/services/path_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pool:// URI helpers', () {
    test('isPoolRoot and poolIdFromRoot recognize pool and archive-in-pool roots', () {
      expect(isPoolRoot('pool://p1'), isTrue);
      expect(isPoolRoot('remote://r1'), isFalse);
      expect(poolIdFromRoot('pool://p1'), 'p1');
      expect(poolIdFromRoot('pool://p1/movies'), 'p1');
      expect(poolIdFromRoot('archive://pool://p2/backups/archive.zip'), 'p2');
      expect(poolIdFromRoot('vault://v1'), isNull);
    });

    test('parseJumpAddress resolves pool:// paths with id/name resolution', () {
      final byId = BrowserPaneController.parseJumpAddress(
        'pool://p1/movies/clip.mp4',
        currentRoot: '/',
        currentRelPath: '',
      );
      expect(byId, isNotNull);
      expect(byId!.root, 'pool://p1');
      expect(byId.relPath, 'movies/clip.mp4');

      final byName = BrowserPaneController.parseJumpAddress(
        'pool://MediaPool/docs',
        currentRoot: '/',
        currentRelPath: '',
        resolvePoolId: (idOrName) => idOrName == 'MediaPool' ? 'pool_42' : idOrName,
      );
      expect(byName, isNotNull);
      expect(byName!.root, 'pool://pool_42');
      expect(byName.relPath, 'docs');
    });

    test('deriveTabTitle preserves fallback title at pool root', () {
      expect(
        BrowserWorkspacePage.deriveTabTitle('pool://p1', '', 'Media Pool'),
        'Media Pool',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('pool://p1', 'movies/2026', 'Media Pool'),
        '2026',
      );
    });
  });

  group('PoolDashboardPage widget', () {
    Widget wrap(Widget child) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      );
    }

    testWidgets('shows empty state when no pools exist', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PoolDashboardPage(
            initialPoolsOverride: [],
            remotesOverride: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No storage pools configured'), findsOneWidget);
      expect(find.text('Create Storage Pool'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders capacity bars, degraded warning, and node statuses', (tester) async {
      const remotes = [
        RemoteConfigDto(
          id: 'rem-sftp',
          name: 'Hetzner Box',
          kind: 'sftp',
          pathStyle: false,
        ),
        RemoteConfigDto(
          id: 'rem-s3',
          name: 'AWS S3',
          kind: 's3',
          pathStyle: false,
        ),
      ];
      final pools = [
        PoolSummaryDto(
          id: 'p1',
          name: 'Hybrid 12-Node Pool',
          chunkSize: 16 * 1024 * 1024,
          replicationFactor: 2,
          encrypted: true,
          totalPhysicalQuota: BigInt.from(200) * BigInt.from(1024 * 1024 * 1024),
          effectiveLogicalCapacity: BigInt.from(100) * BigInt.from(1024 * 1024 * 1024),
          totalPhysicalUsed: BigInt.from(20) * BigInt.from(1024 * 1024 * 1024),
          logicalUsedBytes: BigInt.from(10) * BigInt.from(1024 * 1024 * 1024),
          fileCount: BigInt.from(42),
          dirCount: BigInt.from(5),
          degradedChunks: BigInt.from(3),
          pendingGcCount: BigInt.from(1),
          metaVersion: BigInt.from(9),
          dirty: false,
          nodes: [
            PoolNodeStatusDto(
              nodeId: 'n1',
              remoteId: 'rem-sftp',
              basePrefix: 'fm_pool',
              failureDomain: 'hetzner',
              quotaBytes: BigInt.from(100) * BigInt.from(1024 * 1024 * 1024),
              usedBytes: BigInt.from(12) * BigInt.from(1024 * 1024 * 1024),
              remoteFreeBytes:
                  BigInt.from(400) * BigInt.from(1024 * 1024 * 1024),
              remoteTotalBytes:
                  BigInt.from(500) * BigInt.from(1024 * 1024 * 1024),
              role: 'rw',
              isMetaBackup: true,
              healthScore: 0.95,
              avgLatencyMs: BigInt.from(42),
              circuitState: 'closed',
              lastCheckedMs: 1000,
            ),
            PoolNodeStatusDto(
              nodeId: 'n2',
              remoteId: 'rem-s3',
              basePrefix: '/',
              failureDomain: 'aws',
              quotaBytes: BigInt.from(100) * BigInt.from(1024 * 1024 * 1024),
              usedBytes: BigInt.from(8) * BigInt.from(1024 * 1024 * 1024),
              role: 'rw',
              isMetaBackup: true,
              healthScore: 0.88,
              avgLatencyMs: BigInt.from(85),
              circuitState: 'closed',
              lastCheckedMs: 1000,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        wrap(
          PoolDashboardPage(
            initialPoolsOverride: pools,
            remotesOverride: remotes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hybrid 12-Node Pool'), findsOneWidget);
      expect(find.text('Encrypted'), findsOneWidget);
      expect(find.text('Meta v9'), findsOneWidget);
      expect(find.text('2x Replicas'), findsOneWidget);
      expect(
        find.text('3 chunk(s) below 2 replicas — run Heal to restore redundancy'),
        findsOneWidget,
      );
      expect(find.text('Hetzner Box'), findsOneWidget);
      expect(find.text('Dir: /fm_pool'), findsOneWidget);
      expect(find.text('Free 400.00 GB / 500.00 GB'), findsOneWidget);
      expect(find.text('Pool used: 12.00 GB'), findsOneWidget);
      expect(find.text('12.00 GB / 100.00 GB'), findsNothing);
      expect(find.text('Health 95% · 42 ms · closed'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Pool used: 8.00 GB'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('AWS S3'), findsOneWidget);
      expect(find.text('hetzner · RW'), findsOneWidget);
      expect(find.text('aws · RW'), findsOneWidget);
      expect(find.text('Dir: /'), findsOneWidget);
      expect(find.text('Free space unavailable'), findsOneWidget);
      expect(find.text('Pool used: 8.00 GB'), findsOneWidget);

      // Tapping the replication chip opens Set Replication Factor dialog.
      await tester.scrollUntilVisible(
        find.text('2x Replicas'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('2x Replicas'));
      await tester.pumpAndSettle();
      expect(find.text('Set Replication Factor'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('PoolEditorDialog widget', () {
    testWidgets('validates fields and submits PoolConfigDto', (tester) async {
      PoolConfigDto? submitted;
      const remotes = [
        RemoteConfigDto(
          id: 'r1',
          name: 'Node One',
          kind: 'sftp',
          pathStyle: false,
        ),
        RemoteConfigDto(
          id: 'r2',
          name: 'Node Two',
          kind: 's3',
          pathStyle: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  submitted = await PoolEditorDialog.show(ctx, remotes: remotes);
                },
                child: const Text('Open Editor'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      // Submit with empty name -> stays open with validation message.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(PoolEditorDialog), findsOneWidget);

      // Enter pool name and select both nodes.
      await tester.enterText(find.byType(TextField).first, 'My Test Pool');
      await tester.tap(find.text('Node One (SFTP)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Node Two (S3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Node Two (S3)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.name, 'My Test Pool');
      expect(submitted!.nodes.length, 2);
      expect(submitted!.nodes.map((n) => n.remoteId), ['r1', 'r2']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'picks remote node directories including root and supports replication > 3',
        (tester) async {
      PoolConfigDto? submitted;
      const remotes = [
        RemoteConfigDto(id: 'r1', name: 'N1', kind: 'sftp', pathStyle: false),
        RemoteConfigDto(id: 'r2', name: 'N2', kind: 's3', pathStyle: false),
        RemoteConfigDto(id: 'r3', name: 'N3', kind: 'webdav', pathStyle: false),
        RemoteConfigDto(id: 'r4', name: 'N4', kind: 'smb', pathStyle: false),
      ];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  submitted = await PoolEditorDialog.show(
                    ctx,
                    remotes: remotes,
                    onPickNodeDirectory: (remote, currentPath) async {
                      if (remote.id == 'r1') return 'storage/pool_a';
                      if (remote.id == 'r2') return '';
                      return currentPath;
                    },
                  );
                },
                child: const Text('Open Editor 4'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Editor 4'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Four Replica Pool');

      // Select replication factor 4x.
      await tester.tap(find.text('2x'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4x').last);
      await tester.pumpAndSettle();

      for (final label in [
        'N1 (SFTP)',
        'N2 (S3)',
        'N3 (WEBDAV)',
        'N4 (SMB)',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      // Pick directory for N1 -> 'storage/pool_a' and N2 -> '/'.
      final folderButtons = find.byIcon(Icons.folder_open_outlined);
      expect(folderButtons, findsNWidgets(4));
      await tester.ensureVisible(folderButtons.at(0));
      await tester.pumpAndSettle();
      await tester.tap(folderButtons.at(0));
      await tester.pumpAndSettle();

      await tester.ensureVisible(folderButtons.at(1));
      await tester.pumpAndSettle();
      await tester.tap(folderButtons.at(1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.replicationFactor, 4);
      expect(submitted!.nodes.length, 4);
      expect(submitted!.nodes[0].basePrefix, 'storage/pool_a');
      expect(submitted!.nodes[1].basePrefix, '/');
      expect(submitted!.nodes[2].basePrefix, 'fm_pool');
      expect(tester.takeException(), isNull);
    });

    testWidgets('FolderPickerDialog with lockRoot hides quick targets and formats root path',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FolderPickerDialog(
              title: 'Choose Folder · NAS',
              initialRoot: 'remote://r1',
              initialPath: 'backups',
              lockRoot: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Choose Folder · NAS'), findsOneWidget);
      expect(find.text('/backups'), findsOneWidget);
      expect(find.byIcon(Icons.folder_special), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
