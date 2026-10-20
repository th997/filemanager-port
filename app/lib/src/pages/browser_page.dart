import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../dialogs/download_prompt_dialog.dart';
import '../dialogs/file_picker_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import 'image_viewer_page.dart';
import 'media_player_page.dart';
import 'text_editor_page.dart';

enum SortField { name, size, modified, type }

class ClipboardState {
  final String srcRoot;
  final List<String> paths;
  final bool isCut;

  const ClipboardState({
    required this.srcRoot,
    required this.paths,
    required this.isCut,
  });
}

class BrowserPage extends StatefulWidget {
  final String initialRoot;
  final String initialPath;

  const BrowserPage({
    super.key,
    required this.initialRoot,
    this.initialPath = '',
  });

  @override
  State<BrowserPage> createState() => BrowserPageState();
}

class BrowserPageState extends State<BrowserPage> {
  late String _root;
  late String _relPath;
  List<EntryItem> _entries = [];
  bool _loading = false;
  String? _error;
  CapabilitiesDto? _capabilities;

  bool _isGrid = false;
  bool _showHidden = false;
  SortField _sortField = SortField.name;
  bool _sortAsc = true;
  String _filterQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Address bar direct jump state
  bool _isEditingAddress = false;
  final TextEditingController _addressController = TextEditingController();

  String get _currentFullPath {
    if (_root == '/') {
      return _relPath.isEmpty ? '/' : '/$_relPath';
    }
    if (_root.startsWith('remote://') || _root.startsWith('archive://')) {
      return _relPath.isEmpty ? _root : '$_root/$_relPath';
    }
    return _relPath.isEmpty ? _root : '$_root/$_relPath';
  }

  // Multi-selection state
  bool _isSelecting = false;
  final Set<String> _selectedPaths = <String>{};

  String get _selectedSummary {
    final count = _selectedPaths.length;
    BigInt totalBytes = BigInt.zero;
    for (final e in _entries) {
      if (_selectedPaths.contains(_fullEntryPath(e))) {
        if (!e.isDir && e.size != null) {
          totalBytes += e.size!;
        }
      }
    }
    if (totalBytes > BigInt.zero) {
      final bytes = totalBytes.toDouble();
      String sizeStr;
      if (bytes < 1024) {
        sizeStr = '${bytes.toInt()} B';
      } else if (bytes < 1024 * 1024) {
        sizeStr = '${(bytes / 1024).toStringAsFixed(1)} KB';
      } else if (bytes < 1024 * 1024 * 1024) {
        sizeStr = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        sizeStr = '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
      }
      return '$count selected ($sizeStr)';
    }
    return '$count selected';
  }

  // Pagination state
  int _currentPage = 1;
  static const int _pageSize = 100;
  bool _hasMore = false;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Clipboard state for copy/cut/paste
  static ClipboardState? _clipboard;

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    _relPath = widget.initialPath;
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 250 &&
        _hasMore &&
        !_loadingMore &&
        !_loading) {
      _loadMore();
    }
  }

  /// Directory the in-flight load belongs to. A load started for one folder
  /// must not fill the list after the user has navigated elsewhere.
  String? _loadingFor;

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final loadingFor = '$_root\u0000$_relPath';
    setState(() => _loadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final paged = await listDirPaged(
        root: _root,
        path: _relPath,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      if (_loadingFor == loadingFor) {
        setState(() {
          _currentPage = nextPage;
          _entries.addAll(paged.entries.map((e) => EntryItem(e)));
          _hasMore = paged.hasMore;
          _loadingMore = false;
        });
      } else {
        setState(() => _loadingMore = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void navigateTo(String root, String relPath) {
    setState(() {
      _root = root;
      _relPath = relPath;
      _isSelecting = false;
      _selectedPaths.clear();
      _isSearching = false;
      _filterQuery = '';
      _searchController.clear();
      _isEditingAddress = false;
      _currentPage = 1;
      _hasMore = false;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _load();
  }

  void _jumpToAddress(String input) {
    final path = input.trim();
    if (path.isEmpty) return;
    setState(() => _isEditingAddress = false);

    if (path.startsWith('remote://')) {
      final withoutPrefix = path.substring('remote://'.length);
      final slashIdx = withoutPrefix.indexOf('/');
      if (slashIdx != -1) {
        final remoteId = withoutPrefix.substring(0, slashIdx);
        final rel = withoutPrefix.substring(slashIdx + 1);
        navigateTo('remote://$remoteId', rel);
      } else {
        navigateTo('remote://$withoutPrefix', '');
      }
    } else if (path.startsWith('archive://')) {
      final withoutPrefix = path.substring('archive://'.length);
      final match = RegExp(r'(\.(zip|apk|jar|tar\.gz|tgz|tar|7z))([/\\]|$)', caseSensitive: false).firstMatch(withoutPrefix);
      if (match != null) {
        final archivePath = withoutPrefix.substring(0, match.start + match.group(1)!.length);
        final rel = withoutPrefix.substring(match.end).replaceAll(RegExp(r'^[/\\]+'), '').replaceAll('\\', '/');
        navigateTo('archive://$archivePath', rel);
      } else {
        navigateTo('archive://$withoutPrefix', '');
      }
    } else if (path.startsWith('/')) {
      final normalized = path == '/' ? '/' : path.replaceAll(RegExp(r'/+'), '/');
      if (normalized == '/') {
        navigateTo('/', '');
      } else {
        final rel = normalized.substring(1);
        navigateTo('/', rel);
      }
    } else if (RegExp(r'^[a-zA-Z]:').hasMatch(path)) {
      final drive = path.substring(0, 2);
      final rel = path.substring(2).replaceAll(RegExp(r'^[/\\]+'), '').replaceAll('\\', '/');
      navigateTo('$drive/', rel);
    } else {
      final nextRel = _relPath.isEmpty ? path : '$_relPath/$path';
      navigateTo(_root, nextRel);
    }
  }

  Future<void> _load() async {
    final loadingFor = '$_root\u0000$_relPath';
    _loadingFor = loadingFor;
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = false;
    });

    try {
      final caps = await getCapabilities(root: _root);
      final paged = await listDirPaged(
        root: _root,
        path: _relPath,
        page: _currentPage,
        pageSize: _pageSize,
      );
      final items = paged.entries.map((e) => EntryItem(e)).toList();

      // A newer navigation superseded this load; its result belongs to a
      // folder the user already left.
      if (!mounted || _loadingFor != loadingFor) return;
      setState(() {
        _capabilities = caps;
        _entries = items;
        _hasMore = paged.hasMore;
        _loading = false;
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      StorageService.instance.recordHistory(root: _root, path: _relPath);
    } catch (e) {
      if (mounted && _loadingFor == loadingFor) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _navigateUp() {
    if (_relPath.isNotEmpty) {
      final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        setState(() {
          _relPath = segments.join('/');
          _isSelecting = false;
          _selectedPaths.clear();
        });
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        _load();
        return;
      }
    }
    if (_root.startsWith('/') && _root != '/') {
      final segments = _root.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        final newRoot = segments.isEmpty ? '/' : '/${segments.join('/')}';
        navigateTo(newRoot, '');
        return;
      }
    }
    final driveMatch = RegExp(r'^[a-zA-Z]:[/\\]').firstMatch(_root);
    if (driveMatch != null) {
      final drive = _root.substring(0, 2);
      final rest = _root.substring(driveMatch.end);
      final segments = rest.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        final newRoot = segments.isEmpty ? '$drive/' : '$drive/${segments.join('/')}';
        navigateTo(newRoot, '');
        return;
      }
    }
    // If inside archive, navigate back to host folder
    if (_root.startsWith('archive://')) {
      final archiveHost = _root.substring('archive://'.length);
      if (archiveHost.startsWith('remote://')) {
        final withoutPrefix = archiveHost.substring('remote://'.length);
        final slashIdx = withoutPrefix.indexOf('/');
        if (slashIdx != -1) {
          final remoteId = withoutPrefix.substring(0, slashIdx);
          final fullRemotePath = withoutPrefix.substring(slashIdx + 1);
          final segments = fullRemotePath.split('/').where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) segments.removeLast();
          navigateTo('remote://$remoteId', segments.join('/'));
          return;
        } else {
          navigateTo('remote://$withoutPrefix', '');
          return;
        }
      }
      final segments = archiveHost.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) segments.removeLast();
      if (RegExp(r'^[a-zA-Z]:').hasMatch(archiveHost)) {
        final drive = archiveHost.substring(0, 2);
        if (segments.isNotEmpty && segments.first.toLowerCase() == drive.toLowerCase()) {
          segments.removeAt(0);
        }
        final target = segments.isEmpty ? '$drive/' : '$drive/${segments.join('/')}';
        navigateTo(target, '');
        return;
      }
      final parentDir = segments.isEmpty ? '/' : '/${segments.join('/')}';
      navigateTo(parentDir, '');
      return;
    }
  }

  String _fullEntryPath(EntryItem item) {
    if (_relPath.isEmpty) return item.name;
    return '$_relPath/${item.name}';
  }

  void _openEntry(EntryItem item) {
    if (_isSelecting) {
      _toggleSelect(_fullEntryPath(item));
      return;
    }

    if (item.isDir) {
      final next = _fullEntryPath(item);
      setState(() {
        _relPath = next;
        _isSelecting = false;
        _selectedPaths.clear();
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _load();
      return;
    }

    if (item.isArchive) {
      if (_needsDownloadPrompt(item)) {
        _downloadThenOpen(item);
        return;
      }
      final fullPath = joinNative(_root, _fullEntryPath(item));
      navigateTo('archive://$fullPath', '');
      return;
    }

    if (item.isText || item.isMarkdown || item.isHtml) {
      if (_needsDownloadPrompt(item)) {
        _downloadThenOpen(item);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: _root,
            path: _fullEntryPath(item),
            fileName: item.name,
          ),
        ),
      ).then((_) => _load());
      return;
    }

    if (item.isMedia) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: _root,
            path: _fullEntryPath(item),
            fileName: item.name,
            isAudio: item.isAudio,
          ),
        ),
      );
      return;
    }

    if (item.isImage) {
      if (_needsDownloadPrompt(item)) {
        _downloadThenOpen(item);
        return;
      }
      _openImage(item);
      return;
    }

    // PDF, Office, APK and anything else: hand it to the system.
    if (_needsDownloadPrompt(item)) {
      _downloadThenOpen(item);
      return;
    }
    _openWithSystem(item);
  }

  /// Files above this size that have no streaming preview are downloaded
  /// explicitly instead of silently exported through the cache.
  static const int _downloadPromptThreshold = 10 * 1024 * 1024;

  bool _isRemoteOrArchive(String root) =>
      root.startsWith('remote://') || root.startsWith('archive://');

  /// Whether the current backend accepts edits. Archive contents and
  /// read-only accounts do not, so their menus must not offer writes.
  bool get _canWrite => _capabilities?.write ?? true;

  /// ZIP creation and extraction run on native paths, so they only work
  /// while browsing a local folder.
  bool get _canArchive => isNativeRoot(_root);

  bool _needsDownloadPrompt(EntryItem item) {
    if (!_isRemoteOrArchive(_root)) return false;
    final size = item.size;
    return size != null && size > BigInt.from(_downloadPromptThreshold);
  }

  /// Copy a large non-streamable file into a user-chosen folder, then open the
  /// local copy.
  Future<void> _downloadThenOpen(EntryItem item) async {
    final choice = await DownloadPromptDialog.show(
      context,
      fileName: item.name,
      sizeText: item.formattedSize,
      sizeBytes: item.size,
    );
    if (choice == null || !mounted) return;

    final destination = choice.destination;
    final dstDir = destination.relPath;

    try {
      await _ensureDir(destination.root, dstDir);
      final name = await _uniqueName(
        destination.root,
        dstDir,
        item.name,
      );

      final taskId = await TaskService.instance.copy(
        srcRoot: _root,
        srcPaths: [_fullEntryPath(item)],
        dstRoot: destination.root,
        dstDir: dstDir,
        dstName: name,
      );
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading ${item.name}',
      );
      if (completed != true || !mounted) return;

      final dstPath = dstDir.isEmpty ? name : '$dstDir/$name';
      await _openLocalCopy(destination.root, dstPath, item);
    } catch (e) {
      _showError('Download failed: $e');
    }
  }

  /// Create the destination folder, ignoring "already exists".
  Future<void> _ensureDir(String root, String relPath) async {
    if (relPath.isEmpty) return;
    final segments = relPath.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (final segment in segments) {
      current = current.isEmpty ? segment : '$current/$segment';
      try {
        await createDir(root: root, path: current);
      } catch (_) {
        // Existing directories report an error; the copy below decides
        // whether the path is actually usable.
      }
    }
  }

  /// `name (1).ext` when `name.ext` already exists in the destination.
  Future<String> _uniqueName(String root, String relPath, String name) async {
    final existing = <String>{};
    try {
      final entries = await listDir(root: root, path: relPath);
      existing.addAll(entries.map((e) => e.name));
    } catch (_) {
      return name;
    }
    if (!existing.contains(name)) return name;

    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      final candidate = '$stem ($i)$ext';
      if (!existing.contains(candidate)) return candidate;
    }
    return name;
  }

  Future<void> _openLocalCopy(
    String root,
    String path,
    EntryItem item,
  ) async {
    if (item.isArchive) {
      final fullPath = joinNative(root, path);
      navigateTo('archive://$fullPath', '');
      return;
    }
    if (item.isText || item.isMarkdown || item.isHtml) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: root,
            path: path,
            fileName: item.name,
          ),
        ),
      );
      return;
    }
    if (item.isImage) {
      final native = joinNative(root, path);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: native,
            fileName: item.name,
          ),
        ),
      );
      return;
    }
    final result = await OpenFilex.open(joinNative(root, path));
    if (!mounted) return;
    if (result.type == ResultType.noAppToOpen) {
      _showError('Downloaded, but no installed app can open ${item.name}');
    } else if (result.type != ResultType.done) {
      _showError(result.message);
    }
  }

  Future<void> _openImage(EntryItem item) async {
    if (isNativeRoot(_root)) {
      final fullLocalPath = joinNative(_root, _fullEntryPath(item));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: fullLocalPath,
            fileName: item.name,
          ),
        ),
      );
      return;
    }

    // Remote and archive images have no native path yet; export once and show.
    try {
      final native = await FileOpenService.instance.nativePath(_root, _fullEntryPath(item));
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: native,
            fileName: item.name,
          ),
        ),
      );
    } catch (e) {
      _showError('Cannot open image: $e');
    }
  }

  Future<void> _openWithSystem(EntryItem item) async {
    try {
      final result = await FileOpenService.instance.openWith(_root, _fullEntryPath(item));
      if (!mounted) return;
      if (result.type == ResultType.noAppToOpen) {
        _showError('No installed app can open ${item.name}');
      } else if (result.type != ResultType.done) {
        _showError(result.message);
      }
    } catch (e) {
      _showError('Cannot open file: $e');
    }
  }

  Future<void> _shareEntry(EntryItem item) async {
    try {
      await FileOpenService.instance.share(_root, _fullEntryPath(item));
    } catch (e) {
      _showError('Cannot share file: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  /// Long-press menu for one entry, matching the actions the original app
  /// offers on a file.
  Future<void> _showEntryActions(EntryItem item) async {
    final path = _fullEntryPath(item);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(item.icon, color: item.iconColor(ctx)),
              title: Text(item.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.isDir ? 'Folder' : item.formattedSize),
            ),
            const Divider(height: 1),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open with'),
                onTap: () => Navigator.of(ctx).pop('open_with'),
              ),
            if (_isRemoteOrArchive(_root))
              ListTile(
                leading: const Icon(Icons.download_outlined, color: Colors.blue),
                title: const Text('Download to local'),
                onTap: () => Navigator.of(ctx).pop('download'),
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () => Navigator.of(ctx).pop('copy'),
            ),
            if (_canWrite)
              ListTile(
                leading: const Icon(Icons.cut),
                title: const Text('Cut'),
                onTap: () => Navigator.of(ctx).pop('cut'),
              ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Select items'),
              onTap: () => Navigator.of(ctx).pop('select'),
            ),
            if (item.isArchive && _canArchive)
              ListTile(
                leading: const Icon(Icons.unarchive),
                title: const Text('Extract Here'),
                onTap: () => Navigator.of(ctx).pop('extract'),
              )
            else if (_canWrite && _canArchive)
              ListTile(
                leading: const Icon(Icons.archive),
                title: const Text('Compress to ZIP'),
                onTap: () => Navigator.of(ctx).pop('compress'),
              ),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
            if (_canWrite)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.of(ctx).pop('rename'),
              ),
            if (_canWrite)
              ListTile(
                leading: const Icon(Icons.control_point_duplicate),
                title: const Text('Duplicate'),
                onTap: () => Navigator.of(ctx).pop('duplicate'),
              ),
            if (_canWrite)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Properties'),
              onTap: () => Navigator.of(ctx).pop('info'),
            ),
          ],
        ),
      ),
    );

    switch (action) {
      case 'open':
        _openEntry(item);
        break;
      case 'open_with':
        _openWithSystem(item);
        break;
      case 'download':
        _downloadSingle(item);
        break;
      case 'copy':
        setState(() {
          _clipboard = ClipboardState(srcRoot: _root, paths: [path], isCut: false);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied ${item.name} to clipboard')),
        );
        break;
      case 'cut':
        setState(() {
          _clipboard = ClipboardState(srcRoot: _root, paths: [path], isCut: true);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cut ${item.name} to clipboard')),
        );
        break;
      case 'select':
        setState(() {
          _isSelecting = true;
          _selectedPaths.add(path);
        });
        break;
      case 'extract':
        _extractArchive(item);
        break;
      case 'compress':
        setState(() {
          _selectedPaths
            ..clear()
            ..add(path);
        });
        _compressSelected();
        break;
      case 'share':
        _shareEntry(item);
        break;
      case 'rename':
        _renameSingle(item);
        break;
      case 'duplicate':
        _duplicateEntry(item);
        break;
      case 'delete':
        _deleteSingle(item);
        break;
      case 'info':
        _showFileInfo(item);
        break;
    }
  }

  /// Desktop right-click context menu on a file/folder referencing File Manager+.
  Future<void> _showContextMenu(BuildContext originContext, Offset position, EntryItem item) async {
    final path = _fullEntryPath(item);
    final action = await showMenu<String>(
      context: originContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(item.isDir ? Icons.folder_open : Icons.open_in_new, size: 18),
              const SizedBox(width: 8),
              Text(item.isDir ? 'Open' : 'Open'),
            ],
          ),
        ),
        if (!item.isDir)
          const PopupMenuItem(
            value: 'open_with',
            child: Row(
              children: [
                Icon(Icons.open_in_browser, size: 18),
                SizedBox(width: 8),
                Text('Open with'),
              ],
            ),
          ),
        if (_isRemoteOrArchive(_root))
          const PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                Icon(Icons.download, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Text('Download to local'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy'),
            ],
          ),
        ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'cut',
            child: Row(
              children: [
                Icon(Icons.cut, size: 18),
                SizedBox(width: 8),
                Text('Cut'),
              ],
            ),
          ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline, size: 18),
                SizedBox(width: 8),
                Text('Rename'),
              ],
            ),
          ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'duplicate',
            child: Row(
              children: [
                Icon(Icons.control_point_duplicate, size: 18),
                SizedBox(width: 8),
                Text('Duplicate'),
              ],
            ),
          ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        if (item.isArchive && _canArchive)
          const PopupMenuItem(
            value: 'extract',
            child: Row(
              children: [
                Icon(Icons.unarchive, size: 18),
                SizedBox(width: 8),
                Text('Extract Here'),
              ],
            ),
          )
        else if (_canWrite && _canArchive)
          const PopupMenuItem(
            value: 'compress',
            child: Row(
              children: [
                Icon(Icons.archive, size: 18),
                SizedBox(width: 8),
                Text('Compress to ZIP'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 8),
              Text('Properties'),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'open':
        _openEntry(item);
        break;
      case 'open_with':
        _openWithSystem(item);
        break;
      case 'download':
        _downloadSingle(item);
        break;
      case 'copy':
        setState(() {
          _clipboard = ClipboardState(srcRoot: _root, paths: [path], isCut: false);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied ${item.name} to clipboard')),
        );
        break;
      case 'cut':
        setState(() {
          _clipboard = ClipboardState(srcRoot: _root, paths: [path], isCut: true);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cut ${item.name} to clipboard')),
        );
        break;
      case 'rename':
        _renameSingle(item);
        break;
      case 'duplicate':
        _duplicateEntry(item);
        break;
      case 'delete':
        _deleteSingle(item);
        break;
      case 'extract':
        _extractArchive(item);
        break;
      case 'compress':
        setState(() {
          _selectedPaths
            ..clear()
            ..add(path);
        });
        _compressSelected();
        break;
      case 'info':
        _showFileInfo(item);
        break;
    }
  }

  /// Desktop right-click context menu on empty space.
  Future<void> _showBackgroundContextMenu(Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        if (_canWrite)
          const PopupMenuItem(
            value: 'new_folder',
            child: Row(
              children: [
                Icon(Icons.create_new_folder, size: 18),
                SizedBox(width: 8),
                Text('New Folder'),
              ],
            ),
          ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'new_file',
            child: Row(
              children: [
                Icon(Icons.note_add_outlined, size: 18),
                SizedBox(width: 8),
                Text('New Text File'),
              ],
            ),
          ),
        if (_canWrite)
          const PopupMenuItem(
            value: 'upload',
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 18),
                SizedBox(width: 8),
                Text('Upload Files'),
              ],
            ),
          ),
        if (_clipboard != null && _canWrite)
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                const Icon(Icons.paste, size: 18),
                const SizedBox(width: 8),
                Text('Paste (${_clipboard!.paths.length})'),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18),
              SizedBox(width: 8),
              Text('Refresh'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'select_all',
          child: Row(
            children: [
              Icon(Icons.select_all, size: 18),
              SizedBox(width: 8),
              Text('Select All'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('Copy Folder Path'),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;
    switch (action) {
      case 'new_folder':
        _createFolder();
        break;
      case 'new_file':
        _createFile();
        break;
      case 'upload':
        _uploadFiles();
        break;
      case 'paste':
        _paste();
        break;
      case 'refresh':
        _load();
        break;
      case 'select_all':
        setState(() => _isSelecting = true);
        _selectAll();
        break;
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: _currentFullPath));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder path copied to clipboard')),
        );
        break;
    }
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _isSelecting = false;
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _isSelecting = true;
      for (final e in _filteredAndSortedEntries) {
        _selectedPaths.add(_fullEntryPath(e));
      }
    });
  }

  void _invertSelection() {
    setState(() {
      final currentSelected = Set<String>.from(_selectedPaths);
      _selectedPaths.clear();
      for (final e in _filteredAndSortedEntries) {
        final path = _fullEntryPath(e);
        if (!currentSelected.contains(path)) {
          _selectedPaths.add(path);
        }
      }
      if (_selectedPaths.isEmpty) {
        _isSelecting = false;
      } else {
        _isSelecting = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPaths.clear();
      _isSelecting = false;
    });
  }

  // File Operations
  Future<void> _uploadFiles() async {
    final picked = await FilePickerDialog.show(
      context,
      title: 'Upload Files to Current Folder',
    );
    if (picked == null || picked.paths.isEmpty || !mounted) return;

    try {
      final taskId = await TaskService.instance.copy(
        srcRoot: picked.root,
        srcPaths: picked.paths,
        dstRoot: _root,
        dstDir: _relPath,
      );
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Uploading ${picked.paths.length} item(s)…',
      );
      if (mounted) _load();
      if (completed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded ${picked.paths.length} item(s)')),
        );
      }
    } catch (e) {
      _showError('Upload failed: $e');
    }
  }

  Future<void> _downloadSelected() async {
    if (_selectedPaths.isEmpty) return;
    if (!_isRemoteOrArchive(_root)) {
      _showError('Already local: use Copy to place these files elsewhere.');
      return;
    }
    final dest = await FolderPickerDialog.show(
      context,
      title: 'Select Download Destination',
      initialRoot: PlatformPaths.defaultRoot(),
    );
    if (dest == null || !mounted) return;

    try {
      final taskId = await TaskService.instance.copy(
        srcRoot: _root,
        srcPaths: _selectedPaths.toList(),
        dstRoot: dest.root,
        dstDir: dest.relPath,
      );
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading Files…',
      );
      if (!mounted) return;
      _clearSelection();
      if (completed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded to ${dest.path}')),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    }
  }

  Future<void> _downloadSingle(EntryItem item) async {
    final dest = await FolderPickerDialog.show(
      context,
      title: 'Select Download Destination',
      initialRoot: PlatformPaths.defaultRoot(),
    );
    if (dest == null || !mounted) return;

    try {
      final taskId = await TaskService.instance.copy(
        srcRoot: _root,
        srcPaths: [_fullEntryPath(item)],
        dstRoot: dest.root,
        dstDir: dest.relPath,
        dstName: item.name,
      );
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading ${item.name}…',
      );
      if (!mounted) return;
      if (completed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded ${item.name} to ${dest.path}')),
        );
      }
    } catch (e) {
      _showError('Download failed: $e');
    }
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New Folder'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Folder Name', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Create')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (name != null && name.isNotEmpty) {
      final target = _relPath.isEmpty ? name : '$_relPath/$name';
      try {
        await createDir(root: _root, path: target);
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create folder: $e')));
        }
      }
    }
  }

  Future<void> _createFile() async {
    final ctrl = TextEditingController();
    final String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New Text File'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'File Name',
              hintText: 'e.g. notes.txt',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Create')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (name != null && name.isNotEmpty) {
      final target = _relPath.isEmpty ? name : '$_relPath/$name';
      try {
        await writeTextFile(root: _root, path: target, content: '');
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created "$name"')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create file: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _copySelected({required bool isCut}) {
    setState(() {
      _clipboard = ClipboardState(
        srcRoot: _root,
        paths: _selectedPaths.toList(),
        isCut: isCut,
      );
      _clearSelection();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_clipboard!.paths.length} items ${isCut ? "cut" : "copied"} to clipboard')),
    );
  }

  Future<void> _paste() async {
    final cb = _clipboard;
    if (cb == null) return;

    try {
      final taskId = cb.isCut
          ? await TaskService.instance.move(
              srcRoot: cb.srcRoot,
              srcPaths: cb.paths,
              dstRoot: _root,
              dstDir: _relPath,
            )
          : await TaskService.instance.copy(
              srcRoot: cb.srcRoot,
              srcPaths: cb.paths,
              dstRoot: _root,
              dstDir: _relPath,
            );

      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        cb.isCut ? 'Moving Files…' : 'Copying Files…',
      );
      // A cancelled move may have already removed some sources, so the
      // clipboard is only cleared once the move actually finished.
      if (cb.isCut && completed == true) {
        setState(() => _clipboard = null);
      }
      if (mounted) _load();
    } catch (e) {
      _showError('${cb.isCut ? 'Move' : 'Copy'} failed: $e');
    }
  }

  Future<void> _duplicateEntry(EntryItem item) async {
    final oldName = item.name;
    final dotIndex = oldName.lastIndexOf('.');
    String base;
    String ext;
    if (!item.isDir && dotIndex > 0 && !oldName.startsWith('.')) {
      base = oldName.substring(0, dotIndex);
      ext = oldName.substring(dotIndex);
    } else {
      base = oldName;
      ext = '';
    }

    String candidate = '${base}_copy$ext';
    int count = 2;
    final existingNames = _entries.map((e) => e.name).toSet();
    while (existingNames.contains(candidate)) {
      candidate = '${base}_copy_$count$ext';
      count++;
    }

    try {
      final taskId = await TaskService.instance.copy(
        srcRoot: _root,
        srcPaths: [_fullEntryPath(item)],
        dstRoot: _root,
        dstDir: _relPath,
        dstName: candidate,
      );
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(context, taskId, 'Duplicating…');
      if (completed == true && mounted) {
        _load();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$candidate"')),
        );
      }
    } catch (e) {
      _showError('Duplicate failed: $e');
    }
  }

  Future<void> _deleteSelected() => _deletePaths(_selectedPaths.toList());

  Future<void> _deleteSingle(EntryItem item) =>
      _deletePaths([_fullEntryPath(item)]);

  Future<void> _deletePaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final count = paths.length;
    final canTrash = isNativeRoot(_root);
    final confirm = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(count == 1 ? 'Delete "${paths.first.split('/').last}"?' : 'Delete $count items?'),
        content: Text(
          canTrash
              ? 'Choose whether to move to Recycle Bin or delete permanently.'
              : 'This item is on a remote server and cannot be moved to the '
                  'local Recycle Bin. It will be deleted permanently.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          if (canTrash)
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('trash'),
              child: const Text('Recycle Bin'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop('permanent'),
            child: const Text('Permanent Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirm == 'trash') {
      try {
        for (final p in paths) {
          await StorageService.instance.moveToTrash(joinNative(_root, p));
        }
      } catch (e) {
        _showError('Could not move to Recycle Bin: $e');
      }
      if (!mounted) return;
      _clearSelection();
      _load();
    } else if (confirm == 'permanent') {
      try {
        final taskId = await TaskService.instance.delete(root: _root, paths: paths);
        if (!mounted) return;
        await TaskProgressDialog.show(context, taskId, 'Deleting…');
        if (!mounted) return;
        _clearSelection();
        _load();
      } catch (e) {
        _showError('Delete failed: $e');
      }
    }
  }

  Future<void> _renameSelected() async {
    if (_selectedPaths.length != 1) return;
    await _renamePath(_selectedPaths.first);
  }

  Future<void> _renameSingle(EntryItem item) =>
      _renamePath(_fullEntryPath(item));

  Future<void> _renamePath(String oldPath) async {
    final oldName = oldPath.split('/').last;
    final dotIndex = oldName.lastIndexOf('.');
    final selectionEnd = (dotIndex > 0 && !oldName.startsWith('.')) ? dotIndex : oldName.length;
    final ctrl = TextEditingController(text: oldName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: selectionEnd);
    final String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New Name', border: OutlineInputBorder()),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                Navigator.of(ctx).pop(v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Rename')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      if (newName.contains('/') || newName.contains('\\')) {
        _showError('A name cannot contain "/" or "\\"');
        return;
      }
      final parent = oldPath.contains('/') ? oldPath.substring(0, oldPath.lastIndexOf('/')) : '';
      final newPath = parent.isEmpty ? newName : '$parent/$newName';
      try {
        await renameEntry(root: _root, from: oldPath, to: newPath);
        if (!mounted) return;
        _clearSelection();
        _load();
      } catch (e) {
        _showError('Rename failed: $e');
      }
    }
  }

  Future<void> _compressSelected() async {
    final ctrl = TextEditingController(text: 'archive.zip');
    final String? zipName;
    try {
      zipName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compress to ZIP'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Archive Name', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Compress')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (zipName != null && zipName.isNotEmpty) {
      final dstPath = joinNative(_root, _relPath.isEmpty ? zipName : '$_relPath/$zipName');
      try {
        final taskId = await TaskService.instance.compress(
          srcRoot: _root,
          srcPaths: _selectedPaths.toList(),
          dstArchivePath: dstPath,
        );
        if (!mounted) return;
        await TaskProgressDialog.show(context, taskId, 'Compressing…');
        if (!mounted) return;
        _clearSelection();
        _load();
      } catch (e) {
        _showError('Compress failed: $e');
      }
    }
  }

  Future<void> _extractArchive(EntryItem item) async {
    final fullArchive = joinNative(_root, _fullEntryPath(item));
    final targetDir = joinNative(_root, _relPath);
    try {
      final taskId = await TaskService.instance.extract(
        archivePath: fullArchive,
        dstDir: targetDir,
      );
      if (!mounted) return;
      await TaskProgressDialog.show(context, taskId, 'Extracting Archive…');
      if (mounted) _load();
    } catch (e) {
      _showError('Extract failed: $e');
    }
  }

  Future<void> _bookmarkCurrentFolder() async {
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty ? (_root.split('/').last.isEmpty ? 'Root' : _root.split('/').last) : segments.last;
    await StorageService.instance.addBookmark(name: name, root: _root, path: _relPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bookmarked "$name"')),
      );
    }
  }

  void _showFileInfo(EntryItem item) {
    final path = _fullEntryPath(item);
    final ext = item.isDir ? null : (item.name.contains('.') ? item.name.split('.').last : null);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(item.icon, color: item.iconColor(ctx)),
            const SizedBox(width: 8),
            Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Name', item.name),
            _infoRow('Path', path),
            if (ext != null) _infoRow('Extension', ext.toUpperCase()),
            _infoRow(
              'Size',
              item.isDir
                  ? 'Directory'
                  : '${item.formattedSize}${item.size != null ? " (${item.size} bytes)" : ""}',
            ),
            _infoRow('Modified', item.formattedModified),
            _infoRow('Type', item.isDir ? 'Directory' : (item.isArchive ? 'Archive' : 'File')),
            _infoRow('Hidden', item.hidden ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path copied to clipboard')),
              );
            },
          ),
          if (item.isArchive && _canArchive)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _extractArchive(item);
              },
              child: const Text('Extract Here'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  List<EntryItem> get _filteredAndSortedEntries {
    var list = _entries.where((e) {
      if (!_showHidden && e.hidden) return false;
      if (_filterQuery.isNotEmpty && !e.name.toLowerCase().contains(_filterQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int cmp = 0;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortField.size:
          final sa = a.size ?? BigInt.zero;
          final sb = b.size ?? BigInt.zero;
          cmp = sa.compareTo(sb);
          break;
        case SortField.modified:
          final ma = a.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          final mb = b.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          cmp = ma.compareTo(mb);
          break;
        case SortField.type:
          final extA = a.isDir ? '' : (a.name.contains('.') ? a.name.split('.').last.toLowerCase() : '');
          final extB = b.isDir ? '' : (b.name.contains('.') ? b.name.split('.').last.toLowerCase() : '');
          cmp = extA.compareTo(extB);
          if (cmp == 0) {
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    final String rootDisplay = _root == '/'
        ? '/'
        : (_root.startsWith('remote://')
            ? '☁️ Remote Storage'
            : (_root.startsWith('archive://')
                ? '📦 [Archive] ${_root.split('/').last}'
                : (_root.split('/').where((s) => s.isNotEmpty).lastOrNull ?? _root)));
    final displayName = segments.isEmpty ? rootDisplay : segments.last;

    // Back first leaves selection/search/address, then walks up the directory tree.
    // At the top level the platform handles it (exit or tab switch).
    final canNavigateUp = _isSelecting || _isSearching || _isEditingAddress || _relPath.isNotEmpty ||
        _root.startsWith('archive://') || (_root.startsWith('/') && _root != '/');

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => _isSearching = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _isSearching = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (_isSelecting && _selectedPaths.isNotEmpty) {
            _copySelected(isCut: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          if (_isSelecting && _selectedPaths.isNotEmpty) {
            _copySelected(isCut: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          if (_isSelecting && _selectedPaths.isNotEmpty && _canWrite) {
            _copySelected(isCut: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          if (_isSelecting && _selectedPaths.isNotEmpty && _canWrite) {
            _copySelected(isCut: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (_clipboard != null && _canWrite) {
            _paste();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          if (_clipboard != null && _canWrite) {
            _paste();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          if (_isSelecting && _selectedPaths.length == 1 && _canWrite) {
            final item = _entries.firstWhere(
              (e) => _fullEntryPath(e) == _selectedPaths.first,
              orElse: () => _entries.first,
            );
            _duplicateEntry(item);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          if (_isSelecting && _selectedPaths.length == 1 && _canWrite) {
            final item = _entries.firstWhere(
              (e) => _fullEntryPath(e) == _selectedPaths.first,
              orElse: () => _entries.first,
            );
            _duplicateEntry(item);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5): _load,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _load,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _load,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isSelecting) {
            _clearSelection();
          } else if (_isSearching) {
            setState(() {
              _isSearching = false;
              _filterQuery = '';
              _searchController.clear();
            });
          } else if (_isEditingAddress) {
            setState(() => _isEditingAddress = false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_isSelecting && _canWrite) {
            _deleteSelected();
          }
        },
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          if (!_isEditingAddress && !_isSearching) {
            _navigateUp();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _navigateUp,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
      canPop: !canNavigateUp,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSelecting) {
          _clearSelection();
        } else if (_isSearching) {
          setState(() {
            _isSearching = false;
            _filterQuery = '';
            _searchController.clear();
          });
        } else if (_isEditingAddress) {
          setState(() => _isEditingAddress = false);
        } else {
          _navigateUp();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: _isSelecting
            ? IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection)
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Filter files...',
                  border: InputBorder.none,
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filterQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filterQuery = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSelecting ? _selectedSummary : displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (!_isSelecting)
                    Text(
                      _currentFullPath,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
        actions: [
          if (_isSelecting) ...[
            IconButton(icon: const Icon(Icons.select_all), tooltip: 'Select All', onPressed: _selectAll),
            IconButton(icon: const Icon(Icons.swap_horiz), tooltip: 'Invert Selection', onPressed: _invertSelection),
          ] else ...[
            IconButton(
              icon: Icon(_isSearching ? Icons.search_off : Icons.search),
              tooltip: 'Filter',
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _filterQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
            if (_canWrite)
              IconButton(
                icon: const Icon(Icons.cloud_upload_outlined),
                tooltip: 'Upload Files',
                onPressed: _uploadFiles,
              ),
            if (_canWrite)
              IconButton(
                icon: const Icon(Icons.create_new_folder),
                tooltip: 'New Folder',
                onPressed: _createFolder,
              ),
            if (_canWrite)
              IconButton(
                icon: const Icon(Icons.note_add_outlined),
                tooltip: 'New File',
                onPressed: _createFile,
              ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Bookmark Folder',
              onPressed: _bookmarkCurrentFolder,
            ),
            IconButton(
              icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
              tooltip: _isGrid ? 'List view' : 'Grid view',
              onPressed: () => setState(() => _isGrid = !_isGrid),
            ),
            PopupMenuButton<String>(
              tooltip: 'Options',
              icon: const Icon(Icons.more_vert),
              onSelected: (val) {
                if (val == 'toggle_hidden') {
                  setState(() => _showHidden = !_showHidden);
                } else if (val == 'select') {
                  setState(() => _isSelecting = true);
                } else if (val == 'sort_name') {
                  setState(() {
                    if (_sortField == SortField.name) {
                      _sortAsc = !_sortAsc;
                    } else {
                      _sortField = SortField.name;
                      _sortAsc = true;
                    }
                  });
                } else if (val == 'sort_size') {
                  setState(() {
                    if (_sortField == SortField.size) {
                      _sortAsc = !_sortAsc;
                    } else {
                      _sortField = SortField.size;
                      _sortAsc = false;
                    }
                  });
                } else if (val == 'sort_date') {
                  setState(() {
                    if (_sortField == SortField.modified) {
                      _sortAsc = !_sortAsc;
                    } else {
                      _sortField = SortField.modified;
                      _sortAsc = false;
                    }
                  });
                } else if (val == 'sort_type') {
                  setState(() {
                    if (_sortField == SortField.type) {
                      _sortAsc = !_sortAsc;
                    } else {
                      _sortField = SortField.type;
                      _sortAsc = true;
                    }
                  });
                }
              },
              itemBuilder: (ctx) => [
                CheckedPopupMenuItem<String>(
                  value: 'toggle_hidden',
                  checked: _showHidden,
                  child: const Text('Show hidden files'),
                ),
                PopupMenuItem<String>(
                  value: 'select',
                  child: const Text('Select items'),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem<String>(
                  value: 'sort_name',
                  checked: _sortField == SortField.name,
                  child: Text('Sort by Name ${_sortField == SortField.name ? (_sortAsc ? '(A → Z)' : '(Z → A)') : ''}'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'sort_type',
                  checked: _sortField == SortField.type,
                  child: Text('Sort by Type ${_sortField == SortField.type ? (_sortAsc ? '(A → Z)' : '(Z → A)') : ''}'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'sort_size',
                  checked: _sortField == SortField.size,
                  child: Text('Sort by Size ${_sortField == SortField.size ? (_sortAsc ? '(Smallest)' : '(Largest)') : ''}'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'sort_date',
                  checked: _sortField == SortField.modified,
                  child: Text('Sort by Date ${_sortField == SortField.modified ? (_sortAsc ? '(Oldest)' : '(Newest)') : ''}'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildPathBar(segments),
          _buildCapabilitiesBar(),
          Expanded(child: _buildBody()),
          if (_isSelecting || _clipboard != null) _buildBottomActionBar(),
        ],
      ),
      ),
    ),
    ),
    );
  }

  Widget _buildPathBar(List<String> segments) {
    if (_isEditingAddress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Row(
          children: [
            const Icon(Icons.link, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _addressController,
                autofocus: true,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Enter path to jump (e.g. /, /etc, /home/user)...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: _jumpToAddress,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 20, color: Colors.blue),
              tooltip: 'Jump',
              onPressed: () => _jumpToAddress(_addressController.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Cancel',
              onPressed: () => setState(() => _isEditingAddress = false),
            ),
          ],
        ),
      );
    }

    final rootLabel = _root == '/'
        ? '/'
        : (_root.startsWith('remote://')
            ? 'Cloud'
            : (_root.startsWith('archive://')
                ? 'Archive'
                : (_root.split('/').where((s) => s.isNotEmpty).lastOrNull ?? _root)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Up one level',
            onPressed: (_relPath.isNotEmpty || _root.startsWith('archive://') || (_root.startsWith('/') && _root != '/'))
                ? _navigateUp
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      if (_relPath.isNotEmpty) {
                        setState(() => _relPath = '');
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                        _load();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        rootLabel,
                        style: TextStyle(
                          color: _relPath.isEmpty ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                          fontWeight: _relPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    InkWell(
                      onTap: () {
                        final next = segments.sublist(0, i + 1).join('/');
                        if (next != _relPath) {
                          setState(() => _relPath = next);
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                          _load();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          segments[i],
                          style: TextStyle(
                            color: i == segments.length - 1 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                            fontWeight: i == segments.length - 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Address bar / Jump',
            onPressed: () {
              _addressController.text = _currentFullPath;
              setState(() => _isEditingAddress = true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesBar() {
    final caps = _capabilities;
    if (caps == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: Row(
        children: [
          Text('Capabilities: ', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          _capChip('read', caps.read),
          _capChip('write', caps.write),
          _capChip('rename', caps.rename),
          _capChip('copy', caps.copy),
          _capChip('mkdir', caps.mkdir),
          _capChip('remove', caps.remove),
          const Spacer(),
          Text('${_filteredAndSortedEntries.length} items${_hasMore ? ' (more below)' : ''}', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _capChip(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: enabled ? Colors.green.shade700 : Colors.grey,
          fontWeight: enabled ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (_isSelecting) ...[
              if (_isRemoteOrArchive(_root))
                _actionButton(Icons.download, 'Download', _downloadSelected, color: Colors.blue),
              _actionButton(Icons.copy, 'Copy', () => _copySelected(isCut: false)),
              if (_canWrite) ...[
                _actionButton(Icons.cut, 'Cut', () => _copySelected(isCut: true)),
                _actionButton(Icons.delete, 'Delete', _deleteSelected, color: Colors.red),
                if (_selectedPaths.length == 1)
                  _actionButton(Icons.edit, 'Rename', _renameSelected),
                if (_canArchive)
                  _actionButton(Icons.archive, 'Zip', _compressSelected),
              ],
            ],
            if (_clipboard != null && !_isSelecting && _canWrite) ...[
              _actionButton(
                Icons.paste,
                'Paste (${_clipboard!.paths.length})',
                _paste,
                color: Theme.of(context).colorScheme.primary,
              ),
              _actionButton(
                Icons.close,
                'Clear',
                () => setState(() => _clipboard = null),
                color: Colors.grey,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load directory', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final list = _filteredAndSortedEntries;
    if (list.isEmpty) {
      final isFiltered = _filterQuery.isNotEmpty;
      return RefreshIndicator(
        onRefresh: () async => _load(),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFiltered ? Icons.search_off : Icons.folder_open,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isFiltered
                            ? 'No files matching "$_filterQuery"'
                            : 'Directory is empty',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (isFiltered) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Filter'),
                          onPressed: () {
                            setState(() {
                              _filterQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                      ] else if (_canWrite) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.create_new_folder),
                              label: const Text('New Folder'),
                              onPressed: _createFolder,
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.note_add_outlined),
                              label: const Text('New File'),
                              onPressed: _createFile,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_isGrid) {
      return RefreshIndicator(
        onRefresh: () async => _load(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
          child: GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: list.length + (_hasMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == list.length) {
              return Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.more_horiz),
                        tooltip: 'Load more',
                        onPressed: _loadMore,
                      ),
              );
            }
            final item = list[i];
            final path = _fullEntryPath(item);
            final isSelected = _selectedPaths.contains(path);

            return GestureDetector(
              onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, item),
              child: InkWell(
                onTap: () => _openEntry(item),
                onLongPress: () => _showEntryActions(item),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, size: 36, color: item.iconColor(ctx)),
                            const SizedBox(height: 6),
                            Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(item.formattedSize, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      if (_isSelecting)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelect(path),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: list.length + (_hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == list.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton.icon(
                        icon: const Icon(Icons.expand_more, size: 18),
                        label: const Text('Load more'),
                        onPressed: _loadMore,
                      ),
              ),
            );
          }
          final item = list[i];
          final path = _fullEntryPath(item);
          final isSelected = _selectedPaths.contains(path);

          return GestureDetector(
            onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, item),
            child: ListTile(
              dense: true,
              selected: isSelected,
              leading: _isSelecting
                  ? Checkbox(value: isSelected, onChanged: (_) => _toggleSelect(path))
                  : Icon(item.icon, color: item.iconColor(ctx), size: 28),
              title: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: item.isDir ? FontWeight.w600 : FontWeight.normal),
              ),
              subtitle: Text(
                item.isDir
                    ? item.formattedModified
                    : '${item.formattedSize}  •  ${item.formattedModified}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: item.isDir || item.isArchive ? const Icon(Icons.chevron_right, size: 18) : null,
              onTap: () => _openEntry(item),
              onLongPress: () => _showEntryActions(item),
            ),
          );
        },
      ),
    ),
    );
  }
}
