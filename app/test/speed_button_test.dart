import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showMenu speed selection applies rate even after ephemeral caller finishes', (tester) async {
    double selectedRate = 1.0;
    final rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 8.0];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('btn'),
                onPressed: () async {
                  final selected = await showMenu<double>(
                    context: context,
                    position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                    initialValue: selectedRate,
                    items: [
                      for (final r in rates)
                        PopupMenuItem(value: r, child: Text('$r×')),
                    ],
                  );
                  if (selected != null) {
                    selectedRate = selected;
                  }
                },
                child: Text('$selectedRate×'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('1.0×'), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn')));
    await tester.pumpAndSettle();

    expect(find.text('2.0×'), findsOneWidget);
    expect(find.text('4.0×'), findsOneWidget);

    await tester.tap(find.text('4.0×'));
    await tester.pumpAndSettle();

    expect(selectedRate, 4.0);
  });
}
