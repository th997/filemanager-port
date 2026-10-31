import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/dialogs/folder_picker_dialog.dart';
import 'package:filemanager/src/dialogs/file_picker_dialog.dart';
import 'package:filemanager/src/services/path_utils.dart';

void main() {
  group('Upload Folder and Files Tests', () {
    test('splitNativeFile splits Linux and Windows paths accurately', () {
      final linux = splitNativeFile('/k/145233001_kjbbaishi/1a转存/2026/00643老姜高级盘口2.0系列/01-2.87选股法-2.mp4');
      expect(linux.srcRoot, equals('/k/145233001_kjbbaishi/1a转存/2026/00643老姜高级盘口2.0系列'));
      expect(linux.name, equals('01-2.87选股法-2.mp4'));

      final rootFile = splitNativeFile('/video.mp4');
      expect(rootFile.srcRoot, equals('/'));
      expect(rootFile.name, equals('video.mp4'));

      final win = splitNativeFile(r'D:\Movies\Action\film.mkv');
      expect(win.srcRoot, equals(r'D:\Movies\Action'));
      expect(win.name, equals('film.mkv'));

      final winRootFile = splitNativeFile(r'C:\boot.ini');
      expect(winRootFile.srcRoot, equals(r'C:\'));
      expect(winRootFile.name, equals('boot.ini'));
    });

    test('splitPathToRootAndRel handles POSIX and Windows directories', () {
      final linux = splitPathToRootAndRel('/k/145233001_kjbbaishi/1a转存');
      expect(linux.root, equals('/'));
      expect(linux.relPath, equals('k/145233001_kjbbaishi/1a转存'));

      final win = splitPathToRootAndRel(r'D:\Work\Projects\App');
      expect(win.root, equals(r'D:\'));
      expect(win.relPath, equals(r'Work\Projects\App'));
    });

    test('shortDirectoryName extracts last two segments for compact chips', () {
      expect(shortDirectoryName('/k/145233001_kjbbaishi/1a转存/2026/00643老姜高级盘口2.0系列'), equals('2026/00643老姜高级盘口2.0系列'));
      expect(shortDirectoryName('/home/user/downloads'), equals('user/downloads'));
      expect(shortDirectoryName('/downloads'), equals('downloads'));
      expect(shortDirectoryName('/'), equals('/'));
    });
    test('PickedFolder path computation', () {
      const folderWithRel = PickedFolder(root: '/home/user', relPath: 'documents/work');
      expect(folderWithRel.path, equals('/home/user/documents/work'));

      const folderAtRoot = PickedFolder(root: '/home/user', relPath: '');
      expect(folderAtRoot.path, equals('/home/user'));
    });

    test('Folder upload path decomposition for subfolders and root paths', () {
      // Case 1: Picking a subfolder
      {
        const picked = PickedFolder(root: '/home/user', relPath: 'projects/filemanager');
        final srcPaths = [picked.relPath];
        final folderName = picked.relPath.split('/').where((s) => s.isNotEmpty).last;
        expect(srcPaths, equals(['projects/filemanager']));
        expect(folderName, equals('filemanager'));
      }

      // Case 2: Picking a folder that was mounted as root (Linux/macOS)
      {
        const srcRoot = '/home/user/my_folder';
        final isWindows = srcRoot.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(srcRoot);
        final parts = srcRoot.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
        expect(isWindows, isFalse);
        expect(parts, equals(['home', 'user', 'my_folder']));

        final folderName = parts.last;
        parts.removeLast();
        final parentRoot = isWindows ? parts.join('\\') : '/${parts.join('/')}';
        expect(folderName, equals('my_folder'));
        expect(parentRoot, equals('/home/user'));
      }

      // Case 3: Picking a folder that was mounted as root (Windows drive subfolder)
      {
        const srcRoot = r'D:\projects\app';
        final isWindows = srcRoot.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(srcRoot);
        final parts = srcRoot.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
        expect(isWindows, isTrue);
        expect(parts, equals(['D:', 'projects', 'app']));

        final folderName = parts.last;
        parts.removeLast();
        final parentRoot = parts.join('\\');
        expect(folderName, equals('app'));
        expect(parentRoot, equals(r'D:\projects'));
      }

      // Case 4: Windows drive root subfolder
      {
        const srcRoot = r'C:\MyFiles';
        final isWindows = srcRoot.contains('\\') || RegExp(r'^[a-zA-Z]:').hasMatch(srcRoot);
        final parts = srcRoot.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
        expect(isWindows, isTrue);

        final folderName = parts.last;
        parts.removeLast();
        final parentRoot = parts.length == 1 ? '${parts.first}\\' : parts.join('\\');
        expect(folderName, equals('MyFiles'));
        expect(parentRoot, equals(r'C:\'));
      }
    });

    test('PickedFiles supports multiple paths including folders', () {
      const picked = PickedFiles(
        root: '/storage/emulated/0',
        paths: ['DCIM/Camera', 'Documents/Report.pdf', 'Downloads/music'],
      );
      expect(picked.root, equals('/storage/emulated/0'));
      expect(picked.paths.length, equals(3));
      expect(picked.paths[0], equals('DCIM/Camera'));
    });

    test('FolderPickerDialog selected subfolder computes correct effective relPath', () {
      // User is at root of picker, selects a folder item "work"
      const root = '/home/user';
      const relPath = '';
      const selectedFolder = 'work';
      final effectiveRel = relPath.isEmpty ? selectedFolder : '$relPath/$selectedFolder';
      final picked = PickedFolder(root: root, relPath: effectiveRel);
      expect(picked.relPath, equals('work'));
      expect(picked.path, equals('/home/user/work'));

      // User has navigated into "documents", then selects "invoices"
      const navRelPath = 'documents';
      const navSelectedFolder = 'invoices';
      final navEffectiveRel = navRelPath.isEmpty ? navSelectedFolder : '$navRelPath/$navSelectedFolder';
      final navPicked = PickedFolder(root: root, relPath: navEffectiveRel);
      expect(navPicked.relPath, equals('documents/invoices'));
      expect(navPicked.path, equals('/home/user/documents/invoices'));
    });

    test('Empty relPath at default root is identified as requiring specific folder selection', () {
      const defaultRoot = '/home/user';
      const pickedRelPath = '';
      const pickedRoot = '/home/user';

      final parts = pickedRoot.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      final isDangerousRoot = parts.isEmpty || pickedRoot == defaultRoot || parts.length <= 2;
      expect(pickedRelPath.isEmpty && isDangerousRoot, isTrue);
    });
  });
}
