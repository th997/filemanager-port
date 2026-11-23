import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dialogs/archive_password_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/metadata.dart';
import '../rust/api/tasks.dart';
import '../services/path_utils.dart';
import '../services/preferences_service.dart';
import '../services/sharing_service.dart';
import '../services/storage_service.dart';
import '../widgets/qr_code_widget.dart';

/// Extracted file operations helpers shared across browser panes, tabs, and
/// dual-pane split views.
class BrowserFileOps {
  /// Share a local folder or single file immediately over LAN HTTP and display
  /// a scannable QR code + copyable link dialog.
  static Future<void> shareViaLan(
    BuildContext context, {
    required String nativeTargetPath,
    required String displayName,
  }) async {
    final l10n = AppLocalizations.of(context);
    try {
      final status = await SharingService.instance.startHttp(
        rootDir: nativeTargetPath,
        readOnly: true,
      );
      if (!context.mounted) return;
      final ips = status.addresses.isNotEmpty ? status.addresses : ['127.0.0.1'];
      final tokenMatch = RegExp(r'[?&]token=([^&]+)').firstMatch(status.url);
      final tokenSuffix = tokenMatch != null ? '/?token=${tokenMatch.group(1)}' : '/';
      String selectedIp = ips.first;

      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            final activeUrl = 'http://$selectedIp:${status.port}$tokenSuffix';
            return AlertDialog(
              title: Text('${l10n.shareViaLan}: $displayName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ips.length > 1) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedIp,
                      isDense: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: ips
                          .map((ip) => DropdownMenuItem(value: ip, child: Text(ip)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => selectedIp = v);
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(ctx).dividerColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: QrCodeWidget(data: activeUrl, size: 210),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.scanQrToConnect,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    activeUrl,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: activeUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.urlCopied)),
                    );
                  },
                  child: Text(l10n.copyUrl),
                ),
                TextButton(
                  onPressed: () {
                    SharingService.instance.stopHttp();
                    Navigator.of(ctx).pop();
                  },
                  child: Text(l10n.stopped),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.close),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Pin a remote file for offline access (respecting the configured LRU cap).
  static Future<void> pinFileOffline(
    BuildContext context, {
    required String remoteRoot,
    required String remotePath,
    required String displayName,
  }) async {
    final l10n = AppLocalizations.of(context);
    final capMb = int.tryParse(PreferencesService.instance.getString('offline.pin_cap_mb') ?? '') ?? 512;
    try {
      await pinRemoteFile(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: remoteRoot,
        remotePath: remotePath,
        maxCacheBytes: BigInt.from(capMb * 1024 * 1024),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pinnedOfflineNotice(displayName))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Copy or move selected items directly to the opposite pane in Dual-Pane mode.
  static Future<bool> transferToOtherPane(
    BuildContext context, {
    required String srcRoot,
    required List<String> srcPaths,
    required String dstRoot,
    required String dstRelPath,
    required bool isMove,
  }) async {
    if (srcPaths.isEmpty) return false;
    final l10n = AppLocalizations.of(context);
    try {
      final taskId = isMove
          ? await startMoveTask(
              srcRoot: srcRoot,
              srcPaths: srcPaths,
              dstRoot: dstRoot,
              dstDir: dstRelPath,
              conflictPolicy: 'rename',
            )
          : await startCopyTask(
              srcRoot: srcRoot,
              srcPaths: srcPaths,
              dstRoot: dstRoot,
              dstDir: dstRelPath,
              dstName: null,
              conflictPolicy: 'rename',
            );
      if (!context.mounted) return false;
      final res = await TaskProgressDialog.show(
        context,
        taskId,
        isMove ? l10n.moveToOtherPane : l10n.copyToOtherPane,
      );
      return res == true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return false;
    }
  }

  /// Extract a local archive, prompting for a password if it is encrypted.
  static Future<bool> extractArchiveInteractive(
    BuildContext context, {
    required String archiveNativePath,
    required String archiveName,
    required String dstDir,
    String? initialPassword,
  }) async {
    final l10n = AppLocalizations.of(context);
    String? password = initialPassword;
    bool wrongPassword = false;

    for (int attempt = 0; attempt < 3; attempt++) {
      if (wrongPassword) {
        if (!context.mounted) return false;
        password = await showArchivePasswordDialog(
          context,
          archiveName: archiveName,
          wrongPassword: true,
        );
        if (password == null) return false;
      }

      final taskId = await startExtractWithPasswordTask(
        archivePath: archiveNativePath,
        dstDir: dstDir,
        password: password,
      );
      if (!context.mounted) return false;
      final outcome = await TaskProgressDialog.show(
        context,
        taskId,
        l10n.extracting,
      );
      if (outcome == true) return true;
      final status = pollTaskProgress(taskId: taskId);
      final err = status?.error ?? '';
      if (err.contains('ARCHIVE_PASSWORD_REQUIRED') ||
          err.contains('ARCHIVE_WRONG_PASSWORD')) {
        wrongPassword = err.contains('ARCHIVE_WRONG_PASSWORD') || password != null;
        if (!wrongPassword) {
          if (!context.mounted) return false;
          password = await showArchivePasswordDialog(
            context,
            archiveName: archiveName,
            wrongPassword: false,
          );
          if (password == null) return false;
          continue;
        }
        continue;
      }
      return false;
    }
    return false;
  }

  /// Show confirmation warning before exporting a Privacy Vault file to an
  /// external app (explaining automatic cleanup on lock).
  static Future<bool> confirmVaultExternalOpen(
    BuildContext context, {
    required String root,
  }) async {
    if (vaultIdFromRoot(root) == null) return true;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.openWith),
        content: Text(l10n.vaultExternalOpenNotice),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.ok)),
        ],
      ),
    );
    return ok == true;
  }
}
