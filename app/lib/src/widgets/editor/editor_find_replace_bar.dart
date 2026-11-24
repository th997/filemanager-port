import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Reusable Find / Replace / Go-to-Line toolbar widget used by [TextEditorPage].
class EditorFindReplaceBar extends StatelessWidget {
  final TextEditingController findController;
  final TextEditingController replaceController;
  final FocusNode findFocusNode;
  final FocusNode replaceFocusNode;
  final bool showReplace;
  final bool readOnly;
  final int matchCount;
  final int currentMatchIndex;
  final bool matchCountCapped;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onFindSubmitted;
  final VoidCallback? onClearFind;
  final VoidCallback onPreviousMatch;
  final VoidCallback onNextMatch;
  final VoidCallback onReplaceOne;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleReplace;
  final VoidCallback? onGoToLine;
  final VoidCallback onClose;

  const EditorFindReplaceBar({
    super.key,
    required this.findController,
    required this.replaceController,
    required this.findFocusNode,
    required this.replaceFocusNode,
    required this.showReplace,
    required this.readOnly,
    required this.matchCount,
    required this.currentMatchIndex,
    this.matchCountCapped = false,
    required this.onQueryChanged,
    this.onFindSubmitted,
    this.onClearFind,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.onReplaceOne,
    required this.onReplaceAll,
    required this.onToggleReplace,
    this.onGoToLine,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hasQuery = findController.text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.search, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: findController,
                  focusNode: findFocusNode,
                  decoration: InputDecoration(
                    hintText: l10n.findInFileHint,
                    isDense: true,
                    border: InputBorder.none,
                    suffixIcon: hasQuery
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            tooltip: l10n.clear,
                            onPressed: onClearFind,
                          )
                        : null,
                  ),
                  onChanged: onQueryChanged,
                  onSubmitted: (_) => (onFindSubmitted ?? onNextMatch)(),
                ),
              ),
              if (hasQuery)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    matchCount == 0
                        ? '0/0'
                        : '${currentMatchIndex + 1}/${matchCountCapped ? '10000+' : matchCount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: l10n.previousMatch,
                onPressed: matchCount > 0 ? onPreviousMatch : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: l10n.nextMatch,
                onPressed: matchCount > 0 ? onNextMatch : null,
              ),
              if (onGoToLine != null)
                IconButton(
                  icon: const Icon(Icons.format_list_numbered, size: 18),
                  tooltip: l10n.goToLine,
                  onPressed: onGoToLine,
                ),
              if (!readOnly)
                IconButton(
                  icon: Icon(
                    showReplace ? Icons.find_replace : Icons.find_replace_outlined,
                    size: 18,
                  ),
                  tooltip: l10n.toggleReplaceShortcut,
                  onPressed: onToggleReplace,
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.closeFindShortcut,
                onPressed: onClose,
              ),
            ],
          ),
          if (showReplace && !readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_alt, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: replaceController,
                      focusNode: replaceFocusNode,
                      decoration: InputDecoration(
                        hintText: l10n.replaceWithHint,
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => onReplaceOne(),
                    ),
                  ),
                  TextButton(
                    onPressed: matchCount > 0 ? onReplaceOne : null,
                    child: Text(l10n.replace),
                  ),
                  TextButton(
                    onPressed: matchCount > 0 ? onReplaceAll : null,
                    child: Text(l10n.replaceAll),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
