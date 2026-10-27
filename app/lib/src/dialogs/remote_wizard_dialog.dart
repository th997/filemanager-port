import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/remotes.dart';
import '../services/error_text.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';

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
  late final TextEditingController _rootPathController;
  bool _pathStyle = false;
  bool _obscurePassword = true;
  bool _obscureSecretKey = true;

  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _kind = c?.kind ?? 's3';
    _nameController = TextEditingController(text: c?.name ?? '');
    _idController = TextEditingController(text: c?.id ?? '');
    _idManuallyEdited = c != null;
    _nameController.addListener(_onNameChanged);
    _endpointController = TextEditingController(text: c?.endpoint ?? '');
    _endpointController.addListener(_onEndpointChanged);
    _bucketController = TextEditingController(text: c?.bucket ?? '');
    _regionController = TextEditingController(text: c?.region ?? 'us-east-1');
    _keyIdController = TextEditingController(text: c?.accessKeyId ?? '');
    _keySecretController = TextEditingController(text: c?.secretAccessKey ?? '');
    _hostController = TextEditingController(text: c?.host ?? '');
    _portController = TextEditingController(text: c?.port?.toString() ?? '');
    _usernameController = TextEditingController(text: c?.username ?? '');
    _passwordController = TextEditingController(text: c?.password ?? '');
    _rootPathController = TextEditingController(text: c?.rootPath ?? '/');
    _pathStyle = c?.pathStyle ?? false;
  }

  bool _endpointInsecure = false;

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
    _rootPathController.dispose();
    super.dispose();
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
      password: _passwordController.text.isEmpty ? null : _passwordController.text,
      rootPath: _rootPathController.text.trim().isEmpty ? '/' : _rootPathController.text.trim(),
      pathStyle: _pathStyle,
    );
  }

  String? _portError() {
    final t = _portController.text.trim();
    if (t.isEmpty) return null;
    final p = int.tryParse(t);
    if (p == null) return 'Port must be a number.';
    if (p < 1 || p > 65535) return 'Port must be between 1 and 65535.';
    return null;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final portError = _portError();
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
      final ok = await StorageService.instance.testConnection(config);
      if (mounted) {
        setState(() {
          _testing = false;
          _testSuccess = ok;
          _testResult = ok ? 'Connection successful!' : 'Connection returned false';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testSuccess = false;
          _testResult = 'Connection failed: ${friendlyErrorText(e)}';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildConfig();
    final oldId = widget.initialConfig?.id;
    try {
      // Save the new record first: deleting the old one before the save
      // meant a failed save (DB error, validation) destroyed the existing
      // connection for good.
      await StorageService.instance.saveRemote(config);
      if (oldId != null && oldId != config.id) {
        await StorageService.instance.deleteRemote(oldId);
        invalidateRoot(root: 'remote://$oldId');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _testResult = 'Could not save: $e');
        _testSuccess = false;
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialConfig == null ? 'Add Remote Storage' : 'Edit Remote Storage'),
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
                  decoration: const InputDecoration(labelText: 'Protocol / Provider', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 's3', child: Text('Amazon S3 / S3-Compatible (MinIO, R2)')),
                    DropdownMenuItem(value: 'oss', child: Text('Aliyun OSS (阿里云对象存储)')),
                    DropdownMenuItem(value: 'webdav', child: Text('WebDAV (Nextcloud, OwnCloud)')),
                    DropdownMenuItem(value: 'sftp', child: Text('SFTP (SSH File Transfer)')),
                    DropdownMenuItem(value: 'ftp', child: Text('FTP / FTPS')),
                    DropdownMenuItem(value: 'smb', child: Text('SMB / Windows Share (Samba)')),
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
                  decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _idController,
                  decoration: InputDecoration(
                    labelText: 'Identifier / ID (e.g. sftp_mac, my_nas)',
                    hintText: 'Used in remote paths: remote://id/...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.auto_fix_high, size: 20),
                      tooltip: 'Generate clean ID from Name',
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
                    if (v == null || v.trim().isEmpty) return 'Please enter an identifier';
                    if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(v.trim())) {
                      return 'Identifier may only contain letters, numbers, hyphens and underscores';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                if (_kind == 's3' || _kind == 'oss') ...[
                  TextFormField(
                    controller: _bucketController,
                    decoration: const InputDecoration(
                      labelText: 'Bucket Name (Optional, empty for all buckets)',
                      hintText: 'Leave empty to browse all buckets, or comma-separated',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _endpointController,
                    decoration: InputDecoration(
                      labelText: _kind == 's3' ? 'Endpoint (Optional for AWS, required for MinIO/R2)' : 'Endpoint (e.g. https://oss-cn-hangzhou.aliyuncs.com)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_kind == 's3') ...[
                    TextFormField(
                      controller: _regionController,
                      decoration: const InputDecoration(labelText: 'Region (e.g. us-east-1, auto)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('Use Path-Style (for MinIO / local S3)'),
                      value: _pathStyle,
                      onChanged: (v) => setState(() => _pathStyle = v ?? false),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                  TextFormField(
                    controller: _keyIdController,
                    decoration: const InputDecoration(labelText: 'Access Key ID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _keySecretController,
                    decoration: InputDecoration(
                      labelText: 'Secret Access Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSecretKey ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscureSecretKey ? 'Show secret key' : 'Hide secret key',
                        onPressed: () => setState(() => _obscureSecretKey = !_obscureSecretKey),
                      ),
                    ),
                    obscureText: _obscureSecretKey,
                  ),
                ] else if (_kind == 'webdav') ...[
                  TextFormField(
                    controller: _endpointController,
                    decoration: const InputDecoration(labelText: 'WebDAV URL (e.g. https://example.com/dav)', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'URL is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                  ),
                  if (_endpointInsecure) ...[
                    const SizedBox(height: 12),
                    _insecureWarning(
                      'This URL uses http:// — the password and files travel '
                      'unencrypted. Use https:// if the server supports it.',
                    ),
                  ],
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _hostController,
                          decoration: const InputDecoration(labelText: 'Host / IP', border: OutlineInputBorder()),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Host is required' : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _portController,
                          decoration: InputDecoration(
                            labelText: 'Port',
                            hintText: _kind == 'sftp' ? '22' : (_kind == 'smb' ? '445' : '21'),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null; // default per protocol
                            final p = int.tryParse(t);
                            if (p == null) return 'Numbers only';
                            if (p < 1 || p > 65535) return 'Use 1–65535';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rootPathController,
                    decoration: const InputDecoration(labelText: 'Remote Root Path', border: OutlineInputBorder()),
                  ),
                  if (_kind == 'ftp') ...[
                    const SizedBox(height: 12),
                    _insecureWarning(
                      'FTP is not encrypted: the password and files travel in '
                      'plain text. Prefer SFTP when the server offers it.',
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
                            tooltip: 'Copy Error',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _testResult!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Error copied to clipboard')),
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
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.network_check),
          label: const Text('Test Connection'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
