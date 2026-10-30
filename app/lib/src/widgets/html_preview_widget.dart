import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../pages/image_viewer_page.dart';
import '../rust/api/servers.dart';
import '../services/path_utils.dart';

class HtmlPreviewWidget extends StatefulWidget {
  final String root;
  final String path;
  final String rawHtml;
  final bool isDirty;
  final double fontSize;
  final void Function(WebViewController controller)? onControllerCreated;
  final VoidCallback? onOpenInBrowser;

  const HtmlPreviewWidget({
    super.key,
    required this.root,
    required this.path,
    required this.rawHtml,
    this.isDirty = false,
    this.fontSize = 13.0,
    this.onControllerCreated,
    this.onOpenInBrowser,
  });

  @override
  State<HtmlPreviewWidget> createState() => _HtmlPreviewWidgetState();
}

class _HtmlPreviewWidgetState extends State<HtmlPreviewWidget> {
  WebViewController? _controller;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<double> _progressNotifier = ValueNotifier<double>(0.0);
  String? _streamUrl;
  String? _error;

  bool get _isWebViewSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    if (_isWebViewSupported) {
      _initWebView();
    } else {
      _loadingNotifier.value = false;
      _initBaseUrl();
    }
  }

  Future<void> _initBaseUrl() async {
    try {
      final base = await startMediaStream(root: widget.root);
      final cleanPath = widget.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
      final encodedSegments = cleanPath.split('/').map(Uri.encodeComponent).join('/');
      if (mounted) {
        setState(() {
          _streamUrl = '$base$encodedSegments';
        });
      }
    } catch (_) {}
  }

  Uri? _resolveBaseUrl() {
    if (_streamUrl != null && _streamUrl!.isNotEmpty) {
      return Uri.tryParse(_streamUrl!);
    }
    if (isNativeRoot(widget.root)) {
      try {
        final fullPath = joinNative(widget.root, widget.path);
        final dir = File(fullPath).parent.path;
        return Uri.file(dir.endsWith('/') ? dir : '$dir/');
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _handleUrlTap(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (Platform.isLinux) {
      try {
        await Process.start('gio', ['open', url], mode: ProcessStartMode.detached);
        return true;
      } catch (_) {
        try {
          await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
          return true;
        } catch (_) {}
      }
    }
    try {
      final res = await OpenFilex.open(url);
      return res.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _loadingNotifier.dispose();
    _progressNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HtmlPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isWebViewSupported) {
      if (widget.root != oldWidget.root || widget.path != oldWidget.path) {
        _initBaseUrl();
      }
      return;
    }
    if (_controller == null) return;

    if (widget.root != oldWidget.root || widget.path != oldWidget.path) {
      _initWebView();
    } else if (widget.isDirty != oldWidget.isDirty ||
        (widget.isDirty && widget.rawHtml != oldWidget.rawHtml)) {
      _loadContent();
    }
  }

  Future<void> _initWebView() async {
    setState(() {
      _error = null;
    });
    _loadingNotifier.value = true;
    _progressNotifier.value = 0.0;

    try {
      String? fullUrl;
      try {
        final base = await startMediaStream(root: widget.root);
        final cleanPath = widget.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^/+'), '');
        final encodedSegments = cleanPath.split('/').map(Uri.encodeComponent).join('/');
        fullUrl = '$base$encodedSegments';
      } catch (_) {}

      _streamUrl = fullUrl;

      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'ImagePreviewChannel',
          onMessageReceived: (message) {
            _handleImageClick(message.message);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              _progressNotifier.value = p / 100.0;
            },
            onPageStarted: (_) {
              _loadingNotifier.value = true;
            },
            onPageFinished: (_) {
              _loadingNotifier.value = false;
              _progressNotifier.value = 1.0;
              _injectScripts(controller);
            },
            onWebResourceError: (err) {
              if (err.isForMainFrame ?? true) {
                if (mounted) {
                  setState(() {
                    _error = err.description;
                  });
                  _loadingNotifier.value = false;
                }
              }
            },
          ),
        );

      if (Platform.isIOS && controller.platform is WebKitWebViewController) {
        (controller.platform as WebKitWebViewController)
            .setAllowsBackForwardNavigationGestures(true);
      }

      setState(() {
        _controller = controller;
      });
      widget.onControllerCreated?.call(controller);

      await _loadContent();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        _loadingNotifier.value = false;
      }
    }
  }

  void _injectScripts(WebViewController controller) {
    controller.runJavaScript('''
      (function() {
        if (!document.querySelector('meta[name="viewport"]')) {
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=5.0';
          document.head.appendChild(meta);
        }

        function bindImages() {
          var imgs = document.querySelectorAll('img');
          for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            if (img.dataset.clickBound === 'true') continue;
            img.dataset.clickBound = 'true';
            img.style.cursor = 'pointer';
            img.addEventListener('click', function(e) {
              e.preventDefault();
              e.stopPropagation();
              var all = document.querySelectorAll('img');
              var list = [];
              var currentIdx = 0;
              for (var j = 0; j < all.length; j++) {
                var it = all[j];
                var s = it.currentSrc || it.src || '';
                if (s) {
                  if (it === this) {
                    currentIdx = list.length;
                  }
                  list.push({
                    src: s,
                    alt: it.alt || it.title || ''
                  });
                }
              }
              var payload = JSON.stringify({
                index: currentIdx,
                images: list
              });
              var ch = window.ImagePreviewChannel || (typeof ImagePreviewChannel !== 'undefined' ? ImagePreviewChannel : null);
              if (ch && ch.postMessage) {
                ch.postMessage(payload);
              }
            });
          }
        }

        bindImages();
        if (window.MutationObserver) {
          var obs = new MutationObserver(bindImages);
          obs.observe(document.body || document.documentElement, { childList: true, subtree: true });
        }
      })();
    ''').catchError((_) {});
  }

  Future<void> _loadContent() async {
    final controller = _controller;
    if (controller == null) return;

    final url = _streamUrl;
    if (widget.rawHtml.isNotEmpty) {
      await controller.loadHtmlString(widget.rawHtml, baseUrl: url);
    } else if (url != null && url.isNotEmpty) {
      await controller.loadRequest(Uri.parse(url));
    }
  }

  String _resolveRelativePath(String basePath, String relative) {
    if (relative.startsWith('/') ||
        relative.startsWith('http://') ||
        relative.startsWith('https://')) {
      return relative;
    }
    final baseDir = basePath.contains('/')
        ? basePath.substring(0, basePath.lastIndexOf('/'))
        : '';
    final parts = [
      ...baseDir.split('/').where((s) => s.isNotEmpty),
      ...relative.split('/'),
    ];
    final resolved = <String>[];
    for (final part in parts) {
      if (part == '.' || part.isEmpty) continue;
      if (part == '..') {
        if (resolved.isNotEmpty) resolved.removeLast();
      } else {
        resolved.add(part);
      }
    }
    return resolved.join('/');
  }

  Future<ImageViewerEntry?> _resolveImageEntry(
    String src,
    String alt,
    int index,
  ) async {
    if (src.startsWith('data:image/')) {
      final comma = src.indexOf(',');
      if (comma != -1) {
        try {
          final mimePart =
              src.substring(11, comma).split(';').first.toLowerCase();
          final ext = mimePart == 'jpeg'
              ? 'jpg'
              : (mimePart.isEmpty ? 'png' : mimePart);
          final base64Data = src.substring(comma + 1).trim();
          final bytes = base64Decode(base64Data);
          final tempDir = await getTemporaryDirectory();
          final name = alt.isNotEmpty ? alt : 'image_$index.$ext';
          final file = File('${tempDir.path}/html_b64_${bytes.hashCode}.$ext');
          if (!file.existsSync()) {
            await file.writeAsBytes(bytes);
          }
          return ImageViewerEntry(name: name, localPath: file.path);
        } catch (_) {}
      }
      return null;
    }

    if (src.startsWith('file://')) {
      try {
        final fileUri = Uri.parse(src);
        final path = fileUri.toFilePath();
        return ImageViewerEntry(
          name: alt.isNotEmpty ? alt : path.split('/').last,
          localPath: path,
        );
      } catch (_) {}
    }

    final uri = Uri.tryParse(src);
    if (uri != null) {
      if ((uri.host == '127.0.0.1' || uri.host == 'localhost') &&
          uri.pathSegments.length >= 3 &&
          uri.pathSegments[0] == 'stream') {
        final relSegments =
            uri.pathSegments.skip(2).map(Uri.decodeComponent).toList();
        final relPath = relSegments.join('/');
        final name = alt.isNotEmpty
            ? alt
            : (relSegments.isNotEmpty ? relSegments.last : 'image');
        if (isNativeRoot(widget.root)) {
          return ImageViewerEntry(
            name: name,
            localPath: joinNative(widget.root, relPath),
          );
        } else {
          return ImageViewerEntry(
            name: name,
            root: widget.root,
            remotePath: relPath,
          );
        }
      }

      if (uri.scheme == 'http' || uri.scheme == 'https') {
        final name = alt.isNotEmpty
            ? alt
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'image.png');
        return ImageViewerEntry(
          name: name,
          resolvePath: () async {
            final tempDir = await getTemporaryDirectory();
            final ext = uri.pathSegments.isNotEmpty &&
                    uri.pathSegments.last.contains('.')
                ? uri.pathSegments.last.split('.').last.split('?').first
                : 'png';
            final file =
                File('${tempDir.path}/web_${uri.toString().hashCode}.$ext');
            if (file.existsSync()) return file.path;
            final client = HttpClient();
            try {
              final request = await client.getUrl(uri);
              final response = await request.close();
              if (response.statusCode == 200) {
                final bytes = await consolidateHttpClientResponseBytes(response);
                await file.writeAsBytes(bytes);
                return file.path;
              }
            } finally {
              client.close();
            }
            return null;
          },
        );
      }
    }

    final resolved = _resolveRelativePath(widget.path, src);
    final name = alt.isNotEmpty ? alt : resolved.split('/').last;
    if (isNativeRoot(widget.root)) {
      return ImageViewerEntry(
        name: name,
        localPath: joinNative(widget.root, resolved),
      );
    } else {
      return ImageViewerEntry(
        name: name,
        root: widget.root,
        remotePath: resolved,
      );
    }
  }

  Future<void> _handleImageClick(String message) async {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;
      final initialIndex = (data['index'] as num?)?.toInt() ?? 0;
      final rawImages =
          (data['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (rawImages.isEmpty) return;

      final siblings = <ImageViewerEntry>[];
      int? matchedIndex;
      for (int i = 0; i < rawImages.length; i++) {
        final img = rawImages[i];
        final src = (img['src'] as String?)?.trim() ?? '';
        final alt = (img['alt'] as String?)?.trim() ?? '';
        if (src.isEmpty) continue;
        final entry = await _resolveImageEntry(src, alt, i);
        if (entry != null) {
          if (i == initialIndex) {
            matchedIndex = siblings.length;
          }
          siblings.add(entry);
        }
      }

      if (siblings.isEmpty || !mounted) return;
      final safeIndex =
          (matchedIndex ?? initialIndex).clamp(0, siblings.length - 1);
      final current = siblings[safeIndex];

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: current.localPath ?? '',
            fileName: current.name,
            siblings: siblings,
            initialIndex: safeIndex,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Failed to preview image: $e');
    }
  }

  Future<void> _openSingleImage(String src, String alt) async {
    final entry = await _resolveImageEntry(src, alt, 0);
    if (entry == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          filePath: entry.localPath ?? '',
          fileName: entry.name,
          siblings: [entry],
          initialIndex: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWebViewSupported) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
      final textColor = isDark ? const Color(0xFFE0E0E0) : Colors.black87;

      return Container(
        color: bgColor,
        width: double.infinity,
        height: double.infinity,
        child: Column(
          children: [
            if (widget.onOpenInBrowser != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2D32) : const Color(0xFFF1F5F9),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF3E4451) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '桌面端为精简 HTML 预览。如需完整的 JS/CSS 样式效果，可在浏览器中打开。',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: widget.onOpenInBrowser,
                      icon: const Icon(Icons.open_in_browser, size: 16),
                      label: const Text('用浏览器打开', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: HtmlWidget(
                  widget.rawHtml,
                  baseUrl: _resolveBaseUrl(),
                  textStyle: TextStyle(
                    fontSize: widget.fontSize + 2,
                    color: textColor,
                  ),
                  onTapImage: (imageMetadata) {
                    final src = imageMetadata.sources.firstOrNull?.url;
                    if (src != null && src.isNotEmpty) {
                      _openSingleImage(src, imageMetadata.alt ?? '');
                    }
                  },
                  onTapUrl: _handleUrlTap,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load webpage: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _initWebView,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null)
          WebViewWidget(
            key: const ValueKey('html_webview_widget'),
            controller: _controller!,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                EagerGestureRecognizer.new,
              ),
            },
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: _loadingNotifier,
            builder: (context, loading, _) {
              if (!loading) return const SizedBox.shrink();
              return ValueListenableBuilder<double>(
                valueListenable: _progressNotifier,
                builder: (context, progress, _) {
                  if (progress >= 1.0) return const SizedBox.shrink();
                  return LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 2.5,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
