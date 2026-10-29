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
}
