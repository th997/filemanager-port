import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'package:filemanager/l10n/app_localizations.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashItemDto> _items = [];
  bool _loading = true;
  bool _showSearch = false;
  /// Non-zero while "Restore All" is running, so the header can show progress
  /// instead of looking hung.
  int _restoringTotal = 0;
  int _restoringDone = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Only the first load blanks the page; a refresh keeps the list visible
    // so a restore does not flash a full-screen spinner.
    if (_items.isEmpty) setState(() => _loading = true);
    try {
      final items = await StorageService.instance.getTrashItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotLoadTrash('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _formatSize(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _deletedAgo(TrashItemDto item) {
    final then = DateTime.fromMillisecondsSinceEpoch(item.deletedMillis.toInt());
    final diff = DateTime.now().difference(then);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} d ago';
    return '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')}';
  }

  String _displayName(TrashItemDto item) {
    final parts = item.originalPath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? item.originalPath : parts.last;
  }

  void _showItemDetails(TrashItemDto item) {
    final name = _displayName(item);
    final then = DateTime.fromMillisecondsSinceEpoch(item.deletedMillis.toInt());
    final dateStr = '${then.year}-${then.month.toString().padLeft(2, '0')}-${then.day.toString().padLeft(2, '0')} '
        '${then.hour.toString().padLeft(2, '0')}:${then.minute.toString().padLeft(2, '0')}:${then.second.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).recycledItemDetails),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(AppLocalizations.of(context).nameLabel, name),
              _detailRow(AppLocalizations.of(context).typeLabel, item.isDir ? AppLocalizations.of(context).folderLabel : AppLocalizations.of(context).fileLabel),
              _detailRow(AppLocalizations.of(context).sizeLabel, AppLocalizations.of(context).yesBytes(_formatSize(item.size), '${item.size}')),
              _detailRow(AppLocalizations.of(context).taskDelete, '$dateStr (${_deletedAgo(item)})'),
              const SizedBox(height: 6),
              Text(AppLocalizations.of(context).originalPathColon, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        item.originalPath,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: AppLocalizations.of(context).copyPath,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.originalPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context).pathCopied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).close),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restore, size: 16),
            label: Text(AppLocalizations.of(context).restore),
            onPressed: () {
              Navigator.of(ctx).pop();
              _restore(item);
            },
          ),
        ],
      ),
    );
  }

  void _showTrashActionSheet(TrashItemDto item) {
    HapticFeedback.mediumImpact();
    final name = _displayName(item);

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
                  name.isEmpty ? item.originalPath : name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_formatSize(item.size)}  •  ${item.originalPath}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.restore, color: Theme.of(context).colorScheme.success),
                title: Text(AppLocalizations.of(context).restoreItem),
                onTap: () {
                  Navigator.pop(ctx);
                  _restore(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(AppLocalizations.of(context).viewDetails),
                onTap: () {
                  Navigator.pop(ctx);
                  _showItemDetails(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(AppLocalizations.of(context).copyOriginalPath),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: item.originalPath));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppLocalizations.of(context).originalPathCopied)),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context).deletePermanently,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _delete(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(TrashItemDto item) async {
    final name = _displayName(item);
    setState(() {
      // Replace the list instead of mutating it in place: the caches below
      // key on identity, and an in-place removeWhere left the old entries
      // on screen after a successful restore.
      _items = _items.where((i) => i.id != item.id).toList();
    });
    try {
      await StorageService.instance.restoreTrashItem(item.id);
    } catch (e) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRestoreNamed(name, '$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).restoredNamed(name))),
      );
    }
  }

  Future<void> _delete(TrashItemDto item) async {
    final name = _displayName(item);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deletePermanently),
        content: Text(AppLocalizations.of(context).permanentlyDeleteConfirm(name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _items = _items.where((i) => i.id != item.id).toList();
      });
      try {
        await StorageService.instance.deleteTrashItem(item.id);
      } catch (e) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).couldNotDeleteNamed(name, '$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).deletedItem(name))),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).emptyRecycleBin),
        content: Text(
          AppLocalizations.of(context).permanentlyDeleteAllTrash(_items.length, _formatSize(_totalSize))
,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).emptyAll),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await StorageService.instance.clearTrash();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).couldNotEmptyTrash('$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).recycleBinEmptied)),
        );
      }
    }
  }

  Future<void> _restoreAll() async {
    final count = _items.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).restoreAllItems),
        content: Text(AppLocalizations.of(context).restoreAllConfirm(count)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).restoreAll),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (mounted) setState(() => _restoringTotal = count);
      int successCount = 0;
      final failures = <String>[];
      // Restoring is one FFI round-trip per item; without a counter a large
      // bin looks frozen until the snackbar appears.
      if (mounted) setState(() => _restoringDone = 0);
      for (final item in List.of(_items)) {
        try {
          await StorageService.instance.restoreTrashItem(item.id);
          successCount++;
        } catch (_) {
          failures.add(_displayName(item));
        }
        if (mounted) setState(() => _restoringDone++);
      }
      if (mounted) setState(() => _restoringTotal = 0);
      _load();
      if (mounted) {
        final scheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failures.isEmpty
                  ? AppLocalizations.of(context).restoredCountOfTotal(successCount, count)
                  : AppLocalizations.of(context).restoredPartialTrash(
                          successCount, count, failures.length,
                          '${failures.take(3).join(', ')}${failures.length > 3 ? '…' : ''}'),
            ),
            backgroundColor: failures.isEmpty ? null : scheme.warning,
          ),
        );
      }
    }
  }

  List<TrashItemDto>? _displayedItemsCache;
  List<TrashItemDto>? _lastItems;
  String? _lastSearchQuery;
  BigInt? _cachedTotalSize;

  /// Bytes held by everything in the bin, so the header answers "how much
  /// space can I get back?" before deleting anything.
  BigInt get _totalSize {
    if (_cachedTotalSize != null && identical(_lastItems, _items)) {
      return _cachedTotalSize!;
    }
    _cachedTotalSize = _items.fold<BigInt>(BigInt.zero, (sum, item) => sum + item.size);
    return _cachedTotalSize!;
  }

  List<TrashItemDto> get _displayedItems {
    if (_displayedItemsCache != null &&
        identical(_lastItems, _items) &&
        _lastSearchQuery == _searchQuery) {
      return _displayedItemsCache!;
    }
    final q = _searchQuery.trim().toLowerCase();
    final list = (q.isEmpty
        ? [..._items]
        : _items
            .where((item) =>
                item.originalPath.toLowerCase().contains(q) ||
                _displayName(item).toLowerCase().contains(q))
            .toList())
      ..sort((a, b) => b.deletedMillis.compareTo(a.deletedMillis));
    _lastItems = _items;
    _lastSearchQuery = _searchQuery;
    _displayedItemsCache = list;
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final displayedItems = _displayedItems;

    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _restoringTotal > 0
              ? AppLocalizations.of(context).restoringProgress(_restoringDone, _restoringTotal)
              : _items.isEmpty
                  ? AppLocalizations.of(context).recycleBin
                  : MediaQuery.sizeOf(context).width < 500
                      ? '${AppLocalizations.of(context).recycleBin} (${_items.length})'
                      : AppLocalizations.of(context).recycleBinSummary(_items.length, _formatSize(_totalSize)),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_items.isNotEmpty) ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? AppLocalizations.of(context).closeSearch : AppLocalizations.of(context).searchTrash,
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
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: AppLocalizations.of(context).restoreAllItems,
              onPressed: _restoringTotal > 0 ? null : _restoreAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: AppLocalizations.of(context).emptyRecycleBin,
              // Emptying mid-restore deleted items the restore loop was
              // still working on, and left the final count wrong.
              onPressed: _restoringTotal > 0 ? null : _clearAll,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).filterRecycledHint,
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
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
                    onRefresh: _load,
                    child: displayedItems.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: AppEmptyState(
                                  icon: Icons.delete_outline,
                                  title: _items.isEmpty ? AppLocalizations.of(context).recycleBinIsEmpty : AppLocalizations.of(context).noMatchingItemsTrash,
                                  subtitle: _items.isEmpty ? AppLocalizations.of(context).trashEmptyHint : null,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: AppUiTokens.pagePadding,
                            itemCount: displayedItems.length,
                            itemBuilder: (ctx, i) {
                              final item = displayedItems[i];
                              final name = _displayName(item);

                              return Card(
                                child: ListTile(
                                  leading: AppCircleBadge(
                                    icon: item.isDir ? Icons.folder : Icons.insert_drive_file,
                                    color: item.isDir ? Colors.amber : Colors.blue,
                                  ),
                                  title: Text(
                                    name.isEmpty ? item.originalPath : name,
                                  ),
                                  subtitle: Text(
                                    '${_formatSize(item.size)}  •  deleted ${_deletedAgo(item)}  •  ${item.originalPath}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppIconButton(
                                        icon: Icons.restore,
                                        color: Theme.of(context).colorScheme.success,
                                        tooltip: AppLocalizations.of(context).restore,
                                        onPressed: _restoringTotal > 0
                                            ? null
                                            : () => _restore(item),
                                      ),
                                      AppIconButton(
                                        icon: Icons.delete_forever,
                                        color: Theme.of(context).colorScheme.error,
                                        tooltip: AppLocalizations.of(context).deletePermanently,
                                        onPressed: _restoringTotal > 0
                                            ? null
                                            : () => _delete(item),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showItemDetails(item),
                                  onLongPress: () => _showTrashActionSheet(item),
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
