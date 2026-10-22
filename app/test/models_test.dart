import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/services/path_utils.dart';
import 'package:filemanager/src/services/platform_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntryItem Tests', () {
    test('detects archive types correctly', () {
      final zipEntry = EntryItem(
        EntryDto(name: 'data.zip', path: '/data.zip', isDir: false, hidden: false, isSymlink: false),
      );
      expect(zipEntry.isArchive, isTrue);

      final tarEntry = EntryItem(
        EntryDto(name: 'archive.tar.gz', path: '/archive.tar.gz', isDir: false, hidden: false, isSymlink: false),
      );
      expect(tarEntry.isArchive, isTrue);

      final sevenzEntry = EntryItem(
        EntryDto(name: 'backup.7z', path: '/backup.7z', isDir: false, hidden: false, isSymlink: false),
      );
      expect(sevenzEntry.isArchive, isTrue);

      final textEntry = EntryItem(
        EntryDto(name: 'doc.txt', path: '/doc.txt', isDir: false, hidden: false, isSymlink: false),
      );
      expect(textEntry.isArchive, isFalse);
    });

    test('detects text/code types correctly', () {
      final rsEntry = EntryItem(
        EntryDto(name: 'main.rs', path: '/main.rs', isDir: false, hidden: false, isSymlink: false),
      );
      expect(rsEntry.isText, isTrue);

      final jsonEntry = EntryItem(
        EntryDto(name: 'config.json', path: '/config.json', isDir: false, hidden: false, isSymlink: false),
      );
      expect(jsonEntry.isText, isTrue);
    });

    test('detects image types correctly', () {
      final pngEntry = EntryItem(
        EntryDto(name: 'logo.png', path: '/logo.png', isDir: false, hidden: false, isSymlink: false),
      );
      expect(pngEntry.isImage, isTrue);

      final jpgEntry = EntryItem(
        EntryDto(name: 'photo.jpg', path: '/photo.jpg', isDir: false, hidden: false, isSymlink: false),
      );
      expect(jpgEntry.isImage, isTrue);
    });

    test('formats file sizes accurately', () {
      final small = EntryItem(
        EntryDto(name: 'a', path: '/a', isDir: false, size: BigInt.from(500), hidden: false, isSymlink: false),
      );
      expect(small.formattedSize, '500 B');

      final med = EntryItem(
        EntryDto(name: 'b', path: '/b', isDir: false, size: BigInt.from(2048), hidden: false, isSymlink: false),
      );
      expect(med.formattedSize, '2.0 KB');

      final large = EntryItem(
        EntryDto(name: 'c', path: '/c', isDir: false, size: BigInt.from(5 * 1024 * 1024), hidden: false, isSymlink: false),
      );
      expect(large.formattedSize, '5.0 MB');
    });
  });

  group('Path utils', () {
    test('joins relative paths onto native roots without doubling separators', () {
      expect(joinNative('/', 'a/b'), '/a/b');
      expect(joinNative('/home/user', 'a/b'), '/home/user/a/b');
      expect(joinNative('/home/user/', 'a'), '/home/user/a');
      expect(joinNative('/home/user', ''), '/home/user');
      expect(joinNative(r'C:\', 'a/b'), r'C:\a\b');
    });

    test('recognises native roots only', () {
      expect(isNativeRoot('/storage/emulated/0'), isTrue);
      expect(isNativeRoot(r'C:\'), isTrue);
      expect(isNativeRoot('C:/foo/bar'), isTrue);
      expect(isNativeRoot('remote://abc'), isFalse);
      expect(isNativeRoot('archive:///tmp/a.zip'), isFalse);
    });
  });

  group('PlatformPaths Tests', () {
    test('defaultRoot returns a valid path', () {
      final root = PlatformPaths.defaultRoot();
      expect(root, isNotEmpty);
    });

    test('quickTargets returns essential directories', () {
      final targets = PlatformPaths.quickTargets();
      expect(targets, isNotEmpty);
      expect(targets.any((t) => t.name.contains('Home') || t.name.contains('Storage')), isTrue);
    });

    test('databasePath is within appDataDir', () {
      final dbPath = PlatformPaths.databasePath();
      expect(dbPath.endsWith('filemanager.db'), isTrue);
    });
  });
}
