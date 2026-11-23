import 'dart:collection';
import 'dart:typed_data';

/// Bounded LRU in-memory image prefetch cache used by [ImageViewerPage] for
/// remote, archive, and zero-disk Privacy Vault images.
class ImagePrefetchController<K> {
  final int maxBudgetBytes;
  final LinkedHashMap<K, Uint8List> _cache = LinkedHashMap<K, Uint8List>();
  final Map<K, Future<Uint8List>> _inFlight = {};
  int _usedBytes = 0;

  ImagePrefetchController({this.maxBudgetBytes = 48 * 1024 * 1024});

  int get usedBytes => _usedBytes;
  int get length => _cache.length;

  Uint8List? get(K key) {
    final hit = _cache.remove(key);
    if (hit != null) {
      // Refresh LRU recency.
      _cache[key] = hit;
    }
    return hit;
  }

  Future<Uint8List> getOrLoad(K key, Future<Uint8List> Function() loader) {
    final existing = get(key);
    if (existing != null) return Future.value(existing);
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = loader().then((bytes) {
      _inFlight.remove(key);
      put(key, bytes);
      return bytes;
    }).catchError((Object err, StackTrace st) {
      _inFlight.remove(key);
      Error.throwWithStackTrace(err, st);
    });
    _inFlight[key] = future;
    return future;
  }

  void put(K key, Uint8List bytes) {
    final old = _cache.remove(key);
    if (old != null) _usedBytes -= old.lengthInBytes;
    _cache[key] = bytes;
    _usedBytes += bytes.lengthInBytes;
    _evictIfNeeded(keep: key);
  }

  void _evictIfNeeded({K? keep}) {
    while (_usedBytes > maxBudgetBytes && _cache.length > 1) {
      final oldestKey = _cache.keys.firstWhere(
        (k) => k != keep,
        orElse: () => _cache.keys.first,
      );
      if (oldestKey == keep) break;
      final removed = _cache.remove(oldestKey);
      if (removed != null) _usedBytes -= removed.lengthInBytes;
    }
  }

  void remove(K key) {
    final removed = _cache.remove(key);
    if (removed != null) _usedBytes -= removed.lengthInBytes;
    _inFlight.remove(key);
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
    _usedBytes = 0;
  }
}
