import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/remotes.dart' as rem_api;
import 'keychain_service.dart';
import 'platform_paths.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  static const String _keychainRemotesKey = 'backup_remotes';
  static const String _keychainBookmarksKey = 'backup_bookmarks';
  static const String _remotesBackupFileName = 'remotes_backup.json';
  static const String _bookmarksBackupFileName = 'bookmarks_backup.json';

  String get dbPath => PlatformPaths.databasePath();

  bool _initialized = false;

  void ensureInitialized() {
    if (!_initialized) {
      fm_api.initDatabase(dbPath: dbPath);
      _initialized = true;
    }
  }

  // Remotes
  // These reads used to swallow every error and return an empty list, which
  // made a transient database failure look exactly like "you have no
  // bookmarks / remotes / history / trash" — data loss from the user's side.
  // The callers all have error handling; let them see the failure.
  Future<List<rem_api.RemoteConfigDto>> getRemotes() async {
    ensureInitialized();
    var rems = await rem_api.listRemotes(dbPath: dbPath);
    if (rems.isEmpty) {
      final restored = await _restoreRemotesFromBackup();
      if (restored.isNotEmpty) {
        rems = restored;
      }
    }
    return rems;
  }

  Future<void> saveRemote(rem_api.RemoteConfigDto config) async {
    ensureInitialized();
    await rem_api.saveRemote(dbPath: dbPath, config: config);
    unawaited(_syncRemotesBackup());
  }

  Future<void> deleteRemote(String id) async {
    ensureInitialized();
    await rem_api.deleteRemote(dbPath: dbPath, id: id);
    unawaited(_syncRemotesBackup());
  }

  Future<bool> testConnection(rem_api.RemoteConfigDto config) async {
    return await rem_api.testRemoteConnection(config: config);
  }

  Future<void> _syncRemotesBackup() async {
    try {
      final list = await rem_api.listRemotes(dbPath: dbPath);
      final jsonStr = jsonEncode(list.map(_remoteConfigToMap).toList());
      if (KeychainService.isSupported) {
        await KeychainService.save(_keychainRemotesKey, jsonStr);
      }
      final filePath = _backupFilePath(_remotesBackupFileName);
      if (filePath != null) {
        final f = File(filePath);
        await f.writeAsString(jsonStr);
      }
    } catch (_) {}
  }

  Future<List<rem_api.RemoteConfigDto>> _restoreRemotesFromBackup() async {
    // 1. iOS Keychain survives reinstall/uninstall
    if (KeychainService.isSupported) {
      try {
        final jsonStr = await KeychainService.read(_keychainRemotesKey);
        if (jsonStr != null && jsonStr.trim().isNotEmpty) {
          final list = _parseRemotesJson(jsonStr);
          if (list.isNotEmpty) {
            for (final r in list) {
              try {
                await rem_api.saveRemote(dbPath: dbPath, config: r);
              } catch (_) {}
            }
            return await rem_api.listRemotes(dbPath: dbPath);
          }
        }
      } catch (_) {}
    }

    // 2. Documents file backup (iCloud / iTunes sync)
    try {
      final filePath = _backupFilePath(_remotesBackupFileName);
      if (filePath != null) {
        final f = File(filePath);
        if (f.existsSync()) {
          final jsonStr = await f.readAsString();
          final list = _parseRemotesJson(jsonStr);
          if (list.isNotEmpty) {
            for (final r in list) {
              try {
                await rem_api.saveRemote(dbPath: dbPath, config: r);
              } catch (_) {}
            }
            return await rem_api.listRemotes(dbPath: dbPath);
          }
        }
      }
    } catch (_) {}

    return [];
  }

  Future<String> exportRemotesJson() async {
    final list = await getRemotes();
    final data = list.map(_remoteConfigToMap).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<int> importRemotesJson(String jsonStr) async {
    final list = _parseRemotesJson(jsonStr);
    if (list.isEmpty) return 0;
    var count = 0;
    for (final r in list) {
      try {
        await rem_api.saveRemote(dbPath: dbPath, config: r);
        count++;
      } catch (_) {}
    }
    if (count > 0) {
      await _syncRemotesBackup();
    }
    return count;
  }

  // Bookmarks
  Future<List<meta_api.BookmarkDto>> getBookmarks() async {
    ensureInitialized();
    var bms = await meta_api.listBookmarks(dbPath: dbPath);
    if (bms.isEmpty) {
      final restored = await _restoreBookmarksFromBackup();
      if (restored.isNotEmpty) {
        bms = restored;
      }
    }
    return bms;
  }

  Future<void> addBookmark({required String name, required String root, required String path}) async {
    ensureInitialized();
    await meta_api.addBookmark(dbPath: dbPath, name: name, root: root, path: path);
    unawaited(_syncBookmarksBackup());
  }

  Future<void> deleteBookmark(String id) async {
    ensureInitialized();
    await meta_api.deleteBookmark(dbPath: dbPath, id: id);
    unawaited(_syncBookmarksBackup());
  }

  Future<void> renameBookmark({
    required String id,
    required String oldName,
    required String newName,
    required String root,
    required String path,
  }) async {
    ensureInitialized();
    await deleteBookmark(id);
    try {
      await addBookmark(name: newName, root: root, path: path);
    } catch (_) {
      try {
        await addBookmark(name: oldName, root: root, path: path);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _syncBookmarksBackup() async {
    try {
      final list = await meta_api.listBookmarks(dbPath: dbPath);
      final jsonStr = jsonEncode(list.map(_bookmarkToMap).toList());
      if (KeychainService.isSupported) {
        await KeychainService.save(_keychainBookmarksKey, jsonStr);
      }
      final filePath = _backupFilePath(_bookmarksBackupFileName);
      if (filePath != null) {
        final f = File(filePath);
        await f.writeAsString(jsonStr);
      }
    } catch (_) {}
  }

  Future<List<meta_api.BookmarkDto>> _restoreBookmarksFromBackup() async {
    if (KeychainService.isSupported) {
      try {
        final jsonStr = await KeychainService.read(_keychainBookmarksKey);
        if (jsonStr != null && jsonStr.trim().isNotEmpty) {
          final list = _parseBookmarksJson(jsonStr);
          if (list.isNotEmpty) {
            for (final b in list) {
              try {
                await meta_api.addBookmark(dbPath: dbPath, name: b.name, root: b.root, path: b.path);
              } catch (_) {}
            }
            return await meta_api.listBookmarks(dbPath: dbPath);
          }
        }
      } catch (_) {}
    }

    try {
      final filePath = _backupFilePath(_bookmarksBackupFileName);
      if (filePath != null) {
        final f = File(filePath);
        if (f.existsSync()) {
          final jsonStr = await f.readAsString();
          final list = _parseBookmarksJson(jsonStr);
          if (list.isNotEmpty) {
            for (final b in list) {
              try {
                await meta_api.addBookmark(dbPath: dbPath, name: b.name, root: b.root, path: b.path);
              } catch (_) {}
            }
            return await meta_api.listBookmarks(dbPath: dbPath);
          }
        }
      }
    } catch (_) {}

    return [];
  }

  // History
  Future<List<meta_api.HistoryDto>> getHistory() async {
    ensureInitialized();
    return await meta_api.listHistory(dbPath: dbPath);
  }

  Future<void> clearHistory() async {
    ensureInitialized();
    await meta_api.clearHistory(dbPath: dbPath);
  }

  Future<void> removeHistoryEntry({required String root, required String path}) async {
    ensureInitialized();
    await meta_api.removeHistory(dbPath: dbPath, root: root, path: path);
  }

  Future<void> recordHistory({required String root, required String path}) async {
    ensureInitialized();
    try {
      await meta_api.recordHistory(dbPath: dbPath, root: root, path: path);
    } catch (_) {}
  }

  // Trash
  Future<List<meta_api.TrashItemDto>> getTrashItems() async {
    ensureInitialized();
    return await meta_api.listTrash(dbPath: dbPath);
  }

  Future<void> moveToTrash(String sourcePath) async {
    ensureInitialized();
    await meta_api.moveToTrash(dbPath: dbPath, sourcePath: sourcePath);
  }

  Future<void> restoreTrashItem(String id) async {
    ensureInitialized();
    await meta_api.restoreTrashItem(dbPath: dbPath, id: id);
  }

  Future<void> deleteTrashItem(String id) async {
    ensureInitialized();
    await meta_api.deleteTrashItem(dbPath: dbPath, id: id);
  }

  Future<void> clearTrash() async {
    ensureInitialized();
    await meta_api.clearTrash(dbPath: dbPath);
  }

  // Serialization helpers
  static String? _backupFilePath(String filename) {
    try {
      final root = PlatformPaths.defaultRoot();
      return '$root/$filename';
    } catch (_) {
      return null;
    }
  }

  static List<rem_api.RemoteConfigDto> _parseRemotesJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => _remoteConfigFromMap(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic> _remoteConfigToMap(rem_api.RemoteConfigDto c) => {
    'id': c.id,
    'name': c.name,
    'kind': c.kind,
    if (c.endpoint != null) 'endpoint': c.endpoint,
    if (c.bucket != null) 'bucket': c.bucket,
    if (c.region != null) 'region': c.region,
    if (c.accessKeyId != null) 'accessKeyId': c.accessKeyId,
    if (c.secretAccessKey != null) 'secretAccessKey': c.secretAccessKey,
    if (c.host != null) 'host': c.host,
    if (c.port != null) 'port': c.port,
    if (c.username != null) 'username': c.username,
    if (c.password != null) 'password': c.password,
    if (c.rootPath != null) 'rootPath': c.rootPath,
    'pathStyle': c.pathStyle,
  };

  static rem_api.RemoteConfigDto _remoteConfigFromMap(Map<String, dynamic> m) =>
      rem_api.RemoteConfigDto(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        kind: m['kind'] as String? ?? 's3',
        endpoint: m['endpoint'] as String?,
        bucket: m['bucket'] as String?,
        region: m['region'] as String?,
        accessKeyId: m['accessKeyId'] as String?,
        secretAccessKey: m['secretAccessKey'] as String?,
        host: m['host'] as String?,
        port: (m['port'] as num?)?.toInt(),
        username: m['username'] as String?,
        password: m['password'] as String?,
        rootPath: m['rootPath'] as String?,
        pathStyle: m['pathStyle'] as bool? ?? false,
      );

  static List<meta_api.BookmarkDto> _parseBookmarksJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => _bookmarkFromMap(m.cast<String, dynamic>()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic> _bookmarkToMap(meta_api.BookmarkDto b) => {
    'id': b.id,
    'name': b.name,
    'root': b.root,
    'path': b.path,
  };

  static meta_api.BookmarkDto _bookmarkFromMap(Map<String, dynamic> m) =>
      meta_api.BookmarkDto(
        id: m['id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        root: m['root'] as String? ?? '',
        path: m['path'] as String? ?? '',
      );
}
