import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../rust/api/remotes.dart';
import '../services/path_utils.dart';
import '../services/photo_backup_service.dart';
import '../services/pool_service.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

class PhotoBackupPage extends StatefulWidget {
  const PhotoBackupPage({super.key});

  @override
  State<PhotoBackupPage> createState() => _PhotoBackupPageState();
}

class _PhotoBackupPageState extends State<PhotoBackupPage> {
  final _service = PhotoBackupService.instance;
  late bool _enabled;
  late bool _wifiOnly;
  late String _targetRoot;
  late String _targetDir;
  late List<String> _sourceDirs;
  late List<String> _sourceAlbumIds;
  List<RemoteConfigDto> _remotes = const [];
  int _backedUpCount = 0;

  @override
  void initState() {
    super.initState();
    _enabled = _service.isEnabled;
    _wifiOnly = _service.wifiOnly;
    _targetRoot = _service.targetRoot;
    _targetDir = _service.targetDir;
    _sourceDirs = List<String>.from(_service.sourceDirs);
    _sourceAlbumIds = List<String>.from(_service.sourceAlbumIds);
    _backedUpCount = _service.loadBackedUpIds().length;
    _service.progressNotifier.addListener(_onBackupProgress);
    _loadRemotes();
  }

  Future<void> _loadRemotes() async {
    try {
      final list = await StorageService.instance.getRemotes();
      if (mounted) {
        setState(() => _remotes = list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _service.progressNotifier.removeListener(_onBackupProgress);
    super.dispose();
  }

  void _onBackupProgress() {
    if (!mounted) return;
    final nextCount = _service.loadBackedUpIds().length;
    if (nextCount != _backedUpCount) {
      setState(() => _backedUpCount = nextCount);
    }
  }

  bool get _isTargetLockedVault {
    final vid = vaultIdFromRoot(_targetRoot);
    if (vid == null) return false;
    return !VaultService.instance.isUnlocked(vid);
  }

  String _formatLastRunTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showPermissionDeniedDialog() async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photoBackupPermissionDeniedTitle),
        content: Text(l10n.photoBackupPermissionDeniedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              PhotoManager.openSetting();
            },
            child: Text(l10n.photoBackupOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _resetBackupHistory() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photoBackupResetHistory),
        content: Text(l10n.photoBackupResetHistoryConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _service.clearLedger();
    setState(() => _backedUpCount = 0);
  }

  void _openDestination() {
    if (_targetRoot.isEmpty || _isTargetLockedVault) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: _targetRoot,
          initialPath: _targetDir,
        ),
      ),
    );
  }

  String _formatTargetDisplay(AppLocalizations l10n) {
    if (_targetRoot.isEmpty) return l10n.photoBackupNoTarget;
    String rootLabel = _targetRoot;
    if (_targetRoot.startsWith('remote://')) {
      final id = _targetRoot.substring('remote://'.length);
      final match = _remotes.where((r) => r.id == id).firstOrNull;
      if (match != null) {
        rootLabel = '☁️ ${match.name}';
      }
    } else if (poolIdFromRoot(_targetRoot) != null) {
      final pid = poolIdFromRoot(_targetRoot)!;
      final match =
          PoolService.instance.pools.where((p) => p.id == pid).firstOrNull;
      if (match != null) {
        rootLabel = '🧩 ${match.name}';
      }
    } else if (vaultIdFromRoot(_targetRoot) != null) {
      final vid = vaultIdFromRoot(_targetRoot)!;
      final match = VaultService.instance.unlockedVaults
          .where((v) => v.id == vid)
          .firstOrNull;
      if (match != null) {
        rootLabel = '🔒 ${match.name}';
      }
    }
    return _targetDir.isEmpty ? rootLabel : '$rootLabel/$_targetDir';
  }

  Future<void> _addSourceFolder() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.photoBackupSelectSource,
      initialRoot: _sourceDirs.isNotEmpty ? _sourceDirs.last : null,
      includeUnlockedVaults: false,
      includeRemotes: false,
      includePools: false,
    );
    if (picked != null && mounted) {
      if (!isNativeRoot(picked.root)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.localStorage)),
        );
        return;
      }
      final full = joinNative(picked.root, picked.relPath);
      _service.addSourceDir(full);
      setState(() {
        _sourceDirs = List<String>.from(_service.sourceDirs);
      });
    }
  }

  void _removeSourceFolder(String dir) {
    _service.removeSourceDir(dir);
    setState(() {
      _sourceDirs = List<String>.from(_service.sourceDirs);
    });
  }

  void _resetSourceSelection() {
    _service.setSourceDirs(const []);
    _service.setSourceAlbumIds(const []);
    setState(() {
      _sourceDirs = const [];
      _sourceAlbumIds = const [];
    });
  }

  Future<void> _pickAlbums() async {
    final l10n = AppLocalizations.of(context);
    final perm = await PhotoManager.requestPermissionExtend();
    if (!perm.hasAccess) {
      if (mounted) await _showPermissionDeniedDialog();
      return;
    }
    if (!mounted) return;
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: false,
      type: RequestType.common,
    );
    if (!mounted) return;
    final items = <({AssetPathEntity album, int count})>[];
    for (final album in paths) {
      if (album.isAll) continue;
      final count = await album.assetCountAsync;
      items.add((album: album, count: count));
    }
    if (!mounted) return;
    final selected = Set<String>.from(_sourceAlbumIds);
    final confirmed = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.photoBackupSelectAlbums),
          content: SizedBox(
            width: 360,
            height: 360,
            child: items.isEmpty
                ? Center(child: Text(l10n.photoBackupAllAlbums))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final entry = items[i];
                      final checked = selected.contains(entry.album.id);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        title: Text(entry.album.name),
                        subtitle: Text('${entry.count}'),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selected.add(entry.album.id);
                            } else {
                              selected.remove(entry.album.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() => selected.clear());
              },
              child: Text(l10n.photoBackupAllAlbums),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected.toList()),
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
    if (confirmed != null && mounted) {
      _service.setSourceAlbumIds(confirmed);
      setState(() {
        _sourceAlbumIds = List<String>.from(_service.sourceAlbumIds);
      });
    }
  }

  Future<void> _pickDestination() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.photoBackupSelectTarget,
      initialRoot: _targetRoot.isEmpty ? null : _targetRoot,
      initialPath: _targetDir,
      includeUnlockedVaults: true,
      includeRemotes: true,
      includePools: true,
    );
    if (picked != null && mounted) {
      _service.setTarget(root: picked.root, dir: picked.relPath);
      setState(() {
        _targetRoot = picked.root;
        _targetDir = picked.relPath;
      });
    }
  }

  Future<void> _runNow() async {
    final l10n = AppLocalizations.of(context);
    if (_targetRoot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photoBackupNoTarget)),
      );
      return;
    }
    if ((Platform.isAndroid || Platform.isIOS) && _sourceDirs.isEmpty) {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      if (!perm.hasAccess) {
        await _showPermissionDeniedDialog();
        return;
      }
    }
    try {
      final count = await _service.runBackup(force: true);
      if (!mounted) return;
      setState(() {
        _backedUpCount = _service.loadBackedUpIds().length;
      });
      final prog = _service.progressNotifier.value;
      final lastError = prog.lastError;
      if (prog.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.photoBackupCancelledNotice(prog.uploaded))),
        );
      } else if (lastError != null && lastError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lastError),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.photoBackupCompleted(count))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final targetDisplay = _formatTargetDisplay(l10n);
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final hasCustomSource = _sourceDirs.isNotEmpty || _sourceAlbumIds.isNotEmpty;

    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.photoBackupTitle),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_upload_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.photoBackupTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.photoBackupSubtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n.photoBackupStats(_backedUpCount),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary,
                          ),
                        ),
                        if (_service.lastBackupMillis > 0)
                          Text(
                            l10n.photoBackupLastRun(
                              _formatLastRunTime(_service.lastBackupMillis),
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (_backedUpCount > 0)
                          TextButton.icon(
                            onPressed: _resetBackupHistory,
                            icon: const Icon(Icons.history_toggle_off, size: 16),
                            label: Text(l10n.photoBackupResetHistory),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: Text(l10n.photoBackupEnable),
                    value: _enabled,
                    onChanged: (v) {
                      _service.isEnabled = v;
                      setState(() => _enabled = v);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(l10n.photoBackupWifiOnly),
                    value: _wifiOnly,
                    onChanged: (v) {
                      _service.wifiOnly = v;
                      setState(() => _wifiOnly = v);
                    },
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.perm_media_outlined, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.photoBackupSourceLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            if (hasCustomSource)
                              TextButton(
                                onPressed: _resetSourceSelection,
                                child: Text(l10n.photoBackupResetSources),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (isMobile) ...[
                          Text(
                            _sourceAlbumIds.isEmpty
                                ? l10n.photoBackupAllAlbums
                                : l10n.photoBackupSelectedAlbumsCount(
                                    _sourceAlbumIds.length,
                                  ),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ] else if (_sourceDirs.isEmpty) ...[
                          Text(
                            '${l10n.photoBackupDefaultSources}: ${_service.effectiveDesktopSourceDirs().join(' · ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_sourceDirs.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final dir in _sourceDirs)
                                InputChip(
                                  avatar:
                                      const Icon(Icons.folder_outlined, size: 16),
                                  label: Text(
                                    dir,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onDeleted: () => _removeSourceFolder(dir),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (isMobile)
                              OutlinedButton.icon(
                                onPressed: _pickAlbums,
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                  size: 16,
                                ),
                                label: Text(l10n.photoBackupSelectAlbums),
                              ),
                            OutlinedButton.icon(
                              onPressed: _addSourceFolder,
                              icon: const Icon(
                                Icons.create_new_folder_outlined,
                                size: 16,
                              ),
                              label: Text(l10n.photoBackupSelectSource),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      _isTargetLockedVault ? Icons.lock_outline : Icons.folder_outlined,
                      color: _isTargetLockedVault ? scheme.warning : null,
                    ),
                    title: Text(l10n.photoBackupTargetLabel),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          targetDisplay,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_isTargetLockedVault)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l10n.photoBackupVaultLocked,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_targetRoot.isNotEmpty && !_isTargetLockedVault)
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 18),
                            tooltip: l10n.photoBackupOpenDestination,
                            onPressed: _openDestination,
                          ),
                        OutlinedButton(
                          onPressed: _pickDestination,
                          child: Text(l10n.photoBackupSelectTarget),
                        ),
                      ],
                    ),
                    onTap: _pickDestination,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<PhotoBackupProgress>(
              valueListenable: _service.progressNotifier,
              builder: (context, prog, _) {
                final progressText = prog.scanning
                    ? l10n.photoBackupScanning
                    : prog.total > 0
                        ? '${prog.currentFile ?? l10n.photoBackupRunning} · ${l10n.photoBackupProgressCount(prog.uploaded, prog.total)}'
                        : (prog.currentFile ?? l10n.photoBackupRunning);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (prog.running) ...[
                      LinearProgressIndicator(
                        value: !prog.scanning && prog.total > 0
                            ? prog.uploaded / prog.total
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        progressText,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if ((prog.lastError ?? '').isNotEmpty) ...[
                      Text(
                        prog.lastError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (prog.running)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: null,
                              icon: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              ),
                              label: Text(l10n.photoBackupRunning),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _service.cancelBackup,
                            icon: const Icon(Icons.close, size: 18),
                            label: Text(l10n.photoBackupCancel),
                          ),
                        ],
                      )
                    else
                      FilledButton.icon(
                        onPressed: _runNow,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(l10n.photoBackupNow),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
