import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/platform_paths.dart';
import 'image_viewer_page.dart';

/// One picture shown by the gallery.
///
/// On phones this is a system-library asset; on desktop it is a file found by
/// scanning the usual picture folders.
class _Photo {
  final String name;
  final File? file;
  final AssetEntity? asset;

  const _Photo.file(this.name, File this.file) : asset = null;
  const _Photo.asset(this.name, AssetEntity this.asset) : file = null;

  Future<File?> resolve() async => file ?? await asset?.file;
}

/// Photo library: the system photo album on phones, scanned picture folders
/// on desktop.
///
/// Browsing a folder still works through `BrowserPage`; this page is a
/// thumbnail grid for the places photos actually live.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> with WidgetsBindingObserver {
  /// Directories are scanned this deep so `DCIM/100APPLE/x.jpg` is included
  /// without walking an entire home folder.
  static const int _maxDepth = 3;

  List<_Photo> _photos = [];
  bool _loading = true;
  String? _notice;
  /// Set when the system library refused access, so the empty state can offer
  /// a jump to Settings instead of a dead end.
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The permission prompt sends the user to Settings; coming back should
  /// pick up the newly granted access instead of showing the old refusal.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionDenied) _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _notice = null;
      _permissionDenied = false;
    });
    final found = Platform.isIOS || Platform.isAndroid
        ? await _loadSystemAlbum()
        : _scanFolders();
    if (!mounted) return;
    setState(() {
      _photos = found;
      _loading = false;
    });
  }

  /// Photos and videos live in the system library on iOS; the app sandbox
  /// only sees files the user put there, so scanning Documents finds nothing.
  Future<List<_Photo>> _loadSystemAlbum() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      _permissionDenied = true;
      _notice = 'Photo library access denied.\nEnable it in Settings → Privacy → Photos.';
      return [];
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (paths.isEmpty) return [];
    final assets = await paths.first.getAssetListRange(start: 0, end: 5000);
    return assets.map((a) => _Photo.asset(a.title ?? a.id, a)).toList();
  }

  List<_Photo> _scanFolders() {
    final found = <File>[];
    for (final dir in PlatformPaths.galleryDirs()) {
      _collect(Directory(dir), 0, found);
    }
    // Stat each file once up front: statSync inside the sort comparator
    // cost two syscalls per comparison (thousands on a large roll).
    final mtimes = <File, DateTime>{
      for (final f in found) f: f.statSync().modified,
    };
    found.sort((a, b) => mtimes[b]!.compareTo(mtimes[a]!));
    return found
        .map((f) => _Photo.file(f.path.split(Platform.pathSeparator).last, f))
        .toList();
  }

  void _collect(Directory dir, int depth, List<File> out) {
    if (depth > _maxDepth) return;
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entity in entities) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      if (entity is Directory) {
        _collect(entity, depth + 1, out);
      } else if (entity is File) {
        if (EntryItem(_stubDto(name)).isImage) out.add(entity);
      }
    }
  }

  /// [EntryItem] derives its type from the name only, so a stub DTO is enough.
  static EntryDto _stubDto(String name) => EntryDto(
        name: name,
        path: name,
        isDir: false,
        hidden: false,
        isSymlink: false,
      );

  Future<void> _open(int index) async {
    final File? file;
    try {
      file = await _photos[index].resolve();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open photo: $e'), backgroundColor: Colors.red.shade700),
        );
      }
      return;
    }
    if (file == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo is no longer available')),
        );
      }
      return;
    }
    // Siblings resolve lazily inside the viewer: each asset.file may copy
    // bytes out of the library, so touching the whole roll up front is slow.
    final siblings = _photos
        .map((p) => ImageViewerEntry(
              name: p.name,
              localPath: p.file?.path,
              resolvePath: p.file == null
                  ? () async => (await p.asset!.file)?.path
                  : null,
            ))
        .toList();
    final resolved = file;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          filePath: resolved.path,
          fileName: _photos[index].name,
          siblings: siblings,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loading ? 'Photos' : 'Photos (${_photos.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Rescan',
            onPressed: _scan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                _notice ?? 'No photos found',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (_permissionDenied) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Open Settings'),
                  onPressed: () => PhotoManager.openSetting(),
                ),
              ],
              if (_notice == null) ...[
                const SizedBox(height: 4),
                Text(
                  PlatformPaths.galleryDirs().join('\n'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _scan,
      child: GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _photos.length,
      itemBuilder: (ctx, i) {
        final photo = _photos[i];
        final thumb = photo.asset;
        return GestureDetector(
          onTap: () => _open(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: thumb != null
                ? _AssetThumb(key: ValueKey(thumb.id), asset: thumb)
                : Image.file(
                    photo.file!,
                    fit: BoxFit.cover,
                    // Decode at thumbnail size; full-size decode of a photo
                    // roll would exhaust memory.
                    cacheWidth: 220,
                    errorBuilder: (_, _, _) => _brokenThumb(),
                  ),
          ),
        );
      },
      ),
    );
  }

  /// `_open` needs the photo at [index]; thumbnails are cheap to reload but a
  /// missing source file should still be visible as broken, not blank.
  Widget _brokenThumb() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.broken_image, size: 20),
      );
}

/// One system-library thumbnail, decoded once per tile.
class _AssetThumb extends StatefulWidget {
  final AssetEntity asset;

  const _AssetThumb({super.key, required this.asset});

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  late final Future<Uint8List?> _data = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize.square(220),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _data,
      builder: (ctx, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}
