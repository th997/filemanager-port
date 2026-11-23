part of '../vault_dialogs.dart';

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
  bool _alwaysVisible = false;
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
        alwaysVisible: _alwaysVisible,
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
              const SizedBox(height: 6),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _alwaysVisible,
                title: Text(
                  l10n.vaultAlwaysVisibleTitle,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  l10n.vaultAlwaysVisibleDesc,
                  style: const TextStyle(fontSize: 11),
                ),
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _alwaysVisible = v),
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

