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
