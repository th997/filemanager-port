import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../rust/api/servers.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';

/// Video and audio playback for local, remote, and archive files.
///
/// Native files are opened directly. Anything else is served over a loopback
/// HTTP endpoint with Range support, so seeking works without downloading the
/// whole file first.
class MediaPlayerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;
  final bool isAudio;

  const MediaPlayerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    required this.isAudio,
  });

  @override
  State<MediaPlayerPage> createState() => _MediaPlayerPageState();
}

class _MediaPlayerPageState extends State<MediaPlayerPage> {
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _volumeSub;
  String? _error;
  bool _opened = false;
  bool _startedStream = false;
  bool _isLooping = false;
  static const _prefVolume = 'player.volume';
  static const _prefLoop = 'player.loop';
  static const _prefResumePrefix = 'player.resume.';
  /// Where playback was when the page closed, keyed by the opened file.
  String get _resumeKey => '$_prefResumePrefix${widget.root}|${widget.path}';
  bool _resumeApplied = false;
  StreamSubscription<Duration>? _resumeSub;
  double _volume = 100.0;
  double _lastNonZeroVolume = 100.0;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        hwdec: Platform.isLinux ? 'no' : null,
        enableHardwareAcceleration: !Platform.isLinux,
      ),
    );
    _volume = _player.state.volume;
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
    _volumeSub = _player.stream.volume.listen((vol) {
      if (mounted) setState(() => _volume = vol);
    });
    _errorSub = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    _open();
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
    final target = pos < Duration.zero ? Duration.zero : (pos > duration ? duration : pos);
    _player.seek(target);
  }


  Future<void> _open() async {
    try {
      final String uri;
      final native = joinNative(widget.root, widget.path);
      if (isNativeRoot(widget.root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
      } else {
        final base = (await startMediaStream(root: widget.root))
            .replaceFirst(RegExp(r'/$'), '');
        _startedStream = true;
        final encoded = widget.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        uri = '$base/$encoded';
      }
      await _player.open(Media(uri));
      if (mounted) setState(() => _opened = true);
      _applyResume();
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
  Future<void> _retry() async {
    await _player.stop();
    if (mounted) {
      setState(() {
        _error = null;
        _opened = false;
      });
    }
    await _open();
  }

  @override
  void dispose() {
    _saveResumePosition();
    _resumeSub?.cancel();
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
    Widget speedButton() => _SpeedButton(player: _player);
    final mobileNormal = kDefaultMaterialVideoControlsThemeData.copyWith(
      // Not enabled by default in non-fullscreen. The page used to wrap the
      // video in its own drag handler, but the controls' recognizer is deeper
      // in the tree and always won the gesture arena, so it never fired.
      seekGesture: true,
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeData.bottomButtonBar,
        speedButton(),
      ],
    );
    final mobileFullscreen = kDefaultMaterialVideoControlsThemeDataFullscreen
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialVideoControlsThemeDataFullscreen.bottomButtonBar,
        speedButton(),
      ],
    );
    final desktopNormal = kDefaultMaterialDesktopVideoControlsThemeData
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeData.bottomButtonBar,
        speedButton(),
      ],
    );
    final desktopFullscreen = kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
        .copyWith(
      bottomButtonBar: [
        ...kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
            .bottomButtonBar,
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
    return CallbackShortcuts(
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
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekRelative(-10),
        const SingleActivator(LogicalKeyboardKey.keyL): () => _seekRelative(10),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _player.playOrPause(),
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            _player.stop();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  await _player.stop();
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                },
              ),
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  tooltip: 'Rewind 10s (←)',
                  onPressed: () => _seekRelative(-10),
                ),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  tooltip: 'Forward 10s (→)',
                  onPressed: () => _seekRelative(10),
                ),
                IconButton(
                  icon: Icon(
                    _volume == 0
                        ? Icons.volume_off
                        : (_volume < 50 ? Icons.volume_down : Icons.volume_up),
                  ),
                  tooltip: _volume == 0
                      ? 'Unmute (M)'
                      : 'Mute (M) (${_volume.toInt()}%)',
                  onPressed: _toggleMute,
                ),
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
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Fullscreen (F)',
                  onPressed: () {
                    _videoKey.currentState?.toggleFullscreen();
                  },
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
                    _withSpeedControls(
                      Video(
                        key: _videoKey,
                        controller: _controller,
                        fill: Colors.black,
                        controls: AdaptiveVideoControls,
                      ),
                    ),
                    if (widget.isAudio)
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
                                widget.fileName,
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
    );
  }
}

/// Playback speed menu: 0.5× through 8×.
class _SpeedButton extends StatefulWidget {
  final Player player;

  const _SpeedButton({required this.player});

  @override
  State<_SpeedButton> createState() => _SpeedButtonState();
}

class _SpeedButtonState extends State<_SpeedButton> {
  static const _rates = [0.5, 1.0, 1.5, 2.0, 4.0, 8.0];
  static const _prefSpeed = 'player.speed';

  double _rate = 1.0;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _rate = widget.player.state.rate;
    final saved = double.tryParse(
      PreferencesService.instance.getString(_prefSpeed) ?? '',
    );
    if (saved != null && _rates.contains(saved)) {
      _rate = saved;
      widget.player.setRate(saved);
    }
    _sub = widget.player.stream.rate.listen((rate) {
      if (mounted) setState(() => _rate = rate);
    });
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
      onSelected: (rate) {
        widget.player.setRate(rate);
        PreferencesService.instance.setString(_prefSpeed, rate.toString());
      },
      itemBuilder: (context) => [
        for (final rate in _rates)
          PopupMenuItem<double>(
            value: rate,
            child: Text(
              _label(rate),
              style: TextStyle(
                fontWeight:
                    rate == _rate ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
