import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/share_receiver_dialog.dart';
import 'package:filemanager/src/services/external_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleFile1;
  late File sampleFile2;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('share_receiver_test_');
    sampleFile1 = File('${tempDir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    sampleFile2 = File('${tempDir.path}/notes.txt')..writeAsStringSync('Hello world');
  });

  tearDownAll(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget buildTestableWidget(Widget child, {Locale locale = const Locale('zh')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('ShareReceiverContent widget tests', () {
    testWidgets('Renders single file share details and 3 action cards in Chinese', (tester) async {
      bool cancelled = false;
      ShareReceiverAction? selectedAction;
      await tester.pumpWidget(
        buildTestableWidget(
          ShareReceiverContent(
            filePaths: [sampleFile1.path],
            onAction: (a) => selectedAction = a,
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and file name
      expect(find.text('接收到分享文件'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);

      // Check 3 action options
      expect(find.text('保存到本地'), findsOneWidget);
      expect(find.text('选择本地文件夹并保存'), findsOneWidget);
      expect(find.text('保存到远程'), findsOneWidget);
      expect(find.text('上传至云存储、WebDAV 或 SFTP'), findsOneWidget);
      expect(find.text('直接打开'), findsOneWidget);
      expect(find.text('在应用内直接查看或播放'), findsOneWidget);

      // Check cancel button
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('取消'));
      expect(cancelled, isTrue);

      // Test tapping Save to Local triggers action
      await tester.tap(find.text('保存到本地'));
      expect(selectedAction, equals(ShareReceiverAction.saveLocal));
    });

    testWidgets('Allows editing single file name and triggers onActionWithName', (tester) async {
      ShareReceiverAction? selectedAction;
      String? customName;
      await tester.pumpWidget(
        buildTestableWidget(
          ShareReceiverContent(
            filePaths: [sampleFile1.path],
            onAction: (a) => selectedAction = a,
            onActionWithName: (a, name) {
              selectedAction = a;
              customName = name;
            },
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the edit icon to edit filename
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Enter new filename
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'renamed_photo.jpg');
      await tester.pumpAndSettle();

      // Tap Save to Local
      await tester.tap(find.text('保存到本地'));
      expect(selectedAction, equals(ShareReceiverAction.saveLocal));
      expect(customName, equals('renamed_photo.jpg'));
    });

    testWidgets('Rejects invalid filename containing slash when saving', (tester) async {
      ShareReceiverAction? selectedAction;
      String? customName;
      await tester.pumpWidget(
        buildTestableWidget(
          ShareReceiverContent(
            filePaths: [sampleFile1.path],
            onAction: (a) => selectedAction = a,
            onActionWithName: (a, name) {
              selectedAction = a;
              customName = name;
            },
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '../evil.jpg');
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存到本地'));
      await tester.pumpAndSettle();

      expect(selectedAction, isNull);
      expect(customName, isNull);
      expect(find.textContaining('不能包含 "/"'), findsOneWidget);
    });

    testWidgets('Ignores custom name for openDirectly and whitespace-only input', (tester) async {
      ShareReceiverAction? selectedAction;
      String? customName = 'sentinel';
      await tester.pumpWidget(
        buildTestableWidget(
          ShareReceiverContent(
            filePaths: [sampleFile1.path],
            onAction: (a) => selectedAction = a,
            onActionWithName: (a, name) {
              selectedAction = a;
              customName = name;
            },
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存到本地'));
      expect(selectedAction, equals(ShareReceiverAction.saveLocal));
      expect(customName, isNull);

      await tester.enterText(find.byType(TextField), 'custom.jpg');
      await tester.pumpAndSettle();
      await tester.tap(find.text('直接打开'));
      expect(selectedAction, equals(ShareReceiverAction.openDirectly));
      expect(customName, isNull);
    });

    testWidgets('Renders multiple files share details in English', (tester) async {
      ShareReceiverAction? selectedAction;
      await tester.pumpWidget(
        buildTestableWidget(
          ShareReceiverContent(
            filePaths: [sampleFile1.path, sampleFile2.path],
            onAction: (a) => selectedAction = a,
            onCancel: () {},
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and multiple files label
      expect(find.text('Received Shared Files'), findsOneWidget);
      expect(find.text('Received 2 files'), findsOneWidget);

      // Check file preview entries
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);

      // Check 3 actions in English
      expect(find.text('Save to Local'), findsOneWidget);
      expect(find.text('Choose a local folder to save'), findsOneWidget);
      expect(find.text('Save to Remote'), findsOneWidget);
      expect(find.text('Upload to cloud storage, WebDAV or SFTP'), findsOneWidget);
      expect(find.text('Open Directly'), findsOneWidget);
      expect(find.text('View or play directly in app'), findsOneWidget);

      await tester.tap(find.text('Save to Remote'));
      expect(selectedAction, equals(ShareReceiverAction.saveRemote));
    });

    testWidgets('showShareReceiverDialog opens bottom sheet on mobile screens', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger showShareReceiverDialog
      showShareReceiverDialog(context: testContext, filePaths: [sampleFile1.path]);
      await tester.pumpAndSettle();

      // Should find ShareReceiverContent inside bottom sheet
      expect(find.byType(ShareReceiverContent), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('接收到分享文件'), findsOneWidget);
    });

    testWidgets('showShareReceiverDialog opens dialog on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) {
              testContext = ctx;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger showShareReceiverDialog
      showShareReceiverDialog(context: testContext, filePaths: [sampleFile1.path, sampleFile2.path]);
      await tester.pumpAndSettle();

      // Should find ShareReceiverContent inside Dialog
      expect(find.byType(ShareReceiverContent), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('接收到分享文件'), findsOneWidget);
    });
  });

  group('ShareReceiver helper safety tests', () {
    test('isPathInTemporaryInbox only matches files inside app inbox dirs', () {
      const allowed = [
        '/data/user/0/com.github.th997.filemanager/cache/inbox',
        '/var/mobile/Containers/Data/Application/123/Documents/Inbox',
      ];

      expect(
        isPathInTemporaryInbox(
          '/data/user/0/com.github.th997.filemanager/cache/inbox/photo.jpg',
          allowed,
        ),
        isTrue,
      );
      expect(
        isPathInTemporaryInbox(
          '/var/mobile/Containers/Data/Application/123/Documents/Inbox/notes.txt',
          allowed,
        ),
        isTrue,
      );

      // User directories that happen to contain "/inbox/" must NEVER be deleted.
      expect(
        isPathInTemporaryInbox('/home/user/inbox/contract.pdf', allowed),
        isFalse,
      );
      expect(
        isPathInTemporaryInbox('/storage/emulated/0/Documents/inbox/a.jpg', allowed),
        isFalse,
      );
      expect(
        isPathInTemporaryInbox(
          '/data/user/0/com.github.th997.filemanager/cache/inbox/../secret.txt',
          allowed,
        ),
        isFalse,
      );
      expect(
        isPathInTemporaryInbox(
          '/data/user/0/com.github.th997.filemanager/cache/inbox_extra/a.jpg',
          allowed,
        ),
        isFalse,
      );
    });

    test('isValidFileName validates file names strictly', () {
      expect(isValidFileName('photo_1.jpg'), isTrue);
      expect(isValidFileName('.gitignore'), isTrue);
      expect(isValidFileName(''), isFalse);
      expect(isValidFileName('.'), isFalse);
      expect(isValidFileName('..'), isFalse);
      expect(isValidFileName('a/b.txt'), isFalse);
      expect(isValidFileName(r'a\b.txt'), isFalse);
    });

    test('expandInboxDirCandidates matches files across symlinked inbox parents', () {
      final realDocs = Directory('${tempDir.path}/real_docs');
      final realInbox = Directory('${realDocs.path}/Inbox')..createSync(recursive: true);
      final incomingFile = File('${realInbox.path}/incoming.pdf')..writeAsBytesSync([1, 2, 3]);
      final symlinkDocs = Link('${tempDir.path}/symlink_docs')..createSync(realDocs.path);

      final candidates = expandInboxDirCandidates(Directory(symlinkDocs.path), 'Inbox');
      expect(candidates.length, equals(2));
      expect(isPathInTemporaryInbox(incomingFile.path, candidates), isTrue);
      expect(isPathInTemporaryInbox('${symlinkDocs.path}/Inbox/incoming.pdf', candidates), isTrue);
      expect(isPathInTemporaryInbox('${tempDir.path}/other/Inbox/incoming.pdf', candidates), isFalse);
    });
  });

  group('ExternalFileService share channel tests', () {
    const channel = MethodChannel('com.github.th997.filemanager/open_file');

    testWidgets('Cold-start getInitialShareRequest opens ShareReceiverDialog', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getInitialShareRequest') {
          return <String>[sampleFile1.path];
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        ExternalFileService.instance.resetForTesting();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      ExternalFileService.instance.init(navKey);
      await tester.pumpAndSettle();

      expect(find.byType(ShareReceiverContent), findsOneWidget);
      expect(find.text('接收到分享文件'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('保存到本地'), findsOneWidget);
      expect(find.text('保存到远程'), findsOneWidget);
    });

    testWidgets('Warm-start onShareReceived opens dialog and deduplicates identical payloads', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        ExternalFileService.instance.resetForTesting();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      ExternalFileService.instance.init(navKey);
      await tester.pumpAndSettle();

      Future<void> sendShare(List<String> paths) async {
        final data = const StandardMethodCodec().encodeMethodCall(
          MethodCall('onShareReceived', {'paths': paths}),
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          data,
          (_) {},
        );
      }

      // First warm-start payload opens the receiver UI.
      await sendShare([sampleFile1.path]);
      await tester.pumpAndSettle();
      expect(find.byType(ShareReceiverContent), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);

      // Identical payload within 1 second is deduplicated rather than stacking a second sheet.
      await sendShare([sampleFile1.path]);
      await tester.pumpAndSettle();
      expect(find.byType(ShareReceiverContent), findsOneWidget);

      // Dismiss and send a distinct payload: it must not be suppressed.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.byType(ShareReceiverContent), findsNothing);

      await sendShare([sampleFile1.path, sampleFile2.path]);
      await tester.pumpAndSettle();
      expect(find.byType(ShareReceiverContent), findsOneWidget);
      expect(find.text('接收到 2 个文件'), findsOneWidget);
      expect(find.text('保存到本地'), findsOneWidget);
      expect(find.text('保存到远程'), findsOneWidget);
    });
  });
}
