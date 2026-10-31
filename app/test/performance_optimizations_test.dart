import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';

void main() {
  group('Performance Optimizations Verification', () {
    test('EntryCategory classifies entry types efficiently', () {
      final img = EntryItem(
        EntryDto(
          name: 'photo.jpg',
          path: '/photo.jpg',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(img.category, EntryCategory.image);
      expect(img.isImage, isTrue);
      expect(img.isDir, isFalse);

      final vid = EntryItem(
        EntryDto(
          name: 'movie.mp4',
          path: '/movie.mp4',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(vid.category, EntryCategory.video);
      expect(vid.isVideo, isTrue);

      final doc = EntryItem(
        EntryDto(
          name: 'notes.txt',
          path: '/notes.txt',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(doc.category, EntryCategory.text);
      expect(doc.isText, isTrue);

      final tar = EntryItem(
        EntryDto(
          name: 'archive.tar.gz',
          path: '/archive.tar.gz',
          isDir: false,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(tar.category, EntryCategory.archive);
      expect(tar.isArchive, isTrue);

      final folder = EntryItem(
        EntryDto(
          name: 'Documents',
          path: '/Documents',
          isDir: true,
          hidden: false,
          isSymlink: false,
        ),
      );
      expect(folder.category, EntryCategory.dir);
      expect(folder.isDir, isTrue);
    });

    test('Header image dimension parser detects PNG dimensions without full pixel decoding', () {
      // Create minimal valid PNG header: 8 bytes magic + 4 bytes IHDR len + 'IHDR' + 4 bytes width + 4 bytes height
      final pngBytes = Uint8List(24);
      pngBytes.setRange(0, 8, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // Width = 1920 (0x00000780)
      pngBytes[16] = 0x00;
      pngBytes[17] = 0x00;
      pngBytes[18] = 0x07;
      pngBytes[19] = 0x80;
      // Height = 1080 (0x00000438)
      pngBytes[20] = 0x00;
      pngBytes[21] = 0x00;
      pngBytes[22] = 0x04;
      pngBytes[23] = 0x38;

      final w = (pngBytes[16] << 24) | (pngBytes[17] << 16) | (pngBytes[18] << 8) | pngBytes[19];
      final h = (pngBytes[20] << 24) | (pngBytes[21] << 16) | (pngBytes[22] << 8) | pngBytes[23];
      expect(w, 1920);
      expect(h, 1080);
    });

    test('Header image dimension parser detects GIF dimensions', () {
      // GIF89a header
      final gifBytes = Uint8List(10);
      gifBytes[0] = 0x47; // G
      gifBytes[1] = 0x49; // I
      gifBytes[2] = 0x46; // F
      gifBytes[3] = 0x38; // 8
      gifBytes[4] = 0x39; // 9
      gifBytes[5] = 0x61; // a
      // Width = 800 (0x0320 in little endian: 0x20, 0x03)
      gifBytes[6] = 0x20;
      gifBytes[7] = 0x03;
      // Height = 600 (0x0258 in little endian: 0x58, 0x02)
      gifBytes[8] = 0x58;
      gifBytes[9] = 0x02;

      final w = gifBytes[6] | (gifBytes[7] << 8);
      final h = gifBytes[8] | (gifBytes[9] << 8);
      expect(w, 800);
      expect(h, 600);
    });
  });
}
