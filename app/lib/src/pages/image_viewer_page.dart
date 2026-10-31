import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/file_open_service.dart';
import '../services/task_service.dart';
import '../widgets/app_swipe_back.dart';

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
  bool _showChrome = true;
  Offset _lastDoubleTapPosition = Offset.zero;
  /// Accumulated downward drag on the current image, used to close on swipe.
  double _dismissDrag = 0;

  /// Cache path per entry index, filled in lazily for remote images.
  final Map<int, String> _localPaths = {};
  final Map<int, Future<String>> _inFlightPaths = {};

  @override
  void initState() {
    super.initState();
    _entries = widget.siblings.isEmpty
        ? [ImageViewerEntry(name: widget.fileName, localPath: widget.filePath)]
        : List<ImageViewerEntry>.from(widget.siblings);
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

  /// Warm the cache for previous and upcoming images so a swipe does not wait
  /// for a fresh remote download or image decode.
  void _prefetchNeighbors() {
    for (final i in [_index - 1, _index + 1, _index + 2]) {
      if (i < 0 || i >= _entries.length) continue;
      _localPathFor(i).then((path) {
        if (!mounted || path.isEmpty) return;
        final file = File(path);
        if (file.existsSync()) {
          precacheImage(FileImage(file), context).catchError((_) {});
        }
      }).catchError((_) {});
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
    if (scale <= 0.0001 || scale.isNaN) return;
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
        SnackBar(content: Text('Cannot read image details: $e'), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    if (!mounted) return;
    final file = File(native);
    if (!file.existsSync()) {
      // A cached copy can be evicted between opening the viewer and tapping
      // Details; silently returning made the button look broken.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image details are no longer available')),
      );
      return;
    }

    final stat = file.statSync();
    Size? dimensions;
    Uint8List? bytes;
    try {
      if (stat.size <= 32 * 1024 * 1024) {
        bytes = await file.readAsBytes();
      } else {
        // Read just the head — enough for header parsing and EXIF
        final raf = await file.open();
        try {
          bytes = await raf.read(256 * 1024);
        } finally {
          await raf.close();
        }
      }
      dimensions = _parseImageDimensions(bytes);
      if (dimensions == null && stat.size <= 32 * 1024 * 1024) {
        final image = await decodeImageFromList(bytes);
        dimensions = Size(image.width.toDouble(), image.height.toDouble());
        image.dispose();
      }
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
        actionsOverflowButtonSpacing: 8,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
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
          ),
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

  static Size? _parseImageDimensions(Uint8List bytes) {
    if (bytes.length < 16) return null;
    // PNG: 8-byte signature: 137 80 78 71 13 10 26 10
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      if (bytes.length >= 24) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
      }
    }
    // GIF: GIF87a or GIF89a
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      if (bytes.length >= 10) {
        final w = bytes[6] | (bytes[7] << 8);
        final h = bytes[8] | (bytes[9] << 8);
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
      }
    }
    // BMP: BM
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      if (bytes.length >= 26) {
        final w = bytes[18] | (bytes[19] << 8) | (bytes[20] << 16) | (bytes[21] << 24);
        final h = (bytes[22] | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24)).abs();
        if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
      }
    }
    // JPEG: 0xFF, 0xD8
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      var offset = 2;
      while (offset + 4 < bytes.length) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        offset += 2;
        if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
          if (offset + 7 <= bytes.length) {
            final h = (bytes[offset + 3] << 8) | bytes[offset + 4];
            final w = (bytes[offset + 5] << 8) | bytes[offset + 6];
            if (w > 0 && h > 0) return Size(w.toDouble(), h.toDouble());
          }
          break;
        } else if (marker == 0xD9 || marker == 0xDA) {
          break;
        } else {
          if (offset + 2 > bytes.length) break;
          final len = (bytes[offset] << 8) | bytes[offset + 1];
          if (len < 2) break;
          offset += len;
        }
      }
    }
    return null;
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
    final inFlight = _inFlightPaths[index];
    if (inFlight != null) return inFlight;

    final entry = _entries[index];
    if (entry.localPath != null) {
      _localPaths[index] = entry.localPath!;
      return Future.value(entry.localPath!);
    }

    final Future<String> fut;
    final resolver = entry.resolvePath;
    if (resolver != null) {
      fut = resolver().then((path) {
        if (path == null) throw StateError('Cannot read ${entry.name}');
        _localPaths[index] = path;
        return path;
      });
    } else {
      fut = FileOpenService.instance
          .nativePath(entry.root!, entry.remotePath!)
          .then((path) {
        _localPaths[index] = path;
        return path;
      });
    }

    _inFlightPaths[index] = fut;
    fut.whenComplete(() {
      _inFlightPaths.remove(index);
    });
    return fut;
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
    return Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (ctx, err, stack) => const Center(
        child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  /// Copies the resolved path, which is what a user needs to paste into a
  /// terminal or another app — the gallery shows no path anywhere else.
  Future<void> _copyCurrentPath() async {
    try {
      final native = await _localPathFor(_index);
      await Clipboard.setData(ClipboardData(text: native));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image path copied')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot copy path: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _shareCurrent() async {
    try {
      final native = await _localPathFor(_index);
      await SharePlus.instance.share(ShareParams(files: [XFile(native)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot share image: $e'), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  Future<void> _deleteCurrent() async {
    HapticFeedback.mediumImpact();
    final entry = _current;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
        title: Text('Delete "${entry.name}"?'),
        content: const Text(
          'Are you sure you want to delete this image? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      if (entry.localPath != null) {
        final f = File(entry.localPath!);
        if (f.existsSync()) {
          await f.delete();
        }
      } else if (entry.root != null && entry.remotePath != null) {
        await TaskService.instance.delete(root: entry.root!, paths: [entry.remotePath!]);
      }

      HapticFeedback.lightImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${entry.name}')),
      );

      setState(() {
        _entries.removeAt(_index);
        _localPaths.remove(_index);
        _inFlightPaths.remove(_index);
        final newLocal = <int, String>{};
        _localPaths.forEach((k, v) {
          if (k < _index) {
            newLocal[k] = v;
          } else if (k > _index) {
            newLocal[k - 1] = v;
          }
        });
        _localPaths
          ..clear()
          ..addAll(newLocal);

        final newInFlight = <int, Future<String>>{};
        _inFlightPaths.forEach((k, v) {
          if (k < _index) {
            newInFlight[k] = v;
          } else if (k > _index) {
            newInFlight[k - 1] = v;
          }
        });
        _inFlightPaths
          ..clear()
          ..addAll(newInFlight);
      });

      if (_entries.isEmpty) {
        Navigator.of(context).pop();
      } else {
        final newIndex = _index.clamp(0, _entries.length - 1);
        _index = newIndex;
        _pageController.jumpToPage(newIndex);
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showQuickActionsSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _current.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share Image'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareCurrent();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('Copy Path'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyCurrentPath();
                },
              ),
              ListTile(
                leading: const Icon(Icons.rotate_right),
                title: const Text('Rotate 90°'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Image Details'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImageDetails();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Image', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteCurrent();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final multiple = _entries.length > 1;

    return AppSwipeBack(
      child: CallbackShortcuts(
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
          extendBodyBehindAppBar: true,
          appBar: _showChrome
              ? AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  backgroundColor: Colors.black.withValues(alpha: 0.65),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  title: Text(
              multiple
                  ? '${_current.name}  (${_index + 1}/${_entries.length})'
                  : _current.name,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.rotate_right),
                tooltip: 'Rotate 90° (R)',
                onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share image',
                onPressed: _shareCurrent,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete image',
                onPressed: _deleteCurrent,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (action) {
                  switch (action) {
                    case 'zoom_in':
                      _zoomBy(1.25);
                      break;
                    case 'zoom_out':
                      _zoomBy(0.8);
                      break;
                    case 'reset_zoom':
                      _resetView();
                      break;
                    case 'copy_path':
                      _copyCurrentPath();
                      break;
                    case 'details':
                      _showImageDetails();
                      break;
                    case 'delete':
                      _deleteCurrent();
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 10),
                        Text('Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy_path',
                    child: Row(
                      children: [
                        Icon(Icons.copy_all_outlined, size: 20),
                        SizedBox(width: 10),
                        Text('Copy Path'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'zoom_in',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_in, size: 20),
                        SizedBox(width: 10),
                        Text('Zoom in (+)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'zoom_out',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_out, size: 20),
                        SizedBox(width: 10),
                        Text('Zoom out (-)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reset_zoom',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_out_map, size: 20),
                        SizedBox(width: 10),
                        Text('Reset zoom (0)'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          )
        : null,
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
                    onTap: () => setState(() => _showChrome = !_showChrome),
                    onLongPress: _showQuickActionsSheet,
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
              if (multiple && !_zoomed && _showChrome)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: SafeArea(
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
                ),
              if (multiple && !_zoomed && _showChrome) ...[
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
    ),
    );
  }
}
