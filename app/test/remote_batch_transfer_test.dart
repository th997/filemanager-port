import 'dart:convert';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/remote_batch_transfer_dialogs.dart';
import 'package:filemanager/src/rust/api/remotes.dart';
import 'package:filemanager/src/services/platform_capabilities.dart';
import 'package:filemanager/src/services/remote_transfer_service.dart';
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
    'format': RemoteTransferService.envelopeFormat,
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

RemoteConfigDto _s3Remote({
  String id = 's3-prod',
  String name = 'Prod S3',
}) =>
    RemoteConfigDto(
      id: id,
      name: name,
      kind: 's3',
      endpoint: 'https://s3.example.com',
      bucket: 'my-bucket',
      region: 'us-east-1',
      accessKeyId: 'AKIAEXAMPLE',
      secretAccessKey: 'super-secret-key',
      host: null,
      port: null,
      username: null,
      password: null,
      privateKey: null,
      passphrase: null,
      rootPath: '/data',
      pathStyle: true,
    );

RemoteConfigDto _sftpRemote({
  String id = 'sftp-nas',
  String name = 'Office NAS',
}) =>
    RemoteConfigDto(
      id: id,
      name: name,
      kind: 'sftp',
      endpoint: null,
      bucket: null,
      region: null,
      accessKeyId: null,
      secretAccessKey: null,
      host: '192.168.10.20',
      port: 2222,
      username: 'ops',
      password: 'sftp-login-secret',
      privateKey:
          '-----BEGIN OPENSSH PRIVATE KEY-----\nABC\n-----END OPENSSH PRIVATE KEY-----',
      passphrase: 'key-passphrase',
      rootPath: '/srv/files',
      pathStyle: false,
    );

RemoteConfigDto _unreadableRemote({
  String id = 'broken-id',
  String name = 'Broken Shell',
}) =>
    RemoteConfigDto(
      id: id,
      name: name,
      kind: 'webdav',
      pathStyle: false,
    );

Widget _wrapWithL10n(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('RemoteTransferService', () {
    test('rejects empty selection, unreadable items, empty or short passwords', () {
      expect(
        () => RemoteTransferService.encryptRemotesBundle(
          const [],
          password: 'password123',
          encryptFn: _mockEncrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.noRemotesSelected,
          ),
        ),
      );

      expect(
        () => RemoteTransferService.encryptRemotesBundle(
          [_unreadableRemote()],
          password: 'password123',
          encryptFn: _mockEncrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.noRemotesSelected,
          ),
        ),
      );

      expect(
        () => RemoteTransferService.encryptRemotesBundle(
          [_s3Remote()],
          password: '',
          encryptFn: _mockEncrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.emptyPassword,
          ),
        ),
      );

      expect(
        () => RemoteTransferService.encryptRemotesBundle(
          [_s3Remote()],
          password: '12345',
          encryptFn: _mockEncrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.passwordTooShort,
          ),
        ),
      );
    });

    test('round-trips S3 and SFTP configs including credentials cleanly', () {
      final s3 = _s3Remote();
      final sftp = _sftpRemote();
      final unreadable = _unreadableRemote();

      final envelope = RemoteTransferService.encryptRemotesBundle(
        [s3, sftp, unreadable],
        password: 'vault-transfer-secret',
        encryptFn: _mockEncrypt,
        now: DateTime.utc(2026, 11, 25, 12, 0),
      );

      expect(RemoteTransferService.looksLikeEncryptedEnvelope(envelope), isTrue);
      expect(envelope.contains('super-secret-key'), isFalse);
      expect(envelope.contains('sftp-login-secret'), isFalse);

      final decoded = RemoteTransferService.decryptRemotesBundle(
        envelope,
        password: 'vault-transfer-secret',
        decryptFn: _mockDecrypt,
      );

      expect(decoded.sourceType, RemoteTransferService.bundleType);
      expect(decoded.remotes.length, 2);
      expect(decoded.remotes[0], s3);
      expect(decoded.remotes[1], sftp);
    });

    test('decrypts Settings v2 migration bundle containing remotes', () {
      final v2Payload = jsonEncode({
        'version': 2,
        'exportedAt': '2026-11-25T08:00:00Z',
        'remotes': [
          {
            'id': 'webdav-1',
            'name': 'Nextcloud',
            'kind': 'webdav',
            'endpoint': 'https://cloud.example.com/dav',
            'username': 'alice',
            'password': 'dav-password',
            'rootPath': '/',
            'pathStyle': false,
          },
        ],
        'bookmarks': [],
        'preferences': {},
      });
      final envelope = _mockEncrypt(
        plaintextJson: v2Payload,
        password: 'migrate-password',
      );

      final decoded = RemoteTransferService.decryptRemotesBundle(
        envelope,
        password: 'migrate-password',
        decryptFn: _mockDecrypt,
      );

      expect(decoded.sourceType, 'fp_migration_v2');
      expect(decoded.remotes.length, 1);
      expect(decoded.remotes.first.id, 'webdav-1');
      expect(decoded.remotes.first.password, 'dav-password');
    });

    test('rejects plaintext JSON, invalid JSON, wrong password, and empty bundles', () {
      expect(
        () => RemoteTransferService.decryptRemotesBundle(
          'not json at all',
          password: 'password123',
          decryptFn: _mockDecrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.invalidFormat,
          ),
        ),
      );

      expect(
        () => RemoteTransferService.decryptRemotesBundle(
          jsonEncode([
            {'id': 'r1', 'name': 'Plain', 'kind': 'sftp', 'host': '10.0.0.1'},
          ]),
          password: 'password123',
          decryptFn: _mockDecrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.notEncrypted,
          ),
        ),
      );

      final envelope = RemoteTransferService.encryptRemotesBundle(
        [_s3Remote()],
        password: 'right-password',
        encryptFn: _mockEncrypt,
      );

      expect(
        () => RemoteTransferService.decryptRemotesBundle(
          envelope,
          password: 'wrong-password',
          decryptFn: _mockDecrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.wrongPasswordOrCorrupted,
          ),
        ),
      );

      final emptyEnvelope = _mockEncrypt(
        plaintextJson: jsonEncode({'type': 'fm_remotes_bundle', 'remotes': []}),
        password: 'right-password',
      );
      expect(
        () => RemoteTransferService.decryptRemotesBundle(
          emptyEnvelope,
          password: 'right-password',
          decryptFn: _mockDecrypt,
        ),
        throwsA(
          isA<RemoteBundleException>().having(
            (e) => e.code,
            'code',
            RemoteBundleErrorCode.emptyBundle,
          ),
        ),
      );
    });

    test('buildImportPlan handles skip, overwrite, keepBoth with chained collisions', () {
      final existing = [
        _s3Remote(id: 's3-prod', name: 'Prod S3'),
        _s3Remote(id: 's3-prod_copy', name: 'Prod S3 (2)'),
      ];
      final incoming = [
        _s3Remote(id: 's3-prod', name: 'Prod S3'),
        _sftpRemote(id: 'sftp-nas', name: 'Office NAS'),
      ];

      final skipPlan = RemoteTransferService.buildImportPlan(
        incoming: incoming,
        existing: existing,
        strategy: RemoteImportConflictStrategy.skip,
      );
      expect(skipPlan[0].action, RemoteImportItemAction.skip);
      expect(skipPlan[0].hasConflict, isTrue);
      expect(skipPlan[1].action, RemoteImportItemAction.create);
      expect(skipPlan[1].hasConflict, isFalse);

      final overwritePlan = RemoteTransferService.buildImportPlan(
        incoming: incoming,
        existing: existing,
        strategy: RemoteImportConflictStrategy.overwrite,
      );
      expect(overwritePlan[0].action, RemoteImportItemAction.overwrite);
      expect(overwritePlan[0].resolved.id, 's3-prod');

      final keepBothPlan = RemoteTransferService.buildImportPlan(
        incoming: incoming,
        existing: existing,
        strategy: RemoteImportConflictStrategy.keepBoth,
      );
      expect(keepBothPlan[0].action, RemoteImportItemAction.duplicate);
      expect(keepBothPlan[0].resolved.id, 's3-prod_copy_2');
      expect(keepBothPlan[0].resolved.name, 'Prod S3 (3)');
      expect(keepBothPlan[1].action, RemoteImportItemAction.create);
    });

    test('executeImportPlan counts added, overwritten, duplicated, skipped and partial failures', () async {
      final plan = [
        RemoteImportPlanItem(
          original: _s3Remote(id: 'new-1', name: 'New One'),
          resolved: _s3Remote(id: 'new-1', name: 'New One'),
          hasConflict: false,
          action: RemoteImportItemAction.create,
        ),
        RemoteImportPlanItem(
          original: _sftpRemote(id: 'existing-1', name: 'Existing One'),
          resolved: _sftpRemote(id: 'existing-1', name: 'Existing One'),
          hasConflict: true,
          action: RemoteImportItemAction.overwrite,
        ),
        RemoteImportPlanItem(
          original: _s3Remote(id: 'dup-orig', name: 'Dup'),
          resolved: _s3Remote(id: 'dup-orig_copy', name: 'Dup (2)'),
          hasConflict: true,
          action: RemoteImportItemAction.duplicate,
        ),
        RemoteImportPlanItem(
          original: _s3Remote(id: 'skip-1', name: 'Skipped'),
          resolved: _s3Remote(id: 'skip-1', name: 'Skipped'),
          hasConflict: true,
          action: RemoteImportItemAction.skip,
        ),
      ];

      List<RemoteConfigDto>? captured;
      final res = await RemoteTransferService.executeImportPlan(
        plan: plan,
        saveBatchFn: (configs) async {
          captured = configs;
          return (
            saved: 2,
            failedIds: ['existing-1'],
            failures: ['Existing One'],
          );
        },
      );

      expect(captured!.length, 3);
      expect(res.added, 1);
      expect(res.overwritten, 0);
      expect(res.duplicated, 1);
      expect(res.skipped, 1);
      expect(res.totalImported, 2);
      expect(res.failures, ['Existing One']);
    });
  });

  group('RemoteBatchExportDialog widget', () {
    testWidgets('enforces password confirmation and exports only selected readable remotes', (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);

      String? savedName;
      String? savedPayload;
      RemoteBatchExportOutcome? dialogOutcome;

      final remotes = [
        _s3Remote(),
        _sftpRemote(),
        _unreadableRemote(),
      ];

      await tester.pumpWidget(
        _wrapWithL10n(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogOutcome = await showDialog<RemoteBatchExportOutcome>(
                  context: context,
                  builder: (_) => RemoteBatchExportDialog(
                    remotes: remotes,
                    encryptFn: _mockEncrypt,
                    saveFileFn: (name, content) async {
                      savedName = name;
                      savedPayload = content;
                      return '/tmp/$name';
                    },
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

      expect(find.text('Selected 2 / 2'), findsOneWidget);
      expect(find.text('Unreadable credentials (cannot be exported)'), findsOneWidget);

      // Save button is disabled until a matching 6+ char password is set.
      FilledButton saveBtn() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(saveBtn().onPressed, isNull);

      // Deselect Office NAS so only Prod S3 is exported.
      await tester.tap(find.text('Office NAS'));
      await tester.pump();
      expect(find.text('Selected 1 / 2'), findsOneWidget);

      // Short password triggers inline warning and keeps button disabled.
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_password')),
        '123',
      );
      await tester.pump();
      expect(find.text('Password must be at least 6 characters.'), findsOneWidget);
      expect(saveBtn().onPressed, isNull);

      // Matching 6+ char password vs mismatched confirmation.
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_password')),
        'export-pass-99',
      );
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_confirm_password')),
        'mismatch',
      );
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(saveBtn().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_confirm_password')),
        'export-pass-99',
      );
      await tester.pump();
      expect(saveBtn().onPressed, isNotNull);

      await tester.tap(find.text('Save Encrypted File'));
      await tester.pumpAndSettle();

      expect(savedName, isNotNull);
      expect(savedName!.endsWith('.fmremotes'), isTrue);
      expect(dialogOutcome, isNotNull);
      expect(dialogOutcome!.count, 1);
      expect(dialogOutcome!.method, RemoteBatchExportMethod.saveFile);

      final decoded = RemoteTransferService.decryptRemotesBundle(
        savedPayload!,
        password: 'export-pass-99',
        decryptFn: _mockDecrypt,
      );
      expect(decoded.remotes.length, 1);
      expect(decoded.remotes.single.id, 's3-prod');
    });

    testWidgets('uses share sheet button on mobile and recovers if desktop save is cancelled', (tester) async {
      PlatformCapabilities.debugPlatformOverride = HostPlatform.macos;
      addTearDown(() => PlatformCapabilities.debugPlatformOverride = null);

      RemoteBatchExportOutcome? cancelOutcome;
      await tester.pumpWidget(
        _wrapWithL10n(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                cancelOutcome = await showDialog<RemoteBatchExportOutcome>(
                  context: context,
                  builder: (_) => RemoteBatchExportDialog(
                    remotes: [_s3Remote()],
                    encryptFn: _mockEncrypt,
                    saveFileFn: (_, _) async => null,
                  ),
                );
              },
              child: const Text('Open Cancel Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Cancel Export'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_password')),
        'desktop-secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_confirm_password')),
        'desktop-secret',
      );
      await tester.pump();

      await tester.tap(find.text('Save Encrypted File'));
      await tester.pumpAndSettle();

      // Cancelling OS save sheet keeps dialog open instead of closing with failure.
      expect(find.text('Batch Export Connections'), findsOneWidget);
      expect(cancelOutcome, isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      PlatformCapabilities.debugPlatformOverride = HostPlatform.ios;

      String? sharedFileName;
      RemoteBatchExportOutcome? outcome;

      await tester.pumpWidget(
        _wrapWithL10n(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                outcome = await showDialog<RemoteBatchExportOutcome>(
                  context: context,
                  builder: (_) => RemoteBatchExportDialog(
                    remotes: [_s3Remote()],
                    encryptFn: _mockEncrypt,
                    shareFileFn: (name, content, origin) async {
                      sharedFileName = name;
                    },
                  ),
                );
              },
              child: const Text('Open Mobile Export'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Mobile Export'));
      await tester.pumpAndSettle();

      expect(find.text('Export / Share File'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_password')),
        'mobile-secret',
      );
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_export_confirm_password')),
        'mobile-secret',
      );
      await tester.pump();

      await tester.tap(find.text('Export / Share File'));
      await tester.pumpAndSettle();

      expect(sharedFileName, isNotNull);
      expect(outcome!.method, RemoteBatchExportMethod.shareFile);
      expect(outcome!.count, 1);
    });
  });

  group('RemoteBatchImportDialog widget', () {
    testWidgets('rejects plaintext JSON and wrong password, then previews and imports with conflict resolution', (tester) async {
      final s3 = _s3Remote(id: 's3-prod', name: 'Prod S3');
      final sftp = _sftpRemote(id: 'sftp-nas', name: 'Office NAS');
      final envelope = RemoteTransferService.encryptRemotesBundle(
        [s3, sftp],
        password: 'correct-bundle-pass',
        encryptFn: _mockEncrypt,
      );

      var savedBatches = <List<RemoteConfigDto>>[];
      RemoteBatchImportResult? importResult;

      await tester.pumpWidget(
        _wrapWithL10n(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                importResult = await showDialog<RemoteBatchImportResult>(
                  context: context,
                  builder: (_) => RemoteBatchImportDialog(
                    existingRemotes: [s3],
                    decryptFn: _mockDecrypt,
                    readClipboardFn: () async => null,
                    pickFileFn: () async => (
                      name: 'team.fmremotes',
                      content: envelope,
                      sizeBytes: envelope.length,
                    ),
                    saveBatchFn: (configs) async {
                      savedBatches.add(configs);
                      return (
                        saved: configs.length,
                        failedIds: const <String>[],
                        failures: const <String>[],
                      );
                    },
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

      // Plaintext JSON must be rejected.
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_import_paste')),
        jsonEncode([{'id': 'x', 'name': 'Plain', 'kind': 's3'}]),
      );
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_import_password')),
        'any-pass',
      );
      await tester.pump();
      await tester.tap(find.text('Decrypt & Preview'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Unencrypted plaintext data is not allowed. Please select a password-encrypted backup.',
        ),
        findsOneWidget,
      );

      // Choose encrypted file and try wrong password first.
      await tester.tap(find.text('Choose Backup File'));
      await tester.pumpAndSettle();
      expect(find.text('Selected file: team.fmremotes'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_import_password')),
        'wrong-pass',
      );
      await tester.pump();
      await tester.tap(find.text('Decrypt & Preview'));
      await tester.pumpAndSettle();
      expect(
        find.text('Incorrect password or corrupted backup file.'),
        findsOneWidget,
      );

      // Correct password enters Step 2 preview.
      await tester.enterText(
        find.byKey(const ValueKey('remote_batch_import_password')),
        'correct-bundle-pass',
      );
      await tester.pump();
      await tester.tap(find.text('Decrypt & Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Decrypted 2 connection(s)'), findsOneWidget);
      expect(find.text('Exists'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      // Default strategy is Skip -> only Office NAS is actionable (1).
      expect(find.text('Import (1)'), findsOneWidget);

      // Navigate Back and confirm loaded file persists, then decrypt again.
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Selected file: team.fmremotes'), findsOneWidget);
      await tester.tap(find.text('Decrypt & Preview'));
      await tester.pumpAndSettle();

      // Switch conflict strategy to Keep Both -> both actionable (2) and copy name shown.
      await tester.tap(find.text('Keep Both'));
      await tester.pumpAndSettle();
      expect(find.text('Import (2)'), findsOneWidget);
      expect(find.textContaining('Prod S3 (2)'), findsOneWidget);

      await tester.tap(find.text('Import (2)'));
      await tester.pumpAndSettle();

      expect(importResult, isNotNull);
      expect(importResult!.added, 1);
      expect(importResult!.duplicated, 1);
      expect(importResult!.overwritten, 0);
      expect(importResult!.skipped, 0);
      expect(savedBatches.single.length, 2);
      expect(savedBatches.single[0].id, 's3-prod_copy');
      expect(savedBatches.single[0].name, 'Prod S3 (2)');
      expect(savedBatches.single[1].id, 'sftp-nas');
    });
  });
}
