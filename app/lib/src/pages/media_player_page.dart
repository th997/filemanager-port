import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../rust/api/servers.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../widgets/app_swipe_back.dart';
import 'native_media_player_page.dart';

/// Video and audio playback for local, remote, and archive files.
///
/// Native files are opened directly. Anything else is served over a loopback
/// HTTP endpoint with Range support, so seeking works without downloading the
/// whole file first.
/// One playable item in a [MediaPlayerPage] session. All tracks share
/// the page's root; only the path differs.
class MediaTrack {
  final String path;
  final String fileName;
  final bool isAudio;

  const MediaTrack({
    required this.path,
    required this.fileName,
    required this.isAudio,
  });
}

class MediaPlayerPage extends StatelessWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;

  /// Sibling media files from the folder the user opened, in display
  /// order. Empty means single-file playback (the fields above).
  final List<MediaTrack> playlist;
  final int startIndex;

  const MediaPlayerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
    this.playlist = const [],
    this.startIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return NativeMediaPlayerPage(
        root: root,
        path: path,
        fileName: fileName,
        isAudio: isAudio,
        playlist: playlist,
        startIndex: startIndex,
      );
    }
    return _MediaKitPlayerPage(
      root: root,
      path: path,
      fileName: fileName,
      isAudio: isAudio,
      playlist: playlist,
      startIndex: startIndex,
    );
  }
}

class _MediaKitPlayerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;
  final List<MediaTrack> playlist;
  final int startIndex;

  const _MediaKitPlayerPage({
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
    this.playlist = const [],
    this.startIndex = 0,
  });

  @override
  State<_MediaKitPlayerPage> createState() => _MediaKitPlayerPageState();
}

class _MediaKitPlayerPageState extends State<_MediaKitPlayerPage>
    with WidgetsBindingObserver {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<bool>? _playingSub;
  String? _error;
  bool _opened = false;
  bool _startedStream = false;
  bool _isLooping = false;
  bool _wasPlayingBeforeBackground = false;
  static const _prefVolume = 'player.volume';
  static const _prefLoop = 'player.loop';
  static const _prefAutoNext = 'player.auto_next';
  static const _prefResumePrefix = 'player.resume.';
  late int _index;
  bool _switching = false;
  bool _autoNext = true;
  StreamSubscription<bool>? _completedSub;

  MediaTrack get _track => widget.playlist.isEmpty
      ? MediaTrack(path: widget.path, fileName: widget.fileName, isAudio: widget.isAudio)
      : widget.playlist[_index.clamp(0, widget.playlist.length - 1)];
  bool get _hasPrev => widget.playlist.length > 1 && _index > 0;
  bool get _hasNext =>
      widget.playlist.length > 1 && _index < widget.playlist.length - 1;

  /// Where playback was when the page closed, keyed by the opened file.
  String get _resumeKey => '$_prefResumePrefix${widget.root}|${_track.path}';
  bool _resumeApplied = false;
  Duration? _retryPosition;
  StreamSubscription<Duration>? _resumeSub;
  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;

  static const _prefSpeed = 'player.speed';
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0, 8.0];
  double _playbackSpeed = 1.0;
  Timer? _speedHudTimer;
  double? _hudSpeed;
  StreamSubscription<double>? _rateSub;

  bool _isSpeedBoosting = false;
  double _preBoostSpeed = 1.0;
  double _boostRate = 2.0;

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_player.state.playing) return;
    HapticFeedback.mediumImpact();
    _preBoostSpeed = _playbackSpeed;
    _boostRate = _preBoostSpeed >= 2.0 ? 3.0 : 2.0;
    _player.setRate(_boostRate);
    setState(() {
      _isSpeedBoosting = true;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isSpeedBoosting) return;
    HapticFeedback.lightImpact();
    _player.setRate(_preBoostSpeed);
    setState(() {
      _isSpeedBoosting = false;
    });
  }

  void _setSpeed(double speed) {
    if (_isSpeedBoosting) return;
    _playbackSpeed = speed;
    _player.setRate(speed);
    PreferencesService.instance.setString(_prefSpeed, speed.toString());
    _showSpeedHud(speed);
    if (mounted) setState(() {});
  }

  void _showSpeedHud(double speed) {
    _speedHudTimer?.cancel();
    setState(() {
      _hudSpeed = speed;
    });
    _speedHudTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _hudSpeed = null;
        });
      }
    });
  }

  void _cycleSpeed({required bool increase}) {
    final currentIndex = _rates.indexOf(_playbackSpeed);
    if (currentIndex == -1) {
      _setSpeed(increase ? 1.25 : 0.75);
      return;
    }
    final nextIndex = increase
        ? (currentIndex + 1).clamp(0, _rates.length - 1)
        : (currentIndex - 1).clamp(0, _rates.length - 1);
    _setSpeed(_rates[nextIndex]);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 128 * 1024 * 1024,
      ),
    );
    _tunePlayerProperties();
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        hwdec: 'auto-safe',
        enableHardwareAcceleration: true,
      ),
    );
    _volume = _player.state.volume;
    _playingSub = _player.stream.playing.listen((playing) {
      if (playing) {
        WakelockPlus.enable().catchError((_) {});
      } else {
        WakelockPlus.disable().catchError((_) {});
      }
    });
    final savedSpeed = double.tryParse(
      PreferencesService.instance.getString(_prefSpeed) ?? '',
    );
    if (savedSpeed != null && _rates.contains(savedSpeed)) {
      _playbackSpeed = savedSpeed;
      _player.setRate(savedSpeed);
    }
    _rateSub = _player.stream.rate.listen((rate) {
      if (mounted && !_isSpeedBoosting && _playbackSpeed != rate) {
        setState(() => _playbackSpeed = rate);
      }
    });
    // Volume is a user preference, so a muted-then-closed player does not come
    // back silent next time.
    final savedVolume = double.tryParse(
      PreferencesService.instance.getString(_prefVolume) ?? '',
    );
    if (savedVolume != null) {
      _volume = savedVolume.clamp(0.0, 100.0);
      _player.setVolume(_volume);
    }
    // Loop is a preference too: someone who loops one clip usually keeps
    // looping the next one.
    _isLooping = PreferencesService.instance.getBool(_prefLoop) ?? false;
    if (_isLooping) _player.setPlaylistMode(PlaylistMode.single);
    _autoNext = PreferencesService.instance.getBool(_prefAutoNext) ?? true;
    _volumeSub = _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    _errorSub = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    _index = widget.playlist.isEmpty
        ? 0
        : widget.startIndex.clamp(0, widget.playlist.length - 1);
    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        final pos = _player.state.position;
        final dur = _player.state.duration;
        // Premature stream termination (>2s before true duration):
        // auto-resume from current position instead of pausing or skipping.
        if (dur > const Duration(seconds: 3) &&
            pos < dur - const Duration(seconds: 2)) {
          _retry(fromPosition: pos);
          return;
        }
        // Auto-advance only on a natural finish: not while looping a
        // single track and not while a manual track switch is mid-open.
        if (_autoNext && completed && !_isLooping && !_switching && _hasNext) {
          final nextTrack = widget.playlist[_index + 1];
          _openTrack(_index + 1);
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Auto-playing next: ${nextTrack.fileName}'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    });
    _open();
  }

  /// Switches playback to another track in the playlist, saving the
  /// outgoing track's resume position first.
  Future<void> _openTrack(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    _saveResumePosition();
    _resumeSub?.cancel();
    _resumeSub = null;
    _resumeApplied = false;
    _switching = true;
    setState(() {
      _index = index;
      _error = null;
      _opened = false;
    });
    try {
      await _open();
    } finally {
      _switching = false;
    }
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

  void _toggleMute() {
    if (_volume > 0) {
      _lastNonZeroVolume = _volume;
      _player.setVolume(0.0);
    } else {
      _player.setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 100.0);
    }
    _saveVolume();
  }

  void _changeVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _player.setVolume(newVol);
    if (newVol > 0) _lastNonZeroVolume = newVol;
    _saveVolume();
  }

  /// Remember the level the user settled on; a muted session should not
  /// silence the next video.
  void _saveVolume() {
    final level = _volume > 0 ? _volume : _lastNonZeroVolume;
    PreferencesService.instance.setString(_prefVolume, level.toStringAsFixed(0));
  }

  void _seekRelative(int seconds) {
    final duration = _player.state.duration;
    final pos = _player.state.position + Duration(seconds: seconds);
    final target = pos < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && pos > duration ? duration : pos);
    _player.seek(target);
  }


  Future<void> _open() async {
    try {
      final String uri;
      final native = joinNative(widget.root, _track.path);
      if (isNativeRoot(widget.root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
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
      }
      await _tunePlayerProperties();
      await _player.open(Media(uri));
      await _tunePlayerProperties();
      if (_playbackSpeed != 1.0) {
        await _player.setRate(_playbackSpeed);
      }
      if (mounted) setState(() => _opened = true);
      if (_retryPosition != null) {
        final resumePos = _retryPosition!;
        _retryPosition = null;
        _resumeApplied = true;
        _player.seek(resumePos);
      } else {
        _applyResume();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Continues where the file was left off, unless it was near the start or
  /// already finished. Audio books and long videos are the reason this exists.
  ///
  /// The duration is often still unknown right after `open`, so the seek waits
  /// for the first non-zero duration before deciding whether the saved spot is
  /// past the end.
  void _applyResume() {
    if (_resumeApplied) return;
    _resumeApplied = true;
    final saved = int.tryParse(
      PreferencesService.instance.getString(_resumeKey) ?? '',
    );
    if (saved == null || saved < 5000) return;
    _resumeSub = _player.stream.duration.listen((duration) {
      if (duration <= Duration.zero) return;
      _resumeSub?.cancel();
      _resumeSub = null;
      if (saved > duration.inMilliseconds * 0.95) return;
      _player.seek(Duration(milliseconds: saved));
    });
  }

  void _saveResumePosition() {
    final position = _player.state.position;
    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    if (position < const Duration(seconds: 5) ||
        position > duration * 0.95) {
      PreferencesService.instance.remove(_resumeKey);
      return;
    }
    PreferencesService.instance.setString(
      _resumeKey,
      position.inMilliseconds.toString(),
    );
  }

  /// Reopens the same source after a playback error, e.g. once the network
  /// is back or the remote stream endpoint has restarted.
  Future<void> _retry({Duration? fromPosition}) async {
    _resumeApplied = false;
    _retryPosition = fromPosition;
    await _player.stop();
    if (mounted) {
      setState(() {
        _error = null;
        _opened = false;
      });
    }
    await _open();
  }

  Future<void> _tunePlayerProperties() async {
    final dynamic platform = _player.platform;
    if (platform != null) {
      final isAudio = _track.isAudio;
      final maxBytes = isAudio ? '${16 * 1024 * 1024}' : '${128 * 1024 * 1024}';
      final maxBackBytes = isAudio ? '${8 * 1024 * 1024}' : '${64 * 1024 * 1024}';
      try {
        final futures = <Future<dynamic>>[
          platform.setProperty('cache-pause', 'no') as Future<dynamic>,
          platform.setProperty('cache-pause-wait', '0') as Future<dynamic>,
          platform.setProperty('cache-pause-initial', 'no') as Future<dynamic>,
          platform.setProperty('cache-on-disk', 'no') as Future<dynamic>,
          // Use 'audio' clock sync mode so high playback rates (4x, 8x) advance
          // smoothly without audio resampler overflow or massive vo frame drops.
          platform.setProperty('video-sync', 'audio') as Future<dynamic>,
          // Increase scaletempo2 ceiling beyond the default 8.0 to handle 8x/16x
          // smoothly without muting or dropping audio.
          platform.setProperty('af', 'scaletempo2=max-speed=16:search-interval=30') as Future<dynamic>,
          platform.setProperty('demuxer-readahead-secs', '120') as Future<dynamic>,
          platform.setProperty('demuxer-max-bytes', maxBytes) as Future<dynamic>,
          platform.setProperty('demuxer-max-back-bytes', maxBackBytes) as Future<dynamic>,
          platform.setProperty('network-timeout', '60') as Future<dynamic>,
          platform.setProperty('framedrop', 'vo') as Future<dynamic>,
          platform.setProperty('hr-seek-framedrop', 'yes') as Future<dynamic>,
          platform.setProperty('audio-buffer', '1.0') as Future<dynamic>,
          platform.setProperty('keep-open-pause', 'no') as Future<dynamic>,
        ];
        await Future.wait(futures);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;
    if (_track.isAudio) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // iOS kills apps that perform OpenGL ES rendering in the background.
      // Disabling video track stops GL rendering while audio keeps playing uninterrupted.
      if (_player.state.playing) {
        _wasPlayingBeforeBackground = true;
      }
      _player.setVideoTrack(VideoTrack.no());
    } else if (state == AppLifecycleState.resumed) {
      _player.setVideoTrack(VideoTrack.auto());
      if (_wasPlayingBeforeBackground) {
        _wasPlayingBeforeBackground = false;
        _player.play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    _playingSub?.cancel();
    _rateSub?.cancel();
    _speedHudTimer?.cancel();
    _saveResumePosition();
    _resumeSub?.cancel();
    _completedSub?.cancel();
    _errorSub?.cancel();
    _volumeSub?.cancel();
    _player.stop();
    _player.dispose();
    if (_startedStream) {
      // The loopback stream server started for this root would otherwise
      // keep running (and holding its port) for the rest of the app's
      // lifetime, accumulating one server per played remote file.
      stopMediaStreams();
    }
    super.dispose();
  }

  /// The bundled controls already seek; they just lack a rate menu. Both
  /// themes are installed because `AdaptiveVideoControls` picks one by
  /// platform, and fullscreen inherits whichever was active.
  Widget _withSpeedControls(Widget child) {
    // Each theme data gets its own instance: normal and fullscreen controls can
    // be mounted at the same time, and one widget instance cannot be.
    Widget speedButton() => _SpeedButton(
          player: _player,
          currentRate: _playbackSpeed,
          onSelected: _setSpeed,
        );
    Widget nextButton() => widget.playlist.length > 1
        ? IconButton(
            icon: Icon(
              Icons.skip_next,
              color: _hasNext ? Colors.white : Colors.white38,
            ),
            tooltip: 'Next episode (N)',
            onPressed: _hasNext ? () => _openTrack(_index + 1) : null,
          )
        : const SizedBox.shrink();
    final mobileNormal = kDefaultMaterialVideoControlsThemeData.copyWith(
      // Not enabled by default in non-fullscreen. The page used to wrap the
      // video in its own drag handler, but the controls' recognizer is deeper
      // in the tree and always won the gesture arena, so it never fired.
      seekGesture: true,
      volumeGesture: true,
      brightnessGesture: true,
      bottomButtonBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        bottom: 24.0,
      ),
      seekBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: 84.0,
      ),
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeData.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final mobileFullscreen = kDefaultMaterialVideoControlsThemeDataFullscreen
        .copyWith(
      seekGesture: true,
      volumeGesture: true,
      brightnessGesture: true,
      bottomButtonBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
        bottom: 36.0,
      ),
      seekBarMargin: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        bottom: 96.0,
      ),
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeDataFullscreen.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final desktopNormal = kDefaultMaterialDesktopVideoControlsThemeData
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeData.bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );
    final desktopFullscreen = kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
            .bottomButtonBar,
        nextButton(),
        speedButton(),
      ],
    );

    return MaterialVideoControlsTheme(
      normal: mobileNormal,
      fullscreen: mobileFullscreen,
      child: MaterialDesktopVideoControlsTheme(
        normal: desktopNormal,
        fullscreen: desktopFullscreen,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSwipeBack(
      child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          _player.playOrPause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          _seekRelative(-5);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          _seekRelative(5);
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          _changeVolume(10);
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          _changeVolume(-10);
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          _toggleMute();
        },
        const SingleActivator(LogicalKeyboardKey.keyF): () {
          _videoKey.currentState?.toggleFullscreen();
        },
        const SingleActivator(LogicalKeyboardKey.keyN): () {
          if (_hasNext) _openTrack(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (_hasPrev) _openTrack(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekRelative(-10),
        const SingleActivator(LogicalKeyboardKey.keyL): () => _seekRelative(10),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _player.playOrPause(),
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () {
          _cycleSpeed(increase: false);
        },
        const SingleActivator(LogicalKeyboardKey.bracketRight): () {
          _cycleSpeed(increase: true);
        },
        const SingleActivator(LogicalKeyboardKey.backslash): () {
          _setSpeed(1.0);
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            _saveResumePosition();
            _player.stop();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () async {
                  _saveResumePosition();
                  await _player.stop();
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              iconTheme: const IconThemeData(color: Colors.white),
              actionsIconTheme: const IconThemeData(color: Colors.white),
              title: Text(_track.fileName, overflow: TextOverflow.ellipsis),
              actions: [
                if (widget.playlist.length > 1) ...[
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    tooltip: 'Playlist (${_index + 1}/${widget.playlist.length})',
                    onPressed: _showPlaylist,
                  ),
                  IconButton(
                    icon: Icon(_autoNext ? Icons.playlist_play : Icons.playlist_remove),
                    tooltip: _autoNext ? 'Auto-next: On' : 'Auto-next: Off',
                    color: _autoNext ? Colors.blueAccent : Colors.white60,
                    onPressed: () {
                      setState(() {
                        _autoNext = !_autoNext;
                        PreferencesService.instance.setBool(_prefAutoNext, _autoNext);
                      });
                    },
                  ),
                ],
                IconButton(
                  icon: Icon(_isLooping ? Icons.repeat_one : Icons.repeat),
                  tooltip: _isLooping ? 'Loop: Single' : 'Loop: Off',
                  color: _isLooping ? Colors.blueAccent : Colors.white,
                  onPressed: () {
                    setState(() {
                      _isLooping = !_isLooping;
                      _player.setPlaylistMode(
                        _isLooping ? PlaylistMode.single : PlaylistMode.none,
                      );
                      PreferencesService.instance.setBool(_prefLoop, _isLooping);
                    });
                  },
                ),
                _SpeedButton(
                  player: _player,
                  currentRate: _playbackSpeed,
                  onSelected: _setSpeed,
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Fullscreen (F)',
                  onPressed: () {
                    _videoKey.currentState?.toggleFullscreen();
                  },
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
                          PreferencesService.instance.setBool(_prefAutoNext, _autoNext);
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
                                : (_volume < 50 ? Icons.volume_down : Icons.volume_up),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(_volume == 0 ? 'Unmute (M)' : 'Mute (M) (${_volume.toInt()}%)'),
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
                              _autoNext ? Icons.playlist_play : Icons.playlist_remove,
                              size: 20,
                              color: _autoNext ? Colors.blueAccent : null,
                            ),
                            const SizedBox(width: 10),
                            Text(_autoNext ? 'Auto-next (On)' : 'Auto-next (Off)'),
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
            ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.redAccent),
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
                      style: const TextStyle(
                          fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          : !_opened
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPressStart: _onLongPressStart,
                      onLongPressEnd: _onLongPressEnd,
                      child: _withSpeedControls(
                        Video(
                          key: _videoKey,
                          controller: _controller,
                          fill: Colors.black,
                          controls: AdaptiveVideoControls,
                          pauseUponEnteringBackgroundMode: false,
                          resumeUponEnteringForegroundMode: false,
                        ),
                      ),
                    ),
                    if (_isSpeedBoosting)
                      Positioned(
                        top: 64,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
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
                                const Icon(
                                  Icons.fast_forward,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_boostRate.toInt()}X Fast Forward',
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
                      ),
                    if (_hudSpeed != null && !_isSpeedBoosting)
                      Positioned(
                        top: 64,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
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
                                  '${_hudSpeed == _hudSpeed!.roundToDouble() ? _hudSpeed!.toInt() : _hudSpeed}× 播放速度',
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
                      ),
                    if (_track.isAudio)
                      Positioned(
                        top: 24,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Column(
                            children: [
                              Icon(Icons.audiotrack,
                                  size: 72,
                                  color: Colors.white.withValues(alpha: 0.25)),
                              const SizedBox(height: 8),
                              Text(
                                _track.fileName,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Playback speed menu: 0.5× through 8×.
class _SpeedButton extends StatefulWidget {
  final Player player;
  final double currentRate;
  final ValueChanged<double>? onSelected;

  const _SpeedButton({
    required this.player,
    this.currentRate = 1.0,
    this.onSelected,
  });

  @override
  State<_SpeedButton> createState() => _SpeedButtonState();
}

class _SpeedButtonState extends State<_SpeedButton> {
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0, 8.0];
  static const _prefSpeed = 'player.speed';

  late double _rate;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _rate = widget.currentRate;
    final saved = double.tryParse(
      PreferencesService.instance.getString(_prefSpeed) ?? '',
    );
    if (saved != null && _rates.contains(saved)) {
      _rate = saved;
    }
    _sub = widget.player.stream.rate.listen((rate) {
      if (mounted) setState(() => _rate = rate);
    });
  }

  @override
  void didUpdateWidget(covariant _SpeedButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentRate != widget.currentRate) {
      _rate = widget.currentRate;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _label(double rate) {
    final text = rate == rate.roundToDouble()
        ? rate.toInt().toString()
        : rate.toString();
    return '$text×';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: _rate,
      onSelected: (rate) async {
        setState(() => _rate = rate);
        widget.onSelected?.call(rate);
        await widget.player.setRate(rate);
        PreferencesService.instance.setString(_prefSpeed, rate.toString());
      },
      itemBuilder: (context) => [
        for (final rate in _rates)
          PopupMenuItem<double>(
            value: rate,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _label(rate),
                    style: TextStyle(
                      fontWeight:
                          rate == _rate ? FontWeight.bold : FontWeight.normal,
                      color: rate == _rate
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ),
                if (rate == _rate)
                  Icon(
                    Icons.check,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          _label(_rate),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
