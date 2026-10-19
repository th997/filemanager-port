import 'package:flutter/material.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/platform_paths.dart';

/// Result of picking files to upload.
class PickedFiles {
  final String root;
  final List<String> paths;

  const PickedFiles({required this.root, required this.paths});
}

/// In-app file picker over local VFS to pick files for uploading to remote storage.
class FilePickerDialog extends StatefulWidget {
  final String title;
  final String initialRoot;
  final String initialPath;

  const FilePickerDialog({
    super.key,
    required this.title,
    required this.initialRoot,
    this.initialPath = '',
  });

  static Future<PickedFiles?> show(
    BuildContext context, {
    required String title,
    String? initialRoot,
    String initialPath = '',
  }) {
    final root = initialRoot ?? PlatformPaths.defaultRoot();
    return showDialog<PickedFiles>(
      context: context,
      builder: (_) => FilePickerDialog(
        title: title,
        initialRoot: root,
        initialPath: initialPath,
      ),
    );
  }

  @override
  State<FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<FilePickerDialog> {
  late String _root;
  late String _relPath;
  List<EntryItem> _folders = const [];
  List<EntryItem> _files = const [];
  final Set<String> _selectedPaths = {};
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
      final all = entries.map((e) => EntryItem(e)).where((e) => !e.hidden).toList();
      final folders = all.where((e) => e.isDir).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final files = all.where((e) => !e.isDir).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _folders = folders;
          _files = files;
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

  void _openFolder(String name) {
    setState(() {
      _relPath = _relPath.isEmpty ? name : '$_relPath/$name';
      _selectedPaths.clear();
    });
    _load();
  }

  void _up() {
    if (_relPath.isEmpty) return;
    final segments = _relPath.split('/').where((s) => s.isNotEmpty).toList();
    segments.removeLast();
    setState(() {
      _relPath = segments.join('/');
      _selectedPaths.clear();
    });
    _load();
  }

  String _fullPath(EntryItem item) {
    return _relPath.isEmpty ? item.name : '$_relPath/${item.name}';
  }

  void _toggleSelect(EntryItem item) {
    final p = _fullPath(item);
    setState(() {
      if (_selectedPaths.contains(p)) {
        _selectedPaths.remove(p);
      } else {
        _selectedPaths.add(p);
      }
    });
  }

  String get _currentPath => _relPath.isEmpty ? _root : '$_root/$_relPath';

  @override
  Widget build(BuildContext context) {
    final quickTargets = PlatformPaths.quickTargets()
        .where((t) => t.root.startsWith('/') || t.root.contains(':'))
        .toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 480,
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
                              _selectedPaths.clear();
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
                  onPressed: _relPath.isEmpty ? null : _up,
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)))
                      : (_folders.isEmpty && _files.isEmpty)
                          ? const Center(child: Text('Folder is empty', style: TextStyle(color: Colors.grey)))
                          : ListView(
                              children: [
                                for (final folder in _folders)
                                  ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.folder, color: Colors.amber),
                                    title: Text(folder.name),
                                    trailing: const Icon(Icons.chevron_right, size: 16),
                                    onTap: () => _openFolder(folder.name),
                                  ),
                                for (final file in _files)
                                  ListTile(
                                    dense: true,
                                    leading: Checkbox(
                                      value: _selectedPaths.contains(_fullPath(file)),
                                      onChanged: (_) => _toggleSelect(file),
                                    ),
                                    title: Text(file.name),
                                    subtitle: Text(file.formattedSize, style: const TextStyle(fontSize: 11)),
                                    onTap: () => _toggleSelect(file),
                                  ),
                              ],
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
        FilledButton.icon(
          icon: const Icon(Icons.upload, size: 18),
          label: Text('Upload (${_selectedPaths.length})'),
          onPressed: _selectedPaths.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    PickedFiles(root: _root, paths: _selectedPaths.toList()),
                  );
                },
        ),
      ],
    );
  }
}
