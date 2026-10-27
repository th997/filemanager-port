import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _showHidden = false;
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
      final all = entries
          .map((e) => EntryItem(e))
          .where((e) => _showHidden || !e.hidden)
          .toList();
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
      _selectedPaths.clear();
      _filterQuery = '';
      _filterController.clear();
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

  /// Files the list is actually showing. "Select All" has to work on these:
  /// with a filter typed it used to select every file in the folder, so the
  /// upload included files the user never saw.
  List<EntryItem> get _visibleFiles {
    final query = _filterQuery.toLowerCase();
    return query.isEmpty
        ? _files
        : _files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  void _selectAllFiles() {
    setState(() {
      final visible = _visibleFiles;
      final allSelected =
          visible.isNotEmpty && visible.every((f) => _selectedPaths.contains(_fullPath(f)));
      if (allSelected) {
        for (final f in visible) {
          _selectedPaths.remove(_fullPath(f));
        }
      } else {
        for (final f in visible) {
          _selectedPaths.add(_fullPath(f));
        }
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
      actionsOverflowButtonSpacing: 6,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 480),
        child: SizedBox(
          width: double.maxFinite,
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
                  onPressed: _relPath.isEmpty ? null : _up,
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
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(_showHidden ? Icons.visibility : Icons.visibility_off, size: 18),
                  tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
                  onPressed: () {
                    setState(() {
                      _showHidden = !_showHidden;
                      if (!_showHidden) {
                        _selectedPaths.removeWhere((p) =>
                            _files.any((f) => f.hidden && _fullPath(f) == p));
                      }
                    });
                    _load();
                  },
                ),
                if (_visibleFiles.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(
                      _visibleFiles.every((f) => _selectedPaths.contains(_fullPath(f)))
                          ? Icons.deselect
                          : Icons.select_all,
                      size: 16,
                    ),
                    label: Text(
                      _visibleFiles.every((f) => _selectedPaths.contains(_fullPath(f)))
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _selectAllFiles,
                  ),
              ],
            ),
            const Divider(height: 1),
            if ((_folders.length + _files.length > 5) || _filterQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: TextField(
                  controller: _filterController,
                  decoration: InputDecoration(
                    hintText: 'Filter files & folders...',
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
                      // A dead-end error forced the user to cancel and reopen
                      // the dialog to retry, as the folder picker already does.
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 12)),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry'),
                                onPressed: _load,
                              ),
                            ],
                          ),
                        )
                      : (_folders.isEmpty && _files.isEmpty)
                          ? const Center(child: Text('Folder is empty', style: TextStyle(color: Colors.grey)))
                          : () {
                              final query = _filterQuery.toLowerCase();
                              final displayedFolders = query.isEmpty
                                  ? _folders
                                  : _folders.where((f) => f.name.toLowerCase().contains(query)).toList();
                              final displayedFiles = query.isEmpty
                                  ? _files
                                  : _files.where((f) => f.name.toLowerCase().contains(query)).toList();

                              if (displayedFolders.isEmpty && displayedFiles.isEmpty) {
                                return const Center(
                                  child: Text('No matching items', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                );
                              }

                              // Builder, not a children list: a folder with
                              // thousands of files otherwise builds every
                              // tile (and checkbox) up front.
                              return ListView.builder(
                                itemCount: displayedFolders.length + displayedFiles.length,
                                itemBuilder: (context, index) {
                                  if (index < displayedFolders.length) {
                                    final folder = displayedFolders[index];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        folder.hidden ? Icons.folder_outlined : Icons.folder,
                                        color: folder.hidden ? Colors.grey : Colors.amber,
                                      ),
                                      title: Text(
                                        folder.name,
                                        style: folder.hidden
                                            ? TextStyle(color: Theme.of(context).colorScheme.outline)
                                            : null,
                                      ),
                                      trailing: const Icon(Icons.chevron_right, size: 16),
                                      onTap: () => _openFolder(folder.name),
                                    );
                                  }
                                  final file = displayedFiles[index - displayedFolders.length];
                                  return ListTile(
                                    dense: true,
                                    leading: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Checkbox(
                                          value: _selectedPaths.contains(_fullPath(file)),
                                          onChanged: (_) => _toggleSelect(file),
                                        ),
                                        Icon(
                                          file.icon,
                                          color: file.hidden ? Colors.grey : file.iconColor(context),
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                    title: Text(
                                      file.name,
                                      style: file.hidden
                                          ? TextStyle(color: Theme.of(context).colorScheme.outline)
                                          : null,
                                    ),
                                    subtitle: Text(file.formattedSize, style: const TextStyle(fontSize: 11)),
                                    onTap: () => _toggleSelect(file),
                                  );
                                },
                              );
                            }(),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                '${_folders.length} folder${_folders.length == 1 ? "" : "s"}, ${_files.length} file${_files.length == 1 ? "" : "s"}'
                '${_selectedPaths.isNotEmpty ? " • ${_selectedPaths.length} selected" : ""}',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
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
