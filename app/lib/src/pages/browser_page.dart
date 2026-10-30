import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import '../dialogs/download_prompt_dialog.dart';
import '../dialogs/file_picker_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/remotes.dart';
import '../services/error_text.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/permission_service.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/entry_thumbnail.dart';
import 'image_viewer_page.dart';
import 'media_player_page.dart';
import 'text_editor_page.dart';

enum SortField { name, size, modified, type }

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.name => 'Name',
        SortField.size => 'Size',
        SortField.modified => 'Date',
        SortField.type => 'Type',
      };
}

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

  /// True when hosted inside the split view: no route back button, no
  /// PopScope interception, no nested split.
  final bool embedded;

  /// Reports the current location whenever it changes (used by the
  /// split host to restore the left pane's location on exit).
  final void Function(String root, String path)? onLocationChanged;

  const BrowserPage({
    super.key,
    required this.initialRoot,
    this.initialPath = '',
    this.embedded = false,
    this.onLocationChanged,
  });

  @override
  State<BrowserPage> createState() => BrowserPageState();
}

class BrowserPageState extends State<BrowserPage> {
  late String _root;
  late String _relPath;
  List<EntryItem> _entries = [];
  bool _loading = false;
  /// A refresh keeps the old list on screen, so without this the F5 / Cmd+R
  /// shortcut (and the pull-to-refresh) looked like it did nothing.
  bool _refreshing = false;
  String? _error;
  CapabilitiesDto? _capabilities;

  bool _isGrid = false;
  bool _showHidden = false;
  SortField _sortField = SortField.name;
  bool _sortAsc = true;

  static const _prefGrid = 'browser.grid';
  static const _prefHidden = 'browser.show_hidden';
  static const _prefSortField = 'browser.sort_field';
  static const _prefSortAsc = 'browser.sort_asc';

  /// Restore view preferences so a new browser keeps the last layout.
  void _loadViewPreferences() {
    final prefs = PreferencesService.instance;
    _isGrid = prefs.getBool(_prefGrid) ?? _isGrid;
    _showHidden = prefs.getBool(_prefHidden) ?? _showHidden;
    final field = prefs.getString(_prefSortField);
    if (field != null) {
      _sortField = SortField.values.firstWhere(
        (f) => f.name == field,
        orElse: () => _sortField,
      );
    }
    _sortAsc = prefs.getBool(_prefSortAsc) ?? _sortAsc;
  }

  void _saveViewPreferences() {
    final prefs = PreferencesService.instance;
    prefs.setBool(_prefGrid, _isGrid);
    prefs.setBool(_prefHidden, _showHidden);
    prefs.setString(_prefSortField, _sortField.name);
    prefs.setBool(_prefSortAsc, _sortAsc);
  }
  String _filterQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  // Recursive search (Rust side) state: results for the current query,
  // debounced so a remote folder is not walked on every keystroke.
  List<EntryItem> _searchResults = [];
  bool _searchBusy = false;
  Timer? _searchDebounce;
  int _searchSeq = 0;
  final FocusNode _searchFocusNode = FocusNode();

  // Address bar direct jump state
  bool _isEditingAddress = false;
  final TextEditingController _addressController = TextEditingController();

  String get _displayFullPath {
    if (isNativeRoot(_root)) {
      return joinNative(_root, _relPath);
    }
    String rootPart = _root;
    if (_root.startsWith('remote://')) {
      final remoteId = _root.substring('remote://'.length);
      final remote = _findRemote(remoteId);
      if (remote != null) {
        rootPart = 'remote://${remote.name}';
      }
    }
    if (_relPath.isEmpty) return rootPart;
    final cleanRel = _relPath.startsWith('/') ? _relPath.substring(1) : _relPath;
    return '$rootPart/$cleanRel';
  }

  List<RemoteConfigDto> _remotes = [];

  Future<void> _loadRemotesMetadata() async {
    try {
      final rems = await StorageService.instance.getRemotes();
      if (mounted) {
        setState(() => _remotes = rems);
      }
    } catch (_) {}
  }

  RemoteConfigDto? _findRemote(String idOrName) {
    for (final r in _remotes) {
      if (r.id == idOrName || r.name.toLowerCase() == idOrName.toLowerCase()) {
        return r;
      }
    }
    return null;
  }

  // Multi-selection state
  bool _isSelecting = false;

  /// Anchor index (into the visible list) for Shift+click range selection.
  int? _selectionAnchor;

  /// Rubber-band (lasso) selection state, grid view only: mouse drag on
  /// the grid background selects every tile the rectangle covers.
  Offset? _lassoStart;
  Rect? _lassoRect;
  Set<String> _lassoBase = {};
  double _gridWidth = 0;

  /// Set while a tile drag (stage H) is in flight so the lasso stands down.
  bool _itemDragActive = false;
  final Set<String> _selectedPaths = <String>{};
  double _swipeStartX = 0;
  double _swipeDeltaX = 0;

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
    return count == 0 ? 'Select items' : '$count selected';
  }

  // Pagination state
  int _currentPage = 1;
  static const int _pageSize = 100;
  bool _hasMore = false;
  int _totalCount = 0;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Clipboard state for copy/cut/paste
  static ClipboardState? _clipboard;

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    _relPath = widget.initialPath;
    _loadViewPreferences();
    _scrollController.addListener(_onScroll);
    PreferencesService.toolbarAtBottom.addListener(_onToolbarPositionChanged);
    _loadRemotesMetadata();
    _load();
  }

  void _onToolbarPositionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PreferencesService.toolbarAtBottom.removeListener(_onToolbarPositionChanged);
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.position.pixels > 350;
      if (shouldShow != _showScrollToTop) {
        setState(() => _showScrollToTop = shouldShow);
      }
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 250 &&
          _hasMore &&
          !_loadingMore &&
          !_loading) {
        _loadMore();
      }
    }
  }

  bool _showScrollToTop = false;

  /// Directory the in-flight load belongs to. A load started for one folder
  /// must not fill the list after the user has navigated elsewhere.
  String? _loadingFor;
  DateTime? _lastItemSecondaryTap;

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
        sortBy: _sortField.name,
        sortAscending: _sortAsc,
      );
      if (!mounted) return;
      if (_loadingFor == loadingFor) {
        setState(() {
          _currentPage = nextPage;
          _entries.addAll(paged.entries.map((e) => EntryItem(e)));
          _hasMore = paged.hasMore;
          _totalCount = paged.total;
          _loadingMore = false;
        });
        if (_filteredAndSortedEntries.isEmpty && _hasMore) {
          _loadMore();
        }
      } else {
        setState(() => _loadingMore = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMore = false);
        // Without this the "Load more" button just does nothing on failure.
        _showError('Could not load more: ${_friendlyError(e)}');
      }
    }
  }

  /// Split view (dual pane): both panes are full BrowserPages hosted by
  /// this one; exiting returns to the left pane's last location.
  bool _splitActive = false;
  Widget? _splitPaneA;
  Widget? _splitPaneB;
  (String, String)? _splitReturn;

  void _toggleSplit() {
    if (_splitActive) {
      setState(() {
        _splitActive = false;
        _splitPaneA = null;
        _splitPaneB = null;
      });
      final ret = _splitReturn;
      _splitReturn = null;
      if (ret != null && (ret.$1 != _root || ret.$2 != _relPath)) {
        navigateTo(ret.$1, ret.$2);
      }
    } else {
      setState(() {
        _splitPaneA = BrowserPage(
          embedded: true,
          initialRoot: _root,
          initialPath: _relPath,
          onLocationChanged: (r, p) => _splitReturn = (r, p),
        );
        _splitPaneB = BrowserPage(
          embedded: true,
          initialRoot: _root,
          initialPath: _relPath,
        );
        _splitActive = true;
      });
    }
  }

  /// Back/forward history within the current root. A root switch starts
  /// a fresh history, like opening a new window in a desktop manager.
  final List<String> _backStack = [];
  final List<String> _forwardStack = [];

  void _pushHistory() {
    if (_backStack.isEmpty || _backStack.last != _relPath) {
      _backStack.add(_relPath);
      if (_backStack.length > 100) _backStack.removeAt(0);
    }
    _forwardStack.clear();
  }

  void _goBack() {
    if (_backStack.isEmpty) return;
    _forwardStack.add(_relPath);
    final target = _backStack.removeLast();
    setState(() {
      _relPath = target;
      _isSelecting = false;
      _selectedPaths.clear();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load();
  }

  void _goForward() {
    if (_forwardStack.isEmpty) return;
    _backStack.add(_relPath);
    final target = _forwardStack.removeLast();
    setState(() {
      _relPath = target;
      _isSelecting = false;
      _selectedPaths.clear();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load();
  }

  void _handleSwipeBack() {
    if (_isSelecting) {
      _clearSelection();
      return;
    }
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _filterQuery = '';
        _searchController.clear();
        _searchResults = [];
        _searchBusy = false;
      });
      return;
    }
    if (_backStack.isNotEmpty) {
      _goBack();
      return;
    }
    if (_canNavigateUp) {
      _navigateUp();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void navigateTo(String root, String relPath) {
    setState(() {
      _root = root;
      _relPath = relPath;
      _backStack.clear();
      _forwardStack.clear();
      _isSelecting = false;
      _selectedPaths.clear();
      _isSearching = false;
      _filterQuery = '';
      _searchController.clear();
      _searchResults = [];
      _searchBusy = false;
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
        final target = withoutPrefix.substring(0, slashIdx);
        final rel = withoutPrefix.substring(slashIdx + 1).replaceAll(RegExp(r'^/+'), '');
        final remote = _findRemote(target);
        final resolvedId = remote != null ? remote.id : target;
        navigateTo('remote://$resolvedId', rel);
      } else {
        final remote = _findRemote(withoutPrefix);
        final resolvedId = remote != null ? remote.id : withoutPrefix;
        navigateTo('remote://$resolvedId', '');
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

  /// [refresh] keeps the scroll offset so a pull-to-refresh or a post-action
  /// reload does not throw the user back to the top of a long folder.
  Future<void> _load({bool refresh = false}) async {
    widget.onLocationChanged?.call(_root, _relPath);
    final loadingFor = '$_root\u0000$_relPath';
    _loadingFor = loadingFor;
    setState(() {
      // A refresh keeps the current list on screen; swapping it for a spinner
      // would drop the scroll offset and flash the whole page.
      if (!refresh) _loading = true;
      if (refresh) _refreshing = true;
      if (!refresh) _selectionAnchor = null;
      // Navigating (a non-refresh load) leaves search behind: the results
      // belonged to the folder the user just left.
      if (!refresh && _isSearching) {
        _isSearching = false;
        _filterQuery = '';
        _searchResults = [];
        _searchBusy = false;
        _searchController.clear();
      }
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
        sortBy: _sortField.name,
        sortAscending: _sortAsc,
      );
      final items = paged.entries.map((e) => EntryItem(e)).toList();

      // A newer navigation superseded this load; its result belongs to a
      // folder the user already left.
      if (!mounted || _loadingFor != loadingFor) return;
      setState(() {
        _capabilities = caps;
        _entries = items;
        _hasMore = paged.hasMore;
        _totalCount = paged.total;
        _loading = false;
        _refreshing = false;
      });
      if (!refresh && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      StorageService.instance.recordHistory(root: _root, path: _relPath);

      // If hidden files are filtered out and this batch left the visible list empty,
      // keep fetching the next page so directories with many dotfiles (like $HOME)
      // do not display as empty.
      if (_entries.isNotEmpty && _filteredAndSortedEntries.isEmpty && _hasMore) {
        _loadMore();
      }
    } catch (e) {
      if (mounted && _loadingFor == loadingFor) {
        if (refresh && _entries.isNotEmpty) {
          // A failed refresh must not nuke a list the user is looking at
          // (a network blip on a remote folder used to replace the whole
          // page with an error). Keep the entries; report via snackbar.
          setState(() {
            _loading = false;
            _refreshing = false;
          });
          _showError('Refresh failed: ${_friendlyError(e)}');
        } else {
          setState(() {
            _error = _friendlyError(e);
            // The entries and capabilities belong to the folder that just failed
            // to load; keeping them makes the bars contradict the error body.
            _entries = [];
            _hasMore = false;
            _capabilities = null;
            _loading = false;
            _refreshing = false;
          });
        }
      }
    }
  }

  bool get _canNavigateUp {
    if (_relPath.isNotEmpty) return true;
    if (_root.startsWith('archive://')) return true;
    if (_root.startsWith('/') && _root != '/') return true;
    final driveMatch = RegExp(r'^[a-zA-Z]:[/\\]').firstMatch(_root);
    if (driveMatch != null) {
      final rest = _root.substring(driveMatch.end);
      return rest.split(RegExp(r'[/\\]')).any((s) => s.isNotEmpty);
    }
    return false;
  }

  void _navigateUp() {
    if (_relPath.isNotEmpty) {
      final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        segments.removeLast();
        _pushHistory();
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
      _pushHistory();
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
            readOnly: !_canWrite,
          ),
        ),
      ).then((_) => _load(refresh: true));
      return;
    }

    if (item.isMedia) {
      // The playlist is the folder's media files in the order currently
      // on screen (same filter + sort), so Next matches what the user
      // sees. Only loaded entries are included.
      final mediaEntries =
          _filteredAndSortedEntries.where((e) => e.isMedia).toList();
      final tracks = mediaEntries
          .map((e) => MediaTrack(
                path: _fullEntryPath(e),
                fileName: e.name,
                isAudio: e.isAudio,
              ))
          .toList();
      final startIndex =
          mediaEntries.indexWhere((e) => e.name == item.name);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: _root,
            path: _fullEntryPath(item),
            fileName: item.name,
            isAudio: item.isAudio,
            playlist: tracks,
            startIndex: startIndex < 0 ? 0 : startIndex,
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

      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: _root,
            srcPaths: [_fullEntryPath(item)],
            dstRoot: destination.root,
            dstDir: dstDir,
            dstName: name,
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading ${item.name}',
        onRetry: startTask,
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
            readOnly: root.startsWith('archive://'),
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

  /// Images in the current folder, for swiping inside the viewer.
  /// Native roots pass a local path per entry; remote and archive roots pass
  /// the VFS location, which the viewer exports lazily when each image is
  /// actually shown.
  (List<ImageViewerEntry>, int) _imageSiblings(EntryItem item) {
    final images = _filteredAndSortedEntries.where((e) => !e.isDir && e.isImage).toList();
    if (images.isEmpty) return (const [], 0);
    final native = isNativeRoot(_root);
    final entries = images
        .map((e) => native
            ? ImageViewerEntry(
                name: e.name,
                localPath: joinNative(_root, _fullEntryPath(e)),
              )
            : ImageViewerEntry(
                name: e.name,
                root: _root,
                remotePath: _fullEntryPath(e),
              ))
        .toList();
    final index = images.indexWhere((e) => e.name == item.name);
    return (entries, index < 0 ? 0 : index);
  }

  Future<void> _openImage(EntryItem item) async {
    final (siblings, index) = _imageSiblings(item);
    final native = isNativeRoot(_root);
    final fullLocalPath = native ? joinNative(_root, _fullEntryPath(item)) : '';

    if (native) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: fullLocalPath,
            fileName: item.name,
            siblings: siblings,
            initialIndex: index,
          ),
        ),
      );
      return;
    }

    // Remote and archive images have no native path yet; the viewer exports
    // the current one and any image swiped to.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          filePath: '',
          fileName: item.name,
          siblings: siblings,
          initialIndex: index,
        ),
      ),
    );
  }

  Future<void> _openWithSystem(EntryItem item) async {
    try {
      if (Platform.isAndroid && item.name.toLowerCase().endsWith('.apk')) {
        if (!await PermissionService.instance.hasInstallPackagesAccess()) {
          final granted = await PermissionService.instance.requestInstallPackagesAccess();
          if (!granted) {
            _showError('Allow installing unknown apps to open APK files');
            return;
          }
        }
      }
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

  /// Backend errors arrive as `kind: detail` strings. Turn the common ones
  /// into something a user can act on instead of echoing the Rust wording.
  String _friendlyError(Object error) => friendlyErrorText(error);

  /// Two layers: the local filter keeps narrowing the loaded pages as you
  /// type (instant, 1+ chars), and a debounced recursive search on the
  /// Rust side finds matches inside subfolders (2+ chars). The recursive
  /// results take over the body; the old behaviour — filtering only what
  /// was already fetched — made files in subfolders unfindable.
  void _onFilterChanged(String value) {
    // The anchor is an index into the visible list; the filter reorders that
    // list, so a stale anchor made the next Shift-click select the wrong span.
    setState(() {
      _filterQuery = value;
      _selectionAnchor = null;
    });
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    try {
      final dtos = await searchEntries(
        root: _root,
        path: _relPath,
        query: query,
        maxResults: 200,
      );
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchResults = dtos.map((e) => EntryItem(e)).toList();
        _searchBusy = false;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() => _searchBusy = false);
      _showError('Search failed: ${_friendlyError(e)}');
    }
  }

  /// Reset all search state (used when leaving search or navigating).
  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchSeq++;
    setState(() {
      _filterQuery = '';
      _searchResults = [];
      _searchBusy = false;
    });
    _searchController.clear();
  }

  Widget _buildSearchResults() {
    if (_searchBusy && _searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'No results for "${_filterQuery.trim()}"',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Searched this folder and its subfolders.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear search'),
                onPressed: () {
                  setState(() {
                    _filterQuery = '';
                    _searchController.clear();
                    _isSearching = false;
                  });
                },
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchBusy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            _searchResults.length >= 200
                ? 'First 200 results (narrow the search to see more)'
                : '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'} in this folder and subfolders',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _searchResults.length,
            itemBuilder: (ctx, i) {
              final item = _searchResults[i];
              return ListTile(
                leading: Icon(item.icon),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _searchResultParent(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing:
                    item.isDir ? const Icon(Icons.chevron_right, size: 18) : null,
                onTap: () => _openSearchResult(item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Display parent for a search hit: its folder path from the root.
  String _searchResultParent(EntryItem item) {
    var p = item.path;
    if (p.startsWith('/')) p = p.substring(1);
    final idx = p.lastIndexOf('/');
    if (idx < 0) return 'Current folder';
    return p.substring(0, idx);
  }

  /// Open a search hit: folders navigate straight in; files navigate to
  /// their folder first (then open), because the open flows are written
  /// against entries of the current folder.
  Future<void> _openSearchResult(EntryItem item) async {
    var p = item.path;
    if (p.startsWith('/')) p = p.substring(1);
    _pushHistory();
    if (item.isDir) {
      setState(() => _relPath = p);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _load();
      return;
    }
    final parent = p.contains('/') ? p.substring(0, p.lastIndexOf('/')) : '';
    setState(() => _relPath = parent);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _load();
    if (!mounted) return;
    final match = _entries.where((e) => e.name == item.name).firstOrNull;
    if (match != null) _openEntry(match);
  }

  /// True while the address or search field holds the keyboard. Page-wide
  /// shortcuts (Cmd+A, C/X/V, `/`) must not steal those keys from typing.
  bool get _isTyping => _isEditingAddress || _searchFocusNode.hasFocus;

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  /// Long-press menu for one entry, matching the actions the original app
  /// offers on a file.
  Future<void> _showEntryActions(EntryItem item) async {
    HapticFeedback.mediumImpact();
    final path = _fullEntryPath(item);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
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
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy Path'),
              onTap: () => Navigator.of(ctx).pop('copy_path'),
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
            if (item.isDir)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Bookmark This Folder'),
                onTap: () => Navigator.of(ctx).pop('bookmark'),
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
      ),
    );

    switch (action) {
      case 'open':
        _openEntry(item);
        break;
      case 'copy_path':
        _copyEntryPath(item);
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
      case 'bookmark':
        _bookmarkFolder(item);
        break;
      case 'info':
        _showFileInfo(item);
        break;
    }
  }

  /// Desktop right-click context menu on a file/folder referencing File Manager+.
  Future<void> _showContextMenu(BuildContext originContext, Offset position, EntryItem item) async {
    HapticFeedback.mediumImpact();
    _lastItemSecondaryTap = DateTime.now();
    final path = _fullEntryPath(item);
    final action = await showMenu<String>(
      context: originContext,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(originContext).height * 0.85,
        minWidth: 200,
      ),
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
        const PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(Icons.link, size: 18),
              SizedBox(width: 8),
              Text('Copy Path'),
            ],
          ),
        ),
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
        if (item.isDir)
          const PopupMenuItem(
            value: 'bookmark',
            child: Row(
              children: [
                Icon(Icons.bookmark_add_outlined, size: 18),
                SizedBox(width: 8),
                Text('Bookmark This Folder'),
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
      case 'bookmark':
        _bookmarkFolder(item);
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
      case 'copy_path':
        _copyEntryPath(item);
        break;
      case 'info':
        _showFileInfo(item);
        break;
    }
  }

  void _copyEntryPath(EntryItem item) {
    final path = _fullEntryPath(item);
    final full = isNativeRoot(_root) ? joinNative(_root, path) : '$_root/$path';
    Clipboard.setData(ClipboardData(text: full));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Path copied to clipboard')),
    );
  }

  /// Desktop right-click context menu on empty space.
  Future<void> _showBackgroundContextMenu(Offset position) async {
    if (_lastItemSecondaryTap != null &&
        DateTime.now().difference(_lastItemSecondaryTap!).inMilliseconds < 400) {
      return;
    }
    HapticFeedback.mediumImpact();
    final action = await showMenu<String>(
      context: context,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        minWidth: 200,
      ),
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
          value: 'invert_selection',
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 18),
              SizedBox(width: 8),
              Text('Invert Selection'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'bookmark',
          child: Row(
            children: [
              Icon(Icons.bookmark_add_outlined, size: 18),
              SizedBox(width: 8),
              Text('Bookmark This Folder'),
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
        _load(refresh: true);
        break;
      case 'select_all':
        setState(() => _isSelecting = true);
        _selectAll();
        break;
      case 'invert_selection':
        _invertSelection();
        break;
      case 'bookmark':
        _bookmarkCurrentFolder();
        break;
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: _displayFullPath));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Folder path copied to clipboard')),
        );
        break;
    }
  }

  /// Tile tap with desktop selection semantics: Ctrl/Cmd toggles one
  /// item, Shift extends from the anchor, plain tap keeps the classic
  /// behaviour (open, or toggle while selecting).
  void _handleTileTap(EntryItem item, int index) {
    final kb = HardwareKeyboard.instance;
    if (kb.isShiftPressed && _selectionAnchor != null) {
      _selectRange(_selectionAnchor!, index);
      return;
    }
    if (kb.isControlPressed || kb.isMetaPressed) {
      if (!_isSelecting) setState(() => _isSelecting = true);
      _toggleSelect(_fullEntryPath(item));
      _selectionAnchor = index;
      return;
    }
    _selectionAnchor = index;
    _openEntry(item);
  }

  void _lassoDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) {
      return;
    }
    _lassoStart = e.localPosition;
    _lassoRect = null;
    final kb = HardwareKeyboard.instance;
    _lassoBase = (kb.isControlPressed || kb.isMetaPressed)
        ? {..._selectedPaths}
        : {};
  }

  void _lassoMove(PointerMoveEvent e) {
    final start = _lassoStart;
    if (start == null || _itemDragActive) return;
    final rect = Rect.fromPoints(start, e.localPosition);
    if (_lassoRect == null && rect.longestSide < 8) return;
    setState(() => _lassoRect = rect);
    _applyLasso(rect);
  }

  void _lassoEnd() {
    _lassoStart = null;
    if (_lassoRect != null) setState(() => _lassoRect = null);
  }

  /// Maps the lasso rectangle (viewport coordinates) through the grid
  /// delegate's math and selects every tile it intersects. The delegate
  /// is SliverGridDelegateWithMaxCrossAxisExtent(88, spacing 6, ratio
  /// 0.85) with 8px padding — keep these numbers in sync with _buildBody.
  void _applyLasso(Rect viewportRect) {
    final list = _filteredAndSortedEntries;
    if (_gridWidth <= 0 || list.isEmpty) return;
    const pad = 8.0;
    const spacing = 6.0;
    final crossExtent = _gridWidth - pad * 2;
    var count = (crossExtent / (88.0 + spacing)).ceil();
    if (count < 1) count = 1;
    final childCross = (crossExtent - spacing * (count - 1)) / count;
    final childMain = childCross / 0.85;
    final colStride = childCross + spacing;
    final rowStride = childMain + spacing;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final r = Rect.fromLTRB(
      viewportRect.left,
      viewportRect.top + offset,
      viewportRect.right,
      viewportRect.bottom + offset,
    );
    final picked = <String>{};
    final firstRow = ((r.top - pad) / rowStride).floor().clamp(0, 1 << 30);
    final lastRow = ((r.bottom - pad) / rowStride).floor().clamp(0, 1 << 30);
    final firstCol = ((r.left - pad) / colStride).floor().clamp(0, count - 1);
    final lastCol = ((r.right - pad) / colStride).floor().clamp(0, count - 1);
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        final cell = Rect.fromLTWH(
          pad + col * colStride,
          pad + row * rowStride,
          childCross,
          childMain,
        );
        if (!cell.overlaps(r)) continue;
        final idx = row * count + col;
        if (idx < 0 || idx >= list.length) continue;
        picked.add(_fullEntryPath(list[idx]));
      }
    }
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(_lassoBase)
        ..addAll(picked);
      _isSelecting = _selectedPaths.isNotEmpty;
    });
  }

  void _selectRange(int a, int b) {
    final list = _filteredAndSortedEntries;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final kb = HardwareKeyboard.instance;
    // Shift alone starts a fresh range, like every desktop file manager;
    // Ctrl/Shift adds to what is already selected.
    final additive = kb.isControlPressed || kb.isMetaPressed;
    setState(() {
      _isSelecting = true;
      if (!additive) _selectedPaths.clear();
      for (var i = lo; i <= hi && i < list.length; i++) {
        _selectedPaths.add(_fullEntryPath(list[i]));
      }
    });
  }

  void _toggleSelect(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) _isSelecting = false;
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  /// Select all *visible* entries — including the ones not paged in yet.
  ///
  /// This used to iterate only the loaded pages, so Ctrl+A in a 1,000-file
  /// folder selected a silent 100. When more pages exist, fetch the whole
  /// (server-sorted) folder in one call first; beyond a sanity cap, say so
  /// instead of pretending everything is selected.
  Future<void> _selectAll() async {
    HapticFeedback.selectionClick();
    if (_hasMore && _totalCount > 0) {
      if (_totalCount > 10000) {
        // Returning matters: falling through selected only the loaded pages,
        // so the counter claimed a selection that was not the whole folder.
        _showError('Too many items to select all at once ($_totalCount)');
        return;
      } else {
        try {
          final paged = await listDirPaged(
            root: _root,
            path: _relPath,
            page: 1,
            pageSize: _totalCount,
            sortBy: _sortField.name,
            sortAscending: _sortAsc,
          );
          if (!mounted) return;
          setState(() {
            _entries = paged.entries.map((e) => EntryItem(e)).toList();
            _hasMore = false;
            _currentPage = 1;
            _totalCount = paged.total;
          });
        } catch (e) {
          _showError('Could not load all items: ${_friendlyError(e)}');
        }
      }
    }
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

  void _openSelected() {
    if (_selectedPaths.length != 1) return;
    final path = _selectedPaths.first;
    final item = _entries.where((e) => _fullEntryPath(e) == path).firstOrNull;
    if (item == null) return;
    _clearSelection();
    _openEntry(item);
  }

  void _selectAdjacent(int delta) {
    if (_isTyping) return;
    final list = _filteredAndSortedEntries;
    if (list.isEmpty) return;
    int currentIndex = -1;
    if (_selectedPaths.isNotEmpty) {
      final lastSelected = _selectedPaths.last;
      currentIndex = list.indexWhere((e) => _fullEntryPath(e) == lastSelected);
    }
    final nextIndex = currentIndex < 0
        ? (delta > 0 ? 0 : list.length - 1)
        : (currentIndex + delta).clamp(0, list.length - 1);
    final target = list[nextIndex];
    setState(() {
      _selectedPaths.clear();
      _selectedPaths.add(_fullEntryPath(target));
      _isSelecting = true;
    });
  }

  void _selectBoundary(bool first) {
    if (_isTyping) return;
    final list = _filteredAndSortedEntries;
    if (list.isEmpty) return;
    final target = first ? list.first : list.last;
    setState(() {
      _selectedPaths.clear();
      _selectedPaths.add(_fullEntryPath(target));
      _isSelecting = true;
    });
  }

  void _clearSelection() {
    HapticFeedback.lightImpact();
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
      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: picked.root,
            srcPaths: picked.paths,
            dstRoot: _root,
            dstDir: _relPath,
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Uploading ${picked.paths.length} item(s)…',
        onRetry: startTask,
      );
      if (mounted) _load(refresh: true);
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
      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: _root,
            srcPaths: _selectedPaths.toList(),
            dstRoot: dest.root,
            dstDir: dest.relPath,
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading Files…',
        onRetry: startTask,
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
      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: _root,
            srcPaths: [_fullEntryPath(item)],
            dstRoot: dest.root,
            dstDir: dest.relPath,
            dstName: item.name,
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        'Downloading ${item.name}…',
        onRetry: startTask,
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
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Create'),
              ),
            ),
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
        _load(refresh: true);
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
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Create'),
              ),
            ),
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
        _load(refresh: true);
        if (!mounted) return;
        // A file that was just created is almost always meant to be written
        // in, so open it rather than making the user find it in the list.
        final createdName = name;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TextEditorPage(
              root: _root,
              path: target,
              fileName: createdName,
            ),
          ),
        ).then((_) => _load(refresh: true));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create file: $e'), backgroundColor: Theme.of(context).colorScheme.error),
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
    await _transfer(
      srcRoot: cb.srcRoot,
      paths: cb.paths,
      isCut: cb.isCut,
      destRel: _relPath,
      onCutCompleted: () {
        if (mounted) setState(() => _clipboard = null);
      },
    );
  }

  /// Shared transfer engine for paste and drag & drop: conflict prompt,
  /// progress dialog, retry. [destRel] is the destination folder inside
  /// the current root.
  Future<void> _transfer({
    required String srcRoot,
    required List<String> paths,
    required bool isCut,
    required String destRel,
    VoidCallback? onCutCompleted,
  }) async {
    // Detect name clashes in the destination first and let the user decide
    // once for the whole batch. Overwriting silently would destroy the
    // existing files. Items dropped back into their own folder are
    // excluded: the Rust side renames those automatically.
    var policy = 'overwrite';
    final conflicts = <String>[];
    for (final p in paths) {
      final name = p.split('/').last;
      final dstPath = destRel.isEmpty ? name : '$destRel/$name';
      if (srcRoot == _root && p == dstPath) continue;
      try {
        await statEntry(root: _root, path: dstPath);
        conflicts.add(name);
      } catch (_) {
        // Missing (or not stat-able): nothing to decide for this item.
      }
    }
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Already exists'),
          actionsOverflowButtonSpacing: 6,
          content: Text(
            conflicts.length == 1
                ? '"${conflicts.first}" already exists in this folder. What should happen to it?'
                : '${conflicts.length} items already exist in this folder. What should happen to them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: const Text('Skip'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'rename'),
              child: const Text('Keep both'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      policy = choice;
    }

    Future<String> startTask() => isCut
        ? TaskService.instance.move(
            srcRoot: srcRoot,
            srcPaths: paths,
            dstRoot: _root,
            dstDir: destRel,
            conflictPolicy: policy,
          )
        : TaskService.instance.copy(
            srcRoot: srcRoot,
            srcPaths: paths,
            dstRoot: _root,
            dstDir: destRel,
            conflictPolicy: policy,
          );

    try {
      final taskId = await startTask();

      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        isCut ? 'Moving Files…' : 'Copying Files…',
        onRetry: startTask,
      );
      // A cancelled move may have already removed some sources, so a cut
      // clipboard is only cleared once the move actually finished.
      if (isCut && completed == true) onCutCompleted?.call();
      if (mounted) _load(refresh: true);
    } catch (e) {
      _showError('${isCut ? 'Move' : 'Copy'} failed: $e');
    }
  }

  /// Files dropped in from the OS (Finder/Explorer): each file's parent
  /// folder becomes a source root and the normal copy pipeline takes
  /// over, conflict prompt included.
  Future<void> _handleExternalDrop(DropDoneDetails details) async {
    final files = details.files;
    if (files.isEmpty) return;
    if (!_canWrite) {
      // The drop target accepted the drag but nothing landed, with no
      // explanation, so a read-only folder looked like a broken app.
      _showError('This location is read-only — cannot drop files here');
      return;
    }
    final byParent = <String, List<String>>{};
    for (final f in files) {
      final full = f.path.replaceAll('\\', '/');
      final idx = full.lastIndexOf('/');
      if (idx < 0) continue;
      final parent = idx == 0 ? '/' : full.substring(0, idx);
      byParent.putIfAbsent(parent, () => []).add(full.substring(idx + 1));
    }
    for (final entry in byParent.entries) {
      await _transfer(
        srcRoot: entry.key,
        paths: entry.value,
        isCut: false,
        destRel: _relPath,
      );
      if (!mounted) return;
    }
  }

  Widget _withDropTarget(Widget child) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return child;
    }
    return DropTarget(
      onDragDone: _handleExternalDrop,
      child: child,
    );
  }

  /// Drag & drop landing: same root moves, cross-root copies — the
  /// convention desktop file managers use.
  Future<void> _acceptDrop(
    ({String root, List<String> paths}) data,
    String destRel,
  ) async {
    final isCut = data.root == _root;
    // Dropping a folder onto itself or into its own subtree can only fail.
    final safe = data.paths.where((p) {
      if (!isCut) return true;
      return destRel != p && !destRel.startsWith('$p/');
    }).toList();
    if (safe.isEmpty) {
      // The drag landed but nothing happened; say why instead of silently
      // swallowing a folder dropped onto itself.
      _showError('Cannot drop a folder onto itself or into its own subfolder');
      return;
    }
    await _transfer(
      srcRoot: data.root,
      paths: safe,
      isCut: isCut,
      destRel: destRel,
    );
  }

  /// Wraps a tile so it can be dragged (desktop builds) and, for folders,
  /// receive drops. Touch builds keep the long-press menu instead: an
  /// immediate Draggable would fight it and the scroll gesture.
  Widget _draggableTile({
    required EntryItem item,
    required String path,
    required Widget child,
  }) {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return child;
    }
    final data = (
      root: _root,
      paths: _selectedPaths.contains(path)
          ? _selectedPaths.toList()
          : [path],
    );
    Widget draggable = Draggable<({String root, List<String> paths})>(
      data: data,
      onDragStarted: () => _itemDragActive = true,
      onDragEnd: (_) => _itemDragActive = false,
      onDraggableCanceled: (_, _) => _itemDragActive = false,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 16),
              const SizedBox(width: 6),
              Text(
                data.paths.length > 1
                    ? '${data.paths.length} items'
                    : item.name,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
    if (item.isDir || item.isArchive) {
      // The builder closure must wrap the Draggable, not `draggable` itself:
      // capturing the variable after reassignment would nest the DragTarget
      // inside its own builder and recurse until the stack overflows.
      final dragSource = draggable;
      draggable = DragTarget<({String root, List<String> paths})>(
        onWillAcceptWithDetails: (details) {
          final d = details.data;
          if (d.paths.contains(path)) return false;
          if (d.root == _root &&
              d.paths.any((p) => path.startsWith('$p/'))) {
            return false;
          }
          return true;
        },
        onAcceptWithDetails: (details) => _acceptDrop(details.data, path),
        builder: (ctx, candidate, rejected) => Container(
          decoration: candidate.isNotEmpty
              ? BoxDecoration(
                  border: Border.all(
                    color: Theme.of(ctx).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: dragSource,
        ),
      );
    }
    return draggable;
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
      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: _root,
            srcPaths: [_fullEntryPath(item)],
            dstRoot: _root,
            dstDir: _relPath,
            dstName: candidate,
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(context, taskId, 'Duplicating…', onRetry: startTask);
      if (completed == true && mounted) {
        _load(refresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$candidate"')),
        );
      }
    } catch (e) {
      _showError('Duplicate failed: $e');
    }
  }

  Future<void> _deleteSelected({bool permanent = false}) =>
      _deletePaths(_selectedPaths.toList(), permanent: permanent);

  Future<void> _deleteSingle(EntryItem item) =>
      _deletePaths([_fullEntryPath(item)]);

  Future<void> _deletePaths(List<String> paths, {bool permanent = false}) async {
    if (paths.isEmpty) return;
    final count = paths.length;
    final canTrash = isNativeRoot(_root) && !permanent;
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          canTrash ? Icons.delete_outline : Icons.warning_amber_rounded,
          color: canTrash ? scheme.primary : scheme.error,
          size: 28,
        ),
        title: Text(count == 1 ? 'Delete "${paths.first.split('/').last}"?' : 'Delete $count items?'),
        content: Text(
          canTrash
              ? 'Choose whether to move to Recycle Bin or delete permanently.'
              : permanent
                  ? 'Delete permanently? This cannot be undone.'
                  : 'This item is on a remote server and cannot be moved to the '
                      'local Recycle Bin. It will be deleted permanently.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          if (canTrash) ...[
            TextButton.icon(
              icon: Icon(Icons.delete_forever, size: 18, color: scheme.error),
              label: Text('Permanent Delete', style: TextStyle(color: scheme.error)),
              onPressed: () => Navigator.of(ctx).pop('permanent'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Recycle Bin'),
              onPressed: () => Navigator.of(ctx).pop('trash'),
            ),
          ] else
            FilledButton.icon(
              icon: const Icon(Icons.delete_forever, size: 18),
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop('permanent'),
              label: const Text('Permanent Delete'),
            ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirm == 'trash') {
      // Per-item tolerance: one locked file must not strand the rest of
      // the batch halfway with a single opaque error.
      final beforeIds = (await StorageService.instance.getTrashItems())
          .map((t) => t.id)
          .toSet();
      final failures = <String>[];
      for (final p in paths) {
        try {
          await StorageService.instance.moveToTrash(joinNative(_root, p));
        } catch (e) {
          failures.add('${p.split('/').last}: $e');
        }
      }
      final movedPaths = {
        for (final p in paths)
          if (!failures.any((f) => f.startsWith('${p.split('/').last}:')))
            joinNative(_root, p),
      };
      if (failures.isNotEmpty) {
        _showError(
          'Could not move ${failures.length} of ${paths.length} items to Recycle Bin:\n${failures.take(5).join('\n')}',
        );
      }
      if (!mounted) return;
      _clearSelection();
      _load();
      if (movedPaths.isNotEmpty) {
        // Identify the trash entries this batch just created so Undo
        // restores exactly those — never older items.
        final newIds = (await StorageService.instance.getTrashItems())
            .where((t) =>
                !beforeIds.contains(t.id) &&
                movedPaths.contains(t.originalPath))
            .map((t) => t.id)
            .toList();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Moved ${movedPaths.length} item${movedPaths.length == 1 ? '' : 's'} to Recycle Bin',
            ),
            action: newIds.isEmpty
                ? null
                : SnackBarAction(
                    label: 'Undo',
                    onPressed: () async {
                      for (final id in newIds) {
                        try {
                          await StorageService.instance.restoreTrashItem(id);
                        } catch (_) {}
                      }
                      if (!mounted) return;
                      _load(refresh: true);
                    },
                  ),
          ),
        );
      }
    } else if (confirm == 'permanent') {
      try {
        Future<String> startTask() =>
            TaskService.instance.delete(root: _root, paths: paths);
        final taskId = await startTask();
        if (!mounted) return;
        final done = await TaskProgressDialog.show(context, taskId, 'Deleting…', onRetry: startTask);
        if (!mounted) return;
        _clearSelection();
        _load(refresh: true);
        if (done == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Deleted $count item${count == 1 ? '' : 's'}',
              ),
            ),
          );
        }
      } catch (e) {
        _showError('Delete failed: $e');
      }
    }
  }

  Future<void> _renameSelected() async {
    if (_selectedPaths.length != 1) return;
    await _renamePath(_selectedPaths.first);
  }

  /// Properties for the single selected entry, so the action bar exposes the
  /// same dialog as the context menu.
  void _showSelectedInfo() {
    if (_selectedPaths.length != 1) return;
    final path = _selectedPaths.first;
    final item = _entries.where((e) => _fullEntryPath(e) == path).firstOrNull;
    if (item == null) return;
    _showFileInfo(item);
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
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Rename'),
              ),
            ),
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
        _load(refresh: true);
      } catch (e) {
        _showError('Rename failed: $e');
      }
    }
  }

  Future<void> _compressSelected() async {
    // One folder or file compresses to "<name>.zip"; a multi-selection keeps
    // the generic name. Saves retyping the obvious case.
    String defaultName = 'archive.zip';
    if (_selectedPaths.length == 1) {
      final only = _selectedPaths.first.split('/').last;
      if (only.isNotEmpty) defaultName = '$only.zip';
    }
    final ctrl = TextEditingController(text: defaultName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: defaultName.length - 4);
    final String? zipName;
    try {
      zipName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compress to ZIP'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Archive Name', border: OutlineInputBorder()),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                Navigator.of(ctx).pop(v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Compress'),
              ),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (zipName != null && zipName.isNotEmpty) {
      final dstPath = joinNative(_root, _relPath.isEmpty ? zipName : '$_relPath/$zipName');
      try {
        Future<String> startTask() => TaskService.instance.compress(
              srcRoot: _root,
              srcPaths: _selectedPaths.toList(),
              dstArchivePath: dstPath,
            );
        final taskId = await startTask();
        if (!mounted) return;
        await TaskProgressDialog.show(context, taskId, 'Compressing…', onRetry: startTask);
        if (!mounted) return;
        _clearSelection();
        _load(refresh: true);
      } catch (e) {
        _showError('Compress failed: $e');
      }
    }
  }

  Future<void> _extractArchive(EntryItem item) async {
    final fullArchive = joinNative(_root, _fullEntryPath(item));
    final targetDir = joinNative(_root, _relPath);
    try {
      Future<String> startTask() => TaskService.instance.extract(
            archivePath: fullArchive,
            dstDir: targetDir,
          );
      final taskId = await startTask();
      if (!mounted) return;
      await TaskProgressDialog.show(context, taskId, 'Extracting Archive…', onRetry: startTask);
      if (mounted) _load(refresh: true);
    } catch (e) {
      _showError('Extract failed: $e');
    }
  }

  Future<void> _bookmarkCurrentFolder() =>
      _addBookmark(root: _root, path: _relPath);

  /// Bookmarks a folder row from the context menus.
  Future<void> _bookmarkFolder(EntryItem item) =>
      _addBookmark(root: _root, path: _fullEntryPath(item));

  Future<void> _addBookmark({required String root, required String path}) async {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty
        ? (root.split('/').last.isEmpty ? 'Root' : root.split('/').last)
        : segments.last;
    final bookmarks = await StorageService.instance.getBookmarks();
    final exists = bookmarks.any((b) => b.root == root && b.path == path);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" is already bookmarked')),
        );
      }
      return;
    }
    await StorageService.instance.addBookmark(name: name, root: root, path: path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bookmarked "$name"')),
      );
    }
  }

  /// Walks a folder to total its files. Bounded so a huge tree cannot freeze
  /// the dialog; the count is marked approximate when the cap is hit.
  Future<String> _measureDirectory(String path) async {
    var total = 0;
    var count = 0;
    var capped = false;
    Future<void> walk(Directory dir, int depth) async {
      if (capped || depth > 12) return;
      List<FileSystemEntity> items;
      try {
        items = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      for (final entity in items) {
        if (capped) return;
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
          if (++count >= 20000) {
            capped = true;
            return;
          }
        } else if (entity is Directory) {
          await walk(entity, depth + 1);
        }
      }
    }

    try {
      await walk(Directory(path), 0);
    } catch (_) {
      return 'Directory';
    }
    if (count == 0) return 'Directory (empty)';
    final size = EntryItem(
      EntryDto(
        name: '',
        path: '',
        isDir: false,
        hidden: false,
        isSymlink: false,
        size: BigInt.from(total),
      ),
    ).formattedSize;
    return '$size${capped ? '+' : ''} ($count${capped ? '+' : ''} files)';
  }

  Future<void> _showFileInfo(EntryItem item) async {
    final path = _fullEntryPath(item);
    // Directories report no size from the backend; measure them on demand so
    // Properties is not just "Directory" for every folder.
    String? dirSize;
    if (item.isDir && isNativeRoot(_root)) {
      dirSize = await _measureDirectory(joinNative(_root, path));
      if (!mounted) return;
    }
    final fullPath = isNativeRoot(_root)
        ? joinNative(_root, path)
        : '$_root/$path';
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Name', item.name),
              _infoRow('Path', fullPath),
              if (ext != null) _infoRow('Extension', ext.toUpperCase()),
              _infoRow(
                'Size',
                item.isDir
                    ? (dirSize ?? 'Directory')
                    : '${item.formattedSize}${item.size != null ? " (${item.size} bytes)" : ""}',
              ),
              _infoRow('Modified', item.formattedModified),
              _infoRow('Type', item.isDir ? 'Directory' : (item.isArchive ? 'Archive' : 'File')),
              _infoRow('Hidden', item.hidden ? 'Yes' : 'No'),
              if (item.isSymlink) _infoRow('Symlink', 'Yes'),
            ],
          ),
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Path'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullPath));
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

  /// Visible entries: hidden/filter applied to the loaded pages.
  ///
  /// Sorting is NOT done here anymore — the Rust side sorts the full folder
  /// before paging. Sorting locally used to order only the pages fetched so
  /// far, so "largest file" in a big folder was just the largest of the
  /// first hundred.
  // Memoized: this getter is consulted many times per build (list,
  // grid, counts, menus), and on a huge directory each uncached pass
  // lowercases every file name again — the main source of typing jank
  // in big folders. The key covers every input the filter reads:
  // entries are only ever replaced wholesale or appended to, never
  // mutated in place.
  List<EntryItem>? _filteredCache;
  Object? _filteredCacheEntries;
  int _filteredCacheLength = -1;
  String _filteredCacheQuery = '';
  bool _filteredCacheShowHidden = false;
  BigInt _cachedTotalListedBytes = BigInt.zero;

  List<EntryItem> get _filteredAndSortedEntries {
    final cached = _filteredCache;
    if (cached != null &&
        identical(_filteredCacheEntries, _entries) &&
        _filteredCacheLength == _entries.length &&
        _filteredCacheQuery == _filterQuery &&
        _filteredCacheShowHidden == _showHidden) {
      return cached;
    }
    final query = _filterQuery.toLowerCase();
    BigInt totalBytes = BigInt.zero;
    final result = _entries.where((e) {
      if (!_showHidden && e.hidden) return false;
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) {
        return false;
      }
      if (!e.isDir && e.size != null) {
        totalBytes += e.size!;
      }
      return true;
    }).toList();
    _filteredCache = result;
    _filteredCacheEntries = _entries;
    _filteredCacheLength = _entries.length;
    _filteredCacheQuery = _filterQuery;
    _filteredCacheShowHidden = _showHidden;
    _cachedTotalListedBytes = totalBytes;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_splitActive) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          leading: IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Exit split view',
            onPressed: _toggleSplit,
          ),
          title: const Text('Split view', style: TextStyle(fontSize: 14)),
        ),
        body: LayoutBuilder(
          builder: (ctx, constraints) {
            final panes = <Widget>[
              Expanded(child: _splitPaneA!),
              if (constraints.maxWidth >= 720)
                const VerticalDivider(width: 1)
              else
                const Divider(height: 1),
              Expanded(child: _splitPaneB!),
            ];
            return constraints.maxWidth >= 720
                ? Row(children: panes)
                : Column(children: panes);
          },
        ),
      );
    }

    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();

    // Back first leaves selection/search/address, then walks up the directory tree.
    // At the top level the platform handles it (exit or tab switch).
    final canNavigateUp = _isSelecting || _isSearching || _isEditingAddress || _relPath.isNotEmpty ||
        _root.startsWith('archive://') || (_root.startsWith('/') && _root != '/');

    return _withDropTarget(CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Shortcuts sit above the address and search fields, so they must not
        // fire while one of them has the keyboard: Cmd+A has to select the
        // field text, not every file. The guards live in the handlers.
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          if (!_isTyping) _selectAll();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
          if (!_isTyping) _selectAll();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): () {
          if (!_isTyping) _invertSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true, shift: true): () {
          if (!_isTyping) _invertSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          if (!_isTyping) _invertSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () {
          if (!_isTyping) _invertSelection();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => _isSearching = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _isSearching = true);
          _searchFocusNode.requestFocus();
        },
        // `/` is the muscle-memory filter key in most file managers.
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (_isTyping) return;
          setState(() => _isSearching = true);
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.isNotEmpty) {
            _copySelected(isCut: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.isNotEmpty) {
            _copySelected(isCut: false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.isNotEmpty && _canWrite) {
            _copySelected(isCut: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.isNotEmpty && _canWrite) {
            _copySelected(isCut: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
          if (!_isTyping && _clipboard != null && _canWrite) {
            _paste();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () {
          if (!_isTyping && _clipboard != null && _canWrite) {
            _paste();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.length == 1 && _canWrite) {
            final item = _entries.firstWhere(
              (e) => _fullEntryPath(e) == _selectedPaths.first,
              orElse: () => _entries.first,
            );
            _duplicateEntry(item);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.length == 1 && _canWrite) {
            final item = _entries.firstWhere(
              (e) => _fullEntryPath(e) == _selectedPaths.first,
              orElse: () => _entries.first,
            );
            _duplicateEntry(item);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (_isSelecting && _selectedPaths.length == 1 && _canWrite) {
            _renameSelected();
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete, shift: true): () {
          if (!_isTyping && _isSelecting && _canWrite) {
            _deleteSelected(permanent: true);
          }
        },
        // The Mac "delete" key reports backspace, so Shift+Delete has to be
        // matched on backspace there; otherwise permanent delete is unreachable.
        const SingleActivator(LogicalKeyboardKey.backspace, shift: true): () {
          if (!_isTyping && Platform.isMacOS && _isSelecting && _canWrite) {
            _deleteSelected(permanent: true);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () {
          setState(() => _isGrid = !_isGrid);
          _saveViewPreferences();
        },
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () {
          setState(() => _isGrid = !_isGrid);
          _saveViewPreferences();
        },
        const SingleActivator(LogicalKeyboardKey.f5): () => _load(refresh: true),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => _load(refresh: true),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => _load(refresh: true),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          setState(() => _showHidden = !_showHidden);
          _saveViewPreferences();
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
          _addressController.text = _displayFullPath;
          setState(() => _isEditingAddress = true);
        },
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () {
          _addressController.text = _displayFullPath;
          setState(() => _isEditingAddress = true);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isSelecting) {
            _clearSelection();
          } else if (_isSearching) {
            setState(() {
              _isSearching = false;
              _filterQuery = '';
              _searchController.clear();
              _searchResults = [];
              _searchBusy = false;
            });
          } else if (_isEditingAddress) {
            setState(() => _isEditingAddress = false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (!_isTyping && _isSelecting && _canWrite) {
            _deleteSelected();
          }
        },
        const SingleActivator(LogicalKeyboardKey.backspace): () {
          // On a Mac keyboard "delete" reports backspace. With files selected
          // it has to delete them; navigating up left the folder instead.
          // Elsewhere Backspace keeps its Explorer-style "go up" meaning.
          if (_isTyping) return;
          if (Platform.isMacOS && _isSelecting && _canWrite) {
            _deleteSelected();
          } else if (!_isSearching) {
            _navigateUp();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _navigateUp,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _goBack,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _goForward,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _selectAdjacent(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _selectAdjacent(-1),
        const SingleActivator(LogicalKeyboardKey.home): () => _selectBoundary(true),
        const SingleActivator(LogicalKeyboardKey.end): () => _selectBoundary(false),
        // Enter opens the single selected entry, like every desktop file list.
        const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _openSelected,
      },
      child: Listener(
        // Mouse back/forward side buttons, like a desktop file manager.
        onPointerDown: (event) {
          if (event.buttons == kBackMouseButton) {
            _goBack();
          } else if (event.buttons == kForwardMouseButton) {
            _goForward();
          }
        },
        child: Focus(
        autofocus: true,
        child: PopScope(
      canPop: widget.embedded || !canNavigateUp,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || widget.embedded) return;
        if (_isSelecting) {
          _clearSelection();
        } else if (_isSearching) {
          setState(() {
            _isSearching = false;
            _filterQuery = '';
            _searchController.clear();
            _searchResults = [];
            _searchBusy = false;
          });
        } else if (_isEditingAddress) {
          setState(() => _isEditingAddress = false);
        } else {
          _navigateUp();
        }
      },
      child: Scaffold(
      appBar: PreferencesService.toolbarAtBottom.value ? null : AppBar(
        titleSpacing: MediaQuery.sizeOf(context).width < 600 ? 10 : 4,
        toolbarHeight: MediaQuery.sizeOf(context).width < 600 ? 40 : 46,
        automaticallyImplyLeading: false,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                tooltip: 'Cancel selection (Esc)',
                onPressed: _clearSelection,
              )
            : (MediaQuery.sizeOf(context).width >= 600 && !widget.embedded && Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: 'Back to previous page',
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null),
        title: _toolbarContent(segments),
      ),
      bottomNavigationBar:
          PreferencesService.toolbarAtBottom.value ? _buildBottomToolbar(segments) : null,
      floatingActionButton: _showScrollToTop
          ? FloatingActionButton.small(
              heroTag: 'browser_scroll_to_top',
              onPressed: () {
                HapticFeedback.lightImpact();
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                );
              },
              tooltip: 'Back to top',
              child: const Icon(Icons.arrow_upward, size: 18),
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          _swipeStartX = details.globalPosition.dx;
          _swipeDeltaX = 0;
        },
        onHorizontalDragUpdate: (details) {
          _swipeDeltaX = details.globalPosition.dx - _swipeStartX;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          final fromLeftEdge = _swipeStartX < 140;
          if (fromLeftEdge && (_swipeDeltaX > 35 || (velocity > 260 && _swipeDeltaX > 20))) {
            _handleSwipeBack();
          } else if ((velocity < -260 && _swipeDeltaX < -25) && _forwardStack.isNotEmpty) {
            _goForward();
          }
          _swipeStartX = 0;
          _swipeDeltaX = 0;
        },
        onHorizontalDragCancel: () {
          _swipeStartX = 0;
          _swipeDeltaX = 0;
        },
        child: Column(
          children: [
            // A refresh keeps the list, so it needs its own progress line —
            // otherwise F5 and pull-to-refresh look like a no-op.
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            _buildCapabilitiesBar(),
            Expanded(child: _buildBody()),
            if (_isSelecting || _clipboard != null) _buildBottomActionBar(),
          ],
        ),
      ),
      ),
    ),
    ),
    ),
    ),
    );
  }

  Widget _toolbarContent(List<String> segments) {
    // Icons sit flush right; the address bar stays pinned left at a fixed
    // width so the two regions do not trade space as the window resizes.
    final actions = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(mainAxisSize: MainAxisSize.min, children: _toolbarActions()),
    );
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    // The search field, selection summary, or narrow phone screens need the whole bar.
    if (_isSearching || _isSelecting || isCompact) {
      return Row(
        children: [
          Expanded(child: _buildToolbarTitle(segments)),
          const SizedBox(width: 4),
          actions,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // On desktop, the address bar keeps a stable width; the icon row scrolls
        // once the window is too narrow to fit every action.
        final addressWidth = (constraints.maxWidth * 0.45).clamp(200.0, 420.0);
        return Row(
          children: [
            SizedBox(width: addressWidth, child: _buildToolbarTitle(segments)),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbarTitle(List<String> segments) {
    return _isSearching
        ? TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search files & subfolders…',
              border: InputBorder.none,
              suffixIcon: _filterQuery.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _filterQuery.trim().length >= 2 ? '${_searchResults.length} found' : '${_filteredAndSortedEntries.length}/${_entries.where((e) => _showHidden || !e.hidden).length}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          onPressed: _clearSearch,
                        ),
                      ],
                    )
                  : null,
            ),
            onChanged: _onFilterChanged,
          )
        : (_isSelecting
            ? Text(
                _selectedSummary,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              )
            : _buildUnifiedAddressBar(segments));
  }

  void _showSortBottomSheet() {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isZh ? '排序方式' : 'Sort By',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        icon: Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                        label: Text(_sortAsc ? (isZh ? '升序' : 'Ascending') : (isZh ? '降序' : 'Descending')),
                        onPressed: () {
                          setState(() => _sortAsc = !_sortAsc);
                          setModalState(() {});
                          _saveViewPreferences();
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
                for (final field in SortField.values)
                  ListTile(
                    leading: Icon(
                      _sortField == field ? Icons.check : null,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                    title: Text(
                      isZh
                          ? (field == SortField.name
                              ? '按名称'
                              : field == SortField.size
                                  ? '按大小'
                                  : field == SortField.modified
                                      ? '按修改日期'
                                      : '按文件类型')
                          : field.label,
                    ),
                    trailing: _sortField == field
                        ? Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16)
                        : null,
                    onTap: () {
                      setState(() {
                        if (_sortField == field) {
                          _sortAsc = !_sortAsc;
                        } else {
                          _sortField = field;
                          _sortAsc = field == SortField.name || field == SortField.type;
                        }
                      });
                      _saveViewPreferences();
                      _load();
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _toolbarActions() {
    // Phones get a tighter bar so more icons fit before scrolling.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
      // `shrinkWrap` drops the 48px Material tap-target box, which otherwise
      // leaves a wide gap between neighbouring icons.
      return IconButton(
        icon: Icon(icon, size: compact ? 18 : 20),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: compact ? 28 : 30, height: compact ? 28 : 30),
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        tooltip: tooltip,
        onPressed: onPressed,
      );
    }

    if (_isSelecting) {
      return [
        action(Icons.select_all, isZh ? '全选' : 'Select All (Ctrl+A)', _selectAll),
        action(Icons.swap_horiz, isZh ? '反选' : 'Invert Selection (Ctrl+Shift+A)', _invertSelection),
      ];
    }

    return [
      // Upload lived only in the empty-space right-click menu, so a full
      // list (no blank area to click) had no discoverable way in at all.
      // Phones get it from the overflow menu to keep the icon row narrow.
      if (_canWrite && !compact)
        action(Icons.cloud_upload_outlined, isZh ? '上传文件' : 'Upload files', _uploadFiles),
      if (!compact) ...[
        action(
          _isSearching ? Icons.search_off : Icons.search,
          'Search',
          () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _filterQuery = '';
                _searchController.clear();
                _searchResults = [];
                _searchBusy = false;
              }
            });
          },
        ),
        if (!widget.embedded)
          action(Icons.vertical_split, 'Split view', _toggleSplit),
        action(
          _isGrid ? Icons.view_list : Icons.grid_view,
          _isGrid ? 'List view' : 'Grid view',
          () {
            setState(() => _isGrid = !_isGrid);
            _saveViewPreferences();
          },
        ),
        // Sorting lives one tap from the list instead of two menus deep.
        PopupMenuButton<SortField>(
          // The current order was only visible inside the opened menu, so the
          // button looked identical whatever the list was sorted by.
          tooltip: 'Sort: ${_sortField.label} ${_sortAsc ? '↑' : '↓'}',
          icon: Icon(Icons.sort, size: compact ? 18 : 20),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            fixedSize: Size.square(compact ? 28 : 30),
          ),
          onSelected: (field) {
            setState(() {
              if (_sortField == field) {
                _sortAsc = !_sortAsc;
              } else {
                _sortField = field;
                _sortAsc = field == SortField.name || field == SortField.type;
              }
            });
            _saveViewPreferences();
            _load();
          },
          itemBuilder: (ctx) => [
            for (final field in SortField.values)
              CheckedPopupMenuItem<SortField>(
                value: field,
                checked: _sortField == field,
                child: Text(
                  '${field.label}'
                  '${_sortField == field ? (_sortAsc ? '  ↑' : '  ↓') : ''}',
                ),
              ),
          ],
        ),
      ],
      if (Navigator.of(context).canPop())
        action(
          Icons.home_outlined,
          isZh ? '返回主页' : 'Home Dashboard',
          () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      PopupMenuButton<String>(
        tooltip: isZh ? '更多选项' : 'Options',
        icon: Icon(Icons.more_vert, size: compact ? 18 : 20),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          fixedSize: Size.square(compact ? 28 : 30),
        ),
        onSelected: (val) {
          if (val == 'search') {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _filterQuery = '';
                _searchController.clear();
                _searchResults = [];
                _searchBusy = false;
              }
            });
          } else if (val == 'toggle_view') {
            setState(() => _isGrid = !_isGrid);
            _saveViewPreferences();
          } else if (val == 'sort') {
            _showSortBottomSheet();
          } else if (val == 'split') {
            _toggleSplit();
          } else if (val == 'select') {
            setState(() => _isSelecting = true);
          } else if (val == 'toggle_hidden') {
            setState(() => _showHidden = !_showHidden);
            _saveViewPreferences();
          } else if (val == 'upload') {
            _uploadFiles();
          } else if (val == 'new_folder') {
            _createFolder();
          }
        },
        itemBuilder: (ctx) => [
          // File-creation actions were only in the empty-space context menu,
          // which a full list never shows.
          if (_canWrite) ...[
            PopupMenuItem<String>(
              value: 'upload',
              child: Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(isZh ? '上传文件' : 'Upload files'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'new_folder',
              child: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(isZh ? '新建文件夹' : 'New folder'),
                ],
              ),
            ),
            const PopupMenuDivider(),
          ],
          if (compact) ...[
            PopupMenuItem<String>(
              value: 'search',
              child: Row(
                children: [
                  Icon(_isSearching ? Icons.search_off : Icons.search, size: 18),
                  const SizedBox(width: 8),
                  Text(_isSearching ? (isZh ? '关闭搜索' : 'Close search') : (isZh ? '搜索文件' : 'Search files')),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_view',
              child: Row(
                children: [
                  Icon(_isGrid ? Icons.view_list : Icons.grid_view, size: 18),
                  const SizedBox(width: 8),
                  Text(_isGrid ? (isZh ? '切换为列表视图' : 'Switch to List') : (isZh ? '切换为网格视图' : 'Switch to Grid')),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'sort',
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 8),
                  Text(isZh ? '文件排序方式…' : 'Sort by…'),
                ],
              ),
            ),
            if (!widget.embedded)
              PopupMenuItem<String>(
                value: 'split',
                child: Row(
                  children: [
                    const Icon(Icons.vertical_split, size: 18),
                    const SizedBox(width: 8),
                    Text(isZh ? '分屏浏览' : 'Split view'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
          ],
          PopupMenuItem<String>(
            value: 'select',
            child: Row(
              children: [
                const Icon(Icons.checklist, size: 18),
                const SizedBox(width: 8),
                Text(isZh ? '多选模式' : 'Select items'),
              ],
            ),
          ),
          CheckedPopupMenuItem<String>(
            value: 'toggle_hidden',
            checked: _showHidden,
            child: Text(isZh ? '显示隐藏文件' : 'Show hidden files'),
          ),
        ],
      ),
    ];
  }

  /// Same bar under the list when the user pins the toolbar to the bottom.
  ///
  /// A plain [AppBar] misbehaves down here: it reserves top-only padding and
  /// assumes it owns the whole width, so the address bar and the icon strip
  /// overlap the home indicator. A [Material] row inside [SafeArea] keeps the
  /// same content without those assumptions.
  PreferredSizeWidget _buildBottomToolbar(List<String> segments) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PreferredSize(
      preferredSize: Size.fromHeight(compact ? 40 : 46),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: compact ? 40 : 46,
            child: Row(
              children: [
                const SizedBox(width: 4),
                if (_isSelecting)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: 'Cancel selection (Esc)',
                    onPressed: _clearSelection,
                  )
                // Embedded split panes have no route of their own to pop;
                // without this guard each pane grew its own back arrow that
                // closed the whole split view.
                else if (!compact &&
                    !widget.embedded &&
                    Navigator.of(context).canPop())
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: 'Back to previous page',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                Expanded(child: _toolbarContent(segments)),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedAddressBar(List<String> segments) {
    if (_isEditingAddress) {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.link, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _addressController,
                autofocus: true,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Enter path to jump...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onSubmitted: _jumpToAddress,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 16, color: Colors.blue),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Jump',
              onPressed: () => _jumpToAddress(_addressController.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Cancel',
              onPressed: () => setState(() => _isEditingAddress = false),
            ),
          ],
        ),
      );
    }

    String rootLabel;
    if (_root == '/') {
      rootLabel = '/';
    } else if (_root.startsWith('remote://')) {
      final remoteId = _root.substring('remote://'.length);
      final remote = _findRemote(remoteId);
      rootLabel = remote != null ? '☁️ ${remote.name}' : 'Remote';
    } else if (_root.startsWith('archive://')) {
      rootLabel = 'Archive';
    } else {
      rootLabel = _root.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? _root;
    }

    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: AppUiTokens.borderRadiusMd,
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          if (!isCompact) ...[
            // Chevrons, not arrows: the plain arrow at the far left of the
            // bar leaves the page, this one only walks folder history.
            AppIconButton(
              icon: Icons.chevron_left,
              size: 28,
              iconSize: 16,
              tooltip: 'Back in history (Alt+←)',
              onPressed: _backStack.isEmpty ? null : _goBack,
            ),
            AppIconButton(
              icon: Icons.chevron_right,
              size: 28,
              iconSize: 16,
              tooltip: 'Forward in history (Alt+→)',
              onPressed: _forwardStack.isEmpty ? null : _goForward,
            ),
          ],
          if (!isCompact || _canNavigateUp)
            AppIconButton(
              icon: Icons.arrow_upward,
              size: 28,
              iconSize: 16,
              tooltip: 'Up one level',
              onPressed: _canNavigateUp ? _navigateUp : null,
            ),
          if (!isCompact)
            AppIconButton(
              icon: Icons.refresh,
              size: 28,
              iconSize: 16,
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          if (!isCompact || _canNavigateUp)
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          Expanded(
            // Reversed so a deep path opens scrolled to the current folder
            // instead of the drive root; the crumb order still reads normally.
            child: SingleChildScrollView(
              reverse: true,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  DragTarget<({String root, List<String> paths})>(
                    onAcceptWithDetails: (d) => _acceptDrop(d.data, ''),
                    builder: (ctx, candidate, rejected) => InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      if (_relPath.isNotEmpty) {
                        _pushHistory();
                        setState(() => _relPath = '');
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                        _load();
                      }
                    },
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: _root));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied path: $_root')),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        rootLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: _relPath.isEmpty ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                          fontWeight: _relPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    ),
                  ),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                    DragTarget<({String root, List<String> paths})>(
                      onAcceptWithDetails: (d) =>
                          _acceptDrop(d.data, segments.sublist(0, i + 1).join('/')),
                      builder: (ctx, candidate, rejected) => InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        final next = segments.sublist(0, i + 1).join('/');
                        if (next != _relPath) {
                          _pushHistory();
                          setState(() => _relPath = next);
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                          _load();
                        }
                      },
                      onLongPress: () {
                        final next = segments.sublist(0, i + 1).join('/');
                        final full = isNativeRoot(_root) ? joinNative(_root, next) : '$_root/$next';
                        Clipboard.setData(ClipboardData(text: full));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied path: $full')),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          segments[i],
                          style: TextStyle(
                            fontSize: 12,
                            color: i == segments.length - 1 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                            fontWeight: i == segments.length - 1 ? FontWeight.bold : FontWeight.normal,
                          ),
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
            icon: const Icon(Icons.edit_outlined, size: 15),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Edit address (Cmd/Ctrl+L)',
            onPressed: () {
              _addressController.text = _displayFullPath;
              setState(() => _isEditingAddress = true);
            },
          ),
        ],
      ),
    );
  }

  /// Bytes of the files currently listed; folders are skipped because their
  /// size is unknown until they are walked.
  int _selectedCacheCount = -1;
  int _selectedCacheEntriesLen = -1;
  BigInt _selectedBytesCache = BigInt.zero;

  BigInt get _selectedBytes {
    if (_selectedPaths.isEmpty) return BigInt.zero;
    if (_selectedCacheCount == _selectedPaths.length &&
        _selectedCacheEntriesLen == _entries.length) {
      return _selectedBytesCache;
    }
    var total = BigInt.zero;
    for (final e in _entries) {
      if (_selectedPaths.contains(_fullEntryPath(e)) && !e.isDir && e.size != null) {
        total += e.size!;
      }
    }
    _selectedCacheCount = _selectedPaths.length;
    _selectedCacheEntriesLen = _entries.length;
    _selectedBytesCache = total;
    return total;
  }

  BigInt get _totalListedBytes {
    // Reading _filteredAndSortedEntries warms _cachedTotalListedBytes
    _filteredAndSortedEntries;
    return _cachedTotalListedBytes;
  }

  String _formatBytes(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildCapabilitiesBar() {
    final caps = _capabilities;
    if (caps == null) return const SizedBox.shrink();
    // Clicking the item count opens search directly.
    void openSearch() {
      if (!_isSearching) {
        setState(() => _isSearching = true);
        _searchFocusNode.requestFocus();
      }
    }
    // On a phone the capability chips take more room than the item count they
    // sit next to, so the row keeps only the counts there.
    final showCaps = MediaQuery.sizeOf(context).width >= 600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: Row(
        children: [
          if (showCaps) ...[
            Text('Capabilities: ', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            _capChip('read', caps.read),
            _capChip('write', caps.write),
            _capChip('rename', caps.rename),
            _capChip('copy', caps.copy),
            _capChip('mkdir', caps.mkdir),
            _capChip('remove', caps.remove),
          ],
          const Spacer(),
          InkWell(
            onTap: openSearch,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                _filterQuery.isNotEmpty
                    ? '${_filteredAndSortedEntries.length} of ${_entries.where((e) => _showHidden || !e.hidden).length} items'
                    : '${_filteredAndSortedEntries.length} items'
                '${_totalListedBytes > BigInt.zero ? '  •  ${_formatBytes(_totalListedBytes)}' : ''}'
                '${!_showHidden && _entries.any((e) => e.hidden) ? '  •  hidden files off' : ''}'
                '${_hasMore ? ' (more below)' : ''}',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
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
          fontSize: 10,
          color: enabled ? Colors.green.shade700 : Colors.grey,
          fontWeight: enabled ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    final selectionSize = _selectedBytes;
    final selectionLabel = selectionSize > BigInt.zero
        ? '${_selectedPaths.length} selected (${_formatBytes(selectionSize)})'
        : '${_selectedPaths.length} selected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  selectionLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              _actionButton(Icons.copy, 'Copy', () => _copySelected(isCut: false)),
              if (_canWrite) ...[
                _actionButton(Icons.cut, 'Cut', () => _copySelected(isCut: true)),
                _actionButton(Icons.delete, 'Delete', _deleteSelected, color: Colors.red),
                if (_selectedPaths.length == 1)
                  _actionButton(Icons.edit, 'Rename', _renameSelected),
                if (_selectedPaths.length == 1)
                  _actionButton(Icons.info_outline, 'Info', _showSelectedInfo),
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
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildItemNameText(
    String name,
    TextStyle baseStyle, {
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    final query = _filterQuery.trim();
    if (query.isEmpty) {
      return Text(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: baseStyle,
      );
    }

    final lowerName = name.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    final highlightColor = Theme.of(context).colorScheme.primary;
    var start = 0;

    while (start < name.length) {
      final matchIdx = lowerName.indexOf(lowerQuery, start);
      if (matchIdx == -1) {
        spans.add(TextSpan(text: name.substring(start)));
        break;
      }
      if (matchIdx > start) {
        spans.add(TextSpan(text: name.substring(start, matchIdx)));
      }
      spans.add(
        TextSpan(
          text: name.substring(matchIdx, matchIdx + query.length),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: highlightColor,
            backgroundColor: highlightColor.withValues(alpha: 0.18),
          ),
        ),
      );
      start = matchIdx + query.length;
    }

    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
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
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  if (_canNavigateUp)
                    OutlinedButton.icon(
                      onPressed: _navigateUp,
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('Go up'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Recursive search results take over the body while a 2+ character
    // query is active.
    if (_isSearching && _filterQuery.trim().length >= 2) {
      return _buildSearchResults();
    }

    final list = _filteredAndSortedEntries;
    if (list.isEmpty) {
      final isFiltered = _filterQuery.isNotEmpty;
      return RefreshIndicator(
        onRefresh: () async => _load(refresh: true),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
                onLongPressStart: (details) => _showBackgroundContextMenu(details.globalPosition),
                // Tap empty space to leave selection mode, like the platform file managers.
                onTap: _isSelecting ? _clearSelection : null,
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
                            : (_entries.isNotEmpty && !_showHidden)
                                ? 'Only hidden files here'
                                : 'Directory is empty',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (isFiltered) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear Filter'),
                          onPressed: () {
                            // Leaving `_isSearching` on kept an empty search
                            // box open after the filter it belonged to was gone.
                            setState(() {
                              _filterQuery = '';
                              _searchController.clear();
                              _searchResults = [];
                              _searchBusy = false;
                              _isSearching = false;
                            });
                          },
                        ),
                      ] else if (_entries.isNotEmpty && !_showHidden) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.visibility, size: 16),
                          label: const Text('Show Hidden Files'),
                          onPressed: () {
                            setState(() => _showHidden = true);
                            _saveViewPreferences();
                          },
                        ),
                      ] else if (_canWrite) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.create_new_folder),
                              label: const Text('New Folder'),
                              onPressed: _createFolder,
                            ),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.note_add_outlined),
                              label: const Text('New File'),
                              onPressed: _createFile,
                            ),
                            if (_canNavigateUp)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_upward, size: 16),
                                label: const Text('Go Up'),
                                onPressed: _navigateUp,
                              ),
                          ],
                        ),
                      ] else if (_canNavigateUp) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: const Text('Go Up'),
                          onPressed: _navigateUp,
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
        onRefresh: () async => _load(refresh: true),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
          onLongPressStart: (details) => _showBackgroundContextMenu(details.globalPosition),
                // Tap empty space to leave selection mode, like the platform file managers.
                onTap: _isSelecting ? _clearSelection : null,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              _gridWidth = constraints.maxWidth;
              return Stack(
                children: [
                  GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 88,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.85,
          ),
          itemCount: list.length + (_hasMore ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i == list.length) {
              return Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        tooltip: 'Load more',
                        onPressed: _loadMore,
                      ),
              );
            }
            final item = list[i];
            final path = _fullEntryPath(item);
            final isSelected = _selectedPaths.contains(path);

            return KeyedSubtree(
              key: ValueKey(path),
              child: _draggableTile(
                item: item,
                path: path,
                child: GestureDetector(
              onSecondaryTapDown: (details) {
                _lastItemSecondaryTap = DateTime.now();
                if (Platform.isIOS || Platform.isAndroid) {
                  _showEntryActions(item);
                } else {
                  _showContextMenu(context, details.globalPosition, item);
                }
              },
              child: InkWell(
                onTap: () => _handleTileTap(item, i),
                onLongPress: () => _showEntryActions(item),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor.withValues(alpha: 0.25),
                      width: isSelected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (item.isImage || item.isVideo)
                              EntryThumbnail(
                                root: _root,
                                relPath: _fullEntryPath(item),
                                item: item,
                                size: 52,
                              )
                            else
                              Icon(item.icon, size: 28, color: item.iconColor(ctx)),
                            const SizedBox(height: 4),
                            _buildItemNameText(
                              item.name,
                              TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 1),
                            Text(item.formattedSize, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (item.isSymlink)
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Icon(Icons.link, size: 11, color: Colors.grey.shade600),
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
              ),
            ),
            );
          },
                  ),
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _lassoDown,
                      onPointerMove: _lassoMove,
                      onPointerUp: (_) => _lassoEnd(),
                      onPointerCancel: (_) => _lassoEnd(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  if (_lassoRect != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _LassoPainter(
                            _lassoRect!,
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _load(refresh: true),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) => _showBackgroundContextMenu(details.globalPosition),
        onLongPressStart: (details) => _showBackgroundContextMenu(details.globalPosition),
                // Tap empty space to leave selection mode, like the platform file managers.
                onTap: _isSelecting ? _clearSelection : null,
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

          return KeyedSubtree(
            key: ValueKey(path),
            child: _draggableTile(
              item: item,
              path: path,
              child: GestureDetector(
              onSecondaryTapDown: (details) {
                _lastItemSecondaryTap = DateTime.now();
                if (Platform.isIOS || Platform.isAndroid) {
                  _showEntryActions(item);
                } else {
                  _showContextMenu(context, details.globalPosition, item);
                }
              },
              child: ListTile(
                dense: true,
                visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                minVerticalPadding: 0,
                minLeadingWidth: 20,
                minTileHeight: 34,
                selected: isSelected,
                leading: _isSelecting
                    ? Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelect(path),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.isImage || item.isVideo)
                            EntryThumbnail(
                              root: _root,
                              relPath: path,
                              item: item,
                              size: 28,
                            )
                          else
                            Icon(item.icon, color: item.iconColor(ctx), size: 18),
                          if (item.isSymlink)
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Icon(Icons.link, size: 11, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                title: _buildItemNameText(
                  item.name,
                  TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                subtitle: Text(
                  item.isDir
                      ? item.formattedModified
                      : '${item.formattedSize}  •  ${item.formattedModified}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: item.isDir || item.isArchive ? const Icon(Icons.chevron_right, size: 14) : null,
                onTap: () => _handleTileTap(item, i),
                onLongPress: () => _showEntryActions(item),
              ),
              ),
            ),
          );
        },
      ),
    ),
    );
  }
}

/// The rubber-band rectangle drawn over the grid during lasso selection.
class _LassoPainter extends CustomPainter {
  final Rect rect;
  final Color color;

  const _LassoPainter(this.rect, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LassoPainter old) => old.rect != rect || old.color != color;
}
