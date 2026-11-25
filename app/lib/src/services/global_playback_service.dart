import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../pages/media_player_page.dart';
import '../rust/api/servers.dart';
import 'path_utils.dart';
import 'preferences_service.dart';

/// Global manager for active media playback across route navigation.
///
/// Keeps player instances alive when users minimize the player to browse files,
/// synchronizes Now Playing lock screen controls, and coordinates the mini player bar.
class GlobalPlaybackService extends ChangeNotifier {
  static final GlobalPlaybackService instance = GlobalPlaybackService._();
  GlobalPlaybackService._();

  static const _nowPlayingChannel =
      MethodChannel('com.github.th997.filemanager/now_playing');

  GlobalKey<NavigatorState>? _navKey;
  void init(GlobalKey<NavigatorState> navKey) {
    _navKey = navKey;
    initNowPlayingHandler();
  }

  String? currentRoot;
  String? currentPath;
  String? currentFileName;
  bool isAudio = false;
  List<MediaTrack> playlist = const [];
  int currentIndex = 0;

  bool isFullScreen = false;
  bool isMiniPlayerCollapsed = false;
  bool isModalActive = false;
  bool startedStream = false;

  void setModalActive(bool active) {
    if (isModalActive != active) {
      isModalActive = active;
      _notifySafely();
    }
  }

  /// Additional bottom inset (e.g. from BrowserBottomActionBar or bottom toolbars)
  /// that the floating mini player should stay above.
  final ValueNotifier<double> bottomBarInset = ValueNotifier<double>(0.0);
  final Map<String, double> _namedBottomInsets = {};

  void setNamedBottomInset(String key, double inset) {
    if (inset <= 0) {
      _namedBottomInsets.remove(key);
    } else {
      _namedBottomInsets[key] = inset;
    }
    var pageInset = 0.0;
    for (final entry in _namedBottomInsets.entries) {
      if (entry.key == 'active_tasks_banner') continue;
      if (entry.value > pageInset) pageInset = entry.value;
    }
    final next = pageInset + (_namedBottomInsets['active_tasks_banner'] ?? 0.0);
    if (bottomBarInset.value != next) {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        binding.addPostFrameCallback((_) {
          bottomBarInset.value = next;
        });
        return;
      }
      bottomBarInset.value = next;
    }
  }

  void setBottomBarInset(double inset) => setNamedBottomInset('_default', inset);

  void collapseMiniPlayer() {
    if (!isMiniPlayerCollapsed) {
      isMiniPlayerCollapsed = true;
      notifyListeners();
    }
  }

  void expandMiniPlayer() {
    if (isMiniPlayerCollapsed) {
      isMiniPlayerCollapsed = false;
      notifyListeners();
    }
  }

  void toggleMiniPlayerCollapsed() {
    isMiniPlayerCollapsed = !isMiniPlayerCollapsed;
    notifyListeners();
  }

  // iOS native player controller
  VideoPlayerController? videoPlayerController;

  // Desktop media_kit player & controller
  Player? desktopPlayer;
  VideoController? desktopVideoController;
  StreamSubscription? _desktopPosSub;
  StreamSubscription? _desktopDurSub;
  StreamSubscription? _desktopPlaySub;
  StreamSubscription? _desktopCompSub;

  Timer? _sleepTimer;
  DateTime? _sleepTimerEndTime;
  Duration? get sleepTimerRemaining {
    final end = _sleepTimerEndTime;
    if (end == null) return null;
    final diff = end.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }
  bool sleepTimerAtEndOfTrack = false;

  void setSleepTimer(Duration? duration, {bool atEndOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    sleepTimerAtEndOfTrack = atEndOfTrack;
    if (duration != null) {
      _sleepTimerEndTime = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        _sleepTimer = null;
        _sleepTimerEndTime = null;
        sleepTimerAtEndOfTrack = false;
        pause();
      });
    }
    notifyListeners();
  }

  bool consumeEndOfTrackSleepTimer() {
    if (!sleepTimerAtEndOfTrack) return false;
    sleepTimerAtEndOfTrack = false;
    _notifySafely();
    return true;
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    sleepTimerAtEndOfTrack = false;
    notifyListeners();
  }

  // Cached playback metrics for mini player
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isBuffering = false;
  double playbackSpeed = 1.0;

  bool? _lastNowPlayingIsPlaying;
  int _lastNowPlayingSec = -1;
  double _lastNowPlayingDuration = -1;
  double _lastNowPlayingRate = -1;
  String _privacyAudioTitle = 'Private Audio';
  String _privacyVideoTitle = 'Private Video';

  void setPrivacyMediaLabels({required String audio, required String video}) {
    if (_privacyAudioTitle == audio && _privacyVideoTitle == video) return;
    _privacyAudioTitle = audio;
    _privacyVideoTitle = video;
    if (Platform.isIOS && hasActiveSession && vaultIdFromRoot(currentRoot ?? '') != null) {
      _updateNowPlaying(force: true);
    }
  }

  String redactedNowPlayingTitle({
    required String? root,
    required String? fileName,
    required bool isAudio,
  }) {
    if (root != null && vaultIdFromRoot(root) != null) {
      return isAudio ? _privacyAudioTitle : _privacyVideoTitle;
    }
    return fileName ?? '';
  }

  bool get hasActiveSession {
    final vpc = videoPlayerController;
    if (vpc != null) {
      try {
        if (vpc.value.isInitialized) return true;
      } catch (_) {
        // Controller already disposed; treat as no session.
      }
    }
    return desktopPlayer != null;
  }

  bool get hasNext => playlist.isNotEmpty && currentIndex < playlist.length - 1;
  bool get hasPrev => playlist.isNotEmpty && currentIndex > 0;

  void initNowPlayingHandler() {
    if (Platform.isIOS) {
      _nowPlayingChannel.setMethodCallHandler(_handleNowPlayingMethodCall);
    }
  }

  void setFullScreen(bool value) {
    if (isFullScreen != value) {
      isFullScreen = value;
      _notifySafely();
    }
  }

  /// Notifies listeners unless the widget tree is locked (e.g. a page's
  /// dispose() during unmount). A notify dropped in that window never reaches
  /// the mini player bar, which then keeps rendering its stale state forever.
  void _notifySafely() {
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => notifyListeners());
      return;
    }
    notifyListeners();
  }

  void setIosSession({
    required String root,
    required String path,
    required String fileName,
    required bool isAudio,
    required List<MediaTrack> playlist,
    required int currentIndex,
    required VideoPlayerController controller,
    required bool startedStream,
    double playbackSpeed = 1.0,
  }) {
    if (videoPlayerController != null && videoPlayerController != controller) {
      videoPlayerController!.removeListener(_onIosControllerUpdate);
    }

    currentRoot = root;
    currentPath = path;
    currentFileName = fileName;
    this.isAudio = isAudio;
    this.playlist = playlist;
    this.currentIndex = currentIndex;
    videoPlayerController = controller;
    this.startedStream = startedStream;
    this.playbackSpeed = playbackSpeed;
    isFullScreen = true;

    initNowPlayingHandler();
    controller.addListener(_onIosControllerUpdate);
    _onIosControllerUpdate();
  }

  /// Drops the service's reference before the owner disposes [controller],
  /// so listeners never observe a disposed controller mid track switch.
  void detachIosSessionController(VideoPlayerController controller) {
    if (videoPlayerController != controller) return;
    try {
      controller.removeListener(_onIosControllerUpdate);
    } catch (_) {}
    videoPlayerController = null;
    isPlaying = false;
    _notifySafely();
  }

  void _onIosControllerUpdate() {
    if (videoPlayerController == null || !videoPlayerController!.value.isInitialized) return;
    final val = videoPlayerController!.value;
    final changed = isPlaying != val.isPlaying ||
        (position.inSeconds != val.position.inSeconds) ||
        (duration.inSeconds != val.duration.inSeconds) ||
        isBuffering != val.isBuffering;

    isPlaying = val.isPlaying;
    position = val.position;
    duration = val.duration;
    isBuffering = val.isBuffering;

    if (Platform.isIOS) {
      _updateNowPlaying();
    }

    if (!isFullScreen &&
        val.duration > Duration.zero &&
        val.position >= val.duration - const Duration(milliseconds: 300) &&
        !val.isPlaying) {
      if (consumeEndOfTrackSleepTimer()) {
        pause();
        return;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setDesktopSession({
    required String root,
    required String path,
    required String fileName,
    required bool isAudio,
    required List<MediaTrack> playlist,
    required int currentIndex,
    required Player player,
    required VideoController controller,
    required bool startedStream,
    double playbackSpeed = 1.0,
  }) {
    _cleanupDesktopSubs();

    currentRoot = root;
    currentPath = path;
    currentFileName = fileName;
    this.isAudio = isAudio;
    this.playlist = playlist;
    this.currentIndex = currentIndex;
    desktopPlayer = player;
    desktopVideoController = controller;
    this.startedStream = startedStream;
    this.playbackSpeed = playbackSpeed;
    isFullScreen = true;

    isPlaying = player.state.playing;
    position = player.state.position;
    duration = player.state.duration;

    _desktopPlaySub = player.stream.playing.listen((playing) {
      isPlaying = playing;
      if (Platform.isIOS) {
        _updateNowPlaying(force: true);
      }
      notifyListeners();
    });
    _desktopPosSub = player.stream.position.listen((pos) {
      final prevSec = position.inSeconds;
      position = pos;
      if (pos.inSeconds != prevSec) {
        if (Platform.isIOS) {
          _updateNowPlaying();
        }
        notifyListeners();
      }
    });
    _desktopDurSub = player.stream.duration.listen((dur) {
      duration = dur;
      if (Platform.isIOS) {
        _updateNowPlaying(force: true);
      }
      notifyListeners();
    });
    _desktopCompSub = player.stream.completed.listen((completed) {
      if (completed && !isFullScreen) {
        if (consumeEndOfTrackSleepTimer()) {
          pause();
          return;
        }
        if (hasNext) {
          playNext();
        } else {
          stop();
        }
      }
    });

    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed;
    if (videoPlayerController != null && videoPlayerController!.value.isInitialized) {
      videoPlayerController!.setPlaybackSpeed(speed);
    } else if (desktopPlayer != null) {
      desktopPlayer!.setRate(speed);
    }
    _updateNowPlaying(force: true);
    notifyListeners();
  }

  void _cleanupDesktopSubs() {
    _desktopPlaySub?.cancel();
    _desktopPlaySub = null;
    _desktopPosSub?.cancel();
    _desktopPosSub = null;
    _desktopDurSub?.cancel();
    _desktopDurSub = null;
    _desktopCompSub?.cancel();
    _desktopCompSub = null;
  }

  void pause() {
    isPlaying = false;
    if (videoPlayerController != null) {
      videoPlayerController!.pause();
      _updateNowPlaying(force: true);
    } else if (desktopPlayer != null) {
      desktopPlayer!.pause();
    }
    _notifySafely();
  }

  void togglePlayPause() {
    if (videoPlayerController != null) {
      if (videoPlayerController!.value.isPlaying) {
        isPlaying = false;
        videoPlayerController!.pause();
      } else {
        isPlaying = true;
        videoPlayerController!.play();
        if (playbackSpeed != 1.0) {
          videoPlayerController!.setPlaybackSpeed(playbackSpeed);
        }
      }
      _updateNowPlaying(force: true);
    } else if (desktopPlayer != null) {
      isPlaying = !isPlaying;
      desktopPlayer!.playOrPause();
    }
    notifyListeners();
  }

  void seekRelative(int seconds) {
    if (videoPlayerController != null) {
      final newPos = position + Duration(seconds: seconds);
      final clamped = Duration(
        milliseconds: newPos.inMilliseconds.clamp(0, duration.inMilliseconds),
      );
      videoPlayerController!.seekTo(clamped);
      _updateNowPlaying(force: true);
    } else if (desktopPlayer != null) {
      final newPos = position + Duration(seconds: seconds);
      final maxMs = duration.inMilliseconds;
      final clamped = maxMs > 0
          ? Duration(milliseconds: newPos.inMilliseconds.clamp(0, maxMs))
          : (newPos.isNegative ? Duration.zero : newPos);
      desktopPlayer!.seek(clamped);
    }
  }

  void seekTo(Duration target) {
    if (videoPlayerController != null) {
      videoPlayerController!.seekTo(target);
      _updateNowPlaying(force: true);
    } else if (desktopPlayer != null) {
      desktopPlayer!.seek(target);
    }
  }

  void playNext() {
    if (!hasNext) return;
    _switchTrack(currentIndex + 1);
  }

  void playPrev() {
    if (!hasPrev) return;
    _switchTrack(currentIndex - 1);
  }

  /// The live player still holds the previous file's media source. Just
  /// changing `currentPath` made the newly pushed player page believe it
  /// could reuse that controller, so it never opened the new track: the UI
  /// showed the next title while the old file kept playing. Drop the whole
  /// session and let the new page create a player for the new URI.
  void _switchTrack(int index) {
    final root = currentRoot;
    final tracks = playlist;
    if (root == null || index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    final speed = playbackSpeed;

    // When minimized on desktop/Android, swap the track directly on the live
    // Player instead of pushing fullscreen over whatever the user is doing.
    if (!isFullScreen && desktopPlayer != null) {
      _persistResumePosition();
      currentPath = track.path;
      currentFileName = track.fileName;
      isAudio = track.isAudio;
      currentIndex = index;
      position = Duration.zero;
      duration = Duration.zero;
      notifyListeners();
      unawaited(_openDesktopTrackInBackground(root, track, speed));
      return;
    }

    stop();

    currentRoot = root;
    currentPath = track.path;
    currentFileName = track.fileName;
    isAudio = track.isAudio;
    playlist = tracks;
    currentIndex = index;
    playbackSpeed = speed;
    restoreFullScreen();
  }

  Future<void> _openDesktopTrackInBackground(
    String root,
    MediaTrack track,
    double speed,
  ) async {
    final player = desktopPlayer;
    if (player == null) return;
    try {
      final String uri;
      final native = joinNative(root, track.path);
      if (isNativeRoot(root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
      } else {
        final base = (await startMediaStream(root: root))
            .replaceFirst(RegExp(r'/$'), '');
        startedStream = true;
        final encoded = track.path
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        final bufferMb = PreferencesService.instance.bufferSizeMb;
        uri = '$base/$encoded?buffer_mb=$bufferMb';
      }
      if (!identical(desktopPlayer, player)) return;
      await player.open(Media(uri), play: true);
      if (speed != 1.0) {
        await player.setRate(speed);
      }
      notifyListeners();
    } catch (_) {
      if (identical(desktopPlayer, player)) {
        stop();
      }
    }
  }

  void stop() {
    _persistResumePosition();
    final vpc = videoPlayerController;
    videoPlayerController = null;

    final dp = desktopPlayer;
    desktopPlayer = null;
    desktopVideoController = null;

    final wasStartedStream = startedStream;
    startedStream = false;

    currentRoot = null;
    currentPath = null;
    currentFileName = null;
    playlist = const [];
    currentIndex = 0;
    isFullScreen = false;
    isMiniPlayerCollapsed = false;
    isPlaying = false;
    position = Duration.zero;
    duration = Duration.zero;
    isBuffering = false;
    playbackSpeed = 1.0;

    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndTime = null;
    sleepTimerAtEndOfTrack = false;

    _lastNowPlayingIsPlaying = null;
    _lastNowPlayingSec = -1;
    _lastNowPlayingDuration = -1;
    _lastNowPlayingRate = -1;

    _notifySafely();

    if (wasStartedStream) {
      try {
        stopMediaStreams();
      } catch (_) {}
    }

    if (vpc != null) {
      try {
        vpc.removeListener(_onIosControllerUpdate);
      } catch (_) {}
      try {
        vpc.pause().catchError((_) {});
      } catch (_) {}
      try {
        vpc.dispose().catchError((_) {});
      } catch (_) {}
    }

    _cleanupDesktopSubs();
    if (dp != null) {
      try {
        dp.dispose();
      } catch (_) {}
    }

    if (Platform.isIOS) {
      try {
        _nowPlayingChannel.invokeMethod('clear').catchError((_) {});
      } catch (_) {}
      // The player page overwrites this channel's handler while visible.
      // Take it back so lock-screen/headset commands keep working after the
      // page is gone (mini player, track switch, ...).
      initNowPlayingHandler();
    }
  }

  /// Same key format and near-start/near-end rules as the player pages, so
  /// positions survive completion/track switches handled while minimized.
  void _persistResumePosition() {
    final root = currentRoot;
    final path = currentPath;
    if (root == null || path == null || duration <= Duration.zero) return;
    if (vaultIdFromRoot(root) != null) return;
    final key = 'player.resume.$root|$path';
    if (position < const Duration(seconds: 5) || position > duration * 0.95) {
      PreferencesService.instance.remove(key);
      return;
    }
    PreferencesService.instance.setString(
      key,
      position.inMilliseconds.toString(),
    );
  }

  void restoreFullScreen([BuildContext? context]) {
    if (currentRoot == null || currentPath == null || currentFileName == null) return;
    if (isFullScreen) return;
    isFullScreen = true;
    notifyListeners();

    final route = MaterialPageRoute(
      builder: (_) => MediaPlayerPage(
        root: currentRoot!,
        path: currentPath!,
        fileName: currentFileName!,
        isAudio: isAudio,
        playlist: playlist,
        startIndex: currentIndex,
        forceMediaKit: desktopPlayer != null,
      ),
    );

    final nav = (context != null ? Navigator.maybeOf(context, rootNavigator: true) : null) ??
        _navKey?.currentState;
    nav?.push(route);
  }

  Future<dynamic> _handleNowPlayingMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onRemoteCommand':
        final arg = call.arguments;
        if (arg == 'play') {
          if (videoPlayerController != null && !videoPlayerController!.value.isPlaying) {
            videoPlayerController!.play();
            _updateNowPlaying(force: true);
          } else if (desktopPlayer != null && !desktopPlayer!.state.playing) {
            desktopPlayer!.play();
            _updateNowPlaying(force: true);
          }
        } else if (arg == 'pause') {
          if (videoPlayerController != null && videoPlayerController!.value.isPlaying) {
            videoPlayerController!.pause();
            _updateNowPlaying(force: true);
          } else if (desktopPlayer != null && desktopPlayer!.state.playing) {
            desktopPlayer!.pause();
            _updateNowPlaying(force: true);
          }
        } else if (arg == 'togglePlayPause') {
          togglePlayPause();
        } else if (arg == 'forward10') {
          seekRelative(10);
        } else if (arg == 'rewind10') {
          seekRelative(-10);
        } else if (arg == 'next') {
          if (hasNext) playNext();
        } else if (arg == 'prev') {
          if (hasPrev) playPrev();
        } else if (arg is Map && arg.containsKey('seek')) {
          final target = (arg['seek'] as num).toDouble();
          seekTo(Duration(milliseconds: (target * 1000).toInt()));
        }
        break;
    }
  }

  void _updateNowPlaying({bool force = false}) {
    if (!Platform.isIOS) return;
    final bool hasVp = videoPlayerController != null && videoPlayerController!.value.isInitialized;
    final bool hasDp = desktopPlayer != null;
    if (!hasVp && !hasDp) return;

    final bool playing = hasVp ? videoPlayerController!.value.isPlaying : desktopPlayer!.state.playing;
    final int posSec = position.inSeconds;
    final double durationSec = duration.inMilliseconds / 1000.0;
    final double currentRate = playing ? playbackSpeed : 0.0;

    if (!force &&
        _lastNowPlayingIsPlaying == playing &&
        _lastNowPlayingDuration == durationSec &&
        _lastNowPlayingRate == currentRate &&
        (posSec - _lastNowPlayingSec).abs() < 5) {
      return;
    }
    _lastNowPlayingIsPlaying = playing;
    _lastNowPlayingSec = posSec;
    _lastNowPlayingDuration = durationSec;
    _lastNowPlayingRate = currentRate;

    _nowPlayingChannel.invokeMethod('update', {
      'title': redactedNowPlayingTitle(
        root: currentRoot,
        fileName: currentFileName,
        isAudio: isAudio,
      ),
      'duration': durationSec,
      'position': position.inMilliseconds / 1000.0,
      'rate': currentRate,
      'isAudio': isAudio,
      'hasNext': hasNext,
      'hasPrev': hasPrev,
    }).catchError((_) {});
  }
}
