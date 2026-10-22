import 'dart:async';
import '../rust/api/tasks.dart' as tasks_api;

/// Human-readable byte size (used by the task centre; the progress dialog
/// keeps its own copy for now).
String formatBytes(BigInt bytes) {
  final value = bytes.toDouble();
  if (value < 1024) return '${value.toInt()} B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Estimates transfer speed from successive `completed` samples and
/// derives an ETA. Exponentially smoothed so a single stalled poll does
/// not send the readout jumping.
class SpeedEstimator {
  BigInt? _lastCompleted;
  DateTime? _lastTime;
  double _bytesPerSecond = 0;

  /// Feed a new sample; returns the smoothed speed in bytes/sec, or null
  /// until two samples exist.
  double? add(BigInt completed) {
    final now = DateTime.now();
    final lastCompleted = _lastCompleted;
    final lastTime = _lastTime;
    _lastCompleted = completed;
    _lastTime = now;
    if (lastCompleted == null || lastTime == null) return null;
    final dt = now.difference(lastTime).inMilliseconds / 1000.0;
    if (dt <= 0) return _bytesPerSecond > 0 ? _bytesPerSecond : null;
    final instant = (completed - lastCompleted).toDouble() / dt;
    if (instant < 0) return _bytesPerSecond > 0 ? _bytesPerSecond : null;
    _bytesPerSecond =
        _bytesPerSecond == 0 ? instant : _bytesPerSecond * 0.7 + instant * 0.3;
    return _bytesPerSecond;
  }

  /// "about 4 min left" style text, or null when it cannot be estimated.
  String? etaText(BigInt completed, BigInt? total) {
    if (total == null || _bytesPerSecond <= 0) return null;
    final remaining = (total - completed).toDouble();
    if (remaining <= 0) return null;
    final seconds = (remaining / _bytesPerSecond).round();
    if (seconds < 5) return 'almost done';
    if (seconds < 60) return 'about $seconds sec left';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return 'about $minutes min left';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'about $hours h left' : 'about $hours h $rest min left';
  }

  String? speedText() {
    if (_bytesPerSecond <= 0) return null;
    return '${formatBytes(BigInt.from(_bytesPerSecond.round()))}/s';
  }
}

class TaskService {
  static final TaskService instance = TaskService._();
  TaskService._();

  Future<String> copy({
    required String srcRoot,
    required List<String> srcPaths,
    required String dstRoot,
    required String dstDir,
    String? dstName,
    String conflictPolicy = 'overwrite',
  }) async {
    return await tasks_api.startCopyTask(
      srcRoot: srcRoot,
      srcPaths: srcPaths,
      dstRoot: dstRoot,
      dstDir: dstDir,
      dstName: dstName,
      conflictPolicy: conflictPolicy,
    );
  }

  Future<String> move({
    required String srcRoot,
    required List<String> srcPaths,
    required String dstRoot,
    required String dstDir,
    String conflictPolicy = 'overwrite',
  }) async {
    return await tasks_api.startMoveTask(
      srcRoot: srcRoot,
      srcPaths: srcPaths,
      dstRoot: dstRoot,
      dstDir: dstDir,
      conflictPolicy: conflictPolicy,
    );
  }

  Future<String> delete({
    required String root,
    required List<String> paths,
  }) async {
    return await tasks_api.startDeleteTask(
      root: root,
      paths: paths,
    );
  }

  Future<String> compress({
    required String srcRoot,
    required List<String> srcPaths,
    required String dstArchivePath,
  }) async {
    return await tasks_api.startCompressTask(
      srcRoot: srcRoot,
      srcPaths: srcPaths,
      dstArchivePath: dstArchivePath,
    );
  }

  Future<String> extract({
    required String archivePath,
    required String dstDir,
  }) async {
    return await tasks_api.startExtractTask(
      archivePath: archivePath,
      dstDir: dstDir,
    );
  }

  tasks_api.TaskProgressDto? poll(String taskId) {
    return tasks_api.pollTaskProgress(taskId: taskId);
  }

  bool cancel(String taskId) {
    return tasks_api.cancelTask(taskId: taskId);
  }

  /// All registered tasks, oldest first, finished ones included.
  List<tasks_api.TaskProgressDto> list() {
    return tasks_api.listTasks();
  }

  bool dismiss(String taskId) {
    return tasks_api.dismissTask(taskId: taskId);
  }

  Stream<tasks_api.TaskProgressDto> watch(String taskId, {Duration interval = const Duration(milliseconds: 200)}) async* {
    // A finished task is dropped from the registry; if that happens before its
    // terminal event was seen, polling would otherwise spin forever and leave
    // the progress dialog open.
    var misses = 0;
    while (true) {
      final p = poll(taskId);
      if (p != null) {
        misses = 0;
        yield p;
        if (p.state == 'completed' || p.state == 'failed' || p.state == 'cancelled') {
          break;
        }
      } else if (++misses >= 10) {
        break;
      }
      await Future.delayed(interval);
    }
  }
}
