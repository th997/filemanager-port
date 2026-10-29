import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:re_highlight/styles/base16/dracula.dart';
import 'package:re_highlight/styles/base16/nord.dart';
import 'package:re_highlight/styles/base16/solarized-dark.dart';
import 'package:re_highlight/styles/base16/solarized-light.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

enum MarkdownThemeType {
  github('github', 'GitHub', Icons.code),
  dracula('dracula', 'Dracula (Neon)', Icons.nightlight_round),
  solarizedDark('solarized_dark', 'Solarized Dark', Icons.brightness_2),
  solarizedLight('solarized_light', 'Solarized Light', Icons.wb_sunny_outlined),
  vibrant('vibrant', 'Vibrant 彩色', Icons.palette_outlined),
  sepia('sepia', 'Sepia 羊皮纸', Icons.menu_book_outlined),
  nord('nord', 'Nord 极光冷灰', Icons.ac_unit);

  final String id;
  final String label;
  final IconData icon;

  const MarkdownThemeType(this.id, this.label, this.icon);

  static MarkdownThemeType fromId(String? id) {
    for (final t in MarkdownThemeType.values) {
      if (t.id == id) return t;
    }
    return MarkdownThemeType.github;
  }
}

class MarkdownThemeConfig {
  final MarkdownThemeType type;
  final bool isDark;
  final Color backgroundColor;
  final Color cardColor;
  final Color textColor;
  final Color h1Color;
  final Color h2Color;
  final Color h3Color;
  final Color h4Color;
  final Color linkColor;
  final Color codeTextColor;
  final Color codeBgColor;
  final Color blockquoteBorder;
  final Color blockquoteBg;
  final Color tableBorder;
  final Color tableHeadBg;
  final Color hrColor;
  final Map<String, TextStyle> highlightTheme;

  const MarkdownThemeConfig({
    required this.type,
    required this.isDark,
    required this.backgroundColor,
    required this.cardColor,
    required this.textColor,
    required this.h1Color,
    required this.h2Color,
    required this.h3Color,
    required this.h4Color,
    required this.linkColor,
    required this.codeTextColor,
    required this.codeBgColor,
    required this.blockquoteBorder,
    required this.blockquoteBg,
    required this.tableBorder,
    required this.tableHeadBg,
    required this.hrColor,
    required this.highlightTheme,
  });

  static MarkdownThemeConfig get(MarkdownThemeType type, Brightness brightness) {
    switch (type) {
      case MarkdownThemeType.github:
        final dark = brightness == Brightness.dark;
        return dark ? _githubDark : _githubLight;
      case MarkdownThemeType.dracula:
        return _dracula;
      case MarkdownThemeType.solarizedDark:
        return _solarizedDark;
      case MarkdownThemeType.solarizedLight:
        return _solarizedLight;
      case MarkdownThemeType.vibrant:
        return _vibrant;
      case MarkdownThemeType.sepia:
        return _sepia;
      case MarkdownThemeType.nord:
        return _nord;
    }
  }

  static const _githubLight = MarkdownThemeConfig(
    type: MarkdownThemeType.github,
    isDark: false,
    backgroundColor: Color(0xFFFFFFFF),
    cardColor: Color(0xFFF6F8FA),
    textColor: Color(0xFF24292F),
    h1Color: Color(0xFF1F2328),
    h2Color: Color(0xFF1F2328),
    h3Color: Color(0xFF24292F),
    h4Color: Color(0xFF24292F),
    linkColor: Color(0xFF0969DA),
    codeTextColor: Color(0xFF24292F),
    codeBgColor: Color(0xFFF6F8FA),
    blockquoteBorder: Color(0xFFD0D7DE),
    blockquoteBg: Color(0xFFF6F8FA),
    tableBorder: Color(0xFFD0D7DE),
    tableHeadBg: Color(0xFFF6F8FA),
    hrColor: Color(0xFFD0D7DE),
    highlightTheme: githubTheme,
  );

  static const _githubDark = MarkdownThemeConfig(
    type: MarkdownThemeType.github,
    isDark: true,
    backgroundColor: Color(0xFF0D1117),
    cardColor: Color(0xFF161B22),
    textColor: Color(0xFFE6EDF3),
    h1Color: Color(0xFFF0F6FC),
    h2Color: Color(0xFFF0F6FC),
    h3Color: Color(0xFFE6EDF3),
    h4Color: Color(0xFFE6EDF3),
    linkColor: Color(0xFF4493F8),
    codeTextColor: Color(0xFFE6EDF3),
    codeBgColor: Color(0xFF161B22),
    blockquoteBorder: Color(0xFF30363D),
    blockquoteBg: Color(0x33161B22),
    tableBorder: Color(0xFF30363D),
    tableHeadBg: Color(0xFF161B22),
    hrColor: Color(0xFF30363D),
    highlightTheme: githubDarkTheme,
  );

  static const _dracula = MarkdownThemeConfig(
    type: MarkdownThemeType.dracula,
    isDark: true,
    backgroundColor: Color(0xFF282A36),
    cardColor: Color(0xFF21222C),
    textColor: Color(0xFFF8F8F2),
    h1Color: Color(0xFFFF79C6),
    h2Color: Color(0xFF8BE9FD),
    h3Color: Color(0xFF50FA7B),
    h4Color: Color(0xFFBD93F9),
    linkColor: Color(0xFF8BE9FD),
    codeTextColor: Color(0xFFF1FA8C),
    codeBgColor: Color(0xFF1E1F29),
    blockquoteBorder: Color(0xFFBD93F9),
    blockquoteBg: Color(0x33BD93F9),
    tableBorder: Color(0xFF6272A4),
    tableHeadBg: Color(0xFF21222C),
    hrColor: Color(0xFF6272A4),
    highlightTheme: draculaTheme,
  );

  static const _solarizedDark = MarkdownThemeConfig(
    type: MarkdownThemeType.solarizedDark,
    isDark: true,
    backgroundColor: Color(0xFF002B36),
    cardColor: Color(0xFF073642),
    textColor: Color(0xFF839496),
    h1Color: Color(0xFFCB4B16),
    h2Color: Color(0xFF268BD2),
    h3Color: Color(0xFFD33682),
    h4Color: Color(0xFF2AA198),
    linkColor: Color(0xFF268BD2),
    codeTextColor: Color(0xFFB58900),
    codeBgColor: Color(0xFF073642),
    blockquoteBorder: Color(0xFF859900),
    blockquoteBg: Color(0x33859900),
    tableBorder: Color(0xFF586E75),
    tableHeadBg: Color(0xFF073642),
    hrColor: Color(0xFF586E75),
    highlightTheme: solarizedDarkTheme,
  );

  static const _solarizedLight = MarkdownThemeConfig(
    type: MarkdownThemeType.solarizedLight,
    isDark: false,
    backgroundColor: Color(0xFFFDF6E3),
    cardColor: Color(0xFFEEE8D5),
    textColor: Color(0xFF657B83),
    h1Color: Color(0xFFCB4B16),
    h2Color: Color(0xFF268BD2),
    h3Color: Color(0xFFD33682),
    h4Color: Color(0xFF2AA198),
    linkColor: Color(0xFF268BD2),
    codeTextColor: Color(0xFFB58900),
    codeBgColor: Color(0xFFEEE8D5),
    blockquoteBorder: Color(0xFF859900),
    blockquoteBg: Color(0x22859900),
    tableBorder: Color(0xFF93A1A1),
    tableHeadBg: Color(0xFFEEE8D5),
    hrColor: Color(0xFF93A1A1),
    highlightTheme: solarizedLightTheme,
  );

  static const _vibrant = MarkdownThemeConfig(
    type: MarkdownThemeType.vibrant,
    isDark: false,
    backgroundColor: Color(0xFFFBFBFD),
    cardColor: Color(0xFFF2F4F8),
    textColor: Color(0xFF2D3748),
    h1Color: Color(0xFF6366F1), // Indigo
    h2Color: Color(0xFFEC4899), // Pink
    h3Color: Color(0xFF06B6D4), // Cyan
    h4Color: Color(0xFF10B981), // Emerald
    linkColor: Color(0xFF4F46E5),
    codeTextColor: Color(0xFF0D9488),
    codeBgColor: Color(0xFFEEF2FF),
    blockquoteBorder: Color(0xFF8B5CF6),
    blockquoteBg: Color(0x188B5CF6),
    tableBorder: Color(0xFFE2E8F0),
    tableHeadBg: Color(0xFFF1F5F9),
    hrColor: Color(0xFFCBD5E1),
    highlightTheme: githubTheme,
  );

  static const _sepia = MarkdownThemeConfig(
    type: MarkdownThemeType.sepia,
    isDark: false,
    backgroundColor: Color(0xFFF7F1E5),
    cardColor: Color(0xFFECE4D0),
    textColor: Color(0xFF4A3B32),
    h1Color: Color(0xFF8B4513), // Saddle Brown
    h2Color: Color(0xFFA0522D), // Sienna
    h3Color: Color(0xFF6E4D38),
    h4Color: Color(0xFF5C4033),
    linkColor: Color(0xFF8A3324),
    codeTextColor: Color(0xFF6B4226),
    codeBgColor: Color(0xFFE8DFC8),
    blockquoteBorder: Color(0xFFB38B6D),
    blockquoteBg: Color(0x22B38B6D),
    tableBorder: Color(0xFFD4C5B9),
    tableHeadBg: Color(0xFFECE4D0),
    hrColor: Color(0xFFD4C5B9),
    highlightTheme: githubTheme,
  );

  static const _nord = MarkdownThemeConfig(
    type: MarkdownThemeType.nord,
    isDark: true,
    backgroundColor: Color(0xFF2E3440),
    cardColor: Color(0xFF3B4252),
    textColor: Color(0xFFECEFF4),
    h1Color: Color(0xFF88C0D0), // Frost blue
    h2Color: Color(0xFF81A1C1),
    h3Color: Color(0xFF5E81AC),
    h4Color: Color(0xFFA3BE8C), // Aurora green
    linkColor: Color(0xFF88C0D0),
    codeTextColor: Color(0xFFEBCB8B),
    codeBgColor: Color(0xFF3B4252),
    blockquoteBorder: Color(0xFF88C0D0),
    blockquoteBg: Color(0x2288C0D0),
    tableBorder: Color(0xFF4C566A),
    tableHeadBg: Color(0xFF3B4252),
    hrColor: Color(0xFF4C566A),
    highlightTheme: nordTheme,
  );

  MarkdownStyleSheet toStyleSheet(BuildContext context, {double fontSize = 14.0}) {
    final scale = fontSize / 14.0;
    return MarkdownStyleSheet(
      p: TextStyle(
        color: textColor,
        fontSize: fontSize,
        height: 1.6,
      ),
      h1: TextStyle(
        color: h1Color,
        fontSize: 24 * scale,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.5,
      ),
      h1Padding: const EdgeInsets.only(top: 18, bottom: 8),
      h2: TextStyle(
        color: h2Color,
        fontSize: 20 * scale,
        fontWeight: FontWeight.w700,
        height: 1.35,
        letterSpacing: -0.3,
      ),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h3: TextStyle(
        color: h3Color,
        fontSize: 16 * scale,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
      h4: TextStyle(
        color: h4Color,
        fontSize: 14 * scale,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h5: TextStyle(
        color: h4Color,
        fontSize: 13 * scale,
        fontWeight: FontWeight.w600,
      ),
      h6: TextStyle(
        color: textColor.withValues(alpha: 0.8),
        fontSize: 12 * scale,
        fontWeight: FontWeight.w600,
      ),
      em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
      strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      del: TextStyle(
        color: textColor.withValues(alpha: 0.6),
        decoration: TextDecoration.lineThrough,
      ),
      a: TextStyle(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor.withValues(alpha: 0.5),
      ),
      code: TextStyle(
        color: codeTextColor,
        backgroundColor: codeBgColor,
        fontFamily: 'monospace',
        fontSize: (fontSize - 1).clamp(10.0, 30.0),
      ),
      blockquote: TextStyle(
        color: textColor.withValues(alpha: 0.85),
        fontSize: fontSize,
        fontStyle: FontStyle.italic,
        height: 1.5,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBg,
        border: Border(
          left: BorderSide(color: blockquoteBorder, width: 4),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      tableHead: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
        fontSize: fontSize,
      ),
      tableBody: TextStyle(
        color: textColor,
        fontSize: fontSize,
      ),
      tableBorder: TableBorder.all(
        color: tableBorder,
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),
      tableHeadCellsPadding: const EdgeInsets.all(8),
      tableCellsPadding: const EdgeInsets.all(8),
      tableHeadCellsDecoration: BoxDecoration(color: tableHeadBg),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: hrColor, width: 1.5)),
      ),
      listBullet: TextStyle(color: textColor),
    );
  }
}
