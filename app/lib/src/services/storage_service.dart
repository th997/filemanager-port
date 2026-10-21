import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/remotes.dart' as rem_api;
import 'platform_paths.dart';

class StorageService {
  static final StorageService instance = StorageService._();
  StorageService._();

  String get dbPath => PlatformPaths.databasePath();

  bool _initialized = false;

  void ensureInitialized() {
    if (!_initialized) {
      fm_api.initDatabase(dbPath: dbPath);
      _initialized = true;
    }
  }

  // Remotes
  Future<List<rem_api.RemoteConfigDto>> getRemotes() async {
    ensureInitialized();
    try {
      return await rem_api.listRemotes(dbPath: dbPath);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRemote(rem_api.RemoteConfigDto config) async {
    ensureInitialized();
    await rem_api.saveRemote(dbPath: dbPath, config: config);
  }

  Future<void> deleteRemote(String id) async {
    ensureInitialized();
    await rem_api.deleteRemote(dbPath: dbPath, id: id);
  }

  Future<bool> testConnection(rem_api.RemoteConfigDto config) async {
    return await rem_api.testRemoteConnection(config: config);
  }

  // Bookmarks
  Future<List<meta_api.BookmarkDto>> getBookmarks() async {
    ensureInitialized();
    try {
      return await meta_api.listBookmarks(dbPath: dbPath);
    } catch (_) {
      return [];
    }
  }

  Future<void> addBookmark({required String name, required String root, required String path}) async {
    ensureInitialized();
    await meta_api.addBookmark(dbPath: dbPath, name: name, root: root, path: path);
  }

  Future<void> deleteBookmark(String id) async {
    ensureInitialized();
    await meta_api.deleteBookmark(dbPath: dbPath, id: id);
  }

  Future<void> renameBookmark({
    required String id,
    required String newName,
    required String root,
    required String path,
  }) async {
    ensureInitialized();
    await deleteBookmark(id);
    await addBookmark(name: newName, root: root, path: path);
  }

  // History
  Future<List<meta_api.HistoryDto>> getHistory() async {
    ensureInitialized();
    try {
      return await meta_api.listHistory(dbPath: dbPath);
    } catch (_) {
      return [];
    }
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
    try {
      return await meta_api.listTrash(dbPath: dbPath);
    } catch (_) {
      return [];
    }
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
}
