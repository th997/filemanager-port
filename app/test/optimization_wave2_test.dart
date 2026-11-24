import 'dart:convert';
import 'dart:typed_data';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/l10n/app_localizations_en.dart';
import 'package:filemanager/l10n/app_localizations_zh.dart';
import 'package:filemanager/src/pages/browser_workspace_page.dart';
import 'package:filemanager/src/pages/pdf_viewer_page.dart';
import 'package:filemanager/src/services/background_keepalive_service.dart';
import 'package:filemanager/src/services/error_text.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/vault_service.dart';
import 'package:filemanager/src/widgets/media_player/media_player_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _syntheticSimplePdf(String contentText) {
  final content = 'BT ($contentText) Tj ET';
  final objects = <String>[
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>\nendobj\n',
    '4 0 obj\n<< /Length ${content.length} >>\nstream\n$content\nendstream\nendobj\n',
  ];
  return Uint8List.fromList(latin1.encode('%PDF-1.4\n${objects.join()}%%EOF\n'));
}

void main() {
  group('BackgroundKeepAliveService ref-counting', () {
    test('starts on 0->1, updates on 1->2 and 2->1, stops on 1->0', () async {
      final calls = <({String method, Map<String, dynamic>? args})>[];
      final svc = BackgroundKeepAliveService(
        channelInvoker: (method, args) async {
          calls.add((method: method, args: args));
          return true;
        },
      );

      expect(svc.isActive, isFalse);
      await svc.acquire('t1', title: 'Upload A', detail: '10%');
      expect(svc.isActive, isTrue);
      expect(svc.activeCount, 1);
      expect(calls.length, 1);
      expect(calls.last.method, 'start');
      expect(calls.last.args?['title'], 'Upload A');

      await svc.acquire('t2', title: 'LAN Share', detail: 'Serving');
      expect(svc.activeCount, 2);
      expect(calls.length, 2);
      expect(calls.last.method, 'start');
      expect(calls.last.args?['title'], 'LAN Share');

      await svc.release('t2');
      expect(svc.isActive, isTrue);
      expect(svc.activeCount, 1);
      expect(calls.length, 3);
      expect(calls.last.method, 'start');
      expect(calls.last.args?['title'], 'Upload A');

      await svc.release('t1');
      expect(svc.isActive, isFalse);
      expect(svc.activeCount, 0);
      expect(calls.length, 4);
      expect(calls.last.method, 'stop');
    });

    test('runWithKeepAlive always releases even when action throws', () async {
      final calls = <String>[];
      final svc = BackgroundKeepAliveService(
        channelInvoker: (method, _) async {
          calls.add(method);
          return true;
        },
      );

      await expectLater(
        svc.runWithKeepAlive('sync:1', () async {
          expect(svc.isActive, isTrue);
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(svc.isActive, isFalse);
      expect(calls, ['start', 'stop']);
    });
  });

  group('PdfViewerPage text copy sheet', () {
    testWidgets('opens SelectableText sheet from pdf_copy_text_btn without full-doc raster',
        (tester) async {
      final bytes = _syntheticSimplePdf('Secret Memo Line 1');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PdfViewerPage(
            root: 'local',
            path: '/tmp/memo.pdf',
            fileName: 'memo.pdf',
            initialBytes: bytes,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final copyBtn = find.byKey(const ValueKey('pdf_copy_text_btn'));
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('Secret Memo Line 1'), findsOneWidget);
    });
  });

  group('Localized friendlyErrorText & detectErrorRecovery', () {
    test('localizes new backend error categories in English and Chinese', () {
      final en = AppLocalizationsEn();
      final zh = AppLocalizationsZh();

      expect(
        friendlyErrorText('SSH host key verification failed: mismatch', en),
        contains('SSH host key verification failed'),
      );
      expect(
        friendlyErrorText('SSH host key verification failed: mismatch', zh),
        contains('SSH 主机密钥验证失败'),
      );
      expect(
        friendlyErrorText('SignatureDoesNotMatch from S3', zh),
        contains('对象存储配置错误'),
      );
      expect(
        friendlyErrorText('NT_STATUS_BAD_NETWORK_NAME', zh),
        contains('SMB 共享连接失败'),
      );
      expect(
        friendlyErrorText('encrypted archive requires wrong password', zh),
        contains('压缩包密码'),
      );
      expect(
        friendlyErrorText('No space left on device (disk full)', zh),
        contains('剩余空间不足'),
      );
    });

    test('detectErrorRecovery classifies every ErrorRecoveryKind', () {
      expect(
        detectErrorRecovery('permission denied: /sdcard'),
        ErrorRecoveryKind.storagePermission,
      );
      expect(
        detectErrorRecovery('SFTP fingerprint mismatch for example.com'),
        ErrorRecoveryKind.hostKeyTrust,
      );
      expect(
        detectErrorRecovery('encrypted archive bad password'),
        ErrorRecoveryKind.archivePassword,
      );
      expect(
        detectErrorRecovery('No space left on device'),
        ErrorRecoveryKind.storageSpace,
      );
      expect(
        detectErrorRecovery('InvalidAccessKeyId'),
        ErrorRecoveryKind.remoteCredentials,
      );
      expect(
        detectErrorRecovery('connection timed out after 30s'),
        ErrorRecoveryKind.networkRetry,
      );
      expect(
        detectErrorRecovery('unexpected unknown error'),
        ErrorRecoveryKind.none,
      );
    });
  });

  group('media_player_shared helpers', () {
    test('formatMediaDuration, speed persistence, and nextPlaybackSpeed', () {
      expect(formatMediaDuration(const Duration(seconds: -5)), '00:00');
      expect(formatMediaDuration(const Duration(minutes: 4, seconds: 9)), '04:09');
      expect(
        formatMediaDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );

      savePlaybackSpeed(1.5);
      expect(
        PreferencesService.instance.getString(kPrefMediaPlaybackSpeed),
        '1.5',
      );
      expect(loadSavedPlaybackSpeed(), 1.5);

      savePlaybackSpeed(99.0);
      expect(loadSavedPlaybackSpeed(fallback: 1.0), 1.0);

      expect(nextPlaybackSpeed(1.0, increase: true), 1.25);
      expect(nextPlaybackSpeed(1.0, increase: false), 0.75);
      expect(nextPlaybackSpeed(kMediaPlaybackSpeeds.last, increase: true), 4.0);
      expect(nextPlaybackSpeed(kMediaPlaybackSpeeds.first, increase: false), 0.5);
    });
  });

  group('Vault lock cleanup & workspace matcher', () {
    test('matchesLockedVault accurately scopes specific and all vault roots', () {
      expect(
        BrowserWorkspacePageState.matchesLockedVault('vault://v1', 'v1'),
        isTrue,
      );
      expect(
        BrowserWorkspacePageState.matchesLockedVault(
          'archive://vault://v1/sub.zip',
          'v1',
        ),
        isTrue,
      );
      expect(
        BrowserWorkspacePageState.matchesLockedVault('vault://v2', 'v1'),
        isFalse,
      );
      expect(
        BrowserWorkspacePageState.matchesLockedVault('/home/user', null),
        isFalse,
      );
      expect(
        BrowserWorkspacePageState.matchesLockedVault('vault://v2', null),
        isTrue,
      );
    });

    test('registerLockCleanup and unregisterLockCleanup manage callbacks', () {
      final events = <String?>[];
      void listener(String? id) => events.add(id);
      VaultService.instance.registerLockCleanup(listener);
      VaultService.instance.dispatchLockCleanupsForTest('v1');
      expect(events, ['v1']);

      VaultService.instance.unregisterLockCleanup(listener);
      VaultService.instance.dispatchLockCleanupsForTest('v2');
      expect(events, ['v1']);
    });
  });
}
