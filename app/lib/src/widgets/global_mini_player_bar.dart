import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/global_playback_service.dart';
import '../services/preferences_service.dart';

/// Floating mini player bar displayed across directory browsing when playback is active.
///
/// Supports interactive controls (Play/Pause, Close, restore to fullscreen),
/// manual collapse/expand (hide/reveal), and free draggable repositioning across the screen.
class GlobalMiniPlayerBar extends StatefulWidget {
  const GlobalMiniPlayerBar({super.key});

  @override
  State<GlobalMiniPlayerBar> createState() => _GlobalMiniPlayerBarState();
}

class _GlobalMiniPlayerBarState extends State<GlobalMiniPlayerBar> {
  // Vertical displacement above default baseline for the expanded bar
  double _barDragOffsetY = 0.0;

  // Custom position for the collapsed floating pill (null = default bottom-right)
  double? _pillRight;
  double? _pillBottom;

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        GlobalPlaybackService.instance,
        PreferencesService.toolbarAtBottom,
      ]),
      builder: (context, _) {
        final service = GlobalPlaybackService.instance;
        if (!service.hasActiveSession || service.isFullScreen) {
          return const SizedBox.shrink();
        }

        final compact = MediaQuery.sizeOf(context).width < 600;
        final bottomToolbarHeight = PreferencesService.toolbarAtBottom.value
            ? (compact ? 40.0 : 46.0)
            : 0.0;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final baseBottomOffset = bottomToolbarHeight +
            (PreferencesService.toolbarAtBottom.value ? 6.0 : 8.0) +
            safeBottom;

        if (service.isMiniPlayerCollapsed) {
          return _buildCollapsedPill(context, service, baseBottomOffset);
        } else {
          return _buildExpandedBar(context, service, baseBottomOffset);
        }
      },
    );
  }

  Widget _buildCollapsedPill(
    BuildContext context,
    GlobalPlaybackService service,
    double baseBottomOffset,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;

    final currentRight = _pillRight ?? 16.0;
    final currentBottom = _pillBottom ?? baseBottomOffset;

    return Positioned(
      key: const ValueKey('mini_player_collapsed_positioned'),
      right: currentRight,
      bottom: currentBottom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            _pillRight = (currentRight - details.delta.dx).clamp(
              8.0,
              size.width - 160.0,
            );
            _pillBottom = (currentBottom - details.delta.dy).clamp(
              baseBottomOffset,
              size.height - safeTop - 60.0,
            );
          });
        },
        onTap: () {
          HapticFeedback.lightImpact();
          // Tapping the minimized pill restores the video immediately
          service.restoreFullScreen(context);
        },
        child: Material(
          elevation: 6,
          shadowColor: Colors.black54,
          color: colorScheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  service.isPlaying
                      ? (service.isAudio ? Icons.music_note : Icons.movie)
                      : Icons.pause,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    service.currentFileName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Tap chevron specifically to expand mini controls bar instead of fullscreen
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    service.expandMiniPlayer();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedBar(
    BuildContext context,
    GlobalPlaybackService service,
    double baseBottomOffset,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeTop = MediaQuery.paddingOf(context).top;
    final maxOffsetY = (screenHeight - baseBottomOffset - safeTop - 90.0).clamp(0.0, double.infinity);
    final effectiveBottom = baseBottomOffset + _barDragOffsetY;

    return Positioned(
      key: const ValueKey('mini_player_expanded_positioned'),
      left: 10,
      right: 10,
      bottom: effectiveBottom,
      child: Material(
        elevation: 8,
        shadowColor: Colors.black54,
        color: colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dedicated drag handle at the top of the bar for relocation
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _barDragOffsetY = (_barDragOffsetY - details.delta.dy).clamp(0.0, maxOffsetY);
                });
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0.0;
                if (velocity > 350 && _barDragOffsetY < 20) {
                  HapticFeedback.lightImpact();
                  service.collapseMiniPlayer();
                  setState(() => _barDragOffsetY = 0.0);
                }
              },
              onDoubleTap: () {
                HapticFeedback.lightImpact();
                setState(() => _barDragOffsetY = 0.0);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  // Full body is a pure, unblocked tap-target to restore fullscreen
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        service.restoreFullScreen(context);
                      },
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          IgnorePointer(
                            child: _buildThumbnail(context, service),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.currentFileName ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_formatDuration(service.position)} / ${_formatDuration(service.duration)}${service.playbackSpeed != 1.0 ? ' • ${service.playbackSpeed.toStringAsFixed(service.playbackSpeed.truncateToDouble() == service.playbackSpeed ? 0 : 2)}x' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      service.isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 24,
                      color: colorScheme.onSurface,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      service.togglePlayPause();
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      size: 22,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      service.collapseMiniPlayer();
                    },
                  ),
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    icon: Icon(
                      Icons.close,
                      size: 22,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      service.stop();
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            _buildProgressBar(context, service),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, GlobalPlaybackService service) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        service.isAudio ? Icons.music_note : Icons.movie,
        size: 20,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, GlobalPlaybackService service) {
    final posMs = service.position.inMilliseconds;
    final durMs = service.duration.inMilliseconds;
    final progress = (durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(
          Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
