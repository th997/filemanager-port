import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/history_retention_dialog.dart';
import '../rust/api/file_manager.dart' show clearArchiveCache, archiveCacheSize;
import '../rust/api/metadata.dart' show isSecretEncryptionActive;
import '../services/platform_capabilities.dart';
import '../services/preferences_service.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';

class SettingsPage extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String localeCode;
  final ValueChanged<String> onLocaleChanged;
  final String accentCode;
  final ValueChanged<String> onAccentChanged;
  final VoidCallback? onConfigImported;

  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.localeCode,
    required this.onLocaleChanged,
    required this.accentCode,
    required this.onAccentChanged,
    this.onConfigImported,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Mirrors of the values owned by HomePage. The page is pushed with copies
  // of those values and never rebuilt when they change, so the dropdowns and
  // subtitles kept showing the old choice after a selection.
  late ThemeMode _themeMode = widget.currentThemeMode;
  late String _accentCode = _normalizeAccent(widget.accentCode);
  late String _localeCode = _normalizeLocale(widget.localeCode);
  late int _bufferDurationSec = _normalizeBufferDuration(
    PreferencesService.instance.bufferDurationSec,
  );
  late int _bufferSizeMb = _normalizeBufferSize(
    PreferencesService.instance.bufferSizeMb,
  );
  late int _vaultAutoLockSec = _normalizeAutoLockSec(
    PreferencesService.instance.vaultAutoLockTimeoutSec,
  );
  late int _historyRetentionDays =
      PreferencesService.instance.historyRetentionDays;

  static int _normalizeAutoLockSec(int raw) {
    const allowed = {0, 60, 300, 600, -1};
    return allowed.contains(raw) ? raw : 600;
  }

  static String _normalizeLocale(String raw) {
    const allowed = {'system', 'en', 'zh', 'ja'};
    return allowed.contains(raw) ? raw : 'system';
  }

  static String _normalizeAccent(String raw) {
    const allowed = {'dynamic', 'deepTeal', 'classicBlue', 'indigo', 'forest', 'sunset', 'grape'};
    if (!allowed.contains(raw)) return 'deepTeal';
    if (!PlatformCapabilities.supportsDynamicColor && raw == 'dynamic') {
      return 'deepTeal';
    }
    return raw;
  }

  static int _normalizeBufferDuration(int raw) {
    const allowed = {5, 15, 30, 60, 120};
    return allowed.contains(raw) ? raw : 30;
  }

  static int _normalizeBufferSize(int raw) {
    const allowed = {4, 8, 16, 32, 64, 128};
    return allowed.contains(raw) ? raw : 16;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentThemeMode != widget.currentThemeMode) {
      _themeMode = widget.currentThemeMode;
    }
    if (oldWidget.accentCode != widget.accentCode) {
      _accentCode = _normalizeAccent(widget.accentCode);
    }
    if (oldWidget.localeCode != widget.localeCode) {
      _localeCode = _normalizeLocale(widget.localeCode);
    }
  }

  String _autoLockLabel(int sec) {
    final l10n = AppLocalizations.of(context);
    if (sec < 0) return l10n.vaultAutoLockNever;
    if (sec == 0) return l10n.vaultAutoLockImmediate;
    return l10n.vaultAutoLockMinutes((sec / 60).round());
  }

  ThemeMode get currentThemeMode => _themeMode;

  String? _versionLabel;
  String? _buildTimeLabel;
  String? _platformLabel;
  int _cacheSizeBytes = 0;
  bool _clearingCache = false;
  bool _secretEncryptionActive = true;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() => _versionLabel =
          'v${info.version} (build ${info.buildNumber}) • Rust Core');
    }).catchError((_) {});
    _buildTimeLabel = _getBuildTime();
    _platformLabel = _getPlatformLabel();
    _updateCacheSize();
    _checkSecretEncryption();
    PreferencesService.historyRetentionDaysNotifier
        .addListener(_onHistoryRetentionChanged);
  }

  void _checkSecretEncryption() {
    try {
      final active = isSecretEncryptionActive(
        dbPath: StorageService.instance.dbPath,
      );
      if (mounted && active != _secretEncryptionActive) {
        setState(() => _secretEncryptionActive = active);
      }
    } catch (_) {}
  }

  void _onHistoryRetentionChanged() {
    if (!mounted) return;
    setState(() {
      _historyRetentionDays =
          PreferencesService.historyRetentionDaysNotifier.value;
    });
  }

  @override
  void dispose() {
    PreferencesService.historyRetentionDaysNotifier
        .removeListener(_onHistoryRetentionChanged);
    super.dispose();
  }

  Future<void> _configureHistoryRetention() async {
    final picked = await showHistoryRetentionDialog(
      context,
      currentDays: _historyRetentionDays,
    );
    if (picked == null || !mounted) return;
    await StorageService.instance.applyHistoryRetention(picked);
    if (!mounted) return;
    setState(() {
      _historyRetentionDays = PreferencesService.instance.historyRetentionDays;
    });
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          picked == 0
              ? l10n.historyRetentionUpdatedOff
              : l10n.historyRetentionUpdatedDays(picked),
        ),
      ),
    );
  }

  String? _getBuildTime() {
    const envBuildTime = String.fromEnvironment('BUILD_TIME');
    if (envBuildTime.isNotEmpty) return envBuildTime;
    try {
      final exe = File(Platform.resolvedExecutable);
      if (exe.existsSync()) {
        final mtime = exe.lastModifiedSync().toLocal();
        final y = mtime.year.toString();
        final m = mtime.month.toString().padLeft(2, '0');
        final d = mtime.day.toString().padLeft(2, '0');
        final h = mtime.hour.toString().padLeft(2, '0');
        final min = mtime.minute.toString().padLeft(2, '0');
        final s = mtime.second.toString().padLeft(2, '0');
        return '$y-$m-$d $h:$min:$s';
      }
    } catch (_) {}
    return null;
  }

  String _getPlatformLabel() {
    if (Platform.isLinux) {
      try {
        final osRelease = File('/etc/os-release');
        if (osRelease.existsSync()) {
          final lines = osRelease.readAsLinesSync();
          for (final line in lines) {
            if (line.startsWith('PRETTY_NAME=')) {
              final pretty = line.substring('PRETTY_NAME='.length).replaceAll('"', '').trim();
              if (pretty.isNotEmpty) {
                return '$pretty (${Platform.version.contains('x64') || Platform.resolvedExecutable.contains('x64') ? 'x86_64' : 'Linux'})';
              }
            }
          }
        }
      } catch (_) {}
      final firstPart = Platform.operatingSystemVersion.split(' ').first;
      return 'Linux (${firstPart.isNotEmpty ? firstPart : 'x86_64'})';
    }
    return '${Platform.operatingSystem} (${Platform.operatingSystemVersion})';
  }

  int _archiveCacheBytes = 0;
  int _inboxCacheBytes = 0;

  Future<void> _updateCacheSize() async {
    int tempTotal = 0;
    int inboxTotal = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final file in tempDir.list(recursive: true, followLinks: false)) {
          if (file is File) {
            try {
              final pth = file.path.replaceAll('\\', '/');
              // Rust's archiveCacheSize() counts temp_dir/fm_archive_cache;
              // skip it here so desktop/iOS platforms never double-count it.
              if (pth.contains('/fm_archive_cache/')) continue;
              final len = await file.length();
              tempTotal += len;
              if (pth.contains('/inbox/') || pth.contains('/Inbox/')) {
                inboxTotal += len;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    int archiveTotal = 0;
    try {
      archiveTotal = archiveCacheSize().toInt();
    } catch (_) {}

    final total = tempTotal + archiveTotal;
    if (mounted) {
      setState(() {
        _cacheSizeBytes = total;
        _archiveCacheBytes = archiveTotal;
        _inboxCacheBytes = inboxTotal;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _clearCache() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).clearTempCacheQuestion),
        content: Text(
          AppLocalizations.of(context).clearTempCacheDesc(_formatBytes(_cacheSizeBytes)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).clear),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    setState(() => _clearingCache = true);

    try {
      try {
        clearArchiveCache();
      } catch (_) {}

      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final f in tempDir.listSync()) {
          try {
            if (f is File) await f.delete();
            if (f is Directory) await f.delete(recursive: true);
          } catch (_) {}
        }
      }
      await _updateCacheSize();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).tempCacheCleared)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotClearCache('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
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
      case 'ja':
        return '日本語';
      default:
        return l10n.languageSystem;
    }
  }

  Future<void> _exportAppConfig() async {
    final passwordController = TextEditingController();
    var includeRemotes = true;
    var obscurePassword = true;
    final outerL10n = AppLocalizations.of(context);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(ctx);
          final hasPassword = passwordController.text.isNotEmpty;
          return AlertDialog(
            title: Text(l10n.exportMigrationTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.exportMigrationPasswordHint,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.exportMigrationPasswordLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: hasPassword && includeRemotes,
                    onChanged: hasPassword
                        ? (v) => setDialogState(() => includeRemotes = v ?? true)
                        : null,
                    title: Text(
                      l10n.exportIncludeCredentials,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: hasPassword
                        ? null
                        : Text(
                            l10n.exportMigrationPasswordHint,
                            style: const TextStyle(fontSize: 11),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('clipboard'),
                child: Text(
                  hasPassword ? l10n.copyEncryptedAction : l10n.copyJsonAction,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('file'),
                child: Text(
                  hasPassword
                      ? l10n.saveBackupFileAction
                      : l10n.saveJsonFileAction,
                ),
              ),
            ],
          );
        },
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    if (action == null || !mounted) return;
    try {
      final isEncrypted = password.isNotEmpty;
      final payload = isEncrypted
          ? await StorageService.instance.exportEncryptedMigrationBundle(
              password,
              includeRemotes: includeRemotes,
            )
          : await StorageService.instance.exportAppConfigBundleJson();
      if (action == 'file') {
        final loc = await getSaveLocation(
          suggestedName: isEncrypted
              ? 'filemanager-migration.fmbak'
              : 'filemanager-config.json',
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'FileManager Migration Backup',
              extensions: ['fmbak', 'json'],
            ),
          ],
        );
        if (loc == null) return;
        await File(loc.path).writeAsString(payload);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outerL10n.exportSavedNotice(loc.path))),
        );
      } else {
        await Clipboard.setData(ClipboardData(text: payload));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outerL10n.exportCopiedNotice)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  bool _looksLikeEncryptedMigrationEnvelope(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> &&
          decoded.containsKey('ciphertext') &&
          decoded.containsKey('salt') &&
          decoded.containsKey('nonce');
    } catch (_) {
      return false;
    }
  }

  void _syncPreferencesAfterImport() {
    final prefs = PreferencesService.instance;
    prefs.flush();
    final savedTheme = prefs.getString('theme_mode');
    final nextTheme = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.system,
    );
    final nextLocale = _normalizeLocale(prefs.getString('app.language') ?? 'system');
    final nextAccent = _normalizeAccent(prefs.getString('app.accent') ?? 'deepTeal');
    prefs.syncToolbarAtBottom();
    PreferencesService.historyRetentionDaysNotifier.value = prefs.historyRetentionDays;
    PreferencesService.vaultVideoThumbnailsNotifier.value =
        prefs.getBool(PreferencesService.prefVaultVideoThumbnails) ?? false;

    setState(() {
      _themeMode = nextTheme;
      _localeCode = nextLocale;
      _accentCode = nextAccent;
      _bufferDurationSec = _normalizeBufferDuration(prefs.bufferDurationSec);
      _bufferSizeMb = _normalizeBufferSize(prefs.bufferSizeMb);
      _vaultAutoLockSec = _normalizeAutoLockSec(prefs.vaultAutoLockTimeoutSec);
      _historyRetentionDays = prefs.historyRetentionDays;
    });
    widget.onThemeModeChanged(nextTheme);
    widget.onLocaleChanged(nextLocale);
    widget.onAccentChanged(nextAccent);
    widget.onConfigImported?.call();
  }

  Future<void> _importAppConfig() async {
    final contentController = TextEditingController();
    final passwordController = TextEditingController();
    var obscurePassword = true;
    String? dialogError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(ctx);
          final rawText = contentController.text.trim();
          final isEncrypted = _looksLikeEncryptedMigrationEnvelope(rawText);
          final canSubmit =
              rawText.isNotEmpty && (!isEncrypted || passwordController.text.isNotEmpty);
          return AlertDialog(
            title: Text(l10n.importMigrationTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final file = await openFile(
                          acceptedTypeGroups: const [
                            XTypeGroup(
                              label: 'FileManager Migration Backup',
                              extensions: ['fmbak', 'json'],
                            ),
                          ],
                        );
                        if (file == null) return;
                        final text = await file.readAsString();
                        contentController.text = text;
                        dialogError = null;
                        setDialogState(() {});
                      } catch (e) {
                        dialogError = '$e';
                        setDialogState(() {});
                      }
                    },
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l10n.chooseBackupFileAction),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contentController,
                    maxLines: 6,
                    onChanged: (_) {
                      dialogError = null;
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: l10n.importPasteHint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onChanged: (_) {
                      dialogError = null;
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: l10n.importPasswordLabel,
                      hintText: l10n.importPasswordHint,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  if (isEncrypted && passwordController.text.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.importPasswordRequiredError,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(ctx).colorScheme.warning,
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: canSubmit ? () => Navigator.of(ctx).pop(true) : null,
                child: Text(l10n.ok),
              ),
            ],
          );
        },
      ),
    );
    final raw = contentController.text.trim();
    final password = passwordController.text;
    contentController.dispose();
    passwordController.dispose();
    if (confirmed != true || raw.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      if (_looksLikeEncryptedMigrationEnvelope(raw) || password.isNotEmpty) {
        final res = await StorageService.instance.importEncryptedMigrationBundle(
          raw,
          password,
        );
        if (!mounted) return;
        _syncPreferencesAfterImport();
        final failed = StorageService.instance.lastImportFailures;
        final failNote = failed.isEmpty
            ? ''
            : l10n.remoteImportFailedSummary(failed.length, failed.join(', '));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l10n.importSummaryNotice(res.remotes, res.bookmarks, res.preferences)}$failNote',
            ),
            backgroundColor: failed.isNotEmpty ? Theme.of(context).colorScheme.error : null,
          ),
        );
      } else {
        final res = await StorageService.instance.importAppConfigBundleJson(raw);
        if (!mounted) return;
        _syncPreferencesAfterImport();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.importSummaryNotice(0, res.bookmarks, res.preferences)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
            child: Column(
              children: [
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.brightness_medium,
                    color: Colors.blue,
                  ),
                  title: Text(l10n.theme),
                  subtitle: Text(_themeModeLabel(currentThemeMode), style: const TextStyle(fontSize: 11)),
                  trailing: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: const Icon(Icons.brightness_auto, size: 16),
                        tooltip: l10n.themeSystem,
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: const Icon(Icons.light_mode, size: 16),
                        tooltip: l10n.themeLight,
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: const Icon(Icons.dark_mode, size: 16),
                        tooltip: l10n.themeDark,
                      ),
                    ],
                    selected: {currentThemeMode},
                    onSelectionChanged: (set) {
                      final mode = set.first;
                      setState(() => _themeMode = mode);
                      widget.onThemeModeChanged(mode);
                    },
                  ),
                ),
                const Divider(height: 1),
                Builder(
                  builder: (context) {
                    final effectiveAccent =
                        !PlatformCapabilities.supportsDynamicColor &&
                                _accentCode == 'dynamic'
                            ? 'deepTeal'
                            : _accentCode;
                    return ListTile(
                      leading: AppCircleBadge(
                        icon: Icons.palette_outlined,
                        color: _accentSeeds[effectiveAccent] ??
                            Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(l10n.accentColor),
                      subtitle: Text(
                        _accentLabel(effectiveAccent),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: DropdownButton<String>(
                        value: effectiveAccent,
                        underline: const SizedBox.shrink(),
                        items: [
                          if (PlatformCapabilities.supportsDynamicColor)
                            DropdownMenuItem(
                              value: 'dynamic',
                              child: Text(l10n.accentDynamic,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          DropdownMenuItem(
                            value: 'deepTeal',
                            child: Text(l10n.accentDeepTeal,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'classicBlue',
                            child: Text(l10n.accentClassicBlue,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'indigo',
                            child: Text(l10n.accentIndigo,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'forest',
                            child: Text(l10n.accentForest,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'sunset',
                            child: Text(l10n.accentSunset,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: 'grape',
                            child: Text(l10n.accentGrape,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                        onChanged: (code) {
                          if (code == null) return;
                          setState(() => _accentCode = code);
                          widget.onAccentChanged(code);
                        },
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.language,
                    color: Colors.indigo,
                  ),
                  title: Text(l10n.language),
                  subtitle: Text(_languageLabel(_localeCode), style: const TextStyle(fontSize: 11)),
                  trailing: DropdownButton<String>(
                    value: _localeCode,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(value: 'system', child: Text(l10n.languageSystem, style: const TextStyle(fontSize: 12))),
                      const DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(fontSize: 12))),
                      const DropdownMenuItem(value: 'zh', child: Text('中文', style: TextStyle(fontSize: 12))),
                      const DropdownMenuItem(value: 'ja', child: Text('日本語', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      setState(() => _localeCode = code);
                      widget.onLocaleChanged(code);
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.browserSection),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  minTileHeight: 40,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const AppCircleBadge(
                    icon: Icons.open_in_browser,
                    color: Colors.blue,
                  ),
                  title: Text(l10n.uploadWithSystemPicker),
                  subtitle: Text(
                    l10n.uploadWithSystemPickerDesc,
                    style: const TextStyle(fontSize: 10),
                  ),
                  value: PreferencesService.instance.useSystemPicker,
                  onChanged: (val) {
                    setState(() {
                      PreferencesService.instance.useSystemPicker = val;
                    });
                  },
                ),
                if (PlatformCapabilities.supportsBottomToolbar) ...[
                  const Divider(height: 1),
                  SwitchListTile(
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
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.mediaPlayback),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.timer_outlined,
                    color: Colors.teal,
                  ),
                  title: Text(l10n.bufferDuration),
                  subtitle: Text('$_bufferDurationSec s',
                      style: const TextStyle(fontSize: 11)),
                  trailing: DropdownButton<int>(
                    value: _bufferDurationSec,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: 5,
                          child: Text('5s',
                              style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 15,
                          child: Text('15s',
                              style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 30,
                          child:
                              Text('30s', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 60,
                          child:
                              Text('60s', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 120,
                          child:
                              Text('120s', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _bufferDurationSec = val);
                        PreferencesService.instance.bufferDurationSec = val;
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.memory,
                    color: Colors.purple,
                  ),
                  title: Text(l10n.bufferSize),
                  subtitle: Text('$_bufferSizeMb MB',
                      style: const TextStyle(fontSize: 11)),
                  trailing: DropdownButton<int>(
                    value: _bufferSizeMb,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: 4,
                          child: Text('4 MB',
                              style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 8,
                          child: Text('8 MB', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 16,
                          child: Text('16 MB',
                              style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 32,
                          child: Text('32 MB', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 64,
                          child: Text('64 MB', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 128,
                          child: Text('128 MB',
                              style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _bufferSizeMb = val);
                        PreferencesService.instance.bufferSizeMb = val;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.privacyFolder),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.lock_clock_outlined,
                    color: Colors.indigo,
                  ),
                  title: Text(l10n.vaultAutoLockTitle),
                  subtitle: Text(
                    _autoLockLabel(_vaultAutoLockSec),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: DropdownButton<int>(
                    value: _vaultAutoLockSec,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(
                          l10n.vaultAutoLockImmediate,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 60,
                        child: Text(
                          l10n.vaultAutoLockMinutes(1),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 300,
                        child: Text(
                          l10n.vaultAutoLockMinutes(5),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 600,
                        child: Text(
                          l10n.vaultAutoLockMinutes(10),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DropdownMenuItem(
                        value: -1,
                        child: Text(
                          l10n.vaultAutoLockNever,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _vaultAutoLockSec = val);
                        PreferencesService.instance.vaultAutoLockTimeoutSec = val;
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  minTileHeight: 40,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const AppCircleBadge(
                    icon: Icons.shield_outlined,
                    color: Colors.deepPurple,
                  ),
                  title: Text(l10n.vaultConfirmExternalOpenTitle),
                  subtitle: Text(
                    l10n.vaultConfirmExternalOpenDesc,
                    style: const TextStyle(fontSize: 10),
                  ),
                  value: !PreferencesService.instance.vaultSkipExternalOpenWarning,
                  onChanged: (val) {
                    setState(() {
                      PreferencesService.instance.vaultSkipExternalOpenWarning =
                          !val;
                    });
                  },
                ),
                if (PlatformCapabilities.supportsVaultVideoThumbnails) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    dense: true,
                    visualDensity:
                        const VisualDensity(horizontal: -2, vertical: -2),
                    minTileHeight: 40,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    secondary: const AppCircleBadge(
                      icon: Icons.video_library_outlined,
                      color: Colors.blueGrey,
                    ),
                    title: Text(l10n.vaultVideoThumbnailsTitle),
                    subtitle: Text(
                      l10n.vaultVideoThumbnailsDesc,
                      style: const TextStyle(fontSize: 10),
                    ),
                    value: PreferencesService.instance.vaultVideoThumbnails,
                    onChanged: (val) {
                      setState(() {
                        PreferencesService.instance.vaultVideoThumbnails = val;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          _buildSectionHeader(context, l10n.storageAndCache),
          Card(
            child: Column(
              children: [
                if (!_secretEncryptionActive) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: Colors.amber.withValues(alpha: 0.14),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.unencryptedCredentialsBanner,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  key: const ValueKey('settings_history_retention_tile'),
                  leading: const AppCircleBadge(
                    icon: Icons.history_rounded,
                    color: Colors.indigo,
                  ),
                  title: Text(l10n.historyRetentionTitle),
                  subtitle: Text(
                    _historyRetentionDays == 0
                        ? l10n.historyRetentionDisabled
                        : l10n.historyRetentionDaysLabel(_historyRetentionDays),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: _configureHistoryRetention,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.cleaning_services_outlined,
                    color: Colors.orange,
                  ),
                  title: Text(l10n.temporaryCache),
                  subtitle: Text(
                    '${_formatBytes(_cacheSizeBytes)}'
                    '${_archiveCacheBytes > 0 ? " • ${l10n.archiveLabel}: ${_formatBytes(_archiveCacheBytes)}" : ""}'
                    '${_inboxCacheBytes > 0 ? " • ${l10n.receivedShareTitle}: ${_formatBytes(_inboxCacheBytes)}" : ""}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: _clearingCache
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _cacheSizeBytes > 0 ? _clearCache : null,
                          child: Text(l10n.clear),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.import_export_rounded,
                    color: Colors.teal,
                  ),
                  title: Text(l10n.backupRestoreConfigTitle),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.backupRestoreConfigSubtitle,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.upload_file, size: 16),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: _exportAppConfig,
                              label: Text(l10n.exportAction),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: _importAppConfig,
                              label: Text(l10n.importAction),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                    '${_buildTimeLabel != null ? '${l10n.buildLabel(_buildTimeLabel!)}\n' : ''}'
                    '${l10n.platformLabel(_platformLabel ?? Platform.operatingSystem)}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () {
                    final info = '${l10n.appTitle} ${_versionLabel ?? ""}\n'
                        '${_buildTimeLabel != null ? '${l10n.buildLabel(_buildTimeLabel!)}\n' : ''}'
                        '${l10n.platformLabel(_platformLabel ?? Platform.operatingSystem)}';
                    Clipboard.setData(ClipboardData(text: info));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.appInfoCopied)),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: AppCircleBadge(
                    icon: Icons.cloud_done,
                    color: Theme.of(context).colorScheme.success,
                  ),
                  title: Text(l10n.supportedProtocols),
                  subtitle: const Text(
                    'Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP, SMB, ZIP, TAR, 7Z',
                    style: TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(
                      text: 'Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP, SMB, ZIP, TAR, 7Z',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.supportedProtocolsCopied)),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.policy_outlined,
                    color: Colors.amber,
                  ),
                  title: Text(l10n.openSourceLicenses),
                  subtitle: Text(
                    l10n.openSourceLicensesSubtitle,
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: l10n.appTitle,
                      applicationVersion: _versionLabel,
                      applicationLegalese:
                          'Copyright © 2026 FP File Manager Contributors. Released under the MIT License.',
                    );
                  },
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
