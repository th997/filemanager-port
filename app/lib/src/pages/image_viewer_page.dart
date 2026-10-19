import 'dart:io';
import 'package:flutter/material.dart';

class ImageViewerPage extends StatelessWidget {
  final String filePath;
  final String fileName;

  const ImageViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(fileName),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
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
    );
  }
}
