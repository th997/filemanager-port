import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/servers.dart';
import '../services/file_open_service.dart';
import '../services/global_playback_service.dart';
import '../services/path_utils.dart';
import '../services/task_service.dart';
import '../services/vault_service.dart';
import 'package:filemanager/l10n/app_localizations.dart';

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
  final int? sizeBytes;

  /// Resolves a native path on demand, for entries whose bytes live in a
  /// system library (the photo album) rather than on a browsable path.
  final Future<String?> Function()? resolvePath;

  const ImageViewerEntry({
    required this.name,
    this.localPath,
    this.root,
    this.remotePath,
    this.sizeBytes,
    this.resolvePath,
  });

  bool get isLocal => localPath != null;
  bool get canDelete => localPath != null || (root != null && remotePath != null);
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
  late List<ImageViewerEntry> _entries;
  late int _index;
  int _quarterTurns = 0;
  bool _zoomed = false;
  bool _showChrome = true;
  Offset _lastDoubleTapPosition = Offset.zero;
  /// Accumulated downward drag on the current image, used to close on swipe.
  double _dismissDrag = 0;

  /// Cache path per entry (not per index): deleting an image shifts every
  /// later index, and an in-flight download completing after the shift used
  /// to write its path into the wrong slot.
  final Map<ImageViewerEntry, String> _localPaths = {};
  final Map<ImageViewerEntry, Future<String>> _inFlightPaths = {};
  static const int _vaultPrefetchMaxBytes = 12 * 1024 * 1024;
  static const int _vaultDirectMaxBytes = 128 * 1024 * 1024;
  static const int _vaultCacheBudgetBytes = 48 * 1024 * 1024;

  final Map<ImageViewerEntry, Uint8List> _vaultBytes = {};
  final Map<ImageViewerEntry, Future<Uint8List>> _inFlightVaultBytes = {};
  final Map<ImageViewerEntry, String> _vaultStreamUrls = {};
  final Map<ImageViewerEntry, Future<String>> _inFlightVaultStreams = {};
  final Set<ImageViewerEntry> _streamFallbackEntries = {};
  bool _startedMediaStream = false;
  int _vaultCacheBytes = 0;
  bool _vaultAutoClosing = false;

  bool _isVaultEntry(ImageViewerEntry entry) =>
      entry.root != null && vaultIdFromRoot(entry.root!) != null;

  bool _shouldStreamVaultEntry(ImageViewerEntry entry) =>
      _streamFallbackEntries.contains(entry) ||
      (entry.sizeBytes != null && entry.sizeBytes! > _vaultDirectMaxBytes);

  int _decodeCacheWidth(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxLogical =
        mq.size.width > mq.size.height ? mq.size.width : mq.size.height;
    return (maxLogical * mq.devicePixelRatio * 2).round().clamp(1080, 4096);
  }

  void _clearVaultViewerCaches() {
    _vaultBytes.clear();
    _vaultCacheBytes = 0;
    _inFlightVaultBytes.clear();
    _vaultStreamUrls.clear();
    _inFlightVaultStreams.clear();
    _streamFallbackEntries.clear();
  }

  void _onVaultChanged() {
    for (final e in _entries) {
      final vid = e.root != null ? vaultIdFromRoot(e.root!) : null;
      if (vid != null && !VaultService.instance.isUnlocked(vid)) {
        _clearVaultViewerCaches();
        PaintingBinding.instance.imageCache.clear();
        if (!_vaultAutoClosing && mounted) {
          _vaultAutoClosing = true;
          final route = ModalRoute.of(context);
          if (route != null && route.isActive && !route.isFirst) {
            Navigator.of(context).removeRoute(route);
          } else if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
        return;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _entries = widget.siblings.isEmpty
        ? [ImageViewerEntry(name: widget.fileName, localPath: widget.filePath)]
        : List<ImageViewerEntry>.from(widget.siblings);
    _index = widget.initialIndex.clamp(0, _entries.length - 1);

    // If only 1 entry or no siblings were supplied, try to auto-discover
    // sibling images from the local file's parent folder.
    if (_entries.length <= 1 && widget.filePath.isNotEmpty) {
      try {
        final f = File(widget.filePath);
        if (f.existsSync()) {
          final parent = f.parent;
          if (parent.existsSync()) {
            final files = parent.listSync(followLinks: false).whereType<File>().where((file) {
              final name = file.path.split(Platform.pathSeparator).last;
              if (name.startsWith('.')) return false;
              final dot = name.lastIndexOf('.');
              if (dot < 0 || dot == name.length - 1) return false;
              final ext = name.substring(dot + 1).toLowerCase();
              return EntryItem.isImageExtension(ext);
            }).toList();
            if (files.length > 1) {
              files.sort((a, b) {
                final an = a.path.split(Platform.pathSeparator).last.toLowerCase();
                final bn = b.path.split(Platform.pathSeparator).last.toLowerCase();
                return an.compareTo(bn);
              });
              _entries = files.map((file) => ImageViewerEntry(
                name: file.path.split(Platform.pathSeparator).last,
                localPath: file.path,
              )).toList();
              final targetName = widget.fileName;
              final targetPath = widget.filePath;
              final found = _entries.indexWhere((e) => e.localPath == targetPath || e.name == targetName);
              _index = found >= 0 ? found : 0;
            }
          }
        }
      } catch (_) {}
    }

    _pageController = PageController(initialPage: _index);
    _transformationController.addListener(_onTransformChanged);
    VaultService.instance.addListener(_onVaultChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchNeighbors();
    });
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    _clearVaultViewerCaches();
    if (_startedMediaStream && !GlobalPlaybackService.instance.hasActiveSession) {
      stopMediaStreams();
    }
    GlobalPlaybackService.instance.setBottomBarInset(0.0);
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

  void _resetView({bool keepRotation = false}) {
    setState(() {
      _transformationController.value = Matrix4.identity();
      if (!keepRotation) _quarterTurns = 0;
      _zoomed = false;
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= _entries.length) return;
    if (_zoomed) {
      _resetView();
    }
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
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return;
    final indices = _isVaultEntry(_current)
        ? [_index - 1, _index + 1]
        : [_index - 1, _index + 1, _index + 2];
    for (final i in indices) {
      if (i < 0 || i >= _entries.length) continue;
      final neighbor = _entries[i];
      if (_isVaultEntry(neighbor)) {
        if (_shouldStreamVaultEntry(neighbor)) continue;
        if (neighbor.sizeBytes != null &&
            neighbor.sizeBytes! > _vaultPrefetchMaxBytes) {
          continue;
        }
        if (_vaultCacheBytes + (neighbor.sizeBytes ?? 0) >
            _vaultCacheBudgetBytes) {
          continue;
        }
        _vaultBytesFor(i).then((bytes) {
          if (!mounted || bytes.isEmpty) return;
          final cw = _decodeCacheWidth(context);
          precacheImage(
            ResizeImage.resizeIfNeeded(cw, null, MemoryImage(bytes)),
            context,
          ).catchError((_) {});
        }).catchError((_) {});
        continue;
      }
      _localPathFor(i).then((path) {
        if (!mounted || path.isEmpty) return;
        final file = File(path);
        if (file.existsSync()) {
          final cw = _decodeCacheWidth(context);
          precacheImage(
            ResizeImage.resizeIfNeeded(cw, null, FileImage(file)),
            context,
          ).catchError((_) {});
        }
      }).catchError((_) {});
    }
  }

  /// Double-tap zooms to 2.5× around the tapped point; tapping again when
  /// already zoomed returns to fit.
  void _toggleZoom(Offset position) {
    if (_zoomed) {
      // Un-zoom only: double-tap should not also drop the rotation.
      _resetView(keepRotation: true);
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

  Future<({String? dateTaken, String? camera, String? gpsText})>
      _readExifMetaFromBytes(Uint8List? bytes) async {
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
    return (dateTaken: dateTaken, camera: camera, gpsText: gpsText);
  }

  Future<void> _showImageDetails() async {
    final entry = _current;
    if (_isVaultEntry(entry)) {
      if (_shouldStreamVaultEntry(entry)) {
        final imagePath = entry.remotePath ?? entry.name;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context).imageDetails),
            actionsOverflowButtonSpacing: 8,
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(AppLocalizations.of(context).nameLabel, entry.name),
                    if (entry.sizeBytes != null)
                      _detailRow(
                        AppLocalizations.of(context).sizeLabel,
                        _formatSize(entry.sizeBytes!),
                      ),
                    _detailRow(AppLocalizations.of(context).pathLabel, imagePath),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.of(context).close),
              ),
            ],
          ),
        );
        return;
      }
      final Uint8List bytes;
      try {
        bytes = await _vaultBytesFor(_index);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).cannotReadImageDetails('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      Size? dimensions;
      try {
        dimensions = _parseImageDimensions(bytes);
        if (dimensions == null && bytes.length <= 32 * 1024 * 1024) {
          final image = await decodeImageFromList(bytes);
          dimensions = Size(image.width.toDouble(), image.height.toDouble());
          image.dispose();
        }
      } catch (_) {}
      final meta = await _readExifMetaFromBytes(bytes);
      if (!mounted) return;
      final imagePath = entry.remotePath ?? entry.name;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).imageDetails),
          actionsOverflowButtonSpacing: 8,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(AppLocalizations.of(context).nameLabel, entry.name),
                  if (dimensions != null)
                    _detailRow(AppLocalizations.of(context).dimensionsLabel, '${dimensions.width.toInt()} × ${dimensions.height.toInt()} px'),
                  if (meta.dateTaken != null) _detailRow(AppLocalizations.of(context).dateTakenLabel, meta.dateTaken!),
                  if (meta.camera != null) _detailRow(AppLocalizations.of(context).cameraLabel, meta.camera!),
                  if (meta.gpsText != null) _detailRow(AppLocalizations.of(context).locationLabel, meta.gpsText!),
                  _detailRow(AppLocalizations.of(context).sizeLabel, _formatSize(bytes.length)),
                  _detailRow(AppLocalizations.of(context).pathLabel, imagePath),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(context).close),
            ),
          ],
        ),
      );
      return;
    }

    final String native;
    try {
      native = await _localPathFor(_index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).cannotReadImageDetails('$e')), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    if (!mounted) return;
    final file = File(native);
    if (!file.existsSync()) {
      // A cached copy can be evicted between opening the viewer and tapping
      // Details; silently returning made the button look broken.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).imageDetailsUnavailable)),
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
    final meta = await _readExifMetaFromBytes(bytes);

    if (!mounted) return;

    final imagePath = entry.remotePath ?? native;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).imageDetails),
        actionsOverflowButtonSpacing: 8,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(AppLocalizations.of(context).nameLabel, entry.name),
                if (dimensions != null)
                  _detailRow(AppLocalizations.of(context).dimensionsLabel, '${dimensions.width.toInt()} × ${dimensions.height.toInt()} px'),
                if (meta.dateTaken != null) _detailRow(AppLocalizations.of(context).dateTakenLabel, meta.dateTaken!),
                if (meta.camera != null) _detailRow(AppLocalizations.of(context).cameraLabel, meta.camera!),
                if (meta.gpsText != null) _detailRow(AppLocalizations.of(context).locationLabel, meta.gpsText!),
                _detailRow(AppLocalizations.of(context).sizeLabel, _formatSize(stat.size)),
                _detailRow(AppLocalizations.of(context).modifiedLabel, stat.modified.toString().split('.').first),
                _detailRow(AppLocalizations.of(context).pathLabel, imagePath),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(AppLocalizations.of(context).copyPath),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: imagePath));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context).pathCopied)),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).close),
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
    final entry = _entries[index];
    final cached = _localPaths[entry];
    if (cached != null) return Future.value(cached);
    final inFlight = _inFlightPaths[entry];
    if (inFlight != null) return inFlight;

    if (entry.localPath != null) {
      _localPaths[entry] = entry.localPath!;
      return Future.value(entry.localPath!);
    }

    final Future<String> fut;
    final resolver = entry.resolvePath;
    if (resolver != null) {
      fut = resolver().then((path) {
        if (path == null) throw StateError('Cannot read ${entry.name}');
        _localPaths[entry] = path;
        return path;
      });
    } else {
      fut = FileOpenService.instance
          .nativePath(entry.root!, entry.remotePath!)
          .then((path) {
        _localPaths[entry] = path;
        return path;
      });
    }

    _inFlightPaths[entry] = fut;
    fut.whenComplete(() {
      _inFlightPaths.remove(entry);
    });
    return fut;
  }

  void _storeVaultBytes(ImageViewerEntry entry, Uint8List bytes) {
    final prev = _vaultBytes.remove(entry);
    if (prev != null) {
      _vaultCacheBytes -= prev.length;
    }
    while (_vaultBytes.isNotEmpty &&
        (_vaultCacheBytes + bytes.length > _vaultCacheBudgetBytes ||
            _vaultBytes.length >= 6)) {
      ImageViewerEntry? farthest;
      var maxDist = -1;
      for (final k in _vaultBytes.keys) {
        final idx = _entries.indexOf(k);
        final dist = idx < 0 ? 1 << 30 : (idx - _index).abs();
        if (dist > maxDist) {
          maxDist = dist;
          farthest = k;
        }
      }
      if (farthest == null) break;
      final removed = _vaultBytes.remove(farthest);
      if (removed != null) {
        _vaultCacheBytes -= removed.length;
      }
    }
    _vaultBytes[entry] = bytes;
    _vaultCacheBytes += bytes.length;
  }

  Future<Uint8List> _vaultBytesFor(int index) {
    final entry = _entries[index];
    final cached = _vaultBytes[entry];
    if (cached != null) return Future.value(cached);
    final inFlight = _inFlightVaultBytes[entry];
    if (inFlight != null) return inFlight;

    final root = entry.root;
    final remotePath = entry.remotePath;
    if (root == null || remotePath == null) {
      return Future.error(StateError('Missing vault path for ${entry.name}'));
    }
    final vid = vaultIdFromRoot(root);
    if (vid == null || !VaultService.instance.isUnlocked(vid)) {
      return Future.error(StateError('Privacy folder is locked'));
    }

    final fut = readFileBytes(
      root: root,
      path: remotePath,
      maxBytes: BigInt.from(_vaultDirectMaxBytes),
    ).then((bytes) {
      if (!VaultService.instance.isUnlocked(vid)) {
        throw StateError('Privacy folder is locked');
      }
      _storeVaultBytes(entry, bytes);
      return bytes;
    });

    _inFlightVaultBytes[entry] = fut;
    fut.whenComplete(() {
      _inFlightVaultBytes.remove(entry);
    });
    return fut;
  }

  Future<String> _vaultStreamUrlFor(int index) {
    final entry = _entries[index];
    final cached = _vaultStreamUrls[entry];
    if (cached != null) return Future.value(cached);
    final inFlight = _inFlightVaultStreams[entry];
    if (inFlight != null) return inFlight;

    final root = entry.root;
    final remotePath = entry.remotePath;
    if (root == null || remotePath == null) {
      return Future.error(StateError('Missing vault path for ${entry.name}'));
    }
    final vid = vaultIdFromRoot(root);
    if (vid == null || !VaultService.instance.isUnlocked(vid)) {
      return Future.error(StateError('Privacy folder is locked'));
    }

    final fut = startMediaStream(root: root).then((base) {
      if (!VaultService.instance.isUnlocked(vid)) {
        throw StateError('Privacy folder is locked');
      }
      _startedMediaStream = true;
      final trimmed = base.replaceFirst(RegExp(r'/$'), '');
      final encoded = remotePath
          .split('/')
          .where((s) => s.isNotEmpty)
          .map(Uri.encodeComponent)
          .join('/');
      final url = '$trimmed/$encoded';
      _vaultStreamUrls[entry] = url;
      return url;
    });

    _inFlightVaultStreams[entry] = fut;
    fut.whenComplete(() {
      _inFlightVaultStreams.remove(entry);
    });
    return fut;
  }

  Widget _imageFromBytes(Uint8List bytes) {
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      cacheWidth: _decodeCacheWidth(context),
      gaplessPlayback: true,
      errorBuilder: (ctx, err, stack) => Center(
        child: Text(AppLocalizations.of(context).failedToLoadImage, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  Widget _imageFromStreamUrl(String url) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      cacheWidth: _decodeCacheWidth(context),
      gaplessPlayback: true,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        final value = (total != null && total > 0)
            ? progress.cumulativeBytesLoaded / total
            : null;
        return Center(child: CircularProgressIndicator(value: value));
      },
      errorBuilder: (ctx, err, stack) => Center(
        child: Text(AppLocalizations.of(context).failedToLoadImage, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  Widget _buildImageAt(int index, {required bool interactive}) {
    final entry = _entries[index];
    if (_isVaultEntry(entry)) {
      if (_shouldStreamVaultEntry(entry)) {
        final cachedUrl = _vaultStreamUrls[entry];
        if (cachedUrl != null) {
          return _imageFromStreamUrl(cachedUrl);
        }
        return FutureBuilder<String>(
          future: _vaultStreamUrlFor(index),
          builder: (ctx, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLocalizations.of(context).cannotLoadImage('${snapshot.error}'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _imageFromStreamUrl(snapshot.data!);
          },
        );
      }

      final cached = _vaultBytes[entry];
      if (cached != null) {
        return _imageFromBytes(cached);
      }
      return FutureBuilder<Uint8List>(
        future: _vaultBytesFor(index),
        builder: (ctx, snapshot) {
          if (snapshot.hasError) {
            final errStr = '${snapshot.error}';
            if (errStr.contains('exceeds in-memory read limit')) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (_streamFallbackEntries.add(entry)) {
                  setState(() {});
                }
              });
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.of(context).cannotLoadImage(errStr),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(AppLocalizations.of(context).retry),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _imageFromBytes(snapshot.data!);
        },
      );
    }

    final native = entry.localPath ?? _localPaths[entry];

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
                    AppLocalizations.of(context).cannotLoadImage('${snapshot.error}'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(AppLocalizations.of(context).retry),
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
      return Center(
        child: Text(AppLocalizations.of(context).imageFileNotFoundLocally, style: const TextStyle(color: Colors.white70)),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.contain,
      cacheWidth: _decodeCacheWidth(context),
      errorBuilder: (ctx, err, stack) => Center(
        child: Text(AppLocalizations.of(context).failedToLoadImage, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  /// Copies the resolved path, which is what a user needs to paste into a
  /// terminal or another app — the gallery shows no path anywhere else.
  Future<void> _copyCurrentPath() async {
    if (_isVaultEntry(_current)) return;
    try {
      final native = await _localPathFor(_index);
      await Clipboard.setData(ClipboardData(text: native));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).imagePathCopied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).cannotCopyPath('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _shareCurrent() async {
    if (_isVaultEntry(_current)) return;
    try {
      final native = await _localPathFor(_index);
      await SharePlus.instance.share(ShareParams(files: [XFile(native)]));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).cannotShareImage('$e')), backgroundColor: Theme.of(context).colorScheme.error),
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
        title: Text(AppLocalizations.of(context).deleteSingleConfirmTitle(entry.name)),
        content: Text(
          AppLocalizations.of(context).deleteImageConfirm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    if (!entry.canDelete) return;

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
        SnackBar(content: Text(AppLocalizations.of(context).deletedItem(entry.name))),
      );

      setState(() {
        _entries.removeAt(_index);
        _localPaths.remove(entry);
        _inFlightPaths.remove(entry);
        _vaultBytes.remove(entry);
        _inFlightVaultBytes.remove(entry);
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
          content: Text(AppLocalizations.of(context).failedToDelete('$e')),
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
              if (!_isVaultEntry(_current)) ...[
                ListTile(
                  leading: const Icon(Icons.share),
                  title: Text(AppLocalizations.of(context).shareImage),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareCurrent();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: Text(AppLocalizations.of(context).copyPath),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyCurrentPath();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.rotate_right),
                title: Text(AppLocalizations.of(context).rotate90),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(AppLocalizations.of(context).imageDetails),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImageDetails();
                },
              ),
              if (_current.canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(AppLocalizations.of(context).deleteImage, style: const TextStyle(color: Colors.red)),
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
    final hasBottomPill = multiple && !_zoomed && _showChrome;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GlobalPlaybackService.instance.setBottomBarInset(hasBottomPill ? 48.0 : 0.0);
      }
    });

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
          _goTo(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () {
          _goTo(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.pageUp): () {
          _goTo(_index - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          _goTo(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.bracketRight): () {
          _goTo(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.pageDown): () {
          _goTo(_index + 1);
        },
        const SingleActivator(LogicalKeyboardKey.space): () {
          _goTo(_index + 1);
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
                tooltip: AppLocalizations.of(context).rotate90Shortcut,
                onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
              ),
              if (!_isVaultEntry(_current))
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: AppLocalizations.of(context).shareImage,
                  onPressed: _shareCurrent,
                ),
              if (_current.canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: AppLocalizations.of(context).deleteImage,
                  onPressed: _deleteCurrent,
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: AppLocalizations.of(context).moreOptions,
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
                  PopupMenuItem(
                    value: 'details',
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 10),
                        Text(AppLocalizations.of(context).details),
                      ],
                    ),
                  ),
                  if (!_isVaultEntry(_current))
                    PopupMenuItem(
                      value: 'copy_path',
                      child: Row(
                        children: [
                          Icon(Icons.copy_all_outlined, size: 20),
                          SizedBox(width: 10),
                          Text(AppLocalizations.of(context).copyPath),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'zoom_in',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_in, size: 20),
                        SizedBox(width: 10),
                        Text(AppLocalizations.of(context).zoomInShortcut),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'zoom_out',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_out, size: 20),
                        SizedBox(width: 10),
                        Text(AppLocalizations.of(context).zoomOutShortcut),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reset_zoom',
                    child: Row(
                      children: [
                        Icon(Icons.zoom_out_map, size: 20),
                        SizedBox(width: 10),
                        Text(AppLocalizations.of(context).resetZoomShortcut),
                      ],
                    ),
                  ),
                  if (_current.canDelete) ...[
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 10),
                          Text(AppLocalizations.of(context).delete, style: const TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
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
                    // Swipe down to close, the usual gallery gesture. Unregister
                    // the vertical drag recognizer while zoomed so it never competes
                    // with InteractiveViewer's pan gesture.
                    onVerticalDragStart: _zoomed ? null : (_) => _dismissDrag = 0,
                    onVerticalDragUpdate: _zoomed
                        ? null
                        : (details) {
                            _dismissDrag = (_dismissDrag + details.delta.dy)
                                .clamp(0.0, double.infinity);
                          },
                    onVerticalDragEnd: _zoomed
                        ? null
                        : (_) {
                            final dragged = _dismissDrag;
                            _dismissDrag = 0;
                            if (dragged > 120) {
                              Navigator.of(context).maybePop();
                            }
                          },
                    onVerticalDragCancel: _zoomed ? null : () => _dismissDrag = 0,
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
              // Bottom navigation pill with Previous / Position / Next
              if (multiple && !_zoomed && _showChrome)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                              color: _index > 0 ? Colors.white : Colors.white24,
                              tooltip: AppLocalizations.of(context).previousImage,
                              onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '${_index + 1} / ${_entries.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios, size: 14),
                              color: _index < _entries.length - 1 ? Colors.white : Colors.white24,
                              tooltip: AppLocalizations.of(context).nextImage,
                              onPressed: _index < _entries.length - 1 ? () => _goTo(_index + 1) : null,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (multiple && !_zoomed && _showChrome) ...[
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: const Icon(Icons.chevron_left, size: 30),
                        color: _index > 0 ? Colors.white : Colors.white24,
                        tooltip: AppLocalizations.of(context).previousImage,
                        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right, size: 30),
                        color: _index < _entries.length - 1 ? Colors.white : Colors.white24,
                        tooltip: AppLocalizations.of(context).nextImage,
                        onPressed: _index < _entries.length - 1 ? () => _goTo(_index + 1) : null,
                      ),
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
