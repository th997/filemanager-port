import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/recent_page.dart';
import 'package:filemanager/src/rust/api/metadata.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryDto _historyItem(String path, int visitedMillis) {
  return HistoryDto(
    id: 'local:$path',
    root: '/tmp',
    path: path,
    visitedMillis: PlatformInt64Util.from(visitedMillis),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: child,
  );
}

void main() {
  setUp(() {
    PreferencesService.instance.historyRetentionDays =
        PreferencesService.defaultHistoryRetentionDays;
  });

  tearDown(() {
    PreferencesService.instance.historyRetentionDays =
        PreferencesService.defaultHistoryRetentionDays;
  });

  test('PreferencesService historyRetentionDays defaults to 30 and persists changes', () {
    final prefs = PreferencesService.instance;
    expect(prefs.historyRetentionDays, 30);

    final observed = <int>[];
    void listener() =>
        observed.add(PreferencesService.historyRetentionDaysNotifier.value);

    PreferencesService.historyRetentionDaysNotifier.addListener(listener);
    addTearDown(
      () => PreferencesService.historyRetentionDaysNotifier
          .removeListener(listener),
    );

    prefs.historyRetentionDays = 0;
    expect(prefs.historyRetentionDays, 0);

    prefs.historyRetentionDays = 14;
    expect(prefs.historyRetentionDays, 14);

    // Negative values clamp to 0 (do not retain).
    prefs.historyRetentionDays = -5;
    expect(prefs.historyRetentionDays, 0);
    expect(observed, [0, 14, 0]);
  });

  test('partitionHistoryByRetention splits expired entries and clears all on 0 days', () {
    const now = 1700000000000;
    final dayMs = Duration.millisecondsPerDay;
    final fresh = _historyItem('Documents', now - 5 * dayMs);
    final boundary = _historyItem('Downloads', now - 30 * dayMs);
    final stale = _historyItem('Archive', now - 31 * dayMs);

    final split30 = StorageService.partitionHistoryByRetention(
      [fresh, boundary, stale],
      retentionDays: 30,
      nowMillis: now,
    );
    expect(split30.kept, [fresh, boundary]);
    expect(split30.expired, [stale]);

    final split0 = StorageService.partitionHistoryByRetention(
      [fresh, boundary, stale],
      retentionDays: 0,
      nowMillis: now,
    );
    expect(split0.kept, isEmpty);
    expect(split0.expired, [fresh, boundary, stale]);
  });

  test('recordHistory is a safe no-op when retention is 0', () async {
    PreferencesService.instance.historyRetentionDays = 0;
    await StorageService.instance.recordHistory(root: '/tmp', path: 'ignored');
  });

  testWidgets('RecentPage configures retention days (0 disables and custom days persist)',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var fakeHistory = [
      _historyItem('Projects', now - 1000),
      _historyItem('Pictures', now - 2000),
    ];
    final appliedDays = <int>[];

    await tester.pumpWidget(
      _wrap(
        RecentPage(
          loadHistoryOverride: () async => fakeHistory,
          applyRetentionOverride: (days) async {
            appliedDays.add(days);
            PreferencesService.instance.historyRetentionDays = days;
            if (days == 0) {
              fakeHistory = [];
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('30 天'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);

    // Open retention dialog and select 0 ("不保留").
    await tester.tap(find.byKey(const ValueKey('recent_retention_btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('history_retention_input')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history_retention_preset_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(appliedDays, [0]);
    expect(PreferencesService.instance.historyRetentionDays, 0);
    expect(find.text('不保留'), findsOneWidget);
    expect(find.text('已关闭历史记录保留'), findsOneWidget);
    expect(find.text('设置保留天数'), findsOneWidget);

    // Re-open from empty-state CTA and enter custom value 15 days.
    await tester.tap(find.text('设置保留天数'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('history_retention_input')),
      '15',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(appliedDays, [0, 15]);
    expect(PreferencesService.instance.historyRetentionDays, 15);
    expect(find.text('15 天'), findsOneWidget);
  });
}
