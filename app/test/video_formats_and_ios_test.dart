import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/media_player_page.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Video Formats Support Tests', () {
    test('All common and advanced video formats are identified as video', () {
      final formats = [
        // Standard containers
        'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', '3gp', '3gpp', '3g2', '3gpp2',
        'm4v', 'ts', 'wmv', 'rmvb', 'rm', 'vob', 'ogv', 'm2ts', 'mts', 'f4v', 'f4p',
        'asf', 'divx', 'xvid', 'mpg', 'mpeg', 'qt',
        // Broadcast, transport streams & TV recordings
        'tp', 'trp', 'm2t', 'm2v', 'm1v', 'mpv', 'mpe', 'evo', 'mxf', 'wtv', 'dvr-ms',
        // Camcorder, raw elementary video streams & surveillance
        'dv', 'dif', 'h264', '264', 'avc', 'h265', '265', 'hevc', 'h266', 'vvc',
        'vc1', 'dav', 'ivf', 'y4m',
        // Streaming manifests & multimedia containers
        'm3u8', 'mpd', 'nut', 'roq', 'bik', 'bk2',
      ];

      for (final ext in formats) {
        expect(
          EntryItem.isVideoExtension(ext),
          isTrue,
          reason: 'Expected .$ext to be recognized as video extension',
        );

        final item = EntryItem(
          EntryDto(
            name: 'sample.$ext',
            path: '/videos/sample.$ext',
            isDir: false,
            hidden: false,
            isSymlink: false,
          ),
        );

        expect(
          item.category,
          EntryCategory.video,
          reason: 'Expected category of sample.$ext to be video',
        );
        expect(
          item.isVideo,
          isTrue,
          reason: 'Expected isVideo of sample.$ext to be true',
        );
        expect(
          item.mimeType,
          isNotNull,
          reason: 'Expected mimeType for sample.$ext to be registered',
        );
      }
    });

    test('MediaPlayerPage identifies Apple native formats correctly', () {
      // Formats natively supported by AVPlayer on iOS
      const nativeApple = ['mp4', 'mov', 'm4v', 'qt', 'm3u8', 'mp3', 'm4a', 'aac', 'wav'];
      for (final ext in nativeApple) {
        expect(
          MediaPlayerPage.isAppleNativeFormat('video.$ext'),
          isTrue,
          reason: 'Expected .$ext to be classified as Apple native format',
        );
      }

      // Formats requiring universal MediaKit (libmpv) engine on iOS
      const mediaKitFormats = [
        'mkv', 'avi', 'webm', 'flv', 'wmv', 'rmvb', 'rm', 'vob', 'ogv', 'ts',
        'm2ts', 'mts', 'f4v', 'asf', 'divx', 'xvid', 'mpg', 'mpeg', 'tp', 'trp',
        'mxf', 'wtv', 'h264', 'h265', 'hevc', 'nut', 'bik',
      ];
      for (final ext in mediaKitFormats) {
        expect(
          MediaPlayerPage.isAppleNativeFormat('video.$ext'),
          isFalse,
          reason: 'Expected .$ext to be routed to MediaKit engine on iOS',
        );
      }
    });
  });
}
