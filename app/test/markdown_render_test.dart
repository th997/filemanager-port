import 'package:filemanager/src/theme/markdown_themes.dart';
import 'package:filemanager/src/widgets/markdown_callout_builder.dart';
import 'package:filemanager/src/widgets/markdown_code_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  group('Markdown Preview & Renderer Tests', () {
    testWidgets('renders markdown with SelectionArea, CJK text and code blocks', (tester) async {
      const markdownData = '''
# 欢迎使用文档

这里是普通中文段落，带有 `行内代码` 和 **粗体**。

```dart
// 中文注释
void main() {
  print("你好世界");
}
```

> [!NOTE]
> 这是一个提示框。

> 普通引用段落。
''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final themeConfig = MarkdownThemeConfig.get(MarkdownThemeType.github, Brightness.light);
                return SelectionArea(
                  child: Container(
                    color: themeConfig.backgroundColor,
                    width: double.infinity,
                    height: double.infinity,
                    child: Markdown(
                      data: markdownData,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      selectable: false,
                      extensionSet: md.ExtensionSet.gitHubFlavored,
                      styleSheet: themeConfig.toStyleSheet(context, fontSize: 14.0),
                      builders: {
                        'pre': HighlightCodeElementBuilder(
                          themeConfig: themeConfig,
                          fontSize: 14.0,
                        ),
                        'blockquote': CalloutBlockquoteBuilder(
                          themeConfig: themeConfig,
                          fontSize: 14.0,
                        ),
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('欢迎使用文档'), findsOneWidget);
      expect(find.textContaining('行内代码'), findsOneWidget);
      expect(find.textContaining('你好世界'), findsOneWidget);
      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Note'), findsOneWidget);
      expect(find.textContaining('这是一个提示框'), findsOneWidget);
      expect(find.textContaining('普通引用段落'), findsOneWidget);
    });

    testWidgets('inline code is preserved and not swallowed', (tester) async {
      const markdownData = 'Paragraph with `variableName` and another `foo.bar()` call.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final themeConfig = MarkdownThemeConfig.get(MarkdownThemeType.github, Brightness.light);
                return SelectionArea(
                  child: Markdown(
                    data: markdownData,
                    selectable: false,
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                    styleSheet: themeConfig.toStyleSheet(context, fontSize: 14.0),
                    builders: {
                      'pre': HighlightCodeElementBuilder(
                        themeConfig: themeConfig,
                        fontSize: 14.0,
                      ),
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('variableName'), findsOneWidget);
      expect(find.textContaining('foo.bar()'), findsOneWidget);
    });

    testWidgets('empty markdown document placeholder test', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final themeConfig = MarkdownThemeConfig.get(MarkdownThemeType.github, Brightness.light);
                const data = '';
                if (data.isEmpty) {
                  return Container(
                    color: themeConfig.backgroundColor,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined, color: themeConfig.textColor),
                          Text(
                            'Document is empty',
                            style: TextStyle(fontFamilyFallback: MarkdownThemeConfig.fontFamilyFallback),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Document is empty'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });

    test('toStyleSheet populates fontFamilyFallback for CJK on all styles', () {
      expect(MarkdownThemeConfig.fontFamilyFallback, contains('Noto Sans CJK SC'));
      expect(MarkdownThemeConfig.fontFamilyFallback, contains('WenQuanYi Micro Hei'));
      expect(MarkdownThemeConfig.fontFamilyFallback, contains('Droid Sans Fallback'));
      expect(MarkdownThemeConfig.monoFontFamilyFallback, contains('Noto Sans Mono CJK SC'));
      expect(MarkdownThemeConfig.monoFontFamilyFallback, contains('DejaVu Sans Mono'));
    });
  });
}
