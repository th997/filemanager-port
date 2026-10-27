import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../rust/api/servers.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../widgets/app_swipe_back.dart';
import 'media_player_page.dart';

/// iOS-native video and audio playback using AVPlayer via [VideoPlayerController].
///
/// Bypasses mpv and ao_audiounit entirely, providing native iOS AVFoundation
/// streaming, hardware-accelerated decoding, and system-level audio synchronization.
class NativeMediaPlayerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;
  final List<MediaTrack> playlist;
  final int startIndex;

  const NativeMediaPlayerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
    this.playlist = const [],
    this.startIndex = 0,
  });

  @override
  State<NativeMediaPlayerPage> createState() => _NativeMediaPlayerPageState();
}

class _NativeMediaPlayerPageState extends State<NativeMediaPlayerPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  bool _initialized = false;
  bool _startedStream = false;
  bool _isLooping = false;
  bool _autoNext = true;
  bool _showControls = true;
  bool _isFullscreen = false;
  Timer? _controlsTimer;

  static const _prefVolume = 'player.volume';
  static const _prefLoop = 'player.loop';
  static const _prefAutoNext = 'player.auto_next';
  static const _prefSpeed = 'player.speed';
  static const _prefResumePrefix = 'player.resume.';

  late int _index;
  bool _switching = false;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;

  MediaTrack get _track => widget.playlist.isEmpty
      ? MediaTrack(
          path: widget.path,
          fileName: widget.fileName,
          isAudio: widget.isAudio,
        )
      : widget.playlist[_index.clamp(0, widget.playlist.length - 1)];

  bool get _hasPrev => widget.playlist.length > 1 && _index > 0;
  bool get _hasNext =>
      widget.playlist.length > 1 && _index < widget.playlist.length - 1;

  String get _resumeKey => '$_prefResumePrefix${widget.root}|${_track.path}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.playlist.isEmpty
        ? 0
        : widget.startIndex.clamp(0, widget.playlist.length - 1);

    _isLooping = PreferencesService.instance.getBool(_prefLoop) ?? false;
    _autoNext = PreferencesService.instance.getBool(_prefAutoNext) ?? true;

    final savedSpeed = double.tryParse(
      PreferencesService.instance.getString(_prefSpeed) ?? '',
    );
    if (savedSpeed != null) {
      _playbackSpeed = savedSpeed;
    }

    final savedVol = double.tryParse(
      PreferencesService.instance.getString(_prefVolume) ?? '',
    );
    if (savedVol != null) {
      _volume = (savedVol / 100.0).clamp(0.0, 1.0);
      _lastNonZeroVolume = _volume > 0 ? _volume : 1.0;
    }

    _openCurrentTrack();
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && (_controller?.value.isPlaying ?? false)) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  Future<void> _openCurrentTrack() async {
    _controlsTimer?.cancel();
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      oldController.removeListener(_onControllerUpdate);
      await oldController.dispose();
    }

    if (mounted) {
      setState(() {
        _initialized = false;
        _error = null;
      });
    }

    try {
      final String uri;
      final native = joinNative(widget.root, _track.path);
      if (isNativeRoot(widget.root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
        _controller = VideoPlayerController.file(
          File(native),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
      } else {
        final base = (await startMediaStream(root: widget.root))
            .replaceFirst(RegExp(r'/$'), '');
        _startedStream = true;
        final encoded = _track.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        uri = '$base/$encoded';
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(uri),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
        );
      }

      await _controller!.initialize();
      _controller!.addListener(_onControllerUpdate);

      await _controller!.setLooping(_isLooping);
      await _controller!.setPlaybackSpeed(_playbackSpeed);
      await _controller!.setVolume(_volume);

      // Restore saved resume position if available
      _applyResume();

      await _controller!.play();
      WakelockPlus.enable().catchError((_) {});

      if (mounted) {
        setState(() {
          _initialized = true;
        });
        _resetControlsTimer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  void _applyResume() {
    if (_controller == null) return;
    final saved = int.tryParse(
      PreferencesService.instance.getString(_resumeKey) ?? '',
    );
    if (saved == null || saved < 5000) return;
    final dur = _controller!.value.duration;
    if (dur > Duration.zero && saved < dur.inMilliseconds * 0.95) {
      _controller!.seekTo(Duration(milliseconds: saved));
    }
  }

  void _saveResumePosition() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    if (duration <= Duration.zero) return;
    if (position < const Duration(seconds: 5) || position > duration * 0.95) {
      PreferencesService.instance.remove(_resumeKey);
      return;
    }
    PreferencesService.instance.setString(
      _resumeKey,
      position.inMilliseconds.toString(),
    );
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final val = _controller!.value;

    if (val.hasError) {
      setState(() {
        _error = val.errorDescription ?? 'Unknown playback error';
      });
      return;
    }

    // Auto-advance to next track on natural finish
    if (_initialized &&
        !_switching &&
        !_isLooping &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 300) &&
        !val.isPlaying) {
      if (_autoNext && _hasNext) {
        _switching = true;
        _saveResumePosition();
        final nextTrack = widget.playlist[_index + 1];
        _openTrack(_index + 1);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-playing next: ${nextTrack.fileName}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    if (val.isPlaying) {
      WakelockPlus.enable().catchError((_) {});
    } else {
      WakelockPlus.disable().catchError((_) {});
    }

    setState(() {});
  }

  Future<void> _openTrack(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    _saveResumePosition();
    _switching = true;
    setState(() {
      _index = index;
      _error = null;
      _initialized = false;
    });
    try {
      await _openCurrentTrack();
    } finally {
      _switching = false;
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final cur = _controller!.value.position;
    final dur = _controller!.value.duration;
    final target = cur + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (dur > Duration.zero && target > dur ? dur : target);
    _controller!.seekTo(clamped);
    _resetControlsTimer();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() => _showControls = true);
      _controlsTimer?.cancel();
    } else {
      _controller!.play();
      _resetControlsTimer();
    }
  }

  void _toggleMute() {
    if (_controller == null) return;
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _volume = 0.0;
    } else {
      _volume = _lastNonZeroVolume > 0 ? _lastNonZeroVolume : 1.0;
    }
    _controller!.setVolume(_volume);
    PreferencesService.instance.setString(
      _prefVolume,
      (_volume * 100).toInt().toString(),
    );
    setState(() {});
  }

  void _setSpeed(double speed) {
    if (_controller == null) return;
    _playbackSpeed = speed;
    _controller!.setPlaybackSpeed(speed);
    PreferencesService.instance.setString(_prefSpeed, speed.toString());
    setState(() {});
    _resetControlsTimer();
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  void _showPlaylist() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.playlist.length,
          itemBuilder: (_, i) {
            final t = widget.playlist[i];
            final current = i == _index;
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
                if (i != _index) _openTrack(i);
              },
            );
          },
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // AVPlayer handles background audio natively without OpenGL ES crashes.
    if (state == AppLifecycleState.resumed) {
      _resetControlsTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    WakelockPlus.disable().catchError((_) {});
    _saveResumePosition();

    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }

    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onControllerUpdate);
      c.pause();
      c.dispose();
    }

    if (_startedStream) {
      stopMediaStreams();
    }
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AppSwipeBack(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayPause,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _seekRelative(-5),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _seekRelative(5),
          const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: _showControls || !_isFullscreen
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () async {
                        _saveResumePosition();
                        if (context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    title:
                        Text(_track.fileName, overflow: TextOverflow.ellipsis),
                    actions: [
                      if (widget.playlist.length > 1) ...[
                        IconButton(
                          icon: const Icon(Icons.queue_music),
                          tooltip:
                              'Playlist (${_index + 1}/${widget.playlist.length})',
                          onPressed: _showPlaylist,
                        ),
                        IconButton(
                          icon: Icon(_autoNext
                              ? Icons.playlist_play
                              : Icons.playlist_remove),
                          tooltip:
                              _autoNext ? 'Auto-next: On' : 'Auto-next: Off',
                          color: _autoNext ? Colors.blueAccent : Colors.white60,
                          onPressed: () {
                            setState(() {
                              _autoNext = !_autoNext;
                              PreferencesService.instance
                                  .setBool(_prefAutoNext, _autoNext);
                            });
                          },
                        ),
                      ],
                      IconButton(
                        icon:
                            Icon(_isLooping ? Icons.repeat_one : Icons.repeat),
                        tooltip: _isLooping ? 'Loop: Single' : 'Loop: Off',
                        color: _isLooping ? Colors.blueAccent : Colors.white,
                        onPressed: () {
                          setState(() {
                            _isLooping = !_isLooping;
                            _controller?.setLooping(_isLooping);
                            PreferencesService.instance
                                .setBool(_prefLoop, _isLooping);
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(_isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen),
                        tooltip: _isFullscreen
                            ? 'Exit Fullscreen'
                            : 'Fullscreen',
                        onPressed: _toggleFullscreen,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Playback options',
                        onSelected: (action) {
                          switch (action) {
                            case 'prev':
                              if (_hasPrev) _openTrack(_index - 1);
                              break;
                            case 'next':
                              if (_hasNext) _openTrack(_index + 1);
                              break;
                            case 'auto_next':
                              setState(() {
                                _autoNext = !_autoNext;
                                PreferencesService.instance
                                    .setBool(_prefAutoNext, _autoNext);
                              });
                              break;
                            case 'rewind':
                              _seekRelative(-10);
                              break;
                            case 'forward':
                              _seekRelative(10);
                              break;
                            case 'mute':
                              _toggleMute();
                              break;
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'mute',
                            child: Row(
                              children: [
                                Icon(
                                  _volume == 0
                                      ? Icons.volume_off
                                      : (_volume < 0.5
                                          ? Icons.volume_down
                                          : Icons.volume_up),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(_volume == 0
                                    ? 'Unmute (M)'
                                    : 'Mute (M) (${(_volume * 100).toInt()}%)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'rewind',
                            child: Row(
                              children: [
                                Icon(Icons.replay_10, size: 20),
                                SizedBox(width: 10),
                                Text('Rewind 10s'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'forward',
                            child: Row(
                              children: [
                                Icon(Icons.forward_10, size: 20),
                                SizedBox(width: 10),
                                Text('Forward 10s'),
                              ],
                            ),
                          ),
                          if (widget.playlist.length > 1) ...[
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'auto_next',
                              child: Row(
                                children: [
                                Icon(
                                  _autoNext
                                      ? Icons.playlist_play
                                      : Icons.playlist_remove,
                                  size: 20,
                                  color: _autoNext ? Colors.blueAccent : null,
                                ),
                                const SizedBox(width: 10),
                                Text(_autoNext
                                    ? 'Auto-next (On)'
                                    : 'Auto-next (Off)'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'prev',
                            enabled: _hasPrev,
                            child: const Row(
                              children: [
                                Icon(Icons.skip_previous, size: 20),
                                SizedBox(width: 10),
                                Text('Previous (P)'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'next',
                            enabled: _hasNext,
                            child: const Row(
                              children: [
                                Icon(Icons.skip_next, size: 20),
                                SizedBox(width: 10),
                                Text('Next (N)'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    ],
                  )
                : null,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (details) {
                final width = MediaQuery.of(context).size.width;
                if (details.localPosition.dx < width / 3) {
                  _seekRelative(-10);
                } else if (details.localPosition.dx > width * 2 / 3) {
                  _seekRelative(10);
                } else {
                  _togglePlayPause();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Video rendering surface
                  Center(
                    child: _error != null
                        ? _buildErrorView()
                        : (!_initialized || _controller == null
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : (_track.isAudio
                                ? _buildAudioPlaceholder()
                                : AspectRatio(
                                    aspectRatio:
                                        _controller!.value.aspectRatio > 0
                                            ? _controller!.value.aspectRatio
                                            : 16 / 9,
                                    child: VideoPlayer(_controller!),
                                  ))),
                  ),

                  // Buffering indicator
                  if (_initialized &&
                      _controller != null &&
                      _controller!.value.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),

                  // Center Play/Pause splash button when paused
                  if (_showControls &&
                      _initialized &&
                      _controller != null &&
                      !_controller!.value.isPlaying &&
                      !_controller!.value.isBuffering)
                    Center(
                      child: IconButton(
                        iconSize: 72,
                        icon: const Icon(
                          Icons.play_circle_filled,
                          color: Colors.white70,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),

                  // Overlay Controls (Timeline + Bottom Buttons)
                  if (_showControls && _initialized && _controller != null)
                    _buildControlsOverlay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioPlaceholder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.music_note, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _track.fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(
            'Cannot play this file',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            onPressed: _openCurrentTrack,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final val = _controller!.value;
    final pos = val.position;
    final dur = val.duration;
    final double maxSec = dur.inMilliseconds.toDouble();
    final double curSec = pos.inMilliseconds.toDouble().clamp(0.0, maxSec > 0 ? maxSec : 0.0);

    final double bottomMargin = _isFullscreen ? 36.0 : 24.0;
    final double seekMargin = _isFullscreen ? 96.0 : 84.0;

    return Stack(
      children: [
        // Seek Bar (Safely raised above Home Indicator)
        Positioned(
          left: 16,
          right: 16,
          bottom: seekMargin,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(pos),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(dur),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.0,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14.0),
                  activeTrackColor: Colors.blueAccent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.blueAccent,
                ),
                child: Slider(
                  value: maxSec > 0 ? curSec : 0.0,
                  min: 0.0,
                  max: maxSec > 0 ? maxSec : 1.0,
                  onChanged: (v) {
                    _controlsTimer?.cancel();
                    _controller?.seekTo(Duration(milliseconds: v.toInt()));
                  },
                  onChangeEnd: (_) {
                    _resetControlsTimer();
                  },
                ),
              ),
            ],
          ),
        ),

        // Bottom Action Bar
        Positioned(
          left: 16,
          right: 16,
          bottom: bottomMargin,
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  val.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _togglePlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                tooltip: 'Rewind 10s',
                onPressed: () => _seekRelative(-10),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                tooltip: 'Forward 10s',
                onPressed: () => _seekRelative(10),
              ),
              if (widget.playlist.length > 1) ...[
                IconButton(
                  icon: Icon(
                    Icons.skip_previous,
                    color: _hasPrev ? Colors.white : Colors.white38,
                  ),
                  tooltip: 'Previous (P)',
                  onPressed: _hasPrev ? () => _openTrack(_index - 1) : null,
                ),
                IconButton(
                  icon: Icon(
                    Icons.skip_next,
                    color: _hasNext ? Colors.white : Colors.white38,
                  ),
                  tooltip: 'Next episode (N)',
                  onPressed: _hasNext ? () => _openTrack(_index + 1) : null,
                ),
              ],
              const Spacer(),
              // Speed Menu
              PopupMenuButton<double>(
                tooltip: 'Playback speed',
                onSelected: _setSpeed,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0.5, child: Text('0.5x')),
                  PopupMenuItem(value: 0.75, child: Text('0.75x')),
                  PopupMenuItem(value: 1.0, child: Text('1.0x')),
                  PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  PopupMenuItem(value: 1.5, child: Text('1.5x')),
                  PopupMenuItem(value: 2.0, child: Text('2.0x')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed.toStringAsFixed(_playbackSpeed.truncateToDouble() == _playbackSpeed ? 0 : 2)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
