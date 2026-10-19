import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../dialogs/download_prompt_dialog.dart';
import '../dialogs/file_picker_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/file_open_service.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import 'image_viewer_page.dart';
import 'media_player_page.dart';
import 'text_editor_page.dart';

enum SortField { name, size, modified }

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

  // Multi-selection state
  bool _isSelecting = false;
  final Set<String> _selectedPaths = <String>{};

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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final paged = await listDirPaged(
        root: _root,
        path: _relPath,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _entries.addAll(paged.entries.map((e) => EntryItem(e)));
          _hasMore = paged.hasMore;
          _loadingMore = false;
        });
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
      _currentPage = 1;
      _hasMore = false;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _currentPage = 1;
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

      if (mounted) {
        setState(() {
          _capabilities = caps;
          _entries = items;
          _hasMore = paged.hasMore;
          _loading = false;
        });
        StorageService.instance.recordHistory(root: _root, path: _relPath);
      }
    } catch (e) {
      if (mounted) {
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
        setState(() => _relPath = segments.join('/'));
        _load();
        return;
      }
    }
    // If inside archive, navigate back to host folder
    if (_root.startsWith('archive://')) {
      final archiveHost = _root.substring('archive://'.length);
      final parentDir = archiveHost.split('/').sublist(0, archiveHost.split('/').length - 1).join('/');
      navigateTo(parentDir.isEmpty ? '/' : parentDir, '');
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
      setState(() => _relPath = next);
      _load();
      return;
    }

    if (item.isArchive) {
      final fullPath = _root.endsWith('/')
          ? '$_root${_fullEntryPath(item)}'
          : '$_root/${_fullEntryPath(item)}';
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
      final native = '$root/$path';
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
    final result = await OpenFilex.open('$root/$path');
    if (!mounted) return;
    if (result.type == ResultType.noAppToOpen) {
      _showError('Downloaded, but no installed app can open ${item.name}');
    } else if (result.type != ResultType.done) {
      _showError(result.message);
    }
  }

  Future<void> _openImage(EntryItem item) async {
    final isNative = _root.startsWith('/');
    if (isNative) {
      final fullLocalPath = _root.endsWith('/')
          ? '$_root${_fullEntryPath(item)}'
          : '$_root/${_fullEntryPath(item)}';
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
                onTap: () => Navigator.of(ctx).pop('open'),
              ),
            ListTile(
              leading: const Icon(Icons.download_outlined, color: Colors.blue),
              title: const Text('Download to local'),
              onTap: () => Navigator.of(ctx).pop('download'),
            ),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Share'),
                onTap: () => Navigator.of(ctx).pop('share'),
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
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
      case 'download':
        _downloadSingle(item);
        break;
      case 'share':
        _shareEntry(item);
        break;
      case 'rename':
        setState(() {
          _isSelecting = true;
          _selectedPaths
            ..clear()
            ..add(path);
        });
        _renameSelected();
        break;
      case 'delete':
        setState(() {
          _isSelecting = true;
          _selectedPaths
            ..clear()
            ..add(path);
        });
        _deleteSelected();
        break;
      case 'info':
        _showFileInfo(item);
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
      for (final e in _filteredAndSortedEntries) {
        _selectedPaths.add(_fullEntryPath(e));
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

    final taskId = await TaskService.instance.copy(
      srcRoot: picked.root,
      srcPaths: picked.paths,
      dstRoot: _root,
      dstDir: _relPath,
    );
    if (mounted) {
      await TaskProgressDialog.show(context, taskId, 'Uploading Files...');
      _load();
    }
  }

  Future<void> _downloadSelected() async {
    if (_selectedPaths.isEmpty) return;
    final dest = await FolderPickerDialog.show(
      context,
      title: 'Select Download Destination',
      initialRoot: PlatformPaths.defaultRoot(),
    );
    if (dest == null || !mounted) return;

    final taskId = await TaskService.instance.copy(
      srcRoot: _root,
      srcPaths: _selectedPaths.toList(),
      dstRoot: dest.root,
      dstDir: dest.relPath,
    );
    if (mounted) {
      await TaskProgressDialog.show(context, taskId, 'Downloading Files...');
      if (!mounted) return;
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded to ${dest.path}')),
      );
    }
  }

  Future<void> _downloadSingle(EntryItem item) async {
    final dest = await FolderPickerDialog.show(
      context,
      title: 'Select Download Destination',
      initialRoot: PlatformPaths.defaultRoot(),
    );
    if (dest == null || !mounted) return;

    final taskId = await TaskService.instance.copy(
      srcRoot: _root,
      srcPaths: [_fullEntryPath(item)],
      dstRoot: dest.root,
      dstDir: dest.relPath,
      dstName: item.name,
    );
    if (mounted) {
      await TaskProgressDialog.show(context, taskId, 'Downloading ${item.name}...');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${item.name} to ${dest.path}')),
      );
    }
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
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

    if (mounted) {
      await TaskProgressDialog.show(context, taskId, cb.isCut ? 'Moving Files...' : 'Copying Files...');
      if (cb.isCut) setState(() => _clipboard = null);
      _load();
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedPaths.length;
    final confirm = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count items?'),
        content: const Text('Choose whether to move to Recycle Bin or delete permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          if (!_root.startsWith('remote://') && !_root.startsWith('archive://'))
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

    if (confirm == 'trash') {
      for (final p in _selectedPaths) {
        final full = _root.endsWith('/') ? '$_root$p' : '$_root/$p';
        await StorageService.instance.moveToTrash(full);
      }
      _clearSelection();
      _load();
    } else if (confirm == 'permanent') {
      final taskId = await TaskService.instance.delete(root: _root, paths: _selectedPaths.toList());
      if (mounted) {
        await TaskProgressDialog.show(context, taskId, 'Deleting...');
        _clearSelection();
        _load();
      }
    }
  }

  Future<void> _renameSelected() async {
    if (_selectedPaths.length != 1) return;
    final oldPath = _selectedPaths.first;
    final oldName = oldPath.split('/').last;
    final ctrl = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Name', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Rename')),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      final parent = oldPath.contains('/') ? oldPath.substring(0, oldPath.lastIndexOf('/')) : '';
      final newPath = parent.isEmpty ? newName : '$parent/$newName';
      try {
        await renameEntry(root: _root, from: oldPath, to: newPath);
        _clearSelection();
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
        }
      }
    }
  }

  Future<void> _compressSelected() async {
    final ctrl = TextEditingController(text: 'archive.zip');
    final zipName = await showDialog<String>(
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

    if (zipName != null && zipName.isNotEmpty) {
      final dstPath = _relPath.isEmpty ? '$_root/$zipName' : '$_root/$_relPath/$zipName';
      final taskId = await TaskService.instance.compress(
        srcRoot: _root,
        srcPaths: _selectedPaths.toList(),
        dstArchivePath: dstPath,
      );
      if (mounted) {
        await TaskProgressDialog.show(context, taskId, 'Compressing...');
        _clearSelection();
        _load();
      }
    }
  }

  Future<void> _extractArchive(EntryItem item) async {
    final fullArchive = _root.endsWith('/') ? '$_root${_fullEntryPath(item)}' : '$_root/${_fullEntryPath(item)}';
    final targetDir = _relPath.isEmpty ? _root : '$_root/$_relPath';
    final taskId = await TaskService.instance.extract(archivePath: fullArchive, dstDir: targetDir);
    if (mounted) {
      await TaskProgressDialog.show(context, taskId, 'Extracting Archive...');
      _load();
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
            _infoRow('Path', item.path),
            _infoRow('Size', item.formattedSize),
            _infoRow('Modified', item.formattedModified),
            _infoRow('Type', item.isDir ? 'Directory' : (item.isArchive ? 'Archive' : 'File')),
            _infoRow('Hidden', item.hidden ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          if (item.isArchive)
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
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    final displayName = _root.startsWith('archive://')
        ? '📦 [Archive] ${_root.split('/').last}'
        : (_root.startsWith('remote://') ? '☁️ Remote Storage' : (segments.isEmpty ? _root : segments.last));

    // Back first leaves selection/search, then walks up the directory tree.
    // At the top level the platform handles it (exit or tab switch).
    final canNavigateUp = _isSelecting || _isSearching || _relPath.isNotEmpty ||
        _root.startsWith('archive://');

    return PopScope(
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
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Filter files...', border: InputBorder.none),
                onChanged: (v) => setState(() => _filterQuery = v),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSelecting ? '${_selectedPaths.length} selected' : displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (!_isSelecting)
                    Text(
                      _relPath.isEmpty ? _root : '$_root/$_relPath',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
        actions: [
          if (_isSelecting) ...[
            IconButton(icon: const Icon(Icons.select_all), tooltip: 'Select All', onPressed: _selectAll),
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
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: 'Upload Files',
              onPressed: _uploadFiles,
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              tooltip: 'New Folder',
              onPressed: _createFolder,
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
                PopupMenuItem<String>(
                  value: 'sort_name',
                  child: Text('Sort by Name ${_sortField == SortField.name ? (_sortAsc ? '▲' : '▼') : ''}'),
                ),
                PopupMenuItem<String>(
                  value: 'sort_size',
                  child: Text('Sort by Size ${_sortField == SortField.size ? (_sortAsc ? '▲' : '▼') : ''}'),
                ),
                PopupMenuItem<String>(
                  value: 'sort_date',
                  child: Text('Sort by Date ${_sortField == SortField.modified ? (_sortAsc ? '▲' : '▼') : ''}'),
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
    );
  }

  Widget _buildPathBar(List<String> segments) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Up one level',
            onPressed: (_relPath.isNotEmpty || _root.startsWith('archive://')) ? _navigateUp : null,
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
                        _load();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Root',
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
              _actionButton(Icons.download, 'Download', _downloadSelected, color: Colors.blue),
              _actionButton(Icons.copy, 'Copy', () => _copySelected(isCut: false)),
              _actionButton(Icons.cut, 'Cut', () => _copySelected(isCut: true)),
              _actionButton(Icons.delete, 'Delete', _deleteSelected, color: Colors.red),
              if (_selectedPaths.length == 1)
                _actionButton(Icons.edit, 'Rename', _renameSelected),
              _actionButton(Icons.archive, 'Zip', _compressSelected),
            ],
            if (_clipboard != null && !_isSelecting)
              _actionButton(
                Icons.paste,
                'Paste (${_clipboard!.paths.length})',
                _paste,
                color: Theme.of(context).colorScheme.primary,
              ),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text('Directory is empty', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    if (_isGrid) {
      return GridView.builder(
        controller: _scrollController,
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

          return InkWell(
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
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
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

        return ListTile(
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
          subtitle: Text('${item.formattedSize}  •  ${item.formattedModified}', style: const TextStyle(fontSize: 11)),
          trailing: item.isDir || item.isArchive ? const Icon(Icons.chevron_right, size: 18) : null,
          onTap: () => _openEntry(item),
          onLongPress: () => _showEntryActions(item),
        );
      },
    );
  }
}
