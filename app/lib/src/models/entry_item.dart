import 'package:flutter/material.dart';
import '../rust/api/file_manager.dart';

class EntryItem {
  final EntryDto dto;

  const EntryItem(this.dto);

  String get name => dto.name;
  String get path => dto.path;
  bool get isDir => dto.isDir;
  BigInt? get size => dto.size;
  bool get hidden => dto.hidden;

  DateTime? get modified {
    final millis = dto.modifiedMillis;
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  }

  String get formattedSize {
    if (isDir) return '--';
    final s = size;
    if (s == null) return 'Unknown';
    final bytes = s.toDouble();
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedModified {
    final m = modified;
    if (m == null) return '--';
    final y = m.year.toString().padLeft(4, '0');
    final mo = m.month.toString().padLeft(2, '0');
    final d = m.day.toString().padLeft(2, '0');
    final h = m.hour.toString().padLeft(2, '0');
    final mi = m.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  IconData get icon {
    if (isDir) return Icons.folder;
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg')) {
      return Icons.image;
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv')) {
      return Icons.video_file;
    }
    if (lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac')) {
      return Icons.audio_file;
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz') ||
        lower.endsWith('.7z') ||
        lower.endsWith('.apk') ||
        lower.endsWith('.jar') ||
        lower.endsWith('.rar')) {
      return Icons.folder_zip;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.json') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.rs') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.c') ||
        lower.endsWith('.cpp') ||
        lower.endsWith('.h') ||
        lower.endsWith('.py') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  Color iconColor(BuildContext context) {
    if (isDir) return Theme.of(context).colorScheme.primary;
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Colors.red;
    if (lower.endsWith('.zip') || lower.endsWith('.apk') || lower.endsWith('.7z')) {
      return Colors.amber.shade800;
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
      return Colors.purple;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv')) {
      return Colors.blue;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.flac')) {
      return Colors.teal;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}
