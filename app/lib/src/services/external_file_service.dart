import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../dialogs/share_receiver_dialog.dart';
import '../models/entry_item.dart';
import '../pages/browser_page.dart';
import '../pages/home_page.dart';
import '../pages/image_viewer_page.dart';
import '../pages/media_player_page.dart';
import '../pages/text_editor_page.dart';
import '../rust/api/file_manager.dart';

/// Describes an incoming file-picking request from another app (e.g. Android
/// `ACTION_GET_CONTENT`, `ACTION_PICK`, `ACTION_OPEN_DOCUMENT`, or
/// `org.openintents.action.PICK_FILE`).
class ExternalPickRequest {
  final bool allowMultiple;
  final String mimeType;
  final List<String> extraMimeTypes;
  final bool localOnly;

  const ExternalPickRequest({
    this.allowMultiple = false,
    this.mimeType = '*/*',
    this.extraMimeTypes = const [],
    this.localOnly = false,
  });

  factory ExternalPickRequest.fromMap(Map<Object?, Object?> map) {
    final allowMultiple = map['allowMultiple'] == true;
    final rawMime = (map['mimeType'] as String?)?.trim();
    final mimeType = (rawMime == null || rawMime.isEmpty) ? '*/*' : rawMime;
    final rawExtras = map['extraMimeTypes'];
    final extraMimeTypes = rawExtras is List
        ? rawExtras.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return ExternalPickRequest(
      allowMultiple: allowMultiple,
      mimeType: mimeType,
      extraMimeTypes: extraMimeTypes,
      localOnly: map['localOnly'] == true,
    );
  }

  List<String> get _effectiveMimeTypes {
    if (extraMimeTypes.isNotEmpty) return extraMimeTypes;
    return [mimeType];
  }

  /// Whether the caller narrowed the requested file types beyond `*/*`.
  bool get hasTypeFilter {
    final mimes = _effectiveMimeTypes;
    return mimes.isNotEmpty &&
        !mimes.any((m) => m == '*/*' || m == '*' || m.isEmpty);
  }

  /// Best-effort filename match against the requested MIME type(s).
  bool matchesFileName(String fileName) {
    if (!hasTypeFilter) return true;
    final item = EntryItem(EntryDto(
      name: fileName,
      path: fileName,
      isDir: false,
      isSymlink: false,
      hidden: fileName.startsWith('.'),
    ));
    final ext = item.extension;

    for (final raw in _effectiveMimeTypes) {
      final m = raw.toLowerCase();
      if (m == '*/*' || m == '*') return true;
      if (m.startsWith('image/')) {
        if (m == 'image/*') {
          if (item.isImage || ext == 'svg') return true;
        } else if (_extMatchesSpecificMime(ext, m)) {
          return true;
        }
      } else if (m.startsWith('video/')) {
        if (m == 'video/*') {
          if (item.isVideo) return true;
        } else if (_extMatchesSpecificMime(ext, m)) {
          return true;
        }
      } else if (m.startsWith('audio/')) {
        if (m == 'audio/*') {
          if (item.isAudio) return true;
        } else if (_extMatchesSpecificMime(ext, m)) {
          return true;
        }
      } else if (m.startsWith('text/')) {
        if (m == 'text/*') {
          if (item.isText) return true;
        } else if (_extMatchesSpecificMime(ext, m)) {
          return true;
        }
      } else if (m == 'application/pdf') {
        if (item.isPdf) return true;
      } else if (m == 'application/zip' ||
          m == 'application/x-zip-compressed' ||
          m == 'application/x-7z-compressed' ||
          m == 'application/x-tar' ||
          m == 'application/gzip') {
        if (item.isArchive) return true;
      } else if (_extMatchesSpecificMime(ext, m)) {
        return true;
      }
    }
    return false;
  }

  static bool _extMatchesSpecificMime(String ext, String mime) {
    if (ext.isEmpty) return false;
    switch (mime) {
      case 'image/jpeg':
        return ext == 'jpg' || ext == 'jpeg';
      case 'image/png':
        return ext == 'png';
      case 'image/gif':
        return ext == 'gif';
      case 'image/webp':
        return ext == 'webp';
      case 'image/svg+xml':
        return ext == 'svg';
      case 'text/plain':
        return ext == 'txt' || ext == 'log' || ext == 'md';
      case 'text/markdown':
      case 'text/x-markdown':
        return ext == 'md' || ext == 'markdown';
      case 'text/html':
        return ext == 'html' || ext == 'htm';
      case 'text/csv':
        return ext == 'csv';
      case 'application/json':
        return ext == 'json' || ext == 'jsonc' || ext == 'json5';
      case 'application/xml':
      case 'text/xml':
        return ext == 'xml';
      case 'video/mp4':
        return ext == 'mp4' || ext == 'm4v';
      case 'audio/mpeg':
      case 'audio/mp3':
        return ext == 'mp3';
      case 'audio/wav':
      case 'audio/x-wav':
        return ext == 'wav';
      default:
        return mime.endsWith('/$ext') || mime.endsWith('+$ext');
    }
  }
}

class ExternalFileService {
  ExternalFileService._();
  static final ExternalFileService instance = ExternalFileService._();

  static const _channel = MethodChannel('com.github.th997.filemanager/open_file');
  GlobalKey<NavigatorState>? _navKey;
  BuildContext? get navContext => _navKey?.currentContext;
  bool _initialized = false;
  bool _pickInProgress = false;
  String? _lastOpenedPath;
  DateTime? _lastOpenedTime;

  void init(GlobalKey<NavigatorState> navKey, {List<String>? initialArgs}) {
    if (_initialized) return;
    _initialized = true;
    _navKey = navKey;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _handlePath(path);
        }
      } else if (call.method == 'onPickRequest') {
        final raw = call.arguments;
        if (raw is Map) {
          _handlePickRequest(ExternalPickRequest.fromMap(raw));
        }
      } else if (call.method == 'onShareReceived') {
        final args = call.arguments;
        if (args is Map) {
          final rawPaths = args['paths'];
          if (rawPaths is List) {
            final paths = rawPaths.whereType<String>().toList();
            if (paths.isNotEmpty) {
              _handleShareReceived(paths);
            }
          }
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. Check native channel initial pick request (e.g. Android GET_CONTENT)
      try {
        final pickReq = await _channel.invokeMethod<dynamic>('getInitialPickRequest');
        if (pickReq is Map) {
          _handlePickRequest(ExternalPickRequest.fromMap(pickReq));
          return;
        }
      } catch (_) {}

      // 2. Check native channel initial share request (e.g. Android ACTION_SEND / ACTION_SEND_MULTIPLE)
      try {
        final initialShares = await _channel.invokeMethod<dynamic>('getInitialShareRequest');
        if (initialShares is List) {
          final paths = initialShares.whereType<String>().toList();
          if (paths.isNotEmpty) {
            _handleShareReceived(paths);
            return;
          }
        }
      } catch (_) {}

      // 3. Check CLI args (desktop)
      if (initialArgs != null && initialArgs.isNotEmpty) {
        final validPaths = <String>[];
        for (final arg in initialArgs) {
          if (arg.startsWith('-')) continue;
          final cleaned = cleanPath(arg);
          if (cleaned.isEmpty) continue;
          final f = File(cleaned);
          final d = Directory(cleaned);
          if (f.existsSync()) {
            validPaths.add(f.absolute.path);
          } else if (d.existsSync()) {
            validPaths.add(d.absolute.path);
          }
        }
        if (validPaths.length > 1) {
          _handleShareReceived(validPaths);
          return;
        } else if (validPaths.length == 1) {
          _handlePath(validPaths.first);
          return;
        }
      }

      // 4. Check native channel initial file
      try {
        final initial = await _channel.invokeMethod<String>('getInitialFile');
        if (initial != null && initial.isNotEmpty) {
          _handlePath(initial);
        }
      } catch (_) {}
    });
  }

  void openFile(String filePath) {
    _handlePath(filePath);
  }

  void openFiles(List<String> filePaths) {
    final valid = filePaths.map(cleanPath).where((p) => p.isNotEmpty).toList();
    if (valid.isEmpty) return;
    if (valid.length == 1) {
      _handlePath(valid.first);
      return;
    }

    // Check if all are images
    final allImages = valid.every((f) =>
        EntryItem.isImageExtension(p.extension(f).replaceFirst('.', '').toLowerCase()));
    if (allImages) {
      final nav = _navKey?.currentState;
      if (nav != null) {
        final siblings = valid.map((f) => ImageViewerEntry(
          name: p.basename(f),
          localPath: f,
        )).toList();
        nav.push(
          MaterialPageRoute(
            builder: (_) => ImageViewerPage(
              filePath: valid.first,
              fileName: p.basename(valid.first),
              siblings: siblings,
              initialIndex: 0,
            ),
          ),
        );
        return;
      }
    }

    // Check if all are media (audio or video)
    final allMedia = valid.every((f) {
      final ext = p.extension(f).replaceFirst('.', '').toLowerCase();
      return EntryItem.isVideoExtension(ext) || EntryItem.isAudioExtension(ext);
    });
    if (allMedia) {
      final nav = _navKey?.currentState;
      if (nav != null) {
        final firstItem = EntryItem(EntryDto(
          name: p.basename(valid.first),
          path: valid.first,
          isDir: false,
          isSymlink: false,
          hidden: false,
        ));
        final playlist = valid.map((f) => MediaTrack(
          path: p.basename(f),
          fileName: p.basename(f),
          isAudio: EntryItem.isAudioExtension(p.extension(f).replaceFirst('.', '').toLowerCase()),
        )).toList();
        nav.push(
          MaterialPageRoute(
            builder: (_) => MediaPlayerPage(
              root: p.dirname(valid.first),
              path: p.basename(valid.first),
              fileName: p.basename(valid.first),
              isAudio: firstItem.isAudio,
              playlist: playlist,
              startIndex: 0,
            ),
          ),
        );
        return;
      }
    }

    _handlePath(valid.first);
  }

  void handleShareReceived(List<String> paths) {
    _handleShareReceived(paths);
  }

  void _handleShareReceived(List<String> paths) {
    final valid = paths.map(cleanPath).where((p) => p.isNotEmpty).toList();
    if (valid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showShareDialog(valid);
    });
  }

  void _showShareDialog(List<String> paths) {
    final nav = _navKey?.currentState;
    final ctx = nav?.context;
    if (ctx == null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _showShareDialog(paths);
      });
      return;
    }
    showShareReceiverDialog(context: ctx, filePaths: paths);
  }

  Future<void> completePickRequest(List<String> paths) async {
    try {
      await _channel.invokeMethod<bool>('completePickRequest', {'paths': paths});
    } catch (_) {}
  }

  Future<void> cancelPickRequest() async {
    try {
      await _channel.invokeMethod<bool>('cancelPickRequest');
    } catch (_) {}
  }

  void _handlePickRequest(ExternalPickRequest request) {
    // singleTop reuses one activity, so a concurrent second pick cannot be
    // served; drop it instead of corrupting the in-flight pick.
    if (_pickInProgress) return;
    _pickInProgress = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routePickRequest(request);
    });
  }

  Future<void> _routePickRequest(ExternalPickRequest request) async {
    final nav = _navKey?.currentState;
    if (nav == null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _routePickRequest(request);
      });
      return;
    }

    try {
      final picked = await nav.push<List<String>>(
        MaterialPageRoute(
          builder: (_) => HomePage(
            pickRequest: request,
          ),
        ),
      );
      if (picked != null && picked.isNotEmpty) {
        await completePickRequest(picked);
      } else {
        await cancelPickRequest();
      }
    } finally {
      _pickInProgress = false;
    }
  }

  static String cleanPath(String rawPath) {
    var path = rawPath.trim();
    if (path.startsWith('file://')) {
      final uri = Uri.tryParse(path);
      if (uri != null) {
        path = uri.toFilePath();
      } else {
        path = path.substring(7);
      }
    }
    return path;
  }

  void _handlePath(String rawPath) {
    final path = cleanPath(rawPath);

    if (path.isEmpty) return;

    // Debounce duplicate events within 1 second
    final now = DateTime.now();
    if (_lastOpenedPath == path &&
        _lastOpenedTime != null &&
        now.difference(_lastOpenedTime!) < const Duration(seconds: 1)) {
      return;
    }
    _lastOpenedPath = path;
    _lastOpenedTime = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routePath(path);
    });
  }

  void _routePath(String filePath) {
    final nav = _navKey?.currentState;
    if (nav == null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _routePath(filePath);
      });
      return;
    }

    final isDir = Directory(filePath).existsSync();
    if (isDir) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => BrowserPage(
            initialRoot: filePath,
            initialPath: '',
          ),
        ),
      );
      return;
    }

    final fileName = p.basename(filePath);
    final parentDir = p.dirname(filePath);

    final item = EntryItem(EntryDto(
      name: fileName,
      path: fileName,
      isDir: false,
      isSymlink: false,
      hidden: fileName.startsWith('.'),
    ));

    if (item.isArchive) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => BrowserPage(
            initialRoot: 'archive://$filePath',
            initialPath: '',
          ),
        ),
      );
      return;
    }

    if (item.isText || item.isMarkdown || item.isHtml) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: parentDir,
            path: fileName,
            fileName: fileName,
            readOnly: false,
          ),
        ),
      );
      return;
    }

    if (item.isMedia) {
      List<MediaTrack> playlist = [
        MediaTrack(
          path: fileName,
          fileName: fileName,
          isAudio: item.isAudio,
        ),
      ];
      int startIndex = 0;
      try {
        final dir = Directory(parentDir);
        if (dir.existsSync()) {
          final files = dir.listSync(followLinks: false).whereType<File>().where((f) {
            final name = p.basename(f.path);
            if (name.startsWith('.')) return false;
            final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
            return item.isAudio ? EntryItem.isAudioExtension(ext) : EntryItem.isVideoExtension(ext);
          }).toList();
          if (files.isNotEmpty) {
            files.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
            playlist = files.map((f) => MediaTrack(
              path: p.basename(f.path),
              fileName: p.basename(f.path),
              isAudio: item.isAudio,
            )).toList();
            final idx = playlist.indexWhere((t) => t.fileName == fileName);
            startIndex = idx < 0 ? 0 : idx;
          }
        }
      } catch (_) {}

      nav.push(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: parentDir,
            path: fileName,
            fileName: fileName,
            isAudio: item.isAudio,
            playlist: playlist,
            startIndex: startIndex,
          ),
        ),
      );
      return;
    }

    if (item.isImage) {
      List<ImageViewerEntry> siblings = [
        ImageViewerEntry(
          name: fileName,
          localPath: filePath,
        ),
      ];
      int initialIndex = 0;
      try {
        final dir = Directory(parentDir);
        if (dir.existsSync()) {
          final files = dir.listSync(followLinks: false).whereType<File>().where((f) {
            final name = p.basename(f.path);
            if (name.startsWith('.')) return false;
            final ext = p.extension(f.path).replaceFirst('.', '').toLowerCase();
            return EntryItem.isImageExtension(ext);
          }).toList();
          if (files.isNotEmpty) {
            files.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
            siblings = files.map((f) => ImageViewerEntry(
              name: p.basename(f.path),
              localPath: f.path,
            )).toList();
            final idx = siblings.indexWhere((e) => e.localPath == filePath || e.name == fileName);
            initialIndex = idx < 0 ? 0 : idx;
          }
        }
      } catch (_) {}

      nav.push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: filePath,
            fileName: fileName,
            siblings: siblings,
            initialIndex: initialIndex,
          ),
        ),
      );
      return;
    }

    OpenFilex.open(filePath);
  }
}
