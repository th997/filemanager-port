import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

/// Unified abstract playback engine decoupling shared player UI/HUD/gestures/
/// playlist/subtitle controls from the underlying backend (`media_kit` or
/// iOS `AVPlayer` via `video_player`).
abstract class MediaPlayerEngine {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get bufferingStream;
  Stream<void> get completedStream;

  bool get isPlaying;
  Duration get position;
  Duration get duration;
  double get rate;

  Future<void> open(String source, {bool isNetwork = false});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> setVolume(double volume01);
  Future<void> setExternalSubtitle(String? rawContent, {String? title});
  Future<void> dispose();
}

/// Lightweight [MediaPlayerEngine] implementation backed by `media_kit` (libmpv).
class MediaKitEngine implements MediaPlayerEngine {
  final Player player;
  final bool _ownsPlayer;
  double _rate = 1.0;

  MediaKitEngine({Player? player})
      : player = player ?? Player(),
        _ownsPlayer = player == null;

  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;
  @override
  Stream<void> get completedStream =>
      player.stream.completed.where((done) => done).map((_) {});

  @override
  bool get isPlaying => player.state.playing;
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;
  @override
  double get rate => _rate;

  @override
  Future<void> open(String source, {bool isNetwork = false}) =>
      player.open(Media(source));

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setRate(double rate) {
    _rate = rate;
    return player.setRate(rate);
  }

  @override
  Future<void> setVolume(double volume01) =>
      player.setVolume((volume01 * 100.0).clamp(0.0, 100.0));

  @override
  Future<void> setExternalSubtitle(String? rawContent, {String? title}) async {
    if (rawContent == null || rawContent.isEmpty) {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      await player.setSubtitleTrack(SubtitleTrack.data(rawContent, title: title));
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsPlayer) {
      await player.dispose();
    }
  }
}

/// Lightweight [MediaPlayerEngine] implementation backed by Apple `AVPlayer`
/// via Flutter's `video_player` plugin.
class AvPlayerEngine implements MediaPlayerEngine {
  VideoPlayerController? _controller;
  double _rate = 1.0;

  final _playingCtrl = StreamController<bool>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  bool _completedEmitted = false;

  VideoPlayerController? get controller => _controller;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;
  @override
  Stream<bool> get bufferingStream => _bufferingCtrl.stream;
  @override
  Stream<void> get completedStream => _completedCtrl.stream;

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  @override
  Duration get position => _controller?.value.position ?? Duration.zero;
  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;
  @override
  double get rate => _rate;

  void _onControllerUpdate() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    _playingCtrl.add(v.isPlaying);
    _positionCtrl.add(v.position);
    _durationCtrl.add(v.duration);
    _bufferingCtrl.add(v.isBuffering);
    if (v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 250) &&
        !v.isPlaying) {
      if (!_completedEmitted) {
        _completedEmitted = true;
        _completedCtrl.add(null);
      }
    } else {
      _completedEmitted = false;
    }
  }

  @override
  Future<void> open(String source, {bool isNetwork = false}) async {
    await _disposeController();
    final ctrl = isNetwork
        ? VideoPlayerController.networkUrl(Uri.parse(source))
        : VideoPlayerController.contentUri(Uri.file(source));
    _controller = ctrl;
    ctrl.addListener(_onControllerUpdate);
    await ctrl.initialize();
    await ctrl.setPlaybackSpeed(_rate);
    await ctrl.play();
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _controller?.setPlaybackSpeed(rate);
  }

  @override
  Future<void> setVolume(double volume01) async =>
      _controller?.setVolume(volume01.clamp(0.0, 1.0));

  @override
  Future<void> setExternalSubtitle(String? rawContent, {String? title}) async {
    // AVPlayer renders external subtitles via the synced VideoSubtitleOverlay
    // driven by SubtitleParser + positionStream.
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onControllerUpdate);
      await c.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    await _playingCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _bufferingCtrl.close();
    await _completedCtrl.close();
  }
}
