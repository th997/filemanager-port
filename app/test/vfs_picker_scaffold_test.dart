import 'package:filemanager/src/dialogs/vfs_picker_scaffold.dart';
import 'package:filemanager/src/services/platform_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VfsPickerScaffold', () {
    testWidgets('renders title, recent dirs, path and body', (tester) async {
      String? navigatedDir;
      QuickTarget? selectedTarget;
      bool upTapped = false;
      bool toggleHiddenTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VfsPickerScaffold(
              title: 'Pick a file',
              recentDirs: const ['/home/user/downloads', '/home/user/documents'],
              onNavigateTo: (dir) => navigatedDir = dir,
              quickTargets: const [
                QuickTarget(name: 'Downloads', kind: 'downloads', path: '/home/user/downloads', root: '/home/user/downloads', relPath: ''),
              ],
              onSelectTarget: (t) => selectedTarget = t,
              currentPath: '/home/user',
              canGoUp: true,
              onUp: () => upTapped = true,
              showHidden: false,
              onToggleHidden: () => toggleHiddenTapped = true,
              loading: false,
              body: const Text('Picker Content Body'),
              actions: [
                TextButton(
                  onPressed: () {},
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Pick a file'), findsOneWidget);
      expect(find.text('user/downloads'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('/home/user'), findsOneWidget);
      expect(find.text('Picker Content Body'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('user/downloads'));
      await tester.pump();
      expect(navigatedDir, '/home/user/downloads');

      await tester.tap(find.text('Downloads'));
      await tester.pump();
      expect(selectedTarget?.name, 'Downloads');

      await tester.tap(find.byTooltip('Parent folder'));
      await tester.pump();
      expect(upTapped, isTrue);

      await tester.tap(find.byTooltip('Show hidden files'));
      await tester.pump();
      expect(toggleHiddenTapped, isTrue);
    });

    testWidgets('renders filter field when showFilter is true', (tester) async {
      final controller = TextEditingController();
      String query = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return VfsPickerScaffold(
                  title: 'Filter test',
                  currentPath: '/home/user',
                  canGoUp: false,
                  showHidden: false,
                  onToggleHidden: () {},
                  loading: false,
                  showFilter: true,
                  filterController: controller,
                  filterQuery: query,
                  filterHintText: 'Search here...',
                  onFilterChanged: (v) => setState(() => query = v),
                  onFilterClear: () => setState(() {
                    query = '';
                    controller.clear();
                  }),
                  body: const Text('Body'),
                  actions: const [],
                );
              },
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'photo');
      await tester.pump();
      expect(query, 'photo');

      expect(find.byIcon(Icons.clear), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(query, '');
      expect(controller.text, '');
    });

    testWidgets('renders loading and error states', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VfsPickerScaffold(
              title: 'Loading test',
              currentPath: '/test',
              canGoUp: false,
              showHidden: false,
              onToggleHidden: _noop,
              loading: true,
              body: Text('Hidden Body'),
              actions: [],
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Hidden Body'), findsNothing);

      bool retryTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VfsPickerScaffold(
              title: 'Error test',
              currentPath: '/test',
              canGoUp: false,
              showHidden: false,
              onToggleHidden: _noop,
              loading: false,
              error: 'Permission denied',
              errorPrefix: 'Read failed: ',
              onRetry: () => retryTapped = true,
              body: const Text('Hidden Body'),
              actions: const [],
            ),
          ),
        ),
      );

      expect(find.text('Read failed: Permission denied'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retryTapped, isTrue);
    });
  });
}

void _noop() {}
