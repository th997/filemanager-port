import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../models/entry_item.dart';
import '../pages/browser_page.dart';
import '../pages/image_viewer_page.dart';
import '../pages/media_player_page.dart';
import '../pages/text_editor_page.dart';
import '../rust/api/file_manager.dart';

class ExternalFileService {
  ExternalFileService._();
  static final ExternalFileService instance = ExternalFileService._();

  static const _channel = MethodChannel('com.github.th997.filemanager/open_file');
  GlobalKey<NavigatorState>? _navKey;
  bool _initialized = false;
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
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 1. Check CLI args first (desktop)
      if (initialArgs != null && initialArgs.isNotEmpty) {
        for (final arg in initialArgs) {
          if (arg.startsWith('-')) continue;
          final f = File(arg);
          final d = Directory(arg);
          if (f.existsSync() || d.existsSync()) {
            _handlePath(arg);
            return;
          }
        }
      }

      // 2. Check native channel initial file
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
      nav.push(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: parentDir,
            path: fileName,
            fileName: fileName,
            isAudio: item.isAudio,
            playlist: [
              MediaTrack(
                path: fileName,
                fileName: fileName,
                isAudio: item.isAudio,
              ),
            ],
            startIndex: 0,
          ),
        ),
      );
      return;
    }

    if (item.isImage) {
      nav.push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: filePath,
            fileName: fileName,
            siblings: [
              ImageViewerEntry(
                name: fileName,
                localPath: filePath,
              ),
            ],
            initialIndex: 0,
          ),
        ),
      );
      return;
    }

    OpenFilex.open(filePath);
  }
}
