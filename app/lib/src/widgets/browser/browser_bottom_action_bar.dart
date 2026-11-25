import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:filemanager/l10n/app_localizations.dart';

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
  final VoidCallback? onCompareDiff;
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
    this.onCompareDiff,
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final disabledColor = scheme.onSurface.withValues(alpha: 0.38);
    final hasSelection = selectedCount > 0;
    final selectionLabel = selectedBytes > BigInt.zero
        ? l10n.selectedCountBytesLabel(selectedCount, formatBytes(selectedBytes))
        : l10n.selectedCountLabel(selectedCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
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
                        label: l10n.download,
                        onTap: hasSelection ? onDownload : null,
                        color: hasSelection ? Colors.blue : disabledColor,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        selectionLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    _actionButton(
                      icon: Icons.copy,
                      label: l10n.copy,
                      onTap: hasSelection ? onCopy : null,
                      color: hasSelection ? null : disabledColor,
                    ),
                    if (selectedCount >= 1)
                      _actionButton(
                        icon: Icons.info_outline,
                        label: l10n.actionInfo,
                        onTap: onInfo,
                      ),
                    if (selectedCount == 2 && onCompareDiff != null)
                      _actionButton(
                        icon: Icons.compare_arrows,
                        label: l10n.compareDiff,
                        onTap: onCompareDiff,
                      ),
                    if (canWrite) ...[
                      _actionButton(
                        icon: Icons.cut,
                        label: l10n.cut,
                        onTap: hasSelection ? onCut : null,
                        color: hasSelection ? null : disabledColor,
                      ),
                      _actionButton(
                        icon: Icons.delete,
                        label: l10n.delete,
                        onTap: hasSelection ? onDelete : null,
                        color: hasSelection ? scheme.error : disabledColor,
                      ),
                      if (selectedCount >= 1)
                        _actionButton(
                          icon: selectedCount > 1
                              ? Icons.drive_file_rename_outline
                              : Icons.edit,
                          label: selectedCount > 1
                              ? l10n.batchRename
                              : l10n.rename,
                          onTap: onRename,
                        ),
                      if (canArchive)
                        _actionButton(
                          icon: Icons.archive,
                          label: l10n.compress,
                          onTap: hasSelection ? onCompress : null,
                          color: hasSelection ? null : disabledColor,
                        ),
                    ],
                  ],
                  if (clipboardCount != null && !isSelecting) ...[
                    if (canWrite)
                      _actionButton(
                        icon: Icons.paste,
                        label: l10n.pasteCount(clipboardCount!),
                        onTap: onPaste,
                        color: scheme.primary,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          l10n.clipboardReadOnlyHint(clipboardCount!),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    _actionButton(
                      icon: Icons.close,
                      label: l10n.clear,
                      onTap: onClearClipboard,
                      color: scheme.onSurfaceVariant,
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
