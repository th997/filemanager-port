part of '../vault_dialogs.dart';

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

