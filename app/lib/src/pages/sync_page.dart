import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/sync.dart';
import '../services/auto_sync_service.dart';
import '../services/background_keepalive_service.dart';
import '../services/error_text.dart';
import '../widgets/error_recovery_action.dart';
import '../services/task_service.dart';

/// Directory Sync & Lightweight Backup page (Incremental / Mirror / Bidirectional).
class SyncPage extends StatefulWidget {
  final String? initialSrcRoot;
  final String? initialSrcPath;

  const SyncPage({super.key, this.initialSrcRoot, this.initialSrcPath});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  String? _srcRoot;
  String _srcPath = '';
  String? _dstRoot;
  String _dstPath = '';
  String _mode = 'incremental';

  List<SyncProfile> _profiles = [];
  bool _previewing = false;
  SyncPlanDto? _plan;
  final Set<String> _selectedRelPaths = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _srcRoot = widget.initialSrcRoot;
    _srcPath = widget.initialSrcPath ?? '';
    _loadProfiles();
  }

  void _loadProfiles() {
    _profiles = AutoSyncService.instance.loadProfiles();
  }

  void _persistProfiles() {
    AutoSyncService.instance.saveProfiles(_profiles);
  }

  Future<void> _saveCurrentProfile() async {
    if (_srcRoot == null || _dstRoot == null) return;
    final l10n = AppLocalizations.of(context);
    final defaultName =
        '${_shortLabel(_srcRoot!, _srcPath)} → ${_shortLabel(_dstRoot!, _dstPath)}';
    final existing = _profiles.where((p) => p.name == defaultName).firstOrNull;
    final controller = TextEditingController(text: defaultName);
    var intervalMinutes = existing?.autoIntervalMinutes ?? 0;
    final saved = await showDialog<({String name, int interval})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Save Sync Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Profile name',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('sync_interval_$intervalMinutes'),
                initialValue: intervalMinutes,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText: l10n.autoSyncIntervalLabel,
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.autoSyncOff)),
                  for (final m in const [15, 30, 60, 240])
                    DropdownMenuItem(
                      value: m,
                      child: Text(l10n.autoSyncEveryMinutes(m)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => intervalMinutes = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop((
                name: controller.text.trim(),
                interval: intervalMinutes,
              )),
              child: Text(AppLocalizations.of(ctx).ok),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null || saved.name.isEmpty || !mounted) return;
    setState(() {
      _profiles.removeWhere((p) => p.name == saved.name);
      _profiles.insert(
        0,
        SyncProfile(
          name: saved.name,
          srcRoot: _srcRoot!,
          srcPath: _srcPath,
          dstRoot: _dstRoot!,
          dstPath: _dstPath,
          mode: _mode,
          autoIntervalMinutes: saved.interval,
        ),
      );
      _persistProfiles();
    });
  }

  void _applyProfile(SyncProfile profile) {
    setState(() {
      _srcRoot = profile.srcRoot;
      _srcPath = profile.srcPath;
      _dstRoot = profile.dstRoot;
      _dstPath = profile.dstPath;
      _mode = profile.mode;
      _plan = null;
      _selectedRelPaths.clear();
      _error = null;
    });
  }

  void _deleteProfile(SyncProfile profile) {
    setState(() {
      _profiles.removeWhere((p) => p.name == profile.name);
      _persistProfiles();
    });
  }

  String _shortLabel(String root, String rel) {
    final target = rel.isEmpty ? root : rel;
    final parts = target.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? root : parts.last;
  }

  Future<void> _pickFolder(bool isSource) async {
    final l10n = AppLocalizations.of(context);
    final dest = await FolderPickerDialog.show(
      context,
      title: l10n.directorySync,
      confirmLabel: l10n.ok,
    );
    if (dest == null || !mounted) return;
    setState(() {
      if (isSource) {
        _srcRoot = dest.root;
        _srcPath = dest.relPath;
      } else {
        _dstRoot = dest.root;
        _dstPath = dest.relPath;
      }
      _plan = null;
      _selectedRelPaths.clear();
    });
  }

  Future<void> _preview() async {
    if (_srcRoot == null || _dstRoot == null) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final plan = await BackgroundKeepAliveService.instance.runWithKeepAlive(
        'sync:preview',
        () => previewDirectorySync(
          srcRoot: _srcRoot!,
          srcPath: _srcPath,
          dstRoot: _dstRoot!,
          dstPath: _dstPath,
          mode: _mode,
        ),
        title: 'Directory Sync Scan',
        detail: 'Scanning ${_shortLabel(_srcRoot!, _srcPath)} ↔ ${_shortLabel(_dstRoot!, _dstPath)}',
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selectedRelPaths
          ..clear()
          ..addAll(plan.items.map((e) => e.relPath));
        _previewing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyErrorText(e, AppLocalizations.of(context));
          _previewing = false;
        });
      }
    }
  }

  Future<void> _startSync() async {
    if (_srcRoot == null || _dstRoot == null || _selectedRelPaths.isEmpty) return;
    try {
      await BackgroundKeepAliveService.instance.runWithKeepAlive(
        'sync:execute',
        () async {
          final taskId = await startDirectorySyncTask(
            srcRoot: _srcRoot!,
            srcPath: _srcPath,
            dstRoot: _dstRoot!,
            dstPath: _dstPath,
            mode: _mode,
            selectedRelPaths: _selectedRelPaths.toList(),
          );
          if (!mounted) return;
          await TaskProgressDialog.show(
            context,
            taskId,
            AppLocalizations.of(context).directorySync,
          );
        },
        title: 'Directory Sync in Progress',
        detail: '${_shortLabel(_srcRoot!, _srcPath)} → ${_shortLabel(_dstRoot!, _dstPath)}',
      );
      if (mounted) {
        await _preview();
      }
    } catch (e) {
      if (mounted) {
        final targetRoot = _dstRoot?.startsWith('remote://') == true
            ? _dstRoot
            : _srcRoot;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorText(e, AppLocalizations.of(context))),
            action: ErrorRecoveryActionButton.buildSnackBarAction(
              context,
              rawError: e,
              root: targetRoot,
              onRetry: _startSync,
            ),
          ),
        );
      }
    }
  }

  String _formatTarget(String? root, String rel) {
    if (root == null) return '—';
    return rel.isEmpty ? root : '$root/$rel';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.directorySync),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Save Sync Profile',
            onPressed: (_srcRoot != null && _dstRoot != null) ? _saveCurrentProfile : null,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_profiles.isNotEmpty) ...[
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _profiles.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final p = _profiles[i];
                    final label = p.autoIntervalMinutes > 0
                        ? '${p.name} (${p.autoIntervalMinutes}m)'
                        : p.name;
                    return InputChip(
                      avatar: Icon(
                        p.autoIntervalMinutes > 0 ? Icons.schedule : Icons.sync_alt,
                        size: 15,
                      ),
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _applyProfile(p),
                      onDeleted: () => _deleteProfile(p),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Source'),
                    subtitle: Text(
                      _formatTarget(_srcRoot, _srcPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickFolder(true),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined),
                    title: const Text('Destination'),
                    subtitle: Text(
                      _formatTarget(_dstRoot, _dstPath),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickFolder(false),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('sync_mode_$_mode'),
              initialValue: _mode,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'incremental', child: Text(l10n.syncModeIncremental)),
                DropdownMenuItem(value: 'mirror', child: Text(l10n.syncModeMirror)),
                DropdownMenuItem(value: 'bidirectional', child: Text(l10n.syncModeBidirectional)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _mode = v);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _previewing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.preview, size: 18),
                    label: Text(l10n.syncPreviewChanges),
                    onPressed: (_srcRoot != null && _dstRoot != null && !_previewing)
                        ? _preview
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text(l10n.syncStart),
                    onPressed: (plan != null && _selectedRelPaths.isNotEmpty) ? _startSync : null,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                  const SizedBox(width: 8),
                  ErrorRecoveryActionButton(
                    rawError: _error!,
                    root: _dstRoot?.startsWith('remote://') == true
                        ? _dstRoot
                        : _srcRoot,
                    onRetry: _preview,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (plan != null) ...[
              if (plan.truncated)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Scan limit reached (200,000 files / 64 levels, scanned ${plan.scannedFiles}). Deeper files may not be included.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                '${plan.items.length} changes · ${plan.unchangedCount} unchanged · ${formatBytes(plan.transferBytes)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: plan.items.isEmpty
                    ? Center(child: Text(l10n.syncNoChanges))
                    : ListView.separated(
                        itemCount: plan.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = plan.items[i];
                          final (IconData icon, Color color) = switch (item.action) {
                            'add' => (Icons.add_circle_outline, Colors.green),
                            'update' => (Icons.update, Colors.blue),
                            'delete' => (Icons.delete_outline, Colors.red),
                            'pull_add' || 'pull_update' => (Icons.download_outlined, Colors.teal),
                            _ => (Icons.sync, Colors.grey),
                          };
                          return CheckboxListTile(
                            dense: true,
                            value: _selectedRelPaths.contains(item.relPath),
                            secondary: Icon(icon, color: color, size: 18),
                            title: Text(item.relPath, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${item.action.toUpperCase()} · ${item.srcSize != null ? formatBytes(item.srcSize!) : (item.dstSize != null ? formatBytes(item.dstSize!) : '')}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedRelPaths.add(item.relPath);
                                } else {
                                  _selectedRelPaths.remove(item.relPath);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
