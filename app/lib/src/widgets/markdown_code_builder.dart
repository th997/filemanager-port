import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/re_highlight.dart';

import '../theme/markdown_themes.dart';

/// Renders fenced code blocks with language badge, copy action, and syntax highlighting.
class HighlightCodeElementBuilder extends MarkdownElementBuilder {
  final MarkdownThemeConfig themeConfig;
  final double fontSize;
  static final Highlight _highlighter = Highlight();
  static bool _registered = false;

  HighlightCodeElementBuilder({
    required this.themeConfig,
    this.fontSize = 13.0,
  }) {
    if (!_registered) {
      _registered = true;
      // Common languages registered via highlight_service; additional safe fallback
    }
  }

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // If not a code block, let default inline code styling take over
    final isCodeBlock = element.attributes.containsKey('class') ||
        element.textContent.contains('\n');
    if (!isCodeBlock) return null;

    final rawClass = element.attributes['class'] ?? '';
    String? language;
    if (rawClass.startsWith('language-')) {
      language = rawClass.substring('language-'.length).toLowerCase();
    }

    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    final displayLang = (language ?? 'text').toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: themeConfig.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: themeConfig.tableBorder.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Language pill & Copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: themeConfig.isDark
                  ? Colors.black.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.04),
              border: Border(
                bottom: BorderSide(
                  color: themeConfig.tableBorder.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  displayLang,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: themeConfig.textColor.withValues(alpha: 0.6),
                    fontFamily: 'monospace',
                  ),
                ),
                _CopyButton(code: code, textColor: themeConfig.textColor),
              ],
            ),
          ),
          // Code content with horizontal scroll
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              _buildSpan(code, language),
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _buildSpan(String code, String? language) {
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.45,
      color: themeConfig.textColor,
    );

    if (code.length > 32 * 1024) {
      return TextSpan(text: code, style: baseStyle);
    }

    try {
      HighlightResult? result;
      if (language != null && language.isNotEmpty) {
        try {
          result = _highlighter.highlight(code: code, language: language);
        } catch (_) {}
      }
      if (result == null && code.length <= 2048) {
        try {
          result = _highlighter.highlightAuto(code);
        } catch (_) {}
      }

      if (result != null) {
        final renderer = TextSpanRenderer(baseStyle, themeConfig.highlightTheme);
        result.render(renderer);
        return renderer.span ?? TextSpan(text: code, style: baseStyle);
      }
    } catch (_) {}

    return TextSpan(text: code, style: baseStyle);
  }
}

class _CopyButton extends StatefulWidget {
  final String code;
  final Color textColor;

  const _CopyButton({required this.code, required this.textColor});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _onCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _onCopy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy_rounded,
              size: 14,
              color: _copied ? Colors.green : widget.textColor.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: TextStyle(
                fontSize: 11,
                color: _copied ? Colors.green : widget.textColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
