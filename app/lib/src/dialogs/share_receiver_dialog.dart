import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:filemanager/l10n/app_localizations.dart';

import '../models/entry_item.dart';
import '../pages/browser_page.dart';
import '../rust/api/remotes.dart';
import '../services/external_file_service.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import 'folder_picker_dialog.dart';
import 'remote_wizard_dialog.dart';
import 'task_progress_dialog.dart';

enum ShareReceiverAction {
  saveLocal,
  saveRemote,
  openDirectly,
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
  final action = await (isWide
      ? showDialog<ShareReceiverAction>(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ShareReceiverContent(
                filePaths: validPaths,
                onAction: (a) => Navigator.of(ctx).pop(a),
                onCancel: () => Navigator.of(ctx).pop(null),
              ),
            ),
          ),
        )
      : showModalBottomSheet<ShareReceiverAction>(
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
                onAction: (a) => Navigator.of(ctx).pop(a),
                onCancel: () => Navigator.of(ctx).pop(null),
              ),
            ),
          ),
        ));

  if (action == null) return;
  final activeContext = ExternalFileService.instance.navContext ?? (context.mounted ? context : null);
  if (activeContext == null) return;

  switch (action) {
    case ShareReceiverAction.saveLocal:
      await _handleSaveToLocal(activeContext, validPaths);
      break;
    case ShareReceiverAction.saveRemote:
      await _handleSaveToRemote(activeContext, validPaths);
      break;
    case ShareReceiverAction.openDirectly:
      ExternalFileService.instance.openFiles(validPaths);
      break;
  }
}

Future<void> _handleSaveToLocal(BuildContext context, List<String> filePaths) async {
  final l10n = AppLocalizations.of(context);
  final dest = await FolderPickerDialog.show(
    context,
    title: l10n.saveToLocal,
    initialRoot: PlatformPaths.defaultRoot(),
  );
  if (dest == null) return;

  final liveContext = ExternalFileService.instance.navContext ?? (context.mounted ? context : null);
  if (liveContext == null) return;
  await _executeCopy(liveContext, filePaths, dest);
}

Future<void> _handleSaveToRemote(BuildContext context, List<String> filePaths) async {
  final l10n = AppLocalizations.of(context);

  List<RemoteConfigDto> remotes = [];
  try {
    remotes = await StorageService.instance.getRemotes();
  } catch (_) {}

  final liveContext = ExternalFileService.instance.navContext ?? (context.mounted ? context : null);
  if (liveContext == null) return;

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
      final curCtx = ExternalFileService.instance.navContext ?? liveContext;
      final added = await showDialog<bool>(
        context: curCtx,
        builder: (_) => const RemoteWizardDialog(),
      );
      if (added == true) {
        final nextCtx = ExternalFileService.instance.navContext ?? curCtx;
        await _handleSaveToRemote(nextCtx, filePaths);
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

  final curCtx = ExternalFileService.instance.navContext ?? liveContext;
  final dest = await FolderPickerDialog.show(
    curCtx,
    title: '${l10n.saveToRemote} (${chosenRemote.name})',
    initialRoot: 'remote://${chosenRemote.id}',
  );
  if (dest == null) return;

  final finalCtx = ExternalFileService.instance.navContext ?? curCtx;
  await _executeCopy(finalCtx, filePaths, dest);
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
  PickedFolder dest,
) async {
  final l10n = AppLocalizations.of(context);
  final grouped = <String, List<String>>{};
  for (final pth in paths) {
    grouped.putIfAbsent(p.dirname(pth), () => []).add(p.basename(pth));
  }

  bool allSucceeded = true;
  for (final entry in grouped.entries) {
    Future<String> startTask() => TaskService.instance.copy(
      srcRoot: entry.key,
      srcPaths: entry.value,
      dstRoot: dest.root,
      dstDir: dest.relPath,
    );

    try {
      final taskId = await startTask();
      final activeContext = ExternalFileService.instance.navContext ?? context;
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
      final activeContext = ExternalFileService.instance.navContext ?? context;
      ScaffoldMessenger.of(activeContext).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(activeContext).colorScheme.error,
        ),
      );
      return;
    }
  }

  if (!allSucceeded) return;

  final activeContext = ExternalFileService.instance.navContext ?? context;
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

class ShareReceiverContent extends StatelessWidget {
  final List<String> filePaths;
  final ValueChanged<ShareReceiverAction> onAction;
  final VoidCallback onCancel;

  const ShareReceiverContent({
    super.key,
    required this.filePaths,
    required this.onAction,
    required this.onCancel,
  });

  IconData _iconForPath(String filePath) {
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
    final isSingle = filePaths.length == 1;

    int totalBytes = 0;
    for (final fp in filePaths) {
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
                      isSingle ? _iconForPath(filePaths.first) : Icons.folder_copy_outlined,
                      size: 26,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSingle ? p.basename(filePaths.first) : l10n.receivedShareCount(filePaths.length),
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
                    for (int i = 0; i < filePaths.length && i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              _iconForPath(filePaths[i]),
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.basename(filePaths[i]),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (filePaths.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '... (+${filePaths.length - 3})',
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
              onTap: () => onAction(ShareReceiverAction.saveLocal),
            ),

            // Action 2: Save to remote
            _buildActionCard(
              context: context,
              icon: Icons.cloud_upload_outlined,
              iconBgColor: Colors.blue.withValues(alpha: 0.15),
              iconColor: Colors.blue.shade700,
              title: l10n.saveToRemote,
              subtitle: l10n.saveToRemoteSubtitle,
              onTap: () => onAction(ShareReceiverAction.saveRemote),
            ),

            // Action 3: Open directly
            _buildActionCard(
              context: context,
              icon: Icons.open_in_new_rounded,
              iconBgColor: Colors.deepPurple.withValues(alpha: 0.15),
              iconColor: Colors.deepPurple.shade700,
              title: l10n.openDirectly,
              subtitle: l10n.openDirectlySubtitle,
              onTap: () => onAction(ShareReceiverAction.openDirectly),
            ),

            const SizedBox(height: 8),

            // Cancel button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextButton(
                onPressed: onCancel,
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
