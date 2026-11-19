import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/download_prompt_dialog.dart';
import '../dialogs/file_picker_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/error_text.dart';
import '../services/external_file_service.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/permission_service.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../widgets/browser/browser_action_sheets.dart';
import '../widgets/browser/browser_bottom_action_bar.dart';
import '../widgets/browser/browser_toolbar.dart';
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

  String localizedLabel(AppLocalizations l10n) => switch (this) {
        SortField.name => l10n.sortLabelName,
        SortField.size => l10n.sortLabelSize,
        SortField.modified => l10n.sortLabelDate,
        SortField.type => l10n.sortLabelType,
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

  /// When set, the browser acts as a file picker for another app's
  /// GET_CONTENT / PICK request: taps select instead of open, and the
  /// result is popped as a list of local paths.
  final ExternalPickRequest? pickRequest;

  const BrowserPage({
    super.key,
    required this.initialRoot,
    this.initialPath = '',
    this.embedded = false,
    this.onLocationChanged,
    this.pickRequest,
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
  String _cachedLastFilterQuery = '';
  String _cachedTrimmedFilterQuery = '';
  String _cachedLowerFilterQuery = '';

  String get _trimmedFilterQuery {
    if (_cachedLastFilterQuery != _filterQuery) {
      _cachedLastFilterQuery = _filterQuery;
      _cachedTrimmedFilterQuery = _filterQuery.trim();
      _cachedLowerFilterQuery = _cachedTrimmedFilterQuery.toLowerCase();
    }
    return _cachedTrimmedFilterQuery;
  }

  String get _lowerFilterQuery {
    if (_cachedLastFilterQuery != _filterQuery) {
      _cachedLastFilterQuery = _filterQuery;
      _cachedTrimmedFilterQuery = _filterQuery.trim();
      _cachedLowerFilterQuery = _cachedTrimmedFilterQuery.toLowerCase();
    }
    return _cachedLowerFilterQuery;
  }
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

  bool get _isAtMultiBucketRoot {
    if (_relPath.isNotEmpty && _relPath != '/') return false;
    if (!_root.startsWith('remote://')) return false;
    final remoteId = _root.substring('remote://'.length);
    final remote = _findRemote(remoteId);
    if (remote == null) return false;
    final k = remote.kind.toLowerCase();
    if (k == 's3' || k == 'oss') {
      return remote.bucket == null || remote.bucket!.trim().isEmpty;
    }
    return false;
  }

  // Multi-selection state
  bool _isSelecting = false;

  bool get _pickMode => widget.pickRequest != null;
  bool get _pickMultiple => widget.pickRequest?.allowMultiple ?? false;
  bool _applyMimeFilter = true;

  List<EntryItem> get _selectedItems => _entries
      .where((e) => _selectedPaths.contains(_fullEntryPath(e)) && (!_pickMode || !e.isDir))
      .toList();

  List<EntryItem> get _visibleSearchResults => (_pickMode && _applyMimeFilter)
      ? _searchResults
          .where((e) => e.isDir || widget.pickRequest!.matchesFileName(e.name))
          .toList()
      : _searchResults;

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
  double? _swipeDownX;
  double _swipeStartX = 0;
  double _swipeDeltaX = 0;

  String get _selectedSummary {
    final count = _selectedPaths.length;
    if (count == 0) return AppLocalizations.of(context).selectItems;
    final totalBytes = _selectedBytes;
    if (totalBytes > BigInt.zero) {
      return AppLocalizations.of(context)
          .selectedCountBytesLabel(count, _formatBytes(totalBytes));
    }
    return AppLocalizations.of(context).selectedCountLabel(count);
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
    _applyMimeFilter = widget.pickRequest?.hasTypeFilter ?? false;
    if (_pickMode) _clearPickCache();
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

  /// Bumped on every fresh _load (navigation, refresh, re-sort). Page
  /// appends capture it so a stale page request cannot land in a list that
  /// was reset in the meantime — the directory key alone is identical for
  /// a refresh of the same folder.
  int _loadEpoch = 0;
  DateTime? _lastItemSecondaryTap;

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final loadingFor = '$_root\u0000$_relPath';
    final epoch = _loadEpoch;
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
      if (_loadingFor == loadingFor && _loadEpoch == epoch) {
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
        _showError(AppLocalizations.of(context).couldNotLoadMore(_friendlyError(e)));
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
      HapticFeedback.lightImpact();
      _clearSelection();
      return;
    }
    if (_isSearching) {
      HapticFeedback.lightImpact();
      setState(() {
        _isSearching = false;
        _filterQuery = '';
        _searchController.clear();
        _searchResults = [];
        _searchBusy = false;
      });
      return;
    }
    if (_isEditingAddress) {
      HapticFeedback.lightImpact();
      setState(() => _isEditingAddress = false);
      return;
    }
    if (_backStack.isNotEmpty) {
      HapticFeedback.lightImpact();
      _goBack();
      return;
    }
    // Deep-linked into a subfolder with empty history: still walk up
    // instead of leaving the page outright.
    if (_canNavigateUp) {
      HapticFeedback.lightImpact();
      _navigateUp();
      return;
    }
    if (widget.embedded) return;
    if (Navigator.of(context).canPop()) {
      HapticFeedback.lightImpact();
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
    _loadEpoch++;
    // A pending debounce would otherwise run against the folder the user
    // just left and repopulate stale results.
    _searchDebounce?.cancel();
    _searchSeq++;
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
          _showError(AppLocalizations.of(context).refreshFailed(_friendlyError(e)));
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
    if (Platform.isAndroid) {
      // Only the emulated shared volume is browsable; its parents are not
      // listable by a normal app, so walking up there only shows an error.
      const top = '/storage/emulated/0';
      if (_root == top ||
          _root == '/' ||
          _root == '/sdcard' ||
          _root == '/storage' ||
          _root == '/storage/emulated') {
        return false;
      }
    }
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
    if (_pickMode && !item.isDir) {
      if (_pickMultiple) {
        _toggleSelect(_fullEntryPath(item));
      } else {
        _finishPick([item]);
      }
      return;
    }
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
      // The editor loads the whole file into memory (and the find index
      // roughly doubles it); multi-hundred-MB logs would OOM the app.
      const maxTextBytes = 20 * 1024 * 1024;
      if (item.size != null && item.size! > BigInt.from(maxTextBytes)) {
        _showError(
          '"${item.name}" is too large to edit (${item.formattedSize}). Open it with an external app instead.',
        );
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
      final l10n = AppLocalizations.of(context);
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        l10n.downloadingItem(item.name),
        onRetry: startTask,
      );
      if (completed != true || !mounted) return;

      final dstPath = dstDir.isEmpty ? name : '$dstDir/$name';
      await _openLocalCopy(destination.root, dstPath, item);
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).downloadFailed(e.toString()));
      }
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
      _showError(AppLocalizations.of(context).downloadedNoAppToOpen(item.name));
    } else if (result.type != ResultType.done) {
      _showError(result.message);
    }
  }

  /// Images in the current folder, for swiping inside the viewer.
  /// Native roots pass a local path per entry; remote and archive roots pass
  /// the VFS location, which the viewer exports lazily when each image is
  /// actually shown.
  (List<ImageViewerEntry>, int) _imageSiblings(EntryItem item) {
    final native = isNativeRoot(_root);
    if (native && _hasMore && _filterQuery.isEmpty) {
      try {
        final folderPath = _relPath.isEmpty ? _root : joinNative(_root, _relPath);
        final dir = Directory(folderPath);
        if (dir.existsSync()) {
          final files = dir.listSync(followLinks: false).whereType<File>().where((f) {
            final name = f.path.split(Platform.pathSeparator).last;
            if (name.startsWith('.')) return false;
            final dot = name.lastIndexOf('.');
            if (dot < 0 || dot == name.length - 1) return false;
            final ext = name.substring(dot + 1).toLowerCase();
            return EntryItem.isImageExtension(ext);
          }).toList();
          if (files.isNotEmpty) {
            if (_sortField == SortField.name) {
              files.sort((a, b) {
                final an = a.path.split(Platform.pathSeparator).last.toLowerCase();
                final bn = b.path.split(Platform.pathSeparator).last.toLowerCase();
                return _sortAsc ? an.compareTo(bn) : bn.compareTo(an);
              });
            } else if (_sortField == SortField.modified) {
              files.sort((a, b) {
                final am = a.statSync().modified;
                final bm = b.statSync().modified;
                return _sortAsc ? am.compareTo(bm) : bm.compareTo(am);
              });
            } else if (_sortField == SortField.size) {
              files.sort((a, b) {
                final as = a.statSync().size;
                final bs = b.statSync().size;
                return _sortAsc ? as.compareTo(bs) : bs.compareTo(as);
              });
            }
            final entries = files.map((f) {
              final name = f.path.split(Platform.pathSeparator).last;
              return ImageViewerEntry(
                name: name,
                localPath: f.path,
              );
            }).toList();
            final index = entries.indexWhere((e) => e.name == item.name);
            return (entries, index < 0 ? 0 : index);
          }
        }
      } catch (_) {}
    }

    final images = _filteredAndSortedEntries.where((e) => !e.isDir && e.isImage).toList();
    if (images.isEmpty) return (const [], 0);
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
            if (!mounted) return;
            _showError(AppLocalizations.of(context).allowInstallApkPrompt);
            return;
          }
        }
      }
      final result = await FileOpenService.instance.openWith(_root, _fullEntryPath(item));
      if (!mounted) return;
      if (result.type == ResultType.noAppToOpen) {
        _showError(AppLocalizations.of(context).noAppToOpenFile(item.name));
      } else if (result.type != ResultType.done) {
        _showError(result.message);
      }
    } catch (e) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context).cannotOpenFile('$e'));
    }
  }

  Future<void> _shareEntry(EntryItem item) async {
    try {
      await FileOpenService.instance.share(_root, _fullEntryPath(item));
    } catch (e) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context).cannotShareFile('$e'));
    }
  }

  /// Backend errors arrive as `kind: detail` strings. Turn the common ones
  /// into something a user can act on instead of echoing the Rust wording.
  String _friendlyError(Object error) => friendlyErrorText(error, mounted ? AppLocalizations.of(context) : null);

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
      _showError(AppLocalizations.of(context).searchFailed(_friendlyError(e)));
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _clearSearch();
      }
    });
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
                AppLocalizations.of(context).noSearchResultsFor(_filterQuery.trim()),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).searchedThisAndSubfolders,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.clear, size: 16),
                label: Text(AppLocalizations.of(context).clearSearch),
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
                ? AppLocalizations.of(context).first200Results
                : AppLocalizations.of(context).searchResultsInFolder(_visibleSearchResults.length),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _visibleSearchResults.length,
            itemBuilder: (ctx, i) {
              final item = _visibleSearchResults[i];
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
                onTap: () {
                  if (_pickMode && !_pickMultiple && !item.isDir) {
                    var rel = item.path;
                    if (rel.startsWith('/')) rel = rel.substring(1);
                    _finishPickWith([(item, rel)]);
                  } else {
                    _openSearchResult(item);
                  }
                },
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
    if (idx < 0) return AppLocalizations.of(context).currentFolder;
    return p.substring(0, idx);
  }

  /// Open a search hit: folders navigate straight in; files navigate to
  /// their folder first (then open), because the open flows are written
  /// against entries of the current folder.
  Future<void> _openSearchResult(EntryItem item) async {
    var p = item.path;
    if (p.startsWith('/')) p = p.substring(1);
    _pushHistory();
    // Selection belonged to the old folder; leaving it behind lets
    // destructive actions hit entries the user can no longer see.
    setState(() {
      _isSelecting = false;
      _selectedPaths.clear();
      _selectionAnchor = null;
    });
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
    if (match != null) {
      _openEntry(match);
    } else {
      _showError(AppLocalizations.of(context).fileBeyondFirstPage(parent));
    }
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
    if (_pickMode) {
      if (!item.isDir && _pickMultiple) {
        _toggleSelect(_fullEntryPath(item));
      }
      return;
    }
    HapticFeedback.mediumImpact();
    final action = await showBrowserEntryModalBottomSheet(
      context: context,
      item: item,
      isRemoteOrArchive: _isRemoteOrArchive(_root),
      canWrite: _canWrite,
      canArchive: _canArchive,
    );
    if (action != null && mounted) {
      _handleEntryAction(action, item);
    }
  }

  /// Desktop right-click context menu on a file/folder referencing File Manager+.
  Future<void> _showContextMenu(BuildContext originContext, Offset position, EntryItem item) async {
    HapticFeedback.mediumImpact();
    _lastItemSecondaryTap = DateTime.now();
    final action = await showBrowserContextMenu(
      context: originContext,
      position: position,
      item: item,
      isRemoteOrArchive: _isRemoteOrArchive(_root),
      canWrite: _canWrite,
      canArchive: _canArchive,
    );
    if (action != null && mounted) {
      _handleEntryAction(action, item);
    }
  }

  void _handleEntryAction(String action, EntryItem item) {
    final path = _fullEntryPath(item);
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
          SnackBar(content: Text(AppLocalizations.of(context).copiedItemToClipboard(item.name))),
        );
        break;
      case 'cut':
        setState(() {
          _clipboard = ClipboardState(srcRoot: _root, paths: [path], isCut: true);
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).cutItemToClipboard(item.name))),
        );
        break;
      case 'select':
        setState(() {
          _isSelecting = true;
          _selectedPaths.add(path);
        });
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
      case 'share':
        _shareEntry(item);
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
      SnackBar(content: Text(AppLocalizations.of(context).pathCopied)),
    );
  }

  /// Desktop right-click context menu on empty space.
  Future<void> _showBackgroundContextMenu(Offset position) async {
    if (_lastItemSecondaryTap != null &&
        DateTime.now().difference(_lastItemSecondaryTap!).inMilliseconds < 400) {
      return;
    }
    HapticFeedback.mediumImpact();
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final action = await showBrowserBackgroundContextMenu(
      context: context,
      position: position,
      canWrite: _canWrite,
      isAtMultiBucketRoot: _isAtMultiBucketRoot,
      hasClipboard: _clipboard != null,
      clipboardCount: _clipboard?.paths.length,
      isZh: isZh,
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
      case 'upload_folder':
        _uploadFolder();
        break;
      case 'upload_inapp':
        _uploadFiles(forceInApp: true);
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
          SnackBar(content: Text(AppLocalizations.of(context).folderPathCopied)),
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
    final loadingFor = '$_root\u0000$_relPath';
    final epoch = _loadEpoch;
    if (_hasMore && _totalCount > 0) {
      if (_totalCount > 10000) {
        // Returning matters: falling through selected only the loaded pages,
        // so the counter claimed a selection that was not the whole folder.
        _showError(AppLocalizations.of(context).tooManyItemsSelectAll(_totalCount));
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
          // The user may have navigated or refreshed while the full listing
          // was in flight; those entries belong to the old folder.
          if (_loadingFor != loadingFor || _loadEpoch != epoch) return;
          setState(() {
            _entries = paged.entries.map((e) => EntryItem(e)).toList();
            _hasMore = false;
            _currentPage = 1;
            _totalCount = paged.total;
          });
        } catch (e) {
          _showError(AppLocalizations.of(context).couldNotLoadAllItems(_friendlyError(e)));
        }
      }
    }
    if (!mounted) return;
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
    if (_isTyping) return;
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
  Future<void> _uploadFiles({bool forceInApp = false}) async {
    if (_remotes.isEmpty) await _loadRemotesMetadata();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (_isAtMultiBucketRoot) {
      _showError(l10n.bucketRootUploadError);
      return;
    }

    if (PreferencesService.instance.useSystemPicker && !forceInApp) {
      return _uploadFilesSystem();
    }
    return _uploadFilesInApp();
  }

  Future<void> _uploadFilesSystem() async {
    final recentDirs = PreferencesService.instance.getRecentUploadDirs();
    final initialDir = recentDirs.isNotEmpty ? recentDirs.first : null;

    List<XFile> files;
    try {
      files = await openFiles(
        initialDirectory: initialDir,
        confirmButtonText: AppLocalizations.of(context).upload,
      );
    } catch (_) {
      return _uploadFilesInApp();
    }
    if (files.isEmpty || !mounted) return;

    final byParent = <String, List<String>>{};
    for (final f in files) {
      final split = splitNativeFile(f.path);
      byParent.putIfAbsent(split.srcRoot, () => []).add(split.name);
      PreferencesService.instance.addRecentUploadDir(split.srcRoot);
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

  Future<void> _uploadFilesInApp() async {
    final picked = await FilePickerDialog.show(
      context,
      title: AppLocalizations.of(context).uploadItemsToCurrentFolder,
    );
    if (picked == null || picked.groups.isEmpty || !mounted) return;

    for (final group in picked.groups) {
      if (group.paths.isEmpty) continue;
      PreferencesService.instance.addRecentUploadDir(group.root);
      await _transfer(
        srcRoot: group.root,
        paths: group.paths,
        isCut: false,
        destRel: _relPath,
      );
      if (!mounted) return;
    }
  }

  Future<void> _uploadFolder({bool forceInApp = false}) async {
    if (_remotes.isEmpty) await _loadRemotesMetadata();
    if (!mounted) return;
    if (_isAtMultiBucketRoot) {
      _showError(AppLocalizations.of(context).bucketRootFolderUploadError);
      return;
    }

    if (PreferencesService.instance.useSystemPicker && !forceInApp) {
      return _uploadFolderSystem();
    }
    return _uploadFolderInApp();
  }

  Future<void> _uploadFolderSystem() async {
    final recentDirs = PreferencesService.instance.getRecentUploadDirs();
    final initialDir = recentDirs.isNotEmpty ? recentDirs.first : null;

    String? selectedPath;
    try {
      selectedPath = await getDirectoryPath(
        initialDirectory: initialDir,
        confirmButtonText: AppLocalizations.of(context).uploadThisFolder,
      );
    } catch (_) {
      return _uploadFolderInApp();
    }
    if (selectedPath == null || selectedPath.isEmpty || !mounted) return;

    PreferencesService.instance.addRecentUploadDir(selectedPath);
    final split = splitNativeFile(selectedPath);

    await _transfer(
      srcRoot: split.srcRoot,
      paths: [split.name],
      isCut: false,
      destRel: _relPath,
    );
  }

  Future<void> _uploadFolderInApp() async {
    final picked = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).selectFolderToUpload,
      initialRoot: PlatformPaths.defaultRoot(),
      confirmLabel: AppLocalizations.of(context).uploadThisFolder,
    );
    if (picked == null || !mounted) return;

    String srcRoot = picked.root;
    List<String> srcPaths;

    if (picked.relPath.isNotEmpty) {
      srcPaths = [picked.relPath];
    } else {
      final isWindows = srcRoot.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(srcRoot);
      final parts = srcRoot.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (parts.isEmpty || srcRoot == PlatformPaths.defaultRoot() || (isNativeRoot(srcRoot) && parts.length <= 2)) {
        _showError(AppLocalizations.of(context).pleaseSelectSpecificFolder);
        return;
      }
      final folderName = parts.last;
      parts.removeLast();
      if (parts.isEmpty) {
        srcRoot = isWindows ? '$folderName\\' : '/';
      } else {
        srcRoot = isWindows ? parts.join('\\') : '/${parts.join('/')}';
      }
      srcPaths = [folderName];
    }

    PreferencesService.instance.addRecentUploadDir(picked.path);

    await _transfer(
      srcRoot: srcRoot,
      paths: srcPaths,
      isCut: false,
      destRel: _relPath,
    );
  }

  Future<void> _downloadSelected() async {
    if (_selectedPaths.isEmpty) return;
    if (!_isRemoteOrArchive(_root)) {
      _showError(AppLocalizations.of(context).alreadyLocalUseCopy);
      return;
    }
    final dest = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).downloadDestination,
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
      final l10n = AppLocalizations.of(context);
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        l10n.downloadingFiles,
        onRetry: startTask,
      );
      if (!mounted) return;
      _clearSelection();
      if (completed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.downloadedTo(dest.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).downloadFailed(e.toString()));
      }
    }
  }

  Future<void> _downloadSingle(EntryItem item) async {
    final dest = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).downloadDestination,
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
            // Never destroy a same-named file in the destination folder.
            conflictPolicy: 'rename',
          );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        AppLocalizations.of(context).downloadingItem(item.name),
        onRetry: startTask,
      );
      if (!mounted) return;
      if (completed == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).downloadedTo(dest.path)),
          ),
        );
      }
    } catch (e) {
      _showError(AppLocalizations.of(context).downloadFailed(e.toString()));
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final isBucket = _isAtMultiBucketRoot;
    final ctrl = TextEditingController();
    final String? name;
    try {
      name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(isBucket ? l10n.newBucket : l10n.newFolder),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: isBucket ? l10n.bucketName : l10n.folderName,
              hintText: isBucket ? l10n.bucketNameHint : null,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: Text(l10n.create),
              ),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (name != null && name.isNotEmpty) {
      if (isBucket) {
        final valid = RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(name) && !name.contains('..');
        if (!valid) {
          if (mounted) {
            _showError(AppLocalizations.of(context).invalidBucketName);
          }
          return;
        }
      }
      final target = _relPath.isEmpty ? name : '$_relPath/$name';
      try {
        await createDir(root: _root, path: target);
        _load(refresh: true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).failedToCreate(e.toString()))));
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
          title: Text(AppLocalizations.of(context).newTextFile),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).fileNameLabel,
              hintText: AppLocalizations.of(context).fileNameHint,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: Text(AppLocalizations.of(context).create),
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
            SnackBar(content: Text(AppLocalizations.of(context).failedToCreateFile('$e')), backgroundColor: Theme.of(context).colorScheme.error),
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
      SnackBar(content: Text(isCut ? AppLocalizations.of(context).cutItemsCount(_clipboard!.paths.length) : AppLocalizations.of(context).copiedItemsCount(_clipboard!.paths.length))),
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
    if (_remotes.isEmpty) await _loadRemotesMetadata();
    if (!mounted) return;
    if (_isAtMultiBucketRoot && (destRel.isEmpty || destRel == '/')) {
      _showError(AppLocalizations.of(context).bucketRootTransferError);
      return;
    }
    // Detect name clashes in the destination first and let the user decide
    // once for the whole batch. Default stays 'rename': if the probe fails
    // for a reason other than "missing" (permissions, network), falling back
    // to overwrite could silently replace existing files.
    var policy = 'rename';
    final conflicts = <String>[];
    for (final p in paths) {
      final name = p.split('/').last;
      final dstPath = destRel.isEmpty ? name : '$destRel/$name';
      if (srcRoot == _root && p == dstPath) continue;
      try {
        await statEntry(root: _root, path: dstPath);
        conflicts.add(name);
      } catch (_) {
        // Not found → nothing to decide. Other failures also fall through:
        // the default 'rename' policy keeps both files either way.
      }
    }
    if (conflicts.isNotEmpty) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).alreadyExists),
          actionsOverflowButtonSpacing: 6,
          content: Text(
            conflicts.length == 1
                ? '"${conflicts.first}" already exists in this folder. What should happen to it?'
                : '${conflicts.length} items already exist in this folder. What should happen to them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: Text(AppLocalizations.of(context).skip),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'rename'),
              child: Text(AppLocalizations.of(context).keepBoth),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: Text(AppLocalizations.of(context).replace),
            ),
          ],
        ),
      );
      if (choice == null) return;
      policy = choice;
    }
    if (!mounted) return;

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

    final l10n = AppLocalizations.of(context);
    try {
      final taskId = await startTask();

      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        isCut ? l10n.movingFiles : l10n.copyingFiles,
        onRetry: startTask,
      );
      // A cancelled move may have already removed some sources, so a cut
      // clipboard is only cleared once the move actually finished.
      if (isCut && completed == true) onCutCompleted?.call();
      if (mounted) _load(refresh: true);
    } catch (e) {
      if (mounted) {
        _showError(isCut ? l10n.moveFailed(e.toString()) : l10n.copyFailed(e.toString()));
      }
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
      _showError(AppLocalizations.of(context).readOnlyCannotDrop);
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
      _showError(AppLocalizations.of(context).cannotDropFolderIntoSelf);
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

    // Check against the whole folder, not just the loaded page: a
    // `_copy` that exists beyond page 1 would otherwise be overwritten.
    final existing = <String>{};
    try {
      existing.addAll(
        (await listDir(root: _root, path: _relPath)).map((e) => e.name),
      );
    } catch (_) {
      existing.addAll(_entries.map((e) => e.name));
    }
    String candidate = '${base}_copy$ext';
    int count = 2;
    while (existing.contains(candidate)) {
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
            conflictPolicy: 'rename',
          );
      final taskId = await startTask();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        l10n.creatingCopy,
        onRetry: startTask,
      );
      if (completed == true && mounted) {
        _load(refresh: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.createdCandidate(candidate)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).duplicateFailed(e.toString()));
      }
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
        title: Text(count == 1 ? AppLocalizations.of(context).deleteSingleConfirmTitle(paths.first.split('/').last) : AppLocalizations.of(context).deleteMultipleConfirmTitle(count)),
        content: Text(
          canTrash
              ? AppLocalizations.of(context).deleteChoiceTrashOrPermanent
              : permanent
                  ? AppLocalizations.of(context).deletePermanentWarning
                  : AppLocalizations.of(context).deleteRemotePermanentWarning,

        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
          if (canTrash) ...[
            TextButton.icon(
              icon: Icon(Icons.delete_forever, size: 18, color: scheme.error),
              label: Text(AppLocalizations.of(context).permanentDelete, style: TextStyle(color: scheme.error)),
              onPressed: () => Navigator.of(ctx).pop('permanent'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(AppLocalizations.of(context).recycleBin),
              onPressed: () => Navigator.of(ctx).pop('trash'),
            ),
          ] else
            FilledButton.icon(
              icon: const Icon(Icons.delete_forever, size: 18),
              style: FilledButton.styleFrom(backgroundColor: scheme.error),
              onPressed: () => Navigator.of(ctx).pop('permanent'),
              label: Text(AppLocalizations.of(context).permanentDelete),
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
      if (!mounted) return;
      if (failures.isNotEmpty) {
        _showError(
          AppLocalizations.of(context).couldNotMoveToTrash(failures.length, paths.length, failures.take(5).join('\n')),
        );
      }
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
              movedPaths.length == 1 ? AppLocalizations.of(context).movedOneToTrash : AppLocalizations.of(context).movedManyToTrash(movedPaths.length),
            ),
            action: newIds.isEmpty
                ? null
                : SnackBarAction(
                    label: AppLocalizations.of(context).undo,
                    onPressed: () async {
                      final failures = <String>[];
                      for (final id in newIds) {
                        try {
                          await StorageService.instance.restoreTrashItem(id);
                        } catch (_) {
                          failures.add(id);
                        }
                      }
                      if (!mounted) return;
                      _load(refresh: true);
                      if (failures.isNotEmpty) {
                        _showError(
                          AppLocalizations.of(context).couldNotRestoreItems(failures.length),
                        );
                      }
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
        final l10n = AppLocalizations.of(context);
        final done = await TaskProgressDialog.show(
          context,
          taskId,
          l10n.deleting,
          onRetry: startTask,
        );
        if (!mounted) return;
        _clearSelection();
        _load(refresh: true);
        if (done == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deletedCount(count)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          _showError(AppLocalizations.of(context).deleteFailed(e.toString()));
        }
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
          title: Text(AppLocalizations.of(context).rename),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: AppLocalizations.of(context).newName, border: const OutlineInputBorder()),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                Navigator.of(ctx).pop(v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: Text(AppLocalizations.of(context).rename),
              ),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      if (!mounted) return;
      if (newName.contains('/') || newName.contains('\\')) {
        _showError(AppLocalizations.of(context).nameCannotContainSlash);
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
        if (!mounted) return;
        _showError(AppLocalizations.of(context).renameFailed('$e'));
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
          title: Text(AppLocalizations.of(context).compressToZip),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: AppLocalizations.of(context).archiveName, border: const OutlineInputBorder()),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                Navigator.of(ctx).pop(v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
            ListenableBuilder(
              listenable: ctrl,
              builder: (ctx, _) => FilledButton(
                onPressed: ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: Text(AppLocalizations.of(context).compress),
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
        final l10n = AppLocalizations.of(context);
        await TaskProgressDialog.show(
          context,
          taskId,
          l10n.compressing,
          onRetry: startTask,
        );
        if (!mounted) return;
        _clearSelection();
        _load(refresh: true);
      } catch (e) {
        if (mounted) {
          _showError(AppLocalizations.of(context).compressFailed(e.toString()));
        }
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
      final l10n = AppLocalizations.of(context);
      await TaskProgressDialog.show(
        context,
        taskId,
        l10n.extracting,
        onRetry: startTask,
      );
      if (mounted) _load(refresh: true);
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).extractFailed(e.toString()));
      }
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
        ? (root.split('/').last.isEmpty ? AppLocalizations.of(context).rootLabel : root.split('/').last)
        : segments.last;
    final bookmarks = await StorageService.instance.getBookmarks();
    final exists = bookmarks.any((b) => b.root == root && b.path == path);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).alreadyBookmarked(name))),
        );
      }
      return;
    }
    await StorageService.instance.addBookmark(name: name, root: root, path: path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).bookmarkedName(name))),
      );
    }
  }

  /// Walks a folder to total its files. Bounded so a huge tree cannot freeze
  /// the dialog; the count is marked approximate when the cap is hit.
  Future<String> _measureDirectory(String path) async {
    final l10n = AppLocalizations.of(context);
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
      return l10n.directoryLabel;
    }
    if (count == 0) return l10n.directoryEmptyLabel;
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
    // Directories report no size from the backend; measure them in the
    // background and fill the dialog once the walk finishes, instead of
    // freezing on "Properties" for a large tree.
    final dirSizeNotifier = ValueNotifier<String?>(null);
    // The walk can outlive the dialog; writing a disposed notifier throws.
    var closed = false;
    if (item.isDir && isNativeRoot(_root)) {
      final dirPath = joinNative(_root, path);
      _measureDirectory(dirPath).then((size) {
        if (!closed) dirSizeNotifier.value = size;
      }).catchError((_) {});
    }
    if (!mounted) {
      closed = true;
      dirSizeNotifier.dispose();
      return;
    }
    final fullPath = isNativeRoot(_root)
        ? joinNative(_root, path)
        : '$_root/$path';
    final ext = item.isDir ? null : (item.name.contains('.') ? item.name.split('.').last : null);
    await showDialog(
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
              _infoRow(AppLocalizations.of(context).nameLabel, item.name),
              _infoRow(AppLocalizations.of(context).pathLabel, fullPath),
              if (ext != null) _infoRow(AppLocalizations.of(context).extensionLabel, ext.toUpperCase()),
              if (item.isDir)
                ValueListenableBuilder<String?>(
                  valueListenable: dirSizeNotifier,
                  builder: (_, size, _) => _infoRow(
                    AppLocalizations.of(context).sizeLabel,
                    size ?? AppLocalizations.of(context).measuring,
                  ),
                )
              else
                _infoRow(
                  AppLocalizations.of(context).sizeLabel,
                  item.size != null ? AppLocalizations.of(context).yesBytes(item.formattedSize, '${item.size}') : AppLocalizations.of(context).unknownSize,
                ),
              _infoRow(AppLocalizations.of(context).modifiedLabel, item.formattedModified),
              _infoRow(AppLocalizations.of(context).typeLabel, item.isDir ? AppLocalizations.of(context).directoryLabel : (item.isArchive ? AppLocalizations.of(context).archiveLabel : AppLocalizations.of(context).fileLabel)),
              _infoRow(AppLocalizations.of(context).hiddenLabel, item.hidden ? AppLocalizations.of(context).yes : AppLocalizations.of(context).no),
              if (item.isSymlink) _infoRow(AppLocalizations.of(context).symlinkLabel, AppLocalizations.of(context).yes),
            ],
          ),
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(AppLocalizations.of(context).copyPath),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullPath));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context).pathCopied)),
              );
            },
          ),
          if (item.isArchive && _canArchive)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _extractArchive(item);
              },
              child: Text(AppLocalizations.of(context).extractHere),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).close)),
        ],
      ),
    );
    closed = true;
    dirSizeNotifier.dispose();
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
  bool _filteredCacheMimeFilter = false;
  BigInt _cachedTotalListedBytes = BigInt.zero;

  List<EntryItem> get _filteredAndSortedEntries {
    final cached = _filteredCache;
    if (cached != null &&
        identical(_filteredCacheEntries, _entries) &&
        _filteredCacheLength == _entries.length &&
        _filteredCacheQuery == _filterQuery &&
        _filteredCacheShowHidden == _showHidden &&
        _filteredCacheMimeFilter == _applyMimeFilter) {
      return cached;
    }
    final query = _filterQuery.toLowerCase();
    BigInt totalBytes = BigInt.zero;
    final result = _entries.where((e) {
      if (!_showHidden && e.hidden) return false;
      if (query.isNotEmpty && !e.nameLower.contains(query)) {
        return false;
      }
      if (_pickMode &&
          _applyMimeFilter &&
          !e.isDir &&
          !widget.pickRequest!.matchesFileName(e.name)) {
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
    _filteredCacheMimeFilter = _applyMimeFilter;
    _cachedTotalListedBytes = totalBytes;
    return result;
  }

  String? _lastRelPathForSegments;
  List<String> _cachedRelPathSegments = const [];

  List<String> get _relPathSegments {
    if (identical(_lastRelPathForSegments, _relPath) || _lastRelPathForSegments == _relPath) {
      return _cachedRelPathSegments;
    }
    _lastRelPathForSegments = _relPath;
    _cachedRelPathSegments = _relPath.isEmpty
        ? const []
        : _relPath.split('/').where((s) => s.isNotEmpty).toList();
    return _cachedRelPathSegments;
  }

  @override
  Widget build(BuildContext context) {
    if (_splitActive) {
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          leading: IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: AppLocalizations.of(context).exitSplitView,
            onPressed: _toggleSplit,
          ),
          title: Text(AppLocalizations.of(context).splitView, style: const TextStyle(fontSize: 14)),
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

    final segments = _relPathSegments;

    // Back first leaves selection/search/address, then walks back through
    // folder history. At the initial folder it leaves the page.
    final canInterceptBack = _isSelecting ||
        _isSearching ||
        _isEditingAddress ||
        _backStack.isNotEmpty ||
        _canNavigateUp;

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
          if (!_isTyping && _isSelecting && _selectedPaths.length == 1 && _canWrite && _entries.isNotEmpty) {
            final target = _selectedPaths.first;
            final idx = _entries.indexWhere((e) => _fullEntryPath(e) == target);
            if (idx >= 0) {
              _duplicateEntry(_entries[idx]);
            }
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () {
          if (!_isTyping && _isSelecting && _selectedPaths.length == 1 && _canWrite && _entries.isNotEmpty) {
            final target = _selectedPaths.first;
            final idx = _entries.indexWhere((e) => _fullEntryPath(e) == target);
            if (idx >= 0) {
              _duplicateEntry(_entries[idx]);
            }
          }
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (!_isTyping && _isSelecting && _selectedPaths.length == 1 && _canWrite) {
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
      canPop: widget.embedded || !canInterceptBack,
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
        } else if (_backStack.isNotEmpty) {
          _goBack();
        } else if (_canNavigateUp) {
          _navigateUp();
        }
      },
      child: Scaffold(
      appBar: PreferencesService.toolbarAtBottom.value && !_pickMode ? null : AppBar(
        titleSpacing: MediaQuery.sizeOf(context).width < 600 ? 10 : 4,
        toolbarHeight: MediaQuery.sizeOf(context).width < 600 ? 40 : 46,
        automaticallyImplyLeading: false,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                tooltip: AppLocalizations.of(context).cancelSelectionEsc,
                onPressed: _clearSelection,
              )
            : _pickMode
                ? (Navigator.of(context).canPop()
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        tooltip: AppLocalizations.of(context).backToPreviousPage,
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        tooltip: AppLocalizations.of(context).cancel,
                        onPressed: () => Navigator.of(context).pop(),
                      ))
                : (MediaQuery.sizeOf(context).width >= 600 && !widget.embedded && Navigator.of(context).canPop()
                ? IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: AppLocalizations.of(context).backToPreviousPage,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null),
        title: _pickMode
            ? (_isSearching
                ? _buildToolbarTitle(segments)
                : Text(
                    _pickMultiple
                        ? AppLocalizations.of(context).pickFilesTitle
                        : AppLocalizations.of(context).pickFileTitle,
                    style: const TextStyle(fontSize: 16),
                  ))
            : _toolbarContent(segments),
        actions: _pickMode
            ? [
                if (!_isSearching)
                  IconButton(
                    icon: const Icon(Icons.search, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: AppLocalizations.of(context).searchAction,
                    onPressed: _toggleSearch,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: AppLocalizations.of(context).close,
                    onPressed: _toggleSearch,
                  ),
                IconButton(
                  icon: const Icon(Icons.storage, size: 20),
                  visualDensity: VisualDensity.compact,
                  tooltip: AppLocalizations.of(context).locationLabel,
                  onPressed: _showPickRootSheet,
                ),
              ]
            : null,
      ),
      bottomNavigationBar: _pickMode
          ? _buildPickBar()
          : (PreferencesService.toolbarAtBottom.value ? _buildBottomToolbar(segments) : null),
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
              tooltip: AppLocalizations.of(context).backToTop,
              child: const Icon(Icons.arrow_upward, size: 18),
            )
          : null,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragDown: (details) {
          _swipeDownX = details.globalPosition.dx;
        },
        onHorizontalDragStart: (details) {
          _swipeStartX = _swipeDownX ?? details.globalPosition.dx;
          _swipeDeltaX = 0;
        },
        onHorizontalDragUpdate: (details) {
          _swipeDeltaX = details.globalPosition.dx - _swipeStartX;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          final edgeThreshold = (MediaQuery.sizeOf(context).width * 0.45).clamp(140.0, 220.0);
          final fromLeftEdge = _swipeStartX < edgeThreshold;
          if (fromLeftEdge && (_swipeDeltaX > 35 || (velocity > 220 && _swipeDeltaX > 15))) {
            _handleSwipeBack();
          } else if ((velocity < -220 && _swipeDeltaX < -25) && _forwardStack.isNotEmpty) {
            HapticFeedback.lightImpact();
            _goForward();
          }
          _swipeDownX = null;
          _swipeStartX = 0;
          _swipeDeltaX = 0;
        },
        onHorizontalDragCancel: () {
          _swipeDownX = null;
          _swipeStartX = 0;
          _swipeDeltaX = 0;
        },
        child: SafeArea(
          // With the toolbar moved to the bottom there is no AppBar to consume
          // the status-bar inset, so the body starts under it otherwise.
          top: PreferencesService.toolbarAtBottom.value,
          bottom: false,
          child: Column(
            children: [
              // A refresh keeps the list, so it needs its own progress line —
              // otherwise F5 and pull-to-refresh look like a no-op.
              if (_refreshing) const LinearProgressIndicator(minHeight: 2),
              _buildCapabilitiesBar(),
              Expanded(child: _buildBody()),
              if (!_pickMode && (_isSelecting || _clipboard != null)) _buildBottomActionBar(),
            ],
          ),
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
              hintText: AppLocalizations.of(context).searchFilesSubfoldersHint,
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
                            _filterQuery.trim().length >= 2 ? AppLocalizations.of(context).searchFoundCount(_searchResults.length) : '${_filteredAndSortedEntries.length}/${_entries.where((e) => _showHidden || !e.hidden).length}',
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
                        AppLocalizations.of(context).sortBy,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        icon: Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
                        label: Text(_sortAsc ? AppLocalizations.of(context).ascending : AppLocalizations.of(context).descending),
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
                      field == SortField.name
                          ? AppLocalizations.of(context).sortByName
                          : field == SortField.size
                              ? AppLocalizations.of(context).sortBySize
                              : field == SortField.modified
                                  ? AppLocalizations.of(context).sortByDate
                                  : AppLocalizations.of(context).sortByType,
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
        action(Icons.select_all, AppLocalizations.of(context).selectAll, _selectAll),
        action(Icons.swap_horiz, AppLocalizations.of(context).invertSelection, _invertSelection),
      ];
    }

    return [
      // Upload lived only in the empty-space right-click menu, so a full
      // list (no blank area to click) had no discoverable way in at all.
      // Phones get it from the overflow menu to keep the icon row narrow.
      if (_canWrite && !compact) ...[
        action(Icons.cloud_upload_outlined, AppLocalizations.of(context).uploadFiles, _uploadFiles),
        action(Icons.drive_folder_upload_outlined, AppLocalizations.of(context).uploadFolder, _uploadFolder),
      ],
      if (!compact) ...[
        action(
          _isSearching ? Icons.search_off : Icons.search,
          AppLocalizations.of(context).searchAction,
          _toggleSearch,
        ),
        if (!widget.embedded)
          action(Icons.vertical_split, AppLocalizations.of(context).splitView, _toggleSplit),
        action(
          _isGrid ? Icons.view_list : Icons.grid_view,
          _isGrid ? AppLocalizations.of(context).listView : AppLocalizations.of(context).gridView,
          () {
            setState(() => _isGrid = !_isGrid);
            _saveViewPreferences();
          },
        ),
        // Sorting lives one tap from the list instead of two menus deep.
        PopupMenuButton<SortField>(
          // The current order was only visible inside the opened menu, so the
          // button looked identical whatever the list was sorted by.
          tooltip: AppLocalizations.of(context).sortStatusTooltip(_sortField.localizedLabel(AppLocalizations.of(context)), _sortAsc ? '↑' : '↓'),
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
          AppLocalizations.of(context).homeDashboard,
          () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      PopupMenuButton<String>(
        tooltip: AppLocalizations.of(context).options,
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
          } else if (val == 'upload_folder') {
            _uploadFolder();
          } else if (val == 'upload_inapp') {
            _uploadFiles(forceInApp: true);
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
                  Text(AppLocalizations.of(context).uploadFiles),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'upload_folder',
              child: Row(
                children: [
                  const Icon(Icons.drive_folder_upload_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).uploadFolder),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'upload_inapp',
              child: Row(
                children: [
                  const Icon(Icons.folder_shared_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).browseInAppUpload),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'new_folder',
              child: Row(
                children: [
                  const Icon(Icons.create_new_folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(_isAtMultiBucketRoot ? AppLocalizations.of(context).newBucket : AppLocalizations.of(context).newFolder),
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
                  Text(_isSearching ? AppLocalizations.of(context).closeSearch : AppLocalizations.of(context).searchFiles),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_view',
              child: Row(
                children: [
                  Icon(_isGrid ? Icons.view_list : Icons.grid_view, size: 18),
                  const SizedBox(width: 8),
                  Text(_isGrid ? AppLocalizations.of(context).switchToList : AppLocalizations.of(context).switchToGrid),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'sort',
              child: Row(
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).sortBy),
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
                    Text(AppLocalizations.of(context).splitView),
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
                Text(AppLocalizations.of(context).selectItems),
              ],
            ),
          ),
          CheckedPopupMenuItem<String>(
            value: 'toggle_hidden',
            checked: _showHidden,
            child: Text(AppLocalizations.of(context).showHiddenFiles),
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
                    tooltip: AppLocalizations.of(context).cancelSelectionEsc,
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
                    tooltip: AppLocalizations.of(context).backToPreviousPage,
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
    String rootLabel;
    if (_root == '/') {
      rootLabel = '/';
    } else if (_root.startsWith('remote://')) {
      final remoteId = _root.substring('remote://'.length);
      final remote = _findRemote(remoteId);
      rootLabel = remote != null ? '☁️ ${remote.name}' : AppLocalizations.of(context).remote;
    } else if (_root.startsWith('archive://')) {
      rootLabel = AppLocalizations.of(context).archiveLabel;
    } else if (_root == '/storage/emulated/0') {
      // Last segment of this path is "0", which reads as a drive letter.
      rootLabel = AppLocalizations.of(context).internalStorage;
    } else {
      rootLabel = _root.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ?? _root;
    }

    return BrowserUnifiedAddressBar(
      isEditingAddress: _isEditingAddress,
      addressController: _addressController,
      onJumpToAddress: _jumpToAddress,
      onCancelEdit: () => setState(() => _isEditingAddress = false),
      onStartEdit: () {
        _addressController.text = _displayFullPath;
        setState(() => _isEditingAddress = true);
      },
      root: _root,
      relPath: _relPath,
      rootLabel: rootLabel,
      segments: segments,
      canGoBack: _backStack.isNotEmpty,
      onGoBack: _goBack,
      canGoForward: _forwardStack.isNotEmpty,
      onGoForward: _goForward,
      canNavigateUp: _canNavigateUp,
      onNavigateUp: _navigateUp,
      onRefresh: _load,
      onSegmentTap: (targetRelPath) {
        if (targetRelPath != _relPath) {
          _pushHistory();
          setState(() {
            _relPath = targetRelPath;
            _isSelecting = false;
            _selectedPaths.clear();
            _selectionAnchor = null;
          });
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
          _load();
        }
      },
      onCopyPath: (path) {
        final full = isNativeRoot(_root) ? joinNative(_root, path) : '$_root/$path';
        Clipboard.setData(ClipboardData(text: full));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).copiedPathValue(full))),
        );
      },
      onAcceptDrop: (data, targetRelPath) => _acceptDrop(data, targetRelPath),
    );
  }

  /// Bytes of the files currently listed; folders are skipped because their
  /// size is unknown until they are walked.
  int _selectedCacheHash = -1;
  int _selectedCacheEntriesLen = -1;
  BigInt _selectedBytesCache = BigInt.zero;

  BigInt get _selectedBytes {
    if (_selectedPaths.isEmpty) return BigInt.zero;
    final selHash = Object.hashAllUnordered(_selectedPaths);
    if (_selectedCacheHash == selHash &&
        _selectedCacheEntriesLen == _entries.length) {
      return _selectedBytesCache;
    }
    var total = BigInt.zero;
    if (_selectedPaths.length * 4 < _entries.length) {
      final prefixLen = _relPath.isEmpty ? 0 : _relPath.length + 1;
      final selectedNames = <String>{};
      for (final p in _selectedPaths) {
        if (_relPath.isEmpty) {
          if (!p.contains('/')) selectedNames.add(p);
        } else if (p.startsWith('$_relPath/')) {
          final rest = p.substring(prefixLen);
          if (!rest.contains('/')) selectedNames.add(rest);
        }
      }
      for (final e in _entries) {
        if (selectedNames.contains(e.name) && !e.isDir && e.size != null) {
          total += e.size!;
        }
      }
    } else {
      for (final e in _entries) {
        if (_selectedPaths.contains(_fullEntryPath(e)) && !e.isDir && e.size != null) {
          total += e.size!;
        }
      }
    }
    _selectedCacheHash = selHash;
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
            Text(AppLocalizations.of(context).capabilitiesPrefix, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                (_filterQuery.isNotEmpty
                        ? AppLocalizations.of(context).itemsOutOfTotal(_filteredAndSortedEntries.length, _entries.where((e) => _showHidden || !e.hidden).length)
                        : AppLocalizations.of(context).itemsCount(_filteredAndSortedEntries.length)) +
                    (_totalListedBytes > BigInt.zero ? '  •  ${_formatBytes(_totalListedBytes)}' : '') +
                    (!_showHidden && _entries.any((e) => e.hidden) ? '  •  ${AppLocalizations.of(context).hiddenFilesOff}' : '') +
                    (_hasMore ? ' (${AppLocalizations.of(context).moreBelow})' : ''),
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

  Widget _buildPickBar() {
    final l10n = AppLocalizations.of(context);
    final request = widget.pickRequest!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  tooltip: l10n.toolbarUpOneLevel,
                  onPressed: _canNavigateUp ? _navigateUp : null,
                ),
                Expanded(
                  child: InkWell(
                    onTap: _showPickRootSheet,
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayFullPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (request.hasTypeFilter)
                  FilterChip(
                    label: Text(
                      _applyMimeFilter ? request.mimeType : l10n.showAllFileTypes,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _applyMimeFilter,
                    onSelected: (v) => setState(() => _applyMimeFilter = v),
                  ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                if (_pickMultiple) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(l10n.selectCount(_selectedPaths.length)),
                    onPressed: _selectedPaths.isEmpty
                        ? null
                        : () => _finishPick(_selectedItems),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPickRootSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
            ),
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                StorageService.instance.getRemotes(),
                StorageService.instance.getBookmarks(),
              ]),
              builder: (context, snap) {
                final remotes = (snap.data?[0] as List<RemoteConfigDto>?) ?? const <RemoteConfigDto>[];
                final bookmarks = (snap.data?[1] as List<BookmarkDto>?) ?? const <BookmarkDto>[];
                final isLoading = snap.connectionState == ConnectionState.waiting;

                return ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: Text(l10n.homeDashboard),
                      subtitle: Text(l10n.backToPreviousPage),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).pop();
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.storage),
                      title: Text(l10n.localStorage),
                      subtitle: Text(
                        PlatformPaths.defaultRoot(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        navigateTo(PlatformPaths.defaultRoot(), '');
                      },
                    ),
                    if (bookmarks.isNotEmpty) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          l10n.bookmarks,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                      for (final b in bookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(b.name),
                          subtitle: Text(
                            b.path.isEmpty ? b.root : '${b.root}/${b.path}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            navigateTo(b.root, b.path);
                          },
                        ),
                    ],
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (remotes.isNotEmpty) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          l10n.cloudRemoteStorage,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                      for (final r in remotes)
                        ListTile(
                          leading: const Icon(Icons.cloud_outlined),
                          title: Text(r.name),
                          subtitle: Text(r.kind.toUpperCase()),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            navigateTo('remote://${r.id}', '');
                          },
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _finishPick(List<EntryItem> items) async {
    await _finishPickWith(items.map((e) => (e, _fullEntryPath(e))).toList());
  }

  Future<void> _finishPickWith(List<(EntryItem, String)> picks) async {
    final paths = <String>[];
    for (final (item, rel) in picks) {
      if (isNativeRoot(_root)) {
        paths.add(joinNative(_root, rel));
        continue;
      }
      final local = await _copyToPickCache(item, rel);
      if (local == null) return;
      paths.add(local);
    }
    if (mounted) Navigator.of(context).pop(paths);
  }

  /// Remote and archive entries have no local path the calling app could
  /// read, so pick mode materializes them into a cache folder first.
  Future<String?> _copyToPickCache(EntryItem item, String rel) async {
    final cacheRoot = (await getTemporaryDirectory()).path;
    const dir = 'fp_pick';
    try {
      await _ensureDir(cacheRoot, dir);
      final name = await _uniqueName(cacheRoot, dir, item.name);
      Future<String> startTask() => TaskService.instance.copy(
            srcRoot: _root,
            srcPaths: [rel],
            dstRoot: cacheRoot,
            dstDir: dir,
            dstName: name,
          );
      final taskId = await startTask();
      if (!mounted) return null;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        AppLocalizations.of(context).downloadingItem(item.name),
        onRetry: startTask,
      );
      if (completed != true || !mounted) return null;
      return joinNative(cacheRoot, '$dir/$name');
    } catch (e) {
      if (mounted) {
        _showError(AppLocalizations.of(context).downloadFailed(e.toString()));
      }
      return null;
    }
  }

  void _clearPickCache() {
    getTemporaryDirectory().then((d) {
      final dir = Directory('${d.path}/fp_pick');
      if (!dir.existsSync()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (final f in dir.listSync()) {
        try {
          if (f.statSync().modified.isBefore(cutoff)) f.deleteSync();
        } catch (_) {}
      }
    }).catchError((_) {});
  }

  Widget _buildBottomActionBar() {
    return BrowserBottomActionBar(
      isSelecting: _isSelecting,
      isRemoteOrArchive: _isRemoteOrArchive(_root),
      canWrite: _canWrite,
      canArchive: _canArchive,
      selectedCount: _selectedPaths.length,
      selectedBytes: _selectedBytes,
      formatBytes: _formatBytes,
      clipboardCount: _clipboard?.paths.length,
      onDownload: _downloadSelected,
      onCopy: () => _copySelected(isCut: false),
      onCut: () => _copySelected(isCut: true),
      onDelete: _deleteSelected,
      onRename: _renameSelected,
      onInfo: _showSelectedInfo,
      onCompress: _compressSelected,
      onPaste: _paste,
      onClearClipboard: () => setState(() => _clipboard = null),
    );
  }

  Widget _buildItemNameText(
    String name,
    TextStyle baseStyle, {
    String? lowerName,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
  }) {
    final query = _trimmedFilterQuery;
    if (query.isEmpty) {
      return Text(
        name,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: baseStyle,
      );
    }

    final lower = lowerName ?? name.toLowerCase();
    final lowerQuery = _lowerFilterQuery;
    final spans = <TextSpan>[];
    final highlightColor = Theme.of(context).colorScheme.primary;
    var start = 0;

    while (start < name.length) {
      final matchIdx = lower.indexOf(lowerQuery, start);
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
              Text(AppLocalizations.of(context).failedToLoadDir, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(AppLocalizations.of(context).retry)),
                  if (_canNavigateUp)
                    OutlinedButton.icon(
                      onPressed: _navigateUp,
                      icon: const Icon(Icons.arrow_upward),
                      label: Text(AppLocalizations.of(context).goUp),
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
                            ? AppLocalizations.of(context).noFilesMatching(_filterQuery)
                            : (_entries.isNotEmpty && !_showHidden)
                                ? AppLocalizations.of(context).onlyHiddenFilesHere
                                : AppLocalizations.of(context).directoryIsEmpty,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (isFiltered) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear, size: 16),
                          label: Text(AppLocalizations.of(context).clearFilter),
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
                          label: Text(AppLocalizations.of(context).showHiddenFiles),
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
                              icon: Icon(_isAtMultiBucketRoot ? Icons.create_new_folder_outlined : Icons.create_new_folder),
                              label: Text(_isAtMultiBucketRoot ? AppLocalizations.of(context).newBucket : AppLocalizations.of(context).newFolder),
                              onPressed: _createFolder,
                            ),
                            if (!_isAtMultiBucketRoot)
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.note_add_outlined),
                                label: Text(AppLocalizations.of(context).newFile),
                                onPressed: _createFile,
                              ),
                            if (_canNavigateUp)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_upward, size: 16),
                                label: Text(AppLocalizations.of(context).goUp),
                                onPressed: _navigateUp,
                              ),
                          ],
                        ),
                      ] else if (_canNavigateUp) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: Text(AppLocalizations.of(context).goUp),
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
                        tooltip: AppLocalizations.of(context).loadMore,
                        onPressed: _loadMore,
                      ),
              );
            }
            final item = list[i];
            final path = _fullEntryPath(item);
            final isSelected = _selectedPaths.contains(path);

            return RepaintBoundary(
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
                              lowerName: item.nameLower,
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
                        label: Text(AppLocalizations.of(context).loadMore),
                        onPressed: _loadMore,
                      ),
              ),
            );
          }
          final item = list[i];
          final path = _fullEntryPath(item);
          final isSelected = _selectedPaths.contains(path);

          return RepaintBoundary(
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
                  lowerName: item.nameLower,
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
