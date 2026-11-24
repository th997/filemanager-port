import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/widgets/editor/editor_preview_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RebuildCounter extends StatelessWidget {
  final VoidCallback onBuild;
  final Widget child;

  const _RebuildCounter({
    required this.onBuild,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    onBuild();
    return child;
  }
}

class _TestRectPainter extends CustomPainter {
  final Rect rect;
  _TestRectPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = Colors.blue.withValues(alpha: 0.2));
  }

  @override
  bool shouldRepaint(covariant _TestRectPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

void main() {
  group('Scoped rebuild performance patterns', () {
    testWidgets('scroll-to-top FAB ValueNotifier toggles without rebuilding list body',
        (tester) async {
      final showFab = ValueNotifier<bool>(false);
      addTearDown(showFab.dispose);
      var bodyBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _RebuildCounter(
              onBuild: () => bodyBuilds++,
              child: const Center(child: Text('Large File List')),
            ),
            floatingActionButton: ValueListenableBuilder<bool>(
              valueListenable: showFab,
              builder: (_, show, _) => show
                  ? FloatingActionButton.small(
                      onPressed: () {},
                      child: const Icon(Icons.arrow_upward),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      expect(bodyBuilds, 1);
      expect(find.byType(FloatingActionButton), findsNothing);

      showFab.value = true;
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(bodyBuilds, 1);

      showFab.value = false;
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(bodyBuilds, 1);
    });

    testWidgets('lasso rect ValueNotifier inside Positioned.fill repaints without ParentData errors or body rebuilds',
        (tester) async {
      final lasso = ValueNotifier<Rect?>(null);
      addTearDown(lasso.dispose);
      var gridBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                _RebuildCounter(
                  onBuild: () => gridBuilds++,
                  child: const SizedBox.expand(),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<Rect?>(
                      valueListenable: lasso,
                      builder: (_, rect, _) {
                        if (rect == null) return const SizedBox.shrink();
                        return RepaintBoundary(
                          child: CustomPaint(painter: _TestRectPainter(rect)),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final lassoFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is _TestRectPainter,
      );
      expect(gridBuilds, 1);
      expect(lassoFinder, findsNothing);

      for (var i = 1; i <= 10; i++) {
        lasso.value = Rect.fromLTWH(0, 0, i * 12.0, i * 10.0);
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(lassoFinder, findsOneWidget);
      expect(gridBuilds, 1);

      lasso.value = null;
      await tester.pump();
      expect(lassoFinder, findsNothing);
      expect(gridBuilds, 1);
    });

    testWidgets('EditorStatusBar updates cursor and char counts via ListenableBuilder without parent rebuilds',
        (tester) async {
      final cursorPos = ValueNotifier<({int line, int col})>((line: 1, col: 1));
      final controller = TextEditingController(text: 'hi');
      addTearDown(() {
        cursorPos.dispose();
        controller.dispose();
      });
      var editorBodyBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: _RebuildCounter(
                    onBuild: () => editorBodyBuilds++,
                    child: const SizedBox.expand(),
                  ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([cursorPos, controller]),
                  builder: (_, _) => EditorStatusBar(
                    modeLabel: 'Editing',
                    isDirty: false,
                    cursorLine: cursorPos.value.line,
                    cursorCol: cursorPos.value.col,
                    lines: controller.text.split('\n').length,
                    words: 1,
                    chars: controller.text.length,
                    largeFileMode: false,
                    chunkEncoding: 'utf-8',
                    fontSize: 13,
                    wordWrap: true,
                    onTapStats: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(editorBodyBuilds, 1);
      expect(find.textContaining('Ln 1, Col 1'), findsOneWidget);

      controller.text = 'hello\nworld';
      cursorPos.value = (line: 2, col: 6);
      await tester.pump();

      expect(find.textContaining('Ln 2, Col 6'), findsOneWidget);
      expect(find.textContaining('Chars: 11'), findsOneWidget);
      expect(editorBodyBuilds, 1);
    });
  });
}
