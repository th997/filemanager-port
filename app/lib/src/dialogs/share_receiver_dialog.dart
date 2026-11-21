import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:filemanager/l10n/app_localizations.dart';

import '../models/entry_item.dart';
import '../pages/browser_page.dart';
import '../rust/api/remotes.dart';
import '../services/external_file_service.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import 'folder_picker_dialog.dart';
import 'remote_wizard_dialog.dart';
import 'task_progress_dialog.dart';

export '../services/path_utils.dart' show isValidFileName;

enum ShareReceiverAction {
  saveLocal,
  saveRemote,
  openDirectly,
}

class ShareReceiverResult {
  final ShareReceiverAction action;
  final String? customName;
  const ShareReceiverResult(this.action, [this.customName]);
}

/// Returns candidate paths for `<baseDir>/<subDir>`, including the
/// symlink-resolved variant (e.g. `/var/...` -> `/private/var/...` on iOS).
List<String> expandInboxDirCandidates(Directory baseDir, String subDir) {
  final candidates = <String>[p.join(baseDir.path, subDir)];
  try {
    final resolvedBase = baseDir.resolveSymbolicLinksSync();
    final resolvedInbox = p.join(resolvedBase, subDir);
    if (!candidates.contains(resolvedInbox)) {
      candidates.add(resolvedInbox);
    }
  } catch (_) {}
  return candidates;
}

/// Returns true only when [filePath] resides strictly inside one of the app's
/// temporary share-inbox directories, avoiding accidental deletion of user files.
bool isPathInTemporaryInbox(String filePath, List<String> allowedInboxDirs) {
  if (filePath.isEmpty || allowedInboxDirs.isEmpty) return false;
  final normFile = p.normalize(filePath);
  for (final dir in allowedInboxDirs) {
    if (dir.isEmpty) continue;
    final normDir = p.normalize(dir);
    if (p.isWithin(normDir, normFile)) {
      return true;
    }
  }
  return false;
}

/// Shows the share receiver interface (bottom sheet on mobile, dialog on desktop)
/// allowing the user to Save to Local, Save to Remote, or Open Directly.
Future<void> showShareReceiverDialog({
  required BuildContext context,
  required List<String> filePaths,
}) async {
  final validPaths = filePaths.where((path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }).toList();
  if (validPaths.isEmpty) return;

  final isWide = MediaQuery.sizeOf(context).width >= 600;
  final result = await (isWide
      ? showDialog<ShareReceiverResult>(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ShareReceiverContent(
                filePaths: validPaths,
                onAction: (a) => Navigator.of(ctx).pop(ShareReceiverResult(a)),
                onActionWithName: (a, name) => Navigator.of(ctx).pop(ShareReceiverResult(a, name)),
                onCancel: () => Navigator.of(ctx).pop(null),
              ),
            ),
          ),
        )
      : showModalBottomSheet<ShareReceiverResult>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
              ),
              child: ShareReceiverContent(
                filePaths: validPaths,
                onAction: (a) => Navigator.of(ctx).pop(ShareReceiverResult(a)),
                onActionWithName: (a, name) => Navigator.of(ctx).pop(ShareReceiverResult(a, name)),
                onCancel: () => Navigator.of(ctx).pop(null),
              ),
            ),
          ),
        ));

  if (result == null) return;
  final navCtx = ExternalFileService.instance.navContext;
  final activeContext = (navCtx != null && navCtx.mounted)
      ? navCtx
      : (context.mounted ? context : null);
  if (activeContext == null || !activeContext.mounted) return;

  switch (result.action) {
    case ShareReceiverAction.saveLocal:
      await _handleSaveToLocal(activeContext, validPaths, customName: result.customName);
      break;
    case ShareReceiverAction.saveRemote:
      await _handleSaveToRemote(activeContext, validPaths, customName: result.customName);
      break;
    case ShareReceiverAction.openDirectly:
      ExternalFileService.instance.openFiles(validPaths);
      break;
  }
}

Future<void> _handleSaveToLocal(
  BuildContext context,
  List<String> filePaths, {
  String? customName,
}) async {
  final l10n = AppLocalizations.of(context);
  final dest = await FolderPickerDialog.show(
    context,
    title: l10n.saveToLocal,
    initialRoot: PlatformPaths.defaultRoot(),
  );
  if (dest == null) return;

  final navCtx = ExternalFileService.instance.navContext;
  final liveContext = (navCtx != null && navCtx.mounted)
      ? navCtx
      : (context.mounted ? context : null);
  if (liveContext == null || !liveContext.mounted) return;
  await _executeCopy(liveContext, filePaths, dest, customName: customName);
}

Future<void> _handleSaveToRemote(
  BuildContext context,
  List<String> filePaths, {
  String? customName,
}) async {
  final l10n = AppLocalizations.of(context);

  List<RemoteConfigDto> remotes = [];
  try {
    remotes = await StorageService.instance.getRemotes();
  } catch (_) {}

  final navCtx1 = ExternalFileService.instance.navContext;
  final liveContext = (navCtx1 != null && navCtx1.mounted)
      ? navCtx1
      : (context.mounted ? context : null);
  if (liveContext == null || !liveContext.mounted) return;

  if (remotes.isEmpty) {
    final goToAdd = await showDialog<bool>(
      context: liveContext,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.noRemotesConfigured),
        content: Text(l10n.noRemotesPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.addConnection),
          ),
        ],
      ),
    );
    if (goToAdd == true) {
      final navCtx2 = ExternalFileService.instance.navContext;
      final curCtx = (navCtx2 != null && navCtx2.mounted)
          ? navCtx2
          : (liveContext.mounted ? liveContext : null);
      if (curCtx == null || !curCtx.mounted) return;
      final added = await showDialog<bool>(
        context: curCtx,
        builder: (_) => const RemoteWizardDialog(),
      );
      if (added == true) {
        final navCtx3 = ExternalFileService.instance.navContext;
        final nextCtx = (navCtx3 != null && navCtx3.mounted)
            ? navCtx3
            : (curCtx.mounted ? curCtx : null);
        if (nextCtx == null || !nextCtx.mounted) return;
        await _handleSaveToRemote(nextCtx, filePaths, customName: customName);
      }
    }
    return;
  }

  RemoteConfigDto? chosenRemote;
  if (remotes.length == 1) {
    chosenRemote = remotes.first;
  } else {
    chosenRemote = await _selectRemote(liveContext, remotes);
  }

  if (chosenRemote == null) return;

  final navCtx4 = ExternalFileService.instance.navContext;
  final curCtx = (navCtx4 != null && navCtx4.mounted)
      ? navCtx4
      : (liveContext.mounted ? liveContext : null);
  if (curCtx == null || !curCtx.mounted) return;
  final dest = await FolderPickerDialog.show(
    curCtx,
    title: '${l10n.saveToRemote} (${chosenRemote.name})',
    initialRoot: 'remote://${chosenRemote.id}',
  );
  if (dest == null) return;

  final navCtx5 = ExternalFileService.instance.navContext;
  final finalCtx = (navCtx5 != null && navCtx5.mounted)
      ? navCtx5
      : (curCtx.mounted ? curCtx : null);
  if (finalCtx == null || !finalCtx.mounted) return;
  await _executeCopy(finalCtx, filePaths, dest, customName: customName);
}

Future<RemoteConfigDto?> _selectRemote(
  BuildContext context,
  List<RemoteConfigDto> remotes,
) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<RemoteConfigDto>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.selectRemoteStorage,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const Divider(),
          for (final r in remotes)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.cloud_outlined, color: Theme.of(ctx).colorScheme.primary),
              ),
              title: Text(r.name),
              subtitle: Text(r.kind.toUpperCase()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(ctx).pop(r),
            ),
        ],
      ),
    ),
  );
}

Future<void> _executeCopy(
  BuildContext context,
  List<String> paths,
  PickedFolder dest, {
  String? customName,
}) async {
  final l10n = AppLocalizations.of(context);
  final grouped = <String, List<String>>{};
  for (final pth in paths) {
    grouped.putIfAbsent(p.dirname(pth), () => []).add(p.basename(pth));
  }

  final trimmedCustom = customName?.trim();
  final effectiveDstName = (paths.length == 1 &&
          trimmedCustom != null &&
          isValidFileName(trimmedCustom) &&
          trimmedCustom != p.basename(paths.first))
      ? trimmedCustom
      : null;

  bool allSucceeded = true;
  for (final entry in grouped.entries) {
    Future<String> startTask() => TaskService.instance.copy(
      srcRoot: entry.key,
      srcPaths: entry.value,
      dstRoot: dest.root,
      dstDir: dest.relPath,
      conflictPolicy: 'rename',
      dstName: effectiveDstName,
    );

    try {
      final taskId = await startTask();
      final navCtx = ExternalFileService.instance.navContext;
      final activeContext = (navCtx != null && navCtx.mounted)
          ? navCtx
          : (context.mounted ? context : null);
      if (activeContext == null || !activeContext.mounted) return;
      final completed = await TaskProgressDialog.show(
        activeContext,
        taskId,
        l10n.savingSharedFiles,
        onRetry: startTask,
      );
      if (completed != true) {
        allSucceeded = false;
        break;
      }
    } catch (e) {
      allSucceeded = false;
      final navCtx = ExternalFileService.instance.navContext;
      final activeContext = (navCtx != null && navCtx.mounted)
          ? navCtx
          : (context.mounted ? context : null);
      if (activeContext != null && activeContext.mounted) {
        ScaffoldMessenger.of(activeContext).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(activeContext).colorScheme.error,
          ),
        );
      }
      return;
    }
  }

  if (!allSucceeded) return;

  // Auto-clean only files inside the app's own temporary share inbox directories.
  final allowedInboxDirs = <String>[];
  try {
    final tempDir = await getTemporaryDirectory();
    allowedInboxDirs.addAll(expandInboxDirCandidates(tempDir, 'inbox'));
  } catch (_) {}
  if (Platform.isIOS) {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      allowedInboxDirs.addAll(expandInboxDirCandidates(docsDir, 'Inbox'));
    } catch (_) {}
  }

  for (final pth in paths) {
    try {
      if (isPathInTemporaryInbox(pth, allowedInboxDirs)) {
        final f = File(pth);
        if (f.existsSync()) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  final navCtx = ExternalFileService.instance.navContext;
  final activeContext = (navCtx != null && navCtx.mounted)
      ? navCtx
      : (context.mounted ? context : null);
  if (activeContext == null || !activeContext.mounted) return;
  ScaffoldMessenger.of(activeContext).showSnackBar(
    SnackBar(
      content: Text('${l10n.savedSharedFilesSuccess}: ${dest.path}'),
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: l10n.view,
        onPressed: () {
          final nav = ExternalFileService.instance.navContext;
          if (nav != null) {
            Navigator.of(nav).push(
              MaterialPageRoute(
                builder: (_) => BrowserPage(
                  initialRoot: dest.root,
                  initialPath: dest.relPath,
                ),
              ),
            );
          }
        },
      ),
    ),
  );
}

class ShareReceiverContent extends StatefulWidget {
  final List<String> filePaths;
  final ValueChanged<ShareReceiverAction> onAction;
  final void Function(ShareReceiverAction action, String? customName)? onActionWithName;
  final VoidCallback onCancel;

  const ShareReceiverContent({
    super.key,
    required this.filePaths,
    required this.onAction,
    this.onActionWithName,
    required this.onCancel,
  });

  @override
  State<ShareReceiverContent> createState() => _ShareReceiverContentState();
}

class _ShareReceiverContentState extends State<ShareReceiverContent> {
  late final TextEditingController _nameController;
  bool _isEditingName = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.filePaths.length == 1 ? p.basename(widget.filePaths.first) : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _triggerAction(ShareReceiverAction action) {
    String? customName;
    if (widget.filePaths.length == 1 && action != ShareReceiverAction.openDirectly) {
      final trimmed = _nameController.text.trim();
      if (trimmed.isNotEmpty && !isValidFileName(trimmed)) {
        setState(() {
          _isEditingName = true;
          _nameError = AppLocalizations.of(context).invalidFileNameError;
        });
        return;
      }
      customName = trimmed.isNotEmpty ? trimmed : null;
    }
    if (widget.onActionWithName != null) {
      widget.onActionWithName!(action, customName);
    } else {
      widget.onAction(action);
    }
  }

  IconData _iconForPath(String filePath) {
    try {
      if (Directory(filePath).existsSync()) {
        return Icons.folder_outlined;
      }
    } catch (_) {}
    final lower = filePath.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final ext = (dot >= 0 && dot < lower.length - 1) ? lower.substring(dot + 1) : '';
    if (EntryItem.isImageExtension(ext)) return Icons.image_outlined;
    if (EntryItem.isVideoExtension(ext)) return Icons.play_circle_outline;
    if (EntryItem.isAudioExtension(ext)) return Icons.music_note_outlined;
    if (EntryItem.isArchiveExtension(ext)) return Icons.folder_zip_outlined;
    if (EntryItem.isTextExtension(ext)) return Icons.description_outlined;
    if (lower.endsWith('.pdf')) return Icons.menu_book_outlined;
    return Icons.insert_drive_file_outlined;
  }

  int _fileSize(String filePath) {
    try {
      final f = File(filePath);
      if (f.existsSync()) return f.lengthSync();
    } catch (_) {}
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isSingle = widget.filePaths.length == 1;

    int totalBytes = 0;
    for (final fp in widget.filePaths) {
      totalBytes += _fileSize(fp);
    }
    final totalSizeStr = formatBytes(BigInt.from(totalBytes));

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                l10n.receivedShareTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),

            // File summary card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isSingle ? _iconForPath(widget.filePaths.first) : Icons.folder_copy_outlined,
                      size: 26,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSingle)
                          Row(
                            children: [
                              Expanded(
                                child: _isEditingName
                                    ? TextField(
                                        controller: _nameController,
                                        autofocus: true,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                          border: const OutlineInputBorder(),
                                          errorText: _nameError,
                                        ),
                                        onChanged: (_) {
                                          if (_nameError != null) {
                                            setState(() => _nameError = null);
                                          }
                                        },
                                        onSubmitted: (val) {
                                          final trimmed = val.trim();
                                          if (trimmed.isNotEmpty && !isValidFileName(trimmed)) {
                                            setState(() {
                                              _nameError = l10n.invalidFileNameError;
                                            });
                                            return;
                                          }
                                          setState(() {
                                            _nameError = null;
                                            _isEditingName = false;
                                          });
                                        },
                                      )
                                    : Text(
                                        _nameController.text.trim().isNotEmpty
                                            ? _nameController.text.trim()
                                            : p.basename(widget.filePaths.first),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                      ),
                              ),
                              IconButton(
                                icon: Icon(_isEditingName ? Icons.check : Icons.edit_outlined, size: 16),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                onPressed: () {
                                  if (_isEditingName) {
                                    final trimmed = _nameController.text.trim();
                                    if (trimmed.isNotEmpty && !isValidFileName(trimmed)) {
                                      setState(() {
                                        _nameError = l10n.invalidFileNameError;
                                      });
                                      return;
                                    }
                                    setState(() {
                                      _nameError = null;
                                      _isEditingName = false;
                                    });
                                  } else {
                                    setState(() => _isEditingName = true);
                                  }
                                },
                              ),
                            ],
                          )
                        else
                          Text(
                            l10n.receivedShareCount(widget.filePaths.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          totalSizeStr,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Multiple files preview list
            if (!isSingle)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.filePaths.length && i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _iconForPath(widget.filePaths[i]),
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.basename(widget.filePaths[i]),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.filePaths.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '... (+${widget.filePaths.length - 3})',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Action 1: Save to local
            _buildActionCard(
              context: context,
              icon: Icons.save_alt_rounded,
              iconBgColor: Colors.green.withValues(alpha: 0.15),
              iconColor: Colors.green.shade700,
              title: l10n.saveToLocal,
              subtitle: l10n.saveToLocalSubtitle,
              onTap: () => _triggerAction(ShareReceiverAction.saveLocal),
            ),

            // Action 2: Save to remote
            _buildActionCard(
              context: context,
              icon: Icons.cloud_upload_outlined,
              iconBgColor: Colors.blue.withValues(alpha: 0.15),
              iconColor: Colors.blue.shade700,
              title: l10n.saveToRemote,
              subtitle: l10n.saveToRemoteSubtitle,
              onTap: () => _triggerAction(ShareReceiverAction.saveRemote),
            ),

            // Action 3: Open directly
            _buildActionCard(
              context: context,
              icon: Icons.open_in_new_rounded,
              iconBgColor: Colors.deepPurple.withValues(alpha: 0.15),
              iconColor: Colors.deepPurple.shade700,
              title: l10n.openDirectly,
              subtitle: l10n.openDirectlySubtitle,
              onTap: () => _triggerAction(ShareReceiverAction.openDirectly),
            ),

            const SizedBox(height: 8),

            // Cancel button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextButton(
                onPressed: widget.onCancel,
                child: Text(l10n.cancel),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
