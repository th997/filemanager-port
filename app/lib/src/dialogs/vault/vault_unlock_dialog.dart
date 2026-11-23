part of '../vault_dialogs.dart';

class OpenVaultDialog extends StatefulWidget {
  final String? initialName;

  const OpenVaultDialog({super.key, this.initialName});

  static Future<UnlockedVaultDto?> show(
    BuildContext context, {
    String? initialName,
  }) {
    return showDialog<UnlockedVaultDto>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OpenVaultDialog(initialName: initialName),
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
  void initState() {
    super.initState();
    final initial = widget.initialName?.trim();
    if (initial != null && initial.isNotEmpty) {
      _nameCtrl.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookupName();
      });
    }
  }

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

