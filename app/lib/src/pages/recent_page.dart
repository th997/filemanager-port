import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/storage_service.dart';
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

  /// Filtering by title or full location, since either is what a user
  /// remembers about a past visit.
  List<HistoryDto> get _visibleHistory {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _history;
    return _history
        .where((h) =>
            _displayTitle(h).toLowerCase().contains(query) ||
            h.path.toLowerCase().contains(query) ||
            _rootLabel(h.root).toLowerCase().contains(query))
        .toList();
  }

  Future<void> _loadHistory() async {
    final hist = await StorageService.instance.getHistory();
    final rems = await StorageService.instance.getRemotes();
    if (mounted) {
      setState(() {
        _history = hist;
        _remotes = rems;
        _loading = false;
      });
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
    await StorageService.instance.removeHistoryEntry(root: h.root, path: h.path);
    await _loadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$title"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            // Re-record the visit, then put it back where it was in the list.
            await StorageService.instance.recordHistory(root: h.root, path: h.path);
            await _loadHistory();
            if (!mounted) return;
            setState(() {
              if (index >= 0 && index < _history.length) {
                final restored = _history.removeAt(_history.length - 1);
                _history.insert(index, restored);
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
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirm != true) return;
    await StorageService.instance.clearHistory();
    await _loadHistory();
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

  String _displayTitle(HistoryDto h) {
    if (h.path.isEmpty) return h.root;
    final segments = h.path.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isNotEmpty ? segments.last : h.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_history.isNotEmpty) ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search, size: 20),
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
            icon: const Icon(Icons.refresh, size: 20),
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
                    child: _visibleHistory.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _history.isEmpty ? Icons.history : Icons.search_off,
                                          size: 56,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _history.isEmpty ? 'No recent browsing history' : 'No matching locations',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _history.isEmpty
                                              ? 'Directories and files you browse will show up here.'
                                              : 'Nothing matches "$_searchQuery".',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _visibleHistory.length,
                            itemBuilder: (ctx, i) {
                              final h = _visibleHistory[i];
                              final title = _displayTitle(h);
                              final rootLabel = _rootLabel(h.root);
                              final sub = h.path.isEmpty ? rootLabel : '$rootLabel/${h.path}';

                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                                  minTileHeight: 40,
                                  minLeadingWidth: 24,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                  leading: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.history, size: 16, color: Colors.indigo),
                                  ),
                                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                  subtitle: Text(
                                    sub,
                                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _relativeTime(h.visitedMillis.toInt()),
                                        style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.copy_outlined, size: 15),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                        tooltip: 'Copy Path',
                                        onPressed: () => _copyHistoryPath(h),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                        tooltip: 'Bookmark Location',
                                        onPressed: () => _bookmarkHistory(h, title),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                        tooltip: 'Remove',
                                        onPressed: () => _removeEntry(h, title),
                                      ),
                                      const Icon(Icons.chevron_right, size: 16),
                                    ],
                                  ),
                                  onTap: () => _openHistory(h),
                                  onLongPress: () => _copyHistoryPath(h),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
