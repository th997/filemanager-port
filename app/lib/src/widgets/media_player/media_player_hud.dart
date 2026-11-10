import 'package:flutter/material.dart';

import 'media_player_controls.dart';

/// Floating HUD shown during long-press 2x (or custom) fast-forward.
class MediaPlayerSpeedBoostHud extends StatelessWidget {
  final double boostRate;

  const MediaPlayerSpeedBoostHud({
    super.key,
    required this.boostRate,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 64,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.amber.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fast_forward, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                '${boostRate.toInt()}X Fast Forward',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating toast HUD shown briefly when playback speed is changed.
class MediaPlayerSpeedToastHud extends StatelessWidget {
  final double speed;

  const MediaPlayerSpeedToastHud({
    super.key,
    required this.speed,
  });

  @override
  Widget build(BuildContext context) {
    final speedText =
        speed == speed.roundToDouble() ? speed.toInt().toString() : '$speed';
    return Positioned(
      top: 64,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white24,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.speed,
                color: Colors.lightBlueAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '$speedText× 播放速度',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Center HUD displayed when horizontally swiping across the screen to seek.
class MediaPlayerSeekHud extends StatelessWidget {
  final int deltaSeconds;
  final Duration target;
  final Duration total;

  const MediaPlayerSeekHud({
    super.key,
    required this.deltaSeconds,
    required this.target,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              deltaSeconds >= 0 ? Icons.fast_forward : Icons.fast_rewind,
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 6),
            Text(
              '${deltaSeconds >= 0 ? "+" : ""}${deltaSeconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPlayerDuration(target)} / ${formatPlayerDuration(total)}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Center HUD displayed when vertically sliding on the right side to adjust volume.
class MediaPlayerVolumeHud extends StatelessWidget {
  final double volume; // 0.0 to 1.0

  const MediaPlayerVolumeHud({
    super.key,
    required this.volume,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = volume.clamp(0.0, 1.0);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              clamped == 0
                  ? Icons.volume_off
                  : (clamped < 0.5 ? Icons.volume_down : Icons.volume_up),
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 8),
            Text(
              '${(clamped * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: clamped,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Center HUD displayed when vertically sliding on the left side to adjust screen brightness.
class MediaPlayerBrightnessHud extends StatelessWidget {
  final double brightness; // 0.0 to 1.0

  const MediaPlayerBrightnessHud({
    super.key,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = brightness.clamp(0.0, 1.0);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              clamped < 0.3
                  ? Icons.brightness_low
                  : (clamped < 0.7
                      ? Icons.brightness_medium
                      : Icons.brightness_high),
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 8),
            Text(
              '${(clamped * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 100,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: clamped,
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Left or right ripple HUD displayed when double-tapping left/right third to seek 10s.
class MediaPlayerDoubleTapSeekHud extends StatelessWidget {
  final int seconds;

  const MediaPlayerDoubleTapSeekHud({
    super.key,
    required this.seconds,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: seconds < 0 ? 32 : null,
      right: seconds > 0 ? 32 : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                seconds < 0 ? Icons.replay_10 : Icons.forward_10,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                '${seconds > 0 ? '+' : ''}$seconds s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
