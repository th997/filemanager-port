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

  static const Set<String> _archiveExtensions = {
    'zip', 'apk', 'jar', 'tar', 'tgz', '7z',
  };
  static const Set<String> _textExtensions = {
    'txt', 'md', 'markdown', 'json', 'jsonc', 'json5', 'geojson', 'lock', 'yaml', 'yml', 'xml', 'rs', 'dart', 'c', 'cpp',
    'h', 'hpp', 'py', 'js', 'ts', 'html', 'css', 'toml', 'sh', 'log', 'ini',
    'cfg', 'csv', 'java', 'kt', 'go', 'swift', 'sql', 'properties', 'diff',
    'patch', 'conf', 'gradle', 'dockerfile',
  };
  static const Set<String> _imageExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
  };
  static const Set<String> _videoExtensions = {
    'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', '3gp', 'm4v', 'ts', 'wmv',
    'rmvb', 'rm', 'vob', 'ogv', 'm2ts', 'mts', 'f4v', 'asf', 'divx', 'mpg', 'mpeg',
  };
  static const Set<String> _audioExtensions = {
    'mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'opus', 'wma', 'amr', 'ape',
    'alac', 'aiff', 'mka', 'oga', 'wv', 'mid',
  };

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isArchive {
    final ext = extension;
    if (_archiveExtensions.contains(ext)) return true;
    if (ext == 'gz' && name.toLowerCase().endsWith('.tar.gz')) return true;
    return false;
  }

  bool get isText => _textExtensions.contains(extension);
  bool get isImage => _imageExtensions.contains(extension);
  bool get isVideo => _videoExtensions.contains(extension);
  bool get isAudio => _audioExtensions.contains(extension);
  bool get isMedia => isVideo || isAudio;
  bool get isPdf => extension == 'pdf';
  bool get isMarkdown => extension == 'md' || extension == 'markdown';
  bool get isHtml => extension == 'html' || extension == 'htm' || extension == 'xhtml';

  static const Map<String, String> _mimeTypes = {
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
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  /// Best-effort MIME type for handing the file to another app.
  String get mimeType => _mimeTypes[extension] ?? 'application/octet-stream';

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
    final ext = extension;
    if (_imageExtensions.contains(ext)) return Icons.image;
    if (_videoExtensions.contains(ext)) return Icons.play_circle_fill;
    if (_audioExtensions.contains(ext)) return Icons.music_note;
    if (isArchive) return Icons.archive;
    if (ext == 'pdf') return Icons.menu_book;
    if (_textExtensions.contains(ext)) return Icons.article;
    return Icons.insert_drive_file;
  }

  Color iconColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isDir) return scheme.primary;
    // File-type hues, in a light and a dark variant: the mid-tone palette
    // colors that read well on white (purple, blue-grey, amber 800) sink
    // into dark surfaces, so dark mode gets the 200/300-level tints.
    final dark = scheme.brightness == Brightness.dark;
    final ext = extension;
    if (isArchive) {
      return dark ? const Color(0xFFFFB74D) : Colors.amber.shade800;
    }
    if (_imageExtensions.contains(ext)) return dark ? const Color(0xFFCE93D8) : Colors.purple;
    if (ext == 'pdf') {
      return dark ? const Color(0xFFEF9A9A) : Colors.red;
    }
    if (_videoExtensions.contains(ext)) return dark ? const Color(0xFFFFAB91) : Colors.deepOrange;
    if (_audioExtensions.contains(ext)) return dark ? const Color(0xFF80CBC4) : Colors.teal;
    if (_textExtensions.contains(ext)) return dark ? const Color(0xFFB0BEC5) : Colors.blueGrey;
    return scheme.onSurfaceVariant;
  }
}
