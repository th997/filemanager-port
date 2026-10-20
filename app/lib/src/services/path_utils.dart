/// Whether `root` is a native filesystem path rather than a VFS URI.
bool isNativeRoot(String root) {
  return root.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(root);
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
  final rel = relPath.split('/').where((s) => s.isNotEmpty).join(separator);
  return '$trimmedRoot$separator$rel';
}
