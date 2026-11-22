import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../models/entry_item.dart';
import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/vault_service.dart';
import 'vfs_picker_scaffold.dart';

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
  final bool includeUnlockedVaults;

  const FolderPickerDialog({
    super.key,
    required this.title,
    required this.initialRoot,
    this.initialPath = '',
    this.confirmLabel,
    this.includeUnlockedVaults = false,
  });

  static Future<PickedFolder?> show(
    BuildContext context, {
    required String title,
    String? initialRoot,
    String initialPath = '',
    String? confirmLabel,
    bool includeUnlockedVaults = false,
  }) {
    String root;
    String path;
    if (initialRoot != null) {
      root = initialRoot;
      path = initialPath;
    } else {
      final recentDirs = PreferencesService.instance.getRecentUploadDirs();
      if (recentDirs.isNotEmpty) {
        final split = PlatformPaths.splitPrivateInboxPath(recentDirs.first) ??
            splitPathToRootAndRel(recentDirs.first);
        root = split.root;
        path = split.relPath;
      } else {
        root = initialRoot ?? PlatformPaths.defaultRoot();
        path = initialPath;
      }
    }
    return showDialog<PickedFolder>(
      context: context,
      builder: (_) => FolderPickerDialog(
        title: title,
        initialRoot: root,
        initialPath: path,
        confirmLabel: confirmLabel,
        includeUnlockedVaults: includeUnlockedVaults,
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

  int _loadSeq = 0;

  Future<void> _load() async {
    final seq = ++_loadSeq;
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
      if (mounted && seq == _loadSeq) {
        setState(() {
          _folders = folders;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _loadSeq) {
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
    if (PlatformPaths.isPrivateInboxRoot(_root)) return false;
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
    if (PlatformPaths.isPrivateInboxRoot(_root)) return;
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
    final name = await showNewFolderDialog(context);
    if (name != null && name.isNotEmpty) {
      try {
        final target = _relPath.isEmpty ? name : '$_relPath/$name';
        await createDir(root: _root, path: target);
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).failedCreateFolder('$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  String get _currentPath => _relPath.isEmpty ? _root : '$_root/$_relPath';

  void _navigateTo(String fullPath) {
    final split = PlatformPaths.splitPrivateInboxPath(fullPath) ??
        splitPathToRootAndRel(fullPath);
    setState(() {
      _root = split.root;
      _relPath = split.relPath;
      _selectedFolder = null;
      _filterQuery = '';
      _filterController.clear();
    });
    _load();
  }

  Future<void> _switchToSystemPicker() async {
    final l10n = AppLocalizations.of(context);
    final initialDir = _currentPath.isNotEmpty && Directory(_currentPath).existsSync()
        ? _currentPath
        : null;
    try {
      final selectedPath = await getDirectoryPath(
        initialDirectory: initialDir,
        confirmButtonText: widget.confirmLabel ?? l10n.selectThisFolder,
      );
      if (selectedPath == null || selectedPath.isEmpty || !mounted) return;

      PreferencesService.instance.addRecentUploadDir(selectedPath);
      final split = splitNativeFile(selectedPath);
      Navigator.pop(
        context,
        PickedFolder(root: split.srcRoot, relPath: split.name),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recentDirs = isNativeRoot(_root)
        ? PreferencesService.instance.getRecentUploadDirs()
        : const <String>[];
    final quickTargets = <QuickTarget>[
      if (isNativeRoot(_root) || widget.includeUnlockedVaults)
        ...PlatformPaths.quickTargets().where((t) => isNativeRoot(t.root)),
      if (widget.includeUnlockedVaults)
        for (final v in VaultService.instance.unlockedVaults)
          QuickTarget(
            name: '🔒 ${v.name}',
            kind: 'vault',
            path: 'vault://${v.id}',
            root: 'vault://${v.id}',
            relPath: '',
          ),
    ];

    final filtered = _filterQuery.isEmpty
        ? _folders
        : _folders
            .where((f) => f.name.toLowerCase().contains(_filterQuery.toLowerCase()))
            .toList();

    Widget bodyWidget;
    if (_folders.isEmpty) {
      bodyWidget = Center(
        child: Text(
          AppLocalizations.of(context).noSubfolders,
          style: TextStyle(fontSize: 12),
        ),
      );
    } else if (filtered.isEmpty) {
      bodyWidget = Center(
        child: Text(
          AppLocalizations.of(context).noMatchingSubfolders,
          style: TextStyle(fontSize: 12),
        ),
      );
    } else {
      bodyWidget = ListView.builder(
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
              tooltip: AppLocalizations.of(context).open,
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
    }

    return VfsPickerScaffold(
      title: widget.title,
      onSystemPicker: isNativeRoot(_root) ? _switchToSystemPicker : null,
      recentDirs: recentDirs,
      onNavigateTo: _navigateTo,
      quickTargets: quickTargets,
      onSelectTarget: (target) {
        setState(() {
          _root = target.root;
          _relPath = target.relPath;
          _selectedFolder = null;
          _filterQuery = '';
          _filterController.clear();
        });
        _load();
      },
      currentPath: _currentPath,
      canGoUp: _canGoUp,
      onUp: _up,
      showHidden: _showHidden,
      onToggleHidden: () {
        setState(() => _showHidden = !_showHidden);
        _load();
      },
      hiddenTooltip: _showHidden ? l10n.hideHiddenFolders : l10n.showHiddenFolders,
      pathActions: [
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: l10n.newFolder,
          onPressed: _createNewFolder,
        ),
      ],
      showFilter: _folders.length > 5 || _filterQuery.isNotEmpty,
      filterController: _filterController,
      filterQuery: _filterQuery,
      filterHintText: l10n.filterSubfoldersHint,
      onFilterChanged: (v) => setState(() => _filterQuery = v),
      onFilterClear: () {
        setState(() {
          _filterQuery = '';
          _filterController.clear();
        });
      },
      loading: _loading,
      error: _error,
      errorPrefix: l10n.cannotReadFolderPrefix,
      onRetry: _load,
      body: bodyWidget,
      maxWidth: 500,
      maxHeight: 460,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
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
                  if (isNativeRoot(_root)) {
                    final dirToSave = effectiveRel.isEmpty ? _root : joinNative(_root, effectiveRel);
                    PreferencesService.instance.addRecentUploadDir(dirToSave);
                  }
                  Navigator.of(context).pop(
                    PickedFolder(root: _root, relPath: effectiveRel),
                  );
                },
          child: Text(() {
            if (_selectedFolder != null) {
              final label = widget.confirmLabel ?? l10n.selectFolderAction;
              return '$label "$_selectedFolder"';
            }
            return widget.confirmLabel ?? l10n.selectThisFolder;
          }()),
        ),
      ],
    );
  }
}
