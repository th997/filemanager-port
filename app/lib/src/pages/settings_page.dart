import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../services/preferences_service.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String localeCode;
  final ValueChanged<String> onLocaleChanged;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.localeCode,
    required this.onLocaleChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode get currentThemeMode => widget.currentThemeMode;

  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _versionLabel =
          'v${info.version} (build ${info.buildNumber}) • Rust Core');
    }).catchError((_) {});
  }

  void _setToolbarAtBottom(bool value) {
    PreferencesService.instance.setBool(PreferencesService.prefToolbarBottom, value);
    PreferencesService.toolbarAtBottom.value = value;
    setState(() {});
  }

  String _themeModeLabel(ThemeMode mode) {
    final l10n = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.system:
        return l10n.followSystemSettings;
      case ThemeMode.light:
        return l10n.lightTheme;
      case ThemeMode.dark:
        return l10n.darkTheme;
    }
  }

  String _languageLabel(String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'en':
        return 'English';
      case 'zh':
        return '中文';
      default:
        return l10n.languageSystem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _buildSectionHeader(context, l10n.appearance),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              minTileHeight: 42,
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.brightness_medium, size: 16, color: Colors.blue),
              ),
              title: Text(l10n.theme, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text(_themeModeLabel(currentThemeMode), style: const TextStyle(fontSize: 10)),
              trailing: DropdownButton<ThemeMode>(
                value: currentThemeMode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: ThemeMode.system, child: Text(l10n.themeSystem, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: ThemeMode.light, child: Text(l10n.themeLight, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text(l10n.themeDark, style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (mode) {
                  if (mode != null) widget.onThemeModeChanged(mode);
                },
              ),
            ),
          ),

          const SizedBox(height: 8),

          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              minTileHeight: 42,
              minLeadingWidth: 24,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.language, size: 16, color: Colors.indigo),
              ),
              title: Text(l10n.language, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text(_languageLabel(widget.localeCode), style: const TextStyle(fontSize: 10)),
              trailing: DropdownButton<String>(
                value: widget.localeCode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem, style: const TextStyle(fontSize: 12))),
                  const DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem(value: 'zh', child: Text('中文', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (code) {
                  if (code != null) widget.onLocaleChanged(code);
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.browserSection),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: SwitchListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              minTileHeight: 42,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.vertical_align_bottom, size: 16, color: Colors.teal),
              ),
              title: Text(l10n.toolbarAtBottom, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text(l10n.toolbarAtBottomDesc,
                  style: const TextStyle(fontSize: 10)),
              value: PreferencesService.toolbarAtBottom.value,
              onChanged: _setToolbarAtBottom,
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.aboutSection),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                  minTileHeight: 42,
                  minLeadingWidth: 24,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  ),
                  title: const Text('File Manager+ Cross-Platform', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${_versionLabel ?? 'Rust Core'}\n'
                    'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                  minTileHeight: 40,
                  minLeadingWidth: 24,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_done, size: 16, color: Colors.green),
                  ),
                  title: Text(l10n.supportedProtocols, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP, SMB, ZIP, TAR, 7Z',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
}
