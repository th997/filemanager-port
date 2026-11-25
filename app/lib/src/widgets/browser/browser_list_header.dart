import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Column sort keys shared by the file browser list header, sort menu, and
/// persisted view preferences.
enum SortField { name, size, modified, type }

/// Sticky sortable column header row for wide/desktop detail list views
/// (Finder / Explorer / Nautilus style).
class BrowserListColumnHeader extends StatelessWidget {
  final SortField sortField;
  final bool sortAsc;
  final bool showTypeColumn;
  final bool hasLeadingCheckbox;
  final ValueChanged<SortField> onSortTap;
  final String nameLabel;
  final String modifiedLabel;
  final String typeLabel;
  final String sizeLabel;

  const BrowserListColumnHeader({
    super.key,
    required this.sortField,
    required this.sortAsc,
    required this.showTypeColumn,
    required this.hasLeadingCheckbox,
    required this.onSortTap,
    required this.nameLabel,
    required this.modifiedLabel,
    required this.typeLabel,
    required this.sizeLabel,
  });

  Widget _columnButton(
    BuildContext context, {
    required String label,
    required SortField field,
    Alignment alignment = Alignment.centerLeft,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = sortField == field;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        color: color,
      ),
    );
    final arrow = active
        ? Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Icon(
              sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 13,
              color: scheme.primary,
            ),
          )
        : const SizedBox.shrink();

    return InkWell(
      onTap: () => onSortTap(field),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Align(
          alignment: alignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: alignment == Alignment.centerRight
                ? [arrow, Flexible(child: text)]
                : [Flexible(child: text), arrow],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: EdgeInsets.only(
        left: hasLeadingCheckbox ? 70 : 40,
        right: 14,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _columnButton(
              context,
              label: nameLabel,
              field: SortField.name,
            ),
          ),
          if (showTypeColumn)
            SizedBox(
              width: 84,
              child: _columnButton(
                context,
                label: typeLabel,
                field: SortField.type,
              ),
            ),
          SizedBox(
            width: 136,
            child: _columnButton(
              context,
              label: modifiedLabel,
              field: SortField.modified,
            ),
          ),
          SizedBox(
            width: 90,
            child: _columnButton(
              context,
              label: sizeLabel,
              field: SortField.size,
              alignment: Alignment.centerRight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim bottom status bar modeled after native desktop/tablet file managers
/// (item counts, selection totals, read-only badge, hidden-files quick toggle).
class BrowserStatusBar extends StatelessWidget {
  final int visibleCount;
  final int totalNonHiddenCount;
  final bool isFiltered;
  final BigInt totalListedBytes;
  final int selectedCount;
  final BigInt selectedBytes;
  final bool hasHiddenEntries;
  final bool showHidden;
  final bool isReadOnly;
  final bool hasMore;
  final String Function(BigInt) formatBytes;
  final VoidCallback onTapCount;
  final VoidCallback onToggleHidden;

  const BrowserStatusBar({
    super.key,
    required this.visibleCount,
    required this.totalNonHiddenCount,
    required this.isFiltered,
    required this.totalListedBytes,
    required this.selectedCount,
    required this.selectedBytes,
    required this.hasHiddenEntries,
    required this.showHidden,
    required this.isReadOnly,
    required this.hasMore,
    required this.formatBytes,
    required this.onTapCount,
    required this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final String summary;
    if (selectedCount > 0) {
      summary = selectedBytes > BigInt.zero
          ? l10n.selectedCountBytesLabel(selectedCount, formatBytes(selectedBytes))
          : l10n.selectedCountLabel(selectedCount);
    } else {
      final base = isFiltered
          ? l10n.itemsOutOfTotal(visibleCount, totalNonHiddenCount)
          : l10n.itemsCount(visibleCount);
      final sizeSuffix = totalListedBytes > BigInt.zero
          ? '  •  ${formatBytes(totalListedBytes)}'
          : '';
      final moreSuffix = hasMore ? ' (${l10n.moreBelow})' : '';
      summary = '$base$sizeSuffix$moreSuffix';
    }

    final readOnlyLabel = l10n.readOnly
        .replaceAll('(', '')
        .replaceAll(')', '')
        .trim();

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTapCount,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selectedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                    color: selectedCount > 0
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (isReadOnly)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 11, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text(
                      readOnlyLabel.isEmpty ? 'Read-only' : readOnlyLabel,
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (hasHiddenEntries || showHidden)
            InkWell(
              onTap: onToggleHidden,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      showHidden ? Icons.visibility : Icons.visibility_off_outlined,
                      size: 12,
                      color: showHidden ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      showHidden ? l10n.showHiddenFiles : l10n.hiddenFilesOff,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: showHidden ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: showHidden ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pure rules decoupling selection state (`_selectedPaths`) from the mobile
/// checkbox / bottom-action-bar multi-select UI (`_isSelecting`).
class BrowserSelectionRules {
  /// Returns whether the explicit checkbox/action-bar UI should be active
  /// after a selection change. On desktop, normal clicks, modifier clicks,
  /// lasso drags, range/all selection, and keyboard navigation highlight items
  /// natively without forcing the mobile checkbox/action-bar chrome.
  static bool nextMultiSelectUiMode({
    required bool isDesktop,
    required bool alreadyInMultiSelectBar,
    required bool hasSelection,
    bool explicitMultiSelectAction = false,
  }) {
    if (explicitMultiSelectAction) return true;
    if (!hasSelection) return false;
    if (!isDesktop) return true;
    return alreadyInMultiSelectBar;
  }
}
