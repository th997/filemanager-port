import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Color, TextStyle;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:re_highlight/re_highlight.dart';

import '../theme/markdown_themes.dart';
import 'highlight_service.dart';

PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());

/// Page margins and spacing presets for PDF exports.
enum PdfMarginMode {
  compact('compact', '紧凑 (16pt)', 16.0, 0.6),
  standard('standard', '标准 (36pt)', 36.0, 1.0),
  relaxed('relaxed', '宽松 (54pt)', 54.0, 1.5);

  final String id;
  final String label;
  final double pageMargin;
  final double spacingScale;

  const PdfMarginMode(this.id, this.label, this.pageMargin, this.spacingScale);

  static PdfMarginMode fromId(String? id) {
    for (final m in PdfMarginMode.values) {
      if (m.id == id) return m;
    }
    return PdfMarginMode.standard;
  }
}

/// Exports Markdown content to a PDF document with proper formatting,
/// code block highlighting, and Chinese/Unicode font support.
class MarkdownPdfService {
  static final MarkdownPdfService instance = MarkdownPdfService._();
  MarkdownPdfService._();

  static final md.Document _inlineMdDoc = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  static pw.Font? _cachedSystemFont;
  static bool _systemFontSearched = false;

  /// Attempts to find a local TrueType font supporting Unicode/CJK characters.
  static pw.Font? _loadSystemFont() {
    if (_systemFontSearched) return _cachedSystemFont;
    _systemFontSearched = true;

    final candidatePaths = [
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/Library/Fonts/Arial Unicode.ttf',
      'C:\\Windows\\Fonts\\msyh.ttc',
      'C:\\Windows\\Fonts\\simsun.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/truetype/wqy/wqy-microhei.ttc',
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      '/system/fonts/NotoSansCJK-Regular.ttc',
      '/system/fonts/DroidSansFallback.ttf',
    ];

    for (final path in candidatePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          _cachedSystemFont = pw.Font.ttf(bytes.buffer.asByteData());
          return _cachedSystemFont;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Generates a PDF byte stream from Markdown text, themed with [themeConfig].
  Future<Uint8List> generatePdf({
    required String markdown,
    required String title,
    MarkdownThemeConfig? themeConfig,
    PdfMarginMode marginMode = PdfMarginMode.standard,
    pw.Font? customRegularFont,
    pw.Font? customBoldFont,
  }) async {
    final pdf = pw.Document(title: title);

    pw.Font? regularFont = customRegularFont;
    pw.Font? boldFont = customBoldFont;

    // 1. Try local system CJK font (instant, offline capable)
    if (regularFont == null || boldFont == null) {
      final systemFont = _loadSystemFont();
      if (systemFont != null) {
        regularFont ??= systemFont;
        boldFont ??= systemFont;
      }
    }

    // 2. Try Google Fonts download with timeout
    if (regularFont == null || boldFont == null) {
      try {
        regularFont ??= await PdfGoogleFonts.notoSansSCRegular().timeout(
          const Duration(seconds: 4),
        );
        boldFont ??= await PdfGoogleFonts.notoSansSCBold().timeout(
          const Duration(seconds: 4),
        );
      } catch (_) {}
    }

    // 3. Fallback to standard Helvetica
    regularFont ??= pw.Font.helvetica();
    boldFont ??= pw.Font.helveticaBold();

    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    );

    final widgets = _parseMarkdownToPdfWidgets(
      markdown,
      regularFont,
      boldFont,
      themeConfig,
      marginMode.spacingScale,
    );

    final pageBg = themeConfig != null ? _pdf(themeConfig.backgroundColor) : null;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(marginMode.pageMargin),
          buildBackground: pageBg != null
              ? (context) => pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Container(color: pageBg),
                  )
              : null,
        ),
        build: (context) => widgets,
      ),
    );

    return pdf.save();
  }

  /// Parses Markdown lines into a list of pdf widgets with theme colors applied.
  List<pw.Widget> _parseMarkdownToPdfWidgets(
    String markdown,
    pw.Font regularFont,
    pw.Font boldFont,
    MarkdownThemeConfig? themeConfig,
    double scale,
  ) {
    final List<pw.Widget> result = [];
    final lines = const LineSplitter().convert(markdown);

    final h1Color = themeConfig != null ? _pdf(themeConfig.h1Color) : PdfColors.blueGrey900;
    final h2Color = themeConfig != null ? _pdf(themeConfig.h2Color) : PdfColors.blueGrey800;
    final h3Color = themeConfig != null ? _pdf(themeConfig.h3Color) : PdfColors.blueGrey700;
    final textColor = themeConfig != null ? _pdf(themeConfig.textColor) : PdfColors.grey900;
    final hrColor = themeConfig != null ? _pdf(themeConfig.hrColor) : PdfColors.grey300;

    bool inCodeBlock = false;
    final List<String> codeBuffer = [];
    String? codeLang;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // Fenced code blocks
      if (trimmed.startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          codeLang = trimmed.substring(3).trim();
          codeBuffer.clear();
        } else {
          inCodeBlock = false;
          result.add(
            _buildCodeBlock(codeBuffer.join('\n'), codeLang, regularFont, themeConfig, scale),
          );
          codeBuffer.clear();
          codeLang = null;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.add(line);
        continue;
      }

      if (trimmed.isEmpty) {
        result.add(pw.SizedBox(height: 6 * scale));
        continue;
      }

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(vertical: 8 * scale),
            child: pw.Divider(color: hrColor, thickness: 1),
          ),
        );
        continue;
      }

      // Headings
      if (trimmed.startsWith('# ')) {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 14 * scale, bottom: 6 * scale),
            child: _buildRichText(
              trimmed.substring(2).trim(),
              regularFont: regularFont,
              boldFont: boldFont,
              themeConfig: themeConfig,
              fontSize: 20,
              textColor: h1Color,
              isBold: true,
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('## ')) {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 10 * scale, bottom: 5 * scale),
            child: _buildRichText(
              trimmed.substring(3).trim(),
              regularFont: regularFont,
              boldFont: boldFont,
              themeConfig: themeConfig,
              fontSize: 16,
              textColor: h2Color,
              isBold: true,
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('### ')) {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 8 * scale, bottom: 4 * scale),
            child: _buildRichText(
              trimmed.substring(4).trim(),
              regularFont: regularFont,
              boldFont: boldFont,
              themeConfig: themeConfig,
              fontSize: 13,
              textColor: h3Color,
              isBold: true,
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('#### ')) {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(top: 6 * scale, bottom: 3 * scale),
            child: _buildRichText(
              trimmed.substring(5).trim(),
              regularFont: regularFont,
              boldFont: boldFont,
              themeConfig: themeConfig,
              fontSize: 11,
              textColor: h3Color,
              isBold: true,
            ),
          ),
        );
        continue;
      }

      // Markdown Tables
      if (trimmed.startsWith('|') && trimmed.endsWith('|') && trimmed.length > 2) {
        final tableLines = <String>[];
        while (i < lines.length) {
          final tblLine = lines[i].trim();
          if (tblLine.startsWith('|') && tblLine.endsWith('|') && tblLine.length > 2) {
            tableLines.add(tblLine);
            i++;
          } else {
            i--;
            break;
          }
        }
        if (tableLines.length >= 2) {
          final tableWidget = _buildTable(
            tableLines,
            regularFont,
            boldFont,
            themeConfig,
            scale,
          );
          if (tableWidget != null) {
            result.add(tableWidget);
            continue;
          }
        }
      }

      // Blockquotes & Callouts
      if (trimmed.startsWith('>')) {
        final quoteText = trimmed.substring(1).trim();
        result.add(_buildBlockquote(quoteText, regularFont, boldFont, themeConfig, scale));
        continue;
      }

      // Unordered lists
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
        final itemText = trimmed.substring(2).trim();
        int leadingSpaces = 0;
        for (int c = 0; c < line.length; c++) {
          if (line[c] == ' ') leadingSpaces++;
          else if (line[c] == '\t') leadingSpaces += 2;
          else break;
        }
        final indentPadding = 12.0 + (leadingSpaces ~/ 2) * 10.0;

        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: indentPadding, bottom: 3 * scale),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  margin: const pw.EdgeInsets.only(top: 5, right: 8),
                  decoration: pw.BoxDecoration(
                    color: textColor,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: _buildRichText(
                    itemText,
                    regularFont: regularFont,
                    boldFont: boldFont,
                    themeConfig: themeConfig,
                    fontSize: 10,
                    textColor: textColor,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Ordered lists (e.g. "1. ")
      final numMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (numMatch != null) {
        final numStr = numMatch.group(1)!;
        final itemText = numMatch.group(2)!;
        int leadingSpaces = 0;
        for (int c = 0; c < line.length; c++) {
          if (line[c] == ' ') leadingSpaces++;
          else if (line[c] == '\t') leadingSpaces += 2;
          else break;
        }
        final indentPadding = 12.0 + (leadingSpaces ~/ 2) * 10.0;

        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: indentPadding, bottom: 3 * scale),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 18,
                  child: pw.Text(
                    '$numStr.',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 10,
                      color: textColor,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: _buildRichText(
                    itemText,
                    regularFont: regularFont,
                    boldFont: boldFont,
                    themeConfig: themeConfig,
                    fontSize: 10,
                    textColor: textColor,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Standard paragraph
      result.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: 5 * scale),
          child: _buildRichText(
            trimmed,
            regularFont: regularFont,
            boldFont: boldFont,
            themeConfig: themeConfig,
            fontSize: 10,
            textColor: textColor,
            lineSpacing: 3,
          ),
        ),
      );
    }

    if (inCodeBlock && codeBuffer.isNotEmpty) {
      result.add(
        _buildCodeBlock(codeBuffer.join('\n'), codeLang, regularFont, themeConfig, scale),
      );
    }

    return result;
  }

  pw.Widget _buildCodeBlock(
    String code,
    String? lang,
    pw.Font font,
    MarkdownThemeConfig? themeConfig,
    double scale,
  ) {
    final codeBg = themeConfig != null
        ? _pdf(themeConfig.cardColor)
        : PdfColors.grey100;
    final codeBorder = themeConfig != null
        ? _pdf(themeConfig.tableBorder.withValues(alpha: 0.6))
        : PdfColors.grey300;
    final langColor = themeConfig != null
        ? _pdf(themeConfig.codeTextColor.withValues(alpha: 0.7))
        : PdfColors.grey600;
    final defaultCodeColor = themeConfig != null
        ? _pdf(themeConfig.codeTextColor)
        : PdfColors.grey900;

    pw.Widget codeContent;
    if (themeConfig != null && themeConfig.highlightTheme.isNotEmpty) {
      final span = _highlightCodeToPdfSpan(
        code,
        lang,
        font,
        defaultCodeColor,
        themeConfig.highlightTheme,
      );
      codeContent = pw.RichText(text: span);
    } else {
      codeContent = pw.Text(
        code,
        style: pw.TextStyle(
          font: font,
          fontSize: 8.5,
          lineSpacing: 2,
          color: defaultCodeColor,
        ),
      );
    }

    return pw.Container(
      width: double.infinity,
      margin: pw.EdgeInsets.symmetric(vertical: 6 * scale),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: codeBg,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: codeBorder, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (lang != null && lang.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                lang.toUpperCase(),
                style: pw.TextStyle(
                  font: font,
                  fontSize: 7,
                  color: langColor,
                ),
              ),
            ),
          codeContent,
        ],
      ),
    );
  }

  pw.TextSpan _highlightCodeToPdfSpan(
    String code,
    String? lang,
    pw.Font font,
    PdfColor defaultColor,
    Map<String, TextStyle> highlightTheme,
  ) {
    final baseStyle = pw.TextStyle(
      font: font,
      fontSize: 8.5,
      lineSpacing: 2,
      color: defaultColor,
    );

    if (code.length > 32 * 1024) {
      return pw.TextSpan(text: code, style: baseStyle);
    }

    try {
      final highlighter = HighlightService.instance.highlight;
      HighlightResult? result;
      if (lang != null && lang.isNotEmpty) {
        try {
          result = highlighter.highlight(code: code, language: lang);
        } catch (_) {}
      }
      if (result == null) {
        try {
          result = highlighter.highlightAuto(code);
        } catch (_) {}
      }

      if (result != null) {
        final renderer = _PdfHighlightRenderer(baseStyle, highlightTheme);
        result.render(renderer);
        final span = renderer.span;
        if (span != null) return span;
      }
    } catch (_) {}

    return pw.TextSpan(text: code, style: baseStyle);
  }

  pw.Widget _buildBlockquote(
    String text,
    pw.Font regularFont,
    pw.Font boldFont,
    MarkdownThemeConfig? themeConfig,
    double scale,
  ) {
    final isDark = themeConfig?.isDark ?? false;
    PdfColor accent = isDark ? const PdfColor.fromInt(0xFF1F6FEB) : const PdfColor.fromInt(0xFF0969DA);
    PdfColor bg = themeConfig != null
        ? _pdf(themeConfig.blockquoteBg)
        : (isDark ? const PdfColor.fromInt(0x261F6FEB) : const PdfColor.fromInt(0x140969DA));
    PdfColor quoteTextColor = themeConfig != null ? _pdf(themeConfig.textColor) : PdfColors.grey800;
    String cleanText = text;
    String? title;

    if (text.startsWith('[!NOTE]')) {
      final color = isDark ? const Color(0xFF1F6FEB) : const Color(0xFF0969DA);
      accent = _pdf(color);
      bg = _pdf(color.withValues(alpha: isDark ? 0.15 : 0.08));
      title = 'Note';
      cleanText = text.substring('[!NOTE]'.length).trim();
    } else if (text.startsWith('[!TIP]')) {
      final color = isDark ? const Color(0xFF238636) : const Color(0xFF1A7F37);
      accent = _pdf(color);
      bg = _pdf(color.withValues(alpha: isDark ? 0.15 : 0.08));
      title = 'Tip';
      cleanText = text.substring('[!TIP]'.length).trim();
    } else if (text.startsWith('[!IMPORTANT]')) {
      final color = isDark ? const Color(0xFF8957E5) : const Color(0xFF8250DF);
      accent = _pdf(color);
      bg = _pdf(color.withValues(alpha: isDark ? 0.15 : 0.08));
      title = 'Important';
      cleanText = text.substring('[!IMPORTANT]'.length).trim();
    } else if (text.startsWith('[!WARNING]')) {
      final color = isDark ? const Color(0xFFD29922) : const Color(0xFF9A6700);
      accent = _pdf(color);
      bg = _pdf(color.withValues(alpha: isDark ? 0.15 : 0.08));
      title = 'Warning';
      cleanText = text.substring('[!WARNING]'.length).trim();
    } else if (text.startsWith('[!CAUTION]')) {
      final color = isDark ? const Color(0xFFDA3633) : const Color(0xFFCF222E);
      accent = _pdf(color);
      bg = _pdf(color.withValues(alpha: isDark ? 0.15 : 0.08));
      title = 'Caution';
      cleanText = text.substring('[!CAUTION]'.length).trim();
    } else if (themeConfig != null) {
      accent = _pdf(themeConfig.blockquoteBorder);
    }

    return pw.Container(
      width: double.infinity,
      margin: pw.EdgeInsets.symmetric(vertical: 4 * scale),
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border(left: pw.BorderSide(color: accent, width: 3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (title != null)
            pw.Text(
              title,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 9,
                color: accent,
              ),
            ),
          _buildRichText(
            cleanText,
            regularFont: regularFont,
            boldFont: boldFont,
            themeConfig: themeConfig,
            fontSize: 9.5,
            textColor: quoteTextColor,
            lineSpacing: 2,
          ),
        ],
      ),
    );
  }

  pw.Widget? _buildTable(
    List<String> tableLines,
    pw.Font regularFont,
    pw.Font boldFont,
    MarkdownThemeConfig? themeConfig,
    double scale,
  ) {
    if (tableLines.length < 2) return null;

    List<String> parseRow(String row) {
      final trimmed = row.trim();
      var inner = trimmed;
      if (inner.startsWith('|')) inner = inner.substring(1);
      if (inner.endsWith('|')) inner = inner.substring(0, inner.length - 1);
      return inner.split('|').map((c) => c.trim()).toList();
    }

    final headers = parseRow(tableLines[0]);
    final separator = parseRow(tableLines[1]);

    if (separator.isEmpty || !separator.every((s) => RegExp(r'^:?-+:?$').hasMatch(s))) {
      return null;
    }

    final numCols = headers.length;
    final rows = <pw.TableRow>[];

    final tableBorderColor = themeConfig != null
        ? _pdf(themeConfig.tableBorder)
        : PdfColors.grey300;
    final headerBg = themeConfig != null
        ? _pdf(themeConfig.tableHeadBg)
        : PdfColors.grey100;
    final textColor = themeConfig != null
        ? _pdf(themeConfig.textColor)
        : PdfColors.grey900;

    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerBg),
        children: headers.map((h) {
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: _buildRichText(
              h,
              regularFont: regularFont,
              boldFont: boldFont,
              themeConfig: themeConfig,
              fontSize: 9,
              textColor: textColor,
              isBold: true,
            ),
          );
        }).toList(),
      ),
    );

    for (int r = 2; r < tableLines.length; r++) {
      final cells = parseRow(tableLines[r]);
      while (cells.length < numCols) cells.add('');
      final truncatedCells = cells.take(numCols).toList();

      final rowBg = (r % 2 == 1 && themeConfig != null)
          ? _pdf(themeConfig.cardColor.withValues(alpha: 0.3))
          : null;

      rows.add(
        pw.TableRow(
          decoration: rowBg != null ? pw.BoxDecoration(color: rowBg) : null,
          children: truncatedCells.map((c) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: _buildRichText(
                c,
                regularFont: regularFont,
                boldFont: boldFont,
                themeConfig: themeConfig,
                fontSize: 8.5,
                textColor: textColor,
              ),
            );
          }).toList(),
        ),
      );
    }

    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 6 * scale),
      child: pw.Table(
        border: pw.TableBorder.all(color: tableBorderColor, width: 0.5),
        children: rows,
      ),
    );
  }

  pw.Widget _buildRichText(
    String text, {
    required pw.Font regularFont,
    required pw.Font boldFont,
    required MarkdownThemeConfig? themeConfig,
    required double fontSize,
    required PdfColor textColor,
    double lineSpacing = 2.5,
    pw.TextAlign textAlign = pw.TextAlign.left,
    bool isBold = false,
  }) {
    final baseStyle = pw.TextStyle(
      font: isBold ? boldFont : regularFont,
      fontSize: fontSize,
      color: textColor,
      lineSpacing: lineSpacing,
    );

    if (!text.contains('*') &&
        !text.contains('_') &&
        !text.contains('`') &&
        !text.contains('~') &&
        !text.contains('[') &&
        !text.contains('<')) {
      return pw.Text(
        text,
        style: baseStyle,
        textAlign: textAlign,
      );
    }

    try {
      final nodes = _inlineMdDoc.parseInline(text);
      if (nodes.isEmpty) {
        return pw.Text(text, style: baseStyle, textAlign: textAlign);
      }
      final spans = <pw.InlineSpan>[];
      for (final node in nodes) {
        spans.add(
          _mdNodeToPdfSpan(
            node,
            baseStyle: baseStyle,
            regularFont: regularFont,
            boldFont: boldFont,
            themeConfig: themeConfig,
          ),
        );
      }
      return pw.RichText(
        text: pw.TextSpan(children: spans),
        textAlign: textAlign,
      );
    } catch (_) {
      return pw.Text(
        text,
        style: baseStyle,
        textAlign: textAlign,
      );
    }
  }

  pw.InlineSpan _mdNodeToPdfSpan(
    md.Node node, {
    required pw.TextStyle baseStyle,
    required pw.Font regularFont,
    required pw.Font boldFont,
    required MarkdownThemeConfig? themeConfig,
  }) {
    if (node is md.Text) {
      return pw.TextSpan(text: node.text, style: baseStyle);
    }

    if (node is md.Element) {
      pw.TextStyle childStyle = baseStyle;

      switch (node.tag) {
        case 'strong':
        case 'b':
          childStyle = childStyle.copyWith(
            font: boldFont,
            fontWeight: pw.FontWeight.bold,
          );
          break;
        case 'em':
        case 'i':
          childStyle = childStyle.copyWith(
            fontStyle: pw.FontStyle.italic,
          );
          break;
        case 'code':
          final codeColor = themeConfig != null
              ? _pdf(themeConfig.codeTextColor)
              : PdfColors.pink800;
          final codeBg = themeConfig != null
              ? _pdf(themeConfig.cardColor)
              : PdfColors.grey200;
          childStyle = childStyle.copyWith(
            font: regularFont,
            color: codeColor,
            background: pw.BoxDecoration(
              color: codeBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
            ),
          );
          break;
        case 'del':
          childStyle = childStyle.copyWith(
            decoration: pw.TextDecoration.lineThrough,
          );
          break;
        case 'a':
          final linkColor = themeConfig != null
              ? _pdf(themeConfig.isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA))
              : PdfColors.blue700;
          childStyle = childStyle.copyWith(
            color: linkColor,
            decoration: pw.TextDecoration.underline,
          );
          break;
      }

      final children = node.children;
      if (children == null || children.isEmpty) {
        return pw.TextSpan(text: node.textContent, style: childStyle);
      }

      final childSpans = <pw.InlineSpan>[];
      for (final child in children) {
        childSpans.add(
          _mdNodeToPdfSpan(
            child,
            baseStyle: childStyle,
            regularFont: regularFont,
            boldFont: boldFont,
            themeConfig: themeConfig,
          ),
        );
      }

      return pw.TextSpan(children: childSpans, style: childStyle);
    }

    return pw.TextSpan(text: node.textContent, style: baseStyle);
  }

  /// Opens print dialog or system preview.
  Future<void> printOrPreview({
    required String markdown,
    required String title,
    MarkdownThemeConfig? themeConfig,
    PdfMarginMode marginMode = PdfMarginMode.standard,
  }) async {
    await Printing.layoutPdf(
      onLayout: (format) => generatePdf(
        markdown: markdown,
        title: title,
        themeConfig: themeConfig,
        marginMode: marginMode,
      ),
      name: '$title.pdf',
    );
  }

  /// Shares generated PDF directly.
  Future<void> sharePdf({
    required String markdown,
    required String title,
    MarkdownThemeConfig? themeConfig,
    PdfMarginMode marginMode = PdfMarginMode.standard,
  }) async {
    final bytes = await generatePdf(
      markdown: markdown,
      title: title,
      themeConfig: themeConfig,
      marginMode: marginMode,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '$title.pdf',
    );
  }
}

class _PdfHighlightRenderer implements HighlightRenderer {
  final pw.TextStyle baseStyle;
  final Map<String, TextStyle> theme;
  final List<_PdfHighlightSpan> _stack = [];
  final List<pw.TextSpan> _results = [];

  _PdfHighlightRenderer(this.baseStyle, this.theme);

  @override
  void addText(String text) {
    if (_stack.isEmpty) {
      _results.add(pw.TextSpan(text: text, style: baseStyle));
    } else {
      final top = _stack.removeLast();
      final scope = top.node.scope;
      pw.TextStyle spanStyle = baseStyle;
      if (scope != null && theme.containsKey(scope)) {
        final flutterStyle = theme[scope];
        if (flutterStyle?.color != null) {
          spanStyle = baseStyle.copyWith(
            color: PdfColor.fromInt(flutterStyle!.color!.toARGB32()),
          );
        }
      }
      _stack.add(top.addSpan(pw.TextSpan(text: text, style: spanStyle)));
    }
  }

  @override
  void closeNode(DataNode node) {
    final top = _stack.removeLast();
    final span = top.toSpan();
    if (_stack.isNotEmpty) {
      _stack.last = _stack.last.addSpan(span);
    } else {
      _results.add(span);
    }
  }

  @override
  void openNode(DataNode node) {
    _stack.add(_PdfHighlightSpan(node: node, style: baseStyle));
  }

  pw.TextSpan? get span {
    if (_results.isEmpty) return null;
    if (_results.length == 1) return _results.first;
    return pw.TextSpan(children: _results);
  }
}

class _PdfHighlightSpan {
  final DataNode node;
  final pw.TextStyle style;
  final List<pw.InlineSpan> children;

  _PdfHighlightSpan({
    required this.node,
    required this.style,
    List<pw.InlineSpan>? children,
  }) : children = children ?? [];

  _PdfHighlightSpan addSpan(pw.InlineSpan span) {
    return _PdfHighlightSpan(
      node: node,
      style: style,
      children: [...children, span],
    );
  }

  pw.TextSpan toSpan() {
    return pw.TextSpan(
      style: style,
      children: children,
    );
  }
}
