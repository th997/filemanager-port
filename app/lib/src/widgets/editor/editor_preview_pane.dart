import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../theme/markdown_themes.dart';
import '../html_preview_widget.dart';

/// Reusable Markdown / HTML preview pane extracted from [TextEditorPage].
class EditorPreviewPane extends StatelessWidget {
  final String root;
  final String path;
  final String content;
  final bool isHtml;
  final MarkdownThemeType markdownTheme;
  final void Function(String text, String? href, String title)? onTapLink;

  const EditorPreviewPane({
    super.key,
    required this.root,
    required this.path,
    required this.content,
    required this.isHtml,
    this.markdownTheme = MarkdownThemeType.github,
    this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    if (isHtml) {
      return HtmlPreviewWidget(
        root: root,
        path: path,
        rawHtml: content,
      );
    }
    return Markdown(
      data: content,
      selectable: true,
      styleSheet: MarkdownThemeConfig.get(
        markdownTheme,
        Theme.of(context).brightness,
      ).toStyleSheet(context),
      onTapLink: onTapLink,
    );
  }
}
