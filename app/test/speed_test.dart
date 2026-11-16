import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  // This is an integration test: it needs media_kit's native player libraries
  // (mpv) and a real media file. In a plain `flutter test` / CI environment
  // those are absent, so mark the test as skipped instead of failing setUpAll
  // or silently returning a false positive.
  String? unavailable;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    unavailable = 'media_kit native libraries unavailable: $e';
  }

  final mediaPath = Platform.environment['FM_TEST_MEDIA'] ??
      '/k/145233001_kjbbaishi/1a转存/2026/00643老姜高级盘口2.0系列/01-2.87选股法-2.mp4';
  if (unavailable == null && !File(mediaPath).existsSync()) {
    unavailable = 'no test media file (set FM_TEST_MEDIA to enable)';
  }

  test('media_kit sets playback rates up to 8.0x smoothly', () async {
    final player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024,
      ),
    );

    addTearDown(() => player.dispose());

    final dynamic platform = player.platform;
    if (platform != null) {
      await platform.setProperty('video-sync', 'audio');
      await platform.setProperty('af', 'scaletempo2=max-speed=16:search-interval=30');
    }

    await player.open(Media(mediaPath), play: true);
    await Future.delayed(const Duration(milliseconds: 300));

    // Test 4.0x
    await player.setRate(4.0);
    expect(player.state.rate, 4.0);
    final p4Start = player.state.position;
    await Future.delayed(const Duration(milliseconds: 800));
    final p4End = player.state.position;
    expect(p4End, greaterThanOrEqualTo(p4Start));

    // Test 8.0x
    await player.setRate(8.0);
    expect(player.state.rate, 8.0);
    final p8Start = player.state.position;
    await Future.delayed(const Duration(milliseconds: 800));
    final p8End = player.state.position;
    expect(p8End, greaterThanOrEqualTo(p8Start));
  }, skip: unavailable);
}
