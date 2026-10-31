import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';

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
    String? initialPath,
  }) {
    String root;
    String path;
    if (initialRoot != null) {
      root = initialRoot;
      path = initialPath ?? '';
    } else {
      final recentDirs = PreferencesService.instance.getRecentUploadDirs();
      if (recentDirs.isNotEmpty) {
        final split = splitPathToRootAndRel(recentDirs.first);
        root = split.root;
        path = split.relPath;
      } else {
        root = PlatformPaths.defaultRoot();
        path = initialPath ?? '';
      }
    }
    return showDialog<PickedFiles>(
      context: context,
      builder: (_) => FilePickerDialog(
        title: title,
        initialRoot: root,
        initialPath: path,
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

  /// Items the list is actually showing. "Select All" has to work on these:
  /// with a filter typed it used to select every file/folder, so the
  /// upload included items the user never saw.
  List<EntryItem> get _visibleFolders {
    final query = _filterQuery.toLowerCase();
    return query.isEmpty
        ? _folders
        : _folders.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  List<EntryItem> get _visibleFiles {
    final query = _filterQuery.toLowerCase();
    return query.isEmpty
        ? _files
        : _files.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

  List<EntryItem> get _visibleItems => [..._visibleFolders, ..._visibleFiles];

  void _selectAll() {
    setState(() {
      final visible = _visibleItems;
      final allSelected = visible.isNotEmpty &&
          visible.every((item) => _selectedPaths.contains(_fullPath(item)));
      if (allSelected) {
        for (final item in visible) {
          _selectedPaths.remove(_fullPath(item));
        }
      } else {
        for (final item in visible) {
          _selectedPaths.add(_fullPath(item));
        }
      }
    });
  }

  String get _currentPath => _relPath.isEmpty ? _root : '$_root/$_relPath';

  void _navigateTo(String fullPath) {
    final split = splitPathToRootAndRel(fullPath);
    setState(() {
      _root = split.root;
      _relPath = split.relPath;
      _selectedPaths.clear();
      _filterQuery = '';
      _filterController.clear();
    });
    _load();
  }

  Future<void> _switchToSystemPicker() async {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final initialDir = _currentPath.isNotEmpty && Directory(_currentPath).existsSync()
        ? _currentPath
        : null;
    try {
      final files = await openFiles(
        initialDirectory: initialDir,
        confirmButtonText: isZh ? '上传' : 'Upload',
      );
      if (files.isEmpty || !mounted) return;

      final byParent = <String, List<String>>{};
      for (final f in files) {
        final split = splitNativeFile(f.path);
        byParent.putIfAbsent(split.srcRoot, () => []).add(split.name);
        PreferencesService.instance.addRecentUploadDir(split.srcRoot);
      }

      if (byParent.isEmpty || !mounted) return;
      final first = byParent.entries.first;
      Navigator.pop(
        context,
        PickedFiles(root: first.key, paths: first.value),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final recentDirs = PreferencesService.instance.getRecentUploadDirs();
    final quickTargets = PlatformPaths.quickTargets()
        .where((t) => t.root.startsWith('/') || t.root.contains(':'))
        .toList();

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          TextButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: Text(isZh ? '系统选择器' : 'System Picker'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
            onPressed: _switchToSystemPicker,
          ),
        ],
      ),
      actionsOverflowButtonSpacing: 6,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 500),
        child: SizedBox(
          width: double.maxFinite,
          height: 500,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (recentDirs.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.history, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    isZh ? '最近目录:' : 'Recent:',
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final dir in recentDirs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          avatar: const Icon(Icons.folder_outlined, size: 13),
                          label: Text(
                            shortDirectoryName(dir),
                            style: const TextStyle(fontSize: 11),
                          ),
                          tooltip: dir,
                          onPressed: () => _navigateTo(dir),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
            ],
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
                            [..._folders, ..._files].any((f) => f.hidden && _fullPath(f) == p));
                      }
                    });
                    _load();
                  },
                ),
                if (_visibleItems.isNotEmpty)
                  TextButton.icon(
                    icon: Icon(
                      _visibleItems.every((f) => _selectedPaths.contains(_fullPath(f)))
                          ? Icons.deselect
                          : Icons.select_all,
                      size: 16,
                    ),
                    label: Text(
                      _visibleItems.every((f) => _selectedPaths.contains(_fullPath(f)))
                          ? 'Deselect All'
                          : 'Select All',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _selectAll,
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
                                    final isSelected = _selectedPaths.contains(_fullPath(folder));
                                    return ListTile(
                                      dense: true,
                                      leading: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => _toggleSelect(folder),
                                          ),
                                          Icon(
                                            folder.hidden ? Icons.folder_outlined : Icons.folder,
                                            color: folder.hidden ? Colors.grey : Colors.amber,
                                          ),
                                        ],
                                      ),
                                      title: Text(
                                        folder.name,
                                        style: folder.hidden
                                            ? TextStyle(color: Theme.of(context).colorScheme.outline)
                                            : null,
                                      ),
                                      subtitle: Text(
                                        Localizations.localeOf(context).languageCode == 'zh' ? '文件夹' : 'Folder',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.chevron_right, size: 18),
                                        tooltip: 'Open folder',
                                        onPressed: () => _openFolder(folder.name),
                                      ),
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
          label: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '上传 (${_selectedPaths.length})'
                : 'Upload (${_selectedPaths.length})',
          ),
          onPressed: _selectedPaths.isEmpty
              ? null
              : () {
                  final dirToSave = _relPath.isEmpty ? _root : joinNative(_root, _relPath);
                  PreferencesService.instance.addRecentUploadDir(dirToSave);
                  Navigator.of(context).pop(
                    PickedFiles(root: _root, paths: _selectedPaths.toList()),
                  );
                },
        ),
      ],
    );
  }
}
