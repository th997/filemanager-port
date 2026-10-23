import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
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
    try {
      final bms = await StorageService.instance.getBookmarks();
      final rems = await StorageService.instance.getRemotes();
      if (!mounted) return;
      setState(() {
        _bookmarks = bms;
        _remotes = rems;
        _loading = false;
      });
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load bookmarks: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Sorted by name so the list is predictable between visits; the backend
  /// returns them in creation order.
  List<BookmarkDto> get _visibleBookmarks {
    final query = _searchQuery.trim().toLowerCase();
    final list = query.isEmpty
        ? [..._bookmarks]
        : _bookmarks
            .where((b) =>
                b.name.toLowerCase().contains(query) ||
                b.path.toLowerCase().contains(query) ||
                _rootLabel(b.root).toLowerCase().contains(query))
            .toList();
    list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return list;
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
    final full = b.path.isEmpty
        ? _rootLabel(b.root)
        : '${_rootLabel(b.root)}/${b.path}';
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
            // An empty name used to close the dialog and then do nothing.
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
    if (newName != null && newName.isNotEmpty && newName != bm.name) {
      try {
        await StorageService.instance.renameBookmark(
          id: bm.id,
          oldName: bm.name,
          newName: newName,
          root: bm.root,
          path: bm.path,
        );
        await _loadBookmarks();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not rename bookmark: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Removes without a confirmation dialog; the snackbar carries the undo.
  Future<void> _deleteBookmark(BookmarkDto bm) async {
    try {
      await StorageService.instance.deleteBookmark(bm.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not remove bookmark: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await _loadBookmarks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${bm.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            // Undo is the only way back from a delete; failing silently left
            // the bookmark gone with no hint that the restore did not work.
            try {
              await StorageService.instance.addBookmark(
                name: bm.name,
                root: bm.root,
                path: bm.path,
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not restore bookmark: $e'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
            await _loadBookmarks();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Bookmarks'),
        actions: [
          if (_bookmarks.isNotEmpty)
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
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
            icon: const Icon(Icons.refresh),
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
                            Icon(Icons.bookmark_border, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isEmpty ? 'No bookmarks saved yet' : 'No matching bookmarks',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'In the file browser, long-press a folder (or right-click it) and choose "Bookmark This Folder".'
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
                      padding: AppUiTokens.pagePadding,
                      itemCount: _visibleBookmarks.length,
                      itemBuilder: (ctx, i) {
                        final b = _visibleBookmarks[i];
                        return Card(
                          child: ListTile(
                            leading: const AppCircleBadge(
                              icon: Icons.bookmark,
                              color: Colors.amber,
                            ),
                            title: Text(b.name),
                            subtitle: Text(
                              b.path.isEmpty
                                  ? _rootLabel(b.root)
                                  : '${_rootLabel(b.root)}/${b.path}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIconButton(
                                  icon: Icons.copy_outlined,
                                  tooltip: 'Copy Path',
                                  onPressed: () => _copyBookmarkPath(b),
                                ),
                                const SizedBox(width: 4),
                                AppIconButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Rename',
                                  onPressed: () => _renameBookmark(b),
                                ),
                                const SizedBox(width: 4),
                                AppIconButton(
                                  icon: Icons.close,
                                  color: Colors.red,
                                  tooltip: 'Remove',
                                  onPressed: () => _deleteBookmark(b),
                                ),
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
      ),
    );
  }
}
