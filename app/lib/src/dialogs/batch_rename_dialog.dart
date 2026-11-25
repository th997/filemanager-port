import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:filemanager/l10n/app_localizations.dart';

import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';

enum BatchRenameMode {
  prefixSuffix,
  findReplace,
  numbering,
}

enum BatchRenameOutcome {
  completed,
  partial,
  cancelled,
}

class RenameStep {
  final String from;
  final String to;

  const RenameStep(this.from, this.to);

  @override
  bool operator ==(Object other) =>
      other is RenameStep && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'RenameStep($from -> $to)';
}

enum BatchRenameValidationErrorKind {
  emptyName,
  invalidChars,
  duplicateTarget,
  targetExists,
}

class BatchRenameValidation {
  final BatchRenameValidationErrorKind? errorKind;
  final String? offendingName;
  final List<RenameStep> steps;
  final int changedCount;
  final Set<int> invalidIndices;

  const BatchRenameValidation({
    this.errorKind,
    this.offendingName,
    this.steps = const [],
    this.changedCount = 0,
    this.invalidIndices = const {},
  });

  bool get isValid => errorKind == null;

  String? localizedMessage(AppLocalizations l10n) {
    switch (errorKind) {
      case null:
        return null;
      case BatchRenameValidationErrorKind.emptyName:
        return l10n.batchRenameErrorEmpty;
      case BatchRenameValidationErrorKind.invalidChars:
        return l10n.invalidFileNameError;
      case BatchRenameValidationErrorKind.duplicateTarget:
        return l10n.batchRenameErrorDuplicate(offendingName ?? '');
      case BatchRenameValidationErrorKind.targetExists:
        return l10n.batchRenameErrorExists(offendingName ?? '');
    }
  }
}

class _PlannedEntry {
  final int index;
  final String oldPath;
  final String oldName;
  final String parent;
  final String newPath;
  final String newName;

  const _PlannedEntry({
    required this.index,
    required this.oldPath,
    required this.oldName,
    required this.parent,
    required this.newPath,
    required this.newName,
  });
}

class BatchRenameDialog extends StatefulWidget {
  final String root;
  final List<String> paths;
  final Set<String> dirPaths;
  final Set<String> existingSiblingNames;

  const BatchRenameDialog({
    super.key,
    required this.root,
    required this.paths,
    this.dirPaths = const {},
    this.existingSiblingNames = const {},
  });

  static Future<BatchRenameOutcome?> show(
    BuildContext context, {
    required String root,
    required List<String> paths,
    Set<String> dirPaths = const {},
    Set<String> existingSiblingNames = const {},
  }) {
    return showDialog<BatchRenameOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchRenameDialog(
        root: root,
        paths: paths,
        dirPaths: dirPaths,
        existingSiblingNames: existingSiblingNames,
      ),
    );
  }

  static String _joinPosix(String parent, String name) {
    if (parent == '.' || parent.isEmpty) return name;
    return p.posix.join(parent, name);
  }

  /// Validates target names and constructs an atomic-safe rename plan.
  ///
  /// When any item's destination matches another changing item's source path
  /// (e.g. `item_01 -> item_02`, `item_02 -> item_03`, or a swap), steps are
  /// emitted in two phases via unique temporary names so no file overwrites
  /// another during execution.
  static BatchRenameValidation planRenames({
    required List<String> paths,
    required List<String> newNames,
    Set<String> existingSiblingNames = const {},
    bool caseInsensitive = false,
  }) {
    assert(paths.length == newNames.length);
    String normKey(String value) => caseInsensitive ? value.toLowerCase() : value;
    final entries = <_PlannedEntry>[];
    final invalidIndices = <int>{};
    BatchRenameValidationErrorKind? firstError;
    String? offendingName;

    void recordError(BatchRenameValidationErrorKind kind, String? name, int idx) {
      invalidIndices.add(idx);
      if (firstError == null) {
        firstError = kind;
        offendingName = name;
      }
    }

    final seenTargetPaths = <String, int>{};

    for (int i = 0; i < paths.length; i++) {
      final oldPath = paths[i];
      final oldName = p.posix.basename(oldPath);
      final parent = p.posix.dirname(oldPath);
      final newName = newNames[i];
      final newPath = _joinPosix(parent, newName);

      if (newName.isEmpty) {
        recordError(BatchRenameValidationErrorKind.emptyName, null, i);
      } else if (!isValidFileName(newName)) {
        recordError(BatchRenameValidationErrorKind.invalidChars, newName, i);
      }

      if (newName.isNotEmpty) {
        final targetKey = normKey(newPath);
        final prevIdx = seenTargetPaths[targetKey];
        if (prevIdx != null) {
          invalidIndices.add(prevIdx);
          recordError(BatchRenameValidationErrorKind.duplicateTarget, newName, i);
        } else {
          seenTargetPaths[targetKey] = i;
        }
      }

      entries.add(_PlannedEntry(
        index: i,
        oldPath: oldPath,
        oldName: oldName,
        parent: parent,
        newPath: newPath,
        newName: newName,
      ));
    }

    final changing = entries.where((e) => e.newPath != e.oldPath).toList();
    final movingAwayOldPaths = {for (final e in changing) normKey(e.oldPath)};
    final existingNormNames = {for (final n in existingSiblingNames) normKey(n)};

    if (existingSiblingNames.isNotEmpty) {
      for (final e in changing) {
        if (e.newName.isNotEmpty &&
            existingNormNames.contains(normKey(e.newName)) &&
            !movingAwayOldPaths.contains(normKey(e.newPath))) {
          recordError(BatchRenameValidationErrorKind.targetExists, e.newName, e.index);
        }
      }
    }

    if (firstError != null) {
      return BatchRenameValidation(
        errorKind: firstError,
        offendingName: offendingName,
        changedCount: changing.length,
        invalidIndices: invalidIndices,
      );
    }

    if (changing.isEmpty) {
      return const BatchRenameValidation(steps: [], changedCount: 0);
    }

    // Include exact same-path case-only renames on case-insensitive FS? No, if oldKey == newKey (case change)
    // and only 1 file does it, `a.txt -> A.txt` conflicts against itself only if `oldKey == newKey`?
    // Wait: if file 0 renames `a.txt -> b.txt` while file 1 renames `B.txt -> c.txt`,
    // normKey(newPath) hits movingAwayOldPaths AND needs two-phase staging!
    final hasOverlap = changing.any((e) {
      final newKey = normKey(e.newPath);
      final oldKey = normKey(e.oldPath);
      if (newKey == oldKey) return false; // In-place case rename of same entry.
      return movingAwayOldPaths.contains(newKey);
    });
    if (!hasOverlap) {
      return BatchRenameValidation(
        steps: [for (final e in changing) RenameStep(e.oldPath, e.newPath)],
        changedCount: changing.length,
      );
    }

    // Two-phase rename via unique temporary names so shifting/swapping names
    // never overwrite one another on filesystems with replacing rename semantics.
    final forbiddenNames = <String>{
      for (final n in existingSiblingNames) normKey(n),
      for (final e in entries) normKey(e.oldName),
      for (final e in entries) normKey(e.newName),
    };

    int nonce = 0;
    while (true) {
      final candidateConflict = changing.any(
        (e) => forbiddenNames.contains(normKey('.__fm_br_${nonce}_${e.index}')),
      );
      if (!candidateConflict) break;
      nonce++;
    }

    final phase1 = <RenameStep>[];
    final phase2 = <RenameStep>[];
    for (final e in changing) {
      final tmpName = '.__fm_br_${nonce}_${e.index}';
      final tmpPath = _joinPosix(e.parent, tmpName);
      phase1.add(RenameStep(e.oldPath, tmpPath));
      phase2.add(RenameStep(tmpPath, e.newPath));
    }

    return BatchRenameValidation(
      steps: [...phase1, ...phase2],
      changedCount: changing.length,
    );
  }

  @override
  State<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<BatchRenameDialog> {
  BatchRenameMode _mode = BatchRenameMode.prefixSuffix;
  bool _keepExtension = true;

  // Prefix & Suffix
  final _prefixController = TextEditingController();
  final _suffixController = TextEditingController();

  // Find & Replace
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();

  // Numbering
  final _baseNameController = TextEditingController(text: 'item_');
  int _startNumber = 1;
  int _paddingDigits = 2;

  bool _isProcessing = false;
  bool _hasPartialFailure = false;
  int _processedCount = 0;
  int _totalSteps = 0;
  String? _errorMessage;

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _baseNameController.dispose();
    super.dispose();
  }

  String _computeNewName(String originalPath, int index) {
    final originalName = p.posix.basename(originalPath);
    final isDir = widget.dirPaths.contains(originalPath);
    final dot = originalName.lastIndexOf('.');
    final hasExt = !isDir && dot > 0 && !originalName.startsWith('.');
    final nameWithoutExt =
        hasExt && _keepExtension ? originalName.substring(0, dot) : originalName;
    final ext = hasExt && _keepExtension ? originalName.substring(dot) : '';

    String transformed;
    switch (_mode) {
      case BatchRenameMode.prefixSuffix:
        final prefix = _prefixController.text;
        final suffix = _suffixController.text;
        transformed = '$prefix$nameWithoutExt$suffix$ext';
        break;

      case BatchRenameMode.findReplace:
        final find = _findController.text;
        final replace = _replaceController.text;
        if (find.isEmpty) {
          transformed = originalName;
        } else {
          final replaced = nameWithoutExt.replaceAll(find, replace);
          transformed = '$replaced$ext';
        }
        break;

      case BatchRenameMode.numbering:
        final base = _baseNameController.text;
        final numVal = _startNumber + index;
        final numStr = numVal.toString().padLeft(_paddingDigits, '0');
        transformed = '$base$numStr$ext';
        break;
    }
    return transformed.trim();
  }

  Future<void> _executeBatchRename(BatchRenameValidation plan) async {
    if (!plan.isValid || plan.steps.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _totalSteps = plan.steps.length;
      _errorMessage = null;
    });

    final completed = <RenameStep>[];
    try {
      for (int i = 0; i < plan.steps.length; i++) {
        final step = plan.steps[i];
        await renameEntry(root: widget.root, from: step.from, to: step.to);
        completed.add(step);
        if (mounted) {
          setState(() => _processedCount = i + 1);
        }
      }

      if (mounted) {
        Navigator.of(context).pop(BatchRenameOutcome.completed);
      }
    } catch (e) {
      var rollbackFailed = false;
      for (final step in completed.reversed) {
        try {
          await renameEntry(root: widget.root, from: step.to, to: step.from);
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _hasPartialFailure = completed.isNotEmpty && rollbackFailed;
          _errorMessage = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final availHeight = math.max(
      260.0,
      media.size.height - media.viewInsets.bottom - 48,
    );
    final previewMaxHeight = math.min(240.0, math.max(96.0, availHeight * 0.34));
    final caseInsensitive =
        isNativeRoot(widget.root) && (Platform.isMacOS || Platform.isWindows);

    final computedNames = [
      for (int i = 0; i < widget.paths.length; i++)
        _computeNewName(widget.paths[i], i),
    ];
    final plan = BatchRenameDialog.planRenames(
      paths: widget.paths,
      newNames: computedNames,
      existingSiblingNames: widget.existingSiblingNames,
      caseInsensitive: caseInsensitive,
    );
    final validationMsg = plan.localizedMessage(l10n);

    return PopScope(
      canPop: !_isProcessing,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: math.min(680.0, availHeight),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.drive_file_rename_outline, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.batchRenameTitle(widget.paths.length),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.batchRenameSubtitle,
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Segmented Button for Mode
                SegmentedButton<BatchRenameMode>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: BatchRenameMode.prefixSuffix,
                      label: Text(
                        l10n.batchRenameModePrefixSuffix,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    ButtonSegment(
                      value: BatchRenameMode.findReplace,
                      label: Text(
                        l10n.batchRenameModeFindReplace,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    ButtonSegment(
                      value: BatchRenameMode.numbering,
                      label: Text(
                        l10n.batchRenameModeNumbering,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (_isProcessing || _hasPartialFailure)
                      ? null
                      : (val) {
                          setState(() => _mode = val.first);
                        },
                ),
                const SizedBox(height: 12),

                // Mode-specific inputs
                if (_mode == BatchRenameMode.prefixSuffix) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _prefixController,
                          enabled: !_isProcessing && !_hasPartialFailure,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenamePrefix,
                            hintText: l10n.batchRenamePrefixHint,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _suffixController,
                          enabled: !_isProcessing && !_hasPartialFailure,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenameSuffix,
                            hintText: l10n.batchRenameSuffixHint,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ] else if (_mode == BatchRenameMode.findReplace) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _findController,
                          enabled: !_isProcessing && !_hasPartialFailure,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenameFindText,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _replaceController,
                          enabled: !_isProcessing && !_hasPartialFailure,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenameReplaceWith,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ] else if (_mode == BatchRenameMode.numbering) ...[
                  TextField(
                    controller: _baseNameController,
                    enabled: !_isProcessing && !_hasPartialFailure,
                    decoration: InputDecoration(
                      labelText: l10n.batchRenameBaseName,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _startNumber,
                          isDense: true,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenameStartNumber,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('0')),
                            DropdownMenuItem(value: 1, child: Text('1')),
                            DropdownMenuItem(value: 10, child: Text('10')),
                          ],
                          onChanged: (_isProcessing || _hasPartialFailure)
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _startNumber = v);
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _paddingDigits,
                          isDense: true,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.batchRenamePaddingDigits,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 1,
                              child: Text(l10n.batchRenameDigitsOption(1, '1')),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text(l10n.batchRenameDigitsOption(2, '01')),
                            ),
                            DropdownMenuItem(
                              value: 3,
                              child: Text(l10n.batchRenameDigitsOption(3, '001')),
                            ),
                            DropdownMenuItem(
                              value: 4,
                              child: Text(l10n.batchRenameDigitsOption(4, '0001')),
                            ),
                          ],
                          onChanged: (_isProcessing || _hasPartialFailure)
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _paddingDigits = v);
                                },
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Keep extension checkbox
                Row(
                  children: [
                    Checkbox(
                      value: _keepExtension,
                      onChanged: (_isProcessing || _hasPartialFailure)
                          ? null
                          : (val) {
                              setState(() => _keepExtension = val ?? true);
                            },
                    ),
                    Expanded(
                      child: Text(
                        l10n.batchRenameKeepExtension,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),
                const Divider(),

                // Live Preview header
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.batchRenamePreview,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (plan.isValid && plan.changedCount == 0)
                        Text(
                          l10n.batchRenameNoChanges,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),

                // Live preview list
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: previewMaxHeight),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: plan.isValid
                            ? theme.dividerColor.withValues(alpha: 0.2)
                            : theme.colorScheme.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      itemCount: widget.paths.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final oldPath = widget.paths[i];
                        final oldName = p.posix.basename(oldPath);
                        final newName = computedNames[i];
                        final isModified = newName != oldName;
                        final isRowInvalid = plan.invalidIndices.contains(i);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  oldName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                              ),
                              Expanded(
                                child: Text(
                                  newName.isEmpty ? l10n.batchRenameEmptyName : newName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isRowInvalid
                                        ? theme.colorScheme.error
                                        : (isModified ? Colors.teal : Colors.grey),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                if (validationMsg != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationMsg,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ],

                const SizedBox(height: 14),

                // Actions
                if (_isProcessing)
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(l10n.batchRenameProgress(_processedCount, _totalSteps)),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          _hasPartialFailure
                              ? BatchRenameOutcome.partial
                              : BatchRenameOutcome.cancelled,
                        ),
                        child: Text(_hasPartialFailure ? l10n.close : l10n.cancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (_hasPartialFailure || !plan.isValid || plan.changedCount == 0)
                            ? null
                            : () => _executeBatchRename(plan),
                        child: Text(l10n.batchRenameApply(plan.changedCount)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
