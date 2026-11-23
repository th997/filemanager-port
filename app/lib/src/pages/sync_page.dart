import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/sync.dart';
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

  bool _previewing = false;
  SyncPlanDto? _plan;
  final Set<String> _selectedRelPaths = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _srcRoot = widget.initialSrcRoot;
    _srcPath = widget.initialSrcPath ?? '';
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
      final plan = await previewDirectorySync(
        srcRoot: _srcRoot!,
        srcPath: _srcPath,
        dstRoot: _dstRoot!,
        dstPath: _dstPath,
        mode: _mode,
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
          _error = '$e';
          _previewing = false;
        });
      }
    }
  }

  Future<void> _startSync() async {
    if (_srcRoot == null || _dstRoot == null || _selectedRelPaths.isEmpty) return;
    try {
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
      if (mounted) {
        await _preview();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
      appBar: AppBar(title: Text(l10n.directorySync)),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 8),
            if (plan != null) ...[
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
