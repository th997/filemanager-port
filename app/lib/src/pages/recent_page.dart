import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
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
    final query = _searchQuery.trim().toLowerCase();
    final list = query.isEmpty
        ? _history
        : _history
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
      final results = await Future.wait([
        StorageService.instance.getHistory(),
        StorageService.instance.getRemotes(),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as List<HistoryDto>;
        _remotes = results[1] as List<RemoteConfigDto>;
        _loading = false;
      });
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load recent locations: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Remote ids are opaque; show the connection name when it is known.
  String _rootLabel(String root) {
    if (root.startsWith('remote://')) {
      final id = root.substring('remote://'.length);
      for (final r in _remotes) {
        if (r.id == id) return 'remote://${r.name}';
      }
    }
    return root;
  }

  void _copyHistoryPath(HistoryDto h) {
    final rootLabel = _rootLabel(h.root);
    final full = h.path.isEmpty ? rootLabel : '$rootLabel/${h.path}';
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied path: $full')),
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
          SnackBar(content: Text('Bookmarked "$title"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to bookmark: $e'), backgroundColor: Theme.of(context).colorScheme.error),
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
          content: Text('Could not remove "$title": $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$title"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
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
                final restored = _history.removeAt(found);
                _history.insert(index.clamp(0, _history.length), restored);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Remove all recent locations? Bookmarks are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
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
          content: Text('Could not clear history: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await _loadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared ${cleared.length} recent locations'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            for (final h in cleared.reversed) {
              await StorageService.instance.recordHistory(root: h.root, path: h.path);
            }
            await _loadHistory();
          },
        ),
      ),
    );
  }

  /// Compact relative time, so the list reads as "when", not a timestamp.
  String _relativeTime(int millis) {
    final then = DateTime.fromMillisecondsSinceEpoch(millis);
    final diff = DateTime.now().difference(then);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
  }

  void _openHistory(HistoryDto h) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: h.root,
          initialPath: h.path,
        ),
      ),
    ).then((_) => _loadHistory());
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
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openHistory(h);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Copy Path'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyHistoryPath(h);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Bookmark Location'),
                onTap: () {
                  Navigator.pop(ctx);
                  _bookmarkHistory(h, title);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Remove from History',
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
    if (h.path.isEmpty) return h.root;
    final segments = h.path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.last : h.path;
  }

  @override
  Widget build(BuildContext context) {
    final visibleHistory = _visibleHistory;
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Recent History'),
        actions: [
          if (_history.isNotEmpty) ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? 'Close Search' : 'Search History',
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
            TextButton(
              onPressed: _clearHistory,
              child: const Text('Clear', style: TextStyle(fontSize: 12)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Filter recent locations...',
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
                                  icon: _history.isEmpty ? Icons.history : Icons.search_off,
                                  title: _history.isEmpty ? 'No recent browsing history' : 'No matching locations',
                                  subtitle: _history.isEmpty
                                      ? 'Directories and files you browse will show up here.'
                                      : 'Nothing matches "$_searchQuery".',
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
                                        tooltip: 'Actions',
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
                                          const PopupMenuItem(
                                            value: 'copy',
                                            child: Row(
                                              children: [
                                                Icon(Icons.copy_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text('Copy Path'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'bookmark',
                                            child: Row(
                                              children: [
                                                Icon(Icons.bookmark_add_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text('Bookmark Location'),
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
                                                  'Remove',
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
