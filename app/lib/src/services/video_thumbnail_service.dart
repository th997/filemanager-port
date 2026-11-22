import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';

import '../rust/api/servers.dart';
import 'path_utils.dart';
import 'vault_service.dart';

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
  bool _vaultCleanupRegistered = false;

  void _ensureVaultCleanupRegistered() {
    if (_vaultCleanupRegistered) return;
    _vaultCleanupRegistered = true;
    VaultService.instance.registerLockCleanup((_) {
      _player?.stop().catchError((_) {});
    });
  }

  /// Grabs one frame from a vault video in memory without writing plaintext
  /// JPEGs to temp storage. Serialized on the shared player and disabled on iOS.
  Future<Uint8List?> grabVaultFrameBytes({
    required String root,
    required String path,
    required bool Function() isCancelled,
  }) {
    if (Platform.isIOS || isCancelled()) {
      return Future.value(null);
    }
    _ensureVaultCleanupRegistered();
    return _enqueue(() => _grabVaultBytes(root, path, isCancelled));
  }

  Future<Uint8List?> _grabVaultBytes(
    String root,
    String path,
    bool Function() isCancelled,
  ) async {
    if (isCancelled()) return null;
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      final base = (await startMediaStream(root: root))
          .replaceFirst(RegExp(r'/$'), '');
      if (isCancelled()) return null;
      final encoded = path
          .split('/')
          .where((s) => s.isNotEmpty)
          .map(Uri.encodeComponent)
          .join('/');
      final uri = '$base/$encoded';

      final player = _player ??= Player();
      await player.setVolume(0);
      await player.open(Media(uri));
      if (isCancelled()) {
        await player.stop();
        return null;
      }
      await player.stream.videoParams
          .firstWhere((p) => p.w != null && p.w! > 0)
          .timeout(const Duration(seconds: 6));
      final dur = player.state.duration;
      final target = dur > const Duration(seconds: 4)
          ? const Duration(seconds: 2)
          : Duration(milliseconds: (dur.inMilliseconds * 0.25).round());
      await player.seek(target);
      await player.stream.position
          .firstWhere((p) => p >= target)
          .timeout(const Duration(milliseconds: 250), onTimeout: () => target);
      if (isCancelled()) {
        await player.stop();
        return null;
      }
      final bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 4));
      await player.stop();
      if (bytes == null || bytes.isEmpty || isCancelled()) return null;
      return bytes;
    } catch (_) {
      try {
        await _player?.stop();
      } catch (_) {}
      return null;
    } finally {
      if (_player != null) {
        _scheduleIdleDispose();
      }
    }
  }

  static final String _thumbsDirPath = '${Directory.systemTemp.path}/fm_video_thumbs';

  static String _thumbFileName(String key) {
    // FNV-1a: String.hashCode is stable but different videos can collide,
    // and a collision shows the wrong frame for the file.
    var h = 0xcbf29ce484222325;
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h.toRadixString(16)}.jpg';
  }

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

    // Fast-path: if thumbnail already exists on disk, return immediately
    // without queuing through the serialized media_kit Player pipeline.
    final out = File('$_thumbsDirPath/${_thumbFileName(key)}');
    try {
      if (out.existsSync() && out.lengthSync() > 0) {
        final fut = Future<File?>.value(out);
        _cache[key] = fut;
        return fut;
      }
    } catch (_) {}

    if (_cache.length > 500) {
      _cache.remove(_cache.keys.first);
    }

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
    // A pending idle dispose would otherwise fire in the middle of the next
    // open/seek/screenshot and free the shared player.
    _idleTimer?.cancel();
    _idleTimer = null;
    try {
      final dir = Directory(_thumbsDirPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final out = File('$_thumbsDirPath/${_thumbFileName(key)}');
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
      // Wait for seek to complete with a short timeout instead of a fixed 400ms delay
      await player.stream.position
          .firstWhere((p) => p >= target)
          .timeout(const Duration(milliseconds: 250), onTimeout: () => target);
      final bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 4));
      await player.stop();
      if (bytes == null) return null;
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } catch (_) {
      try {
        await _player?.stop();
      } catch (_) {}
      return null;
    } finally {
      if (_player != null) {
        _scheduleIdleDispose();
      }
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
