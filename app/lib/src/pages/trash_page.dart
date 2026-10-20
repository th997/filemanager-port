import 'package:flutter/material.dart';
import '../rust/api/metadata.dart';
import '../services/storage_service.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashItemDto> _items = [];
  bool _loading = true;
  bool _showSearch = false;
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
    setState(() => _loading = true);
    final items = await StorageService.instance.getTrashItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  String _formatSize(BigInt bytes) {
    final b = bytes.toInt();
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _displayName(TrashItemDto item) {
    final parts = item.originalPath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? item.originalPath : parts.last;
  }

  Future<void> _restore(TrashItemDto item) async {
    final name = _displayName(item);
    await StorageService.instance.restoreTrashItem(item.id);
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.instance.deleteTrashItem(item.id);
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
        content: const Text('Are you sure you want to permanently delete all items in the recycle bin?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Empty All'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await StorageService.instance.clearTrash();
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
      int successCount = 0;
      for (final item in List.of(_items)) {
        try {
          await StorageService.instance.restoreTrashItem(item.id);
          successCount++;
        } catch (_) {}
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $successCount of $count items')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedItems = _searchQuery.isEmpty
        ? _items
        : _items
            .where((item) =>
                item.originalPath.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                _displayName(item).toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
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
              onPressed: _restoreAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Empty Recycle Bin',
              onPressed: _clearAll,
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
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_outline, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        _items.isEmpty ? 'Recycle Bin is empty' : 'No matching items in trash',
                                        style: TextStyle(color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: displayedItems.length,
                            itemBuilder: (ctx, i) {
                              final item = displayedItems[i];
                              final name = _displayName(item);

                              return ListTile(
                                leading: Icon(
                                  item.isDir ? Icons.folder : Icons.insert_drive_file,
                                  color: item.isDir ? Colors.amber : Colors.blue,
                                ),
                                title: Text(name.isEmpty ? item.originalPath : name),
                                subtitle: Text(
                                  '${_formatSize(item.size)}  •  ${item.originalPath}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.restore, color: Colors.green),
                                      tooltip: 'Restore',
                                      onPressed: () => _restore(item),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                                      tooltip: 'Delete Permanently',
                                      onPressed: () => _delete(item),
                                    ),
                                  ],
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
