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

  /// Capture date (library assets) or modification time (files); drives
  /// the month grouping in the grid.
  final DateTime? takenAt;

  const _Photo.file(this.name, File this.file, {this.takenAt}) : asset = null;
  const _Photo.asset(this.name, AssetEntity this.asset, {this.takenAt})
      : file = null;

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

  /// System-library paging: the album can hold tens of thousands of
  /// assets, so it is loaded a page at a time while scrolling. The old
  /// code fetched 5,000 up front and silently showed nothing beyond.
  static const int _pageSize = 200;
  AssetPathEntity? _albumPath;
  int _albumTotal = 0;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 800) {
        _loadMore();
      }
    });
    _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
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
      _albumPath = null;
      _albumTotal = 0;
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
    _albumPath = paths.first;
    _albumTotal = await paths.first.assetCountAsync;
    final end = _albumTotal < _pageSize ? _albumTotal : _pageSize;
    final assets = await paths.first.getAssetListRange(start: 0, end: end);
    return assets
        .map((a) => _Photo.asset(a.title ?? a.id, a, takenAt: a.createDateTime))
        .toList();
  }

  Future<void> _loadMore() async {
    final path = _albumPath;
    if (path == null || _loadingMore || _photos.length >= _albumTotal) {
      return;
    }
    setState(() => _loadingMore = true);
    final start = _photos.length;
    final end = start + _pageSize < _albumTotal
        ? start + _pageSize
        : _albumTotal;
    List<AssetEntity> assets;
    try {
      assets = await path.getAssetListRange(start: start, end: end);
    } catch (_) {
      assets = [];
    }
    if (!mounted) return;
    setState(() {
      _photos = [
        ..._photos,
        ...assets.map(
          (a) => _Photo.asset(a.title ?? a.id, a, takenAt: a.createDateTime),
        ),
      ];
      _loadingMore = false;
    });
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
        .map((f) => _Photo.file(
              f.path.split(Platform.pathSeparator).last,
              f,
              takenAt: mtimes[f],
            ))
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
          SnackBar(content: Text('Cannot open photo: $e'), backgroundColor: Theme.of(context).colorScheme.error),
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
          _loading
              ? 'Photos'
              : 'Photos (${_photos.length}${_albumTotal > _photos.length ? '/$_albumTotal' : ''})',
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
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _scan,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _buildSlivers(),
      ),
    );
  }

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _monthLabel(DateTime? d) =>
      d == null ? 'Unknown date' : '${_monthNames[d.month - 1]} ${d.year}';

  /// Month-grouped grid: photos are newest-first, so equal labels are
  /// contiguous and each group becomes a header + one SliverGrid.
  List<Widget> _buildSlivers() {
    final slivers = <Widget>[];
    var i = 0;
    while (i < _photos.length) {
      final label = _monthLabel(_photos[i].takenAt);
      var j = i;
      while (j < _photos.length && _monthLabel(_photos[j].takenAt) == label) {
        j++;
      }
      final slice = _photos.sublist(i, j);
      final startIndex = i;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, k) => _buildTile(slice[k], startIndex + k),
              childCount: slice.length,
            ),
          ),
        ),
      );
      i = j;
    }
    if (_loadingMore) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }
    return slivers;
  }

  Widget _buildTile(_Photo photo, int index) {
    final thumb = photo.asset;
    return GestureDetector(
      onTap: () => _open(index),
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
