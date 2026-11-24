import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/markdown_themes.dart';
import '../html_preview_widget.dart';
import '../json_formatted_preview.dart';
import '../markdown_callout_builder.dart';
import '../markdown_code_builder.dart';

/// Standalone rendered preview pane for Markdown, JSON, and HTML documents in
/// [TextEditorPage].
class EditorPreviewPane extends StatelessWidget {
  final bool isMarkdown;
  final bool isJson;
  final bool readOnly;
  final String root;
  final String path;
  final String text;
  final bool isDirty;
  final double fontSize;
  final MarkdownThemeType markdownTheme;
  final String filterQuery;
  final VoidCallback onEditSource;
  final VoidCallback onOpenRawCode;
  final ValueChanged<WebViewController> onHtmlControllerCreated;
  final VoidCallback onOpenHtmlInBrowser;

  const EditorPreviewPane({
    super.key,
    required this.isMarkdown,
    required this.isJson,
    required this.readOnly,
    required this.root,
    required this.path,
    required this.text,
    required this.isDirty,
    required this.fontSize,
    required this.markdownTheme,
    required this.filterQuery,
    required this.onEditSource,
    required this.onOpenRawCode,
    required this.onHtmlControllerCreated,
    required this.onOpenHtmlInBrowser,
  });

  @override
  Widget build(BuildContext context) {
    if (isMarkdown) {
      final brightness = Theme.of(context).brightness;
      final themeConfig = MarkdownThemeConfig.get(markdownTheme, brightness);
      if (text.isEmpty) {
        return Container(
          color: themeConfig.backgroundColor,
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 48,
                  color: themeConfig.textColor.withValues(alpha: 0.35),
                ),
                const SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).documentIsEmpty,
                  style: TextStyle(
                    fontSize: 14,
                    color: themeConfig.textColor.withValues(alpha: 0.6),
                    fontFamilyFallback: MarkdownThemeConfig.fontFamilyFallback,
                  ),
                ),
                if (!readOnly) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(AppLocalizations.of(context).editInSourceMode),
                    onPressed: onEditSource,
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Container(
        color: themeConfig.backgroundColor,
        width: double.infinity,
        height: double.infinity,
        child: SelectionArea(
          child: Markdown(
            data: text,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            selectable: false,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            styleSheet: themeConfig.toStyleSheet(context, fontSize: fontSize),
            builders: {
              'pre': HighlightCodeElementBuilder(
                themeConfig: themeConfig,
                fontSize: fontSize,
              ),
              'blockquote': CalloutBlockquoteBuilder(
                themeConfig: themeConfig,
                fontSize: fontSize,
              ),
            },
          ),
        ),
      );
    }

    if (isJson) {
      return JsonFormattedPreviewWidget(
        rawText: text,
        fontSize: fontSize,
        filterQuery: filterQuery,
        onOpenRawEditor: onOpenRawCode,
      );
    }

    return HtmlPreviewWidget(
      root: root,
      path: path,
      rawHtml: text,
      isDirty: isDirty,
      fontSize: fontSize,
      onControllerCreated: onHtmlControllerCreated,
      onOpenInBrowser: onOpenHtmlInBrowser,
    );
  }
}

/// Footer status bar showing document mode, dirty flag, cursor position, line /
/// word / character counts, encoding, and font size.
class EditorStatusBar extends StatelessWidget {
  final String modeLabel;
  final bool isDirty;
  final int cursorLine;
  final int cursorCol;
  final int lines;
  final int? words;
  final int chars;
  final bool largeFileMode;
  final String chunkEncoding;
  final double fontSize;
  final bool wordWrap;
  final VoidCallback onTapStats;

  const EditorStatusBar({
    super.key,
    required this.modeLabel,
    required this.isDirty,
    required this.cursorLine,
    required this.cursorCol,
    required this.lines,
    required this.words,
    required this.chars,
    required this.largeFileMode,
    required this.chunkEncoding,
    required this.fontSize,
    required this.wordWrap,
    required this.onTapStats,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTapStats,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Row(
          children: [
            Text(
              modeLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            if (isDirty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.modifiedLabel,
                  style: const TextStyle(fontSize: 10, color: Colors.amber),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${l10n.editorStatusLine(cursorLine, cursorCol, lines)}'
                '${words == null ? '' : l10n.editorStatusWords(words!)}${l10n.editorStatusChars(chars)}'
                '${largeFileMode ? '  •  ${chunkEncoding.toUpperCase()}  •  ' : ''}'
                '${fontSize.toInt()}pt${wordWrap ? '  •  ${l10n.wrapIndicator}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 13,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
