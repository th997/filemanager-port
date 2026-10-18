import 'dart:io';

class PlatformPaths {
  static String defaultRoot() {
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

  static List<QuickTarget> quickTargets() {
    final targets = <QuickTarget>[];
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
