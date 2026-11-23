import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';

/// Parsed EXIF metadata summary including decimal GPS coordinates.
class ExifSummary {
  final String? cameraMake;
  final String? cameraModel;
  final String? dateTime;
  final String? exposureTime;
  final String? fNumber;
  final String? iso;
  final String? focalLength;
  final String? dimensions;
  final double? latitude;
  final double? longitude;
  final Map<String, String> rawTags;

  const ExifSummary({
    this.cameraMake,
    this.cameraModel,
    this.dateTime,
    this.exposureTime,
    this.fNumber,
    this.iso,
    this.focalLength,
    this.dimensions,
    this.latitude,
    this.longitude,
    this.rawTags = const {},
  });

  bool get hasGps => latitude != null && longitude != null;
  String? get formattedGps => hasGps
      ? '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}'
      : null;
}

/// Extracted EXIF & GPS coordinate parser service (reusable across ImageViewer
/// and gallery info sheets).
class ExifService {
  static Future<ExifSummary?> parseFromFile(String localPath) async {
    try {
      final bytes = await File(localPath).readAsBytes();
      return await parseFromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<ExifSummary?> parseFromBytes(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return null;
      return fromRawTags(tags);
    } catch (_) {
      return null;
    }
  }

  static ExifSummary fromRawTags(Map<String, IfdTag> tags) {
    String? str(String key) => tags[key]?.printable.trim();

    final width = str('EXIF ExifImageWidth') ?? str('Image ImageWidth');
    final height = str('EXIF ExifImageLength') ?? str('Image ImageLength');
    final dims = (width != null && height != null) ? '$width × $height' : null;

    final lat = _parseGpsCoord(
      tags['GPS GPSLatitude'],
      tags['GPS GPSLatitudeRef']?.printable,
    );
    final lon = _parseGpsCoord(
      tags['GPS GPSLongitude'],
      tags['GPS GPSLongitudeRef']?.printable,
    );

    final raw = <String, String>{};
    for (final entry in tags.entries) {
      if (entry.key == 'JPEGThumbnail' || entry.key == 'TIFFThumbnail') continue;
      final v = entry.value.printable.trim();
      if (v.isNotEmpty) raw[entry.key] = v;
    }

    return ExifSummary(
      cameraMake: str('Image Make'),
      cameraModel: str('Image Model'),
      dateTime: str('EXIF DateTimeOriginal') ?? str('Image DateTime'),
      exposureTime: str('EXIF ExposureTime'),
      fNumber: str('EXIF FNumber'),
      iso: str('EXIF ISOSpeedRatings'),
      focalLength: str('EXIF FocalLength'),
      dimensions: dims,
      latitude: lat,
      longitude: lon,
      rawTags: raw,
    );
  }

  static double? _parseGpsCoord(IfdTag? coordTag, String? ref) {
    if (coordTag == null) return null;
    final values = coordTag.values.toList();
    if (values.length < 3) return null;
    double toDouble(dynamic r) {
      if (r is Ratio) {
        return r.denominator == 0 ? 0.0 : r.numerator / r.denominator;
      }
      return double.tryParse('$r') ?? 0.0;
    }

    final deg = toDouble(values[0]);
    final min = toDouble(values[1]);
    final sec = toDouble(values[2]);
    var decimal = deg + min / 60.0 + sec / 3600.0;
    final r = (ref ?? '').trim().toUpperCase();
    if (r == 'S' || r == 'W') decimal = -decimal;
    return decimal;
  }
}
