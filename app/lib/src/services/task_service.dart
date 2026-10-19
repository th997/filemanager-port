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
    while (true) {
      final p = poll(taskId);
      if (p != null) {
        yield p;
        if (p.state == 'completed' || p.state == 'failed' || p.state == 'cancelled') {
          break;
        }
      }
      await Future.delayed(interval);
    }
  }
}
