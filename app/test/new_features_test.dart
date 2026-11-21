import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/dialogs/batch_rename_dialog.dart';
import 'package:filemanager/src/services/global_playback_service.dart';

void main() {
  group('Sleep Timer Tests', () {
    tearDown(() {
      GlobalPlaybackService.instance.cancelSleepTimer();
      GlobalPlaybackService.instance.isPlaying = false;
    });

    test('Setting sleep timer sets remaining duration and timer end time', () {
      final service = GlobalPlaybackService.instance;
      expect(service.sleepTimerRemaining, isNull);

      service.setSleepTimer(const Duration(minutes: 30));
      expect(service.sleepTimerRemaining, isNotNull);
      expect(service.sleepTimerRemaining!.inMinutes, greaterThanOrEqualTo(29));
      expect(service.sleepTimerAtEndOfTrack, isFalse);

      service.cancelSleepTimer();
      expect(service.sleepTimerRemaining, isNull);
    });

    test('Sleep timer countdown expires, pauses playback, and clears state', () async {
      final service = GlobalPlaybackService.instance;
      service.isPlaying = true;
      service.setSleepTimer(const Duration(milliseconds: 40));

      expect(service.sleepTimerRemaining, isNotNull);
      expect(service.sleepTimerRemaining!.isNegative, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(service.isPlaying, isFalse);
      expect(service.sleepTimerRemaining, isNull);
      expect(service.sleepTimerAtEndOfTrack, isFalse);
    });

    test('End-of-track sleep timer flag is consumed exactly once', () {
      final service = GlobalPlaybackService.instance;
      service.setSleepTimer(null, atEndOfTrack: true);
      expect(service.sleepTimerAtEndOfTrack, isTrue);
      expect(service.sleepTimerRemaining, isNull);

      expect(service.consumeEndOfTrackSleepTimer(), isTrue);
      expect(service.sleepTimerAtEndOfTrack, isFalse);
      expect(service.consumeEndOfTrackSleepTimer(), isFalse);
    });
  });

  group('BatchRenameDialog Planner Tests', () {
    test('Plans direct single-phase renames for non-overlapping relative paths', () {
      final plan = BatchRenameDialog.planRenames(
        paths: ['photo1.jpg', 'sub/photo2.jpg'],
        newNames: ['Vacation_photo1.jpg', 'Vacation_photo2.jpg'],
        existingSiblingNames: {'photo1.jpg', 'other.jpg'},
      );

      expect(plan.isValid, isTrue);
      expect(plan.changedCount, 2);
      expect(plan.steps, const [
        RenameStep('photo1.jpg', 'Vacation_photo1.jpg'),
        RenameStep('sub/photo2.jpg', 'sub/Vacation_photo2.jpg'),
      ]);
    });

    test('Plans two-phase renames via temp files for overlapping shifts and swaps', () {
      final shiftPlan = BatchRenameDialog.planRenames(
        paths: ['item_01.jpg', 'item_02.jpg'],
        newNames: ['item_02.jpg', 'item_03.jpg'],
        existingSiblingNames: {'item_01.jpg', 'item_02.jpg'},
      );

      expect(shiftPlan.isValid, isTrue);
      expect(shiftPlan.changedCount, 2);
      expect(shiftPlan.steps.length, 4);
      // Phase 1 moves both sources to temporary names before Phase 2 moves to targets.
      expect(shiftPlan.steps[0].from, 'item_01.jpg');
      expect(shiftPlan.steps[1].from, 'item_02.jpg');
      expect(shiftPlan.steps[2].to, 'item_02.jpg');
      expect(shiftPlan.steps[3].to, 'item_03.jpg');
      expect(shiftPlan.steps[0].to, shiftPlan.steps[2].from);
      expect(shiftPlan.steps[1].to, shiftPlan.steps[3].from);

      final swapPlan = BatchRenameDialog.planRenames(
        paths: ['a.txt', 'b.txt'],
        newNames: ['b.txt', 'a.txt'],
        existingSiblingNames: {'a.txt', 'b.txt'},
      );
      expect(swapPlan.isValid, isTrue);
      expect(swapPlan.steps.length, 4);
    });

    test('Rejects empty names, invalid characters, duplicates, and sibling collisions', () {
      final emptyPlan = BatchRenameDialog.planRenames(
        paths: ['a.jpg', 'b.jpg'],
        newNames: ['', 'b.jpg'],
      );
      expect(emptyPlan.isValid, isFalse);
      expect(emptyPlan.errorKind, BatchRenameValidationErrorKind.emptyName);
      expect(emptyPlan.invalidIndices, contains(0));

      for (final bad in ['a/b.jpg', r'a\b.jpg', '.', '..']) {
        final badPlan = BatchRenameDialog.planRenames(
          paths: ['a.jpg', 'b.jpg'],
          newNames: [bad, 'b2.jpg'],
        );
        expect(badPlan.isValid, isFalse);
        expect(badPlan.errorKind, BatchRenameValidationErrorKind.invalidChars);
      }

      final dupPlan = BatchRenameDialog.planRenames(
        paths: ['a.jpg', 'b.jpg'],
        newNames: ['same.jpg', 'same.jpg'],
      );
      expect(dupPlan.isValid, isFalse);
      expect(dupPlan.errorKind, BatchRenameValidationErrorKind.duplicateTarget);
      expect(dupPlan.invalidIndices, containsAll([0, 1]));

      final existsPlan = BatchRenameDialog.planRenames(
        paths: ['a.jpg', 'b.jpg'],
        newNames: ['existing.jpg', 'b2.jpg'],
        existingSiblingNames: {'a.jpg', 'b.jpg', 'existing.jpg'},
      );
      expect(existsPlan.isValid, isFalse);
      expect(existsPlan.errorKind, BatchRenameValidationErrorKind.targetExists);
      expect(existsPlan.invalidIndices, contains(0));
    });
  });

  group('BatchRenameDialog Widget Tests', () {
    testWidgets('Updates live preview, preserves folder dots, and validates invalid chars', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: BatchRenameDialog(
              root: '/mock/root',
              paths: ['photo1.jpg', 'v1.0.backup'],
              dirPaths: {'v1.0.backup'},
              existingSiblingNames: {'photo1.jpg', 'v1.0.backup'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('批量重命名 (2 项)'), findsOneWidget);
      expect(find.text('photo1.jpg'), findsWidgets);
      expect(find.text('v1.0.backup'), findsWidgets);

      // Initially no changes -> Apply button should be disabled.
      FilledButton applyButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(applyButton().onPressed, isNull);

      // Enter prefix
      final prefixField = find.widgetWithText(TextField, '前缀');
      expect(prefixField, findsOneWidget);
      await tester.enterText(prefixField, 'Vacation_');
      await tester.pumpAndSettle();

      expect(find.text('Vacation_photo1.jpg'), findsOneWidget);
      expect(find.text('Vacation_v1.0.backup'), findsOneWidget);
      expect(applyButton().onPressed, isNotNull);

      // Entering a slash triggers validation error and disables Apply button.
      await tester.enterText(prefixField, 'bad/');
      await tester.pumpAndSettle();
      expect(find.textContaining('不能包含 "/"'), findsOneWidget);
      expect(applyButton().onPressed, isNull);

      // Switch to numbering mode: folder keeps whole name (no .backup extension).
      await tester.tap(find.text('序号递增'));
      await tester.pumpAndSettle();

      expect(find.text('item_01.jpg'), findsOneWidget);
      expect(find.text('item_02'), findsOneWidget);
      expect(applyButton().onPressed, isNotNull);
    });

    testWidgets('Renders localized English UI cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(
            body: BatchRenameDialog(
              root: '/mock/root',
              paths: ['photo1.jpg', 'photo2.jpg'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Batch Rename (2 items)'), findsOneWidget);
      expect(find.text('Prefix / Suffix'), findsOneWidget);
      expect(find.text('Find & Replace'), findsOneWidget);
      expect(find.text('Numbering'), findsOneWidget);
      expect(find.text('Apply Rename (0)'), findsOneWidget);
    });
  });
}
