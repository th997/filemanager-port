import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../pages/media_player_page.dart';
import '../rust/api/servers.dart';

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
  bool startedStream = false;

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

  bool get hasActiveSession =>
      (videoPlayerController != null && videoPlayerController!.value.isInitialized) ||
      (desktopPlayer != null);

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
      notifyListeners();
    }
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
      notifyListeners();
    });
    _desktopPosSub = player.stream.position.listen((pos) {
      position = pos;
      notifyListeners();
    });
    _desktopDurSub = player.stream.duration.listen((dur) {
      duration = dur;
      notifyListeners();
    });
    _desktopCompSub = player.stream.completed.listen((completed) {
      if (completed && !isFullScreen) {
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
      desktopPlayer!.playOrPause();
      isPlaying = desktopPlayer!.state.playing;
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
      desktopPlayer!.seek(newPos);
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
    final nextIndex = currentIndex + 1;
    final track = playlist[nextIndex];
    currentIndex = nextIndex;
    currentPath = track.path;
    currentFileName = track.fileName;
    isAudio = track.isAudio;
    restoreFullScreen();
  }

  void playPrev() {
    if (!hasPrev) return;
    final prevIndex = currentIndex - 1;
    final track = playlist[prevIndex];
    currentIndex = prevIndex;
    currentPath = track.path;
    currentFileName = track.fileName;
    isAudio = track.isAudio;
    restoreFullScreen();
  }

  void stop() {
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

    _lastNowPlayingIsPlaying = null;
    _lastNowPlayingSec = -1;
    _lastNowPlayingDuration = -1;
    _lastNowPlayingRate = -1;

    notifyListeners();

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
    }
  }

  void restoreFullScreen([BuildContext? context]) {
    if (currentRoot == null || currentPath == null || currentFileName == null) return;
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
          }
        } else if (arg == 'pause') {
          if (videoPlayerController != null && videoPlayerController!.value.isPlaying) {
            videoPlayerController!.pause();
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
    if (!Platform.isIOS || videoPlayerController == null || !videoPlayerController!.value.isInitialized) return;
    final val = videoPlayerController!.value;
    final playing = val.isPlaying;
    final posSec = val.position.inSeconds;
    final durationSec = val.duration.inMilliseconds / 1000.0;
    final currentRate = playing ? playbackSpeed : 0.0;

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
      'title': currentFileName ?? '',
      'duration': durationSec,
      'position': val.position.inMilliseconds / 1000.0,
      'rate': currentRate,
      'isAudio': isAudio,
      'hasNext': hasNext,
      'hasPrev': hasPrev,
    }).catchError((_) {});
  }
}
