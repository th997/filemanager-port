import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PlatformPaths {
  static String? _iosDocuments;
  static String? _iosSupport;
  static String? _androidSupport;

  /// Resolve app-private directories before anything else runs.
  ///
  /// `$HOME` inside an iOS sandbox is not a browsable location, so the
  /// environment-based fallbacks used on desktop do not work there. On
  /// Android the database and backups must live in app-private storage,
  /// not shared storage where any app can read credentials.
  static Future<void> init() async {
    if (Platform.isIOS) {
      try {
        _iosDocuments = (await getApplicationDocumentsDirectory()).path;
        _iosSupport = (await getApplicationSupportDirectory()).path;
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        _androidSupport = (await getApplicationSupportDirectory()).path;
      } catch (_) {}
      _migrateLegacyAndroidData();
    }
  }

  static const _legacyAndroidDir = '/storage/emulated/0/.filemanager';

  /// Older builds kept the database and preferences in shared storage.
  /// Move them into the private dir once, then remove the exposed copies.
  static void _migrateLegacyAndroidData() {
    final target = _androidSupport;
    if (target == null || target == _legacyAndroidDir) return;
    try {
      final legacy = Directory(_legacyAndroidDir);
      if (!legacy.existsSync()) return;
      Directory(target).createSync(recursive: true);
      // The DB runs in WAL mode: recent commits live in the -wal sidecar
      // until a checkpoint. Copying only the .db silently dropped them.
      // `master.key` holds the credential key and is looked up next to the
      // DB, so leaving it behind makes every saved remote config
      // undecryptable in the new location.
      final files = <String>[
        'filemanager.db',
        'filemanager.db-wal',
        'filemanager.db-shm',
        'master.key',
        'preferences.json',
      ];
      for (final name in files) {
        final old = File('$_legacyAndroidDir/$name');
        final dst = File('$target/$name');
        if (old.existsSync() && !dst.existsSync()) {
          try {
            old.copySync(dst.path);
          } catch (_) {}
        }
      }
      // The private dir may already hold a key minted by a launch that ran
      // before this migration. In that case the legacy key is the only one
      // that can decrypt the rows just copied, so keep it in the private
      // dir as a fallback before removing the exposed shared-storage copy.
      final legacyKey = File('$_legacyAndroidDir/master.key');
      final newKey = File('$target/master.key');
      if (legacyKey.existsSync() && newKey.existsSync()) {
        try {
          if (legacyKey.readAsStringSync() != newKey.readAsStringSync()) {
            final fallback = File('$target/master.key.legacy');
            if (!fallback.existsSync()) {
              legacyKey.copySync(fallback.path);
            }
          }
        } catch (_) {}
      }
      // Delete only after every copy landed, so an interrupted migration
      // leaves the legacy set intact for the next launch.
      for (final name in files) {
        final old = File('$_legacyAndroidDir/$name');
        final dst = File('$target/$name');
        if (old.existsSync() && dst.existsSync()) {
          try {
            old.deleteSync();
          } catch (_) {}
        }
      }
      for (final name in ['remotes_backup.json', 'bookmarks_backup.json']) {
        final old = File('/storage/emulated/0/$name');
        if (old.existsSync()) {
          final dst = File('$target/$name');
          if (!dst.existsSync()) {
            try {
              old.copySync(dst.path);
            } catch (_) {}
          }
          if (dst.existsSync()) {
            try {
              old.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  static String defaultRoot() {
    if (Platform.isIOS) {
      return _iosDocuments ?? _iosSupport ?? '/';
    }
    if (Platform.isAndroid) {
      final sdcard = Directory('/storage/emulated/0');
      if (sdcard.existsSync()) {
        return sdcard.path;
      }
      return '/sdcard';
    }
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    return Platform.environment['HOME'] ?? '/';
  }

  static String appDataDir() {
    String dir;
    if (Platform.isIOS) {
      // Application Support is not exposed in the Files app, which is where
      // the database and preferences belong.
      dir = _iosSupport ?? _iosDocuments ?? Directory.systemTemp.path;
    } else if (Platform.isAndroid) {
      dir = _androidSupport ?? _legacyAndroidDir;
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? 'C:\\';
      dir = '$appData\\filemanager';
    } else {
      final home = Platform.environment['HOME'] ?? '/tmp';
      dir = '$home/.filemanager';
    }
    final d = Directory(dir);
    if (!d.existsSync()) {
      try {
        d.createSync(recursive: true);
      } catch (_) {}
    }
    return dir;
  }

  static String databasePath() {
    return '${appDataDir()}/filemanager.db';
  }

  /// Folders that commonly hold photos, newest-first scanning happens in the
  /// gallery page. Only existing directories are returned.
  static List<String> galleryDirs() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[];
    if (Platform.isIOS) {
      if (_iosDocuments != null) candidates.add(_iosDocuments!);
    } else if (Platform.isAndroid) {
      candidates.addAll([
        '/storage/emulated/0/DCIM',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
      ]);
    } else if (Platform.isWindows) {
      final user = Platform.environment['USERPROFILE'] ?? '';
      candidates.addAll(['$user\\Pictures', '$user\\Downloads', '$user\\Desktop']);
    } else {
      candidates.addAll(['$home/Pictures', '$home/Downloads', '$home/Desktop']);
    }
    return candidates.where((p) => p.isNotEmpty && Directory(p).existsSync()).toList();
  }

  static List<QuickTarget> quickTargets() {
    final targets = <QuickTarget>[];
    if (Platform.isIOS) {
      final docs = _iosDocuments;
      if (docs != null) {
        targets.add(QuickTarget(
          name: 'Documents',
          path: docs,
          root: docs,
          relPath: '',
        ));
      }
      return targets;
    }
    if (Platform.isAndroid) {
      targets.addAll([
        const QuickTarget(
          name: 'Internal Storage',
          path: '/storage/emulated/0',
          root: '/storage/emulated/0',
          relPath: '',
        ),
        const QuickTarget(
          name: 'Download',
          path: '/storage/emulated/0/Download',
          root: '/storage/emulated/0',
          relPath: 'Download',
        ),
        const QuickTarget(
          name: 'DCIM (Photos)',
          path: '/storage/emulated/0/DCIM',
          root: '/storage/emulated/0',
          relPath: 'DCIM',
        ),
        const QuickTarget(
          name: 'Pictures',
          path: '/storage/emulated/0/Pictures',
          root: '/storage/emulated/0',
          relPath: 'Pictures',
        ),
        const QuickTarget(
          name: 'Documents',
          path: '/storage/emulated/0/Documents',
          root: '/storage/emulated/0',
          relPath: 'Documents',
        ),
      ]);
    } else if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\';
      targets.addAll([
        QuickTarget(
          name: 'Home',
          path: home,
          root: home,
          relPath: '',
        ),
        QuickTarget(
          name: 'Downloads',
          path: '$home\\Downloads',
          root: home,
          relPath: 'Downloads',
        ),
        QuickTarget(
          name: 'Documents',
          path: '$home\\Documents',
          root: home,
          relPath: 'Documents',
        ),
      ]);
      for (final letter in 'CDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
        final drive = '$letter:\\';
        if (Directory(drive).existsSync()) {
          targets.add(
            QuickTarget(
              name: 'Drive ($letter:)',
              path: drive,
              root: drive,
              relPath: '',
            ),
          );
        }
      }
    } else {
      final home = Platform.environment['HOME'] ?? '/';
      targets.addAll([
        QuickTarget(
          name: 'Home',
          path: home,
          root: home,
          relPath: '',
        ),
        QuickTarget(
          name: 'Downloads',
          path: '$home/Downloads',
          root: home,
          relPath: 'Downloads',
        ),
        QuickTarget(
          name: 'Documents',
          path: '$home/Documents',
          root: home,
          relPath: 'Documents',
        ),
        if (Platform.isMacOS) ...[
          QuickTarget(
            name: 'Desktop',
            path: '$home/Desktop',
            root: home,
            relPath: 'Desktop',
          ),
          if (Directory('/Volumes').existsSync())
            const QuickTarget(
              name: 'Volumes',
              path: '/Volumes',
              root: '/Volumes',
              relPath: '',
            ),
        ],
        const QuickTarget(
          name: 'Root /',
          path: '/',
          root: '/',
          relPath: '',
        ),
      ]);
    }
    return targets;
  }
}

class QuickTarget {
  final String name;
  final String path;
  final String root;
  final String relPath;

  const QuickTarget({
    required this.name,
    required this.path,
    required this.root,
    required this.relPath,
  });
}
