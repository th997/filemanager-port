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

class CreateVaultDialog extends StatefulWidget {
  const CreateVaultDialog({super.key});

  static Future<UnlockedVaultDto?> show(BuildContext context) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateVaultDialog(),
    );
  }

  @override
  State<CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<CreateVaultDialog> {
  final _nameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();

  String _cipher = 'aes128gcm';
  String _authMode = 'password';
  late String _storageDir = PlatformPaths.defaultVaultStorageDir();
  bool _systemAuthAvailable = false;
  bool _obscurePwd = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    VaultService.instance.canUseSystemAuth().then((ok) {
      if (mounted) setState(() => _systemAuthAvailable = ok);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _changeStorageDir() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickDirectory(
      context,
      l10n.storageLocation,
      _storageDir,
    );
    if (picked != null && mounted) {
      setState(() {
        _storageDir = joinNative(picked.root, picked.relPath);
      });
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (!isValidFileName(name)) {
      setState(() => _error = l10n.invalidFileNameError);
      return;
    }

    String? password;
    if (_authMode == 'password') {
      final pwdErr = VaultService.validatePassword(_pwdCtrl.text);
      if (pwdErr != PasswordValidationError.none) {
        setState(() => _error = l10n.passwordLengthError);
        return;
      }
      if (_pwdCtrl.text != _confirmPwdCtrl.text) {
        setState(() => _error = l10n.passwordMismatchError);
        return;
      }
      password = _pwdCtrl.text;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final vault = await VaultService.instance.createVault(
        name: name,
        storageRoot: _storageDir,
        cipher: _cipher,
        authMode: _authMode,
        password: password,
        systemAuthReason: l10n.setupSystemAuthPrompt,
      );
      if (mounted) {
        Navigator.of(context).pop(vault);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final defaultDir = PlatformPaths.defaultVaultStorageDir();

    return AlertDialog(
      title: Text(l10n.createPrivacyFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameCtrl,
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: l10n.privacyFolderName,
                  hintText: l10n.privacyFolderNameHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _authMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.credentialMethod,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'password',
                    child: Text(l10n.credentialPassword),
                  ),
                  DropdownMenuItem(
                    value: 'system',
                    enabled: _systemAuthAvailable,
                    child: Text(
                      _systemAuthAvailable
                          ? l10n.credentialSystem
                          : '${l10n.credentialSystem} (${l10n.credentialSystemUnavailable})',
                    ),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() {
                            _authMode = val;
                            _error = null;
                          });
                        }
                      },
              ),
              if (_authMode == 'password') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  enabled: !_submitting,
                  obscureText: _obscurePwd,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.privacyPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePwd ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmPwdCtrl,
                  enabled: !_submitting,
                  obscureText: _obscurePwd,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.privacyConfirmPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _cipher,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.encryptionAlgorithm,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'aes128gcm',
                    child: Text(l10n.cipherAes128Gcm),
                  ),
                  DropdownMenuItem(
                    value: 'aes256gcm',
                    child: Text(l10n.cipherAes256Gcm),
                  ),
                  DropdownMenuItem(
                    value: 'none',
                    child: Text(l10n.cipherNone),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (val) {
                        if (val != null) setState(() => _cipher = val);
                      },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.storageLocation,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (_storageDir != defaultDir)
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _storageDir = defaultDir),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: Text(l10n.useDefaultLocation,
                                style: const TextStyle(fontSize: 11)),
                          ),
                        TextButton(
                          onPressed: _submitting ? null : _changeStorageDir,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(l10n.changeLocation,
                              style: const TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    Text(
                      _storageDir,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.create),
        ),
      ],
    );
  }
}

class OpenVaultDialog extends StatefulWidget {
  const OpenVaultDialog({super.key});

  static Future<UnlockedVaultDto?> show(BuildContext context) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const OpenVaultDialog(),
    );
  }

  @override
  State<OpenVaultDialog> createState() => _OpenVaultDialogState();
}

class _OpenVaultDialogState extends State<OpenVaultDialog> {
  final _nameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  VaultLookupDto? _lookup;
  bool _busy = false;
  bool _obscurePwd = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupName() async {
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.pleaseEnterName);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await VaultService.instance.lookupVault(name);
      if (!mounted) return;
      if (!res.exists) {
        setState(() {
          _busy = false;
          _error = l10n.privacyFolderNotFound;
        });
        return;
      }
      if (res.unlocked && res.id != null) {
        final existing = VaultService.instance.findUnlockedById(res.id!);
        if (existing != null) {
          Navigator.of(context).pop(existing);
          return;
        }
      }
      if (res.cooldownSecs > BigInt.zero) {
        setState(() {
          _busy = false;
          _lookup = res;
          _error = l10n.cooldownRetryError(res.cooldownSecs.toInt());
        });
        return;
      }

      setState(() {
        _busy = false;
        _lookup = res;
      });
      if (res.authMode == 'system') {
        await _unlock();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Future<void> _unlock() async {
    final lookup = _lookup;
    if (lookup == null) return;
    final l10n = AppLocalizations.of(context);
    final name = _nameCtrl.text.trim();
    if (lookup.authMode == 'password' && _pwdCtrl.text.isEmpty) {
      setState(() => _error = l10n.passwordLengthError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vault = await VaultService.instance.unlockVault(
        name: name,
        lookup: lookup,
        password: _pwdCtrl.text,
        systemAuthReason: l10n.unlockWithSystemPrompt(name),
      );
      if (mounted) {
        Navigator.of(context).pop(vault);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lookup = _lookup;

    return AlertDialog(
      title: Text(l10n.openPrivacyFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_busy && lookup == null,
              autofocus: lookup == null,
              onSubmitted: (_) {
                if (lookup == null && !_busy) _lookupName();
              },
              decoration: InputDecoration(
                labelText: l10n.privacyFolderName,
                hintText: l10n.privacyFolderNameHint,
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
              ),
            ),
            if (lookup != null) ...[
              const SizedBox(height: 12),
              if (lookup.authMode == 'password')
                TextField(
                  controller: _pwdCtrl,
                  enabled: !_busy,
                  autofocus: true,
                  obscureText: _obscurePwd,
                  onSubmitted: (_) {
                    if (!_busy) _unlock();
                  },
                  decoration: InputDecoration(
                    labelText: l10n.privacyPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePwd ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePwd = !_obscurePwd),
                    ),
                  ),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fingerprint),
                  title: Text(l10n.credentialSystem),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (lookup != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _lookup = null;
                      _pwdCtrl.clear();
                      _error = null;
                    }),
            child: Text(MaterialLocalizations.of(context).backButtonTooltip),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : (lookup == null ? _lookupName : _unlock),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(lookup == null ? l10n.nextStep : l10n.unlockAction),
        ),
      ],
    );
  }
}

class BackupVaultDialog extends StatefulWidget {
  const BackupVaultDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BackupVaultDialog(),
    );
  }

  @override
  State<BackupVaultDialog> createState() => _BackupVaultDialogState();
}

class _BackupVaultDialogState extends State<BackupVaultDialog> {
  UnlockedVaultDto? _selectedVault;
  String? _destDir;
  final _backupPwdCtrl = TextEditingController();
  final _backupPwdConfirmCtrl = TextEditingController();
  bool _obscurePwd = true;
  bool _exporting = false;
  bool _cancelling = false;
  String? _activeTaskId;
  Timer? _pollTimer;
  VaultBackupTaskProgressDto? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    final unlocked = VaultService.instance.unlockedVaults;
    if (unlocked.length == 1) {
      _selectedVault = unlocked.first;
    }
    _destDir = PlatformPaths.defaultRoot();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_activeTaskId != null) {
      VaultService.instance.cancelBackupTask(_activeTaskId!);
      VaultService.instance.removeBackupTask(_activeTaskId!);
    }
    _backupPwdCtrl.dispose();
    _backupPwdConfirmCtrl.dispose();
    super.dispose();
  }

  bool get _needsBackupPassword =>
      _selectedVault != null &&
      _selectedVault!.authMode == 'system' &&
      _selectedVault!.cipher != 'none';

  Future<void> _unlockAnother() async {
    final v = await OpenVaultDialog.show(context);
    if (v != null && mounted) {
      setState(() {
        _selectedVault = v;
        _error = null;
      });
    }
  }

  Future<void> _pickDestDir() async {
    final l10n = AppLocalizations.of(context);
    final split = splitPathToRootAndRel(_destDir ?? PlatformPaths.defaultRoot());
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.selectBackupDestFile,
      initialRoot: split.root,
      initialPath: split.relPath,
    );
    if (picked != null && mounted) {
      setState(() {
        _destDir = joinNative(picked.root, picked.relPath);
      });
    }
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context);
    final vault = _selectedVault;
    if (vault == null) return;
    final destDir = _destDir;
    if (destDir == null || destDir.isEmpty) return;

    String? backupPwd;
    if (_needsBackupPassword) {
      if (VaultService.validatePassword(_backupPwdCtrl.text) !=
          PasswordValidationError.none) {
        setState(() => _error = l10n.passwordLengthError);
        return;
      }
      if (_backupPwdCtrl.text != _backupPwdConfirmCtrl.text) {
        setState(() => _error = l10n.passwordMismatchError);
        return;
      }
      backupPwd = _backupPwdCtrl.text;
    }

    var safeName =
        vault.name.trim().replaceAll(RegExp(r'[/\\:*?"<>|\s]+'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      safeName = 'vault';
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = joinNative(destDir, '${safeName}_$stamp.fpmvault');

    setState(() {
      _exporting = true;
      _cancelling = false;
      _progress = null;
      _error = null;
    });
    try {
      final taskId = await VaultService.instance.startExportBackup(
        vaultId: vault.id,
        backupPassword: backupPwd,
        destArchivePath: destPath,
      );
      if (!mounted) {
        VaultService.instance.cancelBackupTask(taskId);
        VaultService.instance.removeBackupTask(taskId);
        return;
      }
      _activeTaskId = taskId;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _pollExportTask(destPath),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _exporting = false;
          _cancelling = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  void _pollExportTask(String destPath) {
    final taskId = _activeTaskId;
    if (taskId == null || !mounted) return;
    final p = VaultService.instance.getBackupTaskProgress(taskId);
    if (p == null) return;

    if (p.state == 'running') {
      setState(() => _progress = p);
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _activeTaskId = null;
    VaultService.instance.removeBackupTask(taskId);

    if (p.state == 'completed') {
      Navigator.of(context).pop(destPath);
      return;
    }

    final l10n = AppLocalizations.of(context);
    setState(() {
      _exporting = false;
      _cancelling = false;
      _progress = null;
      _error = p.state == 'cancelled'
          ? l10n.backupCancelledNotice
          : _formatVaultError(context, p.error ?? 'Export failed');
    });
  }

  void _cancelExport() {
    final taskId = _activeTaskId;
    if (taskId == null) {
      if (!_exporting) Navigator.of(context).pop(null);
      return;
    }
    setState(() => _cancelling = true);
    VaultService.instance.cancelBackupTask(taskId);
  }

  Widget _buildExportProgress(BuildContext context, AppLocalizations l10n) {
    final p = _progress;
    final total = p?.totalBytes.toInt() ?? 0;
    final done = p?.doneBytes.toInt() ?? 0;
    final pct = ((p?.fraction ?? 0.0) * 100).round().clamp(0, 100);
    final label = _cancelling
        ? l10n.backupCancelling
        : (total > 0
            ? l10n.backupProgressLabel(
                _formatVaultBytes(done),
                _formatVaultBytes(total),
                pct,
              )
            : l10n.backupExport);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        LinearProgressIndicator(value: total > 0 ? p?.fraction : null),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unlocked = VaultService.instance.unlockedVaults;

    return AlertDialog(
      title: Text(l10n.backupPrivacyFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.selectBackupSourceVault,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (unlocked.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedVault?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final v in unlocked)
                      DropdownMenuItem(
                        value: v.id,
                        child: Text('${v.name} (${v.cipher})'),
                      ),
                  ],
                  onChanged: _exporting
                      ? null
                      : (id) {
                          setState(() {
                            _selectedVault = unlocked.firstWhere((e) => e.id == id);
                            _error = null;
                          });
                        },
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _exporting ? null : _unlockAnother,
                  icon: const Icon(Icons.lock_open, size: 16),
                  label: Text(l10n.openPrivacyFolder),
                ),
              ),
              if (_needsBackupPassword) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.backupPasswordRequiredNotice,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _backupPwdCtrl,
                  enabled: !_exporting,
                  obscureText: _obscurePwd,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.backupPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePwd ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePwd = !_obscurePwd),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _backupPwdConfirmCtrl,
                  enabled: !_exporting,
                  obscureText: _obscurePwd,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.privacyConfirmPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.selectBackupDestFile,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: Text(_destDir ?? '', style: const TextStyle(fontSize: 11)),
                trailing: TextButton(
                  onPressed: _exporting ? null : _pickDestDir,
                  child: Text(l10n.changeLocation),
                ),
              ),
              if (_exporting) _buildExportProgress(context, l10n),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_exporting && (_activeTaskId == null || _cancelling))
              ? null
              : (_exporting ? _cancelExport : () => Navigator.of(context).pop(null)),
          child: Text(_cancelling ? l10n.backupCancelling : l10n.cancel),
        ),
        FilledButton(
          onPressed: (_exporting || _selectedVault == null) ? null : _export,
          child: _exporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.backupExport),
        ),
      ],
    );
  }
}

class ImportVaultDialog extends StatefulWidget {
  const ImportVaultDialog({super.key});

  static Future<UnlockedVaultDto?> show(BuildContext context) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ImportVaultDialog(),
    );
  }

  @override
  State<ImportVaultDialog> createState() => _ImportVaultDialogState();
}

class _ImportVaultDialogState extends State<ImportVaultDialog> {
  String? _archivePath;
  VaultBackupInfoDto? _info;
  final _nameCtrl = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _backupPwdCtrl = TextEditingController();
  final _newLocalPwdCtrl = TextEditingController();
  String _targetAuthMode = 'password';
  late String _storageDir = PlatformPaths.defaultVaultStorageDir();
  bool _systemAuthAvailable = false;
  bool _obscurePwd = true;
  bool _requireManualName = false;
  bool _busy = false;
  bool _cancelling = false;
  String? _activeTaskId;
  Timer? _pollTimer;
  VaultBackupTaskProgressDto? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    VaultService.instance.canUseSystemAuth().then((ok) {
      if (mounted) setState(() => _systemAuthAvailable = ok);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_activeTaskId != null) {
      VaultService.instance.cancelBackupTask(_activeTaskId!);
      VaultService.instance.removeBackupTask(_activeTaskId!);
    }
    _nameCtrl.dispose();
    _nameFocusNode.dispose();
    _backupPwdCtrl.dispose();
    _newLocalPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickArchive() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FilePickerDialog.show(
      context,
      title: l10n.selectBackupArchive,
      initialRoot: PlatformPaths.defaultRoot(),
    );
    if (picked == null || picked.paths.isEmpty || !mounted) return;
    final fullPath = joinNative(picked.root, picked.paths.first);
    setState(() {
      _busy = true;
      _requireManualName = false;
      _nameCtrl.clear();
      _error = null;
    });
    try {
      final info = await VaultService.instance.inspectBackup(fullPath);
      if (!mounted) return;
      var requireManualName = false;
      String? conflictError;
      final originalName = info.originalName?.trim();
      if (originalName != null && originalName.isNotEmpty) {
        final lookup = await VaultService.instance.lookupVault(originalName);
        if (!mounted) return;
        if (lookup.exists) {
          requireManualName = true;
          conflictError = l10n.importNameExistsEnterNew(originalName);
        }
      } else if (!info.requiresPassword) {
        requireManualName = true;
        conflictError = l10n.importEnterFolderNamePrompt;
      }
      setState(() {
        _archivePath = fullPath;
        _info = info;
        _requireManualName = requireManualName;
        _error = conflictError;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Future<void> _changeStorageDir() async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickDirectory(
      context,
      l10n.storageLocation,
      _storageDir,
    );
    if (picked != null && mounted) {
      setState(() {
        _storageDir = joinNative(picked.root, picked.relPath);
      });
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final archivePath = _archivePath;
    final info = _info;
    if (archivePath == null || info == null) return;

    final wasManualName = _requireManualName;
    String? manualVaultName;
    if (wasManualName) {
      final name = _nameCtrl.text.trim();
      if (!isValidFileName(name)) {
        setState(() => _error = l10n.invalidFileNameError);
        return;
      }
      manualVaultName = name;
    }

    if (info.requiresPassword && _backupPwdCtrl.text.isEmpty) {
      setState(() => _error = l10n.passwordLengthError);
      return;
    }

    String? newLocalPwd;
    if (_targetAuthMode == 'password') {
      final candidate = _newLocalPwdCtrl.text.isNotEmpty
          ? _newLocalPwdCtrl.text
          : _backupPwdCtrl.text;
      if (VaultService.validatePassword(candidate) !=
          PasswordValidationError.none) {
        setState(() => _error = l10n.passwordLengthError);
        return;
      }
      newLocalPwd = candidate;
    }

    setState(() {
      _busy = true;
      _cancelling = false;
      _progress = null;
      _error = null;
    });
    try {
      if (_targetAuthMode == 'system') {
        final supported = await VaultService.instance.canUseSystemAuth();
        if (!supported) {
          throw StateError('System authentication is not available on this device');
        }
        final authed = await VaultService.instance.authenticateSystem(
          l10n.setupSystemAuthPrompt,
        );
        if (!authed) {
          throw const VaultAuthCancelledException();
        }
      }

      final taskId = await VaultService.instance.startImportBackup(
        archivePath: archivePath,
        vaultName: manualVaultName,
        targetStorageRoot: _storageDir,
        backupPassword: info.requiresPassword ? _backupPwdCtrl.text : null,
        targetAuthMode: _targetAuthMode,
        newLocalPassword: newLocalPwd,
      );
      if (!mounted) {
        VaultService.instance.cancelBackupTask(taskId);
        VaultService.instance.removeBackupTask(taskId);
        return;
      }
      _activeTaskId = taskId;
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _pollImportTask(wasManualName: wasManualName),
      );
    } catch (e) {
      _handleImportFailure(e, wasManualName: wasManualName);
    }
  }

  Future<void> _pollImportTask({required bool wasManualName}) async {
    final taskId = _activeTaskId;
    if (taskId == null || !mounted) return;
    final p = VaultService.instance.getBackupTaskProgress(taskId);
    if (p == null) return;

    if (p.state == 'running') {
      setState(() => _progress = p);
      return;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _activeTaskId = null;
    VaultService.instance.removeBackupTask(taskId);

    if (p.state == 'completed' && p.imported != null) {
      try {
        final vault = await VaultService.instance.finalizeImportedVault(
          p.imported!,
          targetAuthMode: _targetAuthMode,
        );
        if (mounted) {
          Navigator.of(context).pop(vault);
        }
      } catch (e) {
        _handleImportFailure(e, wasManualName: wasManualName);
      }
      return;
    }

    if (p.state == 'cancelled') {
      final l10n = AppLocalizations.of(context);
      setState(() {
        _busy = false;
        _cancelling = false;
        _progress = null;
        _error = l10n.backupCancelledNotice;
      });
      return;
    }

    _handleImportFailure(p.error ?? 'Import failed', wasManualName: wasManualName);
  }

  void _handleImportFailure(Object e, {required bool wasManualName}) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final existing = VaultService.extractAlreadyExistsName(e);
    if (existing != null) {
      setState(() {
        _busy = false;
        _cancelling = false;
        _progress = null;
        _requireManualName = true;
        if (!wasManualName) {
          _nameCtrl.clear();
        }
        _error = l10n.importNameExistsEnterNew(existing);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocusNode.requestFocus();
      });
    } else if (e.toString().contains('privacy folder name is required')) {
      setState(() {
        _busy = false;
        _cancelling = false;
        _progress = null;
        _requireManualName = true;
        _error = l10n.importEnterFolderNamePrompt;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocusNode.requestFocus();
      });
    } else {
      setState(() {
        _busy = false;
        _cancelling = false;
        _progress = null;
        _error = _formatVaultError(context, e);
      });
    }
  }

  void _cancelImport() {
    final taskId = _activeTaskId;
    if (taskId == null) {
      if (!_busy) Navigator.of(context).pop(null);
      return;
    }
    setState(() => _cancelling = true);
    VaultService.instance.cancelBackupTask(taskId);
  }

  Widget _buildImportProgress(BuildContext context, AppLocalizations l10n) {
    final p = _progress;
    final total = p?.totalBytes.toInt() ?? 0;
    final done = p?.doneBytes.toInt() ?? 0;
    final pct = ((p?.fraction ?? 0.0) * 100).round().clamp(0, 100);
    final label = _cancelling
        ? l10n.backupCancelling
        : (total > 0
            ? l10n.backupProgressLabel(
                _formatVaultBytes(done),
                _formatVaultBytes(total),
                pct,
              )
            : l10n.importAction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        LinearProgressIndicator(value: total > 0 ? p?.fraction : null),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final info = _info;

    return AlertDialog(
      title: Text(l10n.importPrivacyFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickArchive,
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: Text(_archivePath == null
                    ? l10n.selectBackupArchive
                    : _archivePath!.split(RegExp(r'[/\\]')).last),
              ),
              if (info != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.backupArchiveSummary(
                    info.cipher.toUpperCase(),
                    info.objectCount,
                  ),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_requireManualName)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      info.originalName != null
                          ? l10n.importKeepOriginalName(info.originalName!)
                          : l10n.importWillKeepOriginalName,
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                else
                  TextField(
                    controller: _nameCtrl,
                    focusNode: _nameFocusNode,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l10n.importNewFolderNameLabel,
                      hintText: l10n.privacyFolderNameHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                if (info.requiresPassword) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _backupPwdCtrl,
                    enabled: !_busy,
                    obscureText: _obscurePwd,
                    decoration: InputDecoration(
                      labelText: l10n.backupPasswordToVerify,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePwd ? Icons.visibility : Icons.visibility_off,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePwd = !_obscurePwd),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _targetAuthMode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.localUnlockAfterImport,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'password',
                      child: Text(l10n.credentialPassword),
                    ),
                    DropdownMenuItem(
                      value: 'system',
                      enabled: _systemAuthAvailable,
                      child: Text(
                        _systemAuthAvailable
                            ? l10n.credentialSystem
                            : '${l10n.credentialSystem} (${l10n.credentialSystemUnavailable})',
                      ),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _targetAuthMode = v);
                        },
                ),
                if (_targetAuthMode == 'password') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newLocalPwdCtrl,
                    enabled: !_busy,
                    obscureText: _obscurePwd,
                    maxLength: 128,
                    decoration: InputDecoration(
                      labelText: info.requiresPassword
                          ? l10n.newLocalPasswordOptional
                          : l10n.privacyPasswordLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.storageLocation,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text(_storageDir, style: const TextStyle(fontSize: 11)),
                  trailing: TextButton(
                    onPressed: _busy ? null : _changeStorageDir,
                    child: Text(l10n.changeLocation),
                  ),
                ),
              ],
              if (_busy && _activeTaskId != null) _buildImportProgress(context, l10n),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_busy && (_activeTaskId == null || _cancelling))
              ? null
              : (_busy ? _cancelImport : () => Navigator.of(context).pop(null)),
          child: Text(_cancelling ? l10n.backupCancelling : l10n.cancel),
        ),
        FilledButton(
          onPressed: (_busy || info == null) ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.importAction),
        ),
      ],
    );
  }
}

class RenameVaultDialog extends StatefulWidget {
  final UnlockedVaultDto vault;

  const RenameVaultDialog({super.key, required this.vault});

  static Future<UnlockedVaultDto?> show(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RenameVaultDialog(vault: vault),
    );
  }

  @override
  State<RenameVaultDialog> createState() => _RenameVaultDialogState();
}

class _RenameVaultDialogState extends State<RenameVaultDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.vault.name);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final newName = _ctrl.text.trim();
    if (!isValidFileName(newName)) {
      setState(() => _error = l10n.invalidFileNameError);
      return;
    }
    if (newName == widget.vault.name) {
      Navigator.of(context).pop(widget.vault);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await VaultService.instance.renameVault(
        vaultId: widget.vault.id,
        newName: newName,
      );
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.renamePrivacyFolder),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.privacyFolderName,
                hintText: l10n.privacyFolderNameHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _busy ? null : _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}

class DeleteVaultDialog extends StatefulWidget {
  final UnlockedVaultDto vault;
  final Future<void> Function(String vaultId)? onDeleteOverride;

  const DeleteVaultDialog({
    super.key,
    required this.vault,
    this.onDeleteOverride,
  });

  static Future<bool> show(
    BuildContext context,
    UnlockedVaultDto vault,
  ) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteVaultDialog(vault: vault),
    );
    return res ?? false;
  }

  @override
  State<DeleteVaultDialog> createState() => _DeleteVaultDialogState();
}

class _DeleteVaultDialogState extends State<DeleteVaultDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _nameMatches => _ctrl.text.trim() == widget.vault.name;

  Future<void> _submit() async {
    if (!_nameMatches || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deleter =
          widget.onDeleteOverride ?? VaultService.instance.deleteVault;
      await deleter(widget.vault.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.deletePrivacyFolder)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.deletePrivacyFolderWarning(widget.vault.name),
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.deletePrivacyFolderConfirmLabel(widget.vault.name),
                hintText: widget.vault.name,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _nameMatches && !_busy ? _submit() : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: colors.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: (_busy || !_nameMatches) ? null : _submit,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onError,
                  ),
                )
              : Text(l10n.delete),
        ),
      ],
    );
  }
}

class ChangeVaultSecurityDialog extends StatefulWidget {
  final UnlockedVaultDto vault;
  final bool? systemAuthAvailableOverride;
  final Future<UnlockedVaultDto> Function({
    required String vaultId,
    String? currentPassword,
    required String newPassword,
    required String systemAuthReason,
  })? onChangePasswordOverride;
  final Future<UnlockedVaultDto> Function({
    required String vaultId,
    required String currentPassword,
    required String systemAuthReason,
  })? onSwitchToSystemOverride;

  const ChangeVaultSecurityDialog({
    super.key,
    required this.vault,
    this.systemAuthAvailableOverride,
    this.onChangePasswordOverride,
    this.onSwitchToSystemOverride,
  });

  static Future<UnlockedVaultDto?> show(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeVaultSecurityDialog(vault: vault),
    );
  }

  @override
  State<ChangeVaultSecurityDialog> createState() =>
      _ChangeVaultSecurityDialogState();
}

class _ChangeVaultSecurityDialogState extends State<ChangeVaultSecurityDialog> {
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  late String _action =
      widget.vault.authMode == 'system' ? 'to_password' : 'change_password';
  late bool _systemAuthAvailable =
      widget.systemAuthAvailableOverride ?? false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.systemAuthAvailableOverride == null) {
      VaultService.instance.canUseSystemAuth().then((ok) {
        if (mounted) setState(() => _systemAuthAvailable = ok);
      });
    }
  }

  @override
  void dispose() {
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  bool get _needsCurrentPassword => widget.vault.authMode == 'password';
  bool get _needsNewPassword => _action != 'to_system';

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_needsCurrentPassword && _currentPwdCtrl.text.isEmpty) {
      setState(() => _error = l10n.passwordLengthError);
      return;
    }

    if (_needsNewPassword) {
      if (VaultService.validatePassword(_newPwdCtrl.text) !=
          PasswordValidationError.none) {
        setState(() => _error = l10n.passwordLengthError);
        return;
      }
      if (_newPwdCtrl.text != _confirmPwdCtrl.text) {
        setState(() => _error = l10n.passwordMismatchError);
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final UnlockedVaultDto updated;
      if (_action == 'to_system') {
        final switcher = widget.onSwitchToSystemOverride ??
            VaultService.instance.switchToSystemAuth;
        updated = await switcher(
          vaultId: widget.vault.id,
          currentPassword: _currentPwdCtrl.text,
          systemAuthReason: l10n.setupSystemAuthPrompt,
        );
      } else {
        final changer = widget.onChangePasswordOverride ??
            VaultService.instance.changePassword;
        updated = await changer(
          vaultId: widget.vault.id,
          currentPassword: _needsCurrentPassword ? _currentPwdCtrl.text : null,
          newPassword: _newPwdCtrl.text,
          systemAuthReason: l10n.unlockWithSystemPrompt(widget.vault.name),
        );
      }
      if (mounted) {
        Navigator.of(context).pop(updated);
      }
    } on VaultAuthCancelledException {
      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final isPasswordVault = widget.vault.authMode == 'password';

    return AlertDialog(
      title: Text(l10n.vaultSecuritySettings),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _action,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.credentialMethod,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                items: isPasswordVault
                    ? [
                        DropdownMenuItem(
                          value: 'change_password',
                          child: Text(l10n.vaultChangePasswordOption),
                        ),
                        DropdownMenuItem(
                          value: 'to_system',
                          enabled: _systemAuthAvailable,
                          child: Text(
                            _systemAuthAvailable
                                ? l10n.vaultSwitchToSystemOption
                                : '${l10n.vaultSwitchToSystemOption} (${l10n.credentialSystemUnavailable})',
                          ),
                        ),
                      ]
                    : [
                        DropdownMenuItem(
                          value: 'to_password',
                          child: Text(l10n.vaultSwitchToPasswordOption),
                        ),
                      ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _action = v;
                            _error = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (_action == 'to_system'
                          ? colors.tertiaryContainer
                          : colors.primaryContainer)
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _action == 'to_system'
                      ? l10n.vaultSwitchToSystemBackupNotice
                      : l10n.vaultOldBackupsPasswordNotice,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              if (_needsCurrentPassword) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _currentPwdCtrl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.vaultCurrentPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
              if (_needsNewPassword) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _newPwdCtrl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.vaultNewPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                    suffixIcon: !_needsCurrentPassword
                        ? IconButton(
                            icon: Icon(
                              _obscure ? Icons.visibility : Icons.visibility_off,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmPwdCtrl,
                  enabled: !_busy,
                  obscureText: _obscure,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: l10n.privacyConfirmPasswordLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _busy ? null : _submit(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}

class VaultInfoDialog extends StatefulWidget {
  final UnlockedVaultDto vault;
  final Future<VaultStatsDto> Function(String vaultId)? onGetStatsOverride;
  final Future<VaultGcResultDto> Function(String vaultId)? onGcOverride;

  const VaultInfoDialog({
    super.key,
    required this.vault,
    this.onGetStatsOverride,
    this.onGcOverride,
  });

  static Future<void> show(
    BuildContext context,
    UnlockedVaultDto vault,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => VaultInfoDialog(vault: vault),
    );
  }

  @override
  State<VaultInfoDialog> createState() => _VaultInfoDialogState();
}

class _VaultInfoDialogState extends State<VaultInfoDialog> {
  VaultStatsDto? _stats;
  bool _loading = true;
  bool _cleaning = false;
  String? _statusMessage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final getter =
          widget.onGetStatsOverride ?? VaultService.instance.getStats;
      final stats = await getter(widget.vault.id);
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Future<void> _runGc() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _cleaning = true;
      _error = null;
      _statusMessage = null;
    });
    try {
      final cleaner = widget.onGcOverride ?? VaultService.instance.gcVault;
      final res = await cleaner(widget.vault.id);
      if (!mounted) return;
      setState(() {
        _cleaning = false;
        _statusMessage = l10n.vaultCleanupResultNotice(
          res.removedFiles.toInt(),
          _formatVaultBytes(res.freedBytes.toInt()),
        );
      });
      await _loadStats();
    } catch (e) {
      if (mounted) {
        setState(() {
          _cleaning = false;
          _error = _formatVaultError(context, e);
        });
      }
    }
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final stats = _stats;

    return AlertDialog(
      title: Text('${widget.vault.name} • ${l10n.vaultFolderInfo}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statRow(
                l10n.encryptionAlgorithm,
                widget.vault.cipher.toUpperCase(),
              ),
              _statRow(
                l10n.credentialMethod,
                widget.vault.authMode == 'system'
                    ? l10n.credentialSystem
                    : l10n.credentialPassword,
              ),
              const Divider(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (stats != null) ...[
                _statRow(l10n.vaultStatsFiles, '${stats.fileCount}'),
                _statRow(l10n.vaultStatsFolders, '${stats.dirCount}'),
                _statRow(
                  l10n.vaultStatsPlainSize,
                  _formatVaultBytes(stats.totalPlainBytes.toInt()),
                ),
                _statRow(
                  l10n.vaultStatsDiskUsage,
                  _formatVaultBytes(stats.diskBytes.toInt()),
                ),
                _statRow(
                  l10n.vaultStatsOrphaned,
                  l10n.vaultStatsOrphanDetail(
                    stats.orphanCount.toInt(),
                    _formatVaultBytes(stats.orphanBytes.toInt()),
                  ),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (stats != null && stats.orphanCount > BigInt.zero)
          TextButton.icon(
            onPressed: _cleaning ? null : _runGc,
            icon: _cleaning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(l10n.vaultCleanupOrphansAction),
          ),
        FilledButton(
          onPressed: _cleaning ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
