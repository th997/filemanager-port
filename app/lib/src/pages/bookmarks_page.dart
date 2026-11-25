import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/preferences_service.dart';
import '../services/platform_paths.dart';
import '../services/pool_service.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../services/external_file_service.dart';

enum BookmarkSortMode { custom, nameAsc, nameDesc }

class BookmarksPage extends StatefulWidget {
  final ExternalPickRequest? pickRequest;

  const BookmarksPage({super.key, this.pickRequest});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  static const _prefOrderKey = 'bookmarks.custom_order';
  static const _prefSortKey = 'bookmarks.sort_mode';

  List<BookmarkDto> _bookmarks = [];
  List<RemoteConfigDto> _remotes = [];
  bool _loading = true;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  BookmarkSortMode _sortMode = BookmarkSortMode.custom;

  @override
  void initState() {
    super.initState();
    final savedSort = PreferencesService.instance.getString(_prefSortKey);
    if (savedSort == 'nameAsc') _sortMode = BookmarkSortMode.nameAsc;
    if (savedSort == 'nameDesc') _sortMode = BookmarkSortMode.nameDesc;
    _loadBookmarks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyCustomOrder() {
    final raw = PreferencesService.instance.getString(_prefOrderKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        final orderList = decoded.map((e) => e.toString()).toList();
        final map = {for (final b in _bookmarks) b.id: b};
        final sorted = <BookmarkDto>[];
        for (final id in orderList) {
          if (map.containsKey(id)) {
            sorted.add(map.remove(id)!);
          }
        }
        sorted.addAll(map.values);
        _bookmarks = sorted;
      } catch (_) {}
    }
  }

  void _saveCustomOrder() {
    final ids = _bookmarks.map((b) => b.id).toList();
    PreferencesService.instance.setString(_prefOrderKey, jsonEncode(ids));
  }

  Future<void> _loadBookmarks({
    String? remappedOldId,
    String? matchRoot,
    String? matchPath,
    String? matchName,
  }) async {
    try {
      final results = await Future.wait([
        StorageService.instance.getBookmarks(),
        StorageService.instance.getRemotes(),
      ]);
      if (!mounted) return;
      final loadedBookmarks = results[0] as List<BookmarkDto>;
      if (remappedOldId != null &&
          matchRoot != null &&
          matchPath != null &&
          matchName != null) {
        final raw = PreferencesService.instance.getString(_prefOrderKey);
        if (raw != null && raw.isNotEmpty) {
          try {
            final orderList =
                (jsonDecode(raw) as List<dynamic>).map((e) => e.toString()).toList();
            final idx = orderList.indexOf(remappedOldId);
            if (idx >= 0) {
              BookmarkDto? replacement;
              for (final b in loadedBookmarks) {
                if (b.root == matchRoot && b.path == matchPath && b.name == matchName) {
                  replacement = b;
                  break;
                }
              }
              if (replacement != null) {
                orderList[idx] = replacement.id;
                PreferencesService.instance
                    .setString(_prefOrderKey, jsonEncode(orderList));
              }
            }
          } catch (_) {}
        }
      }
      setState(() {
        _bookmarks = loadedBookmarks;
        _remotes = results[1] as List<RemoteConfigDto>;
        _applyCustomOrder();
        if (_bookmarks.isEmpty) {
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
          content: Text(AppLocalizations.of(context).couldNotLoadBookmarks('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<BookmarkDto>? _visibleBookmarksCache;
  List<BookmarkDto>? _lastBookmarks;
  List<RemoteConfigDto>? _lastRemotes;
  String? _lastSearchQuery;
  BookmarkSortMode? _lastSortMode;

  List<BookmarkDto> get _visibleBookmarks {
    if (_visibleBookmarksCache != null &&
        identical(_lastBookmarks, _bookmarks) &&
        identical(_lastRemotes, _remotes) &&
        _lastSearchQuery == _searchQuery &&
        _lastSortMode == _sortMode) {
      return _visibleBookmarksCache!;
    }
    final source = widget.pickRequest != null
        ? _bookmarks
            .where((b) => !PlatformPaths.isInsidePrivateInbox(b.root))
            .toList()
        : _bookmarks;
    final query = _searchQuery.trim().toLowerCase();
    final list = query.isEmpty
        ? [...source]
        : source
            .where((b) =>
                b.name.toLowerCase().contains(query) ||
                b.path.toLowerCase().contains(query) ||
                _rootLabel(b.root).toLowerCase().contains(query))
            .toList();

    if (_sortMode == BookmarkSortMode.nameAsc) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sortMode == BookmarkSortMode.nameDesc) {
      list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }

    _lastBookmarks = _bookmarks;
    _lastRemotes = _remotes;
    _lastSearchQuery = _searchQuery;
    _lastSortMode = _sortMode;
    _visibleBookmarksCache = list;
    return list;
  }

  /// Root shown in the subtitle: remote ids mean nothing to a user, so show
  /// the connection name when it is known.
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

  void _copyBookmarkPath(BookmarkDto b) {
    final full = b.path.isEmpty
        ? _rootLabel(b.root)
        : '${_rootLabel(b.root)}/${b.path}';
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copiedPathValue(full))),
    );
  }

  void _openBookmark(BookmarkDto bm) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: bm.root,
          initialPath: bm.path,
          pickRequest: widget.pickRequest,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      Navigator.of(context).pop(picked);
      return;
    }
    _loadBookmarks();
  }

  void _showBookmarkActionSheet(BookmarkDto b) {
    HapticFeedback.mediumImpact();
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
                  b.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  b.path.isEmpty ? _rootLabel(b.root) : '${_rootLabel(b.root)}/${b.path}',
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
                  _openBookmark(b);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(AppLocalizations.of(context).copyPath),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyBookmarkPath(b);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(AppLocalizations.of(context).rename),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameBookmark(b);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context).remove,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteBookmark(b);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _renameBookmark(BookmarkDto bm) async {
    final oldName = bm.name;
    final dotIndex = oldName.lastIndexOf('.');
    final selectionEnd = (dotIndex > 0 && !oldName.startsWith('.')) ? dotIndex : oldName.length;
    final ctrl = TextEditingController(text: oldName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: selectionEnd);
    final String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).renameBookmark),
          actionsOverflowButtonSpacing: 8,
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).bookmarkNameLabel,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) {
                  Navigator.of(ctx).pop(v.trim());
                }
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
            // An empty name used to close the dialog and then do nothing.
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
    if (newName != null && newName.isNotEmpty && newName != bm.name) {
      try {
        await StorageService.instance.renameBookmark(
          id: bm.id,
          oldName: bm.name,
          newName: newName,
          root: bm.root,
          path: bm.path,
        );
        await _loadBookmarks(
          remappedOldId: bm.id,
          matchRoot: bm.root,
          matchPath: bm.path,
          matchName: newName,
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRenameBookmark('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// Removes without a confirmation dialog; the snackbar carries the undo.
  Future<void> _deleteBookmark(BookmarkDto bm) async {
    final original = _bookmarks;
    setState(() {
      _bookmarks = _bookmarks.where((b) => b.id != bm.id).toList();
    });
    try {
      await StorageService.instance.deleteBookmark(bm.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _bookmarks = original);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotRemoveBookmark('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 4),
        content: Text(AppLocalizations.of(context).removedName(bm.name)),
        action: SnackBarAction(
          label: AppLocalizations.of(context).undo,
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
                  content: Text(AppLocalizations.of(context).couldNotRestoreBookmark('$e')),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
            }
            await _loadBookmarks(
              remappedOldId: bm.id,
              matchRoot: bm.root,
              matchPath: bm.path,
              matchName: bm.name,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visibleBookmarks = _visibleBookmarks;
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookmarks),
        actions: [
          if (_bookmarks.isNotEmpty) ...[
            PopupMenuButton<BookmarkSortMode>(
              icon: const Icon(Icons.sort),
              tooltip: l10n.bookmarkSortModeTooltip,
              onSelected: (mode) {
                setState(() {
                  _sortMode = mode;
                  PreferencesService.instance.setString(_prefSortKey, mode.name);
                });
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: BookmarkSortMode.custom,
                  child: Row(
                    children: [
                      Icon(
                        Icons.drag_handle,
                        size: 18,
                        color: _sortMode == BookmarkSortMode.custom
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.bookmarkSortCustom),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: BookmarkSortMode.nameAsc,
                  child: Row(
                    children: [
                      Icon(
                        Icons.sort_by_alpha,
                        size: 18,
                        color: _sortMode == BookmarkSortMode.nameAsc
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.bookmarkSortNameAsc),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: BookmarkSortMode.nameDesc,
                  child: Row(
                    children: [
                      Icon(
                        Icons.sort_by_alpha,
                        size: 18,
                        color: _sortMode == BookmarkSortMode.nameDesc
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.bookmarkSortNameDesc),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? l10n.closeSearch : l10n.searchBookmarks,
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
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refresh,
            onPressed: _loadBookmarks,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch && _bookmarks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).filterBookmarksHint,
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
              child: visibleBookmarks.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: AppEmptyState(
                            icon: Icons.bookmark_border,
                            title: _searchQuery.isEmpty ? AppLocalizations.of(context).noBookmarksSaved : AppLocalizations.of(context).noMatchingBookmarks,
                            subtitle: _searchQuery.isEmpty
                                ? AppLocalizations.of(context).bookmarksEmptyHint
                                : AppLocalizations.of(context).nothingMatchesQuery(_searchQuery),
                          ),
                        ),
                      ),
                    )
                  : widget.pickRequest == null &&
                          _searchQuery.isEmpty &&
                          _sortMode == BookmarkSortMode.custom
                      ? ReorderableListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: AppUiTokens.pagePadding,
                          buildDefaultDragHandles: false,
                          itemCount: visibleBookmarks.length,
                          onReorderItem: (oldIndex, newIndex) {
                            HapticFeedback.lightImpact();
                            setState(() {
                              final updated = List<BookmarkDto>.of(_bookmarks);
                              final item = updated.removeAt(oldIndex);
                              updated.insert(newIndex, item);
                              _bookmarks = updated;
                              _visibleBookmarksCache = null;
                              _saveCustomOrder();
                            });
                          },
                          itemBuilder: (ctx, i) => _buildBookmarkCard(
                            ctx,
                            visibleBookmarks[i],
                            dragIndex: i,
                          ),
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: AppUiTokens.pagePadding,
                          itemCount: visibleBookmarks.length,
                          itemBuilder: (ctx, i) => _buildBookmarkCard(
                            ctx,
                            visibleBookmarks[i],
                          ),
                        ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildBookmarkCard(
    BuildContext context,
    BookmarkDto b, {
    int? dragIndex,
  }) {
    final l10n = AppLocalizations.of(context);
    final menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: l10n.bookmarkActions,
      onSelected: (action) {
        switch (action) {
          case 'copy':
            _copyBookmarkPath(b);
            break;
          case 'rename':
            _renameBookmark(b);
            break;
          case 'remove':
            _deleteBookmark(b);
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.rename),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.copyPath),
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
                color: Theme.of(ctx).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.remove,
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      key: ValueKey(b.id),
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
        trailing: dragIndex != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  menu,
                  ReorderableDragStartListener(
                    index: dragIndex,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      child: Icon(Icons.drag_handle, color: Colors.grey),
                    ),
                  ),
                ],
              )
            : menu,
        onTap: () => _openBookmark(b),
        onLongPress: () => _showBookmarkActionSheet(b),
      ),
    );
  }
}
