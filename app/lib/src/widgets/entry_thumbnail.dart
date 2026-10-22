import 'dart:io';
import 'package:flutter/material.dart';
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
class EntryThumbnail extends StatelessWidget {
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

  static final Map<String, Future<String>> _exports = {};

  Future<String> _export() {
    final key = '$root\u0000$relPath';
    final existing = _exports[key];
    if (existing != null) return existing;
    final future = exportToNative(root: root, path: relPath);
    _exports[key] = future;
    // A failed export should not poison the session: drop it so a later
    // build can retry (e.g. after the connection comes back).
    future.then((_) {}, onError: (_) => _exports.remove(key));
    return future;
  }

  Widget _image(File file, Widget fallback) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).round(),
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      width: size,
      height: size,
      child: Icon(
        item.icon,
        size: size * 0.62,
        color: item.iconColor(context),
      ),
    );
    if (item.isDir) return fallback;

    if (item.isVideo) {
      return FutureBuilder<File?>(
        future:
            VideoThumbnailService.instance.thumbnail(root: root, path: relPath),
        builder: (ctx, snap) {
          if (!snap.hasData) return fallback;
          final img = _image(snap.data!, fallback);
          if (size < 40) return img;
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

    if (!item.isImage) return fallback;

    if (isNativeRoot(root)) {
      return _image(File(joinNative(root, relPath)), fallback);
    }

    return FutureBuilder<String>(
      future: _export(),
      builder: (ctx, snap) {
        if (!snap.hasData) return fallback;
        return _image(File(snap.data!), fallback);
      },
    );
  }
}
