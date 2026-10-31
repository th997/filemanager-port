/// Whether `root` is a native filesystem path rather than a VFS URI.
bool isNativeRoot(String root) {
  if (root.isEmpty) return false;
  if (root.codeUnitAt(0) == 47) return true; // '/'
  if (root.length >= 3) {
    final c0 = root.codeUnitAt(0);
    final isDrive = (c0 >= 65 && c0 <= 90) || (c0 >= 97 && c0 <= 122);
    if (isDrive && root.codeUnitAt(1) == 58 /* ':' */) {
      final c2 = root.codeUnitAt(2);
      if (c2 == 47 /* '/' */ || c2 == 92 /* '\' */) return true;
    }
  }
  return false;
}

/// Join a VFS-relative path onto a native root.
///
/// Plain string interpolation yields `//` when the root already ends in a
/// separator, and breaks Windows roots (`C:\` + `/` + `a`).
String joinNative(String root, String relPath) {
  if (relPath.isEmpty) return root;
  final separator = root.contains('\\') ? '\\' : '/';
  final trimmedRoot = root.endsWith('/') || root.endsWith('\\')
      ? root.substring(0, root.length - 1)
      : root;
  if (separator == '/') {
    final cleanRel = relPath.startsWith('/') ? relPath.substring(1) : relPath;
    if (!cleanRel.contains('//')) {
      return '$trimmedRoot/$cleanRel';
    }
  }
  final rel = relPath.split('/').where((s) => s.isNotEmpty).join(separator);
  return '$trimmedRoot$separator$rel';
}

/// Splits an absolute native filesystem path into a parent root directory and an item name.
({String srcRoot, String name}) splitNativeFile(String fullPath) {
  final isWindows = fullPath.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(fullPath);
  if (isWindows) {
    final normalized = fullPath.replaceAll('/', '\\');
    final driveMatch = RegExp(r'^([a-zA-Z]:\\?)(.*)$').firstMatch(normalized);
    if (driveMatch != null) {
      var root = driveMatch.group(1)!;
      if (!root.endsWith('\\')) root = '$root\\';
      final rest = driveMatch.group(2)!.replaceAll(RegExp(r'^\\+|\\+$'), '');
      final idx = rest.lastIndexOf('\\');
      if (idx < 0) {
        return (srcRoot: root, name: rest);
      }
      return (
        srcRoot: '$root${rest.substring(0, idx)}',
        name: rest.substring(idx + 1),
      );
    }
  }

  // Linux / macOS / POSIX
  final clean = fullPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final idx = clean.lastIndexOf('/');
  if (idx <= 0) {
    return (srcRoot: '/', name: clean.substring(idx + 1));
  }
  return (
    srcRoot: clean.substring(0, idx),
    name: clean.substring(idx + 1),
  );
}

/// Splits an absolute native filesystem directory path into root and relPath for VFS navigation.
({String root, String relPath}) splitPathToRootAndRel(String fullPath) {
  final isWindows = fullPath.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(fullPath);
  if (isWindows) {
    final driveMatch = RegExp(r'^([a-zA-Z]:[\\/]?)(.*)$').firstMatch(fullPath);
    if (driveMatch != null) {
      var root = driveMatch.group(1)!;
      if (!root.endsWith('\\') && !root.endsWith('/')) {
        root = '$root\\';
      }
      final rel = driveMatch.group(2)!.replaceAll('/', '\\').replaceAll(RegExp(r'^[\\/]+|[\\/]+$'), '');
      return (root: root, relPath: rel);
    }
  }

  // POSIX / Linux / macOS
  final clean = fullPath.replaceAll('\\', '/');
  final rel = clean.replaceAll(RegExp(r'^/+|/+$'), '');
  return (root: '/', relPath: rel);
}

/// Formats a directory path for compact display in chips (e.g. "parent/current").
String shortDirectoryName(String fullPath) {
  final clean = fullPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final segs = clean.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return clean.isEmpty ? '/' : clean;
  if (segs.length == 1) return segs.first;
  return '${segs[segs.length - 2]}/${segs.last}';
}
