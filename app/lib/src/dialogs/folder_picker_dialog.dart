import 'package:flutter/material.dart';

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

  const FolderPickerDialog({
    super.key,
    required this.title,
    required this.initialRoot,
    this.initialPath = '',
  });

  static Future<PickedFolder?> show(
    BuildContext context, {
    required String title,
    required String initialRoot,
    String initialPath = '',
  }) {
    return showDialog<PickedFolder>(
      context: context,
      builder: (_) => FolderPickerDialog(
        title: title,
        initialRoot: initialRoot,
        initialPath: initialPath,
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
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';

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
    });
    try {
      final entries = await listDir(root: _root, path: _relPath);
      final folders = entries
          .map((e) => EntryItem(e))
          .where((e) => e.isDir && !e.hidden)
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
      _filterQuery = '';
      _filterController.clear();
    });
    _load();
  }

  void _up() {
    if (_relPath.isEmpty) return;
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    segments.removeLast();
    setState(() {
      _relPath = segments.join('/');
      _filterQuery = '';
      _filterController.clear();
    });
    _load();
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
          FilledButton(
            onPressed: () {
              final val = nameController.text.trim();
              if (val.isNotEmpty) {
                Navigator.of(ctx).pop(val);
              }
            },
            child: const Text('Create'),
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
              backgroundColor: Colors.red,
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
      content: SizedBox(
        width: 420,
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
                            _root = target.root;
                            _relPath = target.relPath;
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
                  onPressed: _relPath.isEmpty ? null : _up,
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
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
                            child: Text(
                              'Cannot read this folder: $_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
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
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.folder, size: 20),
                                    title: Text(
                                      folder.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () => _open(folder.name),
                                  );
                                },
                              );
                            }(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            PickedFolder(root: _root, relPath: _relPath),
          ),
          child: const Text('Use this folder'),
        ),
      ],
    );
  }
}
