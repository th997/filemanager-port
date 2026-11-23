import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../theme/app_ui_tokens.dart';
import 'browser_pane.dart';

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
    final l10n = AppLocalizations.of(context);
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
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).enterPathToJumpHint,
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
              tooltip: l10n.toolbarJump,
              onPressed: () => onJumpToAddress(addressController.text),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: l10n.cancel,
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
              tooltip: l10n.toolbarBackHistory,
              onPressed: canGoBack ? onGoBack : null,
            ),
            AppIconButton(
              icon: Icons.chevron_right,
              size: 28,
              iconSize: 16,
              tooltip: l10n.toolbarForwardHistory,
              onPressed: canGoForward ? onGoForward : null,
            ),
          ],
          if (!isCompact || canNavigateUp)
            AppIconButton(
              icon: Icons.arrow_upward,
              size: 28,
              iconSize: 16,
              tooltip: l10n.toolbarUpOneLevel,
              onPressed: canNavigateUp ? onNavigateUp : null,
            ),
          if (!isCompact)
            AppIconButton(
              icon: Icons.refresh,
              size: 28,
              iconSize: 16,
              tooltip: l10n.refresh,
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onStartEdit,
              child: SingleChildScrollView(
                reverse: true,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                  HoverExpandDragTarget<({String root, List<String> paths})>(
                    showDefaultDecoration: false,
                    onAccept: (d) => onAcceptDrop?.call(d, ''),
                    onHoverExpand: relPath.isNotEmpty
                        ? () => onSegmentTap?.call('')
                        : null,
                    builder: (ctx, isHovering) {
                      final primary = Theme.of(context).colorScheme.primary;
                      return InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => onSegmentTap?.call(''),
                        onLongPress: () => onCopyPath?.call(''),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: isHovering
                              ? BoxDecoration(
                                  color: primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: primary, width: 1),
                                )
                              : null,
                          child: Text(
                            rootLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: (relPath.isEmpty || isHovering)
                                  ? primary
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: (relPath.isEmpty || isHovering)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  for (int i = 0; i < segments.length; i++) ...[
                    const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                    () {
                      final segPath = segments.take(i + 1).join('/');
                      final isLast = i == segments.length - 1;
                      return HoverExpandDragTarget<({String root, List<String> paths})>(
                        showDefaultDecoration: false,
                        onAccept: (d) => onAcceptDrop?.call(d, segPath),
                        onHoverExpand: !isLast
                            ? () => onSegmentTap?.call(segPath)
                            : null,
                        builder: (ctx, isHovering) {
                          final primary = Theme.of(context).colorScheme.primary;
                          return InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => onSegmentTap?.call(segPath),
                            onLongPress: () => onCopyPath?.call(segPath),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: isHovering
                                  ? BoxDecoration(
                                      color: primary.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: primary, width: 1),
                                    )
                                  : null,
                              child: Text(
                                segments[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (isLast || isHovering)
                                      ? primary
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: (isLast || isHovering)
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }(),
                  ],
                ],
              ),
            ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 15),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            tooltip: l10n.toolbarEditAddress,
            onPressed: onStartEdit,
          ),
        ],
      ),
    );
  }
}
