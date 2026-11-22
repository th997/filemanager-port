import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/share_receiver_dialog.dart';
import 'package:filemanager/src/dialogs/vault_dialogs.dart';
import 'package:filemanager/src/rust/api/vault.dart';
import 'package:filemanager/src/services/global_playback_service.dart';
import 'package:filemanager/src/services/path_utils.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/vault_service.dart';
import 'package:filemanager/src/widgets/entry_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VaultService password & timeout helpers', () {
    test('validatePassword checks 8..128 bounds and allows special symbols', () {
      expect(VaultService.validatePassword(''), PasswordValidationError.tooShort);
      expect(
        VaultService.validatePassword('1234567'),
        PasswordValidationError.tooShort,
      );
      expect(
        VaultService.validatePassword('12345678'),
        PasswordValidationError.none,
      );
      expect(
        VaultService.validatePassword(r'p@$$w0rd!#%^&*()-_=+[]{}|;:,<.>/?'),
        PasswordValidationError.none,
      );
      expect(
        VaultService.validatePassword('a' * 128),
        PasswordValidationError.none,
      );
      expect(
        VaultService.validatePassword('a' * 129),
        PasswordValidationError.tooLong,
      );
    });

    test('shouldAutoLock triggers at 10-minute background threshold', () {
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      expect(
        VaultService.shouldAutoLock(backgroundedAt: null, now: t0),
        isFalse,
      );
      expect(
        VaultService.shouldAutoLock(
          backgroundedAt: t0,
          now: t0.add(const Duration(minutes: 9, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        VaultService.shouldAutoLock(
          backgroundedAt: t0,
          now: t0.add(const Duration(minutes: 10)),
        ),
        isTrue,
      );
      expect(
        VaultService.shouldAutoLock(
          backgroundedAt: t0,
          now: t0.add(const Duration(minutes: 15)),
        ),
        isTrue,
      );
    });

    test('extractAlreadyExistsName parses raw, unicode, parenthesized, and wrapped errors', () {
      expect(
        VaultService.extractAlreadyExistsName('privacy folder already exists: diary'),
        'diary',
      );
      expect(
        VaultService.extractAlreadyExistsName('privacy folder already exists: 绝密相册'),
        '绝密相册',
      );
      expect(
        VaultService.extractAlreadyExistsName(
          'AnyhowException(privacy folder already exists: photos (1))',
        ),
        'photos (1)',
      );
      expect(
        VaultService.extractAlreadyExistsName(
          'Exception(privacy folder already exists: 我的备份)\n#0 main',
        ),
        '我的备份',
      );
      expect(
        VaultService.extractAlreadyExistsName('incorrect password or credential'),
        isNull,
      );
      expect(
        VaultService.extractAlreadyExistsName('privacy folder already exists:   '),
        isNull,
      );
    });
  });

  group('Vault path helpers', () {
    test('isVaultRoot and vaultIdFromRoot parse vault and nested archive roots', () {
      expect(isVaultRoot('vault://id1'), isTrue);
      expect(vaultIdFromRoot('vault://id1'), 'id1');

      expect(isVaultRoot('vault://'), isTrue);
      expect(vaultIdFromRoot('vault://'), isNull);

      expect(isVaultRoot('archive://vault://id1/dir/a.zip'), isFalse);
      expect(vaultIdFromRoot('archive://vault://id1/dir/a.zip'), 'id1');

      expect(isVaultRoot('remote://r1'), isFalse);
      expect(vaultIdFromRoot('remote://r1'), isNull);

      expect(isVaultRoot('/tmp'), isFalse);
      expect(vaultIdFromRoot('/tmp'), isNull);
    });
  });

  group('ShareReceiverContent privacy folder option', () {
    late Directory tempDir;
    late File sampleFile;

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('vault_share_test_');
      sampleFile = File('${tempDir.path}/secret.txt')..writeAsStringSync('top secret');
    });

    tearDownAll(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Widget wrapWithApp(Widget child) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );
    }

    testWidgets('Hides Save to Privacy Folder card when no vault is unlocked', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          ShareReceiverContent(
            filePaths: [sampleFile.path],
            unlockedVaultsOverride: const [],
            onAction: (_) {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('保存到隐私文件夹'), findsNothing);
      expect(find.text('保存到本地'), findsOneWidget);
    });

    testWidgets('Shows and triggers Save to Privacy Folder when an unlocked vault exists', (tester) async {
      ShareReceiverAction? triggered;
      const unlocked = UnlockedVaultDto(
        id: 'v-123',
        name: 'PrivateDocs',
        dirPath: '/tmp/.fpm/v-123',
        cipher: 'aes128gcm',
        authMode: 'password',
        createdAtMs: 1700000000000,
      );

      await tester.pumpWidget(
        wrapWithApp(
          ShareReceiverContent(
            filePaths: [sampleFile.path],
            unlockedVaultsOverride: const [unlocked],
            onAction: (action) => triggered = action,
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('保存到隐私文件夹'), findsOneWidget);
      await tester.tap(find.text('保存到隐私文件夹'));
      expect(triggered, ShareReceiverAction.saveVault);
    });
  });

  group('VaultThumbSemaphore', () {
    test('enforces maxConcurrent = 2 across 8 queued tasks in FIFO order', () async {
      final sem = VaultThumbSemaphore(2);
      var active = 0;
      var maxObserved = 0;
      final startOrder = <int>[];
      final queuedCountsDuringEnqueue = <int>[];

      Future<int> runTask(int id) {
        return sem.withPermit(() async {
          active++;
          if (active > maxObserved) maxObserved = active;
          startOrder.add(id);
          expect(sem.activeCount, lessThanOrEqualTo(2));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return id * 10;
        });
      }

      final futures = <Future<int>>[];
      for (var i = 0; i < 8; i++) {
        futures.add(runTask(i));
        queuedCountsDuringEnqueue.add(sem.queuedCount);
      }

      final results = await Future.wait(futures);
      expect(maxObserved, 2);
      expect(sem.activeCount, 0);
      expect(sem.queuedCount, 0);
      expect(startOrder, [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(results, [0, 10, 20, 30, 40, 50, 60, 70]);
      // Tasks 0 and 1 acquire immediately; tasks 2..7 queue behind them.
      expect(queuedCountsDuringEnqueue, [0, 0, 1, 2, 3, 4, 5, 6]);
    });

    test('releases permit when action throws so subsequent tasks proceed', () async {
      final sem = VaultThumbSemaphore(2);

      await expectLater(
        sem.withPermit(() async {
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(sem.activeCount, 0);
      expect(sem.queuedCount, 0);

      final v = await sem.withPermit(() async => 'ok');
      expect(v, 'ok');
      expect(sem.activeCount, 0);
    });
  });

  group('DeleteVaultDialog', () {
    const vault = UnlockedVaultDto(
      id: 'v-del-1',
      name: 'SecretPics',
      dirPath: '/tmp/.fpm/v-del-1',
      cipher: 'aes128gcm',
      authMode: 'password',
      createdAtMs: 1700000000000,
    );

    Widget wrapDialogHost({
      required Future<void> Function(String) onDelete,
      required void Function(bool?) onClosed,
    }) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final res = await showDialog<bool>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (_) => DeleteVaultDialog(
                    vault: vault,
                    onDeleteOverride: onDelete,
                  ),
                );
                onClosed(res);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
    }

    testWidgets('requires exact vault name match before deleting', (tester) async {
      String? deletedId;
      bool? dialogResult;

      await tester.pumpWidget(
        wrapDialogHost(
          onDelete: (id) async {
            deletedId = id;
          },
          onClosed: (res) => dialogResult = res,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final deleteBtnFinder = find.widgetWithText(FilledButton, '删除');
      expect(deleteBtnFinder, findsOneWidget);
      expect(tester.widget<FilledButton>(deleteBtnFinder).onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'WrongName');
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteBtnFinder).onPressed, isNull);
      expect(deletedId, isNull);

      await tester.enterText(find.byType(TextField), 'SecretPics');
      await tester.pump();
      expect(tester.widget<FilledButton>(deleteBtnFinder).onPressed, isNotNull);

      await tester.tap(deleteBtnFinder);
      await tester.pumpAndSettle();

      expect(deletedId, 'v-del-1');
      expect(dialogResult, isTrue);
    });
  });

  group('Vault auto-lock timeout, suppression, and Now Playing redaction', () {
    tearDown(() {
      PreferencesService.instance.remove(
        PreferencesService.prefVaultAutoLockSec,
      );
      GlobalPlaybackService.instance.setPrivacyMediaLabels(
        audio: 'Private Audio',
        video: 'Private Video',
      );
    });

    test('autoLockTimeout maps preference seconds to Duration / null', () {
      PreferencesService.instance.remove(
        PreferencesService.prefVaultAutoLockSec,
      );
      expect(
        VaultService.instance.autoLockTimeout,
        const Duration(minutes: 10),
      );

      PreferencesService.instance.vaultAutoLockTimeoutSec = 0;
      expect(VaultService.instance.autoLockTimeout, Duration.zero);

      PreferencesService.instance.vaultAutoLockTimeoutSec = 60;
      expect(
        VaultService.instance.autoLockTimeout,
        const Duration(seconds: 60),
      );

      PreferencesService.instance.vaultAutoLockTimeoutSec = -1;
      expect(VaultService.instance.autoLockTimeout, isNull);
    });

    test('runWithAutoLockSuppressed returns value and cleans up on throw', () async {
      final res = await VaultService.instance.runWithAutoLockSuppressed(
        () async => 42,
      );
      expect(res, 42);

      await expectLater(
        VaultService.instance.runWithAutoLockSuppressed(() async {
          throw StateError('picker error');
        }),
        throwsStateError,
      );
    });

    test('redactedNowPlayingTitle masks vault and nested vault archive titles', () {
      GlobalPlaybackService.instance.setPrivacyMediaLabels(
        audio: '私密音频',
        video: '私密视频',
      );

      expect(
        GlobalPlaybackService.instance.redactedNowPlayingTitle(
          root: 'vault://v1',
          fileName: 'secret_voice.m4a',
          isAudio: true,
        ),
        '私密音频',
      );
      expect(
        GlobalPlaybackService.instance.redactedNowPlayingTitle(
          root: 'archive://vault://v1/sub/pack.zip',
          fileName: 'hidden_clip.mp4',
          isAudio: false,
        ),
        '私密视频',
      );
      expect(
        GlobalPlaybackService.instance.redactedNowPlayingTitle(
          root: '/storage/emulated/0/Music',
          fileName: 'public_song.mp3',
          isAudio: true,
        ),
        'public_song.mp3',
      );
      expect(
        GlobalPlaybackService.instance.redactedNowPlayingTitle(
          root: 'remote://nas-1',
          fileName: 'movie.mkv',
          isAudio: false,
        ),
        'movie.mkv',
      );
    });
  });

  group('ChangeVaultSecurityDialog & VaultInfoDialog', () {
    const pwdVault = UnlockedVaultDto(
      id: 'v-sec-1',
      name: 'Personal',
      dirPath: '/tmp/.fpm/v-sec-1',
      cipher: 'aes128gcm',
      authMode: 'password',
      createdAtMs: 1700000000000,
    );

    Widget wrapZh(Widget child) {
      return MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(body: child),
        ),
      );
    }

    testWidgets('ChangeVaultSecurityDialog validates and calls changePassword', (tester) async {
      String? capturedCur;
      String? capturedNew;
      UnlockedVaultDto? result;

      await tester.pumpWidget(
        wrapZh(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showDialog<UnlockedVaultDto>(
                  context: ctx,
                  barrierDismissible: false,
                  builder: (_) => ChangeVaultSecurityDialog(
                    vault: pwdVault,
                    systemAuthAvailableOverride: true,
                    onChangePasswordOverride: ({
                      required vaultId,
                      currentPassword,
                      required newPassword,
                      required systemAuthReason,
                    }) async {
                      capturedCur = currentPassword;
                      capturedNew = newPassword;
                      return pwdVault;
                    },
                  ),
                );
              },
              child: const Text('open-sec'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-sec'));
      await tester.pumpAndSettle();

      expect(find.text('密码与解锁方式'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));

      await tester.enterText(fields.at(0), 'OldPass#1');
      await tester.enterText(fields.at(1), 'NewPass#2');
      await tester.enterText(fields.at(2), 'Mismatch#3');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(capturedNew, isNull);

      await tester.enterText(fields.at(2), 'NewPass#2');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(capturedCur, 'OldPass#1');
      expect(capturedNew, 'NewPass#2');
      expect(result?.id, 'v-sec-1');
    });

    testWidgets('VaultInfoDialog shows stats and cleans orphaned space', (tester) async {
      var statsCalls = 0;
      var gcCalls = 0;

      await tester.pumpWidget(
        wrapZh(
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => VaultInfoDialog(
                  vault: pwdVault,
                  onGetStatsOverride: (_) async {
                    statsCalls++;
                    return VaultStatsDto(
                      fileCount: BigInt.from(3),
                      dirCount: BigInt.from(1),
                      totalPlainBytes: BigInt.from(2048),
                      diskBytes: BigInt.from(statsCalls == 1 ? 4096 : 2560),
                      orphanCount: BigInt.from(statsCalls == 1 ? 2 : 0),
                      orphanBytes: BigInt.from(statsCalls == 1 ? 1536 : 0),
                    );
                  },
                  onGcOverride: (_) async {
                    gcCalls++;
                    return VaultGcResultDto(
                      removedFiles: BigInt.from(2),
                      freedBytes: BigInt.from(1536),
                    );
                  },
                ),
              ),
              child: const Text('open-info'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-info'));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 项（1.5 KB）'), findsOneWidget);
      final gcBtn = find.widgetWithText(TextButton, '清理孤儿数据释放空间');
      expect(gcBtn, findsOneWidget);

      await tester.tap(gcBtn);
      await tester.pumpAndSettle();

      expect(gcCalls, 1);
      expect(statsCalls, 2);
      expect(find.text('已清理 2 个孤儿文件，释放 1.5 KB'), findsOneWidget);
      expect(find.text('0 项（0 B）'), findsOneWidget);
    });
  });
}
