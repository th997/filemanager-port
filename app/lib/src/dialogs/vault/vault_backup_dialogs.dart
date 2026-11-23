part of '../vault_dialogs.dart';

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

