import 'package:flutter/material.dart';

import '../services/platform_paths.dart';
import 'folder_picker_dialog.dart';

/// Outcome of the large-file download prompt.
class DownloadChoice {
  final PickedFolder destination;

  const DownloadChoice(this.destination);
}

/// Ask before pulling a large remote or archive file into local storage.
///
/// Streaming previews are not offered for these types, so the alternative to
/// downloading is not opening the file at all. The default destination is the
/// platform Downloads folder; the user can pick another one.
class DownloadPromptDialog extends StatefulWidget {
  final String fileName;
  final String sizeText;
  final BigInt? sizeBytes;

  const DownloadPromptDialog({
    super.key,
    required this.fileName,
    required this.sizeText,
    required this.sizeBytes,
  });

  static Future<DownloadChoice?> show(
    BuildContext context, {
    required String fileName,
    required String sizeText,
    required BigInt? sizeBytes,
  }) {
    return showDialog<DownloadChoice>(
      context: context,
      builder: (_) => DownloadPromptDialog(
        fileName: fileName,
        sizeText: sizeText,
        sizeBytes: sizeBytes,
      ),
    );
  }

  @override
  State<DownloadPromptDialog> createState() => _DownloadPromptDialogState();
}

class _DownloadPromptDialogState extends State<DownloadPromptDialog> {
  late PickedFolder _destination;

  @override
  void initState() {
    super.initState();
    _destination = _defaultDestination();
  }

  PickedFolder _defaultDestination() {
    final targets = PlatformPaths.quickTargets();
    if (targets.isNotEmpty) {
      final preferred = targets.firstWhere(
        (t) => t.name.toLowerCase().startsWith('download'),
        orElse: () => targets.first,
      );
      return PickedFolder(root: preferred.root, relPath: preferred.relPath);
    }
    final root = PlatformPaths.defaultRoot();
    return PickedFolder(root: root, relPath: '');
  }

  Future<void> _changeDestination() async {
    final picked = await FolderPickerDialog.show(
      context,
      title: 'Choose download folder',
      initialRoot: _destination.root,
      initialPath: _destination.relPath,
    );
    if (picked != null && mounted) {
      setState(() => _destination = picked);
    }
  }

  IconData get _fileIcon {
    final lower = widget.fileName.toLowerCase();
    if (lower.endsWith('.zip') || lower.endsWith('.tar') || lower.endsWith('.gz') || lower.endsWith('.7z')) {
      return Icons.folder_zip;
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov')) {
      return Icons.video_file;
    }
    if (lower.endsWith('.mp3') || lower.endsWith('.flac') || lower.endsWith('.wav') || lower.endsWith('.m4a')) {
      return Icons.audio_file;
    }
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp')) {
      return Icons.image;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download file?'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_fileIcon, size: 28, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.sizeText,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'This file cannot be previewed while streaming, so it has to be downloaded first.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            const Text(
              'Save destination',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _destination.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                  TextButton(
                    onPressed: _changeDestination,
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(DownloadChoice(_destination)),
          child: const Text('Download'),
        ),
      ],
    );
  }
}
