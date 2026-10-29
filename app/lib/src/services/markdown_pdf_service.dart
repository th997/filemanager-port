import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Exports Markdown content to a PDF document with proper formatting,
/// code block highlighting, and Chinese/Unicode font support.
class MarkdownPdfService {
  static final MarkdownPdfService instance = MarkdownPdfService._();
  MarkdownPdfService._();

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

  /// Generates a PDF byte stream from Markdown text.
  Future<Uint8List> generatePdf({
    required String markdown,
    required String title,
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

    final widgets = _parseMarkdownToPdfWidgets(markdown, regularFont, boldFont);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        ),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) => widgets,
      ),
    );

    return pdf.save();
  }

  /// Parses Markdown lines into a list of pdf widgets.
  List<pw.Widget> _parseMarkdownToPdfWidgets(
    String markdown,
    pw.Font regularFont,
    pw.Font boldFont,
  ) {
    final List<pw.Widget> result = [];
    final lines = const LineSplitter().convert(markdown);

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
            _buildCodeBlock(codeBuffer.join('\n'), codeLang, regularFont),
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
        result.add(pw.SizedBox(height: 6));
        continue;
      }

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 8),
            child: pw.Divider(color: PdfColors.grey300, thickness: 1),
          ),
        );
        continue;
      }

      // Headings
      if (trimmed.startsWith('# ')) {
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
            child: pw.Text(
              trimmed.substring(2).trim(),
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 20,
                color: PdfColors.blueGrey900,
              ),
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('## ')) {
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
            child: pw.Text(
              trimmed.substring(3).trim(),
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 16,
                color: PdfColors.blueGrey800,
              ),
            ),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('### ')) {
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(
              trimmed.substring(4).trim(),
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 13,
                color: PdfColors.blueGrey700,
              ),
            ),
          ),
        );
        continue;
      }

      // Blockquotes & Callouts
      if (trimmed.startsWith('>')) {
        final quoteText = trimmed.substring(1).trim();
        result.add(_buildBlockquote(quoteText, regularFont, boldFont));
        continue;
      }

      // Unordered lists
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('+ ')) {
        final itemText = trimmed.substring(2).trim();
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 4,
                  height: 4,
                  margin: const pw.EdgeInsets.only(top: 5, right: 8),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey700,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    itemText,
                    style: pw.TextStyle(
                      font: regularFont,
                      fontSize: 10,
                      lineSpacing: 2,
                    ),
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
        result.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 16,
                  child: pw.Text(
                    '$numStr.',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    itemText,
                    style: pw.TextStyle(
                      font: regularFont,
                      fontSize: 10,
                      lineSpacing: 2,
                    ),
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
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(
            trimmed,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 10,
              lineSpacing: 3,
              color: PdfColors.grey900,
            ),
          ),
        ),
      );
    }

    if (inCodeBlock && codeBuffer.isNotEmpty) {
      result.add(
        _buildCodeBlock(codeBuffer.join('\n'), codeLang, regularFont),
      );
    }

    return result;
  }

  pw.Widget _buildCodeBlock(String code, String? lang, pw.Font font) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.symmetric(vertical: 6),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
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
                  color: PdfColors.grey600,
                ),
              ),
            ),
          pw.Text(
            code,
            style: pw.TextStyle(
              font: font,
              fontSize: 8.5,
              lineSpacing: 2,
              color: PdfColors.grey900,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBlockquote(String text, pw.Font regularFont, pw.Font boldFont) {
    PdfColor accent = PdfColors.blue600;
    PdfColor bg = PdfColors.blue50;
    String cleanText = text;
    String? title;

    if (text.startsWith('[!NOTE]')) {
      accent = PdfColors.blue700;
      bg = PdfColors.blue50;
      title = 'Note';
      cleanText = text.substring('[!NOTE]'.length).trim();
    } else if (text.startsWith('[!TIP]')) {
      accent = PdfColors.green700;
      bg = PdfColors.green50;
      title = 'Tip';
      cleanText = text.substring('[!TIP]'.length).trim();
    } else if (text.startsWith('[!IMPORTANT]')) {
      accent = PdfColors.purple700;
      bg = PdfColors.purple50;
      title = 'Important';
      cleanText = text.substring('[!IMPORTANT]'.length).trim();
    } else if (text.startsWith('[!WARNING]')) {
      accent = PdfColors.amber800;
      bg = PdfColors.amber50;
      title = 'Warning';
      cleanText = text.substring('[!WARNING]'.length).trim();
    } else if (text.startsWith('[!CAUTION]')) {
      accent = PdfColors.red700;
      bg = PdfColors.red50;
      title = 'Caution';
      cleanText = text.substring('[!CAUTION]'.length).trim();
    }

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
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
          pw.Text(
            cleanText,
            style: pw.TextStyle(
              font: regularFont,
              fontSize: 9.5,
              lineSpacing: 2,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens print dialog or system preview.
  Future<void> printOrPreview({
    required String markdown,
    required String title,
  }) async {
    await Printing.layoutPdf(
      onLayout: (format) => generatePdf(markdown: markdown, title: title),
      name: '$title.pdf',
    );
  }

  /// Shares generated PDF directly.
  Future<void> sharePdf({
    required String markdown,
    required String title,
  }) async {
    final bytes = await generatePdf(markdown: markdown, title: title);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '$title.pdf',
    );
  }
}
