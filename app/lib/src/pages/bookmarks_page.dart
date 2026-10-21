import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/storage_service.dart';
import 'browser_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<BookmarkDto> _bookmarks = [];
  List<RemoteConfigDto> _remotes = [];
  bool _loading = true;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    final bms = await StorageService.instance.getBookmarks();
    final rems = await StorageService.instance.getRemotes();
    if (mounted) {
      setState(() {
        _bookmarks = bms;
        _remotes = rems;
        _loading = false;
      });
    }
  }

  List<BookmarkDto> get _visibleBookmarks {
    if (_searchQuery.trim().isEmpty) return _bookmarks;
    final query = _searchQuery.toLowerCase();
    return _bookmarks
        .where((b) =>
            b.name.toLowerCase().contains(query) ||
            b.path.toLowerCase().contains(query) ||
            _rootLabel(b.root).toLowerCase().contains(query))
        .toList();
  }

  /// Root shown in the subtitle: remote ids mean nothing to a user, so show
  /// the connection name when it is known.
  String _rootLabel(String root) {
    if (root.startsWith('remote://')) {
      final id = root.substring('remote://'.length);
      for (final r in _remotes) {
        if (r.id == id) return 'remote://${r.name}';
      }
    }
    return root;
  }

  void _copyBookmarkPath(BookmarkDto b) {
    final full = '${_rootLabel(b.root)}${b.path}';
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied path: $full')),
    );
  }

  void _openBookmark(BookmarkDto bm) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: bm.root,
          initialPath: bm.path,
        ),
      ),
    ).then((_) => _loadBookmarks());
  }

  Future<void> _renameBookmark(BookmarkDto bm) async {
    final ctrl = TextEditingController(text: bm.name);
    final String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename Bookmark'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Bookmark Name',
              border: OutlineInputBorder(),
            ),
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
    if (newName != null && newName.isNotEmpty && newName != bm.name) {
      await StorageService.instance.renameBookmark(
        id: bm.id,
        newName: newName,
        root: bm.root,
        path: bm.path,
      );
      _loadBookmarks();
    }
  }

  Future<void> _deleteBookmark(BookmarkDto bm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Bookmark'),
        content: Text('Remove "${bm.name}" from bookmarks?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    await StorageService.instance.deleteBookmark(bm.id);
    await _loadBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${bm.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await StorageService.instance.addBookmark(
              name: bm.name,
              root: bm.root,
              path: bm.path,
            );
            _loadBookmarks();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_bookmarks.isNotEmpty)
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search, size: 20),
              tooltip: _showSearch ? 'Close Search' : 'Search Bookmarks',
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
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadBookmarks,
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
                        hintText: 'Filter bookmarks...',
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
              onRefresh: _loadBookmarks,
              child: _visibleBookmarks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty ? 'No bookmarks saved yet' : 'No matching bookmarks',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'In the file browser, tap the bookmark icon on any folder to add it here for quick access.'
                                  : 'Nothing matches "$_searchQuery".',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _visibleBookmarks.length,
                      itemBuilder: (ctx, i) {
                        final b = _visibleBookmarks[i];
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
                                color: Colors.amber.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.bookmark, size: 16, color: Colors.amber),
                            ),
                            title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            subtitle: Text(
                              '${_rootLabel(b.root)}${b.path}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined, size: 15),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  tooltip: 'Copy Path',
                                  onPressed: () => _copyBookmarkPath(b),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  tooltip: 'Rename',
                                  onPressed: () => _renameBookmark(b),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                  tooltip: 'Remove',
                                  onPressed: () => _deleteBookmark(b),
                                ),
                                const Icon(Icons.chevron_right, size: 16),
                              ],
                            ),
                            onTap: () => _openBookmark(b),
                            onLongPress: () => _copyBookmarkPath(b),
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
