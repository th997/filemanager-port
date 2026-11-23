import 'dart:async';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/tasks.dart';
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
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _poll() {
    try {
      final list = TaskService.instance
          .list()
          .where((t) => t.state == 'running' || t.state == 'pending' || t.state == 'paused')
          .toList();
      if (mounted &&
          (list.length != _active.length ||
              (list.isNotEmpty &&
                  _active.isNotEmpty &&
                  (list.first.completed != _active.first.completed ||
                      list.first.state != _active.first.state)))) {
        setState(() => _active = list);
      }
    } catch (_) {}
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
