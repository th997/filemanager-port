import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Reusable Find / Replace / Go-to-Line toolbar widget extracted from [TextEditorPage].
class EditorFindReplaceBar extends StatelessWidget {
  final TextEditingController findController;
  final TextEditingController replaceController;
  final FocusNode findFocusNode;
  final FocusNode replaceFocusNode;
  final bool showReplace;
  final bool readOnly;
  final int matchCount;
  final int currentMatchIndex;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onPreviousMatch;
  final VoidCallback onNextMatch;
  final VoidCallback onReplaceOne;
  final VoidCallback onReplaceAll;
  final VoidCallback onToggleReplace;
  final VoidCallback onGoToLine;
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
    required this.onQueryChanged,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.onReplaceOne,
    required this.onReplaceAll,
    required this.onToggleReplace,
    required this.onGoToLine,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (!readOnly)
                IconButton(
                  icon: Icon(showReplace ? Icons.expand_more : Icons.chevron_right, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleReplace,
                ),
              Expanded(
                child: TextField(
                  controller: findController,
                  focusNode: findFocusNode,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.findInFileTooltip,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: onQueryChanged,
                  onSubmitted: (_) => onNextMatch(),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                matchCount == 0 ? '0/0' : '${currentMatchIndex + 1}/$matchCount',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: matchCount > 0 ? onPreviousMatch : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: matchCount > 0 ? onNextMatch : null,
              ),
              IconButton(
                icon: const Icon(Icons.format_list_numbered, size: 18),
                tooltip: l10n.goToLine,
                visualDensity: VisualDensity.compact,
                onPressed: onGoToLine,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          if (showReplace && !readOnly) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 34),
                Expanded(
                  child: TextField(
                    controller: replaceController,
                    focusNode: replaceFocusNode,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.replace,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: matchCount > 0 ? onReplaceOne : null,
                  child: Text(l10n.replace, style: const TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: matchCount > 0 ? onReplaceAll : null,
                  child: const Text('All', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
