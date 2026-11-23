import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../rust/api/tasks.dart';
import '../services/semantic_colors.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';

/// Task centre: every copy/move/delete/compress/extract task, live.
///
/// Until this page existed, the only window onto a task was the modal
/// progress dialog it started from — background a transfer and it became
/// invisible even though the Rust side kept running it.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<TaskProgressDto> _tasks = const [];
  Timer? _timer;
  final Map<String, SpeedEstimator> _speeds = {};

  /// Tasks whose cancellation was requested and is still in flight.
  final Set<String> _cancelling = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final List<TaskProgressDto> tasks;
    try {
      tasks = TaskService.instance.list();
    } catch (_) {
      // This runs on a 1-second timer: letting it throw left the page
      // showing "No tasks yet" while transfers were actually running.
      return;
    }
    final ids = tasks.map((t) => t.id).toSet();
    _speeds.removeWhere((id, _) => !ids.contains(id));
    _cancelling.removeWhere((id) => !ids.contains(id));
    for (final t in tasks) {
      if (_isTerminal(t)) _cancelling.remove(t.id);
    }
    for (final t in tasks) {
      if (t.state == 'running') {
        _speeds.putIfAbsent(t.id, SpeedEstimator.new).add(t.completed);
      }
    }
    if (!_tasksEqual(_tasks, tasks)) {
      if (mounted) setState(() => _tasks = tasks);
    }
  }

  bool _tasksEqual(List<TaskProgressDto> a, List<TaskProgressDto> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ta = a[i];
      final tb = b[i];
      if (ta.id != tb.id ||
          ta.state != tb.state ||
          ta.completed != tb.completed ||
          ta.total != tb.total ||
          ta.current != tb.current ||
          ta.error != tb.error ||
          ta.skipped != tb.skipped) {
        return false;
      }
    }
    return true;
  }

  bool _isTerminal(TaskProgressDto t) =>
      t.state == 'completed' || t.state == 'failed' || t.state == 'cancelled';

  IconData _iconFor(TaskProgressDto t) {
    if (t.state == 'completed') return Icons.check_circle_outline;
    if (t.state == 'failed') return Icons.error_outline;
    if (t.state == 'cancelled') return Icons.cancel_outlined;
    switch (t.label) {
      case 'Copy':
        return Icons.content_copy;
      case 'Move':
        return Icons.drive_file_move_outline;
      case 'Delete':
        return Icons.delete_outline;
      case 'Compress':
        return Icons.folder_zip_outlined;
      case 'Extract':
        return Icons.unarchive_outlined;
      default:
        return Icons.sync;
    }
  }

  Color _iconColor(TaskProgressDto t) {
    final scheme = Theme.of(context).colorScheme;
    if (t.state == 'completed') return scheme.success;
    if (t.state == 'failed') return scheme.error;
    if (t.state == 'cancelled') return scheme.outline;
    return scheme.primary;
  }

  String _localizedLabel(String? label, AppLocalizations l10n) {
    switch (label) {
      case 'Copy':
        return l10n.taskCopy;
      case 'Move':
      case 'MoveItems':
        return l10n.taskMove;
      case 'Delete':
        return l10n.taskDelete;
      case 'Compress':
        return l10n.taskCompress;
      case 'Extract':
        return l10n.taskExtract;
      default:
        return label ?? l10n.taskGeneric;
    }
  }

  String _statusText(TaskProgressDto t, AppLocalizations l10n) {
    if (_cancelling.contains(t.id)) {
      return l10n.cancelling;
    }
    final isFinalizing = t.state == 'running' &&
        ((t.total != null && t.total! > BigInt.zero && t.completed >= t.total!) ||
            (t.fraction != null && t.fraction! >= 1.0));
    if (isFinalizing) {
      return l10n.finalizingServer;
    }
    switch (t.state) {
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
        return t.state;
    }
  }

  String _detailText(TaskProgressDto t, AppLocalizations l10n) {
    final parts = <String>[_statusText(t, l10n)];
    final total = t.total;
    if (total != null) {
      final isItemCount = t.label == 'MoveItems' || t.label == 'Delete';
      if (isItemCount) {
        parts.add(l10n.itemsOutOfTotal(t.completed.toInt(), total.toInt()));
      } else {
        parts.add('${formatBytes(t.completed)} / ${formatBytes(total)}');
      }
    } else if (t.state == 'running' || t.state == 'completed') {
      parts.add(l10n.itemsCount(t.completed.toInt()));
    }
    final isFinalizing = t.state == 'running' &&
        ((t.total != null && t.total! > BigInt.zero && t.completed >= t.total!) ||
            (t.fraction != null && t.fraction! >= 1.0));
    if (isFinalizing) {
      parts.add(l10n.waitingServerVerify);
    } else if (t.state == 'running') {
      final estimator = _speeds[t.id];
      final speed = estimator?.speedText();
      if (speed != null) parts.add(speed);
      final eta = estimator?.etaText(t.completed, t.total, l10n: l10n);
      if (eta != null) parts.add(eta);
    }
    if (t.skipped > BigInt.zero) {
      parts.add(l10n.skippedAlreadyExists(t.skipped.toInt()));
    }
    return parts.join(' • ');
  }

  void _clearFinished() {
    var refused = 0;
    for (final t in _tasks) {
      if (_isTerminal(t) && !TaskService.instance.dismiss(t.id)) refused++;
    }
    _refresh();
    // A refused dismiss left the row in the list, so the button looked dead.
    if (refused > 0 && mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cannotClearFinishedTasks(refused)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasTerminal = _tasks.any(_isTerminal);
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasks),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _refresh,
          ),
          if (hasTerminal)
            TextButton(
              onPressed: _clearFinished,
              child: Text(l10n.clearFinished),
            ),
        ],
      ),
      body: _tasks.isEmpty
          // Scrollable so pull-to-refresh works while the list is empty too.
          ? RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: AppEmptyState(
                      icon: Icons.task_alt,
                      title: l10n.noTasksYet,
                      subtitle: l10n.tasksEmptySubtitle,
                    ),
                  ),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppUiTokens.pagePadding,
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                // Registry order is oldest first; show newest on top.
                final t = _tasks[_tasks.length - 1 - index];
                return _buildTaskTile(t);
              },
            ),
            ),
      ),
    );
  }

  Widget _buildTaskTile(TaskProgressDto t) {
    final l10n = AppLocalizations.of(context);
    final terminal = _isTerminal(t);
    final fraction = t.fraction;
    final isFinalizing = t.state == 'running' &&
        ((t.total != null && t.total! > BigInt.zero && t.completed >= t.total!) ||
            (fraction != null && fraction >= 1.0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCircleBadge(
              icon: _iconFor(t),
              color: _iconColor(t),
              size: 32,
              iconSize: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _localizedLabel(t.label, l10n),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isFinalizing)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              l10n.processingPercent,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      else if (fraction != null && !terminal)
                        Text(
                          '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  if (!terminal) ...[
                    const SizedBox(height: 6),
                    if (isFinalizing)
                      const LinearProgressIndicator()
                    else if (fraction != null)
                      LinearProgressIndicator(value: fraction)
                    else
                      const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _detailText(t, l10n),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  if (t.current != null && !terminal) ...[
                    const SizedBox(height: 2),
                    Text(
                      t.current!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (t.error != null) ...[
                    const SizedBox(height: 4),
                    // Long backend messages are the useful part; let the
                    // user copy them instead of re-typing from a truncation.
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: t.error!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.errorCopied),
                          ),
                        );
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              t.error!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.red),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.copy, size: 13, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!terminal)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.canPause && (t.state == 'running' || t.state == 'paused'))
                    AppIconButton(
                      icon: t.state == 'paused' ? Icons.play_arrow : Icons.pause,
                      tooltip: t.state == 'paused' ? l10n.resumeTask : l10n.pauseTask,
                      onPressed: () {
                        if (t.state == 'paused') {
                          TaskService.instance.resume(t.id);
                        } else {
                          TaskService.instance.pause(t.id);
                        }
                        _refresh();
                      },
                    ),
                  if (t.canPause)
                    PopupMenuButton<int>(
                      tooltip: l10n.rateLimitLabel,
                      icon: const Icon(Icons.speed, size: 18),
                      onSelected: (bps) {
                        TaskService.instance.setRateLimit(t.id, BigInt.from(bps));
                        _refresh();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 0, child: Text(l10n.rateLimitUnlimited)),
                        const PopupMenuItem(value: 512 * 1024, child: Text('512 KB/s')),
                        const PopupMenuItem(value: 2 * 1024 * 1024, child: Text('2 MB/s')),
                        const PopupMenuItem(value: 10 * 1024 * 1024, child: Text('10 MB/s')),
                        const PopupMenuItem(value: 50 * 1024 * 1024, child: Text('50 MB/s')),
                      ],
                    ),
                  AppIconButton(
                    icon: Icons.close,
                    tooltip: l10n.cancelTask,
                    onPressed: () {
                      if (!TaskService.instance.cancel(t.id)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.cannotCancelTask),
                          ),
                        );
                      } else {
                        setState(() => _cancelling.add(t.id));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.cancelling),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                      _refresh();
                    },
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.canRetry && t.failedItems.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.replay, size: 15),
                      label: Text(
                        l10n.retryFailedItems(t.failedItems.length),
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () async {
                        try {
                          await TaskService.instance.retryFailed(t.id);
                          _refresh();
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                    ),
                  AppIconButton(
                    icon: Icons.clear,
                    tooltip: l10n.dismiss,
                    onPressed: () {
                      if (!TaskService.instance.dismiss(t.id)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.cannotDismissTask),
                            ),
                          );
                        }
                      }
                      _refresh();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
