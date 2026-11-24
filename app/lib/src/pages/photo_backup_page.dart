import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../services/photo_backup_service.dart';
import '../theme/app_ui_tokens.dart';

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
  int _backedUpCount = 0;

  @override
  void initState() {
    super.initState();
    _enabled = _service.isEnabled;
    _wifiOnly = _service.wifiOnly;
    _targetRoot = _service.targetRoot;
    _targetDir = _service.targetDir;
    _backedUpCount = _service.loadBackedUpIds().length;
    _service.progressNotifier.addListener(_onBackupProgress);
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

  Future<void> _pickDestination() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.photoBackupSelectTarget,
      initialRoot: _targetRoot.isEmpty ? null : _targetRoot,
      initialPath: _targetDir,
      includeUnlockedVaults: true,
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
    try {
      final count = await _service.runBackup(force: true);
      if (!mounted) return;
      setState(() {
        _backedUpCount = _service.loadBackedUpIds().length;
      });
      final lastError = _service.progressNotifier.value.lastError;
      if (lastError != null && lastError.isNotEmpty) {
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
    final targetDisplay = _targetRoot.isEmpty
        ? l10n.photoBackupNoTarget
        : (_targetDir.isEmpty ? _targetRoot : '$_targetRoot/$_targetDir');

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
                        Icon(Icons.backup_outlined, color: scheme.primary),
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
                    Text(
                      l10n.photoBackupStats(_backedUpCount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
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
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(l10n.photoBackupTargetLabel),
                    subtitle: Text(
                      targetDisplay,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: OutlinedButton(
                      onPressed: _pickDestination,
                      child: Text(l10n.photoBackupSelectTarget),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<PhotoBackupProgress>(
              valueListenable: _service.progressNotifier,
              builder: (context, prog, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (prog.running) ...[
                      LinearProgressIndicator(
                        value: prog.total > 0
                            ? prog.uploaded / prog.total
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        prog.currentFile ?? l10n.photoBackupRunning,
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
                    FilledButton.icon(
                      onPressed: prog.running ? null : _runNow,
                      icon: prog.running
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        prog.running
                            ? l10n.photoBackupRunning
                            : l10n.photoBackupNow,
                      ),
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
