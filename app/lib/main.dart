import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
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
  if (Platform.isAndroid && !await PermissionService.instance.hasStorageAccess()) {
    await PermissionService.instance.requestStorageAccess();
  }
  runApp(const FileManagerApp());
}

class FileManagerApp extends StatefulWidget {
  const FileManagerApp({super.key});

  @override
  State<FileManagerApp> createState() => _FileManagerAppState();
}

class _FileManagerAppState extends State<FileManagerApp> {
  static const _themeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    final saved = PreferencesService.instance.getString(_themeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  void _updateThemeMode(ThemeMode mode) {
    PreferencesService.instance.setString(_themeKey, mode.name);
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1976D2);

    return MaterialApp(
      title: 'File Manager',
      debugShowCheckedModeBanner: false,
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
      ),
    );
  }
}
