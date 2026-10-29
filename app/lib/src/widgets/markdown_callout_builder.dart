import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../theme/markdown_themes.dart';

enum _CalloutType {
  note('Note', Icons.info_outline, Color(0xFF0969DA), Color(0xFF1F6FEB)),
  tip('Tip', Icons.lightbulb_outline, Color(0xFF1A7F37), Color(0xFF238636)),
  important('Important', Icons.bookmark_border, Color(0xFF8250DF), Color(0xFF8957E5)),
  warning('Warning', Icons.warning_amber_rounded, Color(0xFF9A6700), Color(0xFFD29922)),
  caution('Caution', Icons.report_problem_outlined, Color(0xFFCF222E), Color(0xFFDA3633));

  final String title;
  final IconData icon;
  final Color lightColor;
  final Color darkColor;

  const _CalloutType(this.title, this.icon, this.lightColor, this.darkColor);

  Color colorFor(bool isDark) => isDark ? darkColor : lightColor;
}

/// Renders GitHub-style Alert/Callout blocks (> [!NOTE], > [!TIP], etc.)
class CalloutBlockquoteBuilder extends MarkdownElementBuilder {
  final MarkdownThemeConfig themeConfig;
  final double fontSize;

  CalloutBlockquoteBuilder({
    required this.themeConfig,
    this.fontSize = 14.0,
  });

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent.trimLeft();
    _CalloutType? calloutType;
    String cleanText = text;

    for (final type in _CalloutType.values) {
      final prefix = '[!${type.name.toUpperCase()}]';
      if (text.startsWith(prefix)) {
        calloutType = type;
        cleanText = text.substring(prefix.length).trimLeft();
        break;
      }
    }

    if (calloutType == null) {
      // Fallback to default blockquote styling in stylesheet
      return null;
    }

    final accent = calloutType.colorFor(themeConfig.isDark);
    final bg = accent.withValues(alpha: themeConfig.isDark ? 0.15 : 0.08);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          left: BorderSide(color: accent, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(calloutType.icon, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                calloutType.title,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
            ],
          ),
          if (cleanText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              cleanText,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.5,
                color: themeConfig.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
