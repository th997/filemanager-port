import 'dart:convert';
import 'dart:io';

import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/remotes.dart' as rem_api;
import 'keychain_service.dart';
import 'platform_paths.dart';
import 'preferences_service.dart';

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
    // A row whose config could not be decrypted comes back with every
    // field empty (only id/name/kind survive). Restoring from the backup
    // re-saves those ids with the current key, which repairs them. One
    // unreadable row is enough: a mixed list must not skip the repair.
    if (rems.isEmpty || rems.any(_isUnreadableRemote)) {
      final restored = await _restoreRemotesFromBackup();
      if (restored.isNotEmpty) {
        rems = restored;
      }
    }
    return rems;
  }

  /// A remote whose stored config could not be decrypted. The Rust side
  /// always fills `rootPath` for a readable config, so a null root with no
  /// host, endpoint or bucket cannot be a real connection.
  static bool _isUnreadableRemote(rem_api.RemoteConfigDto r) =>
      r.rootPath == null &&
      r.host == null &&
      r.endpoint == null &&
      r.bucket == null;

  Future<void> saveRemote(rem_api.RemoteConfigDto config) async {
    ensureInitialized();
    await rem_api.saveRemote(dbPath: dbPath, config: config);
    // Must finish before callers re-read: getRemotes() restores from backup
    // when the DB is empty, so a stale backup would resurrect deleted rows.
    await _syncRemotesBackup();
  }

  Future<void> deleteRemote(String id) async {
    ensureInitialized();
    await rem_api.deleteRemote(dbPath: dbPath, id: id);
    await _syncRemotesBackup();
  }

  Future<bool> testConnection(rem_api.RemoteConfigDto config) async {
    return await rem_api.testRemoteConnection(config: config);
  }

  Future<void> _syncRemotesBackup() async {
    try {
      final list = await rem_api.listRemotes(dbPath: dbPath);
      final previous = await _readRemotesBackup();
      // Could not read the old backup: writing now might destroy the only
      // plaintext copy of a row that is currently undecryptable.
      if (previous == null) {
        return;
      }
      final entries = <Map<String, dynamic>>[];
      for (final r in list) {
        if (!_isUnreadableRemote(r)) {
          entries.add(_remoteConfigToMap(r));
          continue;
        }
        // An unreadable row carries no credentials, so its previous backup
        // entry is the only plaintext copy left. Keep that rather than
        // writing an empty shell over it.
        final matches = previous.where((p) => p.id == r.id).toList();
        if (matches.isNotEmpty) {
          entries.add(_remoteConfigToMap(matches.first));
        }
      }
      // Written even when empty: ids absent from `list` were deleted, and
      // leaving them in the backup would let getRemotes() resurrect them.
      final jsonStr = jsonEncode(entries);
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

  /// The current backup contents, or null when they could not be read
  /// reliably (IO error, or a non-empty file that failed to parse). An
  /// absent backup is a legitimate empty list, not a failure.
  Future<List<rem_api.RemoteConfigDto>?> _readRemotesBackup() async {
    if (KeychainService.isSupported) {
      try {
        final jsonStr = await KeychainService.read(_keychainRemotesKey);
        if (jsonStr != null && jsonStr.trim().isNotEmpty) {
          final list = _parseRemotesJson(jsonStr);
          if (list.isNotEmpty) {
            return list;
          }
        }
      } catch (_) {}
    }
    try {
      final filePath = _backupFilePath(_remotesBackupFileName);
      if (filePath == null) {
        return null;
      }
      final f = File(filePath);
      if (!f.existsSync()) {
        return [];
      }
      final jsonStr = await f.readAsString();
      final list = _parseRemotesJson(jsonStr);
      if (list.isEmpty && jsonStr.trim().isNotEmpty && jsonStr.trim() != '[]') {
        return null;
      }
      return list;
    } catch (_) {
      return null;
    }
  }

  /// Re-saves only connections that are missing from the database or cannot
  /// be decrypted. Rewriting healthy rows would bump their `created_at` on
  /// every page load and reshuffle the list, which is ordered by it.
  Future<List<rem_api.RemoteConfigDto>> _restoreRemotesFromBackup() async {
    final backup = await _readRemotesBackup();
    if (backup == null || backup.isEmpty) {
      return [];
    }
    try {
      final current = await rem_api.listRemotes(dbPath: dbPath);
      final healthy = <String>{
        for (final r in current)
          if (!_isUnreadableRemote(r)) r.id,
      };
      var repaired = false;
      for (final r in backup) {
        if (healthy.contains(r.id)) {
          continue;
        }
        try {
          await rem_api.saveRemote(dbPath: dbPath, config: r);
          repaired = true;
        } catch (_) {}
      }
      if (!repaired) {
        return [];
      }
      return await rem_api.listRemotes(dbPath: dbPath);
    } catch (_) {
      return [];
    }
  }

  Future<String> exportRemotesJson() async {
    final list = await getRemotes();
    final data = list.map(_remoteConfigToMap).toList();
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Names of connections that failed to save during the last import, so
  /// the UI can report them instead of silently dropping them.
  List<String> lastImportFailures = [];

  Future<int> importRemotesJson(String jsonStr) async {
    final list = _parseRemotesJson(jsonStr, strict: true);
    lastImportFailures = [];
    if (list.isEmpty) return 0;
    var count = 0;
    for (final r in list) {
      try {
        await rem_api.saveRemote(dbPath: dbPath, config: r);
        count++;
      } catch (_) {
        lastImportFailures.add(r.name);
      }
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
    await _syncBookmarksBackup();
  }

  Future<void> deleteBookmark(String id) async {
    ensureInitialized();
    await meta_api.deleteBookmark(dbPath: dbPath, id: id);
    await _syncBookmarksBackup();
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
    } catch (e) {
      try {
        await addBookmark(name: oldName, root: root, path: path);
      } catch (_) {
        throw StateError('Rename failed and the bookmark could not be restored: $e');
      }
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
  static ({
    List<meta_api.HistoryDto> kept,
    List<meta_api.HistoryDto> expired,
  }) partitionHistoryByRetention(
    List<meta_api.HistoryDto> entries, {
    required int retentionDays,
    int? nowMillis,
  }) {
    if (retentionDays <= 0) {
      return (kept: const [], expired: List<meta_api.HistoryDto>.of(entries));
    }
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - retentionDays * Duration.millisecondsPerDay;
    final kept = <meta_api.HistoryDto>[];
    final expired = <meta_api.HistoryDto>[];
    for (final entry in entries) {
      if (entry.visitedMillis.toInt() >= cutoff) {
        kept.add(entry);
      } else {
        expired.add(entry);
      }
    }
    return (kept: kept, expired: expired);
  }

  Future<List<meta_api.HistoryDto>> getHistory() async {
    final retentionDays = PreferencesService.instance.historyRetentionDays;
    ensureInitialized();
    if (retentionDays <= 0) {
      try {
        await meta_api.clearHistory(dbPath: dbPath);
      } catch (_) {}
      return const [];
    }
    final entries = await meta_api.listHistory(dbPath: dbPath);
    final split = partitionHistoryByRetention(
      entries,
      retentionDays: retentionDays,
    );
    for (final h in split.expired) {
      try {
        await meta_api.removeHistory(dbPath: dbPath, root: h.root, path: h.path);
      } catch (_) {}
    }
    return split.kept;
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
    if (PreferencesService.instance.historyRetentionDays <= 0) return;
    ensureInitialized();
    try {
      await meta_api.recordHistory(dbPath: dbPath, root: root, path: path);
    } catch (_) {}
  }

  Future<void> applyHistoryRetention(int days) async {
    final clamped = days < 0 ? 0 : days;
    PreferencesService.instance.historyRetentionDays = clamped;
    try {
      ensureInitialized();
      if (clamped == 0) {
        await meta_api.clearHistory(dbPath: dbPath);
      } else {
        final entries = await meta_api.listHistory(dbPath: dbPath);
        final split = partitionHistoryByRetention(
          entries,
          retentionDays: clamped,
        );
        for (final h in split.expired) {
          await meta_api.removeHistory(dbPath: dbPath, root: h.root, path: h.path);
        }
      }
    } catch (_) {}
  }

  int? _cachedTrashCount;

  void invalidateTrashCount() {
    _cachedTrashCount = null;
  }

  Future<int> getTrashCount() async {
    if (_cachedTrashCount != null) {
      return _cachedTrashCount!;
    }
    final items = await getTrashItems();
    return items.length;
  }

  // Trash
  Future<List<meta_api.TrashItemDto>> getTrashItems() async {
    ensureInitialized();
    final items = await meta_api.listTrash(dbPath: dbPath);
    _cachedTrashCount = items.length;
    return items;
  }

  Future<void> moveToTrash(String sourcePath) async {
    ensureInitialized();
    await meta_api.moveToTrash(dbPath: dbPath, sourcePath: sourcePath);
    _cachedTrashCount = (_cachedTrashCount != null ? _cachedTrashCount! + 1 : null);
  }

  Future<void> restoreTrashItem(String id) async {
    ensureInitialized();
    await meta_api.restoreTrashItem(dbPath: dbPath, id: id);
    if (_cachedTrashCount != null) {
      _cachedTrashCount = _cachedTrashCount! > 0 ? _cachedTrashCount! - 1 : 0;
    }
  }

  Future<void> deleteTrashItem(String id) async {
    ensureInitialized();
    await meta_api.deleteTrashItem(dbPath: dbPath, id: id);
    if (_cachedTrashCount != null) {
      _cachedTrashCount = _cachedTrashCount! > 0 ? _cachedTrashCount! - 1 : 0;
    }
  }

  Future<void> clearTrash() async {
    ensureInitialized();
    await meta_api.clearTrash(dbPath: dbPath);
    _cachedTrashCount = 0;
  }

  // Serialization helpers
  static String? _backupFilePath(String filename) {
    try {
      // Android: app-private dir — shared storage would expose credentials
      // to every app. iOS Documents stays sandboxed and syncs via iCloud.
      final root = Platform.isAndroid
          ? PlatformPaths.appDataDir()
          : PlatformPaths.defaultRoot();
      return '$root/$filename';
    } catch (_) {
      return null;
    }
  }

  static List<rem_api.RemoteConfigDto> _parseRemotesJson(
    String jsonStr, {
    bool strict = false,
  }) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => _remoteConfigFromMap(m.cast<String, dynamic>()))
            .toList();
      }
      if (decoded is Map) {
        return [_remoteConfigFromMap(decoded.cast<String, dynamic>())];
      }
      if (strict) {
        throw const FormatException('Expected a JSON array or object of remote connections');
      }
    } catch (_) {
      if (strict) rethrow;
    }
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
    if (c.privateKey != null) 'privateKey': c.privateKey,
    if (c.passphrase != null) 'passphrase': c.passphrase,
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
        privateKey: m['privateKey'] as String?,
        passphrase: m['passphrase'] as String?,
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
