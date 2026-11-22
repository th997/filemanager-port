import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/vault.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../services/vault_service.dart';
import '../services/video_thumbnail_service.dart';

/// Counting semaphore that bounds concurrent async operations in FIFO order.
class VaultThumbSemaphore {
  final int maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  VaultThumbSemaphore(this.maxConcurrent) : assert(maxConcurrent > 0);

  int get activeCount => _active;
  int get queuedCount => _waiters.length;

  Future<void> acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.addLast(completer);
    return completer.future;
  }

  void release() {
    while (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete();
        return;
      }
    }
    if (_active > 0) _active--;
  }

  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}

/// Thumbnail for an image entry in the browser grid/list.
///
/// Until this existed, every folder — including photo folders on a NAS —
/// rendered as rows of identical generic icons, and the only way to tell
/// pictures apart was to open them one by one.
///
/// Local files decode straight from disk at display size. Remote and
/// archive entries go through the same export-to-cache path the image
/// viewer uses; exports are memoised per root+path for the session so
/// scrolling does not re-export. Anything that fails falls back to the
/// plain file icon.
class EntryThumbnail extends StatefulWidget {
  final String root;
  final String relPath;
  final EntryItem item;
  final double size;

  const EntryThumbnail({
    super.key,
    required this.root,
    required this.relPath,
    required this.item,
    required this.size,
  });

  @override
  State<EntryThumbnail> createState() => _EntryThumbnailState();
}

class _EntryThumbnailState extends State<EntryThumbnail> {
  static final Map<String, Future<String>> _exports = {};
  static final Map<String, Future<Uint8List?>> _vaultThumbs = {};
  static final Set<String> _completedVaultThumbKeys = {};
  static final Map<String, int> _activeVaultKeys = {};
  static final Map<String, int> _vaultThumbReqIds = {};
  static int _nextVaultThumbReq = 0;
  static final VaultThumbSemaphore _thumbReadSemaphore = VaultThumbSemaphore(6);
  static final VaultThumbSemaphore _thumbGenSemaphore = VaultThumbSemaphore(2);
  static bool _cleanupRegistered = false;

  static void _ensureCleanupRegistered() {
    if (_cleanupRegistered) return;
    _cleanupRegistered = true;
    VaultService.instance.registerLockCleanup(clearVaultCache);
  }

  static void clearVaultCache([String? vaultId]) {
    if (vaultId == null) {
      _vaultThumbs.clear();
      _completedVaultThumbKeys.clear();
      _vaultThumbReqIds.clear();
    } else {
      bool belongsToVault(String key) =>
          vaultIdFromRoot(key.split('\u0000').first) == vaultId;
      _vaultThumbs.removeWhere((key, _) => belongsToVault(key));
      _completedVaultThumbKeys.removeWhere(belongsToVault);
      _vaultThumbReqIds.removeWhere((key, _) => belongsToVault(key));
    }
    PaintingBinding.instance.imageCache.clear();
  }

  Future<File?>? _videoFuture;
  Future<String>? _exportFuture;
  Future<Uint8List?>? _vaultThumbFuture;
  String? _watchedVaultKey;

  @override
  void initState() {
    super.initState();
    PreferencesService.vaultVideoThumbnailsNotifier
        .addListener(_onVaultThumbPrefChanged);
    _initFutures();
  }

  @override
  void didUpdateWidget(covariant EntryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root ||
        oldWidget.relPath != widget.relPath ||
        oldWidget.item.name != widget.item.name) {
      _initFutures();
    }
  }

  void _onVaultThumbPrefChanged() {
    if (!mounted) return;
    if (vaultIdFromRoot(widget.root) != null &&
        widget.item.isVideo &&
        !Platform.isIOS) {
      setState(() {
        _initFutures();
      });
    }
  }

  @override
  void dispose() {
    PreferencesService.vaultVideoThumbnailsNotifier
        .removeListener(_onVaultThumbPrefChanged);
    _unwatchVaultKey();
    super.dispose();
  }

  void _watchVaultKey(String key) {
    if (_watchedVaultKey == key) return;
    _unwatchVaultKey();
    _watchedVaultKey = key;
    _activeVaultKeys[key] = (_activeVaultKeys[key] ?? 0) + 1;
  }

  void _unwatchVaultKey() {
    final key = _watchedVaultKey;
    if (key == null) return;
    _watchedVaultKey = null;
    final next = (_activeVaultKeys[key] ?? 0) - 1;
    if (next <= 0) {
      _activeVaultKeys.remove(key);
      // Cancel in-flight/queued decode when the last visible tile scrolls away;
      // completed thumbnails remain memoised up to the LRU bound.
      if (!_completedVaultThumbKeys.contains(key)) {
        _vaultThumbs.remove(key);
        _vaultThumbReqIds.remove(key);
      }
    } else {
      _activeVaultKeys[key] = next;
    }
  }

  void _initFutures() {
    final vid = vaultIdFromRoot(widget.root);
    if (vid != null) {
      _videoFuture = null;
      _exportFuture = null;
      final wantVideoThumb = widget.item.isVideo &&
          !Platform.isIOS &&
          PreferencesService.vaultVideoThumbnailsNotifier.value;
      if (widget.item.isImage || wantVideoThumb) {
        _vaultThumbFuture = _loadVaultThumb(vid);
      } else {
        _unwatchVaultKey();
        _vaultThumbFuture = null;
      }
      return;
    }

    _unwatchVaultKey();
    _vaultThumbFuture = null;
    if (widget.item.isVideo) {
      _videoFuture = VideoThumbnailService.instance.thumbnail(
        root: widget.root,
        path: widget.relPath,
      );
      _exportFuture = null;
    } else if (widget.item.isImage && !isNativeRoot(widget.root)) {
      _exportFuture = _export();
      _videoFuture = null;
    } else {
      _videoFuture = null;
      _exportFuture = null;
    }
  }

  Future<Uint8List?> _loadVaultThumb(String vid) {
    _ensureCleanupRegistered();
    final key = '${widget.root}\u0000${widget.relPath}';
    _watchVaultKey(key);
    final existing = _vaultThumbs[key];
    if (existing != null) return existing;

    if (_vaultThumbs.length >= 300) {
      final oldest = _vaultThumbs.keys.first;
      _vaultThumbs.remove(oldest);
      _completedVaultThumbKeys.remove(oldest);
    }

    final reqId = ++_nextVaultThumbReq;
    _vaultThumbReqIds[key] = reqId;
    late final Future<Uint8List?> future;
    future = _doLoadVaultThumb(vid, key, reqId).then((bytes) {
      if (bytes == null && identical(_vaultThumbs[key], future)) {
        _vaultThumbs.remove(key);
        _completedVaultThumbKeys.remove(key);
      }
      return bytes;
    }, onError: (_) {
      if (identical(_vaultThumbs[key], future)) {
        _vaultThumbs.remove(key);
        _completedVaultThumbKeys.remove(key);
      }
      return null;
    });
    _vaultThumbs[key] = future;
    return future;
  }

  Future<Uint8List?> _doLoadVaultThumb(String vid, String key, int reqId) async {
    bool isCancelled() =>
        !VaultService.instance.isUnlocked(vid) ||
        (_activeVaultKeys[key] ?? 0) <= 0 ||
        _vaultThumbReqIds[key] != reqId;

    if (isCancelled()) return null;

    if (isVaultRoot(widget.root)) {
      try {
        final cached = await _thumbReadSemaphore.withPermit(() async {
          if (isCancelled()) return null;
          return vaultReadThumbnail(
            vaultId: vid,
            relPath: widget.relPath,
          );
        });
        if (cached != null && cached.isNotEmpty) {
          _completedVaultThumbKeys.add(key);
          return cached;
        }
      } catch (_) {}
    }

    if (widget.item.isVideo) {
      if (Platform.isIOS || !PreferencesService.vaultVideoThumbnailsNotifier.value) {
        return null;
      }
      final bytes = await VideoThumbnailService.instance.grabVaultFrameBytes(
        root: widget.root,
        path: widget.relPath,
        isCancelled: isCancelled,
      );
      if (bytes == null || bytes.isEmpty || isCancelled()) return null;
      if (isVaultRoot(widget.root) && VaultService.instance.isUnlocked(vid)) {
        vaultSaveThumbnail(
          vaultId: vid,
          relPath: widget.relPath,
          bytes: bytes,
        ).catchError((_) {});
      }
      _completedVaultThumbKeys.add(key);
      return bytes;
    }

    const maxBytes = 20 * 1024 * 1024;
    if (widget.item.size != null && widget.item.size! > BigInt.from(maxBytes)) {
      return null;
    }
    if (isCancelled()) return null;

    return _thumbGenSemaphore.withPermit(() async {
      if (isCancelled()) return null;

      final raw = await readFileBytes(
        root: widget.root,
        path: widget.relPath,
        maxBytes: BigInt.from(maxBytes),
      );
      if (raw.isEmpty || isCancelled()) return null;

      final codec = await ui.instantiateImageCodec(raw, targetWidth: 160);
      try {
        final frame = await codec.getNextFrame();
        try {
          final data =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) return null;
          final thumbBytes = data.buffer.asUint8List();
          if (isVaultRoot(widget.root) &&
              VaultService.instance.isUnlocked(vid)) {
            vaultSaveThumbnail(
              vaultId: vid,
              relPath: widget.relPath,
              bytes: thumbBytes,
            ).catchError((_) {});
          }
          _completedVaultThumbKeys.add(key);
          return thumbBytes;
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
  }

  Future<String> _export() {
    final key = '${widget.root}\u0000${widget.relPath}';
    final existing = _exports[key];
    if (existing != null) return existing;

    if (_exports.length > 500) {
      _exports.remove(_exports.keys.first);
    }

    final future = _doExport();
    _exports[key] = future;
    // A failed export should not poison the session: drop it so a later
    // build can retry (e.g. after the connection comes back).
    future.then((_) {}, onError: (_) {
      _exports.remove(key);
    });
    return future;
  }

  static Future<String>? _thumbsDirFuture;

  static Future<String> _getThumbsDir() {
    return _thumbsDirFuture ??= () async {
      final base = await getTemporaryDirectory();
      final dir = Directory(joinNative(base.path, 'thumbs'));
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir.path;
    }();
  }

  Future<String> _doExport() async {
    final dirPath = await _getThumbsDir();
    return exportToNative(root: widget.root, path: widget.relPath, cacheDir: dirPath);
  }

  Widget _image(File file, Widget fallback) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        file,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: (widget.size * 2).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Icon(
        widget.item.icon,
        size: widget.size * 0.62,
        color: widget.item.iconColor(context),
      ),
    );
    if (widget.item.isDir) return fallback;

    if (vaultIdFromRoot(widget.root) != null) {
      if (_vaultThumbFuture == null) return fallback;
      return FutureBuilder<Uint8List?>(
        future: _vaultThumbFuture,
        builder: (ctx, snap) {
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) return fallback;
          final img = ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              cacheWidth: (widget.size * 2).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
          if (widget.item.isVideo && widget.size >= 40) {
            return Stack(
              children: [
                img,
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                    shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
                  ),
                ),
              ],
            );
          }
          return img;
        },
      );
    }

    if (widget.item.isVideo) {
      return FutureBuilder<File?>(
        future: _videoFuture,
        builder: (ctx, snap) {
          if (!snap.hasData) return fallback;
          final img = _image(snap.data!, fallback);
          if (widget.size < 40) return img;
          return Stack(
            children: [
              img,
              Positioned(
                right: 2,
                bottom: 2,
                child: Icon(
                  Icons.play_circle_fill,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.9),
                  shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
                ),
              ),
            ],
          );
        },
      );
    }

    if (!widget.item.isImage) return fallback;

    if (isNativeRoot(widget.root)) {
      return _image(File(joinNative(widget.root, widget.relPath)), fallback);
    }

    return FutureBuilder<String>(
      future: _exportFuture,
      builder: (ctx, snap) {
        if (!snap.hasData) return fallback;
        return _image(File(snap.data!), fallback);
      },
    );
  }
}
