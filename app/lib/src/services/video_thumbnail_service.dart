import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import '../rust/api/servers.dart';
import 'path_utils.dart';

/// Frame-grab thumbnails for video entries.
///
/// There is no platform thumbnail API that covers desktop, so a single
/// shared media_kit player opens each video muted, seeks to ~2 s (or a
/// quarter in for short clips), and screenshots one frame. Requests are
/// serialised through a queue — a folder of videos must not spawn a
/// player per tile — and results are cached as JPEGs under the system
/// temp dir, so a folder revisited later renders instantly.
///
/// This is best-effort by design: any failure (codec, network, timeout)
/// completes with null and the tile keeps its plain video icon.
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  static final Map<String, Future<File?>> _cache = {};
  Player? _player;
  Future<void> _queue = Future<void>.value();
  Timer? _idleTimer;

  Future<File?> thumbnail({required String root, required String path}) {
    // Only local native roots should ever generate video thumbnails.
    // Remote SFTP/WebDAV/SMB must NEVER stream entire files in background.
    // On iOS, media_kit is disabled to prevent AudioSession collisions.
    if (!isNativeRoot(root) || Platform.isIOS) {
      return Future.value(null);
    }
    final key = '$root\u0000$path';
    final existing = _cache[key];
    if (existing != null) return existing;
    final future = _enqueue(() => _grab(root, path, key));
    _cache[key] = future;
    // Failures are not memoised: the next build may retry.
    future.then(
      (file) {
        if (file == null) _cache.remove(key);
      },
      onError: (_) {
        _cache.remove(key);
      },
    );
    return future;
  }

  Future<T> _enqueue<T>(Future<T> Function() job) {
    final run = _queue.then((_) => job());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<File?> _grab(String root, String path, String key) async {
    try {
      final dir = Directory('${Directory.systemTemp.path}/fm_video_thumbs');
      await dir.create(recursive: true);
      final out = File('${dir.path}/${key.hashCode.abs()}.jpg');
      if (await out.exists() && await out.length() > 0) return out;

      final String uri;
      final native = joinNative(root, path);
      if (isNativeRoot(root) && File(native).existsSync()) {
        uri = Uri.file(native).toString();
      } else {
        final base = (await startMediaStream(root: root))
            .replaceFirst(RegExp(r'/$'), '');
        final encoded = path
            .split('/')
            .where((s) => s.isNotEmpty)
            .map(Uri.encodeComponent)
            .join('/');
        uri = '$base/$encoded';
      }

      final player = _player ??= Player();
      await player.setVolume(0);
      await player.open(Media(uri));
      // A frame exists only once the video pipeline reports dimensions.
      await player.stream.videoParams
          .firstWhere((p) => p.w != null && p.w! > 0)
          .timeout(const Duration(seconds: 6));
      final dur = player.state.duration;
      final target = dur > const Duration(seconds: 4)
          ? const Duration(seconds: 2)
          : Duration(milliseconds: (dur.inMilliseconds * 0.25).round());
      await player.seek(target);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 4));
      await player.stop();
      if (bytes == null) return null;
      await out.writeAsBytes(bytes, flush: true);
      _scheduleIdleDispose();
      return out;
    } catch (_) {
      try {
        await _player?.stop();
      } catch (_) {}
      return null;
    }
  }

  /// The shared player is released after an idle spell so it does not
  /// hold codec resources for the whole session.
  void _scheduleIdleDispose() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 20), () {
      _player?.dispose();
      _player = null;
    });
  }
}
