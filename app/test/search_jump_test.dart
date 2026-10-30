import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/services/highlight_service.dart';

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
  });
}
