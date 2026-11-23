import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/pages/browser_workspace_page.dart';
import 'package:filemanager/src/widgets/browser/browser_list_header.dart';
import 'package:filemanager/src/widgets/browser/browser_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapZh(Widget child, {double width = 900}) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 700)),
        child: Scaffold(body: child),
      ),
    );
  }

  group('BrowserListColumnHeader', () {
    testWidgets('renders sortable columns and triggers callback on tap',
        (tester) async {
      SortField? tapped;
      await tester.pumpWidget(
        wrapZh(
          BrowserListColumnHeader(
            sortField: SortField.name,
            sortAsc: true,
            showTypeColumn: true,
            hasLeadingCheckbox: false,
            onSortTap: (f) => tapped = f,
            nameLabel: '名称',
            modifiedLabel: '修改时间',
            typeLabel: '类型',
            sizeLabel: '大小',
          ),
        ),
      );

      expect(find.text('名称'), findsOneWidget);
      expect(find.text('类型'), findsOneWidget);
      expect(find.text('修改时间'), findsOneWidget);
      expect(find.text('大小'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await tester.tap(find.text('大小'));
      expect(tapped, SortField.size);

      await tester.tap(find.text('修改时间'));
      expect(tapped, SortField.modified);
    });

    testWidgets('hides Type column when showTypeColumn is false',
        (tester) async {
      await tester.pumpWidget(
        wrapZh(
          BrowserListColumnHeader(
            sortField: SortField.modified,
            sortAsc: false,
            showTypeColumn: false,
            hasLeadingCheckbox: true,
            onSortTap: (_) {},
            nameLabel: '名称',
            modifiedLabel: '修改时间',
            typeLabel: '类型',
            sizeLabel: '大小',
          ),
          width: 640,
        ),
      );

      expect(find.text('类型'), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });
  });

  group('BrowserStatusBar', () {
    String fmt(BigInt b) => '${b.toInt()} B';

    testWidgets('shows item counts, read-only lock badge, and toggles hidden files',
        (tester) async {
      bool toggled = false;
      bool tappedCount = false;

      await tester.pumpWidget(
        wrapZh(
          BrowserStatusBar(
            visibleCount: 12,
            totalNonHiddenCount: 12,
            isFiltered: false,
            totalListedBytes: BigInt.from(512),
            selectedCount: 0,
            selectedBytes: BigInt.zero,
            hasHiddenEntries: true,
            showHidden: false,
            isReadOnly: true,
            hasMore: false,
            formatBytes: fmt,
            onTapCount: () => tappedCount = true,
            onToggleHidden: () => toggled = true,
          ),
        ),
      );

      expect(find.textContaining('12'), findsOneWidget);
      expect(find.textContaining('512 B'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      expect(toggled, isTrue);

      await tester.tap(find.textContaining('512 B'));
      expect(tappedCount, isTrue);
    });

    testWidgets('shows selection count and bytes when items are selected',
        (tester) async {
      await tester.pumpWidget(
        wrapZh(
          BrowserStatusBar(
            visibleCount: 20,
            totalNonHiddenCount: 20,
            isFiltered: false,
            totalListedBytes: BigInt.from(2048),
            selectedCount: 3,
            selectedBytes: BigInt.from(768),
            hasHiddenEntries: false,
            showHidden: false,
            isReadOnly: false,
            hasMore: false,
            formatBytes: fmt,
            onTapCount: () {},
            onToggleHidden: () {},
          ),
        ),
      );

      expect(find.textContaining('3'), findsOneWidget);
      expect(find.textContaining('768 B'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  });

  group('BrowserUnifiedAddressBar', () {
    testWidgets('clicking blank area of breadcrumb bar triggers onStartEdit',
        (tester) async {
      bool startedEdit = false;
      final controller = TextEditingController();

      await tester.pumpWidget(
        wrapZh(
          BrowserUnifiedAddressBar(
            isEditingAddress: false,
            addressController: controller,
            onJumpToAddress: (_) {},
            onCancelEdit: () {},
            onStartEdit: () => startedEdit = true,
            root: '/home/user',
            relPath: 'docs',
            rootLabel: 'user',
            segments: const ['docs'],
            canGoBack: false,
            canGoForward: false,
            canNavigateUp: true,
            onRefresh: () {},
          ),
          width: 720,
        ),
      );

      final barBox = tester.getRect(find.byType(BrowserUnifiedAddressBar));
      // Tap empty right half of the breadcrumb bar (avoiding trailing edit icon).
      await tester.tapAt(Offset(barBox.left + 200, barBox.center.dy));
      await tester.pump();
      expect(startedEdit, isTrue);

      controller.dispose();
    });
  });

  group('BrowserWorkspacePage.deriveTabTitle', () {
    test('extracts subfolder basename, root basename, and preserves remote/vault labels', () {
      expect(
        BrowserWorkspacePage.deriveTabTitle('/home/th', 'Projects/filemanager', 'th'),
        'filemanager',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('/home/th', '', '本地存储'),
        'th',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('/', '', 'Root'),
        '/',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('remote://nas1', '', 'NAS'),
        'NAS',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('vault://v1', '', 'Secret'),
        'Secret',
      );
      expect(
        BrowserWorkspacePage.deriveTabTitle('remote://nas1', 'Movies/2026', 'NAS'),
        '2026',
      );
    });
  });

  group('BrowserSelectionRules', () {
    test('desktop keeps multi-select checkbox bar hidden on normal/modifier selection', () {
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: true,
          alreadyInMultiSelectBar: false,
          hasSelection: true,
        ),
        isFalse,
      );
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: true,
          alreadyInMultiSelectBar: false,
          hasSelection: false,
        ),
        isFalse,
      );
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: true,
          alreadyInMultiSelectBar: false,
          hasSelection: true,
          explicitMultiSelectAction: true,
        ),
        isTrue,
      );
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: true,
          alreadyInMultiSelectBar: true,
          hasSelection: true,
        ),
        isTrue,
      );
    });

    test('mobile activates multi-select bar when items are selected and exits when empty', () {
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: false,
          alreadyInMultiSelectBar: false,
          hasSelection: true,
        ),
        isTrue,
      );
      expect(
        BrowserSelectionRules.nextMultiSelectUiMode(
          isDesktop: false,
          alreadyInMultiSelectBar: true,
          hasSelection: false,
        ),
        isFalse,
      );
    });
  });
}
