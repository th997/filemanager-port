import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom action bar displayed when multi-selection is active or clipboard has items.
class BrowserBottomActionBar extends StatelessWidget {
  final bool isSelecting;
  final bool isRemoteOrArchive;
  final bool canWrite;
  final bool canArchive;
  final int selectedCount;
  final BigInt selectedBytes;
  final String Function(BigInt) formatBytes;
  final int? clipboardCount;
  final VoidCallback? onDownload;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onInfo;
  final VoidCallback? onCompress;
  final VoidCallback? onPaste;
  final VoidCallback? onClearClipboard;

  const BrowserBottomActionBar({
    super.key,
    required this.isSelecting,
    required this.isRemoteOrArchive,
    required this.canWrite,
    required this.canArchive,
    required this.selectedCount,
    required this.selectedBytes,
    required this.formatBytes,
    this.clipboardCount,
    this.onDownload,
    this.onCopy,
    this.onCut,
    this.onDelete,
    this.onRename,
    this.onInfo,
    this.onCompress,
    this.onPaste,
    this.onClearClipboard,
  });

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectionLabel = selectedBytes > BigInt.zero
        ? '$selectedCount selected (${formatBytes(selectedBytes)})'
        : '$selectedCount selected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (isSelecting) ...[
                    if (isRemoteOrArchive)
                      _actionButton(
                        icon: Icons.download,
                        label: 'Download',
                        onTap: onDownload,
                        color: Colors.blue,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        selectionLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    _actionButton(
                      icon: Icons.copy,
                      label: 'Copy',
                      onTap: onCopy,
                    ),
                    if (selectedCount == 1)
                      _actionButton(
                        icon: Icons.info_outline,
                        label: 'Info',
                        onTap: onInfo,
                      ),
                    if (canWrite) ...[
                      _actionButton(
                        icon: Icons.cut,
                        label: 'Cut',
                        onTap: onCut,
                      ),
                      _actionButton(
                        icon: Icons.delete,
                        label: 'Delete',
                        onTap: onDelete,
                        color: Colors.red,
                      ),
                      if (selectedCount == 1)
                        _actionButton(
                          icon: Icons.edit,
                          label: 'Rename',
                          onTap: onRename,
                        ),
                      if (canArchive)
                        _actionButton(
                          icon: Icons.archive,
                          label: 'Zip',
                          onTap: onCompress,
                        ),
                    ],
                  ],
                  if (clipboardCount != null && !isSelecting && canWrite) ...[
                    _actionButton(
                      icon: Icons.paste,
                      label: 'Paste ($clipboardCount)',
                      onTap: onPaste,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    _actionButton(
                      icon: Icons.close,
                      label: 'Clear',
                      onTap: onClearClipboard,
                      color: Colors.grey,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
