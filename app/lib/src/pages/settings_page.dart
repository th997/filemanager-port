import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/servers.dart';
import '../services/platform_paths.dart';
import '../services/sharing_service.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _serverRunning = false;
  ServerStatusDto? _serverStatus;
  bool _starting = false;

  late String _shareRoot;
  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  final TextEditingController _pwdCtrl = TextEditingController();
  bool _readOnly = true;

  @override
  void initState() {
    super.initState();
    _shareRoot = PlatformPaths.defaultRoot();
    _serverRunning = SharingService.instance.isRunning;
    _serverStatus = SharingService.instance.currentStatus;
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleServer(bool start) async {
    if (start) {
      setState(() => _starting = true);
      try {
        final port = int.tryParse(_portCtrl.text.trim());
        final pwd = _pwdCtrl.text.trim().isEmpty ? null : _pwdCtrl.text.trim();

        final status = await SharingService.instance.startHttp(
          rootDir: _shareRoot,
          port: port,
          password: pwd,
          readOnly: _readOnly,
        );

        if (mounted) {
          setState(() {
            _serverRunning = true;
            _serverStatus = status;
            _starting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _starting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start server: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      SharingService.instance.stopHttp();
      setState(() {
        _serverRunning = false;
        _serverStatus = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Sharing'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_medium),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel(widget.currentThemeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: widget.currentThemeMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (mode) {
                if (mode != null) widget.onThemeModeChanged(mode);
              },
            ),
          ),
          const Divider(),

          // LAN HTTP Sharing Card
          _buildSectionHeader('LAN HTTP Sharing & Web Access'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: _serverRunning ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _serverRunning ? Colors.green : Theme.of(context).dividerColor.withValues(alpha: 0.2),
                width: _serverRunning ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wifi_tethering,
                            size: 28,
                            color: _serverRunning ? Colors.green : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Web Sharing Server', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(
                                _serverRunning ? '🟢 Running on LAN' : '⚪ Stopped',
                                style: TextStyle(fontSize: 12, color: _serverRunning ? Colors.green : Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _starting
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : Switch(
                              value: _serverRunning,
                              onChanged: _toggleServer,
                            ),
                    ],
                  ),

                  if (_serverRunning && _serverStatus != null) ...[
                    const Divider(height: 24),
                    Text(
                      'Access files from any browser on the same Wi-Fi:',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ..._serverStatus!.addresses.map((ip) {
                      final url = 'http://$ip:${_serverStatus!.port}';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SelectableText(
                              url,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy URL',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    const SizedBox(height: 12),
                    Text(
                      'Share files on your local network without cables. Stream media, download or upload files through any web browser.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _pwdCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Password (Optional)', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Read Only (disallow web uploads)'),
                      value: _readOnly,
                      onChanged: (v) => setState(() => _readOnly = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const Divider(),
          _buildSectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('File Manager+ Cross-Platform'),
            subtitle: Text(
              'v1.0.0 • Flutter 3.47 + Rust Core\n'
              'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_done),
            title: Text('Supported Protocols'),
            subtitle: Text('Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP, SMB, ZIP, TAR, 7Z'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Zero C-OpenSSL Dependencies'),
            subtitle: Text('Pure-Rust rustls networking, Apache OpenDAL unified cloud storage'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follow system settings';
      case ThemeMode.light:
        return 'Light theme';
      case ThemeMode.dark:
        return 'Dark theme';
    }
  }
}
