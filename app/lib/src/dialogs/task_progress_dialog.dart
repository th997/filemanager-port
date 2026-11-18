import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../rust/api/tasks.dart';
import '../services/task_service.dart';

class TaskProgressDialog extends StatefulWidget {
  final String taskId;
  final String title;

  /// Restarts the operation from scratch and returns the new task id.
  /// When provided, a failed task offers Retry instead of only Close.
  final Future<String> Function()? onRetry;

  const TaskProgressDialog({
    super.key,
    required this.taskId,
    required this.title,
    this.onRetry,
  });

  /// Resolves to `true` only when the task completed; failures and
  /// cancellations resolve to `false` so callers can skip success messages.
  static Future<bool?> show(
    BuildContext context,
    String taskId,
    String title, {
    Future<String> Function()? onRetry,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TaskProgressDialog(
        taskId: taskId,
        title: title,
        onRetry: onRetry,
      ),
    );
  }

  @override
  State<TaskProgressDialog> createState() => _TaskProgressDialogState();
}

class _TaskProgressDialogState extends State<TaskProgressDialog> {
  StreamSubscription<TaskProgressDto>? _sub;
  TaskProgressDto? _latest;
  bool _dismissed = false;
  late String _taskId;
  SpeedEstimator _speed = SpeedEstimator();
  String? _retryError;

  void _pop(bool result) {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _sub?.cancel();
    Navigator.of(context).pop(result);
  }

  @override
  void initState() {
    super.initState();
    _taskId = widget.taskId;
    _subscribe();
  }

  void _subscribe() {
    _sub = TaskService.instance.watch(_taskId).listen(
      (p) {
        if (!mounted) return;
        _speed.add(p.completed);
        setState(() => _latest = p);
        if (p.state == 'completed') {
          _pop(true);
        }
        // Failures stay open so the reason is visible. A cancellation is the
        // user's own action, so close instead of asking them to dismiss it.
        if (p.state == 'cancelled') {
          _pop(false);
        }
      },
      // The task registry can drop a finished task before the terminal event
      // arrives; without this the dialog would stay open forever.
      // However, if the task failed, keep the dialog open so the user can inspect
      // the error and choose Retry or Close, instead of flashing and disappearing.
      onDone: () {
        if (_dismissed || !mounted) return;
        if (_latest?.state != 'failed' && _latest?.error == null) {
          _pop(false);
        }
      },
    );
  }

  /// Dismiss the dialog while the task keeps running on the Rust side.
  /// The task centre (Home → Tasks) remains as the way to watch or cancel
  /// it; until this button existed the modal dialog was a cage.
  void _background() {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    _pop(false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.switchedToBackground),
      ),
    );
  }

  Future<void> _retry() async {
    final start = widget.onRetry;
    if (start == null) return;
    try {
      final newId = await start();
      if (!mounted) return;
      _sub?.cancel();
      setState(() {
        _taskId = newId;
        _latest = null;
        _retryError = null;
        _speed = SpeedEstimator();
      });
      _subscribe();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() => _retryError = l10n.retryFailed(e.toString()));
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _cancel() {
    TaskService.instance.cancel(_taskId);
    _pop(false);
  }

  bool get _isFinalizing {
    final p = _latest;
    if (p == null || p.state != 'running') return false;
    final total = p.total;
    if (total != null && total > BigInt.zero && p.completed >= total) {
      return true;
    }
    final fraction = p.fraction;
    if (fraction != null && fraction >= 1.0) {
      return true;
    }
    return false;
  }

  String _dialogTitle(String title, AppLocalizations l10n) {
    final uploadMatch = RegExp(r'^Uploading\s+(\d+)\s+item\(s\)\.\.\.$').firstMatch(title);
    if (uploadMatch != null) {
      return l10n.uploadingItems(uploadMatch.group(1)!);
    }
    final uploadFolderMatch = RegExp(r'^Uploading\s+folder\s+"(.*)"\.\.\.$').firstMatch(title);
    if (uploadFolderMatch != null) {
      return l10n.uploadingFolder(uploadFolderMatch.group(1)!);
    }
    final downloadFileMatch = RegExp(r'^Downloading\s+(.*)\.\.\.$').firstMatch(title);
    if (downloadFileMatch != null) {
      return l10n.downloadingFile(downloadFileMatch.group(1)!);
    }
    switch (title) {
      case 'Downloading Files…':
        return l10n.downloadingFiles;
      case 'Duplicating…':
        return l10n.creatingCopy;
      case 'Deleting…':
        return l10n.deleting;
      case 'Compressing…':
        return l10n.compressing;
      case 'Extracting Archive…':
        return l10n.extracting;
      case 'Moving Files…':
        return l10n.movingFiles;
      case 'Copying Files…':
        return l10n.copyingFiles;
      default:
        return title;
    }
  }

  String? _speedLine(TaskProgressDto p, AppLocalizations l10n) {
    if (_isFinalizing) {
      return l10n.waitingServerVerify;
    }
    final parts = <String>[];
    final speed = _speed.speedText();
    if (speed != null) parts.add(speed);
    final eta = _speed.etaText(p.completed, p.total, l10n: l10n);
    if (eta != null) parts.add(eta);
    if (parts.isEmpty) {
      return l10n.transferring;
    }
    return parts.join(' • ');
  }

  String _statusLabel(String state, AppLocalizations l10n) {
    if (_isFinalizing) {
      return l10n.finalizingServer;
    }
    switch (state) {
      case 'pending':
        return l10n.waiting;
      case 'running':
        return l10n.inProgress;
      case 'completed':
        return l10n.completed;
      case 'failed':
        return l10n.failed;
      case 'cancelled':
        return l10n.cancelled;
      default:
        return state;
    }
  }

  /// Bytes when the task measured a byte total; otherwise a plain item count.
  String _processedLabel(TaskProgressDto p, AppLocalizations l10n) {
    final total = p.total;
    if (total != null) {
      final isItemCount = p.label == 'MoveItems' || p.label == 'Delete';
      if (isItemCount) {
        return l10n.itemsOutOfTotal(p.completed.toInt(), total.toInt());
      }
      return '${formatBytes(p.completed)} / ${formatBytes(total)}';
    }
    return l10n.itemsCount(p.completed.toInt());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = _latest;
    final state = p?.state ?? 'pending';
    final fraction = p?.fraction;

    return AlertDialog(
      title: Text(_dialogTitle(widget.title, l10n)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _statusLabel(state, l10n),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isFinalizing) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.processingPercent,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ] else if (fraction != null)
                Text(
                  '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isFinalizing)
            const LinearProgressIndicator()
          else if (fraction != null)
            LinearProgressIndicator(value: fraction)
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 12),
          if (p?.current != null) ...[
            const SizedBox(height: 4),
            Text(
              p!.current!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              _processedLabel(p, l10n),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (p != null && p.skipped > BigInt.zero) ...[
            const SizedBox(height: 4),
            Text(
              l10n.skippedAlreadyExists(p.skipped.toInt()),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (state == 'running' && p != null && _speedLine(p, l10n) != null) ...[
            const SizedBox(height: 4),
            Text(
              _speedLine(p, l10n)!,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (p?.error != null || _retryError != null) ...[
            const SizedBox(height: 8),
            Text(
              p?.error ?? _retryError!,
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        if (state == 'failed') ...[
          if (widget.onRetry != null)
            FilledButton(
              onPressed: _retry,
              child: Text(l10n.retry),
            ),
          if (p?.error != null)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(l10n.copyError),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p!.error!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.errorCopied)),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.close),
          ),
        ] else ...[
          TextButton(
            onPressed: _background,
            child: Text(l10n.runInBackground),
          ),
          TextButton(
            onPressed: _cancel,
            child: Text(l10n.cancel),
          ),
        ],
      ],
    );
  }
}
