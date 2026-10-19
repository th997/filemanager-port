import 'dart:math';
import 'package:flutter/material.dart';
import '../rust/api/remotes.dart';
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

  bool _testing = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    final c = widget.initialConfig;
    _kind = c?.kind ?? 's3';
    _nameController = TextEditingController(text: c?.name ?? '');
    _endpointController = TextEditingController(text: c?.endpoint ?? '');
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

  @override
  void dispose() {
    _nameController.dispose();
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
    final id = widget.initialConfig?.id ??
        'remote_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final portInt = int.tryParse(_portController.text.trim());

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

  Future<void> _testConnection() async {
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
          _testResult = 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildConfig();
    await StorageService.instance.saveRemote(config);
    if (mounted) {
      Navigator.of(context).pop(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialConfig == null ? 'Add Remote Storage' : 'Edit Remote Storage'),
      content: SizedBox(
        width: 500,
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
                    decoration: const InputDecoration(labelText: 'Secret Access Key', border: OutlineInputBorder()),
                    obscureText: true,
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
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                  ),
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
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _rootPathController,
                    decoration: const InputDecoration(labelText: 'Remote Root Path', border: OutlineInputBorder()),
                  ),
                ],

                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _testSuccess ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _testSuccess ? Colors.green : Colors.red),
                    ),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testSuccess ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ],
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
