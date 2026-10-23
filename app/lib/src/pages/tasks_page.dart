import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../rust/api/tasks.dart';
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
    if (mounted) setState(() => _tasks = tasks);
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
    if (t.state == 'completed') return Colors.green;
    if (t.state == 'failed') return Colors.red;
    if (t.state == 'cancelled') return Colors.grey;
    return Colors.blue;
  }

  String _statusText(TaskProgressDto t) {
    switch (t.state) {
      case 'pending':
        return 'Waiting…';
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
    final parts = <String>[_statusText(t)];
    final total = t.total;
    if (total != null) {
      parts.add('${formatBytes(t.completed)} of ${formatBytes(total)}');
    } else if (t.state == 'running' || t.state == 'completed') {
      parts.add('${t.completed} items');
    }
    if (t.state == 'running') {
      final estimator = _speeds[t.id];
      final speed = estimator?.speedText();
      if (speed != null) parts.add(speed);
      final eta = estimator?.etaText(t.completed, t.total);
      if (eta != null) parts.add(eta);
    }
    if (t.skipped > BigInt.zero) {
      parts.add('${t.skipped} skipped');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$refused finished task(s) could not be cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTerminal = _tasks.any(_isTerminal);
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).tasks),
        actions: [
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
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.task_alt, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context).noTasksYet,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Copies, moves and other long operations will appear here.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
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
                          t.label ?? 'Task',
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
                          const SnackBar(content: Text('Error copied to clipboard')),
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
                      const SnackBar(content: Text('This task cannot be cancelled')),
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
                  TaskService.instance.dismiss(t.id);
                  _refresh();
                },
              ),
          ],
        ),
      ),
    );
  }
}
