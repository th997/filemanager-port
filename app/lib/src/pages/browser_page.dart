import 'package:flutter/material.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';

enum SortField { name, size, modified }

class BrowserPage extends StatefulWidget {
  final String initialRoot;
  final String initialPath;

  const BrowserPage({
    super.key,
    required this.initialRoot,
    this.initialPath = '',
  });

  @override
  State<BrowserPage> createState() => BrowserPageState();
}

class BrowserPageState extends State<BrowserPage> {
  late String _root;
  late String _relPath;
  List<EntryItem> _entries = [];
  bool _loading = false;
  String? _error;
  CapabilitiesDto? _capabilities;

  bool _isGrid = false;
  bool _showHidden = false;
  SortField _sortField = SortField.name;
  bool _sortAsc = true;
  final String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    _relPath = widget.initialPath;
    _load();
  }

  void navigateTo(String root, String relPath) {
    setState(() {
      _root = root;
      _relPath = relPath;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final caps = getCapabilities(root: _root);
      final rawEntries = await listDir(root: _root, path: _relPath);
      final items = rawEntries.map((e) => EntryItem(e)).toList();

      if (mounted) {
        setState(() {
          _capabilities = caps;
          _entries = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _navigateUp() {
    if (_relPath.isEmpty) return;
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return;
    segments.removeLast();
    setState(() {
      _relPath = segments.join('/');
    });
    _load();
  }

  void _openEntry(EntryItem item) {
    if (item.isDir) {
      final next = _relPath.isEmpty ? item.name : '$_relPath/${item.name}';
      setState(() {
        _relPath = next;
      });
      _load();
    } else {
      _showFileInfo(item);
    }
  }

  void _showFileInfo(EntryItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(item.icon, color: item.iconColor(ctx)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Path', item.path),
            _infoRow('Size', item.formattedSize),
            _infoRow('Modified', item.formattedModified),
            _infoRow('Type', item.isDir ? 'Directory' : 'File'),
            _infoRow('Hidden', item.hidden ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
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

  List<EntryItem> get _filteredAndSortedEntries {
    var list = _entries.where((e) {
      if (!_showHidden && e.hidden) return false;
      if (_filterQuery.isNotEmpty &&
          !e.name.toLowerCase().contains(_filterQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      if (a.isDir != b.isDir) {
        return a.isDir ? -1 : 1;
      }
      int cmp = 0;
      switch (_sortField) {
        case SortField.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortField.size:
          final sa = a.size ?? BigInt.zero;
          final sb = b.size ?? BigInt.zero;
          cmp = sa.compareTo(sb);
          break;
        case SortField.modified:
          final ma = a.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          final mb = b.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
          cmp = ma.compareTo(mb);
          break;
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              segments.isEmpty ? _root : segments.last,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              _relPath.isEmpty ? _root : '$_root/$_relPath',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            tooltip: _isGrid ? 'List view' : 'Grid view',
            onPressed: () => setState(() => _isGrid = !_isGrid),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options',
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'toggle_hidden') {
                setState(() => _showHidden = !_showHidden);
              } else if (val == 'sort_name') {
                setState(() {
                  if (_sortField == SortField.name) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortField = SortField.name;
                    _sortAsc = true;
                  }
                });
              } else if (val == 'sort_size') {
                setState(() {
                  if (_sortField == SortField.size) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortField = SortField.size;
                    _sortAsc = false;
                  }
                });
              } else if (val == 'sort_date') {
                setState(() {
                  if (_sortField == SortField.modified) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortField = SortField.modified;
                    _sortAsc = false;
                  }
                });
              }
            },
            itemBuilder: (ctx) => [
              CheckedPopupMenuItem<String>(
                value: 'toggle_hidden',
                checked: _showHidden,
                child: const Text('Show hidden files'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'sort_name',
                child: Text('Sort by Name ${_sortField == SortField.name ? (_sortAsc ? '▲' : '▼') : ''}'),
              ),
              PopupMenuItem<String>(
                value: 'sort_size',
                child: Text('Sort by Size ${_sortField == SortField.size ? (_sortAsc ? '▲' : '▼') : ''}'),
              ),
              PopupMenuItem<String>(
                value: 'sort_date',
                child: Text('Sort by Date ${_sortField == SortField.modified ? (_sortAsc ? '▲' : '▼') : ''}'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPathBar(segments),
          _buildCapabilitiesBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildPathBar(List<String> segments) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 20),
            tooltip: 'Up one level',
            onPressed: _relPath.isNotEmpty ? _navigateUp : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      if (_relPath.isNotEmpty) {
                        setState(() => _relPath = '');
                        _load();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        'Root',
                        style: TextStyle(
                          color: _relPath.isEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: _relPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                    InkWell(
                      onTap: () {
                        final next = segments.sublist(0, i + 1).join('/');
                        if (next != _relPath) {
                          setState(() => _relPath = next);
                          _load();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          segments[i],
                          style: TextStyle(
                            color: i == segments.length - 1
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: i == segments.length - 1 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesBar() {
    final caps = _capabilities;
    if (caps == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: Row(
        children: [
          Text(
            'Capabilities: ',
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          _capChip('read', caps.read),
          _capChip('write', caps.write),
          _capChip('rename', caps.rename),
          _capChip('copy', caps.copy),
          _capChip('mkdir', caps.mkdir),
          _capChip('remove', caps.remove),
          const Spacer(),
          Text(
            '${_filteredAndSortedEntries.length} items',
            style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _capChip(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: enabled ? Colors.green.shade700 : Colors.grey,
          fontWeight: enabled ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load directory',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final list = _filteredAndSortedEntries;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Directory is empty',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 110,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: list.length,
        itemBuilder: (ctx, i) {
          final item = list[i];
          return InkWell(
            onTap: () => _openEntry(item),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 36, color: item.iconColor(ctx)),
                  const SizedBox(height: 6),
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.formattedSize,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final item = list[i];
        return ListTile(
          dense: true,
          leading: Icon(item.icon, color: item.iconColor(ctx), size: 28),
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: item.isDir ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${item.formattedSize}  •  ${item.formattedModified}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: item.isDir ? const Icon(Icons.chevron_right, size: 18) : null,
          onTap: () => _openEntry(item),
        );
      },
    );
  }
}
