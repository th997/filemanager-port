import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/file_picker_dialog.dart';
import '../rust/api/servers.dart';
import '../services/global_playback_service.dart';
import '../services/native_pip_service.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../services/subtitle_service.dart';
import '../services/vault_service.dart';
import '../widgets/app_swipe_back.dart';
import '../widgets/media_player/media_player_controls.dart';
import '../widgets/media_player/media_player_hud.dart';
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
  bool _isExplicitlyClosed = false;
  bool _fallbackScheduled = false;
  Timer? _controlsTimer;
  LoadedSubtitle? _externalSubtitle;
  bool _subtitlesEnabled = true;
  List<EmbeddedSubtitleTrack> _embeddedSubtitles = const [];
  int? _activeEmbeddedSubtitleIndex;

  static const _prefVolume = 'player.volume';
  static const _prefLoop = 'player.loop';
  static const _prefAutoNext = 'player.auto_next';
  static const _prefSpeed = 'player.speed';
  static const _prefResumePrefix = 'player.resume.';
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0];

  late int _index;
  bool _switching = false;
  int _openGeneration = 0;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;
  double _lastNonZeroVolume = 1.0;

  // Swipe gesture state
  bool _isDraggingSeek = false;
  Duration _dragSeekStartPos = Duration.zero;
  Duration _dragSeekTarget = Duration.zero;
  int _dragSeekDeltaSec = 0;
  double _dragSeekAccumulatedDx = 0.0;

  bool _isDraggingBrightness = false;
  double _dragBrightnessLevel = 0.5;
  Timer? _brightnessHudTimer;

  bool _isDraggingVolume = false;
  double _dragVolumeLevel = 1.0;
  Timer? _volumeHudTimer;

  // Double-tap seek HUD state
  int? _doubleTapSeekSeconds;
  Timer? _doubleTapHudTimer;

  // Long-press speed boost state
  bool _isSpeedBoosting = false;
  double _preBoostSpeed = 1.0;
  double _boostRate = 2.0;

  // Speed change HUD state
  Timer? _speedHudTimer;
  double? _hudSpeed;

  BoxFit _videoFit = BoxFit.contain;

  void _cycleVideoFit() {
    HapticFeedback.lightImpact();
    setState(() {
      _videoFit = nextPlayerVideoFit(_videoFit);
    });
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.videoFitChanged(playerVideoFitLabel(l10n, _videoFit))),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showSleepTimerDialog() {
    showPlayerSleepTimerSheet(
      context,
      onEndOfTrackSelected: () {
        if (_isLooping) {
          _isLooping = false;
          _controller?.setLooping(false);
          PreferencesService.instance.setBool(_prefLoop, false);
        }
      },
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  static const _nowPlayingChannel =
      MethodChannel('com.github.th997.filemanager/now_playing');
  bool? _lastNowPlayingIsPlaying;
  int _lastNowPlayingSec = -1;
  double _lastNowPlayingDuration = -1;
  double _lastNowPlayingRate = -1;

  DateTime? _bufferingStartTime;
  Duration? _bufferingLastPos;
  bool _isRecoveringStall = false;

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

  bool _vaultAutoClosing = false;

  void _onVaultChanged() {
    final vid = vaultIdFromRoot(widget.root);
    if (vid == null || VaultService.instance.isUnlocked(vid)) return;
    if (!_isExplicitlyClosed) {
      _isExplicitlyClosed = true;
      _openGeneration++;
      final c = _controller;
      final ownedByService =
          c != null && identical(GlobalPlaybackService.instance.videoPlayerController, c);
      final streamOwnedByService = GlobalPlaybackService.instance.startedStream;
      GlobalPlaybackService.instance.stop();
      if (c != null && !ownedByService) {
        _controller = null;
        try {
          c.removeListener(_onControllerUpdate);
        } catch (_) {}
        try {
          c.pause().catchError((_) {});
        } catch (_) {}
        try {
          c.dispose().catchError((_) {});
        } catch (_) {}
      }
      if (_startedStream && !streamOwnedByService) {
        _startedStream = false;
        stopMediaStreams();
      }
    }
    if (!_vaultAutoClosing && mounted) {
      _vaultAutoClosing = true;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isFirst) {
        Navigator.of(context).removeRoute(route);
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VaultService.instance.addListener(_onVaultChanged);
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

    final session = GlobalPlaybackService.instance;
    if (session.hasActiveSession &&
        session.currentRoot == widget.root &&
        session.currentPath == _track.path &&
        session.videoPlayerController != null) {
      _controller = session.videoPlayerController;
      _initialized = _controller!.value.isInitialized;
      _startedStream = session.startedStream;
      _index = session.currentIndex;
      _playbackSpeed = session.playbackSpeed;
      _controller!.addListener(_onControllerUpdate);
      session.setFullScreen(true);
      _resetControlsTimer();
    } else {
      if (session.hasActiveSession) {
        session.stop();
      }
      _openCurrentTrack();
      _resetControlsTimer();
    }

    if (Platform.isIOS) {
      _nowPlayingChannel.setMethodCallHandler(_handleNowPlayingMethodCall);
    }
    ScreenBrightness.instance.application.then((val) {
      if (mounted) _dragBrightnessLevel = val;
    }).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    GlobalPlaybackService.instance.setPrivacyMediaLabels(
      audio: l10n.privacyMediaAudio,
      video: l10n.privacyMediaVideo,
    );
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
    final gen = ++_openGeneration;
    final track = _track;
    final index = _index;
    _controlsTimer?.cancel();
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      // Detach from the service first: hasActiveSession() reads the
      // controller's value and would throw on a disposed controller.
      GlobalPlaybackService.instance.detachIosSessionController(oldController);
      oldController.removeListener(_onControllerUpdate);
      await oldController.dispose();
    }

    if (!mounted || gen != _openGeneration) return;
    setState(() {
      _initialized = false;
      _error = null;
      _embeddedSubtitles = const [];
      _activeEmbeddedSubtitleIndex = null;
    });

    VideoPlayerController? controller;
    try {
      final String uri;
      final native = joinNative(widget.root, track.path);
      if (isNativeRoot(widget.root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
        controller = VideoPlayerController.file(
          File(native),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: true,
          ),
        );
      } else {
        final base = (await startMediaStream(root: widget.root))
            .replaceFirst(RegExp(r'/$'), '');
        if (!mounted || gen != _openGeneration) {
          if (!GlobalPlaybackService.instance.hasActiveSession) {
            stopMediaStreams();
          }
          return;
        }
        _startedStream = true;
        final encoded = track.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        final bufferMb = PreferencesService.instance.bufferSizeMb;
        uri = '$base/$encoded?buffer_mb=$bufferMb';
        controller = VideoPlayerController.networkUrl(
          Uri.parse(uri),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: true,
          ),
        );
      }

      await controller.initialize();
      if (!mounted || gen != _openGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      controller.addListener(_onControllerUpdate);
      if (!track.isAudio) {
        unawaited(_autoLoadExternalSubtitle(gen));
        unawaited(_loadEmbeddedSubtitles(gen));
      }

      GlobalPlaybackService.instance.setIosSession(
        root: widget.root,
        path: track.path,
        fileName: track.fileName,
        isAudio: track.isAudio,
        playlist: widget.playlist,
        currentIndex: index,
        controller: controller,
        startedStream: _startedStream,
        playbackSpeed: _playbackSpeed,
      );

      if (Platform.isIOS) {
        _nowPlayingChannel.invokeMethod('setBufferDuration', {
          'seconds': PreferencesService.instance.bufferDurationSec.toDouble(),
        }).catchError((_) {});
      }

      await controller.setLooping(_isLooping);
      await controller.setPlaybackSpeed(_playbackSpeed);
      await controller.setVolume(_volume);
      if (!mounted || gen != _openGeneration) return;

      await _applyResume();
      if (!mounted || gen != _openGeneration) return;

      await controller.play();
      WakelockPlus.enable().catchError((_) {});

      if (mounted && gen == _openGeneration) {
        setState(() {
          _initialized = true;
        });
        _resetControlsTimer();
        _updateNowPlaying(force: true);
      }
    } catch (e) {
      if (controller != null && !identical(_controller, controller)) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
      if (mounted &&
          gen == _openGeneration &&
          controller != null &&
          _shouldAutoFallbackToMediaKit(e)) {
        _handoffToMediaKit(track, index, instant: true);
        return;
      }
      if (mounted && gen == _openGeneration) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _applyResume() async {
    if (vaultIdFromRoot(widget.root) != null) return;
    if (_controller == null) return;
    final saved = int.tryParse(
      PreferencesService.instance.getString(_resumeKey) ?? '',
    );
    if (saved == null || saved < 5000) return;
    final dur = _controller!.value.duration;
    if (dur > Duration.zero && saved < dur.inMilliseconds * 0.95) {
      await _controller!.seekTo(Duration(milliseconds: saved));
    }
  }

  void _saveResumePosition() {
    if (vaultIdFromRoot(widget.root) != null) return;
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
      if (!_isExplicitlyClosed &&
          !_fallbackScheduled &&
          (!_initialized || val.position < const Duration(seconds: 3))) {
        final vid = vaultIdFromRoot(widget.root);
        if (vid == null || VaultService.instance.isUnlocked(vid)) {
          _fallbackScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handoffToMediaKit(_track, _index, instant: true);
          });
          return;
        }
      }
      setState(() {
        _error = val.errorDescription ?? (mounted ? AppLocalizations.of(context).unknownPlaybackError : 'Unknown playback error');
      });
      return;
    }

    // Auto-advance or sleep timer on natural finish
    if (_initialized &&
        !_switching &&
        !_isLooping &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 300) &&
        !val.isPlaying) {
      if (GlobalPlaybackService.instance.consumeEndOfTrackSleepTimer()) {
        _controller?.pause();
        setState(() {});
        return;
      }
      if (_autoNext && _hasNext) {
        _switching = true;
        _saveResumePosition();
        final nextTrack = widget.playlist[_index + 1];
        _openTrack(_index + 1);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).autoPlayingNext(nextTrack.fileName)),
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

    // Auto-recover if stream stalled in buffering state for >= 3s
    if (_initialized && val.isBuffering && val.isPlaying) {
      if (_bufferingStartTime == null || _bufferingLastPos != val.position) {
        _bufferingStartTime = DateTime.now();
        _bufferingLastPos = val.position;
      } else if (!_isRecoveringStall &&
          DateTime.now().difference(_bufferingStartTime!).inSeconds >= 3) {
        _isRecoveringStall = true;
        _bufferingStartTime = DateTime.now();
        final currentPos = val.position;
        _controller!.seekTo(currentPos).then((_) {
          _controller?.play();
          _isRecoveringStall = false;
        }).catchError((_) {
          _isRecoveringStall = false;
        });
      }
    } else {
      _bufferingStartTime = null;
      _bufferingLastPos = null;
      _isRecoveringStall = false;
    }

    if (_initialized && _controller != null) {
      _updateNowPlaying();
    }

    setState(() {});
  }

  bool _shouldAutoFallbackToMediaKit(Object error) {
    if (_isExplicitlyClosed || _fallbackScheduled || !mounted) return false;
    final vid = vaultIdFromRoot(widget.root);
    if (vid != null && !VaultService.instance.isUnlocked(vid)) return false;
    if (error is PlatformException) return true;
    final msg = error.toString();
    return msg.contains('VideoError') ||
        msg.contains('OSStatus') ||
        msg.contains('CoreMediaErrorDomain') ||
        msg.contains('AVFoundationErrorDomain');
  }

  void _handoffToMediaKit(
    MediaTrack targetTrack,
    int targetIndex, {
    bool instant = false,
  }) {
    if (_isExplicitlyClosed || !mounted) return;
    final vid = vaultIdFromRoot(widget.root);
    if (vid != null && !VaultService.instance.isUnlocked(vid)) return;

    _isExplicitlyClosed = true;
    _fallbackScheduled = true;
    _openGeneration++;
    final c = _controller;
    final ownedByService = c != null &&
        identical(GlobalPlaybackService.instance.videoPlayerController, c);
    final streamOwnedByService = GlobalPlaybackService.instance.startedStream;
    GlobalPlaybackService.instance.stop();
    _controller = null;
    if (c != null && !ownedByService) {
      try {
        c.removeListener(_onControllerUpdate);
      } catch (_) {}
      try {
        c.pause().catchError((_) {});
      } catch (_) {}
      try {
        c.dispose().catchError((_) {});
      } catch (_) {}
    }
    if (_startedStream && !streamOwnedByService) {
      _startedStream = false;
      stopMediaStreams();
    } else {
      _startedStream = false;
    }
    if (!mounted) return;
    final targetPage = MediaPlayerPage(
      root: widget.root,
      path: targetTrack.path,
      fileName: targetTrack.fileName,
      isAudio: targetTrack.isAudio,
      playlist: widget.playlist,
      startIndex: targetIndex,
      forceMediaKit: true,
    );
    final route = instant
        ? PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => targetPage,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          )
        : MaterialPageRoute<void>(builder: (_) => targetPage);
    Navigator.of(context).pushReplacement(route);
  }

  Future<void> _openTrack(int index) async {
    if (index < 0 || index >= widget.playlist.length) return;
    _saveResumePosition();
    final nextTrack = widget.playlist[index];
    if (!MediaPlayerPage.isAppleNativeFormat(nextTrack.path)) {
      _handoffToMediaKit(nextTrack, index);
      return;
    }
    _switching = true;
    setState(() {
      _index = index;
      _error = null;
      _initialized = false;
    });
    try {
      await _openCurrentTrack();
    } finally {
      if (index == _index) {
        _switching = false;
      }
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
    _updateNowPlaying(force: true);
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
    _updateNowPlaying(force: true);
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
    // Mute is transient: persist the unmuted level so the next session
    // does not start silent (matches desktop behavior).
    final saved = _volume > 0 ? _volume : _lastNonZeroVolume;
    PreferencesService.instance.setString(
      _prefVolume,
      (saved * 100).toInt().toString(),
    );
    setState(() {});
  }

  void _setSpeed(double speed) {
    if (_controller == null) return;
    _isSpeedBoosting = false;
    _playbackSpeed = speed;
    _controller!.setPlaybackSpeed(speed);
    PreferencesService.instance.setString(_prefSpeed, speed.toString());
    GlobalPlaybackService.instance.setPlaybackSpeed(speed);
    _showSpeedHud(speed);
    _updateNowPlaying(force: true);
    setState(() {});
    _resetControlsTimer();
  }

  Future<dynamic> _handleNowPlayingMethodCall(MethodCall call) async {
    if (!mounted || _controller == null) return;
    switch (call.method) {
      case 'onRemoteCommand':
        final arg = call.arguments;
        if (arg == 'play') {
          if (!_controller!.value.isPlaying) {
            _controller!.play();
            _updateNowPlaying(force: true);
          }
        } else if (arg == 'pause') {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
            _updateNowPlaying(force: true);
          }
        } else if (arg == 'togglePlayPause') {
          _togglePlayPause();
        } else if (arg == 'forward10') {
          _seekRelative(10);
        } else if (arg == 'rewind10') {
          _seekRelative(-10);
        } else if (arg == 'next') {
          if (_hasNext) _openTrack(_index + 1);
        } else if (arg == 'prev') {
          if (_hasPrev) _openTrack(_index - 1);
        } else if (arg is Map && arg.containsKey('seek')) {
          final target = (arg['seek'] as num).toDouble();
          _controller!.seekTo(Duration(milliseconds: (target * 1000).toInt()));
          _updateNowPlaying(force: true);
        }
        break;
    }
  }

  void _updateNowPlaying({bool force = false}) {
    if (!Platform.isIOS || _controller == null || !_controller!.value.isInitialized) return;
    final val = _controller!.value;
    final isPlaying = val.isPlaying;
    final posSec = val.position.inSeconds;
    final durationSec = val.duration.inMilliseconds / 1000.0;
    final currentRate = isPlaying ? _playbackSpeed : 0.0;

    if (!force &&
        _lastNowPlayingIsPlaying == isPlaying &&
        _lastNowPlayingDuration == durationSec &&
        _lastNowPlayingRate == currentRate &&
        (posSec - _lastNowPlayingSec).abs() < 5) {
      return;
    }
    _lastNowPlayingIsPlaying = isPlaying;
    _lastNowPlayingSec = posSec;
    _lastNowPlayingDuration = durationSec;
    _lastNowPlayingRate = currentRate;

    _nowPlayingChannel.invokeMethod('update', {
      'title': GlobalPlaybackService.instance.redactedNowPlayingTitle(
        root: widget.root,
        fileName: _track.fileName,
        isAudio: widget.isAudio,
      ),
      'duration': durationSec,
      'position': val.position.inMilliseconds / 1000.0,
      'rate': currentRate,
      'isAudio': widget.isAudio,
      'hasNext': _hasNext,
      'hasPrev': _hasPrev,
    }).catchError((_) {});
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
        SystemChrome.setPreferredOrientations(const []);
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

  // Horizontal seek gesture handlers
  void _onHorizontalDragStart(DragStartDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controlsTimer?.cancel();
    setState(() {
      _isDraggingSeek = true;
      _dragSeekStartPos = _controller!.value.position;
      _dragSeekTarget = _dragSeekStartPos;
      _dragSeekDeltaSec = 0;
      _dragSeekAccumulatedDx = 0.0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDraggingSeek ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }
    _dragSeekAccumulatedDx += details.primaryDelta ?? 0.0;

    final screenWidth = MediaQuery.of(context).size.width;
    final dur = _controller!.value.duration;
    final double maxDragSeconds;
    if (dur > const Duration(minutes: 30)) {
      maxDragSeconds = 300.0;
    } else if (dur > const Duration(minutes: 10)) {
      maxDragSeconds = 180.0;
    } else {
      maxDragSeconds = 90.0;
    }

    final deltaSec =
        (_dragSeekAccumulatedDx / screenWidth * maxDragSeconds).round();
    final targetMs = (_dragSeekStartPos.inMilliseconds + deltaSec * 1000)
        .clamp(0, dur.inMilliseconds);

    setState(() {
      _dragSeekDeltaSec = deltaSec;
      _dragSeekTarget = Duration(milliseconds: targetMs);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isDraggingSeek) return;
    if (_controller != null && _controller!.value.isInitialized) {
      _controller!.seekTo(_dragSeekTarget);
    }
    setState(() {
      _isDraggingSeek = false;
    });
    _resetControlsTimer();
  }

  // Vertical drag: left = brightness, right = volume
  void _onVerticalDragStart(DragStartDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controlsTimer?.cancel();
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < screenWidth / 2) {
      _brightnessHudTimer?.cancel();
      _isDraggingBrightness = true;
      _isDraggingVolume = false;
      ScreenBrightness.instance.application.then((val) {
        if (mounted) _dragBrightnessLevel = val;
      }).catchError((_) {});
      setState(() {});
    } else {
      _volumeHudTimer?.cancel();
      _isDraggingVolume = true;
      _isDraggingBrightness = false;
      _dragVolumeLevel = _volume;
      setState(() {});
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_controller == null) return;
    final delta = -(details.primaryDelta ?? 0.0) / 250.0;
    if (_isDraggingBrightness) {
      _dragBrightnessLevel = (_dragBrightnessLevel + delta).clamp(0.0, 1.0);
      ScreenBrightness.instance
          .setApplicationScreenBrightness(_dragBrightnessLevel)
          .catchError((_) {});
      setState(() {});
    } else if (_isDraggingVolume) {
      _dragVolumeLevel = (_dragVolumeLevel + delta).clamp(0.0, 1.0);
      _volume = _dragVolumeLevel;
      if (_volume > 0) {
        _lastNonZeroVolume = _volume;
      }
      _controller!.setVolume(_volume);
      setState(() {});
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isDraggingBrightness) {
      _brightnessHudTimer?.cancel();
      _brightnessHudTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() => _isDraggingBrightness = false);
        }
      });
    }
    if (_isDraggingVolume) {
      PreferencesService.instance.setString(
        _prefVolume,
        (_volume * 100).toInt().toString(),
      );
      _volumeHudTimer?.cancel();
      _volumeHudTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() => _isDraggingVolume = false);
        }
      });
    }
    _resetControlsTimer();
  }

  // Long-press speed boost handlers
  void _onLongPressStart(LongPressStartDetails details) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        !_controller!.value.isPlaying) {
      return;
    }
    HapticFeedback.mediumImpact();
    _preBoostSpeed = _playbackSpeed;
    _boostRate = _preBoostSpeed >= 2.0 ? 3.0 : 2.0;
    _controller!.setPlaybackSpeed(_boostRate);
    setState(() {
      _isSpeedBoosting = true;
    });
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isSpeedBoosting) return;
    HapticFeedback.lightImpact();
    _controller?.setPlaybackSpeed(_preBoostSpeed);
    setState(() {
      _isSpeedBoosting = false;
    });
  }

  void _onLongPressCancel() {
    if (!_isSpeedBoosting) return;
    _controller?.setPlaybackSpeed(_preBoostSpeed);
    setState(() {
      _isSpeedBoosting = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resetControlsTimer();
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.setPlaybackSpeed(_playbackSpeed);
        _updateNowPlaying(force: true);
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_controller != null && _controller!.value.isInitialized) {
        _updateNowPlaying(force: true);
      }
    }
  }

  void _closeAndExit() {
    _isExplicitlyClosed = true;
    _openGeneration++;
    _saveResumePosition();
    final c = _controller;
    final ownedByService =
        c != null && identical(GlobalPlaybackService.instance.videoPlayerController, c);
    final streamOwnedByService = GlobalPlaybackService.instance.startedStream;
    GlobalPlaybackService.instance.stop();
    if (c != null && !ownedByService) {
      _controller = null;
      try {
        c.removeListener(_onControllerUpdate);
      } catch (_) {}
      try {
        c.pause().catchError((_) {});
      } catch (_) {}
      try {
        c.dispose().catchError((_) {});
      } catch (_) {}
    }
    if (_startedStream && !streamOwnedByService) {
      _startedStream = false;
      stopMediaStreams();
    }
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _volumeHudTimer?.cancel();
    _brightnessHudTimer?.cancel();
    _doubleTapHudTimer?.cancel();
    _speedHudTimer?.cancel();
    ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    WakelockPlus.disable().catchError((_) {});
    if (!_isExplicitlyClosed) {
      _saveResumePosition();
    }

    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }

    if (_isExplicitlyClosed) {
      // _closeAndExit() already handed the controller to
      // GlobalPlaybackService.stop(), which disposed it and stopped the
      // loopback stream. Touching them again here would double-dispose.
      final c = _controller;
      _controller = null;
      if (c != null) {
        try {
          c.removeListener(_onControllerUpdate);
        } catch (_) {}
      }
      _startedStream = false;
    } else if (!GlobalPlaybackService.instance.hasActiveSession) {
      final c = _controller;
      _controller = null;
      if (c != null) {
        try {
          c.removeListener(_onControllerUpdate);
        } catch (_) {}
        try {
          c.pause().catchError((_) {});
        } catch (_) {}
        try {
          c.dispose().catchError((_) {});
        } catch (_) {}
      }

      if (_startedStream) {
        try {
          stopMediaStreams();
        } catch (_) {}
        _startedStream = false;
      }
      // stop() clears the now-playing info and re-registers the global
      // handler; clearing the channel here would race with that.
      GlobalPlaybackService.instance.stop();
    } else {
      // Minimize: keep playback running in background/mini player. Hand the
      // remote-command handler back to the service — leaving it pointing at
      // this disposed State made lock-screen controls silently stop working.
      _controller?.removeListener(_onControllerUpdate);
      if (Platform.isIOS) {
        GlobalPlaybackService.instance.initNowPlayingHandler();
      }
      GlobalPlaybackService.instance.setFullScreen(false);
    }
    super.dispose();
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
          child: Theme(
            data: ThemeData.dark(),
            child: Scaffold(
              backgroundColor: Colors.black,
            appBar: _showControls || !_isFullscreen
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: AppLocalizations.of(context).minimize,
                      onPressed: () async {
                        _saveResumePosition();
                        if (context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    iconTheme: const IconThemeData(color: Colors.white),
                    actionsIconTheme: const IconThemeData(color: Colors.white),
                    title: Text(
                      _track.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      if (widget.playlist.length > 1) ...[
                        IconButton(
                          icon: const Icon(Icons.queue_music, color: Colors.white),
                          tooltip:
                              AppLocalizations.of(context).playlistProgress(_index + 1, widget.playlist.length),
                          onPressed: _showPlaylist,
                        ),
                        IconButton(
                          icon: Icon(
                            _autoNext
                                ? Icons.playlist_play
                                : Icons.playlist_remove,
                            color: _autoNext ? Colors.blueAccent : Colors.white70,
                          ),
                          tooltip:
                              _autoNext ? AppLocalizations.of(context).autoNextOn : AppLocalizations.of(context).autoNextOff,
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
                        icon: Icon(
                          _isLooping ? Icons.repeat_one : Icons.repeat,
                          color: _isLooping ? Colors.blueAccent : Colors.white,
                        ),
                        tooltip: _isLooping ? AppLocalizations.of(context).loopSingle : AppLocalizations.of(context).loopOff,
                        onPressed: () {
                          setState(() {
                            _isLooping = !_isLooping;
                            _controller?.setLooping(_isLooping);
                            PreferencesService.instance
                                .setBool(_prefLoop, _isLooping);
                          });
                        },
                      ),
                      if (!_track.isAudio) ...[
                        IconButton(
                          icon: Icon(
                            (_subtitlesEnabled && _externalSubtitle != null) ||
                                    _activeEmbeddedSubtitleIndex != null
                                ? Icons.subtitles
                                : Icons.subtitles_outlined,
                            color: (_subtitlesEnabled && _externalSubtitle != null) ||
                                    _activeEmbeddedSubtitleIndex != null
                                ? Colors.blueAccent
                                : Colors.white,
                          ),
                          tooltip: AppLocalizations.of(context).subtitles,
                          onPressed: _showSubtitleSheet,
                        ),
                        if (Platform.isIOS)
                          IconButton(
                            icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
                            tooltip: AppLocalizations.of(context).pictureInPicture,
                            onPressed: () => NativePipService.start(),
                          ),
                        IconButton(
                          icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                          tooltip: AppLocalizations.of(context).videoFitLabel,
                          onPressed: _cycleVideoFit,
                        ),
                      ],
                      IconButton(
                        icon: Icon(
                          _isFullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white,
                        ),
                        tooltip: _isFullscreen
                            ? AppLocalizations.of(context).exitFullscreen
                            : AppLocalizations.of(context).fullscreen,
                        onPressed: _toggleFullscreen,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        tooltip: AppLocalizations.of(context).playbackOptions,
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
                            case 'aspect_ratio':
                              _cycleVideoFit();
                              break;
                            case 'sleep_timer':
                              _showSleepTimerDialog();
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
                                    ? AppLocalizations.of(context).unmuteShortcut
                                    : AppLocalizations.of(context).muteShortcut((_volume * 100).toInt())),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'rewind',
                            child: Row(
                              children: [
                                Icon(Icons.replay_10, size: 20),
                                SizedBox(width: 10),
                                Text(AppLocalizations.of(context).rewind10s),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'forward',
                            child: Row(
                              children: [
                                Icon(Icons.forward_10, size: 20),
                                SizedBox(width: 10),
                                Text(AppLocalizations.of(context).forward10s),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          if (!_track.isAudio)
                            PopupMenuItem(
                              value: 'aspect_ratio',
                              child: Row(
                                children: [
                                  const Icon(Icons.aspect_ratio, size: 20),
                                  const SizedBox(width: 10),
                                  Text('${AppLocalizations.of(context).videoFitLabel} (${playerVideoFitLabel(AppLocalizations.of(context), _videoFit)})'),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'sleep_timer',
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined, size: 20),
                                const SizedBox(width: 10),
                                Text(sleepTimerMenuLabel(AppLocalizations.of(context))),
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
                                      ? AppLocalizations.of(context).autoNextMenuOn
                                      : AppLocalizations.of(context).autoNextMenuOff),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'prev',
                              enabled: _hasPrev,
                              child: Row(
                                children: [
                                  const Icon(Icons.skip_previous, size: 20),
                                  const SizedBox(width: 10),
                                  Text(AppLocalizations.of(context).previousShortcut),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'next',
                              enabled: _hasNext,
                              child: Row(
                                children: [
                                  const Icon(Icons.skip_next, size: 20),
                                  const SizedBox(width: 10),
                                  Text(AppLocalizations.of(context).nextShortcut),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: AppLocalizations.of(context).close,
                        onPressed: _closeAndExit,
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
                  _doubleTapHudTimer?.cancel();
                  setState(() {
                    _doubleTapSeekSeconds = (_doubleTapSeekSeconds != null && _doubleTapSeekSeconds! < 0)
                        ? _doubleTapSeekSeconds! - 10
                        : -10;
                  });
                  _seekRelative(-10);
                  HapticFeedback.lightImpact();
                  _doubleTapHudTimer = Timer(const Duration(milliseconds: 650), () {
                    if (mounted) setState(() => _doubleTapSeekSeconds = null);
                  });
                } else if (details.localPosition.dx > width * 2 / 3) {
                  _doubleTapHudTimer?.cancel();
                  setState(() {
                    _doubleTapSeekSeconds = (_doubleTapSeekSeconds != null && _doubleTapSeekSeconds! > 0)
                        ? _doubleTapSeekSeconds! + 10
                        : 10;
                  });
                  _seekRelative(10);
                  HapticFeedback.lightImpact();
                  _doubleTapHudTimer = Timer(const Duration(milliseconds: 650), () {
                    if (mounted) setState(() => _doubleTapSeekSeconds = null);
                  });
                } else {
                  _togglePlayPause();
                }
              },
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onLongPressCancel: _onLongPressCancel,
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
                                : _buildVideoSurface())),
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

                  // Horizontal swipe seek HUD
                  if (_isDraggingSeek)
                    MediaPlayerSeekHud(
                      deltaSeconds: _dragSeekDeltaSec,
                      target: _dragSeekTarget,
                      total: _controller?.value.duration ?? Duration.zero,
                    ),

                  // Vertical brightness gesture HUD
                  if (_isDraggingBrightness)
                    MediaPlayerBrightnessHud(brightness: _dragBrightnessLevel),

                  // Vertical volume gesture HUD
                  if (_isDraggingVolume)
                    MediaPlayerVolumeHud(volume: _volume),

                  // Long-press speed boost floating HUD
                  if (_isSpeedBoosting)
                    MediaPlayerSpeedBoostHud(boostRate: _boostRate),

                  // Speed change toast HUD
                  if (_hudSpeed != null && !_isSpeedBoosting)
                    MediaPlayerSpeedToastHud(speed: _hudSpeed!),

                  // Double-tap seek HUD ripple
                  if (_doubleTapSeekSeconds != null)
                    MediaPlayerDoubleTapSeekHud(seconds: _doubleTapSeekSeconds!),

                  // Overlay Controls (Timeline + Bottom Buttons)
                  if (_showControls && _initialized && _controller != null)
                    _buildControlsOverlay(),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _autoLoadExternalSubtitle(int gen) async {
    final loaded = await SubtitleService.findMatchingSubtitle(
      root: widget.root,
      mediaPath: _track.path,
    );
    if (!mounted || gen != _openGeneration) return;
    if (loaded != null) {
      await NativePipService.selectEmbeddedSubtitle(null);
      if (!mounted || gen != _openGeneration) return;
    }
    setState(() {
      _externalSubtitle = loaded;
      _subtitlesEnabled = loaded != null;
      if (loaded != null) {
        _activeEmbeddedSubtitleIndex = null;
      }
    });
  }

  Future<void> _loadEmbeddedSubtitles(int gen) async {
    final tracks = await NativePipService.listEmbeddedSubtitles();
    if (!mounted || gen != _openGeneration) return;
    final selectedIdx = tracks.where((t) => t.selected).firstOrNull?.index;
    setState(() {
      _embeddedSubtitles = tracks;
      if (!(_subtitlesEnabled && _externalSubtitle != null)) {
        _activeEmbeddedSubtitleIndex = selectedIdx;
      }
    });
  }

  Future<void> _showSubtitleSheet() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text(l10n.subtitles, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                (!_subtitlesEnabled || _externalSubtitle == null) &&
                        _activeEmbeddedSubtitleIndex == null
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(l10n.subtitleOff),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(NativePipService.selectEmbeddedSubtitle(null));
                if (mounted) {
                  setState(() {
                    _subtitlesEnabled = false;
                    _activeEmbeddedSubtitleIndex = null;
                  });
                }
              },
            ),
            for (final track in _embeddedSubtitles)
              ListTile(
                leading: Icon(
                  _activeEmbeddedSubtitleIndex == track.index && !_subtitlesEnabled
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(track.title),
                subtitle: track.language.isNotEmpty ? Text(track.language) : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final ok = await NativePipService.selectEmbeddedSubtitle(track.index);
                  if (ok && mounted) {
                    setState(() {
                      _subtitlesEnabled = false;
                      _activeEmbeddedSubtitleIndex = track.index;
                    });
                  }
                },
              ),
            if (_externalSubtitle != null)
              ListTile(
                leading: Icon(
                  _subtitlesEnabled ? Icons.radio_button_checked : Icons.radio_button_off,
                ),
                title: Text(_externalSubtitle!.name),
                onTap: () {
                  Navigator.of(ctx).pop();
                  unawaited(NativePipService.selectEmbeddedSubtitle(null));
                  if (mounted) {
                    setState(() {
                      _subtitlesEnabled = true;
                      _activeEmbeddedSubtitleIndex = null;
                    });
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(l10n.loadExternalSubtitle),
              onTap: () async {
                Navigator.of(ctx).pop();
                final slash = _track.path.lastIndexOf('/');
                final dir = slash >= 0 ? _track.path.substring(0, slash) : '';
                final picked = await FilePickerDialog.show(
                  context,
                  title: l10n.loadExternalSubtitle,
                  initialRoot: widget.root,
                  initialPath: dir,
                );
                if (picked == null || picked.paths.isEmpty || !mounted) return;
                final subPath = picked.paths.first;
                final subName = subPath.split('/').last;
                final loaded = await SubtitleService.loadFromVfs(
                  root: picked.root,
                  path: subPath,
                  name: subName,
                );
                if (loaded != null && mounted) {
                  await NativePipService.selectEmbeddedSubtitle(null);
                  if (!mounted) return;
                  setState(() {
                    _externalSubtitle = loaded;
                    _subtitlesEnabled = true;
                    _activeEmbeddedSubtitleIndex = null;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    Widget surface;
    if (_videoFit == BoxFit.fill) {
      surface = SizedBox.expand(child: VideoPlayer(_controller!));
    } else if (_videoFit == BoxFit.cover) {
      final size = _controller!.value.size;
      final ar = _controller!.value.aspectRatio > 0
          ? _controller!.value.aspectRatio
          : 16 / 9;
      final videoWidth = size.width > 0 ? size.width : ar * 1080.0;
      final videoHeight = size.height > 0 ? size.height : 1080.0;
      surface = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: videoWidth,
            height: videoHeight,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    } else {
      surface = AspectRatio(
        aspectRatio: _controller!.value.aspectRatio > 0
            ? _controller!.value.aspectRatio
            : 16 / 9,
        child: VideoPlayer(_controller!),
      );
    }

    if (!_subtitlesEnabled || _externalSubtitle == null) {
      return surface;
    }
    final activeText = SubtitleParser.activeTextAt(
      _externalSubtitle!.cues,
      _controller!.value.position,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        surface,
        VideoSubtitleOverlay(
          text: activeText,
          bottomPadding: _showControls ? 88 : 28,
        ),
      ],
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
            AppLocalizations.of(context).cannotPlayFile,
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
            label: Text(AppLocalizations.of(context).retry),
            onPressed: _openCurrentTrack,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.play_circle_outline),
            label: Text(AppLocalizations.of(context).playWithMediaKit),
            onPressed: () => _handoffToMediaKit(_track, _index),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final val = _controller!.value;
    final pos = val.position;
    final dur = val.duration;

    final double bottomMargin = _isFullscreen ? 36.0 : 24.0;
    final double seekMargin = _isFullscreen ? 96.0 : 84.0;

    return Stack(
      children: [
        // Seek Bar (Safely raised above Home Indicator)
        MediaPlayerTimeline(
          position: pos,
          duration: dur,
          bottomMargin: seekMargin,
          onSeekChanged: (v) {
            _controlsTimer?.cancel();
            _controller?.seekTo(Duration(milliseconds: v.toInt()));
          },
          onSeekEnd: (_) {
            _resetControlsTimer();
          },
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
                tooltip: AppLocalizations.of(context).rewind10s,
                onPressed: () => _seekRelative(-10),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                tooltip: AppLocalizations.of(context).forward10s,
                onPressed: () => _seekRelative(10),
              ),
              if (widget.playlist.length > 1) ...[
                IconButton(
                  icon: Icon(
                    Icons.skip_previous,
                    color: _hasPrev ? Colors.white : Colors.white38,
                  ),
                  tooltip: AppLocalizations.of(context).previousShortcut,
                  onPressed: _hasPrev ? () => _openTrack(_index - 1) : null,
                ),
                IconButton(
                  icon: Icon(
                    Icons.skip_next,
                    color: _hasNext ? Colors.white : Colors.white38,
                  ),
                  tooltip: AppLocalizations.of(context).nextEpisodeShortcut,
                  onPressed: _hasNext ? () => _openTrack(_index + 1) : null,
                ),
              ],
              const Spacer(),
              // Speed Menu: 0.5x to 8.0x
              Builder(
                builder: (btnCtx) => MediaPlayerSpeedBadge(
                  speed: _playbackSpeed,
                  onTap: () {
                    _resetControlsTimer();
                    showPlayerSpeedMenu(
                      context: context,
                      buttonContext: btnCtx,
                      currentSpeed: _playbackSpeed,
                      rates: _rates,
                      onSelected: _setSpeed,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
