import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
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
  if (!Platform.isIOS) {
    MediaKit.ensureInitialized();
  }
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
    _accentCode = PreferencesService.instance.getString(_accentKey) ?? 'deepTeal';
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

  static const _accentKey = 'app.accent';

  /// Accent seeds. The default moved off the template blue (0xFF1976D2)
  /// to a deep teal; the classic blue stays one tap away in Settings.
  static const Map<String, Color> accentSeeds = {
    'deepTeal': Color(0xFF00696D),
    'classicBlue': Color(0xFF1976D2),
    'indigo': Color(0xFF3949AB),
    'forest': Color(0xFF2E7D32),
    'sunset': Color(0xFFD84315),
    'grape': Color(0xFF6750A4),
  };

  /// 'dynamic' | a key of [accentSeeds]
  String _accentCode = 'deepTeal';

  void _updateAccent(String code) {
    PreferencesService.instance.setString(_accentKey, code);
    setState(() => _accentCode = code);
  }

  ThemeData _themeData(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 48,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(
          color: scheme.onSurface,
          size: 20,
        ),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurface,
          size: 20,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        minVerticalPadding: 2,
        minLeadingWidth: 32,
        minTileHeight: 44,
        titleTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 52,
        iconTheme: WidgetStateProperty.resolveWith((_) => const IconThemeData(size: 20)),
        labelTextStyle: WidgetStateProperty.resolveWith((_) => const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
        actionTextColor: scheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useDynamic = _accentCode == 'dynamic' &&
            lightDynamic != null &&
            darkDynamic != null;
        final seed = accentSeeds[_accentCode] ?? accentSeeds['deepTeal']!;
        final lightScheme = useDynamic
            ? lightDynamic
            : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
        final darkScheme = useDynamic
            ? darkDynamic
            : ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'File Manager',
          debugShowCheckedModeBanner: false,
          locale: _locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          themeMode: _themeMode,
          theme: _themeData(lightScheme),
          darkTheme: _themeData(darkScheme),
          home: HomePage(
            themeMode: _themeMode,
            onThemeModeChanged: _updateThemeMode,
            localeCode: _localeCode,
            onLocaleChanged: _updateLocale,
            accentCode: _accentCode,
            onAccentChanged: _updateAccent,
          ),
        );
      },
    );
  }
}
