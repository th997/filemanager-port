import 'package:flutter/foundation.dart';

/// Operation held in the global cross-tab / cross-pane clipboard.
enum ClipboardOp { copy, cut }

/// Snapshot of the entries currently queued for paste.
class BrowserClipboardSnapshot {
  final ClipboardOp op;
  final String sourceRoot;
  final List<String> paths;

  const BrowserClipboardSnapshot({
    required this.op,
    required this.sourceRoot,
    required this.paths,
  });

  int get count => paths.length;
  bool get isCut => op == ClipboardOp.cut;
}

/// Global singleton clipboard service shared across all browser tabs and
/// dual-pane split views so files copied in one tab or pane can be pasted
/// directly into another.
class BrowserClipboardService extends ChangeNotifier {
  static final BrowserClipboardService instance = BrowserClipboardService._();
  BrowserClipboardService._();

  BrowserClipboardSnapshot? _snapshot;

  BrowserClipboardSnapshot? get snapshot => _snapshot;
  bool get hasItems => _snapshot != null && _snapshot!.paths.isNotEmpty;

  void setCopy(String sourceRoot, Iterable<String> paths) {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return;
    _snapshot = BrowserClipboardSnapshot(
      op: ClipboardOp.copy,
      sourceRoot: sourceRoot,
      paths: list,
    );
    notifyListeners();
  }

  void setCut(String sourceRoot, Iterable<String> paths) {
    final list = paths.toList(growable: false);
    if (list.isEmpty) return;
    _snapshot = BrowserClipboardSnapshot(
      op: ClipboardOp.cut,
      sourceRoot: sourceRoot,
      paths: list,
    );
    notifyListeners();
  }

  void clear() {
    if (_snapshot == null) return;
    _snapshot = null;
    notifyListeners();
  }
}
