import 'dart:async';
import 'package:flutter/material.dart';
import '../rust/api/tasks.dart';
import '../services/task_service.dart';

class TaskProgressDialog extends StatefulWidget {
  final String taskId;
  final String title;

  const TaskProgressDialog({
    super.key,
    required this.taskId,
    required this.title,
  });

  static Future<bool?> show(BuildContext context, String taskId, String title) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TaskProgressDialog(taskId: taskId, title: title),
    );
  }

  @override
  State<TaskProgressDialog> createState() => _TaskProgressDialogState();
}

class _TaskProgressDialogState extends State<TaskProgressDialog> {
  StreamSubscription<TaskProgressDto>? _sub;
  TaskProgressDto? _latest;

  @override
  void initState() {
    super.initState();
    _sub = TaskService.instance.watch(widget.taskId).listen((p) {
      if (mounted) {
        setState(() => _latest = p);
        if (p.state == 'completed') {
          Navigator.of(context).pop(true);
        } else if (p.state == 'failed') {
          // Keep the dialog open so the reason is visible.
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _cancel() {
    TaskService.instance.cancel(widget.taskId);
    Navigator.of(context).pop(false);
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
          if (fraction != null)
            LinearProgressIndicator(value: fraction)
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Status: $state',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
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
              'Processed: ${p.completed} items/bytes',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          if (p?.error != null) ...[
            const SizedBox(height: 8),
            Text(
              p!.error!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        if (state == 'failed')
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          )
        else
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}
