import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filemanager/src/theme/app_ui_tokens.dart';

void main() {
  testWidgets('AppCircleBadge renders with correct size and icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCircleBadge(
            icon: Icons.bookmark,
            color: Colors.amber,
            size: 30,
            iconSize: 16,
          ),
        ),
      ),
    );

    expect(find.byType(AppCircleBadge), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    final iconWidget = tester.widget<Icon>(find.byIcon(Icons.bookmark));
    expect(iconWidget.size, 16);
    expect(iconWidget.color, Colors.amber);
  });

  testWidgets('AppIconButton triggers callback on tap', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppIconButton(
            icon: Icons.copy,
            tooltip: 'Copy',
            onPressed: () => pressed = true,
          ),
        ),
      ),
    );

    expect(find.byType(AppIconButton), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);

    await tester.tap(find.byType(AppIconButton));
    expect(pressed, isTrue);
  });

  testWidgets('AppSwipeBack triggers onBack when swiping right from left edge', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSwipeBack(
            onBack: () => popped = true,
            child: Container(color: Colors.blue, width: 400, height: 600),
          ),
        ),
      ),
    );

    // Swipe right starting from x=30 (within left edge threshold 140px)
    final gesture = await tester.startGesture(const Offset(30, 200));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  testWidgets('AppSwipeBack does not trigger when dragging from middle of screen', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSwipeBack(
            onBack: () => popped = true,
            child: Container(color: Colors.blue, width: 400, height: 600),
          ),
        ),
      ),
    );

    // Swipe right starting from x=250 (beyond edge threshold 140px)
    final gesture = await tester.startGesture(const Offset(250, 200));
    await gesture.moveBy(const Offset(60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(popped, isFalse);
  });

  testWidgets('AppSwipeBack does not trigger when dragging leftwards', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSwipeBack(
            onBack: () => popped = true,
            child: Container(color: Colors.blue, width: 400, height: 600),
          ),
        ),
      ),
    );

    // Swipe left starting from x=100
    final gesture = await tester.startGesture(const Offset(100, 200));
    await gesture.moveBy(const Offset(-60, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(popped, isFalse);
  });
}
