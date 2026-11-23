import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart' as fm_api;

/// Signature for loading one page of directory entries (injectable for tests).
typedef EntryPageLoader = Future<({List<EntryItem> items, bool hasMore, int total})> Function({
  required String root,
  required String path,
  required int page,
  required int pageSize,
  required String sortBy,
  required bool ascending,
  required bool showHidden,
  required String filter,
});

/// Standalone state controller for a single browser pane or tab.
///
/// Manages location (`root`, `relPath`), navigation history (`backStack` /
/// `forwardStack`), paginated entries, sorting, search/filtering, keyboard
/// focus, and multi-selection (including `Shift+Click` range selection and
/// `Cmd/Ctrl+Click` discrete toggling).
class BrowserPaneController extends ChangeNotifier {
  final EntryPageLoader _loader;

  String _root;
  String _relPath;
  String _title;

  final List<({String root, String relPath})> _backStack = [];
  final List<({String root, String relPath})> _forwardStack = [];

  List<EntryItem> _entries = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _total = 0;
  final int _pageSize = 200;
  String? _error;

  String _sortBy = 'name';
  bool _ascending = true;
  bool _showHidden = false;
  String _filter = '';

  final Set<String> _selectedPaths = {};
  int? _selectionAnchorIndex;
  int _focusedIndex = -1;

  int _loadGeneration = 0;

  BrowserPaneController({
    required String root,
    String initialRelPath = '',
    required String title,
    EntryPageLoader? loader,
  })  : _root = root.trim(),
        _relPath = initialRelPath,
        _title = title.trim(),
        _loader = loader ?? _defaultLoader;

  static Future<({List<EntryItem> items, bool hasMore, int total})> _defaultLoader({
    required String root,
    required String path,
    required int page,
    required int pageSize,
    required String sortBy,
    required bool ascending,
    required bool showHidden,
    required String filter,
  }) async {
    final paged = await fm_api.listDirPaged(
      root: root,
      path: path,
      page: page,
      pageSize: pageSize,
      sortBy: sortBy,
      sortAscending: ascending,
    );
    var items = paged.entries.map(EntryItem.new).toList();
    if (!showHidden) {
      items = items.where((e) => !e.hidden).toList();
    }
    if (filter.isNotEmpty) {
      final needle = filter.toLowerCase();
      items = items.where((e) => e.nameLower.contains(needle)).toList();
    }
    return (
      items: items,
      hasMore: paged.hasMore,
      total: paged.total,
    );
  }

  String get root => _root;
  String get relPath => _relPath;
  String get title => _title;
  List<EntryItem> get entries => _entries;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  int get total => _total;
  String? get error => _error;
  String get sortBy => _sortBy;
  bool get ascending => _ascending;
  bool get showHidden => _showHidden;
  String get filter => _filter;
  Set<String> get selectedPaths => Set.unmodifiable(_selectedPaths);
  bool get hasSelection => _selectedPaths.isNotEmpty;
  int get focusedIndex => _focusedIndex;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;
  bool get canGoUp => _relPath.isNotEmpty;

  String get tabDisplayTitle {
    if (_relPath.isEmpty) return _title;
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? _title : segments.last;
  }

  Future<void> reload() async {
    final gen = ++_loadGeneration;
    _loading = true;
    _error = null;
    _page = 1;
    notifyListeners();

    try {
      final res = await _loader(
        root: _root,
        path: _relPath,
        page: 1,
        pageSize: _pageSize,
        sortBy: _sortBy,
        ascending: _ascending,
        showHidden: _showHidden,
        filter: _filter,
      );
      if (gen != _loadGeneration) return;
      _entries = res.items;
      _hasMore = res.hasMore;
      _total = res.total;
      _loading = false;
      final existing = _entries.map((e) => e.path).toSet();
      _selectedPaths.retainWhere(existing.contains);
      if (_focusedIndex >= _entries.length) {
        _focusedIndex = _entries.isEmpty ? -1 : _entries.length - 1;
      }
      notifyListeners();
    } catch (e) {
      if (gen != _loadGeneration) return;
      _error = '$e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final gen = _loadGeneration;
    _loadingMore = true;
    notifyListeners();
    try {
      final nextPage = _page + 1;
      final res = await _loader(
        root: _root,
        path: _relPath,
        page: nextPage,
        pageSize: _pageSize,
        sortBy: _sortBy,
        ascending: _ascending,
        showHidden: _showHidden,
        filter: _filter,
      );
      if (gen != _loadGeneration) return;
      _page = nextPage;
      _entries = [..._entries, ...res.items];
      _hasMore = res.hasMore;
      _total = res.total;
      _loadingMore = false;
      notifyListeners();
    } catch (e) {
      if (gen != _loadGeneration) return;
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> navigateTo({
    String? newRoot,
    required String newRelPath,
    String? newTitle,
    bool pushHistory = true,
  }) async {
    final targetRoot = newRoot ?? _root;
    if (targetRoot == _root && newRelPath == _relPath) return;
    if (pushHistory) {
      _backStack.add((root: _root, relPath: _relPath));
      if (_backStack.length > 100) _backStack.removeAt(0);
      _forwardStack.clear();
    }
    _root = targetRoot;
    _relPath = newRelPath;
    if (newTitle != null) _title = newTitle;
    _selectedPaths.clear();
    _selectionAnchorIndex = null;
    _focusedIndex = -1;
    await reload();
  }

  Future<bool> goBack() async {
    if (_backStack.isEmpty) return false;
    _forwardStack.add((root: _root, relPath: _relPath));
    final prev = _backStack.removeLast();
    _root = prev.root;
    _relPath = prev.relPath;
    _selectedPaths.clear();
    _selectionAnchorIndex = null;
    _focusedIndex = -1;
    await reload();
    return true;
  }

  Future<bool> goForward() async {
    if (_forwardStack.isEmpty) return false;
    _backStack.add((root: _root, relPath: _relPath));
    final next = _forwardStack.removeLast();
    _root = next.root;
    _relPath = next.relPath;
    _selectedPaths.clear();
    _selectionAnchorIndex = null;
    _focusedIndex = -1;
    await reload();
    return true;
  }

  Future<bool> goUp() async {
    if (_relPath.isEmpty) return false;
    final parts = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return false;
    parts.removeLast();
    await navigateTo(newRelPath: parts.join('/'));
    return true;
  }

  Future<void> setSort(String sortBy, {bool? ascending}) async {
    if (_sortBy == sortBy && ascending == null) {
      _ascending = !_ascending;
    } else {
      _sortBy = sortBy;
      if (ascending != null) _ascending = ascending;
    }
    await reload();
  }

  Future<void> setShowHidden(bool value) async {
    if (_showHidden == value) return;
    _showHidden = value;
    await reload();
  }

  Future<void> setFilter(String value) async {
    if (_filter == value) return;
    _filter = value;
    await reload();
  }

  /// Desktop-grade selection handler supporting plain click, `Cmd/Ctrl+Click`
  /// discrete toggle, and `Shift+Click` contiguous range selection.
  void handleItemSelectionClick(
    int index, {
    required bool isShiftPressed,
    required bool isCtrlOrMetaPressed,
  }) {
    if (index < 0 || index >= _entries.length) return;
    final item = _entries[index];

    if (isShiftPressed && _selectionAnchorIndex != null) {
      final start = _selectionAnchorIndex!.clamp(0, _entries.length - 1);
      final lo = start < index ? start : index;
      final hi = start < index ? index : start;
      if (!isCtrlOrMetaPressed) {
        _selectedPaths.clear();
      }
      for (int i = lo; i <= hi; i++) {
        _selectedPaths.add(_entries[i].path);
      }
      _focusedIndex = index;
    } else if (isCtrlOrMetaPressed) {
      if (_selectedPaths.contains(item.path)) {
        _selectedPaths.remove(item.path);
      } else {
        _selectedPaths.add(item.path);
      }
      _selectionAnchorIndex = index;
      _focusedIndex = index;
    } else {
      _selectedPaths
        ..clear()
        ..add(item.path);
      _selectionAnchorIndex = index;
      _focusedIndex = index;
    }
    notifyListeners();
  }

  void setSelectedPaths(Iterable<String> paths) {
    _selectedPaths
      ..clear()
      ..addAll(paths);
    notifyListeners();
  }

  void togglePath(String path) {
    final idx = _entries.indexWhere((e) => e.path == path);
    if (_selectedPaths.contains(path)) {
      _selectedPaths.remove(path);
    } else {
      _selectedPaths.add(path);
    }
    if (idx >= 0) {
      _selectionAnchorIndex = idx;
      _focusedIndex = idx;
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths
      ..clear()
      ..addAll(_entries.map((e) => e.path));
    notifyListeners();
  }

  void invertSelection() {
    final next = <String>{};
    for (final e in _entries) {
      if (!_selectedPaths.contains(e.path)) next.add(e.path);
    }
    _selectedPaths
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedPaths.isEmpty && _selectionAnchorIndex == null) return;
    _selectedPaths.clear();
    _selectionAnchorIndex = null;
    notifyListeners();
  }

  void moveFocus(int delta, {bool extendSelection = false}) {
    if (_entries.isEmpty) return;
    final next = _focusedIndex < 0
        ? (delta >= 0 ? 0 : _entries.length - 1)
        : (_focusedIndex + delta).clamp(0, _entries.length - 1);
    handleItemSelectionClick(
      next,
      isShiftPressed: extendSelection,
      isCtrlOrMetaPressed: false,
    );
  }
}
