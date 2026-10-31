import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';

/// Result of picking a destination folder.
class PickedFolder {
  final String root;
  final String relPath;

  const PickedFolder({required this.root, required this.relPath});

  String get path => relPath.isEmpty ? root : '$root/$relPath';
}

/// Minimal folder browser over the same VFS API the file list uses.
///
/// The system picker cannot return an arbitrary writable path, and the
/// destination must be reachable through our own backend, so navigation is
/// built from `listDir`.
class FolderPickerDialog extends StatefulWidget {
  final String title;
  final String initialRoot;
  final String initialPath;
  final String? confirmLabel;

  const FolderPickerDialog({
    super.key,
    required this.title,
    required this.initialRoot,
    this.initialPath = '',
    this.confirmLabel,
  });

  static Future<PickedFolder?> show(
    BuildContext context, {
    required String title,
    required String initialRoot,
    String initialPath = '',
    String? confirmLabel,
  }) {
    return showDialog<PickedFolder>(
      context: context,
      builder: (_) => FolderPickerDialog(
        title: title,
        initialRoot: initialRoot,
        initialPath: initialPath,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  late String _root;
  late String _relPath;
  List<EntryItem> _folders = const [];
  bool _loading = false;
  String? _error;
  bool _showHidden = false;
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  String? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    _relPath = widget.initialPath;
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedFolder = null;
    });
    try {
      final entries = await listDir(root: _root, path: _relPath);
      final folders = entries
          .map((e) => EntryItem(e))
          .where((e) => e.isDir && (_showHidden || !e.hidden))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _folders = folders;
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

  void _open(String name) {
    setState(() {
      _relPath = _relPath.isEmpty ? name : '$_relPath/$name';
      _selectedFolder = null;
      _filterQuery = '';
      _filterController.clear();
    });
    _load();
  }

  bool get _canGoUp {
    if (_relPath.isNotEmpty) return true;
    if (isNativeRoot(_root)) {
      final parts = _root.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      return parts.length > 1 || (parts.length == 1 && !RegExp(r'^[a-zA-Z]:$').hasMatch(parts.first));
    }
    return false;
  }

  void _up() {
    if (_relPath.isNotEmpty) {
      final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
      segments.removeLast();
      setState(() {
        _relPath = segments.join('/');
        _selectedFolder = null;
        _filterQuery = '';
        _filterController.clear();
      });
      _load();
      return;
    }
    if (isNativeRoot(_root)) {
      final isWindows = _root.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(_root);
      final parts = _root.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (parts.length > 1) {
        parts.removeLast();
        final newRoot = isWindows ? parts.join('\\') : '/${parts.join('/')}';
        setState(() {
          _root = newRoot;
          _relPath = '';
          _selectedFolder = null;
          _filterQuery = '';
          _filterController.clear();
        });
        _load();
      } else if (parts.length == 1 && !isWindows) {
        setState(() {
          _root = '/';
          _relPath = '';
          _selectedFolder = null;
          _filterQuery = '';
          _filterController.clear();
        });
        _load();
      }
    }
  }

  Future<void> _createNewFolder() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            hintText: 'e.g. Documents',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              Navigator.of(ctx).pop(val.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          // An empty name used to leave the dialog open with no hint about
          // why nothing happened.
          ListenableBuilder(
            listenable: nameController,
            builder: (ctx, _) => FilledButton(
              onPressed: nameController.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(ctx).pop(nameController.text.trim()),
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    );
    nameController.dispose();

    if (name != null && name.isNotEmpty) {
      try {
        final target = _relPath.isEmpty ? name : '$_relPath/$name';
        await createDir(root: _root, path: target);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create folder: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  String get _currentPath => _relPath.isEmpty ? _root : '$_root/$_relPath';

  @override
  Widget build(BuildContext context) {
    final quickTargets = PlatformPaths.quickTargets()
        .where((t) => isNativeRoot(t.root))
        .toList();

    return AlertDialog(
      title: Text(widget.title),
      actionsOverflowButtonSpacing: 6,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
        child: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quickTargets.isNotEmpty)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final target in quickTargets)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          label: Text(target.name, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            setState(() {
                              _root = target.root;
                              _relPath = target.relPath;
                              _filterQuery = '';
                              _filterController.clear();
                            });
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Parent folder',
                  onPressed: _canGoUp ? _up : null,
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _currentPath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Path copied to clipboard')),
                      );
                    },
                    child: Tooltip(
                      message: 'Click to copy path',
                      child: Text(
                        _currentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off, size: 18),
                  tooltip: _showHidden ? 'Hide hidden folders' : 'Show hidden folders',
                  onPressed: () {
                    setState(() => _showHidden = !_showHidden);
                    _load();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'New Folder',
                  onPressed: _createNewFolder,
                ),
              ],
            ),
            const Divider(height: 1),
            if (_folders.length > 5 || _filterQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: 'Filter subfolders...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _filterQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              setState(() {
                                _filterQuery = '';
                                _filterController.clear();
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (v) => setState(() => _filterQuery = v),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Cannot read this folder: $_error',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _folders.isEmpty
                          ? const Center(
                              child: Text(
                                'No subfolders',
                                style: TextStyle(fontSize: 12),
                              ),
                            )
                          : () {
                              final filtered = _filterQuery.isEmpty
                                  ? _folders
                                  : _folders
                                      .where((f) => f.name.toLowerCase().contains(_filterQuery.toLowerCase()))
                                      .toList();
                              if (filtered.isEmpty) {
                                return const Center(
                                  child: Text(
                                    'No matching subfolders',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                );
                              }
                              return ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final folder = filtered[index];
                                  final isHidden = folder.hidden;
                                  final isSelected = _selectedFolder == folder.name;
                                  return ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                                    leading: Icon(
                                      isHidden ? Icons.folder_outlined : Icons.folder,
                                      size: 20,
                                      color: isHidden
                                          ? Colors.grey
                                          : (isSelected ? Theme.of(context).colorScheme.primary : Colors.amber),
                                    ),
                                    title: Text(
                                      folder.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: isHidden ? TextStyle(color: Theme.of(context).colorScheme.outline) : null,
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.chevron_right, size: 20),
                                      tooltip: 'Open',
                                      onPressed: () => _open(folder.name),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedFolder = isSelected ? null : folder.name;
                                      });
                                    },
                                  );
                                },
                              );
                            }(),
            ),
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Picking a folder that just failed to list would hand the caller a
          // path it cannot use.
          onPressed: _loading || _error != null
              ? null
              : () {
                  final effectiveRel = _selectedFolder != null
                      ? (_relPath.isEmpty ? _selectedFolder! : '$_relPath/$_selectedFolder')
                      : _relPath;
                  Navigator.of(context).pop(
                    PickedFolder(root: _root, relPath: effectiveRel),
                  );
                },
          child: Text(() {
            if (_selectedFolder != null) {
              final label = widget.confirmLabel;
              if (label != null && label.contains('上传')) {
                return '上传 "$_selectedFolder"';
              }
              if (label != null && label.toLowerCase().contains('upload')) {
                return 'Upload "$_selectedFolder"';
              }
              return '选择 "$_selectedFolder"';
            }
            return widget.confirmLabel ?? 'Use this folder';
          }()),
        ),
      ],
    );
  }
}
