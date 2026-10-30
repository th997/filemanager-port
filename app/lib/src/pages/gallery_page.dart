import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entry_item.dart';
import '../services/platform_paths.dart';
import '../theme/app_ui_tokens.dart';
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
  bool _showScrollToTop = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _scan();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.position.pixels > 400;
      if (shouldShow != _showScrollToTop) {
        setState(() => _showScrollToTop = shouldShow);
      }
      if (_scrollController.position.pixels >
          _scrollController.position.maxScrollExtent - 800) {
        _loadMore();
      }
    }
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
    // Let the spinner paint before the synchronous folder walk starts;
    // otherwise a large Pictures folder freezes the frame that shows it.
    await Future<void>.delayed(Duration.zero);
    List<_Photo> found;
    try {
      found = Platform.isIOS || Platform.isAndroid
          ? await _loadSystemAlbum()
          : await _scanFolders();
    } catch (e) {
      // A failed scan must not leave the page on a spinner forever.
      if (!mounted) return;
      setState(() {
        _photos = [];
        _loading = false;
        _notice = 'Could not scan for photos.\n$e';
      });
      return;
    }
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
    } catch (e) {
      // Stop paging instead of retrying on every scroll: leaving the total
      // untouched made the scroll listener re-fire the same failing fetch.
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _albumTotal = _photos.length;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load more photos: $e')),
      );
      return;
    }
    if (!mounted) return;
    // A refresh can swap the album while this page was in flight; appending
    // then duplicated tiles or mixed two albums into one grid. The flag still
    // has to clear, or paging stays stuck for the new album.
    if (!identical(path, _albumPath)) {
      setState(() => _loadingMore = false);
      return;
    }
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

  Future<List<_Photo>> _scanFolders() async {
    // The walk is synchronous filesystem I/O over a whole photo tree. On the
    // UI isolate it locked the app for seconds on a large Pictures folder —
    // no scroll, no back, refresh dead. Run it off the main isolate.
    final dirs = PlatformPaths.galleryDirs();
    final found = await Isolate.run(() => _scanGalleryFolders(dirs));
    return found
        .map((e) => _Photo.file(
              e.path.split(Platform.pathSeparator).last,
              File(e.path),
              takenAt: DateTime.fromMillisecondsSinceEpoch(e.modifiedMillis),
            ))
        .toList();
  }

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

  Future<void> _copyPhotoPath(int index) async {
    try {
      final file = await _photos[index].resolve();
      if (file != null && mounted) {
        Clipboard.setData(ClipboardData(text: file.path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied: ${file.path.split(Platform.pathSeparator).last}')),
        );
      }
    } catch (_) {}
  }

  Future<void> _showPhotoActionSheet(int index) async {
    HapticFeedback.mediumImpact();
    final photo = _photos[index];
    final file = await photo.resolve();

    if (!mounted) return;
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
                  photo.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (photo.takenAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _monthLabel(photo.takenAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('Open in Viewer'),
                onTap: () {
                  Navigator.pop(ctx);
                  _open(index);
                },
              ),
              if (file != null) ...[
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share Photo'),
                  onTap: () {
                    Navigator.pop(ctx);
                    SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy File Path'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyPhotoPath(index);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _loading
                ? 'Photos'
                : 'Photos (${_photos.length}${_albumTotal > _photos.length ? '/$_albumTotal' : ''})',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan',
              onPressed: _scan,
            ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: _showScrollToTop
            ? FloatingActionButton.small(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                },
                tooltip: 'Scroll to top',
                child: const Icon(Icons.arrow_upward),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_photos.isEmpty) {
      return RefreshIndicator(
        onRefresh: _scan,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: AppEmptyState(
                icon: Icons.photo_library_outlined,
                title: _notice ?? 'No photos found',
                subtitle: _notice == null && PlatformPaths.galleryDirs().isNotEmpty
                    ? PlatformPaths.galleryDirs().join('\n')
                    : null,
                action: _permissionDenied
                    ? FilledButton.tonalIcon(
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('Open Settings'),
                        onPressed: () => PhotoManager.openSetting(),
                      )
                    : null,
              ),
            ),
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

  List<({String label, int startIndex, List<_Photo> slice})>? _groupedPhotos;
  int _lastGroupedLength = -1;

  List<({String label, int startIndex, List<_Photo> slice})> _getGroupedPhotos() {
    if (_groupedPhotos != null && _lastGroupedLength == _photos.length) {
      return _groupedPhotos!;
    }
    final groups = <({String label, int startIndex, List<_Photo> slice})>[];
    var i = 0;
    while (i < _photos.length) {
      final label = _monthLabel(_photos[i].takenAt);
      var j = i;
      while (j < _photos.length && _monthLabel(_photos[j].takenAt) == label) {
        j++;
      }
      groups.add((
        label: label,
        startIndex: i,
        slice: _photos.sublist(i, j),
      ));
      i = j;
    }
    _lastGroupedLength = _photos.length;
    _groupedPhotos = groups;
    return groups;
  }

  /// Month-grouped grid: photos are newest-first, so equal labels are
  /// contiguous and each group becomes a header + one SliverGrid.
  List<Widget> _buildSlivers() {
    final slivers = <Widget>[];
    final groups = _getGroupedPhotos();
    for (final group in groups) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Text(
              group.label,
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
              (ctx, k) => _buildTile(group.slice[k], group.startIndex + k),
              childCount: group.slice.length,
            ),
          ),
        ),
      );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          thumb != null
              ? _AssetThumb(key: ValueKey(thumb.id), asset: thumb)
              : Image.file(
                  photo.file!,
                  fit: BoxFit.cover,
                  cacheWidth: 220,
                  errorBuilder: (_, _, _) => _brokenThumb(),
                ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _open(index),
              onLongPress: () => _showPhotoActionSheet(index),
            ),
          ),
        ],
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
        if (snapshot.hasError || (snapshot.connectionState == ConnectionState.done && bytes == null)) {
          // A deleted or cloud-only asset has no thumbnail. An empty grey
          // square was indistinguishable from "still loading", so the tile
          // looked stuck instead of broken.
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.outline,
            ),
          );
        }
        if (bytes == null) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              size: 24,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        );
      },
    );
  }
}

/// One scanned picture, as plain data so it can cross an isolate boundary.
class _ScannedPhoto {
  final String path;
  final int modifiedMillis;

  const _ScannedPhoto(this.path, this.modifiedMillis);
}

/// Folder walk for the desktop gallery, run on a worker isolate.
///
/// Top-level so `Isolate.run` can send it; it takes the directory list as an
/// argument because `Platform.environment` is not guaranteed inside a worker.
/// Directories are scanned three levels deep so `DCIM/100APPLE/x.jpg` is
/// included without walking an entire home folder.
List<_ScannedPhoto> _scanGalleryFolders(List<String> dirs) {
  final found = <String>[];
  void collect(Directory dir, int depth) {
    if (depth > 3) return;
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
        collect(entity, depth + 1);
      } else if (entity is File && _isImageName(name)) {
        found.add(entity.path);
      }
    }
  }

  for (final dir in dirs) {
    collect(Directory(dir), 0);
  }
  // Stat each file once up front: statSync inside the sort comparator cost
  // two syscalls per comparison (thousands on a large roll). A file that
  // vanished between listing and stat is skipped, not fatal.
  final result = <_ScannedPhoto>[];
  for (final path in found) {
    try {
      result.add(_ScannedPhoto(path, File(path).statSync().modified.millisecondsSinceEpoch));
    } catch (_) {}
  }
  result.sort((a, b) => b.modifiedMillis.compareTo(a.modifiedMillis));
  return result;
}

/// Mirrors [EntryItem.isImage] without needing a DTO in the worker isolate.
bool _isImageName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif');
}
