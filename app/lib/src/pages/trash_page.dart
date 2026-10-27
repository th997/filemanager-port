import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';

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
          content: Text('Could not load the Recycle Bin: $e'),
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
        title: const Text('Recycled Item Details'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Name', name),
              _detailRow('Type', item.isDir ? 'Folder' : 'File'),
              _detailRow('Size', '${_formatSize(item.size)} (${item.size} bytes)'),
              _detailRow('Deleted', '$dateStr (${_deletedAgo(item)})'),
              const SizedBox(height: 6),
              const Text('Original Path:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                      tooltip: 'Copy path',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.originalPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Path copied to clipboard')),
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
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Restore'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _restore(item);
            },
          ),
        ],
      ),
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
    try {
      await StorageService.instance.restoreTrashItem(item.id);
    } catch (e) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not restore "$name": $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored "$name"')),
      );
    }
  }

  Future<void> _delete(TrashItemDto item) async {
    final name = _displayName(item);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text('Permanently delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await StorageService.instance.deleteTrashItem(item.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete "$name": $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$name"')),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Recycle Bin'),
        content: Text(
          'Permanently delete all ${_items.length} items '
          '(${_formatSize(_totalSize)})? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Empty All'),
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
              content: Text('Could not empty recycle bin: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recycle bin emptied')),
        );
      }
    }
  }

  Future<void> _restoreAll() async {
    final count = _items.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore All Items'),
        content: Text('Restore all $count items to their original locations?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore All'),
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
                  ? 'Restored $successCount of $count items'
                  : 'Restored $successCount of $count. Still in trash: '
                      '${failures.take(3).join(', ')}${failures.length > 3 ? '…' : ''}',
            ),
            backgroundColor: failures.isEmpty ? null : scheme.warning,
          ),
        );
      }
    }
  }

  /// Bytes held by everything in the bin, so the header answers "how much
  /// space can I get back?" before deleting anything.
  BigInt get _totalSize =>
      _items.fold(BigInt.zero, (sum, item) => sum + item.size);

  @override
  Widget build(BuildContext context) {
    final displayedItems = (_searchQuery.isEmpty
        ? [..._items]
        : _items
            .where((item) =>
                item.originalPath.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                _displayName(item).toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList())
      ..sort((a, b) => b.deletedMillis.compareTo(a.deletedMillis));

    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _restoringTotal > 0
              ? 'Restoring $_restoringDone / $_restoringTotal…'
              : _items.isEmpty
                  ? 'Recycle Bin'
                  : MediaQuery.sizeOf(context).width < 500
                      ? 'Recycle Bin (${_items.length})'
                      : 'Recycle Bin • ${_items.length} items, ${_formatSize(_totalSize)}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_items.isNotEmpty) ...[
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? 'Close Search' : 'Search Trash',
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
              tooltip: 'Restore All Items',
              onPressed: _restoringTotal > 0 ? null : _restoreAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Empty Recycle Bin',
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
                        hintText: 'Filter recycled files...',
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
                                  title: _items.isEmpty ? 'Recycle Bin is empty' : 'No matching items in trash',
                                  subtitle: _items.isEmpty ? 'Deleted files and folders will appear here.' : null,
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
                                        tooltip: 'Restore',
                                        onPressed: _restoringTotal > 0
                                            ? null
                                            : () => _restore(item),
                                      ),
                                      AppIconButton(
                                        icon: Icons.delete_forever,
                                        color: Theme.of(context).colorScheme.error,
                                        tooltip: 'Delete Permanently',
                                        onPressed: _restoringTotal > 0
                                            ? null
                                            : () => _delete(item),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showItemDetails(item),
                                  onLongPress: () {
                                    Clipboard.setData(ClipboardData(text: item.originalPath));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Original path copied to clipboard')),
                                    );
                                  },
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
