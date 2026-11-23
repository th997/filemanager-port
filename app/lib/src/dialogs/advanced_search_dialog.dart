import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../models/entry_item.dart';
import '../pages/text_editor_page.dart';
import '../rust/api/file_manager.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../rust/api/search.dart';
import '../rust/api/vault.dart';
import '../services/platform_capabilities.dart';
import '../services/platform_paths.dart';
import '../services/task_service.dart';
import '../services/vault_service.dart';

/// Optional metadata sources for Global Search (bookmarks, quick folders,
/// privacy vaults, remotes, and browsing history).
class GlobalSearchSources {
  final List<BookmarkDto> bookmarks;
  final List<HistoryDto> history;
  final List<RemoteConfigDto> remotes;
  final List<QuickTarget> quickTargets;
  final List<UnlockedVaultDto> unlockedVaults;
  final List<PinnedVaultEntry> lockedPinnedVaults;

  const GlobalSearchSources({
    this.bookmarks = const [],
    this.history = const [],
    this.remotes = const [],
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
  final List<HistoryDto> history;

  const GlobalSearchMatches({
    this.bookmarks = const [],
    this.quickTargets = const [],
    this.unlockedVaults = const [],
    this.lockedPinnedVaults = const [],
    this.remotes = const [],
    this.history = const [],
  });

  bool get isEmpty =>
      bookmarks.isEmpty &&
      quickTargets.isEmpty &&
      unlockedVaults.isEmpty &&
      lockedPinnedVaults.isEmpty &&
      remotes.isEmpty &&
      history.isEmpty;
}

/// Pure matcher for filtering local metadata (bookmarks, quick folders, vaults,
/// remotes, and recent history) synchronously while the disk search runs.
class GlobalSearchMatcher {
  static GlobalSearchMatches match({
    required GlobalSearchSources sources,
    required String query,
    String matchMode = 'contains',
    bool caseSensitive = false,
    String category = 'all',
    bool hasSizeFilter = false,
    AppLocalizations? l10n,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty ||
        hasSizeFilter ||
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

  Timer? _debounce;
  int _searchSeq = 0;
  bool _hasSearched = false;
  bool _searching = false;
  String? _error;

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
    if (_category != 'all' || widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshGlobalMatches();
        _runSearch();
      });
    }
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

  bool get _hasAnyFilter =>
      _queryController.text.trim().isNotEmpty ||
      _category != 'all' ||
      _hasSizeFilter ||
      _daysController.text.trim().isNotEmpty;

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
      l10n: l10n,
    );
    setState(() => _globalMatches = matches);
  }

  void _onQueryChanged(String _) {
    _refreshGlobalMatches();
    if (_grepMode) return;
    _debounce?.cancel();
    if (!_hasAnyFilter) {
      _searchSeq++;
      setState(() {
        _fileResults = const [];
        _searching = false;
        _hasSearched = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  void _onFilterOptionChanged() {
    _refreshGlobalMatches();
    if (!_grepMode && (_hasSearched || _hasAnyFilter)) {
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
    final seq = ++_searchSeq;
    _refreshGlobalMatches();

    setState(() {
      _searching = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      if (_grepMode) {
        final hits = await widget.grepTextFilesFn(
          root: widget.root,
          path: widget.relPath,
          pattern: _queryController.text,
          useRegex: _matchMode == 'regex',
          caseSensitive: _caseSensitive,
          includeHidden: _includeHidden,
          maxMatches: 300,
        );
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _grepResults = hits;
          _fileResults = const [];
          _searching = false;
        });
        return;
      }

      final minMb = double.tryParse(_minMbController.text.trim());
      final maxMb = double.tryParse(_maxMbController.text.trim());
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

      for (var i = 0; i < scopes.length; i++) {
        if (combined.length >= 500) break;
        final scope = scopes[i];
        try {
          final res = await widget.searchEntriesFn(
            root: scope.root,
            path: scope.relPath,
            options: options,
          );
          if (!mounted || seq != _searchSeq) return;
          for (final dto in res) {
            final isVirtual = scope.root.startsWith('remote://') ||
                scope.root.startsWith('vault://');
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

      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _fileResults = combined;
        _grepResults = const [];
        _searching = false;
      });
    } catch (e) {
      if (mounted && seq == _searchSeq) {
        setState(() {
          _error = '$e';
          _searching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

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
                          _error = null;
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
                          child: Text(l10n.searchCategoryAll),
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
                        onChanged: (_) => _refreshGlobalMatches(),
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
                        onChanged: (_) => _refreshGlobalMatches(),
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
                        onSubmitted: (_) => _runSearch(),
                      ),
                    ),
                  ],
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
            '${hit.name}:${hit.lineNumber}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          subtitle: Text(
            hit.lineText.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
          ),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
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
