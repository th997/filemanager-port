import 'package:flutter/foundation.dart';

import '../rust/api/file_manager.dart';

/// Standalone document controller for [TextEditorPage]: manages full/chunked
/// file loading, dirty tracking, saving, and find/replace match indexing.
class TextEditorDocumentController extends ChangeNotifier {
  static const int chunkPageBytes = 256 * 1024;

  String root;
  String path;
  bool readOnly;

  String _content = '';
  bool _loading = false;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;

  bool _largeFileMode = false;
  int _chunkStart = 0;
  int _chunkEnd = 0;
  int _chunkTotal = 0;
  bool _chunkHasPrev = false;
  bool _chunkHasNext = false;
  String _encoding = 'utf-8';
  final List<int> _prevOffsets = [];

  TextEditorDocumentController({
    required this.root,
    required this.path,
    this.readOnly = false,
  });

  String get content => _content;
  bool get loading => _loading;
  bool get saving => _saving;
  bool get isDirty => _isDirty;
  String? get error => _error;
  bool get largeFileMode => _largeFileMode;
  int get chunkStart => _chunkStart;
  int get chunkEnd => _chunkEnd;
  int get chunkTotal => _chunkTotal;
  bool get chunkHasPrev => _chunkHasPrev;
  bool get chunkHasNext => _chunkHasNext;
  String get encoding => _encoding;

  void updateContent(String next) {
    if (next == _content) return;
    _content = next;
    _isDirty = true;
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final text = await readTextFile(root: root, path: path);
      _content = text;
      _isDirty = false;
      _largeFileMode = false;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (e.toString().toLowerCase().contains('too large')) {
        _largeFileMode = true;
        readOnly = true;
        await loadChunkAt(0, resetHistory: true);
        return;
      }
      _error = '$e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadChunkAt(int offset, {bool resetHistory = false}) async {
    _loading = true;
    _error = null;
    if (resetHistory) _prevOffsets.clear();
    notifyListeners();
    try {
      final chunk = await readTextChunk(
        root: root,
        path: path,
        offset: BigInt.from(offset),
        maxBytes: BigInt.from(chunkPageBytes),
      );
      _content = chunk.text;
      _chunkStart = chunk.startOffset.toInt();
      _chunkEnd = chunk.endOffset.toInt();
      _chunkTotal = chunk.totalSize.toInt();
      _chunkHasPrev = chunk.hasPrev;
      _chunkHasNext = chunk.hasNext;
      _encoding = chunk.encoding;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = '$e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> save() async {
    if (readOnly || _saving) return;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await writeTextFile(root: root, path: path, content: _content);
      _isDirty = false;
    } catch (e) {
      _error = '$e';
      rethrow;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// Find all case-insensitive occurrences of [query] in [_content].
  List<int> findAllIndices(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return const [];
    final haystack = caseSensitive ? _content : _content.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    final matches = <int>[];
    int pos = 0;
    while (true) {
      final idx = haystack.indexOf(needle, pos);
      if (idx < 0) break;
      matches.add(idx);
      pos = idx + needle.length;
    }
    return matches;
  }
}
