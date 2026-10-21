import 'dart:async';
import '../rust/api/tasks.dart' as tasks_api;

class TaskService {
  static final TaskService instance = TaskService._();
  TaskService._();

  Future<String> copy({
    required String srcRoot,
    required List<String> srcPaths,
    required String dstRoot,
    required String dstDir,
    String? dstName,
  }) async {
    return await tasks_api.startCopyTask(
      srcRoot: srcRoot,
      srcPaths: srcPaths,
      dstRoot: dstRoot,
      dstDir: dstDir,
      dstName: dstName,
    );
  }

  Future<String> move({
    required String srcRoot,
    required List<String> srcPaths,
    required String dstRoot,
    required String dstDir,
  }) async {
    return await tasks_api.startMoveTask(
      srcRoot: srcRoot,
      srcPaths: srcPaths,
      dstRoot: dstRoot,
      dstDir: dstDir,
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
