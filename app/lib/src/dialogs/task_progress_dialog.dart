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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    _pop(false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isZh
              ? '已转入后台运行 — 可在 主页 → 任务 查看进度'
              : 'Running in background — track it under Home → Tasks',
        ),
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
        final isZh = Localizations.localeOf(context).languageCode == 'zh';
        setState(() => _retryError = isZh ? '重试失败: $e' : 'Retry failed: $e');
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

  String _dialogTitle(String title, bool isZh) {
    if (!isZh) return title;
    final uploadMatch = RegExp(r'^Uploading\s+(\d+)\s+item\(s\)\.\.\.$').firstMatch(title);
    if (uploadMatch != null) {
      return '正在上传 ${uploadMatch.group(1)} 项…';
    }
    final uploadFolderMatch = RegExp(r'^Uploading\s+folder\s+"(.*)"\.\.\.$').firstMatch(title);
    if (uploadFolderMatch != null) {
      return '正在上传文件夹 "${uploadFolderMatch.group(1)}"…';
    }
    final downloadFileMatch = RegExp(r'^Downloading\s+(.*)\.\.\.$').firstMatch(title);
    if (downloadFileMatch != null) {
      return '正在下载 ${downloadFileMatch.group(1)}…';
    }
    switch (title) {
      case 'Downloading Files…':
        return '正在下载文件…';
      case 'Duplicating…':
        return '正在创建副本…';
      case 'Deleting…':
        return '正在删除…';
      case 'Compressing…':
        return '正在压缩…';
      case 'Extracting Archive…':
        return '正在解压…';
      case 'Moving Files…':
        return '正在移动文件…';
      case 'Copying Files…':
        return '正在复制文件…';
      default:
        return title;
    }
  }

  String? _speedLine(TaskProgressDto p, bool isZh) {
    if (_isFinalizing) {
      return isZh ? '正在同步并校验数据…' : 'Syncing and verifying…';
    }
    final parts = <String>[];
    final speed = _speed.speedText();
    if (speed != null) parts.add(speed);
    final eta = _speed.etaText(p.completed, p.total, isZh: isZh);
    if (eta != null) parts.add(eta);
    if (parts.isEmpty) {
      return isZh ? '正在传输…' : 'Transferring…';
    }
    return parts.join(' • ');
  }

  String _statusLabel(String state, bool isZh) {
    if (_isFinalizing) {
      return isZh ? '正在完成…' : 'Finalizing…';
    }
    switch (state) {
      case 'pending':
        return isZh ? '等待中…' : 'Waiting…';
      case 'running':
        return isZh ? '进行中…' : 'In progress…';
      case 'completed':
        return isZh ? '已完成' : 'Completed';
      case 'failed':
        return isZh ? '失败' : 'Failed';
      case 'cancelled':
        return isZh ? '已取消' : 'Cancelled';
      default:
        return state;
    }
  }

  /// Bytes when the task measured a byte total; otherwise a plain item count.
  String _processedLabel(TaskProgressDto p, bool isZh) {
    final total = p.total;
    if (total != null) {
      final isItemCount = p.label == 'MoveItems' || p.label == 'Delete';
      if (isItemCount) {
        return isZh ? '${p.completed} / $total 项' : '${p.completed} of $total items';
      }
      return isZh
          ? '${formatBytes(p.completed)} / ${formatBytes(total)}'
          : '${formatBytes(p.completed)} of ${formatBytes(total)}';
    }
    return isZh ? '${p.completed} 项' : '${p.completed} items';
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final p = _latest;
    final state = p?.state ?? 'pending';
    final fraction = p?.fraction;

    return AlertDialog(
      title: Text(_dialogTitle(widget.title, isZh)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _statusLabel(state, isZh),
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
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              _processedLabel(p, isZh),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (p != null && p.skipped > BigInt.zero) ...[
            const SizedBox(height: 4),
            Text(
              isZh
                  ? '${p.skipped} 项已跳过（已存在）'
                  : '${p.skipped} skipped (already exists)',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (state == 'running' && p != null && _speedLine(p, isZh) != null) ...[
            const SizedBox(height: 4),
            Text(
              _speedLine(p, isZh)!,
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
              child: Text(isZh ? '重试' : 'Retry'),
            ),
          if (p?.error != null)
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: Text(isZh ? '复制错误' : 'Copy Error'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p!.error!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isZh ? '错误信息已复制到剪贴板' : 'Error copied to clipboard')),
                );
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(isZh ? '关闭' : 'Close'),
          ),
        ] else ...[
          TextButton(
            onPressed: _background,
            child: Text(isZh ? '后台运行' : 'Background'),
          ),
          TextButton(
            onPressed: _cancel,
            child: Text(isZh ? '取消' : 'Cancel'),
          ),
        ],
      ],
    );
  }
}
