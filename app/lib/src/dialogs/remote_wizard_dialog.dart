import 'dart:math';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/remotes.dart';
import '../services/error_text.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import 'package:filemanager/l10n/app_localizations.dart';

class RemoteWizardDialog extends StatefulWidget {
  final RemoteConfigDto? initialConfig;

  const RemoteWizardDialog({super.key, this.initialConfig});

  @override
  State<RemoteWizardDialog> createState() => _RemoteWizardDialogState();
}

class _RemoteWizardDialogState extends State<RemoteWizardDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _kind;
  late final TextEditingController _nameController;
  late final TextEditingController _idController;
  bool _idManuallyEdited = false;
  late final TextEditingController _endpointController;
  late final TextEditingController _bucketController;
  late final TextEditingController _regionController;
  late final TextEditingController _keyIdController;
  late final TextEditingController _keySecretController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _rootPathController;
  String _sftpAuthType = 'password';
  bool _pathStyle = false;
  bool _obscurePassword = true;
  bool _obscureSecretKey = true;
  bool _obscurePassphrase = true;

  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _kind = c?.kind ?? 's3';
    final hasKey = c?.privateKey != null && c!.privateKey!.trim().isNotEmpty;
    _sftpAuthType = hasKey ? 'key' : 'password';
    _nameController = TextEditingController(text: c?.name ?? '');
    _idController = TextEditingController(text: c?.id ?? '');
    _idManuallyEdited = c != null;
    _nameController.addListener(_onNameChanged);
    _endpointController = TextEditingController(text: c?.endpoint ?? '');
    _endpointInsecure =
        _endpointController.text.trim().toLowerCase().startsWith('http://');
    _endpointController.addListener(_onEndpointChanged);
    _bucketController = TextEditingController(text: c?.bucket ?? '');
    _regionController = TextEditingController(text: c?.region ?? 'us-east-1');
    _keyIdController = TextEditingController(text: c?.accessKeyId ?? '');
    _keySecretController = TextEditingController(text: c?.secretAccessKey ?? '');
    _hostController = TextEditingController(text: c?.host ?? '');
    _portController = TextEditingController(text: c?.port?.toString() ?? '');
    _usernameController = TextEditingController(text: c?.username ?? '');
    _passwordController = TextEditingController(text: c?.password ?? '');
    _privateKeyController = TextEditingController(text: c?.privateKey ?? '');
    _passphraseController = TextEditingController(text: c?.passphrase ?? '');
    _rootPathController = TextEditingController(text: c?.rootPath ?? '/');
    _pathStyle = c?.pathStyle ?? false;
  }

  bool _endpointInsecure = false;
  bool _saving = false;

  void _onEndpointChanged() {
    final insecure =
        _endpointController.text.trim().toLowerCase().startsWith('http://');
    if (insecure != _endpointInsecure) {
      _endpointInsecure = insecure;
      if (mounted) setState(() {});
    }
  }

  Widget _insecureWarning(String message) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).colorScheme.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, size: 16, color: Theme.of(context).colorScheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _onNameChanged() {
    if (!_idManuallyEdited && widget.initialConfig == null) {
      final slug = _generateSlug(_nameController.text, _kind);
      _idController.text = slug;
    }
  }

  String _generateSlug(String name, String kind) {
    final cleaned = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned.isNotEmpty) {
      return cleaned.startsWith(kind) ? cleaned : '${kind}_$cleaned';
    }
    return '${kind}_${Random().nextInt(900) + 100}';
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _endpointController.removeListener(_onEndpointChanged);
    _idController.dispose();
    _endpointController.dispose();
    _bucketController.dispose();
    _regionController.dispose();
    _keyIdController.dispose();
    _keySecretController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _rootPathController.dispose();
    super.dispose();
  }

  Future<void> _pickPrivateKeyFile() async {
    try {
      final XFile? file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'SSH Keys',
            extensions: ['pem', 'key', 'pub', 'id_rsa', 'id_ed25519', 'id_ecdsa'],
          ),
          XTypeGroup(label: 'All files'),
        ],
      );
      if (file != null) {
        final content = await file.readAsString();
        if (!mounted) return;
        setState(() {
          _privateKeyController.text = content;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).failedToReadKeyFile('$e'))),
        );
      }
    }
  }

  RemoteConfigDto _buildConfig() {
    var id = _idController.text.trim();
    if (id.isEmpty) {
      id = widget.initialConfig?.id ?? _generateSlug(_nameController.text, _kind);
    }
    int? portInt = int.tryParse(_portController.text.trim());
    if (portInt == null) {
      if (_kind == 'sftp') {
        portInt = 22;
      } else if (_kind == 'ftp') {
        portInt = 21;
      } else if (_kind == 'smb') {
        portInt = 445;
      }
    }

    String? password;
    String? privateKey;
    String? passphrase;
    if (_kind == 'sftp') {
      if (_sftpAuthType == 'key') {
        privateKey = _privateKeyController.text.trim().isEmpty ? null : _privateKeyController.text.trim();
        passphrase = _passphraseController.text.isEmpty ? null : _passphraseController.text;
        password = passphrase;
      } else {
        password = _passwordController.text.isEmpty ? null : _passwordController.text;
      }
    } else {
      password = _passwordController.text.isEmpty ? null : _passwordController.text;
    }

    return RemoteConfigDto(
      id: id,
      name: _nameController.text.trim().isEmpty ? '$_kind Remote' : _nameController.text.trim(),
      kind: _kind,
      endpoint: _endpointController.text.trim().isEmpty ? null : _endpointController.text.trim(),
      bucket: _bucketController.text.trim().isEmpty ? null : _bucketController.text.trim(),
      region: _regionController.text.trim().isEmpty ? null : _regionController.text.trim(),
      accessKeyId: _keyIdController.text.trim().isEmpty ? null : _keyIdController.text.trim(),
      secretAccessKey: _keySecretController.text.trim().isEmpty ? null : _keySecretController.text.trim(),
      host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
      port: portInt,
      username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
      rootPath: _rootPathController.text.trim().isEmpty ? '/' : _rootPathController.text.trim(),
      pathStyle: _pathStyle,
    );
  }

  String? _validatePort(String? value) {
    final l10n = AppLocalizations.of(context);
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final p = int.tryParse(v);
    if (p == null) return l10n.portMustBeNumber;
    if (p < 1 || p > 65535) return l10n.portRangeError;
    return null;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final portError = _validatePort(_portController.text);
    if (portError != null) {
      setState(() {
        _testSuccess = false;
        _testResult = portError;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final config = _buildConfig();
      // A silent hang on a firewalled host blocks the dialog for the OS TCP
      // timeout (~2 min); match the remotes page's 8s probe.
      final ok = await StorageService.instance
          .testConnection(config)
          .timeout(const Duration(seconds: 8));
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _testing = false;
          _testSuccess = ok;
          _testResult = ok ? l10n.connectionSuccessful : l10n.connectionReturnedFalse;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _testing = false;
          _testSuccess = false;
          _testResult = l10n.connectionFailedWithError(friendlyErrorText(e, l10n));
        });
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final config = _buildConfig();
    final oldId = widget.initialConfig?.id;
    String? oldDeleteWarning;
    try {
      // Upsert on an existing id would silently replace another connection.
      final existing = await StorageService.instance.getRemotes();
      final clash = existing.where((r) => r.id == config.id && r.id != oldId);
      if (clash.isNotEmpty) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          setState(() {
            _saving = false;
            _testSuccess = false;
            _testResult = l10n.idAlreadyUsed(config.id, clash.first.name);
          });
        }
        return;
      }
      // Save the new record first: deleting the old one before the save
      // meant a failed save (DB error, validation) destroyed the existing
      // connection for good.
      await StorageService.instance.saveRemote(config);
      if (oldId != null && oldId != config.id) {
        try {
          await StorageService.instance.deleteRemote(oldId);
          invalidateRoot(root: 'remote://$oldId');
        } catch (e) {
          if (mounted) {
            oldDeleteWarning =
                AppLocalizations.of(context).savedOldEntryRemoveFailed(oldId, '$e');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _testResult = AppLocalizations.of(context).couldNotSave('$e');
          _testSuccess = false;
        });
      }
      return;
    }
    if (mounted) {
      if (oldDeleteWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(oldDeleteWarning)),
        );
      }
      Navigator.of(context).pop(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initialConfig == null ? l10n.addRemoteStorage : l10n.editRemoteStorage),
      actionsOverflowButtonSpacing: 8,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SizedBox(
          width: double.maxFinite,
          child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.protocolProvider, border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: 's3', child: Text(l10n.providerS3)),
                    DropdownMenuItem(value: 'oss', child: Text(l10n.providerOss)),
                    DropdownMenuItem(value: 'webdav', child: Text(l10n.providerWebdav)),
                    DropdownMenuItem(value: 'sftp', child: Text(l10n.providerSftp)),
                    DropdownMenuItem(value: 'ftp', child: Text(l10n.providerFtp)),
                    DropdownMenuItem(value: 'smb', child: Text(l10n.providerSmb)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _kind = val;
                        if (_kind == 'oss' && _endpointController.text.isEmpty) {
                          _endpointController.text = 'https://oss-cn-hangzhou.aliyuncs.com';
                        }
                        if (_kind == 'sftp' && (_portController.text.isEmpty || _portController.text == '21' || _portController.text == '445')) {
                          _portController.text = '22';
                        } else if (_kind == 'ftp' && (_portController.text.isEmpty || _portController.text == '22' || _portController.text == '445')) {
                          _portController.text = '21';
                        } else if (_kind == 'smb' && (_portController.text.isEmpty || _portController.text == '22' || _portController.text == '21')) {
                          _portController.text = '445';
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: l10n.displayName, border: const OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? l10n.pleaseEnterName : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: l10n.identifierLabel,
                    hintText: l10n.identifierHint,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.auto_fix_high, size: 20),
                      tooltip: l10n.generateIdTooltip,
                      onPressed: () {
                        setState(() {
                          _idManuallyEdited = true;
                          _idController.text = _generateSlug(_nameController.text, _kind);
                        });
                      },
                    ),
                  ),
                  onChanged: (_) => _idManuallyEdited = true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return l10n.pleaseEnterId;
                    if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(v.trim())) {
                      return l10n.idCharsetError;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                if (_kind == 's3' || _kind == 'oss') ...[
                  TextFormField(
                    controller: _bucketController,
                    decoration: InputDecoration(
                      labelText: l10n.bucketNameOptional,
                      hintText: l10n.bucketNameOptionalHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _endpointController,
                    decoration: InputDecoration(
                      labelText: _kind == 's3' ? l10n.endpointHintS3 : l10n.endpointHintGeneric,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_kind == 's3') ...[
                    TextFormField(
                      controller: _regionController,
                      decoration: InputDecoration(labelText: l10n.regionLabel, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: Text(l10n.usePathStyle),
                      value: _pathStyle,
                      onChanged: (v) => setState(() => _pathStyle = v ?? false),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                  TextFormField(
                    controller: _keyIdController,
                    decoration: InputDecoration(labelText: l10n.accessKeyId, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _keySecretController,
                    decoration: InputDecoration(
                      labelText: l10n.secretAccessKey,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSecretKey ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscureSecretKey ? l10n.showSecretKey : l10n.hideSecretKey,
                        onPressed: () => setState(() => _obscureSecretKey = !_obscureSecretKey),
                      ),
                    ),
                    obscureText: _obscureSecretKey,
                  ),
                ] else if (_kind == 'webdav') ...[
                  TextFormField(
                    controller: _endpointController,
                    decoration: InputDecoration(labelText: l10n.webdavUrlLabel, border: const OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? l10n.urlRequired : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(labelText: l10n.username, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: l10n.password,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscurePassword ? l10n.showPassword : l10n.hidePassword,
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                  ),
                  if (_endpointInsecure) ...[
                    const SizedBox(height: 12),
                    _insecureWarning(l10n.webdavCleartextWarning),
                  ],
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _hostController,
                          decoration: InputDecoration(labelText: l10n.hostIp, border: const OutlineInputBorder()),
                          validator: (v) => v == null || v.trim().isEmpty ? l10n.hostRequired : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: l10n.port,
                            hintText: _kind == 'sftp' ? '22' : (_kind == 'smb' ? '445' : '21'),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null; // default per protocol
                            final p = int.tryParse(t);
                            if (p == null) return l10n.numbersOnly;
                            if (p < 1 || p > 65535) return l10n.portRangeShort;
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(labelText: l10n.username, border: const OutlineInputBorder()),
                  ),
                  if (_kind == 'sftp') ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'password',
                          icon: const Icon(Icons.password, size: 16),
                          label: Text(l10n.authPassword),
                        ),
                        ButtonSegment(
                          value: 'key',
                          icon: const Icon(Icons.key, size: 16),
                          label: Text(l10n.authPrivateKey),
                        ),
                      ],
                      selected: {_sftpAuthType},
                      onSelectionChanged: (val) {
                        setState(() => _sftpAuthType = val.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_sftpAuthType == 'key') ...[
                      Row(
                        children: [
                          Text(
                            l10n.privateKeyLabel,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _pickPrivateKeyFile,
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: Text(l10n.selectKeyFile),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: _privateKeyController,
                        decoration: InputDecoration(
                          hintText: l10n.privateKeyHint,
                          border: const OutlineInputBorder(),
                        ),
                        minLines: 3,
                        maxLines: 6,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        validator: (v) {
                          if (_kind == 'sftp' && _sftpAuthType == 'key') {
                            if (v == null || v.trim().isEmpty) {
                              return l10n.privateKeyRequired;
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passphraseController,
                        decoration: InputDecoration(
                          labelText: l10n.passphraseLabel,
                          hintText: l10n.passphraseHint,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassphrase ? Icons.visibility_off : Icons.visibility),
                            tooltip: _obscurePassphrase ? l10n.showPassphrase : l10n.hidePassphrase,
                            onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                          ),
                        ),
                        obscureText: _obscurePassphrase,
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: l10n.password,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            tooltip: _obscurePassword ? l10n.showPassword : l10n.hidePassword,
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        obscureText: _obscurePassword,
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          tooltip: _obscurePassword ? l10n.showPassword : l10n.hidePassword,
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      obscureText: _obscurePassword,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rootPathController,
                    decoration: InputDecoration(labelText: l10n.remoteRootPath, border: const OutlineInputBorder()),
                  ),
                  if (_kind == 'ftp') ...[
                    const SizedBox(height: 12),
                    _insecureWarning(
                          l10n.ftpCleartextWarning,
                    ),
                  ],
                ],

                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _testSuccess
                          ? Theme.of(context).colorScheme.success.withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _testSuccess
                            ? Theme.of(context).colorScheme.success.withValues(alpha: 0.4)
                            : Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _testSuccess ? Icons.check_circle_outline : Icons.error_outline,
                          size: 16,
                          color: _testSuccess ? Theme.of(context).colorScheme.success : Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _testResult!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _testSuccess ? Theme.of(context).colorScheme.success : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (!_testSuccess)
                          IconButton(
                            icon: const Icon(Icons.copy, size: 14),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            tooltip: l10n.copyError,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _testResult!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.errorCopied)),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        OutlinedButton.icon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check),
          label: Text(l10n.testConnection),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
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
