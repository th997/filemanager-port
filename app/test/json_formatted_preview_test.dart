import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/structured_viewer_page.dart';
import 'package:filemanager/src/widgets/json_formatted_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonFormatter', () {
    test('formats minified JSON with 2 or 4 spaces and optional sorted keys', () {
      const raw = '{"z":1,"a":{"d":true,"b":[null,"hi"]}}';

      final twoSpace = JsonFormatter.format(raw, indentSpaces: 2);
      expect(twoSpace.isValid, isTrue);
      expect(twoSpace.formatted, contains('  "z": 1,'));
      expect(twoSpace.minified, raw);

      final fourSpaceSorted =
          JsonFormatter.format(raw, indentSpaces: 4, sortKeys: true);
      expect(fourSpaceSorted.isValid, isTrue);
      final idxA = fourSpaceSorted.formatted.indexOf('"a"');
      final idxZ = fourSpaceSorted.formatted.indexOf('"z"');
      final idxB = fourSpaceSorted.formatted.indexOf('"b"');
      final idxD = fourSpaceSorted.formatted.indexOf('"d"');
      expect(idxA, lessThan(idxZ));
      expect(idxB, lessThan(idxD));
      expect(fourSpaceSorted.formatted, contains('    "a": {'));
    });

    test('reports invalid JSON gracefully', () {
      final invalid = JsonFormatter.format('{"broken": }');
      expect(invalid.isValid, isFalse);
      expect(invalid.errorMessage, isNotEmpty);
    });

    test('highlightLine distinguishes keys, values, and search matches', () {
      final span = JsonFormatter.highlightLine(
        '  "name": "Alice",',
        brightness: Brightness.dark,
        query: 'alice',
        isActiveMatchLine: true,
      );
      expect(span.toPlainText(), '  "name": "Alice",');
      expect(span.children, isNotNull);
      final hasMatchHighlight = span.children!.any(
        (child) =>
            child is TextSpan &&
            child.text == 'Alice' &&
            child.style?.backgroundColor != null,
      );
      expect(hasMatchHighlight, isTrue);
    });
  });

  group('StructuredViewerPage JSON formatted preview widget tests', () {
    testWidgets('opens JSON in formatted preview by default and toggles options',
        (tester) async {
      const rawJson = '{"zebra":42,"alpha":"hello","nested":{"flag":true}}';

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StructuredViewerPage(
            root: '/tmp',
            path: 'sample.json',
            fileName: 'sample.json',
            initialContent: rawJson,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Defaults to Formatted Preview mode showing JsonFormattedPreviewWidget
      expect(find.byType(JsonFormattedPreviewWidget), findsOneWidget);
      expect(find.text('格式化预览'), findsOneWidget);
      expect(find.text('树形视图'), findsOneWidget);
      expect(find.text('2 空格'), findsOneWidget);

      // Toggle indent to 4 spaces
      await tester.tap(find.text('2 空格'));
      await tester.pumpAndSettle();
      expect(find.text('4 空格'), findsOneWidget);

      // Toggle sort keys
      await tester.tap(find.text('按键排序'));
      await tester.pumpAndSettle();

      // Switch to Tree view and back to Formatted preview
      await tester.tap(find.text('树形视图'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonFormattedPreviewWidget), findsNothing);
      expect(find.text('zebra: '), findsOneWidget);

      await tester.tap(find.text('格式化预览'));
      await tester.pumpAndSettle();
      expect(find.byType(JsonFormattedPreviewWidget), findsOneWidget);
    });
  });
}
