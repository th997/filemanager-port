import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_open_service.dart';

/// One image shown by [ImageViewerPage].
///
/// Native images carry [localPath]. Remote and archive images carry the VFS
/// [root] and [remotePath] instead; they are exported to the cache the first
/// time they are shown, so swiping does not download the whole folder up front.
class ImageViewerEntry {
  final String name;
  final String? localPath;
  final String? root;
  final String? remotePath;

  /// Resolves a native path on demand, for entries whose bytes live in a
  /// system library (the photo album) rather than on a browsable path.
  final Future<String?> Function()? resolvePath;

  const ImageViewerEntry({
    required this.name,
    this.localPath,
    this.root,
    this.remotePath,
    this.resolvePath,
  });

  bool get isLocal => localPath != null;
}

class ImageViewerPage extends StatefulWidget {
  final String filePath;
  final String fileName;

  /// Other images in the same folder; swiping left/right moves between them.
  final List<ImageViewerEntry> siblings;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
    this.siblings = const [],
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _transformationController = TransformationController();
  late final PageController _pageController;
  late final List<ImageViewerEntry> _entries;
  late int _index;
  int _quarterTurns = 0;
  bool _zoomed = false;
  Offset _lastDoubleTapPosition = Offset.zero;
  /// Accumulated downward drag on the current image, used to close on swipe.
  double _dismissDrag = 0;

  /// Cache path per entry index, filled in lazily for remote images.
  final Map<int, String> _localPaths = {};

  @override
  void initState() {
    super.initState();
    _entries = widget.siblings.isEmpty
        ? [ImageViewerEntry(name: widget.fileName, localPath: widget.filePath)]
        : widget.siblings;
    _index = widget.initialIndex.clamp(0, _entries.length - 1);
    _pageController = PageController(initialPage: _index);
    _transformationController.addListener(_onTransformChanged);
    _prefetchNeighbors();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  ImageViewerEntry get _current => _entries[_index];

  void _onTransformChanged() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
    }
  }

  void _resetView() {
    setState(() {
      _transformationController.value = Matrix4.identity();
      _quarterTurns = 0;
      _zoomed = false;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= _entries.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _quarterTurns = 0;
      _zoomed = false;
      _transformationController.value = Matrix4.identity();
    });
    _prefetchNeighbors();
  }

  /// Warm the cache for the previous/next image so a swipe does not wait for
  /// a fresh remote download.
  void _prefetchNeighbors() {
    for (final i in [_index - 1, _index + 1]) {
      if (i < 0 || i >= _entries.length) continue;
      _localPathFor(i).catchError((_) => '');
    }
  }

  /// Double-tap zooms to 2.5× around the tapped point; tapping again when
  /// already zoomed returns to fit.
  void _toggleZoom(Offset position) {
    if (_zoomed) {
      _resetView();
      return;
    }
    const scale = 2.5;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    setState(() => _transformationController.value = matrix);
  }

  void _zoomBy(double factor) {
    final current = _transformationController.value;
    final scale = current.getMaxScaleOnAxis();
    final newScale = (scale * factor).clamp(0.2, 6.0);
    final ratio = newScale / scale;
    setState(() {
      _transformationController.value = current.clone()..scaleByDouble(ratio, ratio, 1.0, 1.0);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _showImageDetails() async {
    final entry = _current;
    final String native;
    try {
      native = await _localPathFor(_index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot read image details: $e'), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    if (!mounted) return;
    final file = File(native);
    if (!file.existsSync()) return;

    final stat = file.statSync();
    Size? dimensions;
    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      dimensions = Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {}

    // EXIF: the real capture date and camera, instead of letting the
    // file's Modified time pose as when the photo was taken. The parser
    // simply finds no tags for formats without EXIF (PNG, WebP).
    String? dateTaken;
    String? camera;
    String? gpsText;
    if (bytes != null) {
      try {
        final tags = await readExifFromBytes(bytes);
        final dt = tags['EXIF DateTimeOriginal']?.printable.trim();
        if (dt != null && dt.length >= 19) {
          dateTaken =
              '${dt.substring(0, 4)}-${dt.substring(5, 7)}-${dt.substring(8, 19)}';
        }
        final make = tags['Image Make']?.printable.trim();
        final model = tags['Image Model']?.printable.trim();
        if (model != null && model.isNotEmpty) {
          camera = (make != null &&
                  make.isNotEmpty &&
                  !model.toLowerCase().startsWith(make.toLowerCase()))
              ? '$make $model'
              : model;
        }
        final lat = _gpsCoordinate(
          tags['GPS GPSLatitude'],
          tags['GPS GPSLatitudeRef']?.printable.trim(),
        );
        final lon = _gpsCoordinate(
          tags['GPS GPSLongitude'],
          tags['GPS GPSLongitudeRef']?.printable.trim(),
        );
        if (lat != null && lon != null) {
          gpsText = '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final imagePath = entry.remotePath ?? native;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Name', entry.name),
            if (dimensions != null)
              _detailRow('Dimensions', '${dimensions.width.toInt()} × ${dimensions.height.toInt()} px'),
            if (dateTaken != null) _detailRow('Date taken', dateTaken),
            if (camera != null) _detailRow('Camera', camera),
            if (gpsText != null) _detailRow('Location', gpsText),
            _detailRow('Size', _formatSize(stat.size)),
            _detailRow('Modified', stat.modified.toString().split('.').first),
            _detailRow('Path', imagePath),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: imagePath));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// EXIF GPS coordinates are stored as degree/minute/second rationals;
  /// the ref ('N'/'S', 'E'/'W') carries the sign.
  double? _gpsCoordinate(IfdTag? tag, String? ref) {
    if (tag == null || ref == null) return null;
    try {
      final parts = tag.values.toList();
      if (parts.length < 3) return null;
      double val(dynamic r) {
        final n = (r.numerator as num).toDouble();
        final d = (r.denominator as num).toDouble();
        return d == 0 ? 0 : n / d;
      }

      var result = val(parts[0]) + val(parts[1]) / 60 + val(parts[2]) / 3600;
      if (ref == 'S' || ref == 'W') result = -result;
      return result;
    } catch (_) {
      return null;
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Native path for an entry, exporting remote and archive images once.
  Future<String> _localPathFor(int index) {
    final cached = _localPaths[index];
    if (cached != null) return Future.value(cached);

    final entry = _entries[index];
    if (entry.localPath != null) {
      _localPaths[index] = entry.localPath!;
      return Future.value(entry.localPath!);
    }
    final resolver = entry.resolvePath;
    if (resolver != null) {
      return resolver().then((path) {
        if (path == null) throw StateError('Cannot read ${entry.name}');
        _localPaths[index] = path;
        return path;
      });
    }
    return FileOpenService.instance
        .nativePath(entry.root!, entry.remotePath!)
        .then((path) {
      _localPaths[index] = path;
      return path;
    });
  }

  Widget _buildImageAt(int index, {required bool interactive}) {
    final entry = _entries[index];
    final native = entry.localPath ?? _localPaths[index];

    if (native != null) {
      return _imageFromFile(native, interactive);
    }

    // Remote/archive image: download on first view, showing progress.
    return FutureBuilder<String>(
      future: _localPathFor(index),
      builder: (ctx, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Cannot load image: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _imageFromFile(snapshot.data!, interactive);
      },
    );
  }

  Widget _imageFromFile(String path, bool interactive) {
    final file = File(path);
    if (!file.existsSync()) {
      return const Center(
        child: Text('Image file not found locally', style: TextStyle(color: Colors.white70)),
      );
    }
    // Decode at display size: a full-resolution decode of a 24 MP photo
    // costs ~96 MB, and the PageView keeps neighbouring pages resident.
    final display = MediaQuery.of(context).size;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    return Image.file(
      file,
      fit: BoxFit.contain,
      cacheWidth: (display.width * pixelRatio).round(),
      cacheHeight: (display.height * pixelRatio).round(),
      errorBuilder: (ctx, err, stack) => const Center(
        child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  Future<void> _shareCurrent() async {
    try {
      final native = await _localPathFor(_index);
      await SharePlus.instance.share(ShareParams(files: [XFile(native)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot share image: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _entries.length > 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.add): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.add, control: true): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.add, meta: true): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.digit0): _resetView,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _resetView,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _resetView,
        const SingleActivator(LogicalKeyboardKey.numpad0): _resetView,
        const SingleActivator(LogicalKeyboardKey.numpad0, control: true): _resetView,
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (!_zoomed) _goTo(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () {
          if (!_zoomed) _goTo(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (!_zoomed) _goTo(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.bracketRight): () {
          if (!_zoomed) _goTo(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            title: Text(
              multiple
                  ? '${_current.name}  (${_index + 1}/${_entries.length})'
                  : _current.name,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: 'Zoom in (+ / Ctrl+=)',
                onPressed: () => _zoomBy(1.25),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: 'Zoom out (- / Ctrl+-)',
                onPressed: () => _zoomBy(0.8),
              ),
              IconButton(
                icon: const Icon(Icons.rotate_right),
                tooltip: 'Rotate 90° (R)',
                onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out_map),
                tooltip: 'Reset zoom (0 / Ctrl+0)',
                onPressed: _resetView,
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share image',
                onPressed: _shareCurrent,
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Details',
                onPressed: _showImageDetails,
              ),
            ],
          ),
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: _entries.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, i) {
                  if (i != _index) {
                    // Off-screen pages stay simple; zoom applies to the
                    // visible one only.
                    return Center(child: _buildImageAt(i, interactive: false));
                  }
                  return GestureDetector(
                    onDoubleTapDown: (details) =>
                        _lastDoubleTapPosition = details.localPosition,
                    onDoubleTap: () => _toggleZoom(_lastDoubleTapPosition),
                    // Swipe down to close, the usual gallery gesture. Zoomed
                    // images keep the drag so panning still works.
                    onVerticalDragUpdate: (details) {
                      if (!_zoomed && details.delta.dy > 0) _dismissDrag += details.delta.dy;
                    },
                    onVerticalDragEnd: (_) {
                      final dragged = _dismissDrag;
                      _dismissDrag = 0;
                      if (!_zoomed && dragged > 120) {
                        Navigator.of(context).maybePop();
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.2,
                      maxScale: 6.0,
                      // At fit scale there is nothing to pan, and the viewer's
                      // own pan recognizer would eat the swipe-down-to-close.
                      panEnabled: _zoomed,
                      child: RotatedBox(
                        quarterTurns: _quarterTurns,
                        child: _buildImageAt(i, interactive: true),
                      ),
                    ),
                  );
                },
              ),
              // A long file name truncates the app bar title, so the position
              // in the set gets its own chip.
              if (multiple && !_zoomed)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_index + 1} / ${_entries.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (multiple && !_zoomed) ...[
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, size: 32),
                      color: Colors.white70,
                      tooltip: 'Previous image',
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right, size: 32),
                      color: Colors.white70,
                      tooltip: 'Next image',
                      onPressed: _index < _entries.length - 1 ? () => _goTo(_index + 1) : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
