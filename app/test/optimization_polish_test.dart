import 'dart:typed_data';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:filemanager/src/controllers/image_prefetch_controller.dart';
import 'package:filemanager/src/services/exif_service.dart';
import 'package:filemanager/src/services/native_pip_service.dart';
import 'package:filemanager/src/widgets/browser/browser_pane.dart';
import 'package:filemanager/src/widgets/browser/browser_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'BrowserUnifiedAddressBar uses HoverExpandDragTarget and expands ancestor after dwell',
      (tester) async {
    String? hoveredSegment;
    ({String root, List<String> paths})? acceptedPayload;
    String? acceptedDest;
    final addrController = TextEditingController();
    addTearDown(addrController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              Draggable<({String root, List<String> paths})>(
                data: (root: '/home/user', paths: ['Downloads/a.txt']),
                feedback: const Material(child: Text('DragItem')),
                child: const Text('DragSource'),
              ),
              BrowserUnifiedAddressBar(
                isEditingAddress: false,
                addressController: addrController,
                onJumpToAddress: (_) {},
                onCancelEdit: () {},
                onStartEdit: () {},
                root: '/home/user',
                relPath: 'Documents/Work',
                rootLabel: 'Home',
                segments: const ['Documents', 'Work'],
                canGoBack: false,
                canGoForward: false,
                canNavigateUp: true,
                onRefresh: () {},
                onSegmentTap: (seg) => hoveredSegment = seg,
                onAcceptDrop: (data, dest) {
                  acceptedPayload = data;
                  acceptedDest = dest;
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byType(HoverExpandDragTarget<({String root, List<String> paths})>),
      findsNWidgets(3),
    );

    // Drag over ancestor segment "Documents" and dwell past 750ms expandDelay.
    final sourceCenter = tester.getCenter(find.text('DragSource'));
    final docCenter = tester.getCenter(find.text('Documents'));
    final gesture = await tester.startGesture(sourceCenter);
    await tester.pump();
    await gesture.moveTo(docCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(hoveredSegment, 'Documents');

    // Dropping on "Documents" triggers onAcceptDrop for that segment.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(acceptedDest, 'Documents');
    expect(acceptedPayload?.paths, ['Downloads/a.txt']);
  });

  test('EmbeddedSubtitleTrack.fromMap and non-iOS NativePipService fallbacks behave safely',
      () async {
    final track = EmbeddedSubtitleTrack.fromMap({
      'index': 2,
      'title': 'Chinese (Simplified)',
      'language': 'zh_Hans',
      'selected': true,
    });
    expect(track.index, 2);
    expect(track.title, 'Chinese (Simplified)');
    expect(track.language, 'zh_Hans');
    expect(track.selected, isTrue);

    final fallbackTitle = EmbeddedSubtitleTrack.fromMap({
      'index': 0,
      'title': '',
      'language': 'en',
      'selected': false,
    });
    expect(fallbackTitle.title, 'en');

    expect(await NativePipService.listEmbeddedSubtitles(), isEmpty);
    expect(await NativePipService.selectEmbeddedSubtitle(0), isFalse);
  });

  test('ImagePrefetchController deduplicates in-flight loads and evicts LRU over budget',
      () async {
    final cache = ImagePrefetchController<String>(maxBudgetBytes: 10);
    int loadCount = 0;

    final futures = [
      cache.getOrLoad('a', () async {
        loadCount++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return Uint8List.fromList([1, 2, 3, 4, 5, 6]);
      }),
      cache.getOrLoad('a', () async {
        loadCount++;
        return Uint8List.fromList([9]);
      }),
    ];
    final loaded = await Future.wait(futures);
    expect(loadCount, 1);
    expect(loaded[0].length, 6);
    expect(cache.usedBytes, 6);

    // Adding 'b' (6 bytes) exceeds budget 10, so 'a' should be evicted.
    await cache.getOrLoad('b', () async => Uint8List.fromList([1, 2, 3, 4, 5, 6]));
    expect(cache.get('a'), isNull);
    expect(cache.get('b')?.length, 6);
    expect(cache.usedBytes, 6);

    expect(await ExifService.parseFromBytes(Uint8List.fromList([0, 1, 2, 3])), isNull);
  });
}
