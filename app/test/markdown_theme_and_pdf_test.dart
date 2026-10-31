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

    test('Generates PDF with inline markdown styles and tables', () async {
      const complexMarkdown = '''
# 综合样式测试

这里是普通段落，包含 **粗体文字** 和 *斜体文字*，以及 ***粗斜体***。
还支持 `行内代码` 和 ~~删除线文本~~ 以及 [链接标签](https://example.com)。

## 列表与格式组合
- **项目 A**：包含 *斜体说明* 和 `代码提示`
- **项目 B**：普通说明
  - 缩进子项目 **子重点**

1. **第一步**：执行 `flutter test`
2. **第二步**：验证结果

### 表格测试
| 功能特性 | 支持平台 | 状态 |
| :--- | :---: | ---: |
| **PDF 导出** | 全平台 | 已就绪 |
| **语法高亮** | iOS/Android/桌面 | *完全支持* |
''';

      final bytes = await MarkdownPdfService.instance.generatePdf(
        markdown: complexMarkdown,
        title: '格式与表格测试',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, equals('%PDF-'));
    });

    test('Generates PDF with CJK characters without font fallback warnings', () async {
      const cjkMarkdown = '''
# 简体中文与多语言混合排版验证

本文档验证 Markdown 转 PDF 导出中的中文字符、英文字母、阿拉伯数字及特殊标点符号的排版呈现。

## 字符集覆盖
- 中文字符：天地玄黄，宇宙洪荒。日月盈昃，辰宿列张。
- 英文字符：The quick brown fox jumps over the lazy dog.
- 数字序列：0123456789 (货币：￥100, \$50, €30)
- 标点符号：！@#￥%……&*（）——+【】{}；：‘“’”，。、《》？

```dart
// 中文注释与字符串
void greet() {
  print("你好，世界！Count: 42");
}
```

> [!NOTE]
> 提示信息：中文引用块正常渲染。

| 序号 | 模块名称 | 描述 |
|---|---|---|
| 1 | 文件浏览 | 支持树形结构展示 |
| 2 | PDF 导出 | 解决中文字体乱码问题 |
''';

      final bytes = await MarkdownPdfService.instance.generatePdf(
        markdown: cjkMarkdown,
        title: 'CJK 排版验证',
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(2000));
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, equals('%PDF-'));
    });
  });
}
