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
  bool get isSymlink => dto.isSymlink;

  DateTime? get modified {
    final millis = dto.modifiedMillis;
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  }

  bool get isArchive {
    final lower = name.toLowerCase();
    return lower.endsWith('.zip') ||
        lower.endsWith('.apk') ||
        lower.endsWith('.jar') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz') ||
        lower.endsWith('.7z');
  }

  bool get isText {
    final lower = name.toLowerCase();
    return lower.endsWith('.txt') ||
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
        lower.endsWith('.ts') ||
        lower.endsWith('.html') ||
        lower.endsWith('.css') ||
        lower.endsWith('.toml') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.log') ||
        lower.endsWith('.ini') ||
        lower.endsWith('.cfg') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.java') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.go') ||
        lower.endsWith('.swift') ||
        lower.endsWith('.sql') ||
        lower.endsWith('.properties') ||
        lower.endsWith('.diff') ||
        lower.endsWith('.patch') ||
        lower.endsWith('.conf') ||
        lower.endsWith('.gradle') ||
        lower.endsWith('.dockerfile');
  }

  bool get isImage {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  bool get isVideo {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.flv') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.wmv') ||
        lower.endsWith('.rmvb') ||
        lower.endsWith('.rm') ||
        lower.endsWith('.vob') ||
        lower.endsWith('.ogv') ||
        lower.endsWith('.m2ts') ||
        lower.endsWith('.mts') ||
        lower.endsWith('.f4v') ||
        lower.endsWith('.asf') ||
        lower.endsWith('.divx') ||
        lower.endsWith('.mpg') ||
        lower.endsWith('.mpeg');
  }

  bool get isAudio {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.opus') ||
        lower.endsWith('.wma') ||
        lower.endsWith('.amr') ||
        lower.endsWith('.ape') ||
        lower.endsWith('.alac') ||
        lower.endsWith('.aiff') ||
        lower.endsWith('.mka') ||
        lower.endsWith('.oga') ||
        lower.endsWith('.wv') ||
        lower.endsWith('.mid');
  }

  bool get isMedia => isVideo || isAudio;

  bool get isPdf => name.toLowerCase().endsWith('.pdf');

  bool get isMarkdown {
    final lower = name.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  bool get isHtml {
    final lower = name.toLowerCase();
    return lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.xhtml');
  }

  /// Best-effort MIME type for handing the file to another app.
  String get mimeType {
    final lower = name.toLowerCase();
    const types = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4',
      'm4v': 'video/x-m4v',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'flv': 'video/x-flv',
      '3gp': 'video/3gpp',
      'wmv': 'video/x-ms-wmv',
      'ts': 'video/mp2t',
      'rmvb': 'video/vnd.rn-realvideo',
      'rm': 'application/vnd.rn-realmedia',
      'vob': 'video/dvd',
      'ogv': 'video/ogg',
      'm2ts': 'video/mp2t',
      'mts': 'video/mp2t',
      'f4v': 'video/x-f4v',
      'asf': 'video/x-ms-asf',
      'mpg': 'video/mpeg',
      'mpeg': 'video/mpeg',
      'mp3': 'audio/mpeg',
      'flac': 'audio/flac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'opus': 'audio/opus',
      'wma': 'audio/x-ms-wma',
      'amr': 'audio/amr',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'apk': 'application/vnd.android.package-archive',
      'jar': 'application/java-archive',
      '7z': 'application/x-7z-compressed',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'html': 'text/html',
      'htm': 'text/html',
      'json': 'application/json',
      'xml': 'text/xml',
      'csv': 'text/csv',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    };
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return 'application/octet-stream';
    return types[lower.substring(dot + 1)] ?? 'application/octet-stream';
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
    if (isImage) return Icons.image;
    final lower = name.toLowerCase();
    if (isVideo) return Icons.play_circle_fill;
    if (isAudio) return Icons.music_note;
    if (isArchive) {
      return Icons.archive;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.menu_book;
    }
    if (isText) {
      return Icons.article;
    }
    return Icons.insert_drive_file;
  }

  Color iconColor(BuildContext context) {
    if (isDir) return Theme.of(context).colorScheme.primary;
    if (isArchive) return Colors.amber.shade800;
    if (isImage) return Colors.purple;
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Colors.red;
    if (isVideo) return Colors.deepOrange;
    if (isAudio) return Colors.teal;
    if (isText) return Colors.blueGrey;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}
