import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/inspect.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/platform_capabilities.dart';
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
  @visibleForTesting
  final StorageAnalysisDto? initialAnalysisOverride;
  @visibleForTesting
  final Future<void> Function(List<String> paths)? onBatchDeleteOverride;

  const StorageAnalyzerPage({
    super.key,
    required this.root,
    this.initialPath = '',
    required this.title,
    this.initialAnalysisOverride,
    this.onBatchDeleteOverride,
  });

  /// Normalizes a relative VFS path by stripping leading, trailing, and
  /// duplicate slashes (`"/Docs/"` -> `"Docs"`, `"/"` -> `""`).
  static String normalizeRelPath(String raw) {
    return raw.split('/').where((s) => s.isNotEmpty).join('/');
  }

  /// Formats the human-readable path shown under the Storage Analyzer AppBar
  /// without duplicating the relative path or introducing double slashes (`//`).
  static String formatDisplayPath({
    required String root,
    required String title,
    required String relPath,
  }) {
    final cleanRel = normalizeRelPath(relPath);
    final cleanTitle = title.trim();
    if (isNativeRoot(root)) {
      final looksLikePath = cleanTitle.isEmpty ||
          cleanTitle == root ||
          cleanTitle.startsWith('/') ||
          isNativeRoot(cleanTitle);
      if (looksLikePath) {
        final base = cleanTitle.isEmpty ? root : cleanTitle;
        return cleanRel.isEmpty ? base : joinNative(base, cleanRel);
      }
      return cleanRel.isEmpty ? cleanTitle : '$cleanTitle/$cleanRel';
    }
    var base = cleanTitle.isNotEmpty ? cleanTitle : root;
    while (base.endsWith('/') && base != '/' && !base.endsWith('://')) {
      base = base.substring(0, base.length - 1);
    }
    if (cleanRel.isEmpty) return base;
    return base.endsWith('://') ? '$base$cleanRel' : '$base/$cleanRel';
  }

  @override
  State<StorageAnalyzerPage> createState() => _StorageAnalyzerPageState();
}

class _StorageAnalyzerPageState extends State<StorageAnalyzerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String _relPath;
  StorageAnalysisDto? _analysis;
  DiskSpaceDto? _diskSpace;
  bool _loading = true;
  String? _error;
  String? _activeOpId;
  bool _selectionMode = false;
  final Set<String> _selectedFilePaths = <String>{};

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
    _relPath = StorageAnalyzerPage.normalizeRelPath(widget.initialPath);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    final override = widget.initialAnalysisOverride;
    if (override != null) {
      _analysis = override;
      _loading = false;
    } else {
      _runAnalysis();
    }
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {
      if (_tabController.index != 2) {
        _selectionMode = false;
        _selectedFilePaths.clear();
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
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
      _selectionMode = false;
      _selectedFilePaths.clear();
    });

    if (widget.initialAnalysisOverride != null) {
      setState(() => _loading = false);
      return;
    }

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
          initialPath: StorageAnalyzerPage.normalizeRelPath(relPath),
        ),
      ),
    );
  }

  void _toggleSelectionMode([bool? enabled]) {
    setState(() {
      final next = enabled ?? !_selectionMode;
      _selectionMode = next;
      if (!next) {
        _selectedFilePaths.clear();
      }
    });
  }

  void _enterSelectionWith(String path) {
    setState(() {
      _selectionMode = true;
      _selectedFilePaths.add(path);
    });
  }

  void _toggleFileSelected(String path) {
    setState(() {
      if (!_selectedFilePaths.remove(path)) {
        _selectedFilePaths.add(path);
      }
    });
  }

  void _applyLocalDeletionResult(Set<String> deletedPaths, BigInt freedBytes) {
    final cur = _analysis;
    setState(() {
      if (cur != null && deletedPaths.isNotEmpty) {
        final remaining = cur.largestFiles
            .where((f) => !deletedPaths.contains(f.path))
            .toList();
        final deletedCount = BigInt.from(deletedPaths.length);
        _analysis = StorageAnalysisDto(
          totalBytes:
              cur.totalBytes > freedBytes ? cur.totalBytes - freedBytes : BigInt.zero,
          totalFiles:
              cur.totalFiles >= deletedCount ? cur.totalFiles - deletedCount : BigInt.zero,
          totalDirs: cur.totalDirs,
          truncated: cur.truncated,
          cancelled: cur.cancelled,
          folders: cur.folders,
          largestFiles: remaining,
          categories: cur.categories,
        );
      }
      _selectionMode = false;
      _selectedFilePaths.clear();
    });
  }

  Future<void> _batchMoveOrCopy({required bool isMove}) async {
    final paths = _selectedFilePaths.toList();
    if (paths.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final dest = await FolderPickerDialog.show(
      context,
      title: isMove ? l10n.taskMove : l10n.copy,
      initialRoot: widget.root,
      initialPath: _relPath,
    );
    if (dest == null || !mounted) return;
    try {
      final normalizedPaths = paths.map(StorageAnalyzerPage.normalizeRelPath).toList();
      Future<String> startTask() => isMove
          ? TaskService.instance.move(
              srcRoot: widget.root,
              srcPaths: normalizedPaths,
              dstRoot: dest.root,
              dstDir: dest.relPath,
              conflictPolicy: 'rename',
            )
          : TaskService.instance.copy(
              srcRoot: widget.root,
              srcPaths: normalizedPaths,
              dstRoot: dest.root,
              dstDir: dest.relPath,
              conflictPolicy: 'rename',
            );
      final taskId = await startTask();
      if (!mounted) return;
      final completed = await TaskProgressDialog.show(
        context,
        taskId,
        isMove ? l10n.movingFiles : l10n.copyingFiles,
        onRetry: startTask,
      );
      if (!mounted) return;
      _toggleSelectionMode(false);
      if (completed == true && isMove) {
        unawaited(_runAnalysis());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isMove ? l10n.moveFailed('$e') : l10n.copyFailed('$e')),
          ),
        );
      }
    }
  }

  Future<void> _batchShareSelected() async {
    if (!isNativeRoot(widget.root) || !PlatformCapabilities.supportsNativeShareSheet) {
      return;
    }
    final paths = _selectedFilePaths.toList();
    if (paths.isEmpty) return;
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize && !box.size.isEmpty
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      final xfiles = paths.map((p) => XFile(joinNative(widget.root, p))).toList();
      await SharePlus.instance.share(
        ShareParams(files: xfiles, sharePositionOrigin: origin),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).cannotShareFile('$e'))),
        );
      }
    }
  }

  Future<void> _batchDeleteSelected() async {
    final analysis = _analysis;
    final selected = _selectedFilePaths.toList();
    if (analysis == null || selected.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final native = isNativeRoot(widget.root);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.analyzerBatchDeleteConfirmTitle(selected.length)),
        content: Text(
          native ? l10n.deleteChoiceTrashOrPermanent : l10n.deleteRemotePermanentWarning,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final sizeByPath = <String, BigInt>{
      for (final f in analysis.largestFiles) f.path: f.sizeBytes,
    };

    if (widget.onBatchDeleteOverride != null) {
      try {
        await widget.onBatchDeleteOverride!(selected);
        if (!mounted) return;
        var freed = BigInt.zero;
        for (final p in selected) {
          freed += sizeByPath[p] ?? BigInt.zero;
        }
        _applyLocalDeletionResult(selected.toSet(), freed);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.analyzerBatchDeleteDone(selected.length, formatBytes(freed))),
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
      return;
    }

    var deleted = 0;
    var failed = 0;
    var freed = BigInt.zero;
    final deletedPaths = <String>{};
    for (final path in selected) {
      try {
        if (native) {
          await StorageService.instance.moveToTrash(joinNative(widget.root, path));
        } else {
          await fm_api.removeEntry(
            root: widget.root,
            path: StorageAnalyzerPage.normalizeRelPath(path),
          );
        }
        deleted++;
        deletedPaths.add(path);
        freed += sizeByPath[path] ?? BigInt.zero;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    _applyLocalDeletionResult(deletedPaths, freed);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? l10n.analyzerBatchDeleteDone(deleted, formatBytes(freed))
              : l10n.analyzerBatchDeletePartial(deleted, failed),
        ),
      ),
    );
    if (widget.initialAnalysisOverride == null) {
      unawaited(_runAnalysis());
    }
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

    final files = analysis?.largestFiles ?? const <StorageFileRankDto>[];
    final allSelected = files.isNotEmpty && _selectedFilePaths.length == files.length;
    var selectedBytes = BigInt.zero;
    if (_selectionMode && _selectedFilePaths.isNotEmpty) {
      for (final f in files) {
        if (_selectedFilePaths.contains(f.path)) {
          selectedBytes += f.sizeBytes;
        }
      }
    }

    return AppSwipeBack(
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.cancel,
                  onPressed: () => _toggleSelectionMode(false),
                ),
                title: Text(
                  l10n.analyzerSelectedCountAndSize(
                    _selectedFilePaths.length,
                    formatBytes(selectedBytes),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                    tooltip: allSelected ? l10n.deselectAll : l10n.selectAll,
                    onPressed: files.isEmpty
                        ? null
                        : () {
                            setState(() {
                              if (allSelected) {
                                _selectedFilePaths.clear();
                              } else {
                                _selectedFilePaths.addAll(files.map((f) => f.path));
                              }
                            });
                          },
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: l10n.topFolders),
                    Tab(text: l10n.fileTypesBreakdown),
                    Tab(text: l10n.topFiles),
                  ],
                ),
              )
            : AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.storageAnalyzer),
                    Text(
                      StorageAnalyzerPage.formatDisplayPath(
                        root: widget.root,
                        title: widget.title,
                        relPath: _relPath,
                      ),
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                actions: [
                  if (_tabController.index == 2 && files.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.checklist),
                      tooltip: l10n.analyzerMultiSelectTooltip,
                      onPressed: () => _toggleSelectionMode(true),
                    ),
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
                  controller: _tabController,
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
                                controller: _tabController,
                                children: [
                                  _buildFoldersTab(analysis),
                                  _buildCategoriesTab(analysis, l10n),
                                  _buildFilesTab(analysis),
                                ],
                              ),
                            ),
                          ],
                        ),
        bottomNavigationBar: _selectionMode && _tabController.index == 2
            ? _buildSelectionBottomBar(context, l10n, scheme)
            : null,
      ),
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme scheme,
  ) {
    final hasSelection = _selectedFilePaths.isNotEmpty;
    final canShare = isNativeRoot(widget.root) && PlatformCapabilities.supportsNativeShareSheet;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: _buildActionBarButton(
                  icon: Icons.drive_file_move_outlined,
                  label: l10n.taskMove,
                  onPressed: hasSelection ? () => _batchMoveOrCopy(isMove: true) : null,
                ),
              ),
              Expanded(
                child: _buildActionBarButton(
                  icon: Icons.file_copy_outlined,
                  label: l10n.copy,
                  onPressed: hasSelection ? () => _batchMoveOrCopy(isMove: false) : null,
                ),
              ),
              if (canShare)
                Expanded(
                  child: _buildActionBarButton(
                    icon: Icons.share_outlined,
                    label: l10n.share,
                    onPressed: hasSelection ? _batchShareSelected : null,
                  ),
                ),
              Expanded(
                child: _buildActionBarButton(
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  color: hasSelection ? scheme.error : null,
                  onPressed: hasSelection ? _batchDeleteSelected : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBarButton({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: onPressed == null
                  ? Theme.of(context).disabledColor
                  : (color ?? Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: onPressed == null
                    ? Theme.of(context).disabledColor
                    : (color ?? Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
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
            setState(() => _relPath = StorageAnalyzerPage.normalizeRelPath(f.path));
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
    final l10n = AppLocalizations.of(context);
    if (analysis.largestFiles.isEmpty) {
      return Center(child: Text(l10n.directoryIsEmpty));
    }
    return ListView.separated(
      itemCount: analysis.largestFiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final f = analysis.largestFiles[i];
        final cleanPath = StorageAnalyzerPage.normalizeRelPath(f.path);
        final slashIdx = cleanPath.lastIndexOf('/');
        final parentDir = slashIdx > 0 ? cleanPath.substring(0, slashIdx) : '';
        final subtitlePath = StorageAnalyzerPage.formatDisplayPath(
          root: widget.root,
          title: widget.title,
          relPath: parentDir,
        );
        final selected = _selectedFilePaths.contains(f.path);
        return ListTile(
          selected: _selectionMode && selected,
          leading: _selectionMode
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleFileSelected(f.path),
                )
              : const Icon(Icons.insert_drive_file_outlined),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            subtitlePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
          trailing: _selectionMode
              ? Text(formatBytes(f.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w600))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatBytes(f.sizeBytes), style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 18),
                      tooltip: l10n.locateInFolder,
                      onPressed: () => _openInBrowser(parentDir),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                      tooltip: l10n.delete,
                      onPressed: () => _deleteFile(f),
                    ),
                  ],
                ),
          onTap: _selectionMode
              ? () => _toggleFileSelected(f.path)
              : () => _openRankedFile(f),
          onLongPress: _selectionMode
              ? () => _toggleFileSelected(f.path)
              : () => _enterSelectionWith(f.path),
        );
      },
    );
  }
}
