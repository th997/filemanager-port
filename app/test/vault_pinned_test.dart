import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/vault_dialogs.dart';
import 'package:filemanager/src/rust/api/vault.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/vault_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    PreferencesService.instance
        .setString(PreferencesService.prefPinnedVaults, '[]');
  });

  group('VaultService always-visible persistence', () {
    test('persists independent always-visible states per privacy folder', () {
      final svc = VaultService.instance;

      expect(svc.pinnedVaults, isEmpty);
      expect(svc.isAlwaysVisible('v1'), isFalse);
      expect(svc.isAlwaysVisible('v2'), isFalse);

      svc.setAlwaysVisible(vaultId: 'v1', name: 'WorkDocs', alwaysVisible: true);
      expect(svc.isAlwaysVisible('v1'), isTrue);
      expect(svc.isAlwaysVisible('v2'), isFalse);
      expect(svc.lockedPinnedVaults, [
        const PinnedVaultEntry(id: 'v1', name: 'WorkDocs'),
      ]);

      svc.setAlwaysVisible(vaultId: 'v2', name: 'Photos', alwaysVisible: true);
      expect(svc.isAlwaysVisible('v1'), isTrue);
      expect(svc.isAlwaysVisible('v2'), isTrue);
      expect(svc.pinnedVaults.length, 2);

      // Disabling one does not affect the other.
      svc.setAlwaysVisible(vaultId: 'v1', name: 'WorkDocs', alwaysVisible: false);
      expect(svc.isAlwaysVisible('v1'), isFalse);
      expect(svc.isAlwaysVisible('v2'), isTrue);
      expect(svc.lockedPinnedVaults, [
        const PinnedVaultEntry(id: 'v2', name: 'Photos'),
      ]);

      svc.unpinVault('v2');
      expect(svc.pinnedVaults, isEmpty);
    });

    test('degrades gracefully when persisted JSON is corrupt', () {
      PreferencesService.instance
          .setString(PreferencesService.prefPinnedVaults, '{not-valid-json');
      expect(VaultService.instance.pinnedVaults, isEmpty);
      expect(VaultService.instance.lockedPinnedVaults, isEmpty);
    });
  });

  group('Vault pinned UI controls', () {
    Widget wrapZh(Widget child) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );
    }

    testWidgets('VaultInfoDialog toggles per-vault always-visible switch',
        (tester) async {
      const vault = UnlockedVaultDto(
        id: 'v-pin-ui-1',
        name: 'Personal',
        dirPath: '/tmp/v-pin-ui-1',
        cipher: 'aes128gcm',
        authMode: 'password',
        createdAtMs: 1700000000000,
      );

      await tester.pumpWidget(
        wrapZh(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => VaultInfoDialog(
                  vault: vault,
                  onGetStatsOverride: (_) async => VaultStatsDto(
                    fileCount: BigInt.from(1),
                    dirCount: BigInt.zero,
                    totalPlainBytes: BigInt.from(128),
                    diskBytes: BigInt.from(256),
                    orphanCount: BigInt.zero,
                    orphanBytes: BigInt.zero,
                  ),
                ),
              ),
              child: const Text('open-info'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-info'));
      await tester.pumpAndSettle();

      expect(find.text('常驻显示'), findsOneWidget);
      expect(VaultService.instance.isAlwaysVisible(vault.id), isFalse);

      await tester.tap(find.text('常驻显示'));
      await tester.pumpAndSettle();
      expect(VaultService.instance.isAlwaysVisible(vault.id), isTrue);

      await tester.tap(find.text('常驻显示'));
      await tester.pumpAndSettle();
      expect(VaultService.instance.isAlwaysVisible(vault.id), isFalse);
    });

    testWidgets('OpenVaultDialog pre-populates initialName cleanly',
        (tester) async {
      await tester.pumpWidget(
        wrapZh(
          const OpenVaultDialog(initialName: 'WorkDocs'),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'WorkDocs');
    });
  });
}
