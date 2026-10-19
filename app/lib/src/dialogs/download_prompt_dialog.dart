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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download file?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.sizeText}. This file cannot be previewed while streaming, '
            'so it has to be downloaded first.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text(
            'Save to',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _destination.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              TextButton(
                onPressed: _changeDestination,
                child: const Text('Change'),
              ),
            ],
          ),
        ],
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
