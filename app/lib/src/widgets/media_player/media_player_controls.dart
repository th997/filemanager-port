import 'package:flutter/material.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../../services/global_playback_service.dart';

/// Standard list of playback speeds supported across players.
const List<double> kPlayerSpeedRates = [
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  2.0,
  3.0,
  4.0,
  8.0,
];

/// Formats a [Duration] into `hh:mm:ss` or `mm:ss`.
String formatPlayerDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Formats a playback speed [rate] into human-readable text (e.g. `2x`, `1.25x`).
String formatPlayerSpeed(double rate) {
  final isWhole = rate == rate.roundToDouble();
  return '${isWhole ? rate.toInt() : rate}x';
}

/// Displays the standard dark speed selection popup menu near [buttonContext].
Future<double?> showPlayerSpeedMenu({
  required BuildContext context,
  required BuildContext buttonContext,
  required double currentSpeed,
  required ValueChanged<double> onSelected,
  List<double> rates = kPlayerSpeedRates,
}) async {
  final RenderBox? button = buttonContext.findRenderObject() as RenderBox?;
  final overlay = Navigator.of(context, rootNavigator: true)
      .overlay
      ?.context
      .findRenderObject() as RenderBox?;
  if (button == null || overlay == null) return null;

  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(button.size.bottomRight(Offset.zero),
          ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );

  final selected = await showMenu<double>(
    context: buttonContext,
    useRootNavigator: true,
    position: position,
    elevation: 8,
    color: const Color(0xF21C1C1E),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Colors.white24, width: 0.8),
    ),
    items: [
      for (final rate in rates)
        PopupMenuItem<double>(
          value: rate,
          height: 38,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  formatPlayerSpeed(rate),
                  style: TextStyle(
                    color: (rate - currentSpeed).abs() < 0.01
                        ? const Color(0xFF40C4FF)
                        : Colors.white,
                    fontWeight: (rate - currentSpeed).abs() < 0.01
                        ? FontWeight.bold
                        : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              if ((rate - currentSpeed).abs() < 0.01)
                const Icon(
                  Icons.check,
                  size: 16,
                  color: Color(0xFF40C4FF),
                ),
            ],
          ),
        ),
    ],
  );

  if (selected != null) {
    onSelected(selected);
  }
  return selected;
}

/// Compact speed badge button displaying current speed and opening speed menu on tap.
class MediaPlayerSpeedBadge extends StatelessWidget {
  final double speed;
  final VoidCallback? onTap;

  const MediaPlayerSpeedBadge({
    super.key,
    required this.speed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return Tooltip(
      message: l10n?.playbackSpeed ?? 'Playback speed',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              formatPlayerSpeed(speed),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable timeline slider displaying current position and duration.
class MediaPlayerTimeline extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double>? onSeekEnd;
  final double bottomMargin;

  const MediaPlayerTimeline({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeekChanged,
    this.onSeekEnd,
    this.bottomMargin = 84.0,
  });

  @override
  State<MediaPlayerTimeline> createState() => _MediaPlayerTimelineState();
}

class _MediaPlayerTimelineState extends State<MediaPlayerTimeline> {
  // While dragging, show the finger position instead of the live playback
  // position, and only seek once on release: per-tick seeks flood the
  // native player and the position updates yank the thumb back.
  double? _dragSec;

  @override
  Widget build(BuildContext context) {
    final double maxSec = widget.duration.inMilliseconds.toDouble();
    final double curSec = (_dragSec ??
            widget.position.inMilliseconds.toDouble())
        .clamp(0.0, maxSec > 0 ? maxSec : 0.0);

    return Positioned(
      left: 16,
      right: 16,
      bottom: widget.bottomMargin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatPlayerDuration(_dragSec != null
                    ? Duration(milliseconds: _dragSec!.toInt())
                    : widget.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                formatPlayerDuration(widget.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.blueAccent,
            ),
            child: Slider(
              value: maxSec > 0 ? curSec : 0.0,
              min: 0.0,
              max: maxSec > 0 ? maxSec : 1.0,
              onChangeStart: (v) => setState(() => _dragSec = v),
              onChanged: (v) => setState(() => _dragSec = v),
              onChangeEnd: (v) {
                setState(() => _dragSec = null);
                widget.onSeekChanged(v);
                widget.onSeekEnd?.call(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Cycles between Contain (Fit) -> Cover (Crop) -> Fill (Stretch).
BoxFit nextPlayerVideoFit(BoxFit current) {
  switch (current) {
    case BoxFit.contain:
      return BoxFit.cover;
    case BoxFit.cover:
      return BoxFit.fill;
    default:
      return BoxFit.contain;
  }
}

/// Localized label for the active [BoxFit] video scaling mode.
String playerVideoFitLabel(AppLocalizations l10n, BoxFit fit) {
  switch (fit) {
    case BoxFit.contain:
      return l10n.videoFitContain;
    case BoxFit.cover:
      return l10n.videoFitCover;
    default:
      return l10n.videoFitFill;
  }
}

/// Localized label for the sleep timer menu entry, including active countdown.
String sleepTimerMenuLabel(AppLocalizations l10n) {
  final service = GlobalPlaybackService.instance;
  if (service.sleepTimerAtEndOfTrack) {
    return l10n.sleepTimerMenuRemaining(l10n.sleepTimerEndOfTrackShort);
  }
  final rem = service.sleepTimerRemaining;
  if (rem != null) {
    final mins = (rem.inSeconds / 60).ceil().clamp(1, 999);
    return l10n.sleepTimerMenuRemaining('${mins}m');
  }
  return l10n.sleepTimerTitle;
}

/// Shows the shared Sleep Timer bottom sheet used by both MediaKit and iOS native players.
Future<void> showPlayerSleepTimerSheet(
  BuildContext context, {
  VoidCallback? onEndOfTrackSelected,
  VoidCallback? onChanged,
}) {
  final l10n = AppLocalizations.of(context);
  final service = GlobalPlaybackService.instance;
  final isOff =
      !service.sleepTimerAtEndOfTrack && service.sleepTimerRemaining == null;
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              l10n.sleepTimerTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.timer_off_outlined,
              color: isOff ? Colors.blueAccent : null,
            ),
            title: Text(l10n.sleepTimerOff),
            trailing:
                isOff ? const Icon(Icons.check, color: Colors.blueAccent) : null,
            onTap: () {
              service.cancelSleepTimer();
              Navigator.of(ctx).pop();
              onChanged?.call();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.sleepTimerOffToast)),
              );
            },
          ),
          for (final mins in [15, 30, 45, 60])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(l10n.sleepTimerMinutes(mins)),
              onTap: () {
                service.setSleepTimer(Duration(minutes: mins));
                Navigator.of(ctx).pop();
                onChanged?.call();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.sleepTimerMinutesToast(mins))),
                );
              },
            ),
          ListTile(
            leading: Icon(
              Icons.skip_next_outlined,
              color: service.sleepTimerAtEndOfTrack ? Colors.blueAccent : null,
            ),
            title: Text(l10n.sleepTimerEndOfTrack),
            trailing: service.sleepTimerAtEndOfTrack
                ? const Icon(Icons.check, color: Colors.blueAccent)
                : null,
            onTap: () {
              onEndOfTrackSelected?.call();
              service.setSleepTimer(null, atEndOfTrack: true);
              Navigator.of(ctx).pop();
              onChanged?.call();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.sleepTimerEndOfTrackToast)),
              );
            },
          ),
        ],
      ),
    ),
  );
}
