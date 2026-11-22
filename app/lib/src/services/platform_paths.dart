import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';

class PlatformPaths {
  static String? _iosDocuments;
  static String? _iosSupport;
  static String? _macosSupport;
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
    } else if (Platform.isMacOS) {
      try {
        _macosSupport = (await getApplicationSupportDirectory()).path;
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        _androidSupport = (await getApplicationSupportDirectory()).path;
      } catch (_) {}
      _migrateLegacyAndroidData();
    }
    final inbox = privateInboxDir();
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        Process.runSync('chmod', ['700', inbox]);
      } catch (_) {}
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

  /// App-private Inbox folder inside sandboxed application support/data storage.
  ///
  /// Inaccessible to other apps on iOS (not exposed in Files app) and Android
  /// (UID/SELinux isolated internal storage, hidden from MediaStore & MTP).
  static String privateInboxDir({bool create = true}) {
    final String dir;
    if (Platform.isIOS) {
      final base = _iosSupport ?? appDataDir();
      dir = '$base/Inbox';
    } else if (Platform.isMacOS) {
      final base = _macosSupport ?? appDataDir();
      dir = '$base/Inbox';
    } else if (Platform.isAndroid) {
      final base = _androidSupport ?? appDataDir();
      dir = '$base/Inbox';
    } else if (Platform.isWindows) {
      dir = '${appDataDir()}\\Inbox';
    } else {
      dir = '${appDataDir()}/Inbox';
    }
    if (create) {
      final d = Directory(dir);
      if (!d.existsSync()) {
        try {
          d.createSync(recursive: true);
        } catch (_) {}
      }
    }
    return dir;
  }

  static String _canonicalComparePath(String path) {
    var s = path.replaceAll('\\', '/');
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if ((Platform.isIOS || Platform.isMacOS) &&
        (s.startsWith('/private/var/') ||
            s == '/private/var' ||
            s.startsWith('/private/tmp/') ||
            s == '/private/tmp')) {
      s = s.substring('/private'.length);
    }
    if (Platform.isWindows) {
      s = s.toLowerCase();
    }
    return s;
  }

  static bool isPrivateInboxRoot(String path) {
    if (path.isEmpty) return false;
    return _canonicalComparePath(path) ==
        _canonicalComparePath(privateInboxDir(create: false));
  }

  static bool isInsidePrivateInbox(String path) {
    if (path.isEmpty) return false;
    final inbox = _canonicalComparePath(privateInboxDir(create: false));
    final c = _canonicalComparePath(path);
    return c == inbox || c.startsWith('$inbox/');
  }

  static ({String root, String relPath})? splitPrivateInboxPath(String fullPath) {
    if (!isInsidePrivateInbox(fullPath)) return null;
    final inboxCmp = _canonicalComparePath(privateInboxDir(create: false));
    final fullCmp = _canonicalComparePath(fullPath);
    if (fullCmp == inboxCmp) {
      return (root: privateInboxDir(), relPath: '');
    }
    var norm = fullPath.replaceAll('\\', '/');
    while (norm.length > 1 && norm.endsWith('/')) {
      norm = norm.substring(0, norm.length - 1);
    }
    if ((Platform.isIOS || Platform.isMacOS) &&
        (norm.startsWith('/private/var/') || norm.startsWith('/private/tmp/'))) {
      norm = norm.substring('/private'.length);
    }
    final rel = norm.length > inboxCmp.length + 1
        ? norm.substring(inboxCmp.length + 1)
        : '';
    return (root: privateInboxDir(), relPath: rel);
  }

  /// Default storage directory for privacy folders.
  ///
  /// Android / iOS / macOS keep vaults inside app-private Application Support
  /// storage (inaccessible to other apps and hidden from iOS Files app).
  /// Windows / Linux default to the hidden `~/.fpm` folder.
  static String defaultVaultStorageDir() {
    if (Platform.isIOS) {
      final base = _iosSupport ?? appDataDir();
      return '$base/private_vaults';
    }
    if (Platform.isMacOS) {
      final base = _macosSupport ?? appDataDir();
      return '$base/private_vaults';
    }
    if (Platform.isAndroid) {
      final base = _androidSupport ?? appDataDir();
      return '$base/private_vaults';
    }
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['APPDATA'] ??
          'C:\\';
      final trimmed = home.endsWith('\\') || home.endsWith('/')
          ? home.substring(0, home.length - 1)
          : home;
      return '$trimmed\\.fpm';
    }
    final home = Platform.environment['HOME'] ?? '/tmp';
    final trimmed =
        home.endsWith('/') ? home.substring(0, home.length - 1) : home;
    return '$trimmed/.fpm';
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
    final inbox = privateInboxDir();
    final inboxTarget = QuickTarget(
      name: 'My Space',
      kind: 'inbox',
      path: inbox,
      root: inbox,
      relPath: '',
    );
    if (Platform.isIOS) {
      final docs = _iosDocuments;
      if (docs != null) {
        targets.add(QuickTarget(
          name: 'Documents',
          kind: 'documents',
          path: docs,
          root: docs,
          relPath: '',
        ));
      }
      targets.add(inboxTarget);
      return targets;
    }
    if (Platform.isAndroid) {
      targets.addAll([
        const QuickTarget(
          name: 'Internal Storage',
          kind: 'storage',
          path: '/storage/emulated/0',
          root: '/storage/emulated/0',
          relPath: '',
        ),
        inboxTarget,
        const QuickTarget(
          name: 'Download',
          kind: 'download',
          path: '/storage/emulated/0/Download',
          root: '/storage/emulated/0',
          relPath: 'Download',
        ),
        const QuickTarget(
          name: 'DCIM (Photos)',
          kind: 'dcim',
          path: '/storage/emulated/0/DCIM',
          root: '/storage/emulated/0',
          relPath: 'DCIM',
        ),
        const QuickTarget(
          name: 'Pictures',
          kind: 'pictures',
          path: '/storage/emulated/0/Pictures',
          root: '/storage/emulated/0',
          relPath: 'Pictures',
        ),
        const QuickTarget(
          name: 'Documents',
          kind: 'documents',
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
          kind: 'home',
          path: home,
          root: home,
          relPath: '',
        ),
        inboxTarget,
        QuickTarget(
          name: 'Downloads',
          kind: 'downloads',
          path: '$home\\Downloads',
          root: home,
          relPath: 'Downloads',
        ),
        QuickTarget(
          name: 'Documents',
          kind: 'documents',
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
              kind: 'drive',
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
          kind: 'home',
          path: home,
          root: home,
          relPath: '',
        ),
        inboxTarget,
        QuickTarget(
          name: 'Downloads',
          kind: 'downloads',
          path: '$home/Downloads',
          root: home,
          relPath: 'Downloads',
        ),
        QuickTarget(
          name: 'Documents',
          kind: 'documents',
          path: '$home/Documents',
          root: home,
          relPath: 'Documents',
        ),
        if (Platform.isMacOS) ...[
          QuickTarget(
            name: 'Desktop',
            kind: 'desktop',
            path: '$home/Desktop',
            root: home,
            relPath: 'Desktop',
          ),
          if (Directory('/Volumes').existsSync())
            const QuickTarget(
              name: 'Volumes',
              kind: 'volumes',
              path: '/Volumes',
              root: '/Volumes',
              relPath: '',
            ),
        ],
        const QuickTarget(
          name: 'Root /',
          kind: 'root',
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
  final String kind;
  final String path;
  final String root;
  final String relPath;

  const QuickTarget({
    required this.name,
    required this.kind,
    required this.path,
    required this.root,
    required this.relPath,
  });

  /// Localized display name; [name] stays as the English fallback for when
  /// no localizations are available (e.g. background isolates).
  String displayName(AppLocalizations? l10n) {
    if (l10n == null) return name;
    switch (kind) {
      case 'storage':
        return l10n.internalStorage;
      case 'documents':
        return l10n.documentsDir;
      case 'download':
        return l10n.quickDownload;
      case 'downloads':
        return l10n.quickDownloads;
      case 'dcim':
        return l10n.quickDcim;
      case 'pictures':
        return l10n.quickPictures;
      case 'home':
        return l10n.quickHome;
      case 'inbox':
        return l10n.quickInbox;
      case 'desktop':
        return l10n.quickDesktop;
      case 'volumes':
        return l10n.quickVolumes;
      case 'root':
        return l10n.quickRoot;
      case 'drive':
        return l10n.quickDrive(path[0]);
      default:
        return name;
    }
  }
}
