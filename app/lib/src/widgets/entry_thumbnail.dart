import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/video_thumbnail_service.dart';

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

  Future<File?>? _videoFuture;
  Future<String>? _exportFuture;

  @override
  void initState() {
    super.initState();
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

  void _initFutures() {
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
        cacheHeight: (widget.size * 2).round(),
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
