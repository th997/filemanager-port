import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../models/entry_item.dart';
import '../pages/text_editor_page.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/metadata.dart';
import '../rust/api/pool.dart';
import '../rust/api/remotes.dart';
import '../rust/api/search.dart';
import '../rust/api/vault.dart';
import '../services/platform_capabilities.dart';
import '../services/platform_paths.dart';
import '../services/task_service.dart';
import '../services/vault_service.dart';

/// Optional metadata sources for Global Search (bookmarks, quick folders,
/// privacy vaults, remotes, storage pools, and browsing history).
class GlobalSearchSources {
  final List<BookmarkDto> bookmarks;
  final List<HistoryDto> history;
  final List<RemoteConfigDto> remotes;
  final List<PoolSummaryDto> pools;
  final List<QuickTarget> quickTargets;
  final List<UnlockedVaultDto> unlockedVaults;
  final List<PinnedVaultEntry> lockedPinnedVaults;

  const GlobalSearchSources({
    this.bookmarks = const [],
    this.history = const [],
    this.remotes = const [],
    this.pools = const [],
    this.quickTargets = const [],
    this.unlockedVaults = const [],
    this.lockedPinnedVaults = const [],
  });
}

/// Filtered metadata hits produced synchronously by [GlobalSearchMatcher].
class GlobalSearchMatches {
  final List<BookmarkDto> bookmarks;
  final List<QuickTarget> quickTargets;
  final List<UnlockedVaultDto> unlockedVaults;
  final List<PinnedVaultEntry> lockedPinnedVaults;
  final List<RemoteConfigDto> remotes;
  final List<PoolSummaryDto> pools;
  final List<HistoryDto> history;

  const GlobalSearchMatches({
    this.bookmarks = const [],
    this.quickTargets = const [],
    this.unlockedVaults = const [],
    this.lockedPinnedVaults = const [],
    this.remotes = const [],
    this.pools = const [],
    this.history = const [],
  });

  bool get isEmpty =>
      bookmarks.isEmpty &&
      quickTargets.isEmpty &&
      unlockedVaults.isEmpty &&
      lockedPinnedVaults.isEmpty &&
      remotes.isEmpty &&
      pools.isEmpty &&
      history.isEmpty;
}

/// Pure matcher for filtering local metadata (bookmarks, quick folders, vaults,
/// remotes, storage pools, and recent history) synchronously while disk search runs.
class GlobalSearchMatcher {
  static GlobalSearchMatches match({
    required GlobalSearchSources sources,
    required String query,
    String matchMode = 'contains',
    bool caseSensitive = false,
    String category = 'all',
    bool hasSizeFilter = false,
    bool hasDateFilter = false,
    AppLocalizations? l10n,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty ||
        hasSizeFilter ||
        hasDateFilter ||
        (category != 'all' && category != 'folder')) {
      return const GlobalSearchMatches();
    }

    final predicate = _buildPredicate(
      trimmed,
      matchMode: matchMode,
      caseSensitive: caseSensitive,
    );
    if (predicate == null) return const GlobalSearchMatches();

    final bookmarks = sources.bookmarks
        .where((bm) =>
            predicate(bm.name) || predicate(bm.path) || predicate(bm.root))
        .toList();

    final quickTargets = sources.quickTargets
        .where((t) =>
            predicate(t.displayName(l10n)) ||
            predicate(t.name) ||
            predicate(t.path))
        .toList();

    final unlockedVaults =
        sources.unlockedVaults.where((v) => predicate(v.name)).toList();

    final lockedPinnedVaults =
        sources.lockedPinnedVaults.where((v) => predicate(v.name)).toList();

    final remotes = sources.remotes
        .where((r) =>
            predicate(r.name) ||
            predicate(r.kind) ||
            predicate(r.host ?? '') ||
            predicate(r.endpoint ?? '') ||
            predicate(r.bucket ?? ''))
        .toList();

    final pools = sources.pools
        .where((p) => predicate(p.name) || predicate(p.id))
        .toList();

    final bookmarkKeys = <String>{
      for (final bm in bookmarks) _canonicalKey(bm.root, bm.path),
    };
    final history = sources.history
        .where((h) =>
            !bookmarkKeys.contains(_canonicalKey(h.root, h.path)) &&
            (predicate(h.path) || predicate(h.root)))
        .take(20)
        .toList();

    return GlobalSearchMatches(
      bookmarks: bookmarks,
      quickTargets: quickTargets,
      unlockedVaults: unlockedVaults,
      lockedPinnedVaults: lockedPinnedVaults,
      remotes: remotes,
      pools: pools,
      history: history,
    );
  }

  static bool Function(String candidate)? _buildPredicate(
    String query, {
    required String matchMode,
    required bool caseSensitive,
  }) {
    final mode = matchMode.trim().toLowerCase();
    if (mode == 'wildcard' || mode == 'regex') {
      final pattern =
          mode == 'wildcard' ? _wildcardToRegex(query) : query;
      try {
        final re = RegExp(pattern, caseSensitive: caseSensitive);
        return (candidate) => candidate.isNotEmpty && re.hasMatch(candidate);
      } catch (_) {
        return null;
      }
    }
    final needle = caseSensitive ? query : query.toLowerCase();
    return (candidate) {
      if (candidate.isEmpty) return false;
      return caseSensitive
          ? candidate.contains(needle)
          : candidate.toLowerCase().contains(needle);
    };
  }

  static String _wildcardToRegex(String pattern) {
    final buf = StringBuffer('^');
    for (final rune in pattern.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '*') {
        buf.write('.*');
      } else if (ch == '?') {
        buf.write('.');
      } else {
        buf.write(RegExp.escape(ch));
      }
    }
    buf.write(r'$');
    return buf.toString();
  }

  static String _canonicalKey(String root, String path) {
    var r = root.replaceAll('\\', '/');
    while (r.length > 1 && r.endsWith('/')) {
      r = r.substring(0, r.length - 1);
    }
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return '$r::$p';
  }
}

/// What kind of item the user picked in [AdvancedSearchDialog].
enum AdvancedSearchSelectionKind {
  entry,
  bookmark,
  history,
  remote,
  pool,
  quickTarget,
  unlockedVault,
  lockedPinnedVault,
}

/// Result returned when the user selects an item from [AdvancedSearchDialog].
class AdvancedSearchSelection {
  final AdvancedSearchSelectionKind kind;
  final EntryItem? entry;
  final String? entryRoot;
  final BookmarkDto? bookmark;
  final HistoryDto? history;
  final RemoteConfigDto? remote;
  final PoolSummaryDto? pool;
  final QuickTarget? quickTarget;
  final UnlockedVaultDto? unlockedVault;
  final PinnedVaultEntry? lockedPinnedVault;

  const AdvancedSearchSelection._({
    required this.kind,
    this.entry,
    this.entryRoot,
    this.bookmark,
    this.history,
    this.remote,
    this.pool,
    this.quickTarget,
    this.unlockedVault,
    this.lockedPinnedVault,
  });

  const AdvancedSearchSelection.entry(EntryItem entry, {required String root})
      : this._(
          kind: AdvancedSearchSelectionKind.entry,
          entry: entry,
          entryRoot: root,
        );

  const AdvancedSearchSelection.bookmark(BookmarkDto bookmark)
      : this._(kind: AdvancedSearchSelectionKind.bookmark, bookmark: bookmark);

  const AdvancedSearchSelection.history(HistoryDto history)
      : this._(kind: AdvancedSearchSelectionKind.history, history: history);

  const AdvancedSearchSelection.remote(RemoteConfigDto remote)
      : this._(kind: AdvancedSearchSelectionKind.remote, remote: remote);

  const AdvancedSearchSelection.pool(PoolSummaryDto pool)
      : this._(kind: AdvancedSearchSelectionKind.pool, pool: pool);

  const AdvancedSearchSelection.quickTarget(QuickTarget target)
      : this._(kind: AdvancedSearchSelectionKind.quickTarget, quickTarget: target);

  const AdvancedSearchSelection.unlockedVault(UnlockedVaultDto vault)
      : this._(
          kind: AdvancedSearchSelectionKind.unlockedVault,
          unlockedVault: vault,
        );

  const AdvancedSearchSelection.lockedPinnedVault(PinnedVaultEntry vault)
      : this._(
          kind: AdvancedSearchSelectionKind.lockedPinnedVault,
          lockedPinnedVault: vault,
        );
}

typedef SearchEntriesAdvancedFn = Future<List<EntryDto>> Function({
  required String root,
  required String path,
  required AdvancedSearchQueryDto options,
});

typedef GrepTextFilesFn = Future<List<GrepMatchDto>> Function({
  required String root,
  required String path,
  required String pattern,
  required bool useRegex,
  required bool caseSensitive,
  required bool includeHidden,
  required int maxMatches,
});

typedef QuerySearchIndexFn = Future<List<IndexedSearchHitDto>> Function({
  String? root,
  required String query,
  String? category,
  BigInt? minSize,
  BigInt? maxSize,
  int? modifiedAfterMillis,
  int? modifiedBeforeMillis,
  required bool includeHidden,
  required int maxResults,
});

typedef RebuildSearchIndexFn = Future<SearchIndexStatsDto> Function({
  required String root,
  int? maxEntries,
});

typedef GetSearchIndexStatsFn = List<SearchIndexStatsDto> Function({
  String? root,
});

typedef ClearSearchIndexFn = bool Function({required String root});

/// Multi-dimensional Search (files, folders, global bookmarks/remotes/history,
/// category, size range, modified date, wildcard/regex) and Content Full-Text
/// Search (Grep mode with direct jump to line number).
Future<AdvancedSearchSelection?> showAdvancedSearchDialog(
  BuildContext context, {
  required String root,
  required String relPath,
  bool readOnly = false,
  String initialCategory = 'all',
  String initialQuery = '',
  GlobalSearchSources? globalSources,
  List<({String root, String relPath})> extraSearchScopes = const [],
  SearchEntriesAdvancedFn? searchEntriesFn,
  GrepTextFilesFn? grepTextFilesFn,
  QuerySearchIndexFn? queryIndexFn,
  RebuildSearchIndexFn? rebuildIndexFn,
  GetSearchIndexStatsFn? indexStatsFn,
  ClearSearchIndexFn? clearIndexFn,
}) {
  return showDialog<AdvancedSearchSelection>(
    context: context,
    builder: (_) => _AdvancedSearchDialog(
      root: root,
      relPath: relPath,
      readOnly: readOnly,
      initialCategory: initialCategory,
      initialQuery: initialQuery,
      globalSources: globalSources,
      extraSearchScopes: extraSearchScopes,
      searchEntriesFn: searchEntriesFn ?? searchEntriesAdvanced,
      grepTextFilesFn: grepTextFilesFn ?? grepTextFiles,
      queryIndexFn: queryIndexFn,
      rebuildIndexFn: rebuildIndexFn,
      indexStatsFn: indexStatsFn,
      clearIndexFn: clearIndexFn,
    ),
  );
}

class _AdvancedSearchDialog extends StatefulWidget {
  final String root;
  final String relPath;
  final bool readOnly;
  final String initialCategory;
  final String initialQuery;
  final GlobalSearchSources? globalSources;
  final List<({String root, String relPath})> extraSearchScopes;
  final SearchEntriesAdvancedFn searchEntriesFn;
  final GrepTextFilesFn grepTextFilesFn;
  final QuerySearchIndexFn? queryIndexFn;
  final RebuildSearchIndexFn? rebuildIndexFn;
  final GetSearchIndexStatsFn? indexStatsFn;
  final ClearSearchIndexFn? clearIndexFn;

  const _AdvancedSearchDialog({
    required this.root,
    required this.relPath,
    required this.readOnly,
    required this.initialCategory,
    required this.initialQuery,
    required this.globalSources,
    required this.extraSearchScopes,
    required this.searchEntriesFn,
    required this.grepTextFilesFn,
    this.queryIndexFn,
    this.rebuildIndexFn,
    this.indexStatsFn,
    this.clearIndexFn,
  });

  @override
  State<_AdvancedSearchDialog> createState() => _AdvancedSearchDialogState();
}

class _AdvancedSearchDialogState extends State<_AdvancedSearchDialog> {
  late final TextEditingController _queryController;
  final TextEditingController _minMbController = TextEditingController();
  final TextEditingController _maxMbController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();

  bool _grepMode = false;
  late String _category;
  String _matchMode = 'contains';
  bool _caseSensitive = false;
  bool _includeHidden = false;
  bool _filtersExpanded = false;

  Timer? _debounce;
  int _fileSearchSeq = 0;
  int _grepSearchSeq = 0;
  bool _hasSearchedFiles = false;
  bool _hasSearchedGrep = false;
  bool _searchingFiles = false;
  bool _searchingGrep = false;
  String? _fileError;
  String? _grepError;

  bool get _searching => _grepMode ? _searchingGrep : _searchingFiles;
  bool get _hasSearched => _grepMode ? _hasSearchedGrep : _hasSearchedFiles;
  String? get _error => _grepMode ? _grepError : _fileError;

  SearchIndexStatsDto? _indexStats;
  bool _indexing = false;

  GlobalSearchMatches _globalMatches = const GlobalSearchMatches();
  List<({EntryItem entry, String root})> _fileResults = const [];
  List<GrepMatchDto> _grepResults = const [];

  @override
  void initState() {
    super.initState();
    _category = (widget.initialCategory == 'apk' &&
            !PlatformCapabilities.supportsInstallersCategory)
        ? 'all'
        : widget.initialCategory;
    _queryController = TextEditingController(text: widget.initialQuery);
    _loadIndexStats();
    if (_category != 'all' || widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshGlobalMatches();
        _runSearch();
      });
    }
  }

  void _loadIndexStats() {
    if (widget.root.startsWith('vault://') ||
        widget.root.startsWith('archive://vault://')) {
      return;
    }
    try {
      final statsFn = widget.indexStatsFn ?? getSearchIndexStats;
      final list = statsFn(root: widget.root);
      if (mounted) {
        setState(() {
          _indexStats = list.isNotEmpty ? list.first : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _rebuildIndex() async {
    if (_indexing) return;
    setState(() => _indexing = true);
    try {
      final rebuildFn = widget.rebuildIndexFn ?? rebuildSearchIndex;
      final stats = await rebuildFn(root: widget.root);
      if (!mounted) return;
      setState(() {
        _indexStats = stats;
        _indexing = false;
      });
      if (_hasSearched || _hasAnyFilter) {
        _runSearch();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _indexing = false;
        _fileError = '$e';
      });
    }
  }

  void _clearIndex() {
    try {
      final clearFn = widget.clearIndexFn ?? clearSearchIndex;
      clearFn(root: widget.root);
      setState(() => _indexStats = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).fastIndexCleared)),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _minMbController.dispose();
    _maxMbController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  bool get _hasSizeFilter =>
      _minMbController.text.trim().isNotEmpty ||
      _maxMbController.text.trim().isNotEmpty;

  bool get _hasDateFilter => _daysController.text.trim().isNotEmpty;

  bool get _hasAnyFilter =>
      _queryController.text.trim().isNotEmpty ||
      _category != 'all' ||
      _hasSizeFilter ||
      _hasDateFilter;

  void _refreshGlobalMatches() {
    final sources = widget.globalSources;
    if (sources == null) {
      if (!_globalMatches.isEmpty) {
        setState(() => _globalMatches = const GlobalSearchMatches());
      }
      return;
    }
    final l10n = AppLocalizations.of(context);
    final matches = GlobalSearchMatcher.match(
      sources: sources,
      query: _queryController.text,
      matchMode: _matchMode,
      caseSensitive: _caseSensitive,
      category: _category,
      hasSizeFilter: _hasSizeFilter,
      hasDateFilter: _hasDateFilter,
      l10n: l10n,
    );
    setState(() => _globalMatches = matches);
  }

  void _onQueryChanged(String _) {
    _refreshGlobalMatches();
    if (_grepMode) return;
    _debounce?.cancel();
    if (!_hasAnyFilter) {
      _fileSearchSeq++;
      setState(() {
        _fileResults = const [];
        _searchingFiles = false;
        _hasSearchedFiles = false;
        _fileError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  void _onFilterOptionChanged() {
    _refreshGlobalMatches();
    if (!_grepMode && (_hasSearchedFiles || _hasAnyFilter)) {
      _debounce?.cancel();
      _runSearch();
    }
  }

  static String _normalizeSlash(String p) {
    var s = p.replaceAll('\\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static bool _isBareRoot(String root, String relPath) {
    if (relPath.trim().isNotEmpty) return false;
    final norm = _normalizeSlash(root);
    return norm == '/' || RegExp(r'^[A-Za-z]:/?$').hasMatch(norm);
  }

  static String _joinFullPath(String root, String relPath) {
    final r = _normalizeSlash(root);
    var rel = relPath.replaceAll('\\', '/');
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    while (rel.length > 1 && rel.endsWith('/')) {
      rel = rel.substring(0, rel.length - 1);
    }
    if (rel.isEmpty) return r;
    if (r == '/') return '/$rel';
    if (RegExp(r'^[A-Za-z]:/$').hasMatch(r)) return '$r$rel';
    return '$r/$rel';
  }

  List<({String root, String relPath})> _buildSearchScopes() {
    final primary = (root: widget.root, relPath: widget.relPath);
    final scopes = <({String root, String relPath})>[primary];
    final keptFulls = <({String full, bool bare})>[
      (
        full: _joinFullPath(primary.root, primary.relPath),
        bare: _isBareRoot(primary.root, primary.relPath),
      ),
    ];

    for (final extra in widget.extraSearchScopes) {
      if (_isBareRoot(extra.root, extra.relPath)) continue;
      final extraFull = _joinFullPath(extra.root, extra.relPath);
      final covered = keptFulls.any(
        (k) => k.full == extraFull || (!k.bare && extraFull.startsWith('${k.full}/')),
      );
      if (covered) continue;
      scopes.add(extra);
      keptFulls.add((full: extraFull, bare: false));
    }
    return scopes;
  }

  Future<void> _runSearch() async {
    _debounce?.cancel();
    if (_grepMode) {
      final seq = ++_grepSearchSeq;
      setState(() {
        _searchingGrep = true;
        _hasSearchedGrep = true;
        _grepError = null;
      });
      try {
        final hits = await widget.grepTextFilesFn(
          root: widget.root,
          path: widget.relPath,
          pattern: _queryController.text,
          useRegex: _matchMode == 'regex',
          caseSensitive: _caseSensitive,
          includeHidden: _includeHidden,
          maxMatches: 300,
        );
        if (!mounted || seq != _grepSearchSeq) return;
        setState(() {
          _grepResults = hits;
          _searchingGrep = false;
        });
      } catch (e) {
        if (mounted && seq == _grepSearchSeq) {
          setState(() {
            _grepError = '$e';
            _searchingGrep = false;
          });
        }
      }
      return;
    }

    final seq = ++_fileSearchSeq;
    _refreshGlobalMatches();

    setState(() {
      _searchingFiles = true;
      _hasSearchedFiles = true;
      _fileError = null;
    });

    try {
      final rawMinMb = double.tryParse(_minMbController.text.trim());
      final rawMaxMb = double.tryParse(_maxMbController.text.trim());
      final minMb = rawMinMb == null ? null : (rawMinMb < 0 ? 0.0 : rawMinMb);
      final maxMb = rawMaxMb == null ? null : (rawMaxMb < 0 ? 0.0 : rawMaxMb);
      final days = int.tryParse(_daysController.text.trim());
      final modifiedAfter = days != null && days > 0
          ? DateTime.now()
              .subtract(Duration(days: days))
              .millisecondsSinceEpoch
          : null;
      final options = AdvancedSearchQueryDto(
        query: _queryController.text,
        category: _category,
        minSize:
            minMb != null ? BigInt.from((minMb * 1024 * 1024).round()) : null,
        maxSize:
            maxMb != null ? BigInt.from((maxMb * 1024 * 1024).round()) : null,
        modifiedAfterMillis: modifiedAfter,
        modifiedBeforeMillis: null,
        matchMode: _matchMode,
        caseSensitive: _caseSensitive,
        includeHidden: _includeHidden,
        maxResults: 500,
      );

      final scopes = _buildSearchScopes();
      final combined = <({EntryItem entry, String root})>[];
      final seenKeys = <String>{};

      final relNorm = _normalizeSlash(widget.relPath).replaceFirst(RegExp(r'^/+'), '');
      final canUseFastIndex = _indexStats != null &&
          _matchMode == 'contains' &&
          !_caseSensitive &&
          !widget.root.startsWith('vault://') &&
          !widget.root.startsWith('archive://vault://');

      for (var i = 0; i < scopes.length; i++) {
        if (combined.length >= 500) break;
        final scope = scopes[i];
        try {
          if (i == 0 && canUseFastIndex) {
            final qFn = widget.queryIndexFn ?? querySearchIndex;
            final hits = await qFn(
              root: scope.root,
              query: options.query,
              category: options.category == 'all' ? null : options.category,
              minSize: options.minSize,
              maxSize: options.maxSize,
              modifiedAfterMillis: options.modifiedAfterMillis,
              modifiedBeforeMillis: options.modifiedBeforeMillis,
              includeHidden: options.includeHidden,
              maxResults: 500,
            );
            if (!mounted || seq != _fileSearchSeq) return;
            for (final hit in hits) {
              if (relNorm.isNotEmpty) {
                final hp = hit.path.replaceFirst(RegExp(r'^/+'), '');
                if (hp != relNorm && !hp.startsWith('$relNorm/')) {
                  continue;
                }
              }
              final dto = EntryDto(
                name: hit.name,
                path: hit.path,
                isDir: hit.isDir,
                size: hit.isDir ? null : hit.size,
                modifiedMillis: hit.modifiedMillis,
                hidden: hit.hidden,
                isSymlink: false,
              );
              final isVirtual = scope.root.startsWith('remote://') ||
                  scope.root.startsWith('vault://') ||
                  scope.root.startsWith('pool://');
              final key = isVirtual
                  ? '${scope.root}::${dto.path}'
                  : _joinFullPath(scope.root, dto.path);
              if (seenKeys.add(key)) {
                combined.add((entry: EntryItem(dto), root: scope.root));
                if (combined.length >= 500) break;
              }
            }
            continue;
          }

          final res = await widget.searchEntriesFn(
            root: scope.root,
            path: scope.relPath,
            options: options,
          );
          if (!mounted || seq != _fileSearchSeq) return;
          for (final dto in res) {
            final isVirtual = scope.root.startsWith('remote://') ||
                scope.root.startsWith('vault://') ||
                scope.root.startsWith('pool://');
            final key = isVirtual
                ? '${scope.root}::${dto.path}'
                : _joinFullPath(scope.root, dto.path);
            if (seenKeys.add(key)) {
              combined.add((entry: EntryItem(dto), root: scope.root));
              if (combined.length >= 500) break;
            }
          }
        } catch (e) {
          if (i == 0) rethrow;
        }
      }

      if (!mounted || seq != _fileSearchSeq) return;
      setState(() {
        _fileResults = combined;
        _searchingFiles = false;
      });
    } catch (e) {
      if (mounted && seq == _fileSearchSeq) {
        setState(() {
          _fileError = '$e';
          _searchingFiles = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final activeFilterCount = (_matchMode != 'contains' ? 1 : 0) +
        (!_grepMode && _category != 'all' ? 1 : 0) +
        (_caseSensitive ? 1 : 0) +
        (_includeHidden ? 1 : 0) +
        (!_grepMode && _hasSizeFilter ? 1 : 0) +
        (!_grepMode && _hasDateFilter ? 1 : 0);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l10n.advancedSearch),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l10n.grepContentSearch),
                        ),
                      ],
                      selected: {_grepMode},
                      onSelectionChanged: (s) {
                        final nextGrep = s.first;
                        _debounce?.cancel();
                        setState(() {
                          _grepMode = nextGrep;
                          if (nextGrep && _matchMode == 'wildcard') {
                            _matchMode = 'contains';
                          }
                        });
                        _refreshGlobalMatches();
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: _grepMode
                            ? l10n.grepContentSearch
                            : (widget.globalSources != null
                                ? l10n.globalSearchHint
                                : l10n.searchFiles),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _onQueryChanged,
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _searching ? null : _runSearch,
                    child: Text(l10n.searchAction),
                  ),
                ],
              ),
              if (isNarrow)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _filtersExpanded = !_filtersExpanded),
                    icon: Icon(
                      _filtersExpanded ? Icons.expand_less : Icons.tune,
                      size: 16,
                    ),
                    label: Text(l10n.searchFiltersLabel(activeFilterCount)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              if (!isNarrow || _filtersExpanded) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<String>(
                      value: _matchMode,
                      isDense: true,
                      items: [
                        DropdownMenuItem(
                          value: 'contains',
                          child: Text(l10n.matchContains),
                        ),
                        if (!_grepMode)
                          DropdownMenuItem(
                            value: 'wildcard',
                            child: Text(l10n.matchWildcard),
                          ),
                        DropdownMenuItem(
                          value: 'regex',
                          child: Text(l10n.matchRegex),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _matchMode = v);
                          _onFilterOptionChanged();
                        }
                      },
                    ),
                    if (!_grepMode)
                      DropdownButton<String>(
                        value: _category,
                        isDense: true,
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(l10n.searchAllTypes),
                          ),
                          DropdownMenuItem(
                            value: 'image',
                            child: Text(l10n.gallery),
                          ),
                          DropdownMenuItem(
                            value: 'video',
                            child: Text(l10n.categoryVideos),
                          ),
                          DropdownMenuItem(
                            value: 'audio',
                            child: Text(l10n.categoryAudio),
                          ),
                          DropdownMenuItem(
                            value: 'document',
                            child: Text(l10n.categoryDocuments),
                          ),
                          DropdownMenuItem(
                            value: 'archive',
                            child: Text(l10n.categoryArchives),
                          ),
                          if (PlatformCapabilities.supportsInstallersCategory)
                            DropdownMenuItem(
                              value: 'apk',
                              child: Text(l10n.categoryApks),
                            ),
                          DropdownMenuItem(
                            value: 'code',
                            child: Text(l10n.searchCategoryCode),
                          ),
                          DropdownMenuItem(
                            value: 'folder',
                            child: Text(l10n.searchCategoryFolders),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _category = v);
                            _onFilterOptionChanged();
                          }
                        },
                      ),
                    FilterChip(
                      label: const Text('Aa'),
                      selected: _caseSensitive,
                      onSelected: (v) {
                        setState(() => _caseSensitive = v);
                        _onFilterOptionChanged();
                      },
                    ),
                    FilterChip(
                      label: Text(l10n.showHiddenFiles),
                      selected: _includeHidden,
                      onSelected: (v) {
                        setState(() => _includeHidden = v);
                        _onFilterOptionChanged();
                      },
                    ),
                  ],
                ),
                if (!_grepMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minMbController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: l10n.minSizeMb,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _onQueryChanged,
                          onSubmitted: (_) => _runSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _maxMbController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: l10n.maxSizeMb,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _onQueryChanged,
                          onSubmitted: (_) => _runSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _daysController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: l10n.modifiedDaysAgo,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: _onQueryChanged,
                          onSubmitted: (_) => _runSearch(),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (!_grepMode &&
                  !widget.root.startsWith('vault://') &&
                  !widget.root.startsWith('archive://vault://')) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _indexStats != null ? Icons.bolt : Icons.bolt_outlined,
                          size: 16,
                          color: _indexStats != null
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _indexStats != null
                                ? l10n.fastIndexReady(_indexStats!.entryCount.toInt())
                                : l10n.fastIndexNotBuilt,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: _indexing ? null : _rebuildIndex,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            _indexing
                                ? l10n.fastIndexBuilding
                                : (_indexStats != null
                                    ? l10n.fastIndexRebuild
                                    : l10n.fastIndexBuild),
                          ),
                        ),
                        if (_indexStats != null)
                          IconButton(
                            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                            tooltip: l10n.fastIndexClear,
                            visualDensity: VisualDensity.compact,
                            onPressed: _indexing ? null : _clearIndex,
                          ),
                      ],
                    ),
                  ),
                ],
              const Divider(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _error!,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
              Expanded(
                child: _grepMode
                    ? (_searching
                        ? const Center(child: CircularProgressIndicator())
                        : _buildGrepResults(l10n))
                    : _buildFileResults(l10n, scheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: scheme.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildFileResults(AppLocalizations l10n, ColorScheme scheme) {
    final query = _queryController.text.trim();
    if (!_hasSearched &&
        !_searching &&
        _globalMatches.isEmpty &&
        _fileResults.isEmpty &&
        query.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.globalSources != null
                ? l10n.searchEnterQueryHint
                : l10n.searchFiles,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    if (_globalMatches.isEmpty && _fileResults.isEmpty && !_searching) {
      return Center(
        child: Text(l10n.noSearchResultsFor(_queryController.text)),
      );
    }

    final rows = <Widget>[];

    if (_globalMatches.bookmarks.isNotEmpty) {
      rows.add(_sectionHeader(l10n.bookmarks, scheme));
      for (final bm in _globalMatches.bookmarks) {
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.bookmark_outline,
            size: 18,
            color: Color(0xFFFB8C00),
          ),
          title: Text(bm.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            bm.path.isEmpty ? bm.root : '${bm.root}/${bm.path}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () =>
              Navigator.of(context).pop(AdvancedSearchSelection.bookmark(bm)),
        ));
      }
    }

    if (_globalMatches.quickTargets.isNotEmpty) {
      rows.add(_sectionHeader(l10n.localStorage, scheme));
      for (final t in _globalMatches.quickTargets) {
        rows.add(ListTile(
          dense: true,
          leading: Icon(
            Icons.folder_special_outlined,
            size: 18,
            color: scheme.primary,
          ),
          title: Text(
            t.displayName(l10n),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            t.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () =>
              Navigator.of(context).pop(AdvancedSearchSelection.quickTarget(t)),
        ));
      }
    }

    if (_globalMatches.unlockedVaults.isNotEmpty ||
        _globalMatches.lockedPinnedVaults.isNotEmpty) {
      rows.add(_sectionHeader(l10n.privacyFolders, scheme));
      for (final v in _globalMatches.unlockedVaults) {
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.lock_open_rounded,
            size: 18,
            color: Colors.indigo,
          ),
          title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            l10n.unlockedBadge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () => Navigator.of(context)
              .pop(AdvancedSearchSelection.unlockedVault(v)),
        ));
      }
      for (final v in _globalMatches.lockedPinnedVaults) {
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.lock_outline,
            size: 18,
            color: Colors.blueGrey,
          ),
          title: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            l10n.lockedBadge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () => Navigator.of(context)
              .pop(AdvancedSearchSelection.lockedPinnedVault(v)),
        ));
      }
    }

    if (_globalMatches.remotes.isNotEmpty) {
      rows.add(_sectionHeader(l10n.remote, scheme));
      for (final r in _globalMatches.remotes) {
        final detail = (r.host ?? r.endpoint ?? r.bucket ?? '').trim();
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.cloud_outlined,
            size: 18,
            color: Color(0xFF1E88E5),
          ),
          title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            detail.isEmpty ? r.kind.toUpperCase() : '${r.kind.toUpperCase()} · $detail',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () =>
              Navigator.of(context).pop(AdvancedSearchSelection.remote(r)),
        ));
      }
    }

    if (_globalMatches.pools.isNotEmpty) {
      rows.add(_sectionHeader(l10n.storagePools, scheme));
      for (final p in _globalMatches.pools) {
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.storage_outlined,
            size: 18,
            color: Colors.deepPurple,
          ),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'pool://${p.id}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () =>
              Navigator.of(context).pop(AdvancedSearchSelection.pool(p)),
        ));
      }
    }

    if (_globalMatches.history.isNotEmpty) {
      rows.add(_sectionHeader(l10n.recent, scheme));
      for (final h in _globalMatches.history) {
        final title =
            h.path.isEmpty ? h.root : h.path.split('/').last;
        rows.add(ListTile(
          dense: true,
          leading: const Icon(
            Icons.history,
            size: 18,
            color: Color(0xFF3949AB),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            h.path.isEmpty ? h.root : '${h.root}/${h.path}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () =>
              Navigator.of(context).pop(AdvancedSearchSelection.history(h)),
        ));
      }
    }

    if (_fileResults.isNotEmpty || _searching) {
      rows.add(_sectionHeader(l10n.searchFilesAndFolders, scheme));
      if (_searching) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.searchingFilesProgress,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      }
      for (final item in _fileResults) {
        final entry = item.entry;
        final isSecondaryRoot = item.root != widget.root;
        final pathText = isSecondaryRoot
            ? _joinFullPath(item.root, entry.path)
            : entry.path;
        final sizeText =
            entry.size != null ? ' · ${formatBytes(entry.size!)}' : '';
        rows.add(ListTile(
          dense: true,
          leading: Icon(
            entry.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
            size: 18,
            color: entry.isDir ? scheme.primary : null,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '$pathText$sizeText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () => Navigator.of(context).pop(
            AdvancedSearchSelection.entry(entry, root: item.root),
          ),
        ));
      }
    }

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _buildGrepResults(AppLocalizations l10n) {
    if (_grepResults.isEmpty) {
      return Center(
        child: Text(
          _hasSearched
              ? l10n.noSearchResultsFor(_queryController.text)
              : l10n.grepContentSearch,
        ),
      );
    }
    return ListView.separated(
      itemCount: _grepResults.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final hit = _grepResults[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.find_in_page_outlined, size: 18),
          title: Text(
            '${hit.path}:${hit.lineNumber}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          subtitle: Text(
            hit.lineText.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
          ),
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(
              MaterialPageRoute(
                builder: (_) => TextEditorPage(
                  root: widget.root,
                  path: hit.path,
                  fileName: hit.name,
                  readOnly: widget.readOnly,
                  initialLine: hit.lineNumber,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
