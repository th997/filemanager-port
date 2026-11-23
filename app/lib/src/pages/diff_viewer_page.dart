import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/file_manager.dart';
import '../rust/api/sync.dart';
import '../services/task_service.dart';

enum DiffOp { equal, insert, delete }

class DiffLine {
  final DiffOp op;
  final int? leftLine;
  final int? rightLine;
  final String text;

  const DiffLine({
    required this.op,
    this.leftLine,
    this.rightLine,
    required this.text,
  });
}

/// Pure-Dart LCS line diff engine.
class DiffEngine {
  static List<DiffLine> diffLines(String leftText, String rightText) {
    final a = leftText.split(RegExp(r'\r?\n'));
    final b = rightText.split(RegExp(r'\r?\n'));
    final n = a.length;
    final m = b.length;

    // Guard memory for huge files (> 3000 lines): trim common prefix/suffix first.
    int prefix = 0;
    while (prefix < n && prefix < m && a[prefix] == b[prefix]) {
      prefix++;
    }
    int suffix = 0;
    while (suffix < (n - prefix) &&
        suffix < (m - prefix) &&
        a[n - 1 - suffix] == b[m - 1 - suffix]) {
      suffix++;
    }

    final out = <DiffLine>[];
    for (int i = 0; i < prefix; i++) {
      out.add(DiffLine(op: DiffOp.equal, leftLine: i + 1, rightLine: i + 1, text: a[i]));
    }

    final midA = a.sublist(prefix, n - suffix);
    final midB = b.sublist(prefix, m - suffix);
    final ma = midA.length;
    final mb = midB.length;

    if (ma * mb <= 2500000) {
      final dp = List.generate(ma + 1, (_) => List<int>.filled(mb + 1, 0));
      for (int i = ma - 1; i >= 0; i--) {
        for (int j = mb - 1; j >= 0; j--) {
          if (midA[i] == midB[j]) {
            dp[i][j] = dp[i + 1][j + 1] + 1;
          } else {
            dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
          }
        }
      }
      int i = 0;
      int j = 0;
      while (i < ma && j < mb) {
        if (midA[i] == midB[j]) {
          out.add(DiffLine(
            op: DiffOp.equal,
            leftLine: prefix + i + 1,
            rightLine: prefix + j + 1,
            text: midA[i],
          ));
          i++;
          j++;
        } else if (dp[i + 1][j] >= dp[i][j + 1]) {
          out.add(DiffLine(op: DiffOp.delete, leftLine: prefix + i + 1, text: midA[i]));
          i++;
        } else {
          out.add(DiffLine(op: DiffOp.insert, rightLine: prefix + j + 1, text: midB[j]));
          j++;
        }
      }
      while (i < ma) {
        out.add(DiffLine(op: DiffOp.delete, leftLine: prefix + i + 1, text: midA[i]));
        i++;
      }
      while (j < mb) {
        out.add(DiffLine(op: DiffOp.insert, rightLine: prefix + j + 1, text: midB[j]));
        j++;
      }
    } else {
      // Linear fallback for extremely large diffs.
      for (int i = 0; i < ma; i++) {
        out.add(DiffLine(op: DiffOp.delete, leftLine: prefix + i + 1, text: midA[i]));
      }
      for (int j = 0; j < mb; j++) {
        out.add(DiffLine(op: DiffOp.insert, rightLine: prefix + j + 1, text: midB[j]));
      }
    }

    for (int k = 0; k < suffix; k++) {
      final li = n - suffix + k;
      final ri = m - suffix + k;
      out.add(DiffLine(op: DiffOp.equal, leftLine: li + 1, rightLine: ri + 1, text: a[li]));
    }
    return out;
  }
}

/// Text file & directory Diff viewer supporting unified and side-by-side modes.
class DiffViewerPage extends StatefulWidget {
  final bool isDirectory;
  final String leftRoot;
  final String leftPath;
  final String leftLabel;
  final String rightRoot;
  final String rightPath;
  final String rightLabel;

  const DiffViewerPage({
    super.key,
    required this.isDirectory,
    required this.leftRoot,
    required this.leftPath,
    required this.leftLabel,
    required this.rightRoot,
    required this.rightPath,
    required this.rightLabel,
  });

  @override
  State<DiffViewerPage> createState() => _DiffViewerPageState();
}

class _DiffViewerPageState extends State<DiffViewerPage> {
  bool _loading = true;
  String? _error;
  bool _sideBySide = false;
  List<DiffLine> _lines = const [];
  int _addedCount = 0;
  int _removedCount = 0;
  SyncPlanDto? _dirDiff;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.isDirectory) {
        final plan = await previewDirectorySync(
          srcRoot: widget.leftRoot,
          srcPath: widget.leftPath,
          dstRoot: widget.rightRoot,
          dstPath: widget.rightPath,
          mode: 'mirror',
        );
        if (!mounted) return;
        setState(() {
          _dirDiff = plan;
          _loading = false;
        });
      } else {
        final left = await readTextFile(root: widget.leftRoot, path: widget.leftPath);
        final right = await readTextFile(root: widget.rightRoot, path: widget.rightPath);
        final diff = DiffEngine.diffLines(left, right);
        int added = 0;
        int removed = 0;
        for (final l in diff) {
          if (l.op == DiffOp.insert) added++;
          if (l.op == DiffOp.delete) removed++;
        }
        if (!mounted) return;
        setState(() {
          _lines = diff;
          _addedCount = added;
          _removedCount = removed;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.compareDiff),
            Text(
              '${widget.leftLabel} ↔ ${widget.rightLabel}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (!widget.isDirectory)
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.diffUnified)),
                ButtonSegment(value: true, label: Text(l10n.diffSideBySide)),
              ],
              selected: {_sideBySide},
              onSelectionChanged: (s) => setState(() => _sideBySide = s.first),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
              : widget.isDirectory
                  ? _buildDirDiff(l10n)
                  : _buildTextDiff(l10n),
    );
  }

  Widget _buildTextDiff(AppLocalizations l10n) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Text('+$_addedCount', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Text('-$_removedCount', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              if (_addedCount == 0 && _removedCount == 0)
                Text(l10n.diffIdentical, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _lines.length,
            itemBuilder: (_, i) {
              final line = _lines[i];
              final isDark = Theme.of(context).brightness == Brightness.dark;
              Color? bg;
              String prefix = ' ';
              if (line.op == DiffOp.insert) {
                bg = isDark ? Colors.green.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.12);
                prefix = '+';
              } else if (line.op == DiffOp.delete) {
                bg = isDark ? Colors.red.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.12);
                prefix = '-';
              }
              if (_sideBySide) {
                return Container(
                  color: bg,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          line.op == DiffOp.insert
                              ? ''
                              : '${(line.leftLine ?? '').toString().padLeft(4)}  ${line.text}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                      const VerticalDivider(width: 12),
                      Expanded(
                        child: Text(
                          line.op == DiffOp.delete
                              ? ''
                              : '${(line.rightLine ?? '').toString().padLeft(4)}  ${line.text}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Container(
                color: bg,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  '${(line.leftLine?.toString() ?? '').padLeft(4)} ${(line.rightLine?.toString() ?? '').padLeft(4)} $prefix ${line.text}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDirDiff(AppLocalizations l10n) {
    final plan = _dirDiff;
    if (plan == null || plan.items.isEmpty) {
      return Center(child: Text(l10n.diffIdentical));
    }
    return ListView.separated(
      itemCount: plan.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = plan.items[i];
        final (IconData icon, Color color, String badge) = switch (item.action) {
          'add' => (Icons.arrow_forward, Colors.green, l10n.diffOnlyInLeft),
          'delete' => (Icons.arrow_back, Colors.orange, l10n.diffOnlyInRight),
          _ => (Icons.difference, Colors.blue, l10n.diffModified),
        };
        final sz = item.srcSize != null
            ? formatBytes(item.srcSize!)
            : (item.dstSize != null ? formatBytes(item.dstSize!) : '');
        return ListTile(
          dense: true,
          leading: Icon(icon, color: color, size: 18),
          title: Text(item.relPath, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$badge · $sz', style: const TextStyle(fontSize: 11)),
        );
      },
    );
  }
}
