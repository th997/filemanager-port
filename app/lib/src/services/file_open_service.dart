import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../rust/api/file_manager.dart';

/// Hands files to other apps.
///
/// Files inside an app-private root are exported to the cache first: the
/// receiving app cannot read our sandbox, and Android 7+ refuses `file://`
/// URIs across packages.
class FileOpenService {
  static final FileOpenService instance = FileOpenService._();
  FileOpenService._();

  Future<Directory> _exportDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/open-with');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Native path for `root`/`path`, exporting it out of the VFS when needed.
  Future<String> nativePath(String root, String path) async {
    if (root.startsWith('/')) {
      final native = '$root/$path';
      if (File(native).existsSync()) return native;
    }
    final dir = await _exportDir();
    return exportToNative(root: root, path: path, cacheDir: dir.path);
  }

  Future<OpenResult> openWith(String root, String path) async {
    final native = await nativePath(root, path);
    return OpenFilex.open(native);
  }

  Future<void> share(String root, String path) async {
    final native = await nativePath(root, path);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(native)]),
    );
  }

  /// Remove exported copies once the caller is done with them.
  Future<void> clearExports() async {
    final dir = await _exportDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
