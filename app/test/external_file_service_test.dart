import 'package:filemanager/src/services/external_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExternalFileService Path Normalization', () {
    test('Standard POSIX path remains unchanged', () {
      expect(
        ExternalFileService.cleanPath('/var/mobile/Documents/test.md'),
        equals('/var/mobile/Documents/test.md'),
      );
    });

    test('Trims surrounding whitespaces', () {
      expect(
        ExternalFileService.cleanPath('   /path/to/file.pdf   \n'),
        equals('/path/to/file.pdf'),
      );
    });

    test('Converts file:// URL to POSIX file path', () {
      expect(
        ExternalFileService.cleanPath('file:///Users/th/sample.txt'),
        equals('/Users/th/sample.txt'),
      );
    });

    test('Decodes percent-encoded characters in file:// URL', () {
      expect(
        ExternalFileService.cleanPath('file:///Users/th/My%20Work/Doc%201.pdf'),
        equals('/Users/th/My Work/Doc 1.pdf'),
      );
    });
  });

  group('ExternalPickRequest MIME Filtering', () {
    test('Wildcard MIME type has no filter and matches everything', () {
      final req = ExternalPickRequest.fromMap({
        'allowMultiple': false,
        'mimeType': '*/*',
        'extraMimeTypes': <String>[],
      });
      expect(req.allowMultiple, isFalse);
      expect(req.hasTypeFilter, isFalse);
      expect(req.matchesFileName('photo.jpg'), isTrue);
      expect(req.matchesFileName('archive.bin'), isTrue);
    });

    test('image/* filters to image files only', () {
      final req = ExternalPickRequest.fromMap({
        'allowMultiple': true,
        'mimeType': 'image/*',
      });
      expect(req.allowMultiple, isTrue);
      expect(req.hasTypeFilter, isTrue);
      expect(req.matchesFileName('sample.png'), isTrue);
      expect(req.matchesFileName('vector.svg'), isTrue);
      expect(req.matchesFileName('document.pdf'), isFalse);
    });

    test('extraMimeTypes overrides primary mimeType', () {
      final req = ExternalPickRequest.fromMap({
        'allowMultiple': false,
        'mimeType': '*/*',
        'extraMimeTypes': ['application/pdf', 'audio/*'],
      });
      expect(req.hasTypeFilter, isTrue);
      expect(req.matchesFileName('report.pdf'), isTrue);
      expect(req.matchesFileName('song.mp3'), isTrue);
      expect(req.matchesFileName('movie.mp4'), isFalse);
    });
  });
}
