import 'dart:async';
import '../rust/api/tasks.dart' as tasks_api;

/// Human-readable byte size (used across dialogs and task center).
String formatBytes(BigInt bytes) {
  final value = bytes.toDouble();
  if (value < 1024) return '${value.toInt()} B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// A completed-bytes sample recorded at [time].
class _SpeedSample {
  final DateTime time;
  final BigInt completed;

  const _SpeedSample(this.time, this.completed);
}

/// Estimates transfer speed and derives ETA using a sliding time window.
///
/// Rather than an instantaneous derivative which plummets to 0 B/s whenever
/// network round-trips or multipart chunk writes cause brief pauses, this
/// estimator maintains a sliding window (default 2.5 seconds) of historical
/// progress samples and lightly filters the result. This delivers smooth,
/// realistic speed and ETA readouts across local disks, network shares,
/// and object storage multipart uploads.
class SpeedEstimator {
  final Duration windowDuration;
  final Duration initialWarmUp;
  final List<_SpeedSample> _samples = [];
  double? _smoothedSpeed;
  DateTime? _firstTransferTime;
  BigInt? _firstCompleted;
  DateTime? _lastProgressChangeTime;

  SpeedEstimator({
    this.windowDuration = const Duration(milliseconds: 4500),
    this.initialWarmUp = const Duration(milliseconds: 300),
  });

  /// Feed a new sample; returns the smoothed speed in bytes/sec, or null
  /// until enough samples exist.
  double? add(BigInt completed) {
    final now = DateTime.now();
    _samples.add(_SpeedSample(now, completed));

    if (_firstTransferTime == null) {
      _firstTransferTime = now;
      _firstCompleted = completed;
      _lastProgressChangeTime = now;
      return null;
    }

    // Track when progress last advanced
    if (_samples.length >= 2 && completed > _samples[_samples.length - 2].completed) {
      _lastProgressChangeTime = now;
    }

    // Keep samples within the window plus one sample before cutoff so the
    // window span is at least windowDuration.
    final cutoff = now.subtract(windowDuration);
    while (_samples.length > 2 && _samples[1].time.isBefore(cutoff)) {
      _samples.removeAt(0);
    }

    final totalElapsed =
        now.difference(_firstTransferTime!).inMilliseconds / 1000.0;
    if (totalElapsed < initialWarmUp.inMilliseconds / 1000.0) {
      // Warm-up period: do not report premature spike from initial buffer dump
      return _smoothedSpeed;
    }

    final oldest = _samples.first;
    final windowDt = now.difference(oldest.time).inMilliseconds / 1000.0;
    final windowBytesDelta = (completed - oldest.completed).toDouble();

    // In the first few seconds of a transfer, anchor against cumulative rate.
    // This absorbs any initial socket buffer burst (e.g. 10MB loaded in 0.1s).
    final cumulativeBytesDelta =
        (completed - (_firstCompleted ?? BigInt.zero)).toDouble();
    final cumulativeSpeed =
        totalElapsed > 0.2 ? cumulativeBytesDelta / totalElapsed : null;

    // Calculate window rate
    double? currentRate;
    if (windowDt >= 0.25 && windowBytesDelta > 0) {
      currentRate = windowBytesDelta / windowDt;
    }

    // If in warm-up transition phase (< 4 seconds), prioritize cumulative rate anchor
    if (totalElapsed < 4.0 && cumulativeSpeed != null) {
      if (currentRate != null) {
        currentRate = cumulativeSpeed * 0.7 + currentRate * 0.3;
      } else {
        currentRate = cumulativeSpeed;
      }
    }

    if (currentRate == null || currentRate <= 0) {
      // No progress in current window. Check how long since progress advanced:
      final timeSinceProgress = _lastProgressChangeTime != null
          ? now.difference(_lastProgressChangeTime!).inMilliseconds / 1000.0
          : 0.0;

      if (timeSinceProgress < 3.0 &&
          _smoothedSpeed != null &&
          _smoothedSpeed! > 0) {
        // Chunks in flight (e.g. S3 5MB/8MB multipart upload, TCP ACKs).
        // Hold the active transfer speed so it does not falsely plunge to 0 B/s.
        return _smoothedSpeed;
      } else if (_smoothedSpeed != null) {
        // Prolonged stall (> 3.0 seconds): gently decay towards 0
        _smoothedSpeed = _smoothedSpeed! * 0.8;
        if (_smoothedSpeed! < 1024) _smoothedSpeed = null;
        return _smoothedSpeed;
      }
      return null;
    }

    if (_smoothedSpeed == null) {
      _smoothedSpeed = currentRate;
    } else {
      // Exponential moving average: 75% previous, 25% current
      _smoothedSpeed = _smoothedSpeed! * 0.75 + currentRate * 0.25;
    }

    return _smoothedSpeed;
  }

  /// "about 4 min left" / "剩余约 4 分钟" style text, or null when it cannot be estimated.
  String? etaText(BigInt completed, BigInt? total, {bool isZh = false}) {
    if (total == null) return null;
    final speed = _smoothedSpeed;
    if (speed == null || speed < 1.0) return null;
    final remaining = (total - completed).toDouble();
    if (remaining <= 0) return null;

    final seconds = (remaining / speed).round();
    if (seconds < 5) {
      return isZh ? '即将完成' : 'almost done';
    }
    if (seconds < 60) {
      return isZh ? '剩余约 $seconds 秒' : 'about $seconds sec left';
    }
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) {
      return isZh ? '剩余约 $minutes 分钟' : 'about $minutes min left';
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (isZh) {
      return rest == 0 ? '剩余约 $hours 小时' : '剩余约 $hours 小时 $rest 分钟';
    } else {
      return rest == 0 ? 'about $hours h left' : 'about $hours h $rest min left';
    }
  }

  /// Formatted transfer speed (e.g. "12.5 MB/s"), or null if below 1 B/s or unknown.
  String? speedText() {
    final speed = _smoothedSpeed;
    if (speed == null || speed < 1.0) return null;
    final rounded = speed.round();
    if (rounded <= 0) return null;
    return '${formatBytes(BigInt.from(rounded))}/s';
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
