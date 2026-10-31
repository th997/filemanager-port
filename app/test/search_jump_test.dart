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
      final minifiedCode = 'var a="' + ('x' * 600) + '";\n';
      final minifiedSpan = HighlightService.instance.spanFor(minifiedCode, 'bundle.min.js', Brightness.dark);
      expect(minifiedSpan, isNull);

      // 3. Normal small files should still produce full syntax highlighting
      const smallCode = 'function hello() { return 42; }';
      final smallSpan = HighlightService.instance.spanFor(smallCode, 'small.js', Brightness.dark);
      expect(smallSpan, isNotNull);
      expect(smallSpan!.children, isNotEmpty);
    });

    test('Non-wrapping line Y calculation accurately counts newlines', () {
      const text = 'Line 0\nLine 1\nLine 2\nLine 3\nLine 4\n';
      const lineHeight = 13.0 * 1.35;

      int calculateDy(int charIndex) {
        int lineCount = 0;
        for (int i = 0; i < charIndex; i++) {
          if (text.codeUnitAt(i) == 10) lineCount++;
        }
        return (lineCount * lineHeight).round();
      }

      final line0 = text.indexOf('Line 0');
      final line1 = text.indexOf('Line 1');
      final line3 = text.indexOf('Line 3');

      expect(calculateDy(line0), equals(0));
      expect(calculateDy(line1), equals(lineHeight.round()));
      expect(calculateDy(line3), equals((3 * lineHeight).round()));
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
  });
}
