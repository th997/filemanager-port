import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../l10n/app_localizations.dart';
import '../services/preferences_service.dart';
import '../theme/app_ui_tokens.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String localeCode;
  final ValueChanged<String> onLocaleChanged;
  final String accentCode;
  final ValueChanged<String> onAccentChanged;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.localeCode,
    required this.onLocaleChanged,
    required this.accentCode,
    required this.onAccentChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Mirrors of the values owned by HomePage. The page is pushed with copies
  // of those values and never rebuilt when they change, so the dropdowns and
  // subtitles kept showing the old choice after a selection.
  late ThemeMode _themeMode = widget.currentThemeMode;
  late String _accentCode = widget.accentCode;
  late String _localeCode = widget.localeCode;

  ThemeMode get currentThemeMode => _themeMode;

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

  static const Map<String, Color> _accentSeeds = {
    'deepTeal': Color(0xFF00696D),
    'classicBlue': Color(0xFF1976D2),
    'indigo': Color(0xFF3949AB),
    'forest': Color(0xFF2E7D32),
    'sunset': Color(0xFFD84315),
    'grape': Color(0xFF6750A4),
  };

  String _accentLabel(String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'dynamic':
        return l10n.accentDynamic;
      case 'classicBlue':
        return l10n.accentClassicBlue;
      case 'indigo':
        return l10n.accentIndigo;
      case 'forest':
        return l10n.accentForest;
      case 'sunset':
        return l10n.accentSunset;
      case 'grape':
        return l10n.accentGrape;
      default:
        return l10n.accentDeepTeal;
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
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        padding: AppUiTokens.pagePadding,
        children: [
          _buildSectionHeader(context, l10n.appearance),
          Card(
            child: ListTile(
              leading: const AppCircleBadge(
                icon: Icons.brightness_medium,
                color: Colors.blue,
              ),
              title: Text(l10n.theme),
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
                  if (mode == null) return;
                  setState(() => _themeMode = mode);
                  widget.onThemeModeChanged(mode);
                },
              ),
            ),
          ),

          const SizedBox(height: 6),

          Card(
            child: ListTile(
              leading: AppCircleBadge(
                icon: Icons.palette_outlined,
                color: _accentSeeds[_accentCode] ?? Theme.of(context).colorScheme.primary,
              ),
              title: Text(l10n.accentColor),
              subtitle: Text(_accentLabel(_accentCode), style: const TextStyle(fontSize: 10)),
              trailing: DropdownButton<String>(
                value: _accentCode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'dynamic', child: Text(l10n.accentDynamic, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'deepTeal', child: Text(l10n.accentDeepTeal, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'classicBlue', child: Text(l10n.accentClassicBlue, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'indigo', child: Text(l10n.accentIndigo, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'forest', child: Text(l10n.accentForest, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'sunset', child: Text(l10n.accentSunset, style: const TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'grape', child: Text(l10n.accentGrape, style: const TextStyle(fontSize: 12))),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  setState(() => _accentCode = code);
                  widget.onAccentChanged(code);
                },
              ),
            ),
          ),
          const SizedBox(height: 6),

          Card(
            child: ListTile(
              leading: const AppCircleBadge(
                icon: Icons.language,
                color: Colors.indigo,
              ),
              title: Text(l10n.language),
              subtitle: Text(_languageLabel(_localeCode), style: const TextStyle(fontSize: 10)),
              trailing: DropdownButton<String>(
                value: _localeCode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem, style: const TextStyle(fontSize: 12))),
                  const DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem(value: 'zh', child: Text('中文', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (code) {
                  if (code == null) return;
                  setState(() => _localeCode = code);
                  widget.onLocaleChanged(code);
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.browserSection),
          Card(
            child: SwitchListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              minTileHeight: 40,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: const AppCircleBadge(
                icon: Icons.vertical_align_bottom,
                color: Colors.teal,
              ),
              title: Text(l10n.toolbarAtBottom),
              subtitle: Text(l10n.toolbarAtBottomDesc,
                  style: const TextStyle(fontSize: 10)),
              value: PreferencesService.toolbarAtBottom.value,
              onChanged: _setToolbarAtBottom,
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.aboutSection),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.info_outline,
                    color: Colors.blue,
                  ),
                  title: Text(l10n.appTitle),
                  subtitle: Text(
                    '${_versionLabel ?? 'Rust Core'}\n'
                    'Platform: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})',
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.cloud_done,
                    color: Colors.green,
                  ),
                  title: Text(l10n.supportedProtocols),
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
