import 'dart:ui';
import 'package:filemanager/src/services/markdown_pdf_service.dart';
import 'package:filemanager/src/theme/markdown_themes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Markdown Themes Test', () {
    test('All theme types return valid configs for dark and light', () {
      for (final type in MarkdownThemeType.values) {
        final lightConfig = MarkdownThemeConfig.get(type, Brightness.light);
        final darkConfig = MarkdownThemeConfig.get(type, Brightness.dark);

        expect(lightConfig.type, equals(type));
        expect(darkConfig.type, equals(type));
        expect(lightConfig.textColor, isNotNull);
        expect(darkConfig.textColor, isNotNull);
        expect(lightConfig.backgroundColor, isNotNull);
        expect(darkConfig.backgroundColor, isNotNull);
        expect(lightConfig.highlightTheme, isNotEmpty);
      }
    });

    test('Theme id parsing works with fallback', () {
      expect(MarkdownThemeType.fromId('dracula'), equals(MarkdownThemeType.dracula));
      expect(MarkdownThemeType.fromId('solarized_dark'), equals(MarkdownThemeType.solarizedDark));
      expect(MarkdownThemeType.fromId('vibrant'), equals(MarkdownThemeType.vibrant));
      expect(MarkdownThemeType.fromId('unknown_id'), equals(MarkdownThemeType.github));
      expect(MarkdownThemeType.fromId(null), equals(MarkdownThemeType.github));
    });
  });

  group('Markdown PDF Generation Test', () {
    test('Generates PDF with Chinese and code blocks without errors', () async {
      const sampleMarkdown = '''
# 欢迎使用文件管理器

这是一个 Markdown 测试文档。

## 代码块示例

```dart
void main() {
  print("Hello, Flutter!");
}
```

### 提示框

> [!NOTE]
> 这是一个测试提示框。

> [!TIP]
> 这是一个技巧。

- 项目一
- 项目二
- 项目三

1. 第一步
2. 第二步

---

普通段落结束。
''';

      final bytes = await MarkdownPdfService.instance.generatePdf(
        markdown: sampleMarkdown,
        title: '测试文档',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
      // PDF header check (%PDF-)
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, equals('%PDF-'));
    });

    test('Generates themed PDFs (Dracula, Sepia, Vibrant) without header/footer', () async {
      const sampleMarkdown = '''
# 深度主题测试

正文内容段落。

```dart
final x = 42;
```

> [!NOTE]
> 提示信息
''';

      for (final type in [MarkdownThemeType.dracula, MarkdownThemeType.sepia, MarkdownThemeType.vibrant]) {
        final config = MarkdownThemeConfig.get(type, Brightness.dark);
        final bytes = await MarkdownPdfService.instance.generatePdf(
          markdown: sampleMarkdown,
          title: '主题测试',
          themeConfig: config,
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(500));
        final header = String.fromCharCodes(bytes.take(5));
        expect(header, equals('%PDF-'));
      }
    });

    test('PdfMarginMode parsing and generation with different margins', () async {
      expect(PdfMarginMode.fromId('compact'), equals(PdfMarginMode.compact));
      expect(PdfMarginMode.fromId('standard'), equals(PdfMarginMode.standard));
      expect(PdfMarginMode.fromId('relaxed'), equals(PdfMarginMode.relaxed));
      expect(PdfMarginMode.fromId('invalid'), equals(PdfMarginMode.standard));

      for (final marginMode in PdfMarginMode.values) {
        final bytes = await MarkdownPdfService.instance.generatePdf(
          markdown: '# 边距测试\n\n段落内容\n\n```dart\nvar a = 1;\n```',
          title: '边距测试',
          marginMode: marginMode,
        );
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(300));
      }
    });
  });
}
