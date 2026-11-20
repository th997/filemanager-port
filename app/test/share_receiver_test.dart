import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/share_receiver_dialog.dart';

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
}
