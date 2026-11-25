import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/tasks.dart';
import '../services/global_playback_service.dart';
import '../services/task_service.dart';
import '../pages/tasks_page.dart';

/// Lightweight bottom status bar showing active/paused background transfers
/// without forcing the user to switch to [TasksPage].
class ActiveTasksBanner extends StatefulWidget {
  final VoidCallback? onTap;

  const ActiveTasksBanner({super.key, this.onTap});

  @override
  State<ActiveTasksBanner> createState() => _ActiveTasksBannerState();
}

class _ActiveTasksBannerState extends State<ActiveTasksBanner> {
  Timer? _timer;
  List<TaskProgressDto> _active = const [];

  @override
  void initState() {
    super.initState();
    TaskService.instance.addListener(_onTasksChanged);
    _poll();
  }

  @override
  void dispose() {
    GlobalPlaybackService.instance.setNamedBottomInset('active_tasks_banner', 0.0);
    TaskService.instance.removeListener(_onTasksChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _onTasksChanged() {
    if (!mounted) return;
    _poll();
  }

  static bool _tasksEqual(List<TaskProgressDto> a, List<TaskProgressDto> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ta = a[i];
      final tb = b[i];
      if (ta.id != tb.id ||
          ta.state != tb.state ||
          ta.completed != tb.completed ||
          ta.total != tb.total ||
          ta.fraction != tb.fraction ||
          ta.current != tb.current ||
          ta.error != tb.error ||
          ta.skipped != tb.skipped ||
          ta.rateLimitBps != tb.rateLimitBps) {
        return false;
      }
    }
    return true;
  }

  void _schedulePoll() {
    _timer?.cancel();
    if (!mounted) return;
    final delay = _active.isEmpty
        ? const Duration(seconds: 4)
        : const Duration(seconds: 1);
    _timer = Timer(delay, _poll);
  }

  void _poll() {
    try {
      final list = TaskService.instance
          .list()
          .where((t) => t.state == 'running' || t.state == 'pending' || t.state == 'paused')
          .toList();
      GlobalPlaybackService.instance.setNamedBottomInset(
        'active_tasks_banner',
        list.isNotEmpty ? 44.0 : 0.0,
      );
      if (mounted && !_tasksEqual(_active, list)) {
        setState(() => _active = list);
      }
    } catch (_) {
    } finally {
      _schedulePoll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_active.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final first = _active.first;
    final progress = first.fraction;

    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: widget.onTap ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TasksPage()),
              );
            },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                first.state == 'paused' ? Icons.pause_circle_outline : Icons.sync,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l10n.activeTasksBanner(_active.length)}'
                      '${first.state == 'paused' ? ' (${l10n.taskStatusPaused})' : ''}'
                      '${first.current != null ? " · ${first.current}" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (progress != null)
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
