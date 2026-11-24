import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:filemanager/src/pages/pdf_viewer_page.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _buildSyntheticPdf(List<({int id, List<int> body})> objects) {
  final bytes = <int>[];
  bytes.addAll(latin1.encode('%PDF-1.4\n'));
  for (final obj in objects) {
    bytes.addAll(latin1.encode('${obj.id} 0 obj\n'));
    bytes.addAll(obj.body);
    bytes.addAll(latin1.encode('\nendobj\n'));
  }
  bytes.addAll(latin1.encode('%%EOF\n'));
  return Uint8List.fromList(bytes);
}

List<int> _makeFlateStreamObj(List<int> compressedPayload) {
  final out = <int>[];
  out.addAll(
    latin1.encode(
      '<< /Length ${compressedPayload.length} /Filter /FlateDecode >>\nstream\n',
    ),
  );
  out.addAll(compressedPayload);
  out.addAll(latin1.encode('\nendstream'));
  return out;
}

void main() {
  group('PdfDocumentInspector', () {
    test('decodePdfString decodes literal escapes, octal, and UTF-16BE hex/literal', () {
      expect(PdfDocumentInspector.decodePdfString(r'(Hello \(PDF\) \\ Test)'), r'Hello (PDF) \ Test');
      expect(PdfDocumentInspector.decodePdfString(r'(\101\102)'), 'AB');
      expect(PdfDocumentInspector.decodePdfString('<FEFF4E2D6587>'), '中文');
      expect(PdfDocumentInspector.decodePdfString('<fe ff 6d4b 8bd5>'), '测试');
    });

    test('extractOutline resolves real /Pages indices, nested levels, and indirect /A GoTo actions', () {
      final pdf = _buildSyntheticPdf([
        (id: 1, body: latin1.encode('<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R >>')),
        (id: 2, body: latin1.encode('<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>')),
        (id: 3, body: latin1.encode('<< /Type /Page /Parent 2 0 R >>')),
        (id: 4, body: latin1.encode('<< /Type /Page /Parent 2 0 R >>')),
        (id: 5, body: latin1.encode('<< /Type /Page /Parent 2 0 R >>')),
        (id: 6, body: latin1.encode('<< /Type /Outlines /First 7 0 R /Last 9 0 R >>')),
        (
          id: 7,
          body: latin1.encode(
            '<< /Title <FEFF7B2C4E007AE0> /Parent 6 0 R /Dest [4 0 R /Fit] /First 8 0 R /Next 9 0 R >>',
          ),
        ),
        (
          id: 8,
          body: latin1.encode(
            '<< /Title (Subchapter 1.1) /Parent 7 0 R /A << /S /GoTo /D [5 0 R /XYZ 0 700 0] >> >>',
          ),
        ),
        (
          id: 9,
          body: latin1.encode(
            '<< /Title (Back to Cover) /Parent 6 0 R /A 10 0 R >>',
          ),
        ),
        (
          id: 10,
          body: latin1.encode('<< /S /GoTo /D [3 0 R /Fit] >>'),
        ),
      ]);

      final outline = PdfDocumentInspector.extractOutline(pdf, 3);
      expect(outline.length, 3);
      expect(outline[0].title, '第一章');
      expect(outline[0].pageIndex, 1);
      expect(outline[0].level, 0);

      expect(outline[1].title, 'Subchapter 1.1');
      expect(outline[1].pageIndex, 2);
      expect(outline[1].level, 1);

      expect(outline[2].title, 'Back to Cover');
      expect(outline[2].pageIndex, 0);
      expect(outline[2].level, 0);
    });

    test('extractPageTexts decodes /ToUnicode CMap and FlateDecode streams per page', () {
      const cmapBody = '''
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<0001> <4E2D>
<0002> <6587>
endbfchar
1 beginbfrange
<0010> <0011> <0041>
endbfrange
endcmap
''';
      final page1Content = 'BT (<0010>) Tj [<00010002>] TJ ET';
      final page2Flate = zlib.encode(latin1.encode('BT (Plain Hello) Tj ET'));

      final pdf = _buildSyntheticPdf([
        (id: 1, body: latin1.encode('<< /Type /Catalog /Pages 2 0 R >>')),
        (id: 2, body: latin1.encode('<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>')),
        (id: 3, body: latin1.encode('<< /Type /Page /Parent 2 0 R /Contents 5 0 R >>')),
        (id: 4, body: latin1.encode('<< /Type /Page /Parent 2 0 R /Contents 6 0 R >>')),
        (
          id: 5,
          body: latin1.encode(
            '<< /Length ${page1Content.length} >>\nstream\n$page1Content\nendstream',
          ),
        ),
        (id: 6, body: _makeFlateStreamObj(page2Flate)),
        (
          id: 7,
          body: latin1.encode(
            '<< /Length ${cmapBody.length} >>\nstream\n$cmapBody\nendstream',
          ),
        ),
      ]);

      final pages = PdfDocumentInspector.extractPageTexts(pdf);
      expect(pages.length, 2);
      expect(pages[0], contains('中文'));
      expect(pages[1], contains('Plain Hello'));

      // Also verify beginbfrange decoded glyph <0010> -> 'A' via Tj hex token
      final pdfRange = _buildSyntheticPdf([
        (id: 1, body: latin1.encode('<< /Type /Catalog /Pages 2 0 R >>')),
        (id: 2, body: latin1.encode('<< /Type /Pages /Kids [3 0 R] /Count 1 >>')),
        (id: 3, body: latin1.encode('<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>')),
        (
          id: 4,
          body: latin1.encode(
            '<< /Length 21 >>\nstream\nBT <00100011> Tj ET\nendstream',
          ),
        ),
        (
          id: 5,
          body: latin1.encode(
            '<< /Length ${cmapBody.length} >>\nstream\n$cmapBody\nendstream',
          ),
        ),
      ]);
      final rangePages = PdfDocumentInspector.extractPageTexts(pdfRange);
      expect(rangePages.length, 1);
      expect(rangePages[0], contains('AB'));
    });

    test('unpacks /ObjStm compressed objects for outline, page count, and text, and detects /Encrypt', () {
      const obj10 = '<< /Type /Page /Parent 2 0 R /Contents 11 0 R >>';
      const obj11 = '<< /Type /Catalog /Pages 2 0 R /Outlines 12 0 R >>';
      const obj12 = '<< /Type /Outlines /First 13 0 R /Last 13 0 R >>';
      const obj13 = '<< /Title (Compressed Chapter) /Parent 12 0 R /Dest [10 0 R /Fit] >>';
      final bodyBuf = StringBuffer();
      final offsets = <(int, int)>[];
      for (final item in [(10, obj10), (11, obj11), (12, obj12), (13, obj13)]) {
        offsets.add((item.$1, bodyBuf.length));
        bodyBuf.write(item.$2);
      }
      final header = '${offsets.map((e) => '${e.$1} ${e.$2}').join(' ')} ';
      final first = header.length;
      final objStmCompressed = zlib.encode(latin1.encode('$header$bodyBuf'));

      final pdf = _buildSyntheticPdf([
        (id: 2, body: latin1.encode('<< /Type /Pages /Kids [10 0 R] /Count 1 >>')),
        (
          id: 9,
          body: [
            ...latin1.encode(
              '<< /Type /ObjStm /N 4 /First $first /Length ${objStmCompressed.length} /Filter /FlateDecode >>\nstream\n',
            ),
            ...objStmCompressed,
            ...latin1.encode('\nendstream'),
          ],
        ),
      ]);

      expect(PdfDocumentInspector.isEncrypted(pdf), isFalse);
      expect(PdfDocumentInspector.estimatePageCount(pdf), 1);
      final outline = PdfDocumentInspector.extractOutline(pdf, 1);
      expect(outline.length, 1);
      expect(outline.first.title, 'Compressed Chapter');
      expect(outline.first.pageIndex, 0);

      final encryptedPdf = _buildSyntheticPdf([
        (id: 1, body: latin1.encode('<< /Type /Catalog /Pages 2 0 R >>')),
        (id: 2, body: latin1.encode('<< /Type /Pages /Count 3 >>')),
        (id: 99, body: latin1.encode('<< /Filter /Standard /V 2 /R 3 /Encrypt << /O <00> >> >>')),
      ]);
      expect(PdfDocumentInspector.isEncrypted(encryptedPdf), isTrue);
      expect(PdfDocumentInspector.estimatePageCount(encryptedPdf), 3);
    });
  });
}
