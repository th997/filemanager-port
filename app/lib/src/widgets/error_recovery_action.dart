import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../dialogs/archive_password_dialog.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../pages/remotes_page.dart';
import '../pages/storage_analyzer_page.dart';
import '../rust/api/file_manager.dart' show invalidateRoot, setArchivePassword;
import '../rust/api/remotes.dart';
import '../services/error_text.dart';
import '../services/permission_service.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';

/// Extracts a remote connection ID from a `remote://<id>` or
/// `archive://remote://<id>/...` root string, if present.
String? extractRemoteIdFromRoot(String? root) {
  if (root == null || root.isEmpty) return null;
  var clean = root;
  if (clean.startsWith('archive://')) {
    clean = clean.substring('archive://'.length);
  }
  if (!clean.startsWith('remote://')) return null;
  final rest = clean.substring('remote://'.length);
  final slashIdx = rest.indexOf('/');
  final id = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
  return id.isEmpty ? null : id;
}

/// Returns the localized label and icon for a recoverable [ErrorRecoveryKind],
/// or `null` when no dedicated action applies.
({String label, IconData icon})? recoveryActionVisuals(
  ErrorRecoveryKind kind,
  AppLocalizations l10n, {
  bool includeNetworkRetry = true,
}) {
  switch (kind) {
    case ErrorRecoveryKind.storagePermission:
      return (
        label: l10n.recoveryGrantPermission,
        icon: Icons.security_outlined,
      );
    case ErrorRecoveryKind.remoteCredentials:
    case ErrorRecoveryKind.hostKeyTrust:
      return (
        label: l10n.recoveryEditConnection,
        icon: Icons.settings_ethernet_outlined,
      );
    case ErrorRecoveryKind.archivePassword:
      return (
        label: l10n.recoveryEnterPassword,
        icon: Icons.password_outlined,
      );
    case ErrorRecoveryKind.storageSpace:
      return (
        label: l10n.recoveryFreeUpSpace,
        icon: Icons.pie_chart_outline,
      );
    case ErrorRecoveryKind.networkRetry:
      if (!includeNetworkRetry) return null;
      return (label: l10n.retry, icon: Icons.refresh);
    case ErrorRecoveryKind.none:
      return null;
  }
}

/// Executes the appropriate one-tap recovery flow for [kind].
Future<void> performErrorRecovery(
  BuildContext context, {
  required ErrorRecoveryKind kind,
  String? root,
  RemoteConfigDto? remoteOverride,
  VoidCallback? onRetry,
}) async {
  switch (kind) {
    case ErrorRecoveryKind.storagePermission:
      if (Platform.isAndroid) {
        await PermissionService.instance.requestStorageAccess();
      } else if (Platform.isIOS) {
        await openAppSettings();
      } else {
        if (!context.mounted) return;
        final l10n = AppLocalizations.of(context);
        await FolderPickerDialog.show(
          context,
          title: l10n.recoveryGrantPermission,
          confirmLabel: l10n.ok,
        );
      }
      onRetry?.call();
    case ErrorRecoveryKind.remoteCredentials:
    case ErrorRecoveryKind.hostKeyTrust:
      RemoteConfigDto? target = remoteOverride;
      if (target == null) {
        final remoteId = extractRemoteIdFromRoot(root);
        if (remoteId != null) {
          try {
            final all = await StorageService.instance.getRemotes();
            for (final r in all) {
              if (r.id == remoteId) {
                target = r;
                break;
              }
            }
          } catch (_) {}
        }
      }
      if (!context.mounted) return;
      if (target != null) {
        final updated = await showDialog<RemoteConfigDto>(
          context: context,
          builder: (_) => RemoteWizardDialog(initialConfig: target),
        );
        if (updated != null) {
          invalidateRoot(root: 'remote://${updated.id}');
          onRetry?.call();
        }
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RemotesPage()),
        );
        onRetry?.call();
      }
    case ErrorRecoveryKind.archivePassword:
      if (!context.mounted) return;
      final archiveRoot = (root != null && root.startsWith('archive://'))
          ? root
          : null;
      final archiveName = archiveRoot?.split('/').last ?? 'Archive';
      final pw = await showArchivePasswordDialog(
        context,
        archiveName: archiveName,
        wrongPassword: true,
      );
      if (pw != null && pw.isNotEmpty) {
        if (archiveRoot != null) {
          setArchivePassword(archiveRoot: archiveRoot, password: pw);
        }
        onRetry?.call();
      }
    case ErrorRecoveryKind.storageSpace:
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StorageAnalyzerPage(
            root: PlatformPaths.defaultRoot(),
            title: l10n.localStorage,
          ),
        ),
      );
    case ErrorRecoveryKind.networkRetry:
      onRetry?.call();
    case ErrorRecoveryKind.none:
      break;
  }
}

/// Action button rendered inside inline error states (e.g., [BrowserPage],
/// [SyncPage]) to let users fix permissions, credentials, archive passwords, or
/// disk space in one tap.
class ErrorRecoveryActionButton extends StatelessWidget {
  final Object rawError;
  final String? root;
  final RemoteConfigDto? remoteOverride;
  final VoidCallback? onRetry;
  final bool includeNetworkRetry;
  final VoidCallback? onOverrideAction;

  const ErrorRecoveryActionButton({
    super.key,
    required this.rawError,
    this.root,
    this.remoteOverride,
    this.onRetry,
    this.includeNetworkRetry = true,
    this.onOverrideAction,
  });

  /// Builds a [SnackBarAction] for transient error SnackBars when a recovery
  /// action applies to [rawError].
  static SnackBarAction? buildSnackBarAction(
    BuildContext context, {
    required Object rawError,
    String? root,
    RemoteConfigDto? remoteOverride,
    VoidCallback? onRetry,
  }) {
    final kind = detectErrorRecovery(rawError);
    final l10n = AppLocalizations.of(context);
    final visuals = recoveryActionVisuals(kind, l10n);
    if (visuals == null) return null;
    return SnackBarAction(
      label: visuals.label,
      onPressed: () {
        performErrorRecovery(
          context,
          kind: kind,
          root: root,
          remoteOverride: remoteOverride,
          onRetry: onRetry,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = detectErrorRecovery(rawError);
    final l10n = AppLocalizations.of(context);
    final visuals = recoveryActionVisuals(
      kind,
      l10n,
      includeNetworkRetry: includeNetworkRetry,
    );
    if (visuals == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: ValueKey('error_recovery_${kind.name}'),
      icon: Icon(visuals.icon, size: 17),
      label: Text(visuals.label),
      onPressed: () {
        if (onOverrideAction != null) {
          onOverrideAction!();
          return;
        }
        performErrorRecovery(
          context,
          kind: kind,
          root: root,
          remoteOverride: remoteOverride,
          onRetry: onRetry,
        );
      },
    );
  }
}
