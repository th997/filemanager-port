import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:filemanager/src/controllers/browser_pane_controller.dart';
import 'package:filemanager/src/controllers/image_prefetch_controller.dart';
import 'package:filemanager/src/dialogs/browser_info_dialog.dart';
import 'package:filemanager/src/models/entry_item.dart';
import 'package:filemanager/src/pages/diff_viewer_page.dart';
import 'package:filemanager/src/pages/pdf_viewer_page.dart';
import 'package:filemanager/src/pages/structured_viewer_page.dart';
import 'package:filemanager/src/rust/api/file_manager.dart';
import 'package:filemanager/src/services/browser_clipboard_service.dart';
import 'package:filemanager/src/services/subtitle_service.dart';
import 'package:filemanager/src/widgets/qr_code_widget.dart';
import 'package:flutter_test/flutter_test.dart';

EntryItem _entry(String name, {bool isDir = false, int size = 100}) {
  return EntryItem(
    EntryDto(
      name: name,
      path: name,
      isDir: isDir,
      size: isDir ? null : BigInt.from(size),
      modifiedMillis: null,
      hidden: name.startsWith('.'),
      isSymlink: false,
    ),
  );
}

void main() {
  group('BrowserPaneController', () {
    test('manages navigation stack, sort, and desktop Shift/Ctrl multi-selection', () async {
      final ctrl = BrowserPaneController(
        root: '/home/user',
        title: 'Home',
        loader: ({
          required root,
          required path,
          required page,
          required pageSize,
          required sortBy,
          required ascending,
          required showHidden,
          required filter,
        }) async {
          final items = [
            _entry('a.txt'),
            _entry('b.txt'),
            _entry('c.txt'),
            _entry('d.txt'),
          ];
          return (items: items, hasMore: false, total: items.length);
        },
      );

      await ctrl.reload();
      expect(ctrl.entries.length, 4);

      // Click index 1 -> selects b.txt
      ctrl.handleItemSelectionClick(1, isShiftPressed: false, isCtrlOrMetaPressed: false);
      expect(ctrl.selectedPaths, {'b.txt'});

      // Shift+Click index 3 -> selects b.txt, c.txt, d.txt
      ctrl.handleItemSelectionClick(3, isShiftPressed: true, isCtrlOrMetaPressed: false);
      expect(ctrl.selectedPaths, {'b.txt', 'c.txt', 'd.txt'});

      // Ctrl+Click index 0 -> adds a.txt discretely
      ctrl.handleItemSelectionClick(0, isShiftPressed: false, isCtrlOrMetaPressed: true);
      expect(ctrl.selectedPaths, {'a.txt', 'b.txt', 'c.txt', 'd.txt'});

      // Invert selection -> empty
      ctrl.invertSelection();
      expect(ctrl.selectedPaths, isEmpty);

      // Navigation stack back / forward / up
      await ctrl.navigateTo(newRelPath: 'docs/2026');
      expect(ctrl.relPath, 'docs/2026');
      expect(ctrl.canGoBack, isTrue);

      expect(await ctrl.goBack(), isTrue);
      expect(ctrl.relPath, '');
      expect(ctrl.canGoForward, isTrue);

      expect(await ctrl.goForward(), isTrue);
      expect(ctrl.relPath, 'docs/2026');

      expect(await ctrl.goUp(), isTrue);
      expect(ctrl.relPath, 'docs');
    });

    test('drops stale async load results on rapid navigation/search race', () async {
      final firstCompleter = Completer<({List<EntryItem> items, bool hasMore, int total})>();
      int call = 0;
      final ctrl = BrowserPaneController(
        root: '/root',
        title: 'Root',
        loader: ({
          required root,
          required path,
          required page,
          required pageSize,
          required sortBy,
          required ascending,
          required showHidden,
          required filter,
        }) {
          call++;
          if (call == 1) return firstCompleter.future;
          return Future.value((
            items: [_entry('latest.txt')],
            hasMore: false,
            total: 1,
          ));
        },
      );

      final staleFuture = ctrl.reload();
      await ctrl.setFilter('latest');
      // Complete stale first request after the second request finished
      firstCompleter.complete((items: [_entry('stale.txt')], hasMore: false, total: 1));
      await staleFuture;

      expect(ctrl.entries.map((e) => e.name).toList(), ['latest.txt']);
    });
  });

  group('BrowserClipboardService', () {
    test('notifies listeners across copy, cut, and clear', () {
      final cb = BrowserClipboardService.instance;
      cb.clear();
      int notifications = 0;
      void listener() => notifications++;
      cb.addListener(listener);

      cb.setCopy('/local', ['a.txt', 'b.txt']);
      expect(cb.hasItems, isTrue);
      expect(cb.snapshot!.isCut, isFalse);
      expect(cb.snapshot!.count, 2);

      cb.setCut('remote://nas', ['video.mp4']);
      expect(cb.snapshot!.isCut, isTrue);
      expect(cb.snapshot!.sourceRoot, 'remote://nas');

      cb.clear();
      expect(cb.hasItems, isFalse);
      expect(notifications, 3);
      cb.removeListener(listener);
    });
  });

  group('CsvParser & XmlTreeNode', () {
    test('parses RFC 4180 quoted CSV with embedded commas and quotes', () {
      const csv = 'name,note,score\n"Alice, Jr.","Says ""Hi""",98\nBob,Plain,75\n';
      final rows = CsvParser.parse(csv);
      expect(rows.length, 3);
      expect(rows[0], ['name', 'note', 'score']);
      expect(rows[1], ['Alice, Jr.', 'Says "Hi"', '98']);
      expect(rows[2], ['Bob', 'Plain', '75']);
    });

    test('parses XML hierarchy and attributes', () {
      const xml = '<catalog><book id="1"><title>Rust</title></book><empty /></catalog>';
      final roots = XmlTreeNode.parse(xml);
      expect(roots.length, 1);
      expect(roots.first.tag, 'catalog');
      expect(roots.first.children.length, 2);
      expect(roots.first.children.first.attributes['id'], '1');
      expect(roots.first.children.first.children.first.text, 'Rust');
    });
  });

  group('DiffEngine', () {
    test('computes line-level additions, deletions, and unchanged lines', () {
      final diff = DiffEngine.diffLines('a\nb\nc\n', 'a\nb2\nc\nd\n');
      final ops = diff.map((l) => (l.op, l.text)).toList();
      expect(ops, contains((DiffOp.equal, 'a')));
      expect(ops, contains((DiffOp.delete, 'b')));
      expect(ops, contains((DiffOp.insert, 'b2')));
      expect(ops, contains((DiffOp.equal, 'c')));
      expect(ops, contains((DiffOp.insert, 'd')));
    });
  });

  group('SubtitleParser', () {
    test('parses SRT and resolves active cue by timestamp', () {
      const srt = '''1
00:00:01,000 --> 00:00:03,500
Hello <i>world</i>!

2
00:00:04,000 --> 00:00:06,000
Second line
''';
      final cues = SubtitleParser.parse(srt, ext: 'srt');
      expect(cues.length, 2);
      expect(cues[0].text, 'Hello world!');
      expect(SubtitleParser.activeTextAt(cues, const Duration(milliseconds: 500)), isNull);
      expect(SubtitleParser.activeTextAt(cues, const Duration(milliseconds: 2000)), 'Hello world!');
      expect(SubtitleParser.activeTextAt(cues, const Duration(milliseconds: 5000)), 'Second line');
    });

    test('parses ASS dialogue lines stripping override tags', () {
      const ass = '''[Events]
Dialogue: 0,0:00:02.50,0:00:05.00,Default,,0,0,0,,{\\an8}Line 1\\NLine 2
''';
      final cues = SubtitleParser.parse(ass, ext: 'ass');
      expect(cues.length, 1);
      expect(cues.first.text, 'Line 1\nLine 2');
      expect(
        SubtitleParser.activeTextAt(cues, const Duration(seconds: 3)),
        'Line 1\nLine 2',
      );
    });
  });

  group('Unix Permissions, QR Code, ImagePrefetchController, PdfInspector', () {
    test('formatUnixMode renders symbolic and octal permissions', () {
      expect(formatUnixMode(0x1ED), 'rwxr-xr-x (0755)');
      expect(formatUnixMode(0x1A4), 'rw-r--r-- (0644)');
    });

    test('QrCodeEncoder produces square boolean matrix for LAN share URLs', () {
      final matrix = QrCodeEncoder.encode('http://192.168.1.42:8080/?token=abcdef123456');
      expect(matrix, isNotNull);
      expect(matrix!.length, greaterThanOrEqualTo(21));
      expect(matrix.length, matrix.first.length);
    });

    test('ImagePrefetchController enforces LRU budget', () {
      final cache = ImagePrefetchController<String>(maxBudgetBytes: 10);
      cache.put('a', Uint8List(6));
      cache.put('b', Uint8List(6));
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNotNull);
      expect(cache.usedBytes, 6);
    });

    test('PdfDocumentInspector extracts page count and outline titles', () {
      final syntheticPdf = Uint8List.fromList(utf8.encode(
        '%PDF-1.4\n/Type /Page\n/Type /Page\n/Title (Chapter 1)\n/Title (Chapter 2)\n',
      ));
      expect(PdfDocumentInspector.estimatePageCount(syntheticPdf), 2);
      final outline = PdfDocumentInspector.extractOutline(syntheticPdf, 2);
      expect(outline.map((o) => o.title).toList(), ['Chapter 1', 'Chapter 2']);
    });
  });
}
