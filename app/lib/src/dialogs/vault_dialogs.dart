import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filemanager/l10n/app_localizations.dart';

import '../rust/api/vault.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/vault_service.dart';
import 'file_picker_dialog.dart';
import 'folder_picker_dialog.dart';

part 'vault/vault_create_dialog.dart';
part 'vault/vault_unlock_dialog.dart';
part 'vault/vault_backup_dialogs.dart';
part 'vault/vault_security_dialog.dart';
part 'vault/vault_info_gc_dialog.dart';

String _formatVaultBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatVaultError(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  final msg = error.toString();
  final cooldownMatch =
      RegExp(r'retry in (\d+) seconds').firstMatch(msg);
  if (cooldownMatch != null) {
    final secs = int.tryParse(cooldownMatch.group(1)!) ?? 30;
    return l10n.cooldownRetryError(secs);
  }
  if (msg.contains('incorrect password or credential')) {
    return l10n.wrongCredentialError;
  }
  if (msg.contains('already exists')) {
    return l10n.privacyFolderAlreadyExists;
  }
  if (msg.contains('does not exist')) {
    return l10n.privacyFolderNotFound;
  }
  return msg.replaceFirst(RegExp(r'^Bad state:\s*'), '');
}

Future<PickedFolder?> _pickDirectory(
  BuildContext context,
  String title,
  String currentPath,
) {
  final split = splitPathToRootAndRel(currentPath);
  final initialRoot = Directory(currentPath).existsSync()
      ? split.root
      : PlatformPaths.defaultRoot();
  final initialRel = Directory(currentPath).existsSync() ? split.relPath : '';
  return FolderPickerDialog.show(
    context,
    title: title,
    initialRoot: initialRoot,
    initialPath: initialRel,
  );
}

