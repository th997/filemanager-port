import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../rust/api/servers.dart';
import '../services/path_utils.dart';

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
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<double>? _volumeSub;
  String? _error;
  bool _opened = false;
  bool _isLooping = false;
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
  }

  void _changeVolume(double delta) {
    final newVol = (_volume + delta).clamp(0.0, 100.0);
    _player.setVolume(newVol);
    if (newVol > 0) _lastNonZeroVolume = newVol;
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
        final encoded = widget.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        uri = '$base/$encoded';
      }
      await _player.open(Media(uri));
      if (mounted) setState(() => _opened = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _volumeSub?.cancel();
    _player.stop();
    _player.dispose();
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
                    });
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

  double _rate = 1.0;
  StreamSubscription<double>? _sub;

  @override
  void initState() {
    super.initState();
    _rate = widget.player.state.rate;
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
      onSelected: (rate) => widget.player.setRate(rate),
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
