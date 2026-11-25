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

/// 3-stage SHA-256 duplicate file finder & cleanup page.
class DuplicateFinderPage extends StatefulWidget {
  final String root;
  final String initialPath;
  final String title;

  const DuplicateFinderPage({
    super.key,
    required this.root,
    this.initialPath = '',
    required this.title,
  });

  @override
  State<DuplicateFinderPage> createState() => _DuplicateFinderPageState();
}

class _DuplicateFinderPageState extends State<DuplicateFinderPage> {
  DuplicateScanResultDto? _result;
  bool _scanning = true;
  bool _cleaning = false;
  String? _error;
  String? _activeOpId;
  final Set<String> _selectedToDelete = {};

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    final op = _activeOpId;
    if (op != null) cancelInspectOp(opId: op);
    super.dispose();
  }

  Future<void> _scan() async {
    final prev = _activeOpId;
    if (prev != null) cancelInspectOp(opId: prev);
    final opId = 'dup_${DateTime.now().microsecondsSinceEpoch}';
    _activeOpId = opId;

    setState(() {
      _scanning = true;
      _error = null;
      _selectedToDelete.clear();
    });

    try {
      final res = await findDuplicateFiles(
        root: widget.root,
        path: widget.initialPath,
        minSize: BigInt.one,
        opId: opId,
      );
      if (!mounted || _activeOpId != opId) return;
      setState(() {
        _result = res;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted || _activeOpId != opId) return;
      setState(() {
        _error = '$e';
        _scanning = false;
      });
    }
  }

  void _selectRule(String rule) {
    final groups = _result?.groups ?? const [];
    final toDelete = <String>{};
    for (final g in groups) {
      if (g.files.length < 2) continue;
      final sorted = List<DuplicateFileItemDto>.from(g.files);
      switch (rule) {
        case 'newest':
          sorted.sort((a, b) => (b.modifiedMillis ?? 0).compareTo(a.modifiedMillis ?? 0));
          break;
        case 'oldest':
          sorted.sort((a, b) => (a.modifiedMillis ?? 0).compareTo(b.modifiedMillis ?? 0));
          break;
        case 'shortest':
          sorted.sort((a, b) => a.path.length.compareTo(b.path.length));
          break;
      }
      // Keep the first file; mark all remaining copies for cleanup.
      for (int i = 1; i < sorted.length; i++) {
        toDelete.add(sorted[i].path);
      }
    }
    setState(() {
      _selectedToDelete
        ..clear()
        ..addAll(toDelete);
    });
  }

  String _formatModified(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCopy(DuplicateFileItemDto f) async {
    try {
      await FileOpenService.instance.openWith(widget.root, f.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _locateCopy(DuplicateFileItemDto f) {
    final parent =
        f.path.contains('/') ? f.path.substring(0, f.path.lastIndexOf('/')) : '';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: widget.root,
          initialPath: parent,
        ),
      ),
    );
  }

  Future<void> _cleanSelected() async {
    if (_selectedToDelete.isEmpty || _cleaning) return;
    final l10n = AppLocalizations.of(context);
    final count = _selectedToDelete.length;
    final allSelectedGroups = (_result?.groups ?? const [])
        .where(
          (g) =>
              g.files.isNotEmpty &&
              g.files.every((f) => _selectedToDelete.contains(f.path)),
        )
        .length;
    final baseBody = isNativeRoot(widget.root)
        ? l10n.duplicatesTrashConfirmBody(count)
        : l10n.deleteRemotePermanentWarning;
    final bodyText = allSelectedGroups > 0
        ? '${l10n.duplicatesAllCopiesWarning(allSelectedGroups)}\n\n$baseBody'
        : baseBody;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteMultipleConfirmTitle(count)),
        content: Text(bodyText),
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
    if (confirmed != true || !mounted) return;

    setState(() => _cleaning = true);
    int failed = 0;
    for (final rel in _selectedToDelete.toList()) {
      try {
        if (isNativeRoot(widget.root)) {
          await StorageService.instance.moveToTrash(
            joinNative(widget.root, rel),
          );
        } else {
          await fm_api.removeEntry(root: widget.root, path: rel);
        }
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _cleaning = false);
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.duplicatesDeleteFailed(failed))),
      );
    }
    unawaited(_scan());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final res = _result;
    final allSelectedGroups = res == null
        ? 0
        : res.groups
            .where(
              (g) =>
                  g.files.isNotEmpty &&
                  g.files.every((f) => _selectedToDelete.contains(f.path)),
            )
            .length;

    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.duplicateFinder),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: _scanning ? null : _scan,
            ),
          ],
        ),
        body: _scanning
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
                : res == null || res.groups.isEmpty
                    ? AppEmptyState(
                        icon: res?.cancelled == true
                            ? Icons.cancel_outlined
                            : Icons.find_replace,
                        title: res?.cancelled == true
                            ? l10n.duplicatesScanCancelled
                            : l10n.noDuplicatesFound,
                        action: res?.cancelled == true
                            ? FilledButton.tonal(
                                onPressed: _scan,
                                child: Text(l10n.analyzerRescan),
                              )
                            : null,
                      )
                    : Column(
                        children: [
                          if (res.cancelled)
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
                                      l10n.duplicatesScanCancelled,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _scan,
                                    child: Text(l10n.analyzerRescan),
                                  ),
                                ],
                              ),
                            ),
                          if (allSelectedGroups > 0)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              color: scheme.errorContainer,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: scheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.duplicatesAllCopiesWarning(
                                        allSelectedGroups,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            color: scheme.surfaceContainerLow,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${l10n.duplicatesGroupCount(res.groups.length)} · ${l10n.wastedSpace(formatBytes(res.wastedBytes))}',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    FilledButton.tonalIcon(
                                      icon: _cleaning
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.cleaning_services, size: 16),
                                      label: Text(
                                        l10n.cleanSelectedDuplicates(_selectedToDelete.length),
                                      ),
                                      onPressed: _selectedToDelete.isEmpty || _cleaning
                                          ? null
                                          : _cleanSelected,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    ActionChip(
                                      label: Text(l10n.keepNewest),
                                      onPressed: () => _selectRule('newest'),
                                    ),
                                    ActionChip(
                                      label: Text(l10n.keepOldest),
                                      onPressed: () => _selectRule('oldest'),
                                    ),
                                    ActionChip(
                                      label: Text(l10n.keepShortestPath),
                                      onPressed: () => _selectRule('shortest'),
                                    ),
                                    if (_selectedToDelete.isNotEmpty)
                                      ActionChip(
                                        label: Text(l10n.duplicatesClearSelection),
                                        onPressed: () => setState(
                                          () => _selectedToDelete.clear(),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(10),
                              itemCount: res.groups.length,
                              itemBuilder: (_, idx) {
                                final g = res.groups[idx];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ExpansionTile(
                                    initiallyExpanded: idx < 5,
                                    title: Text(
                                      '${g.files.first.name} ${l10n.duplicatesCopiesCount(g.files.length)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${l10n.duplicatesEachSize(formatBytes(g.sizeBytes))} · SHA-256: ${g.sha256.substring(0, 12)}…',
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                    children: g.files.map((f) {
                                      final checked = _selectedToDelete.contains(f.path);
                                      return CheckboxListTile(
                                        dense: true,
                                        value: checked,
                                        title: Text(
                                          f.path,
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: f.modifiedMillis != null
                                            ? Text(
                                                _formatModified(f.modifiedMillis!.toInt()),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                              )
                                            : null,
                                        secondary: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.open_in_new, size: 17),
                                              tooltip: l10n.open,
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _openCopy(f),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.folder_open, size: 17),
                                              tooltip: l10n.locateInFolder,
                                              visualDensity: VisualDensity.compact,
                                              onPressed: () => _locateCopy(f),
                                            ),
                                          ],
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedToDelete.add(f.path);
                                            } else {
                                              _selectedToDelete.remove(f.path);
                                            }
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
