import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      onDone: () => _pop(false),
    );
  }

  /// Dismiss the dialog while the task keeps running on the Rust side.
  /// The task centre (Home → Tasks) remains as the way to watch or cancel
  /// it; until this button existed the modal dialog was a cage.
  void _background() {
    final messenger = ScaffoldMessenger.of(context);
    _pop(false);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Running in background — track it under Home → Tasks'),
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
      if (mounted) setState(() => _retryError = 'Retry failed: $e');
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

  String? _speedLine(TaskProgressDto p) {
    final parts = <String>[];
    final speed = _speed.speedText();
    if (speed != null) parts.add(speed);
    final eta = _speed.etaText(p.completed, p.total);
    if (eta != null) parts.add(eta);
    return parts.isEmpty ? null : parts.join(' • ');
  }

  String _statusLabel(String state) {
    switch (state) {
      case 'pending':
        return 'Waiting…';
      case 'running':
        return 'In progress…';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return state;
    }
  }

  String _formatBytes(BigInt bytes) {
    final value = bytes.toDouble();
    if (value < 1024) return '${value.toInt()} B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Bytes when the task measured a byte total; otherwise a plain item count.
  String _processedLabel(TaskProgressDto p) {
    final total = p.total;
    if (total != null) {
      return '${_formatBytes(p.completed)} of ${_formatBytes(total)}';
    }
    return '${p.completed} items';
  }

  @override
  Widget build(BuildContext context) {
    final p = _latest;
    final state = p?.state ?? 'pending';
    final fraction = p?.fraction;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusLabel(state),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (fraction != null)
                Text(
                  '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (fraction != null)
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
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              _processedLabel(p),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (p != null && p.skipped > BigInt.zero) ...[
            const SizedBox(height: 4),
            Text(
              '${p.skipped} skipped (already exists)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (state == 'running' && p != null && _speedLine(p) != null) ...[
            const SizedBox(height: 4),
            Text(
              _speedLine(p)!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (p?.error != null || _retryError != null) ...[
            const SizedBox(height: 8),
            Text(
              p?.error ?? _retryError!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        if (state == 'failed') ...[
          if (widget.onRetry != null)
            FilledButton(
              onPressed: _retry,
              child: const Text('Retry'),
            ),
          if (p?.error != null)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy Error'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p!.error!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Error copied to clipboard')),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
        ] else ...[
          TextButton(
            onPressed: _background,
            child: const Text('Background'),
          ),
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ],
    );
  }
}
