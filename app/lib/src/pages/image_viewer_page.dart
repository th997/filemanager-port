import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class ImageViewerPage extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ImageViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final TransformationController _transformationController = TransformationController();
  int _quarterTurns = 0;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetView() {
    setState(() {
      _transformationController.value = Matrix4.identity();
      _quarterTurns = 0;
    });
  }

  void _zoomBy(double factor) {
    final current = _transformationController.value;
    final scale = current.getMaxScaleOnAxis();
    final newScale = (scale * factor).clamp(0.2, 6.0);
    final ratio = newScale / scale;
    setState(() {
      _transformationController.value = current.clone()..scaleByDouble(ratio, ratio, 1.0, 1.0);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _showImageDetails() async {
    final file = File(widget.filePath);
    if (!file.existsSync()) return;

    final stat = file.statSync();
    Size? dimensions;
    try {
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      dimensions = Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Image Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Name', widget.fileName),
            if (dimensions != null)
              _detailRow('Dimensions', '${dimensions.width.toInt()} × ${dimensions.height.toInt()} px'),
            _detailRow('Size', _formatSize(stat.size)),
            _detailRow('Modified', stat.modified.toString().split('.').first),
            _detailRow('Path', widget.filePath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.filePath);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.add): () => _zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.digit0): _resetView,
        const SingleActivator(LogicalKeyboardKey.numpad0): _resetView,
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          setState(() => _quarterTurns = (_quarterTurns + 1) % 4);
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            backgroundColor: Colors.black87,
            foregroundColor: Colors.white,
            title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                icon: const Icon(Icons.zoom_in),
                tooltip: 'Zoom in (+)',
                onPressed: () => _zoomBy(1.25),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                tooltip: 'Zoom out (-)',
                onPressed: () => _zoomBy(0.8),
              ),
              IconButton(
                icon: const Icon(Icons.rotate_right),
                tooltip: 'Rotate 90° (R)',
                onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out_map),
                tooltip: 'Reset zoom (0)',
                onPressed: _resetView,
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share image',
                onPressed: () {
                  SharePlus.instance.share(
                    ShareParams(files: [XFile(widget.filePath)]),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Details',
                onPressed: _showImageDetails,
              ),
            ],
          ),
          body: Center(
            child: GestureDetector(
              onDoubleTap: _resetView,
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.2,
                maxScale: 6.0,
                child: RotatedBox(
                  quarterTurns: _quarterTurns,
                  child: file.existsSync()
                      ? Image.file(
                          file,
                          fit: BoxFit.contain,
                          errorBuilder: (ctx, err, stack) => const Center(
                            child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
                          ),
                        )
                      : const Center(
                          child: Text('Image file not found locally', style: TextStyle(color: Colors.white70)),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
