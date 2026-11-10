import 'package:flutter/material.dart';

import '../../theme/app_ui_tokens.dart';

/// Unified address bar supporting breadcrumb navigation and text-based path jumping.
class BrowserUnifiedAddressBar extends StatelessWidget {
  final bool isEditingAddress;
  final TextEditingController addressController;
  final ValueChanged<String> onJumpToAddress;
  final VoidCallback onCancelEdit;
  final VoidCallback onStartEdit;
  final String root;
  final String relPath;
  final String rootLabel;
  final List<String> segments;
  final bool canGoBack;
  final VoidCallback? onGoBack;
  final bool canGoForward;
  final VoidCallback? onGoForward;
  final bool canNavigateUp;
  final VoidCallback? onNavigateUp;
  final VoidCallback onRefresh;
  final void Function(String targetRelPath)? onSegmentTap;
  final void Function(String copyText)? onCopyPath;
  final void Function(({String root, List<String> paths}) data, String targetRelPath)? onAcceptDrop;

  const BrowserUnifiedAddressBar({
    super.key,
    required this.isEditingAddress,
    required this.addressController,
    required this.onJumpToAddress,
    required this.onCancelEdit,
    required this.onStartEdit,
    required this.root,
    required this.relPath,
    required this.rootLabel,
    required this.segments,
    required this.canGoBack,
    this.onGoBack,
    required this.canGoForward,
    this.onGoForward,
    required this.canNavigateUp,
    this.onNavigateUp,
    required this.onRefresh,
    this.onSegmentTap,
    this.onCopyPath,
    this.onAcceptDrop,
  });

  @override
  Widget build(BuildContext context) {
    if (isEditingAddress) {
      return Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.link, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: addressController,
                autofocus: true,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Enter path to jump...',
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
                onSubmitted: onJumpToAddress,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward, size: 16, color: Colors.blue),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Jump',
              onPressed: () => onJumpToAddress(addressController.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Cancel',
              onPressed: onCancelEdit,
            ),
          ],
        ),
      );
    }

    final isCompact = MediaQuery.sizeOf(context).width < 600;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: AppUiTokens.borderRadiusMd,
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          if (!isCompact) ...[
            AppIconButton(
              icon: Icons.chevron_left,
              size: 28,
              iconSize: 16,
              tooltip: 'Back in history (Alt+←)',
              onPressed: canGoBack ? onGoBack : null,
            ),
            AppIconButton(
              icon: Icons.chevron_right,
              size: 28,
              iconSize: 16,
              tooltip: 'Forward in history (Alt+→)',
              onPressed: canGoForward ? onGoForward : null,
            ),
          ],
          if (!isCompact || canNavigateUp)
            AppIconButton(
              icon: Icons.arrow_upward,
              size: 28,
              iconSize: 16,
              tooltip: 'Up one level',
              onPressed: canNavigateUp ? onNavigateUp : null,
            ),
          if (!isCompact)
            AppIconButton(
              icon: Icons.refresh,
              size: 28,
              iconSize: 16,
              tooltip: 'Refresh',
              onPressed: onRefresh,
            ),
          if (!isCompact || canNavigateUp)
            Container(
              height: 16,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  DragTarget<({String root, List<String> paths})>(
                    onAcceptWithDetails: (d) => onAcceptDrop?.call(d.data, ''),
                    builder: (ctx, candidate, rejected) => InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => onSegmentTap?.call(''),
                      onLongPress: () => onCopyPath?.call(root),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          rootLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: relPath.isEmpty
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                            fontWeight: relPath.isEmpty ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                    () {
                      final segPath = segments.take(i + 1).join('/');
                      return DragTarget<({String root, List<String> paths})>(
                        onAcceptWithDetails: (d) => onAcceptDrop?.call(d.data, segPath),
                        builder: (ctx, candidate, rejected) => InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => onSegmentTap?.call(segPath),
                          onLongPress: () => onCopyPath?.call(segPath),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Text(
                              segments[i],
                              style: TextStyle(
                                fontSize: 12,
                                color: i == segments.length - 1
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: i == segments.length - 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 15),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: 'Edit address (Cmd/Ctrl+L)',
            onPressed: onStartEdit,
          ),
        ],
      ),
    );
  }
}
