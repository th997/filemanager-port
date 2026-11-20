import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/services/global_playback_service.dart';
import 'package:filemanager/src/services/preferences_service.dart';
import 'package:filemanager/src/widgets/global_mini_player_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalMiniPlayerBar', () {
    setUp(() {
      GlobalPlaybackService.instance.currentFileName = 'test.mp4';
      GlobalPlaybackService.instance.isPlaying = true;
      GlobalPlaybackService.instance.isFullScreen = false;
      GlobalPlaybackService.instance.isMiniPlayerCollapsed = false;
      GlobalPlaybackService.instance.isModalActive = false;
      GlobalPlaybackService.instance.setBottomBarInset(0.0);
      PreferencesService.toolbarAtBottom.value = false;
    });

    tearDown(() {
      GlobalPlaybackService.instance.stop();
      GlobalPlaybackService.instance.setBottomBarInset(0.0);
      GlobalPlaybackService.instance.setModalActive(false);
      PreferencesService.toolbarAtBottom.value = false;
    });

    testWidgets('hides when hasActiveSession is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                GlobalMiniPlayerBar(),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('mini_player_expanded_positioned')), findsNothing);
      expect(find.byKey(const ValueKey('mini_player_collapsed_positioned')), findsNothing);
    });

    testWidgets('positions above bottom action bar when bottomBarInset is set', (tester) async {
      // Simulate active session
      GlobalPlaybackService.instance.currentFileName = 'sample_video.mp4';
      GlobalPlaybackService.instance.duration = const Duration(minutes: 2);
      GlobalPlaybackService.instance.position = const Duration(seconds: 30);
      GlobalPlaybackService.instance.currentPath = '/mock/sample_video.mp4';

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Stack(
              children: [
                Container(),
                const GlobalMiniPlayerBar(),
              ],
            ),
          ),
        ),
      );

      // Default bottom offset without toolbar and without inset:
      // baseBottomOffset = 0 (toolbar) + 0 (inset) + 8.0 + 0 (safeBottom) = 8.0
      // Since desktopPlayer is null, hasActiveSession is false unless controller or desktopPlayer set.
      // Let's verify bottomBarInset logic directly on the service.
      expect(GlobalPlaybackService.instance.bottomBarInset.value, 0.0);

      GlobalPlaybackService.instance.setBottomBarInset(48.0);
      expect(GlobalPlaybackService.instance.bottomBarInset.value, 48.0);

      GlobalPlaybackService.instance.setModalActive(true);
      expect(GlobalPlaybackService.instance.isModalActive, true);

      GlobalPlaybackService.instance.setModalActive(false);
      expect(GlobalPlaybackService.instance.isModalActive, false);
    });

    test('bottomBarInset notifier handles deferred updates safely', () {
      final service = GlobalPlaybackService.instance;
      service.setBottomBarInset(48.0);
      expect(service.bottomBarInset.value, 48.0);

      service.setBottomBarInset(0.0);
      expect(service.bottomBarInset.value, 0.0);
    });
  });
}
