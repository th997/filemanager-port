import 'dart:io';
import 'package:flutter/material.dart';

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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  widget.onThemeModeChanged(mode);
                }
              },
            ),
          ),
          const Divider(),
          _buildSectionHeader('LAN Sharing (M5 Preview)'),
          const ListTile(
            leading: Icon(Icons.wifi_tethering),
            title: Text('HTTP Share Server'),
            subtitle: Text('Share files and media over browser (M5)'),
            trailing: Chip(label: Text('Planned', style: TextStyle(fontSize: 10))),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('FTP Server'),
            subtitle: Text('Access device storage via FTP client (M5)'),
            trailing: Chip(label: Text('Planned', style: TextStyle(fontSize: 10))),
          ),
          const Divider(),
          _buildSectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('File Manager+ Cross-Platform'),
            subtitle: Text(
              'v0.1.0 • Flutter 3.47 + Rust Core\n'
              'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Rust Engine'),
            subtitle: Text('VFS granted-root core, pure-Rust archive & remote protocols'),
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
