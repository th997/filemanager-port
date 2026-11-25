import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/inspect.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';
import 'category_files_page.dart';

/// Visual storage space analyzer showing disk capacity, folder size ranking,
/// file-type breakdown, and Top N largest files with drill-down & cleanup.
class StorageAnalyzerPage extends StatefulWidget {
  final String root;
  final String initialPath;
  final String title;

  const StorageAnalyzerPage({
    super.key,
    required this.root,
    this.initialPath = '',
    required this.title,
  });

  @override
  State<StorageAnalyzerPage> createState() => _StorageAnalyzerPageState();
}

class _StorageAnalyzerPageState extends State<StorageAnalyzerPage> {
  late String _relPath;
  StorageAnalysisDto? _analysis;
  DiskSpaceDto? _diskSpace;
  bool _loading = true;
  String? _error;
  String? _activeOpId;

  static const _categoryColors = <String, Color>{
    'video': Color(0xFFE53935),
    'image': Color(0xFF43A047),
    'audio': Color(0xFF8E24AA),
    'document': Color(0xFF1E88E5),
    'archive': Color(0xFFFB8C00),
    'apk': Color(0xFF00ACC1),
    'code': Color(0xFF3949AB),
    'other': Color(0xFF757575),
  };

  @override
  void initState() {
    super.initState();
    _relPath = widget.initialPath;
    _runAnalysis();
  }

  @override
  void dispose() {
    final op = _activeOpId;
    if (op != null) {
      cancelInspectOp(opId: op);
    }
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    final prev = _activeOpId;
    if (prev != null) cancelInspectOp(opId: prev);
    final opId = 'analyze_${DateTime.now().microsecondsSinceEpoch}';
    _activeOpId = opId;

    setState(() {
      _loading = true;
      _error = null;
    });

    DiskSpaceDto? disk;
    if (isNativeRoot(widget.root)) {
      try {
        final target = _relPath.isEmpty ? widget.root : joinNative(widget.root, _relPath);
        disk = getDiskSpace(path: target);
      } catch (_) {}
    }

    try {
      final result = await analyzeStorage(
        root: widget.root,
        path: _relPath,
        topN: 30,
        opId: opId,
      );
      if (!mounted || _activeOpId != opId) return;
      setState(() {
        _diskSpace = disk;
        _analysis = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || _activeOpId != opId) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteFile(StorageFileRankDto file) async {
    final l10n = AppLocalizations.of(context);
    final native = isNativeRoot(widget.root);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteSingleConfirmTitle(file.name)),
        content: Text(
          native ? l10n.deleteChoiceTrashOrPermanent : l10n.deleteRemotePermanentWarning,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (native) {
        await StorageService.instance.moveToTrash(
          joinNative(widget.root, file.path),
        );
      } else {
        await fm_api.removeEntry(root: widget.root, path: file.path);
      }
      if (mounted) {
        unawaited(_runAnalysis());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openRankedFile(StorageFileRankDto f) async {
    try {
      await FileOpenService.instance.openWith(widget.root, f.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  void _openCategoryFiles(String category) {
    final targetRoot =
        _relPath.isEmpty || !isNativeRoot(widget.root) ? widget.root : joinNative(widget.root, _relPath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryFilesPage(
          category: category,
          root: targetRoot,
        ),
      ),
    );
  }

  void _openInBrowser(String relPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: widget.root,
          initialPath: relPath,
        ),
      ),
    );
  }

  String _categoryLabel(String cat, AppLocalizations l10n) {
    switch (cat) {
      case 'video':
        return l10n.categoryVideos;
      case 'image':
        return l10n.gallery;
      case 'audio':
        return l10n.categoryAudio;
      case 'document':
        return l10n.categoryDocuments;
      case 'archive':
        return l10n.categoryArchives;
      case 'apk':
        return l10n.categoryApks;
      default:
        return cat.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final analysis = _analysis;

    return AppSwipeBack(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.storageAnalyzer),
                Text(
                  _relPath.isEmpty ? widget.title : '${widget.title}/$_relPath',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              if (_relPath.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: l10n.parentFolderTooltip,
                  onPressed: () {
                    final parts = _relPath.split('/').where((s) => s.isNotEmpty).toList();
                    if (parts.isNotEmpty) parts.removeLast();
                    setState(() => _relPath = parts.join('/'));
                    unawaited(_runAnalysis());
                  },
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.refresh,
                onPressed: _runAnalysis,
              ),
            ],
            bottom: TabBar(
              tabs: [
                Tab(text: l10n.topFolders),
                Tab(text: l10n.fileTypesBreakdown),
                Tab(text: l10n.topFiles),
              ],
            ),
          ),
          body: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          final op = _activeOpId;
                          if (op != null) cancelInspectOp(opId: op);
                        },
                        child: Text(l10n.cancel),
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: scheme.error)))
                  : analysis == null
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            if (analysis.cancelled || analysis.truncated)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                color: scheme.warning.withValues(alpha: 0.14),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 18,
                                      color: scheme.warning,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        analysis.cancelled
                                            ? l10n.analyzerScanCancelled
                                            : l10n.analyzerScanTruncated,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _runAnalysis,
                                      child: Text(l10n.analyzerRescan),
                                    ),
                                  ],
                                ),
                              ),
                            _buildSummaryHeader(context, analysis, l10n),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildFoldersTab(analysis),
                                  _buildCategoriesTab(analysis, l10n),
                                  _buildFilesTab(analysis),
                                ],
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader(
    BuildContext context,
    StorageAnalysisDto analysis,
    AppLocalizations l10n,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final disk = _diskSpace;
    final totalDouble = analysis.totalBytes.toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                formatBytes(analysis.totalBytes),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.analyzerStatsSummary(
                  analysis.totalFiles.toInt(),
                  analysis.totalDirs.toInt(),
                ),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (disk != null && disk.totalBytes > BigInt.zero) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: (disk.usedBytes.toDouble() / disk.totalBytes.toDouble()).clamp(0.0, 1.0),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.storageUsedOf(
                formatBytes(disk.usedBytes),
                formatBytes(disk.totalBytes),
                formatBytes(disk.availableBytes),
              ),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
          if (analysis.categories.isNotEmpty && totalDouble > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: analysis.categories.map((cat) {
                    final flex = ((cat.sizeBytes.toDouble() / totalDouble) * 1000).round().clamp(1, 1000);
                    return Expanded(
                      flex: flex,
                      child: Container(
                        color: _categoryColors[cat.category] ?? Colors.grey,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoldersTab(StorageAnalysisDto analysis) {
    final total = analysis.totalBytes.toDouble();
    if (analysis.folders.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).directoryIsEmpty));
    }
    return ListView.separated(
      itemCount: analysis.folders.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final f = analysis.folders[i];
        final ratio = total > 0 ? (f.sizeBytes.toDouble() / total).clamp(0.0, 1.0) : 0.0;
        return ListTile(
          leading: const Icon(Icons.folder, color: Colors.amber),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: ratio, minHeight: 5),
              ),
              const SizedBox(height: 2),
              Text('${f.fileCount} files · ${(ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatBytes(f.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: AppLocalizations.of(context).open,
                onPressed: () => _openInBrowser(f.path),
              ),
            ],
          ),
          onTap: () {
            setState(() => _relPath = f.path);
            unawaited(_runAnalysis());
          },
        );
      },
    );
  }

  Widget _buildCategoriesTab(StorageAnalysisDto analysis, AppLocalizations l10n) {
    final total = analysis.totalBytes.toDouble();
    return ListView.separated(
      itemCount: analysis.categories.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = analysis.categories[i];
        final ratio = total > 0 ? (c.sizeBytes.toDouble() / total).clamp(0.0, 1.0) : 0.0;
        final color = _categoryColors[c.category] ?? Colors.grey;
        return ListTile(
          leading: CircleAvatar(radius: 8, backgroundColor: color),
          title: Text(_categoryLabel(c.category, l10n)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text('${c.fileCount} files · ${(ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 11)),
            ],
          ),
          trailing: Text(formatBytes(c.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w600)),
          onTap: () => _openCategoryFiles(c.category),
        );
      },
    );
  }

  Widget _buildFilesTab(StorageAnalysisDto analysis) {
    if (analysis.largestFiles.isEmpty) {
      return Center(child: Text(AppLocalizations.of(context).directoryIsEmpty));
    }
    return ListView.separated(
      itemCount: analysis.largestFiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final f = analysis.largestFiles[i];
        final parent = f.path.contains('/') ? f.path.substring(0, f.path.lastIndexOf('/')) : '';
        return ListTile(
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatBytes(f.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 18),
                  tooltip: AppLocalizations.of(context).locateInFolder,
                  onPressed: () => _openInBrowser(parent),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                  tooltip: AppLocalizations.of(context).delete,
                  onPressed: () => _deleteFile(f),
                ),
              ],
            ),
            onTap: () => _openRankedFile(f),
          );
      },
    );
  }
}
