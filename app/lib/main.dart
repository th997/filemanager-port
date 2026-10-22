import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/app_localizations.dart';
import 'src/pages/home_page.dart';
import 'src/rust/frb_generated.dart';
import 'src/services/permission_service.dart';
import 'src/services/platform_paths.dart';
import 'src/services/preferences_service.dart';
import 'src/services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await RustLib.init();
  await PlatformPaths.init();
  StorageService.instance.ensureInitialized();
  await PreferencesService.instance.load();
  PreferencesService.instance.syncToolbarAtBottom();
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await _initDesktopWindow();
  }
  if (Platform.isAndroid && !await PermissionService.instance.hasStorageAccess()) {
    await PermissionService.instance.requestStorageAccess();
  }
  runApp(const FileManagerApp());
}

/// Persists window bounds on move/resize so the next launch restores
/// them. Kept as a single shared instance registered with window_manager.
class _WindowBoundsSaver with WindowListener {
  Future<void> _save() async {
    try {
      final bounds = await windowManager.getBounds();
      final prefs = PreferencesService.instance;
      prefs.setString('window.x', bounds.left.toString());
      prefs.setString('window.y', bounds.top.toString());
      prefs.setString('window.width', bounds.width.toString());
      prefs.setString('window.height', bounds.height.toString());
    } catch (_) {}
  }

  @override
  void onWindowMoved() => _save();

  @override
  void onWindowResized() => _save();
}

final _windowBoundsSaver = _WindowBoundsSaver();

Future<void> _initDesktopWindow() async {
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(800, 500));
  final prefs = PreferencesService.instance;
  double? read(String key) => double.tryParse(prefs.getString(key) ?? '');
  final w = read('window.width');
  final h = read('window.height');
  final x = read('window.x');
  final y = read('window.y');
  if (w != null && h != null && w >= 800 && h >= 500) {
    await windowManager.setBounds(
      Rect.fromLTWH(x ?? 0, y ?? 0, w, h),
      animate: false,
    );
    if (x == null || y == null) await windowManager.center();
  }
  windowManager.addListener(_windowBoundsSaver);
}

class FileManagerApp extends StatefulWidget {
  const FileManagerApp({super.key});

  @override
  State<FileManagerApp> createState() => _FileManagerAppState();
}

class _FileManagerAppState extends State<FileManagerApp> {
  static const _themeKey = 'theme_mode';
  static const _localeKey = 'app.language';

  ThemeMode _themeMode = ThemeMode.system;

  /// 'system' | 'en' | 'zh'
  String _localeCode = 'system';

  @override
  void initState() {
    super.initState();
    final saved = PreferencesService.instance.getString(_themeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
    _localeCode = PreferencesService.instance.getString(_localeKey) ?? 'system';
  }

  void _updateThemeMode(ThemeMode mode) {
    PreferencesService.instance.setString(_themeKey, mode.name);
    setState(() {
      _themeMode = mode;
    });
  }

  void _updateLocale(String code) {
    PreferencesService.instance.setString(_localeKey, code);
    setState(() => _localeCode = code);
  }

  Locale? get _locale =>
      _localeCode == 'system' ? null : Locale(_localeCode);

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1976D2);

    return MaterialApp(
      title: 'File Manager',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        listTileTheme: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity(horizontal: -2, vertical: -3),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minVerticalPadding: 0,
          minTileHeight: 36,
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 52,
          iconTheme: WidgetStateProperty.resolveWith((_) => const IconThemeData(size: 20)),
          labelTextStyle: WidgetStateProperty.resolveWith((_) => const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        listTileTheme: const ListTileThemeData(
          dense: true,
          visualDensity: VisualDensity(horizontal: -2, vertical: -3),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          minVerticalPadding: 0,
          minTileHeight: 36,
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 52,
          iconTheme: WidgetStateProperty.resolveWith((_) => const IconThemeData(size: 20)),
          labelTextStyle: WidgetStateProperty.resolveWith((_) => const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
        ),
      ),
      home: HomePage(
        themeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
        localeCode: _localeCode,
        onLocaleChanged: _updateLocale,
      ),
    );
  }
}
