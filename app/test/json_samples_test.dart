import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/services/highlight_service.dart';

void main() {
  test('HighlightService highlights JSON tokens with tuned colors', () {
    const jsonCode = '{\n  "name": "filemanager",\n  "count": 42,\n  "enabled": true\n}';
    final span = HighlightService.instance.spanFor(
      jsonCode,
      'config.json',
      Brightness.light,
    );

    expect(span, isNotNull);

    final colors = <Color>[];
    void collectColors(InlineSpan s) {
      if (s is TextSpan) {
        if (s.style?.color != null) {
          colors.add(s.style!.color!);
        }
        if (s.children != null) {
          for (final child in s.children!) {
            collectColors(child);
          }
        }
      }
    }

    collectColors(span!);

    // Should include key color (0xFF005CC5), string/number color (0xFF098658),
    // literal boolean color (0xFFD73A49), and punctuation color (0xFF586069)
    expect(colors, contains(const Color(0xFF005CC5)));
    expect(colors, contains(const Color(0xFF098658)));
    expect(colors, contains(const Color(0xFFD73A49)));
    expect(colors, contains(const Color(0xFF586069)));
  });

  test('HighlightService recognizes extended JSON extensions', () {
    expect(HighlightService.instance.languageFor('settings.jsonc'), 'json');
    expect(HighlightService.instance.languageFor('data.geojson'), 'json');
    expect(HighlightService.instance.languageFor('pubspec.lock'), 'json');
    expect(HighlightService.instance.languageFor('.eslintrc'), 'json');
  });

  test('HighlightService languageFor handles paths and uppercase extensions', () {
    expect(HighlightService.instance.languageFor('/path/to/FILE.JSON'), 'json');
    expect(HighlightService.instance.languageFor('folder/sub/data.GeoJson'), 'json');
    expect(HighlightService.instance.languageFor('http://example.com/api/config.json?v=123'), 'json');
  });
}
