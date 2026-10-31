import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
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
          ta.total != tb.total) {
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

  String _localizedLabel(String? label, bool isZh) {
    if (!isZh) return label ?? 'Task';
    switch (label) {
      case 'Copy':
        return '复制';
      case 'Move':
      case 'MoveItems':
        return '移动';
      case 'Delete':
        return '删除';
      case 'Compress':
        return '压缩';
      case 'Extract':
        return '解压';
      default:
        return label ?? '任务';
    }
  }

  String _statusText(TaskProgressDto t, {required bool isZh}) {
    final isFinalizing = t.state == 'running' &&
        ((t.total != null && t.total! > BigInt.zero && t.completed >= t.total!) ||
            (t.fraction != null && t.fraction! >= 1.0));
    if (isFinalizing) {
      return isZh ? '正在完成…' : 'Finalizing…';
    }
    switch (t.state) {
      case 'pending':
        return isZh ? '等待中…' : 'Waiting…';
      case 'running':
        return AppLocalizations.of(context).inProgress;
      case 'completed':
        return AppLocalizations.of(context).completed;
      case 'failed':
        return AppLocalizations.of(context).failed;
      case 'cancelled':
        return AppLocalizations.of(context).cancelled;
      default:
        return t.state;
    }
  }

  String _detailText(TaskProgressDto t) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final parts = <String>[_statusText(t, isZh: isZh)];
    final total = t.total;
    if (total != null) {
      final isItemCount = t.label == 'MoveItems' || t.label == 'Delete';
      if (isItemCount) {
        parts.add(isZh ? '${t.completed} / $total 项' : '${t.completed} of $total items');
      } else {
        parts.add(isZh
            ? '${formatBytes(t.completed)} / ${formatBytes(total)}'
            : '${formatBytes(t.completed)} of ${formatBytes(total)}');
      }
    } else if (t.state == 'running' || t.state == 'completed') {
      parts.add(isZh ? '${t.completed} 项' : '${t.completed} items');
    }
    final isFinalizing = t.state == 'running' &&
        ((t.total != null && t.total! > BigInt.zero && t.completed >= t.total!) ||
            (t.fraction != null && t.fraction! >= 1.0));
    if (isFinalizing) {
      parts.add(isZh ? '正在同步数据…' : 'Syncing…');
    } else if (t.state == 'running') {
      final estimator = _speeds[t.id];
      final speed = estimator?.speedText();
      if (speed != null) parts.add(speed);
      final eta = estimator?.etaText(t.completed, t.total, isZh: isZh);
      if (eta != null) parts.add(eta);
    }
    if (t.skipped > BigInt.zero) {
      parts.add(isZh ? '${t.skipped} 项已跳过' : '${t.skipped} skipped');
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
      final isZh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh
                ? '$refused 个已完成的任务无法清除'
                : '$refused finished task(s) could not be cleared',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final hasTerminal = _tasks.any(_isTerminal);
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).tasks),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          if (hasTerminal)
            TextButton(
              onPressed: _clearFinished,
              child: Text(AppLocalizations.of(context).clearFinished),
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
                      title: AppLocalizations.of(context).noTasksYet,
                      subtitle: isZh
                          ? '复制、移动以及其他长时间运行的操作将显示在此处。'
                          : 'Copies, moves and other long operations will appear here.',
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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final terminal = _isTerminal(t);
    final fraction = t.fraction;
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
                          _localizedLabel(t.label, isZh),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (fraction != null && !terminal)
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
                    if (fraction != null)
                      LinearProgressIndicator(value: fraction)
                    else
                      const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    _detailText(t),
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
                            content: Text(
                              isZh
                                  ? '错误信息已复制到剪贴板'
                                  : 'Error copied to clipboard',
                            ),
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
              AppIconButton(
                icon: Icons.close,
                tooltip: AppLocalizations.of(context).cancelTask,
                onPressed: () {
                  // The backend refuses cancellation for some task types; the
                  // button used to look like it worked either way.
                  if (!TaskService.instance.cancel(t.id)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isZh ? '此任务无法取消' : 'This task cannot be cancelled',
                        ),
                      ),
                    );
                  }
                  _refresh();
                },
              )
            else
              AppIconButton(
                icon: Icons.clear,
                tooltip: AppLocalizations.of(context).dismiss,
                onPressed: () {
                  if (!TaskService.instance.dismiss(t.id)) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isZh ? '无法清除该任务' : 'Could not dismiss task',
                          ),
                        ),
                      );
                    }
                  }
                  _refresh();
                },
              ),
          ],
        ),
      ),
    );
  }
}
