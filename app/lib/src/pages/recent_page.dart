import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dialogs/history_retention_dialog.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/platform_paths.dart';
import '../services/pool_service.dart';
import '../services/preferences_service.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../services/external_file_service.dart';

class RecentPage extends StatefulWidget {
  final ExternalPickRequest? pickRequest;
  final Future<List<HistoryDto>> Function()? loadHistoryOverride;
  final Future<void> Function(int days)? applyRetentionOverride;

  const RecentPage({
    super.key,
    this.pickRequest,
    this.loadHistoryOverride,
    this.applyRetentionOverride,
  });

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  List<HistoryDto> _history = [];
  List<RemoteConfigDto> _remotes = [];
  bool _loading = true;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _retentionDays = PreferencesService.instance.historyRetentionDays;

  @override
  void initState() {
    super.initState();
    PreferencesService.historyRetentionDaysNotifier
        .addListener(_onRetentionChanged);
    _loadHistory();
  }

  void _onRetentionChanged() {
    if (!mounted) return;
    setState(() {
      _retentionDays = PreferencesService.historyRetentionDaysNotifier.value;
    });
  }

  @override
  void dispose() {
    PreferencesService.historyRetentionDaysNotifier
        .removeListener(_onRetentionChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<HistoryDto>? _visibleHistoryCache;
  List<HistoryDto>? _lastHistory;
  List<RemoteConfigDto>? _lastRemotes;
  String? _lastSearchQuery;

  /// Filtering by title or full location, since either is what a user
  /// remembers about a past visit.
  List<HistoryDto> get _visibleHistory {
    if (_visibleHistoryCache != null &&
        identical(_lastHistory, _history) &&
        identical(_lastRemotes, _remotes) &&
        _lastSearchQuery == _searchQuery) {
      return _visibleHistoryCache!;
    }
    final source = widget.pickRequest != null
        ? _history
            .where((h) => !PlatformPaths.isInsidePrivateInbox(h.root))
            .toList()
        : _history;
    final query = _searchQuery.trim().toLowerCase();
    final list = query.isEmpty
        ? source
        : source
            .where((h) =>
                _displayTitle(h).toLowerCase().contains(query) ||
                h.path.toLowerCase().contains(query) ||
                _rootLabel(h.root).toLowerCase().contains(query))
            .toList();
    _lastHistory = _history;
    _lastRemotes = _remotes;
    _lastSearchQuery = _searchQuery;
    _visibleHistoryCache = list;
    return list;
  }

  Future<void> _loadHistory() async {
    try {
      if (widget.loadHistoryOverride != null) {
        final history = await widget.loadHistoryOverride!();
        if (!mounted) return;
        setState(() {
          _history = history;
          _remotes = const [];
          if (_history.isEmpty) {
            _showSearch = false;
            _searchQuery = '';
            _searchController.clear();
          }
          _loading = false;
        });
        return;
      }
      final results = await Future.wait([
        StorageService.instance.getHistory(),
        StorageService.instance.getRemotes(),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as List<HistoryDto>;
        _remotes = results[1] as List<RemoteConfigDto>;
        if (_history.isEmpty) {
          _showSearch = false;
          _searchQuery = '';
          _searchController.clear();
        }
        _loading = false;
      });
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotLoadRecent('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Remote ids are opaque; show the connection name when it is known.
  String _rootLabel(String root) {
    if (PlatformPaths.isPrivateInboxRoot(root)) {
      return AppLocalizations.of(context).quickInbox;
    }
    if (root.startsWith('remote://')) {
      final id = root.substring('remote://'.length);
      for (final r in _remotes) {
        if (r.id == id) return 'remote://${r.name}';
      }
    }
    if (root.startsWith('pool://')) {
      final id = root.substring('pool://'.length);
      final pool = PoolService.instance.findById(id);
      if (pool != null) return 'pool://${pool.name}';
    }
    return root;
  }

  void _copyHistoryPath(HistoryDto h) {
    final rootLabel = _rootLabel(h.root);
    final full = h.path.isEmpty ? rootLabel : '$rootLabel/${h.path}';
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copiedPathValue(full))),
    );
  }

  Future<void> _bookmarkHistory(HistoryDto h, String title) async {
    try {
      await StorageService.instance.addBookmark(
        name: title,
        root: h.root,
        path: h.path,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).bookmarkedName(title))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).failedToBookmark('$e')), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  /// Removes a single location from recent history.
  ///
  /// No confirmation dialog: a stray tap costs one entry, and the snackbar
  /// offers an undo.
  Future<void> _removeEntry(HistoryDto h, String title) async {
    final index = _history.indexOf(h);
    setState(() {
      _history = _history.where((item) => !(item.root == h.root && item.path == h.path)).toList();
    });
    try {
      await StorageService.instance.removeHistoryEntry(root: h.root, path: h.path);
    } catch (e) {
      if (!mounted) return;
      _loadHistory();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotRemoveItem(title, '$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).removedName(title)),
        action: SnackBarAction(
          label: AppLocalizations.of(context).undo,
          onPressed: () async {
            try {
              // Re-record the visit, then put it back where it was in the list.
              // The restored row is found by root+path: the database orders by
              // visit time, so assuming it lands last picks the wrong entry.
              await StorageService.instance.recordHistory(root: h.root, path: h.path);
              await _loadHistory();
              if (!mounted) return;
              setState(() {
                final found = _history.indexWhere(
                  (e) => e.root == h.root && e.path == h.path,
                );
                if (found >= 0 && index >= 0) {
                  final reordered = List<HistoryDto>.of(_history);
                  final restored = reordered.removeAt(found);
                  reordered.insert(index.clamp(0, reordered.length), restored);
                  _history = reordered;
                }
              });
            } catch (_) {}
          },
        ),
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).clearHistory),
        content: Text(AppLocalizations.of(context).clearHistoryConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).clear),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    // Keep the list so a mis-tap does not cost every recorded location.
    final cleared = List<HistoryDto>.of(_history);
    try {
      await StorageService.instance.clearHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotClearHistory('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await _loadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).clearedRecentLocations(cleared.length)),
        action: SnackBarAction(
          label: AppLocalizations.of(context).undo,
          onPressed: () async {
            try {
              for (final h in cleared.reversed) {
                await StorageService.instance.recordHistory(root: h.root, path: h.path);
              }
              await _loadHistory();
            } catch (_) {}
          },
        ),
      ),
    );
  }

  /// Compact relative time, so the list reads as "when", not a timestamp.
  String _relativeTime(int millis) {
    final l10n = AppLocalizations.of(context);
    final then = DateTime.fromMillisecondsSinceEpoch(millis);
    final diff = DateTime.now().difference(then);
    if (diff.inMinutes < 1) return l10n.timeJustNow;
    if (diff.inHours < 1) return l10n.timeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return l10n.timeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
    return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
  }

  void _openHistory(HistoryDto h) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: h.root,
          initialPath: h.path,
          pickRequest: widget.pickRequest,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      Navigator.of(context).pop(picked);
      return;
    }
    _loadHistory();
  }

  void _showHistoryActionSheet(HistoryDto h, String title) {
    HapticFeedback.mediumImpact();
    final rootLabel = _rootLabel(h.root);
    final sub = h.path.isEmpty ? rootLabel : '$rootLabel/${h.path}';

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
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  sub,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(AppLocalizations.of(context).open),
                onTap: () {
                  Navigator.pop(ctx);
                  _openHistory(h);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(AppLocalizations.of(context).copyPath),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyHistoryPath(h);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(AppLocalizations.of(context).bookmarkLocation),
                onTap: () {
                  Navigator.pop(ctx);
                  _bookmarkHistory(h, title);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context).removeFromHistory,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeEntry(h, title);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _displayTitle(HistoryDto h) {
    if (h.path.isEmpty) return _rootLabel(h.root);
    final segments = h.path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.last : h.path;
  }

  Future<void> _configureRetention() async {
    final picked = await showHistoryRetentionDialog(
      context,
      currentDays: _retentionDays,
    );
    if (picked == null || !mounted) return;
    final applyFn = widget.applyRetentionOverride ??
        StorageService.instance.applyHistoryRetention;
    await applyFn(picked);
    if (!mounted) return;
    setState(() {
      _retentionDays = PreferencesService.instance.historyRetentionDays;
    });
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          picked == 0
              ? l10n.historyRetentionUpdatedOff
              : l10n.historyRetentionUpdatedDays(picked),
        ),
      ),
    );
    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleHistory = _visibleHistory;
    final isCompact = MediaQuery.sizeOf(context).width < 480;
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.recentHistory),
        actions: [
          if (_history.isNotEmpty) ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? l10n.closeSearch : l10n.searchHistory,
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
            if (!isCompact)
              TextButton(
                onPressed: _clearHistory,
                child: Text(l10n.clear, style: const TextStyle(fontSize: 12)),
              ),
          ],
          TextButton.icon(
            key: const ValueKey('recent_retention_btn'),
            icon: const Icon(Icons.schedule_outlined, size: 16),
            label: Text(
              _retentionDays == 0
                  ? l10n.historyRetentionDisabledShort
                  : l10n.historyRetentionDaysShort(_retentionDays),
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: _configureRetention,
          ),
          if (isCompact)
            PopupMenuButton<String>(
              onSelected: (action) {
                if (action == 'refresh') _loadHistory();
                if (action == 'clear') _clearHistory();
              },
              itemBuilder: (_) => [
                if (_history.isNotEmpty)
                  PopupMenuItem(
                    value: 'clear',
                    child: ListTile(
                      leading: const Icon(Icons.delete_sweep_outlined, size: 18),
                      title: Text(l10n.clear),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: const Icon(Icons.refresh, size: 18),
                    title: Text(l10n.refresh),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: _loadHistory,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch && _history.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).filterRecentHint,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: visibleHistory.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: AppEmptyState(
                                  icon: _history.isEmpty && _retentionDays == 0
                                      ? Icons.history_toggle_off_rounded
                                      : (_history.isEmpty ? Icons.history : Icons.search_off),
                                  title: _history.isEmpty && _retentionDays == 0
                                      ? l10n.historyDisabledTitle
                                      : (_history.isEmpty ? l10n.noRecentHistory : l10n.noMatchingLocations),
                                  subtitle: _history.isEmpty && _retentionDays == 0
                                      ? l10n.historyDisabledSubtitle
                                      : (_history.isEmpty
                                          ? l10n.recentEmptyHint
                                          : l10n.nothingMatchesQuery(_searchQuery)),
                                  action: _history.isEmpty && _retentionDays == 0
                                      ? FilledButton.tonal(
                                          onPressed: _configureRetention,
                                          child: Text(l10n.historyRetentionChange),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: AppUiTokens.pagePadding,
                            itemCount: visibleHistory.length,
                            itemBuilder: (ctx, i) {
                              final h = visibleHistory[i];
                              final title = _displayTitle(h);
                              final rootLabel = _rootLabel(h.root);
                              final sub = h.path.isEmpty ? rootLabel : '$rootLabel/${h.path}';

                              return Card(
                                child: ListTile(
                                  leading: const AppCircleBadge(
                                    icon: Icons.history,
                                    color: Colors.indigo,
                                  ),
                                  title: Text(title),
                                  subtitle: Text(
                                    sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  // The time plus three icons overflowed on
                                  // narrow phones; the actions live in a menu.
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _relativeTime(h.visitedMillis.toInt()),
                                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: AppLocalizations.of(context).actionsTooltip,
                                        icon: const Icon(Icons.more_vert, size: 16),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          fixedSize: const Size.square(AppUiTokens.buttonTargetSize),
                                        ),
                                        onSelected: (v) {
                                          if (v == 'copy') _copyHistoryPath(h);
                                          if (v == 'bookmark') _bookmarkHistory(h, title);
                                          if (v == 'remove') _removeEntry(h, title);
                                        },
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'copy',
                                            child: Row(
                                              children: [
                                                Icon(Icons.copy_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text(AppLocalizations.of(context).copyPath),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'bookmark',
                                            child: Row(
                                              children: [
                                                Icon(Icons.bookmark_add_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text(AppLocalizations.of(context).bookmarkLocation),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'remove',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: Theme.of(context).colorScheme.error,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  AppLocalizations.of(context).remove,
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.error,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Icon(Icons.chevron_right, size: 16),
                                    ],
                                  ),
                                  onTap: () => _openHistory(h),
                                  onLongPress: () => _showHistoryActionSheet(h, title),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
