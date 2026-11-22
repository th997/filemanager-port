import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../rust/api/file_manager.dart';
import 'path_utils.dart';

/// Hands files to other apps.
///
/// Files inside an app-private root are exported to the cache first: the
/// receiving app cannot read our sandbox, and Android 7+ refuses `file://`
/// URIs across packages.
class FileOpenService {
  static final FileOpenService instance = FileOpenService._();
  FileOpenService._();

  Future<Directory> _exportDir({String? vaultId}) async {
    final base = await getTemporaryDirectory();
    final sub = vaultId == null ? 'open-with' : joinNative('open-with', 'vault_$vaultId');
    final dir = Directory(joinNative(base.path, sub));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Native path for `root`/`path`, exporting it out of the VFS when needed.
  Future<String> nativePath(String root, String path) async {
    if (isNativeRoot(root)) {
      final native = joinNative(root, path);
      if (File(native).existsSync()) return native;
    }
    final dir = await _exportDir(vaultId: vaultIdFromRoot(root));
    return exportToNative(root: root, path: path, cacheDir: dir.path);
  }

  Future<OpenResult> openWith(String root, String path) async {
    final native = await nativePath(root, path);
    if (Platform.isLinux) {
      try {
        await Process.start('gio', ['open', native], mode: ProcessStartMode.detached);
        return OpenResult(type: ResultType.done, message: 'done');
      } catch (_) {
        try {
          await Process.start('xdg-open', [native], mode: ProcessStartMode.detached);
          return OpenResult(type: ResultType.done, message: 'done');
        } catch (_) {}
      }
    }
    return OpenFilex.open(native);
  }

  Future<void> share(String root, String path) async {
    final native = await nativePath(root, path);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(native)]),
    );
  }

  /// Total size of exported temporary files in bytes.
  Future<int> getExportCacheSizeBytes() async {
    final dir = await _exportDir();
    if (!dir.existsSync()) return 0;
    int total = 0;
    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    } catch (_) {}
    return total;
  }

  /// Remove exported copies once the caller is done with them.
  Future<void> clearExports() async {
    final dir = await _exportDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// Remove any exported plaintext copies produced from a locked privacy folder.
  Future<void> clearVaultExports([String? vaultId]) async {
    try {
      if (vaultId != null) {
        final dir = await _exportDir(vaultId: vaultId);
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
        return;
      }
      final base = await _exportDir();
      if (!base.existsSync()) return;
      for (final entity in base.listSync(followLinks: false)) {
        if (entity is Directory &&
            entity.path.split(Platform.pathSeparator).last.startsWith('vault_')) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
