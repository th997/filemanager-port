import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import '../models/entry_item.dart';
import '../services/external_file_service.dart';
import '../services/image_privacy_service.dart';
import '../services/platform_capabilities.dart';
import '../services/platform_paths.dart';
import '../theme/app_ui_tokens.dart';
import 'image_viewer_page.dart';
import 'photo_backup_page.dart';
import 'package:filemanager/l10n/app_localizations.dart';

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

  String get key => asset != null ? 'asset:${asset!.id}' : 'file:${file!.path}';

  Future<File?> resolve() async => file ?? await asset?.file;
}

/// Photo library: the system photo album on phones, scanned picture folders
/// on desktop.
///
/// Browsing a folder still works through `BrowserPage`; this page is a
/// thumbnail grid for the places photos actually live.
class GalleryPage extends StatefulWidget {
  final ExternalPickRequest? pickRequest;
  final Future<List<File>> Function()? scanFilesOverride;
  final Future<int> Function(List<File> files)? deleteFilesOverride;
  final Future<void> Function(List<String> paths)? shareFilesOverride;

  const GalleryPage({
    super.key,
    this.pickRequest,
    this.scanFilesOverride,
    this.deleteFilesOverride,
    this.shareFilesOverride,
  });

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
  final ValueNotifier<bool> _showScrollToTopNotifier = ValueNotifier<bool>(false);
  final ScrollController _scrollController = ScrollController();

  final Set<String> _selectedKeys = {};
  late bool _isSelecting = _isMultiPickMode;
  int? _lastSelectedIndex;
  bool _batchBusy = false;

  bool get _isMultiPickMode => widget.pickRequest?.allowMultiple == true;

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
      if (shouldShow != _showScrollToTopNotifier.value) {
        _showScrollToTopNotifier.value = shouldShow;
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
    _showScrollToTopNotifier.dispose();
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
      if (widget.scanFilesOverride != null) {
        final files = await widget.scanFilesOverride!();
        found = files
            .map((f) => _Photo.file(
                  f.path.split(Platform.pathSeparator).last,
                  f,
                  takenAt: f.existsSync() ? f.statSync().modified : null,
                ))
            .toList();
      } else {
        found = Platform.isIOS || Platform.isAndroid
            ? await _loadSystemAlbum()
            : await _scanFolders();
      }
    } catch (e) {
      // A failed scan must not leave the page on a spinner forever.
      if (!mounted) return;
      setState(() {
        _photos = [];
        _loading = false;
        _selectedKeys.clear();
        if (!_isMultiPickMode) _isSelecting = false;
        _groupedPhotos = null;
        _lastGroupedLength = -1;
        _notice = mounted ? AppLocalizations.of(context).couldNotScanPhotos('$e') : 'Could not scan for photos.\n$e';
      });
      return;
    }
    if (!mounted) return;
    final availableKeys = found.map((p) => p.key).toSet();
    setState(() {
      _photos = found;
      _loading = false;
      _groupedPhotos = null;
      _lastGroupedLength = -1;
      _selectedKeys.retainAll(availableKeys);
      if (!_isMultiPickMode && found.isEmpty) {
        _isSelecting = false;
      }
    });
  }

  /// Photos and videos live in the system library on iOS; the app sandbox
  /// only sees files the user put there, so scanning Documents finds nothing.
  Future<List<_Photo>> _loadSystemAlbum() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      _permissionDenied = true;
      _notice = mounted ? AppLocalizations.of(context).photoLibraryDenied : 'Photo library access denied.';
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
        SnackBar(content: Text(AppLocalizations.of(context).couldNotLoadMorePhotos('$e'))),
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
          SnackBar(content: Text(AppLocalizations.of(context).cannotOpenPhoto('$e')), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
      return;
    }
    if (file == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).photoNoLongerAvailable)),
        );
      }
      return;
    }
    if (widget.pickRequest != null) {
      if (widget.pickRequest!.matchesFileName(file.path)) {
        Navigator.of(context).pop([file.path]);
        return;
      }
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
              deleteHandler: p.file == null && p.asset != null
                  ? () async {
                      final deleted = await PhotoManager.editor.deleteWithIds(
                        [p.asset!.id],
                      );
                      return deleted.isNotEmpty;
                    }
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
          onDeleted: () {
            if (!mounted) return;
            setState(() {
              _groupedPhotos = null;
              _lastGroupedLength = -1;
            });
            _scan();
          },
        ),
      ),
    );
  }

  Future<void> _deletePhoto(int index) async {
    if (index < 0 || index >= _photos.length) return;
    final photo = _photos[index];
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
        title: Text(l10n.deleteSingleConfirmTitle(photo.name)),
        content: Text(l10n.deleteImageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      bool deleted = false;
      if (photo.file != null) {
        if (photo.file!.existsSync()) {
          await photo.file!.delete();
        }
        deleted = true;
      } else if (photo.asset != null) {
        final ids = await PhotoManager.editor.deleteWithIds([photo.asset!.id]);
        deleted = ids.isNotEmpty;
      }
      if (!deleted || !mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        if (index < _photos.length && identical(_photos[index], photo)) {
          _photos.removeAt(index);
        } else {
          _photos.remove(photo);
        }
        _groupedPhotos = null;
        _lastGroupedLength = -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deletedItem(photo.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.failedToDelete('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showPhotoContextMenu(Offset globalPosition, int index) async {
    if (index < 0 || index >= _photos.length) return;
    HapticFeedback.mediumImpact();
    final photo = _photos[index];
    final file = await photo.resolve();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'select',
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 18),
              const SizedBox(width: 10),
              Text(l10n.selectItems),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              const Icon(Icons.fullscreen, size: 18),
              const SizedBox(width: 10),
              Text(l10n.openInViewer),
            ],
          ),
        ),
        if (file != null) ...[
          if (PlatformCapabilities.supportsNativeShareSheet)
            PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  const Icon(Icons.share, size: 18),
                  const SizedBox(width: 10),
                  Text(l10n.sharePhoto),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'copy_path',
            child: Row(
              children: [
                const Icon(Icons.copy_outlined, size: 18),
                const SizedBox(width: 10),
                Text(l10n.copyFilePath),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 10),
              Text(l10n.deleteImage, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'select':
        _enterSelectionMode(index);
        break;
      case 'open':
        _open(index);
        break;
      case 'share':
        if (file != null) {
          SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
        }
        break;
      case 'copy_path':
        _copyPhotoPath(index);
        break;
      case 'delete':
        _deletePhoto(index);
        break;
    }
  }

  Future<void> _copyPhotoPath(int index) async {
    try {
      final file = await _photos[index].resolve();
      if (file != null && mounted) {
        Clipboard.setData(ClipboardData(text: file.path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).copiedValue(file.path.split(Platform.pathSeparator).last))),
        );
      }
    } catch (_) {}
  }

  List<_Photo> get _selectedPhotos =>
      _photos.where((p) => _selectedKeys.contains(p.key)).toList();

  void _enterSelectionMode([int? initialIndex]) {
    setState(() {
      _isSelecting = true;
      if (initialIndex != null &&
          initialIndex >= 0 &&
          initialIndex < _photos.length) {
        _selectedKeys.add(_photos[initialIndex].key);
        _lastSelectedIndex = initialIndex;
      }
    });
  }

  void _exitSelectionMode() {
    if (_isMultiPickMode) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSelecting = false;
      _selectedKeys.clear();
      _lastSelectedIndex = null;
    });
  }

  void _toggleSelectIndex(int index, {bool rangeSelect = false}) {
    if (index < 0 || index >= _photos.length) return;
    setState(() {
      if (rangeSelect && _lastSelectedIndex != null) {
        final start = math.min(_lastSelectedIndex!, index);
        final end = math.max(_lastSelectedIndex!, index);
        for (var i = start; i <= end; i++) {
          _selectedKeys.add(_photos[i].key);
        }
      } else {
        final key = _photos[index].key;
        if (!_selectedKeys.remove(key)) {
          _selectedKeys.add(key);
        }
      }
      _lastSelectedIndex = index;
    });
  }

  void _toggleSelectAll() {
    if (_photos.isEmpty) return;
    setState(() {
      if (_selectedKeys.length == _photos.length) {
        _selectedKeys.clear();
      } else {
        _selectedKeys.addAll(_photos.map((p) => p.key));
      }
    });
  }

  void _toggleMonthGroup(List<_Photo> slice) {
    if (slice.isEmpty) return;
    final allSelected = slice.every((p) => _selectedKeys.contains(p.key));
    setState(() {
      if (allSelected) {
        for (final p in slice) {
          _selectedKeys.remove(p.key);
        }
      } else {
        for (final p in slice) {
          _selectedKeys.add(p.key);
        }
      }
    });
  }

  void _handleTileTap(int index) {
    final kb = HardwareKeyboard.instance;
    final ctrlOrMeta = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;

    if (_isSelecting) {
      _toggleSelectIndex(index, rangeSelect: shift);
      return;
    }
    if (ctrlOrMeta || shift) {
      setState(() {
        _isSelecting = true;
        if (shift && _lastSelectedIndex != null) {
          final start = math.min(_lastSelectedIndex!, index);
          final end = math.max(_lastSelectedIndex!, index);
          for (var i = start; i <= end; i++) {
            _selectedKeys.add(_photos[i].key);
          }
        } else {
          _selectedKeys.add(_photos[index].key);
        }
        _lastSelectedIndex = index;
      });
      return;
    }
    _open(index);
  }

  void _handleTileLongPress(int index) {
    HapticFeedback.mediumImpact();
    if (!_isSelecting) {
      _enterSelectionMode(index);
    } else {
      _toggleSelectIndex(index);
    }
  }

  Future<void> _batchDeleteSelected() async {
    final selected = _selectedPhotos;
    if (selected.isEmpty || _batchBusy) return;

    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
        title: Text(
          selected.length == 1
              ? l10n.deleteSingleConfirmTitle(selected.first.name)
              : l10n.deleteMultipleConfirmTitle(selected.length),
        ),
        content: Text(l10n.deletePermanentWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _batchBusy = true);
    try {
      final deletedKeys = <String>{};
      if (widget.deleteFilesOverride != null) {
        final files = selected.map((p) => p.file).whereType<File>().toList();
        await widget.deleteFilesOverride!(files);
        for (final p in selected) {
          if (p.file != null) deletedKeys.add(p.key);
        }
      } else {
        for (final p in selected) {
          if (p.file != null) {
            if (p.file!.existsSync()) {
              await p.file!.delete();
            }
            deletedKeys.add(p.key);
          }
        }
        final assetIds = selected
            .map((p) => p.asset?.id)
            .whereType<String>()
            .toList();
        if (assetIds.isNotEmpty) {
          final deletedIds = await PhotoManager.editor.deleteWithIds(assetIds);
          final deletedIdSet = deletedIds.toSet();
          for (final p in selected) {
            if (p.asset != null && deletedIdSet.contains(p.asset!.id)) {
              deletedKeys.add(p.key);
            }
          }
        }
      }
      if (!mounted) return;
      if (deletedKeys.isNotEmpty) {
        HapticFeedback.lightImpact();
        final singleName = selected.length == 1 ? selected.first.name : '';
        setState(() {
          _photos = _photos
              .where((p) => !deletedKeys.contains(p.key))
              .toList();
          _groupedPhotos = null;
          _lastGroupedLength = -1;
          _selectedKeys.removeAll(deletedKeys);
          if (!_isMultiPickMode && _selectedKeys.isEmpty) {
            _isSelecting = false;
            _lastSelectedIndex = null;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              deletedKeys.length == 1 && singleName.isNotEmpty
                  ? l10n.deletedItem(singleName)
                  : l10n.deletedCount(deletedKeys.length),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.failedToDelete('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _batchShareSelected() async {
    final selected = _selectedPhotos;
    if (selected.isEmpty || _batchBusy) return;

    setState(() => _batchBusy = true);
    try {
      final paths = <String>[];
      for (final p in selected) {
        final file = await p.resolve();
        if (file != null) paths.add(file.path);
      }
      if (!mounted || paths.isEmpty) return;
      if (widget.shareFilesOverride != null) {
        await widget.shareFilesOverride!(paths);
      } else {
        await SharePlus.instance.share(
          ShareParams(files: paths.map(XFile.new).toList()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _batchCopyPathsSelected() async {
    final selected = _selectedPhotos;
    if (selected.isEmpty || _batchBusy) return;

    setState(() => _batchBusy = true);
    try {
      final paths = <String>[];
      for (final p in selected) {
        final file = await p.resolve();
        if (file != null) paths.add(file.path);
      }
      if (!mounted || paths.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: paths.join('\n')));
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final label = paths.length == 1
          ? paths.first.split(Platform.pathSeparator).last
          : '${paths.length}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.copiedValue(label))),
      );
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _batchStripExifSelected() async {
    final selected = _selectedPhotos;
    if (selected.isEmpty || _batchBusy) return;

    setState(() => _batchBusy = true);
    try {
      final paths = <String>[];
      for (final p in selected) {
        final file = await p.resolve();
        if (file != null) paths.add(file.path);
      }
      if (paths.isEmpty || !mounted) return;
      final saved = await ImagePrivacyService.batchStripExif(paths);
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.stripExifBatchDone(saved))),
      );
      if (saved > 0) {
        await _scan();
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _confirmMultiPick() async {
    final selected = _selectedPhotos;
    if (selected.isEmpty || _batchBusy) return;

    setState(() => _batchBusy = true);
    try {
      final paths = <String>[];
      for (final p in selected) {
        final file = await p.resolve();
        if (file != null &&
            (widget.pickRequest == null ||
                widget.pickRequest!.matchesFileName(file.path))) {
          paths.add(file.path);
        }
      }
      if (!mounted || paths.isEmpty) return;
      Navigator.of(context).pop(paths);
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allSelected =
        _photos.isNotEmpty && _selectedKeys.length == _photos.length;

    return AppSwipeBack(
      child: PopScope(
        canPop: !_isSelecting || _isMultiPickMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isSelecting && !_isMultiPickMode) {
            _exitSelectionMode();
          }
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_isSelecting) _exitSelectionMode();
            },
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
              if (_isSelecting) _toggleSelectAll();
            },
            const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
              if (_isSelecting) _toggleSelectAll();
            },
            const SingleActivator(LogicalKeyboardKey.delete): () {
              if (_isSelecting && _selectedKeys.isNotEmpty) {
                _batchDeleteSelected();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: _isSelecting
                  ? AppBar(
                      leading: IconButton(
                        key: const ValueKey('gallery_exit_select_btn'),
                        icon: const Icon(Icons.close),
                        tooltip: l10n.cancelSelectionEsc,
                        onPressed: _exitSelectionMode,
                      ),
                      title: Text(l10n.selectedCountLabel(_selectedKeys.length)),
                      actions: [
                        if (_photos.isNotEmpty)
                          IconButton(
                            key: const ValueKey('gallery_select_all_btn'),
                            icon: Icon(
                              allSelected ? Icons.deselect : Icons.select_all,
                            ),
                            tooltip:
                                allSelected ? l10n.deselectAll : l10n.selectAll,
                            onPressed: _toggleSelectAll,
                          ),
                      ],
                    )
                  : AppBar(
                      title: Text(
                        _loading
                            ? l10n.photosTitle
                            : '${l10n.photosTitle} (${_photos.length}${_albumTotal > _photos.length ? '/$_albumTotal' : ''})',
                      ),
                      actions: [
                        if (_photos.isNotEmpty && !_loading)
                          IconButton(
                            key: const ValueKey('gallery_select_mode_btn'),
                            icon: const Icon(Icons.checklist_rounded),
                            tooltip: l10n.selectItems,
                            onPressed: () => _enterSelectionMode(),
                          ),
                        IconButton(
                          icon: const Icon(Icons.backup_outlined),
                          tooltip: l10n.photoBackupTitle,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PhotoBackupPage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: l10n.rescan,
                          onPressed: _scan,
                        ),
                      ],
                    ),
              body: _buildBody(),
              bottomNavigationBar: _isSelecting ? _buildBottomActionBar(l10n) : null,
              floatingActionButton: ValueListenableBuilder<bool>(
                valueListenable: _showScrollToTopNotifier,
                builder: (ctx, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return FloatingActionButton.small(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    tooltip: AppLocalizations.of(ctx).scrollToTop,
                    child: const Icon(Icons.arrow_upward),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final hasSelection = _selectedKeys.isNotEmpty && !_batchBusy;

    Widget actionItem({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      Color? color,
    }) {
      final effectiveColor = onTap == null
          ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
          : (color ?? scheme.onSurface);
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: effectiveColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: effectiveColor),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      elevation: 3,
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_batchBusy) const LinearProgressIndicator(minHeight: 2),
            SizedBox(
              height: 60,
              child: _isMultiPickMode
                  ? Center(
                      child: FilledButton.icon(
                        key: const ValueKey('gallery_confirm_pick_btn'),
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(l10n.selectCount(_selectedKeys.length)),
                        onPressed: hasSelection ? _confirmMultiPick : null,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (PlatformCapabilities.supportsNativeShareSheet)
                          actionItem(
                            key: const ValueKey('gallery_batch_share_btn'),
                            icon: Icons.share_outlined,
                            label: l10n.share,
                            onTap: hasSelection ? _batchShareSelected : null,
                          ),
                        actionItem(
                          key: const ValueKey('gallery_batch_copy_btn'),
                          icon: Icons.copy_outlined,
                          label: l10n.copyPath,
                          onTap:
                              hasSelection ? _batchCopyPathsSelected : null,
                        ),
                        actionItem(
                          key: const ValueKey('gallery_batch_exif_btn'),
                          icon: Icons.shield_outlined,
                          label: l10n.stripExifBatchAction,
                          onTap:
                              hasSelection ? _batchStripExifSelected : null,
                        ),
                        actionItem(
                          key: const ValueKey('gallery_batch_delete_btn'),
                          icon: Icons.delete_outline,
                          label: l10n.delete,
                          color: scheme.error,
                          onTap: hasSelection ? _batchDeleteSelected : null,
                        ),
                      ],
                    ),
            ),
          ],
        ),
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
                title: _notice ?? AppLocalizations.of(context).noPhotosFound,
                subtitle: _notice == null && PlatformPaths.galleryDirs().isNotEmpty
                    ? PlatformPaths.galleryDirs().join('\n')
                    : null,
                action: _permissionDenied
                    ? FilledButton.tonalIcon(
                        icon: const Icon(Icons.settings, size: 16),
                        label: Text(AppLocalizations.of(context).openSettings),
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

  String _monthLabel(DateTime? d) {
    final l10n = AppLocalizations.of(context);
    if (d == null) return l10n.unknownDate;
    final months = [
      l10n.monthJanuary, l10n.monthFebruary, l10n.monthMarch,
      l10n.monthApril, l10n.monthMay, l10n.monthJune,
      l10n.monthJuly, l10n.monthAugust, l10n.monthSeptember,
      l10n.monthOctober, l10n.monthNovember, l10n.monthDecember,
    ];
    return l10n.monthYearLabel(months[d.month - 1], d.year);
  }

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
      final groupAllSelected = _isSelecting &&
          group.slice.isNotEmpty &&
          group.slice.every((p) => _selectedKeys.contains(p.key));
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isSelecting)
                  InkWell(
                    key: ValueKey('gallery_month_select_${group.label}'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _toggleMonthGroup(group.slice),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        groupAllSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: groupAllSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
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
    final isSelected = _selectedKeys.contains(photo.key);
    final scheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 140),
        padding: _isSelecting && isSelected
            ? const EdgeInsets.all(5)
            : EdgeInsets.zero,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: _isSelecting && isSelected
                ? Border.all(color: scheme.primary, width: 2.5)
                : null,
            color: _isSelecting && isSelected
                ? scheme.primary.withValues(alpha: 0.16)
                : null,
          ),
          child: ClipRRect(
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
                if (_isSelecting)
                  Positioned(
                    top: 5,
                    left: 5,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? scheme.primary
                            : Colors.black.withValues(alpha: 0.42),
                        border: Border.all(
                          color: isSelected ? scheme.onPrimary : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                          : null,
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onSecondaryTapDown: (d) =>
                        _showPhotoContextMenu(d.globalPosition, index),
                    child: InkWell(
                      onTap: () => _handleTileTap(index),
                      onLongPress: () => _handleTileLongPress(index),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
  static final Map<String, Future<Uint8List?>> _thumbCache = {};

  late final Future<Uint8List?> _data = _getThumb(widget.asset);

  static Future<Uint8List?> _getThumb(AssetEntity asset) {
    final existing = _thumbCache[asset.id];
    if (existing != null) return existing;
    if (_thumbCache.length > 500) {
      _thumbCache.remove(_thumbCache.keys.first);
    }
    final future = asset.thumbnailDataWithSize(
      const ThumbnailSize.square(220),
    );
    _thumbCache[asset.id] = future;
    return future;
  }

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
          cacheWidth: 220,
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
