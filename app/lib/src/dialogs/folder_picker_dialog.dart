import 'package:flutter/material.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
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

  @override
  void initState() {
    super.initState();
    _root = widget.initialRoot;
    _relPath = widget.initialPath;
    _load();
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
    });
    _load();
  }

  void _up() {
    if (_relPath.isEmpty) return;
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    segments.removeLast();
    setState(() => _relPath = segments.join('/'));
    _load();
  }

  String get _currentPath => _relPath.isEmpty ? _root : '$_root/$_relPath';

  @override
  Widget build(BuildContext context) {
    final quickTargets = PlatformPaths.quickTargets()
        .where((t) => t.root.startsWith('/'))
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
              ],
            ),
            const Divider(height: 1),
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
                          : ListView.builder(
                              itemCount: _folders.length,
                              itemBuilder: (context, index) {
                                final folder = _folders[index];
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
                            ),
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
