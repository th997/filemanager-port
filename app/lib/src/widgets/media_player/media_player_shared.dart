import 'package:flutter/material.dart';

import '../../pages/media_player_page.dart' show MediaTrack;
import '../../services/preferences_service.dart';

/// Shared preference key and speed presets reused by both `media_kit` and
/// native AVPlayer media player pages.
const String kPrefMediaPlaybackSpeed = 'player.speed';

const List<double> kMediaPlaybackSpeeds = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  2.0,
  3.0,
  4.0,
];

/// Formats a media duration cleanly as `HH:MM:SS` or `MM:SS`.
String formatMediaDuration(Duration d) {
  final safe = d.isNegative ? Duration.zero : d;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// Reads the persisted playback speed from [PreferencesService], falling back
/// to [fallback] if unset or outside [validSpeeds].
double loadSavedPlaybackSpeed({
  double fallback = 1.0,
  List<double> validSpeeds = kMediaPlaybackSpeeds,
}) {
  final saved = double.tryParse(
    PreferencesService.instance.getString(kPrefMediaPlaybackSpeed) ?? '',
  );
  if (saved != null && validSpeeds.contains(saved)) {
    return saved;
  }
  return fallback;
}

/// Persists [speed] to [PreferencesService] under [kPrefMediaPlaybackSpeed].
void savePlaybackSpeed(double speed) {
  PreferencesService.instance.setString(
    kPrefMediaPlaybackSpeed,
    speed.toString(),
  );
}

/// Returns the next (or previous, when [increase] is false) playback speed
/// preset relative to [current].
double nextPlaybackSpeed(
  double current, {
  bool increase = true,
  List<double> speeds = kMediaPlaybackSpeeds,
}) {
  if (speeds.isEmpty) return current;
  final idx = speeds.indexOf(current);
  if (idx == -1) {
    if (increase) {
      for (final s in speeds) {
        if (s > current) return s;
      }
      return speeds.last;
    } else {
      for (final s in speeds.reversed) {
        if (s < current) return s;
      }
      return speeds.first;
    }
  }
  final nextIdx = increase
      ? (idx + 1).clamp(0, speeds.length - 1)
      : (idx - 1).clamp(0, speeds.length - 1);
  return speeds[nextIdx];
}

/// Computes horizontal swipe seek delta seconds scaled to [totalDuration].
int computeDragSeekDeltaSeconds({
  required double accumulatedDx,
  required double screenWidth,
  required Duration totalDuration,
}) {
  if (screenWidth <= 0) return 0;
  final double maxDragSeconds;
  if (totalDuration > const Duration(minutes: 30)) {
    maxDragSeconds = 300.0;
  } else if (totalDuration > const Duration(minutes: 10)) {
    maxDragSeconds = 180.0;
  } else {
    maxDragSeconds = 90.0;
  }
  return (accumulatedDx / screenWidth * maxDragSeconds).round();
}

/// Shared playlist modal sheet reused across both `media_kit` and native
/// AVPlayer media player shells.
void showMediaPlaylistSheet(
  BuildContext context, {
  required List<MediaTrack> playlist,
  required int currentIndex,
  required ValueChanged<int> onSelectTrack,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: playlist.length,
        itemBuilder: (_, i) {
          final t = playlist[i];
          final current = i == currentIndex;
          return ListTile(
            dense: true,
            leading: Icon(
              current
                  ? Icons.play_circle_fill
                  : (t.isAudio ? Icons.music_note : Icons.movie_outlined),
              color: current ? Colors.blueAccent : null,
            ),
            title: Text(
              t.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: current ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              if (i != currentIndex) {
                onSelectTrack(i);
              }
            },
          );
        },
      ),
    ),
  );
}
