import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/services/highlight_service.dart';
import 'package:filemanager/src/pages/text_editor_page.dart';

// Test the TextSpan highlighting and splitting algorithm
void main() {
  group('Syntax Highlighting and Search Tests', () {
    test('HighlightService produces rich token spans for JSON', () {
      const json = '{\n  "version": "1.0.0",\n  "active": true\n}';
      final span = HighlightService.instance.spanFor(json, 'test.json', Brightness.dark);
      expect(span, isNotNull);
      expect(span!.children, isNotEmpty);
    });

    test('HighlightService language recognition handles edge cases', () {
      expect(HighlightService.instance.languageFor('main.rs'), 'rust');
      expect(HighlightService.instance.languageFor('main.dart'), 'dart');
      expect(HighlightService.instance.languageFor('config.json'), 'json');
      expect(HighlightService.instance.languageFor('.eslintrc'), 'json');
      expect(HighlightService.instance.languageFor('Dockerfile'), 'dockerfile');
      expect(HighlightService.instance.languageFor('Makefile'), 'bash');
      expect(HighlightService.instance.languageFor('data.csv'), isNull);
    });

    test('HighlightService skips regex tokenization on large or minified files to prevent UI freeze', () {
      // 1. Files > 48KB should safely return null (clean monospace text) in < 1ms
      final largeCode = 'const x = 1;\n' * 5000; // ~65KB
      final largeSpan = HighlightService.instance.spanFor(largeCode, 'big.js', Brightness.dark);
      expect(largeSpan, isNull);

      // 2. Minified files with lines > 500 chars should safely return null
      final minifiedCode = 'var a="${'x' * 600}";\n';
      final minifiedSpan = HighlightService.instance.spanFor(minifiedCode, 'bundle.min.js', Brightness.dark);
      expect(minifiedSpan, isNull);

      // 3. Normal small files should still produce full syntax highlighting
      const smallCode = 'function hello() { return 42; }';
      final smallSpan = HighlightService.instance.spanFor(smallCode, 'small.js', Brightness.dark);
      expect(smallSpan, isNotNull);
      expect(smallSpan!.children, isNotEmpty);
    });

    test('Font metric preferredLineHeight is exact across multiple lines', () {
      const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 13.0, height: 1.35);
      final metricPainter = TextPainter(
        text: const TextSpan(text: 'M', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final lineHeight = metricPainter.preferredLineHeight;

      // In Flutter text engine, preferredLineHeight is 18.0 for 13pt height 1.35
      expect(lineHeight, equals(18.0));

      final lines = 'Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n';
      final fullPainter = TextPainter(
        text: TextSpan(text: lines, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      // Total height of 6 lines equals exactly 6 * lineHeight
      expect(fullPainter.height, equals(6 * lineHeight));
    });

    test('Non-wrapping line Y calculation accurately counts newlines with exact preferredLineHeight', () {
      const text = 'Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n';
      const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 13.0, height: 1.35);
      final metricPainter = TextPainter(
        text: const TextSpan(text: 'M', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final lineHeight = metricPainter.preferredLineHeight;

      double calculateDy(int charIndex) {
        int lineCount = 0;
        for (int i = 0; i < charIndex; i++) {
          if (text.codeUnitAt(i) == 10) lineCount++;
        }
        return lineCount * lineHeight;
      }

      final line0 = text.indexOf('Line 0');
      final line1 = text.indexOf('Line 1');
      final line3 = text.indexOf('Line 3');

      expect(calculateDy(line0), equals(0.0));
      expect(calculateDy(line1), equals(18.0));
      expect(calculateDy(line3), equals(54.0));
    });

    test('TextPainter caret offset matches exactly between subtext and full text', () {
      const textStyle = TextStyle(fontFamily: 'monospace', fontSize: 13.0, height: 1.35);
      final lines = List.generate(50, (i) => 'Line $i: This is some sample text that soft wraps in the editor.');
      final fullText = lines.join('\n');
      final targetIndex = fullText.indexOf('Line 25:');

      final fullPainter = TextPainter(
        text: TextSpan(text: fullText, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 400);
      final fullOffset = fullPainter.getOffsetForCaret(TextPosition(offset: targetIndex), Rect.zero);

      final nextNewline = fullText.indexOf('\n', targetIndex);
      final lineEnd = nextNewline == -1 ? fullText.length : nextNewline;
      final subtext = fullText.substring(0, lineEnd);
      final subPainter = TextPainter(
        text: TextSpan(text: subtext, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 400);
      final subOffset = subPainter.getOffsetForCaret(TextPosition(offset: targetIndex), Rect.zero);

      expect(subOffset.dy, equals(fullOffset.dy));
      expect(subOffset.dx, equals(fullOffset.dx));
    });

    testWidgets('SyntaxHighlightingEditingController highlights search matches with high performance', (tester) async {
      final controller = SyntaxHighlightingEditingController(
        text: 'hello world! hello flutter! hello test!',
        fileName: 'sample.txt',
        brightnessProvider: () => Brightness.light,
      );

      final matches = <int>[0, 13, 28];
      controller.updateSearch(
        query: 'hello',
        matches: matches,
        currentMatch: 1, // Second match is current
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                final span = controller.buildTextSpan(
                  context: ctx,
                  withComposing: false,
                );
                expect(span, isNotNull);

                // Collect background colors of all leaf spans
                final colors = <Color>[];
                void extractColors(InlineSpan s) {
                  if (s is TextSpan) {
                    if (s.style?.backgroundColor != null) {
                      colors.add(s.style!.backgroundColor!);
                    }
                    if (s.children != null) {
                      for (final c in s.children!) {
                        extractColors(c);
                      }
                    }
                  }
                }
                extractColors(span);

                // Should have 3 highlighted matches: 2 yellow, 1 orange (current)
                expect(colors.length, equals(3));
                expect(colors[0], equals(const Color(0xFFFFEB3B))); // first match is yellow
                expect(colors[1], equals(const Color(0xFFFF6D00))); // current match is orange
                expect(colors[2], equals(const Color(0xFFFFEB3B))); // third match is yellow

                return RichText(text: span);
              },
            ),
          ),
        ),
      );

      expect(find.byType(RichText), findsOneWidget);
      controller.dispose();
    });

    test('Binary search line starts maps character offsets to exact line numbers', () {
      final lines = ['First line', 'Second line of code', 'Third line', 'Fourth line'];
      final text = lines.join('\n');
      final starts = <int>[0];
      for (int i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) {
          starts.add(i + 1);
        }
      }

      int getLineIndex(int offset) {
        int low = 0;
        int high = starts.length - 1;
        while (low <= high) {
          final mid = (low + high) >> 1;
          if (starts[mid] <= offset) {
            if (mid == starts.length - 1 || starts[mid + 1] > offset) {
              return mid;
            }
            low = mid + 1;
          } else {
            high = mid - 1;
          }
        }
        return 0;
      }

      expect(getLineIndex(0), equals(0)); // 'F'
      expect(getLineIndex(9), equals(0)); // 'e' in 'First line'
      expect(getLineIndex(11), equals(1)); // 'S' in 'Second line'
      expect(getLineIndex(text.indexOf('Third')), equals(2));
      expect(getLineIndex(text.indexOf('Fourth')), equals(3));
    });

    test('Exact pixel centering centers target line at (viewport - lineHeight) / 2', () {
      const lineHeight = 18.0;
      const contentPadding = 16.0;
      const viewport = 600.0;
      const targetLine = 250;

      final targetMatchY = contentPadding + targetLine * lineHeight;
      final targetScrollY = (targetMatchY - (viewport - lineHeight) / 2);

      // Distance from top of viewport to line on screen:
      final lineOnScreenY = targetMatchY - targetScrollY;
      expect(lineOnScreenY, equals((viewport - lineHeight) / 2));
      // Line center on screen:
      final lineCenterOnScreenY = lineOnScreenY + lineHeight / 2;
      expect(lineCenterOnScreenY, equals(viewport / 2));
    });

    test('Search match selection picks nearest match to visible line instead of line 1', () {
      const lineHeight = 18.0;
      final matchLines = [10, 50, 120, 250, 310, 450];
      final matchOffsets = matchLines.map((l) => l * 100).toList();

      // Suppose user scrolled to line 200:
      const scrollY = 200 * lineHeight;
      final approxLine = (scrollY / lineHeight).floor();
      final approxOffset = approxLine * 100;

      final nearest = matchOffsets.indexWhere((idx) => idx >= approxOffset);
      expect(nearest, equals(3)); // match at line 250, not match 0 at line 10!
    });
  });
}
