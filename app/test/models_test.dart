import 'dart:io';

import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/services/path_utils.dart';
import 'package:filemanager/src/services/platform_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntryItem Tests', () {
    test('detects all archive types correctly', () {
      for (final name in [
        'data.zip',
        'app.apk',
        'bundle.apkm',
        'split.apks',
        'assets.obb',
        'comic.cbz',
        'lib.jar',
        'src.tar',
        'pkg.tgz',
        'archive.tar.gz',
        'backup.7z',
        'book.epub',
      ]) {
        final entry = EntryItem(
          EntryDto(name: name, path: '/$name', isDir: false, hidden: false, isSymlink: false),
        );
        expect(entry.isArchive, isTrue, reason: 'Expected $name to be archive');
      }

      final textEntry = EntryItem(
        EntryDto(name: 'doc.txt', path: '/doc.txt', isDir: false, hidden: false, isSymlink: false),
      );
      expect(textEntry.isArchive, isFalse);
    });

    test('detects all text/code types and special filenames correctly', () {
      for (final name in [
        'main.rs',
        'app.dart',
        'config.json',
        'tsconfig.jsonc',
        'data.json5',
        'map.geojson',
        'world.topojson',
        'bundle.js.map',
        'Cargo.lock',
        'index.htm',
        'page.xhtml',
        'icon.svg',
        'Info.plist',
        'module.mjs',
        'View.jsx',
        'Screen.tsx',
        'run.bash',
        'rc.zsh',
        'native.cc',
        'Dockerfile',
        'Makefile',
        '.eslintrc',
        '.gitignore',
      ]) {
        final entry = EntryItem(
          EntryDto(name: name, path: '/$name', isDir: false, hidden: false, isSymlink: false),
        );
        expect(entry.isText, isTrue, reason: 'Expected $name to be text');
      }
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

    test('privateInboxDir creates private Inbox and quickTargets exposes it', () {
      final inbox = PlatformPaths.privateInboxDir();
      expect(inbox, isNotEmpty);
      expect(inbox.endsWith('Inbox'), isTrue);
      expect(Directory(inbox).existsSync(), isTrue);

      final targets = PlatformPaths.quickTargets();
      final inboxTargets = targets.where((t) => t.kind == 'inbox').toList();
      expect(inboxTargets, hasLength(1));
      expect(inboxTargets.first.name, equals('My Space'));
      expect(inboxTargets.first.root, equals(inbox));
      expect(inboxTargets.first.relPath, isEmpty);
    });

    test('Inbox containment helpers reject parent and sibling paths', () {
      final inbox = PlatformPaths.privateInboxDir();
      final sep = Platform.pathSeparator;

      expect(PlatformPaths.isPrivateInboxRoot(inbox), isTrue);
      expect(PlatformPaths.isPrivateInboxRoot('$inbox$sep'), isTrue);
      expect(PlatformPaths.isInsidePrivateInbox(inbox), isTrue);

      final nested = '$inbox${sep}Work${sep}Contract.pdf';
      expect(PlatformPaths.isPrivateInboxRoot(nested), isFalse);
      expect(PlatformPaths.isInsidePrivateInbox(nested), isTrue);
      final splitNested = PlatformPaths.splitPrivateInboxPath(nested);
      expect(splitNested, isNotNull);
      expect(splitNested!.root, equals(inbox));
      expect(splitNested.relPath, equals('Work/Contract.pdf'));

      final splitRoot = PlatformPaths.splitPrivateInboxPath('$inbox$sep');
      expect(splitRoot, isNotNull);
      expect(splitRoot!.root, equals(inbox));
      expect(splitRoot.relPath, isEmpty);

      final parentDir = PlatformPaths.appDataDir();
      expect(PlatformPaths.isPrivateInboxRoot(parentDir), isFalse);
      expect(PlatformPaths.isInsidePrivateInbox(parentDir), isFalse);
      expect(PlatformPaths.splitPrivateInboxPath(parentDir), isNull);

      final sibling = '${inbox}_extra';
      expect(PlatformPaths.isPrivateInboxRoot(sibling), isFalse);
      expect(PlatformPaths.isInsidePrivateInbox(sibling), isFalse);
      expect(PlatformPaths.isInsidePrivateInbox('$sibling${sep}a.txt'), isFalse);
      expect(PlatformPaths.splitPrivateInboxPath('$sibling${sep}a.txt'), isNull);
    });
  });
}
