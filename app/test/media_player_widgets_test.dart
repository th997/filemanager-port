import 'package:filemanager/src/widgets/media_player/media_player_controls.dart';
import 'package:filemanager/src/widgets/media_player/media_player_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaPlayerControls', () {
    test('formatPlayerDuration formats under and over 1 hour correctly', () {
      expect(formatPlayerDuration(const Duration(seconds: 45)), '00:45');
      expect(formatPlayerDuration(const Duration(minutes: 5, seconds: 3)), '05:03');
      expect(formatPlayerDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('formatPlayerSpeed formats whole and fractional speeds', () {
      expect(formatPlayerSpeed(1.0), '1x');
      expect(formatPlayerSpeed(2.0), '2x');
      expect(formatPlayerSpeed(1.25), '1.25x');
      expect(formatPlayerSpeed(0.75), '0.75x');
    });

    testWidgets('MediaPlayerTimeline renders position, duration and slider', (tester) async {
      double seekValue = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MediaPlayerTimeline(
                  position: const Duration(seconds: 30),
                  duration: const Duration(seconds: 120),
                  onSeekChanged: (v) => seekValue = v,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('00:30'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.byType(Slider));
      await tester.pump();
      expect(seekValue, greaterThanOrEqualTo(0.0));
    });

    testWidgets('MediaPlayerSpeedBadge triggers callback on tap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaPlayerSpeedBadge(
              speed: 1.5,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('1.5x'), findsOneWidget);
      await tester.tap(find.text('1.5x'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('MediaPlayerHUD', () {
    testWidgets('MediaPlayerSpeedBoostHud renders label and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MediaPlayerSpeedBoostHud(boostRate: 2.0),
              ],
            ),
          ),
        ),
      );

      expect(find.text('2X Fast Forward'), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward), findsOneWidget);
    });

    testWidgets('MediaPlayerSpeedToastHud renders label and speed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MediaPlayerSpeedToastHud(speed: 1.5),
              ],
            ),
          ),
        ),
      );

      expect(find.text('1.5× 播放速度'), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
    });

    testWidgets('MediaPlayerSeekHud renders forward and rewind text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaPlayerSeekHud(
              deltaSeconds: 10,
              target: Duration(seconds: 70),
              total: Duration(seconds: 120),
            ),
          ),
        ),
      );

      expect(find.text('+10s'), findsOneWidget);
      expect(find.text('01:10 / 02:00'), findsOneWidget);
    });
  });
}
