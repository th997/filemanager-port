import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Lossless privacy helpers for stripping camera EXIF, GPS, XMP, IPTC, and
/// comment metadata from JPEG images without re-encoding image pixels.
class ImagePrivacyService {
  ImagePrivacyService._();

  /// Returns `true` when [bytes] starts with a valid JPEG SOI + marker prefix.
  static bool isJpeg(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF;

  /// Removes `APP1` (EXIF/XMP), `APP3`..`APP15` (incl. `APP13` IPTC/Photoshop),
  /// and `COM` (`0xFE`) segments from a JPEG bitstream while preserving `APP0`
  /// (JFIF), `APP2` (ICC color profile), quantization/Huffman tables, and the
  /// entropy-coded `SOS`..`EOI` image data verbatim (stripping post-EOI trailers).
  ///
  /// Returns [bytes] untouched if it is not a valid JPEG starting with `FF D8 FF`.
  static Uint8List stripJpegMetadataLossless(Uint8List bytes) {
    if (!isJpeg(bytes)) {
      return bytes;
    }

    final out = BytesBuilder(copy: false);
    out.add(const [0xFF, 0xD8]);

    var pos = 2;
    var reachedEoi = false;
    while (pos < bytes.length && !reachedEoi) {
      // Advance to the next 0xFF marker prefix; fill bytes (0xFF) are skipped.
      if (bytes[pos] != 0xFF) {
        // Unexpected non-marker data before SOS: bail safely with original bytes.
        return bytes;
      }
      while (pos < bytes.length && bytes[pos] == 0xFF) {
        pos++;
      }
      if (pos >= bytes.length) break;

      final marker = bytes[pos];
      pos++;

      // Standalone markers without length field (TEM, RST0..RST7, SOI, EOI).
      if (marker == 0x00 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7) ||
          marker == 0xD8) {
        out.add([0xFF, marker]);
        continue;
      }

      if (marker == 0xD9) {
        // EOI
        out.add(const [0xFF, 0xD9]);
        reachedEoi = true;
        break;
      }

      if (pos + 2 > bytes.length) {
        return bytes;
      }
      final segLen = (bytes[pos] << 8) | bytes[pos + 1];
      if (segLen < 2 || pos + segLen > bytes.length) {
        return bytes;
      }

      if (marker == 0xDA) {
        // Start of Scan: copy header, then scan entropy-coded data up to EOI
        // so post-EOI trailing metadata (e.g., Motion Photo / MPF) is stripped.
        out.add([0xFF, marker]);
        out.add(Uint8List.sublistView(bytes, pos, pos + segLen));
        pos += segLen;

        var scanStart = pos;
        while (pos < bytes.length) {
          if (bytes[pos] != 0xFF) {
            pos++;
            continue;
          }
          if (pos > scanStart) {
            out.add(Uint8List.sublistView(bytes, scanStart, pos));
          }
          final ffStart = pos;
          while (pos < bytes.length && bytes[pos] == 0xFF) {
            pos++;
          }
          if (pos >= bytes.length) {
            out.add(Uint8List.sublistView(bytes, ffStart, bytes.length));
            scanStart = pos;
            break;
          }
          final nextMarker = bytes[pos];
          pos++;
          if (nextMarker == 0x00 ||
              nextMarker == 0x01 ||
              (nextMarker >= 0xD0 && nextMarker <= 0xD7)) {
            out.add([0xFF, nextMarker]);
            scanStart = pos;
            continue;
          }
          if (nextMarker == 0xD9) {
            out.add(const [0xFF, 0xD9]);
            reachedEoi = true;
            scanStart = pos;
            break;
          }
          // Another structural marker (progressive JPEG SOS/DHT/APPn): rewind
          // to marker prefix so the outer loop handles it uniformly.
          pos -= 2;
          scanStart = pos;
          break;
        }
        if (!reachedEoi && pos < bytes.length && scanStart < pos) {
          out.add(Uint8List.sublistView(bytes, scanStart, pos));
        } else if (!reachedEoi && scanStart < bytes.length) {
          out.add(Uint8List.sublistView(bytes, scanStart));
          pos = bytes.length;
        }
        continue;
      }

      // Preserve APP0 (JFIF, 0xE0) and APP2 (ICC profile, 0xE2). Strip APP1
      // (EXIF/XMP, 0xE1), APP3..APP15 (0xE3..0xEF), and COM (0xFE).
      final shouldStrip =
          marker == 0xE1 || (marker >= 0xE3 && marker <= 0xEF) || marker == 0xFE;
      if (!shouldStrip) {
        out.add([0xFF, marker]);
        out.add(Uint8List.sublistView(bytes, pos, pos + segLen));
      }

      pos += segLen;
    }

    return out.takeBytes();
  }

  /// Strips JPEG metadata losslessly from [sourcePath] and either overwrites
  /// it in place (`overwrite == true`) or saves `<stem>_clean<ext>` alongside.
  static Future<String> stripExifAndSaveCopy(
    String sourcePath, {
    bool overwrite = false,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw FileSystemException('Image file does not exist', sourcePath);
    }
    final raw = await file.readAsBytes();
    if (!isJpeg(raw)) {
      throw UnsupportedError(
        'Only JPEG images are supported for lossless EXIF stripping',
      );
    }
    final cleaned = stripJpegMetadataLossless(raw);

    String destPath = sourcePath;
    if (!overwrite) {
      final dir = p.dirname(sourcePath);
      final base = p.basenameWithoutExtension(sourcePath);
      final ext = p.extension(sourcePath);
      destPath = p.join(dir, '${base}_clean$ext');
      var counter = 1;
      while (await File(destPath).exists()) {
        destPath = p.join(dir, '${base}_clean_$counter$ext');
        counter++;
      }
      await File(destPath).writeAsBytes(cleaned, flush: true);
      return destPath;
    }

    final dir = p.dirname(destPath);
    final tmpFile = File(
      p.join(
        dir,
        '.${p.basename(destPath)}.strip_tmp_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await tmpFile.writeAsBytes(cleaned, flush: true);
      await tmpFile.rename(destPath);
    } catch (_) {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      rethrow;
    }
    return destPath;
  }

  /// Strips metadata for a batch of local image paths, returning the count saved.
  static Future<int> batchStripExif(
    List<String> paths, {
    bool overwrite = false,
  }) async {
    var count = 0;
    for (final p in paths) {
      try {
        await stripExifAndSaveCopy(p, overwrite: overwrite);
        count++;
      } catch (_) {}
    }
    return count;
  }
}
