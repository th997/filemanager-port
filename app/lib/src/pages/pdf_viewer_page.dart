import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/vault_service.dart';

/// Outline entry parsed from a PDF `/Outlines` dictionary.
class PdfOutlineItem {
  final String title;
  final int pageIndex; // 0-based
  final int level;
  const PdfOutlineItem({
    required this.title,
    required this.pageIndex,
    this.level = 0,
  });
}

/// Pure-Dart in-memory PDF structure, outline, `/ToUnicode` CMap & content-stream
/// inspector so TOC navigation and full-text search work accurately (including
/// Chinese/UTF-16BE bookmarks and CIDFont CMaps) without writing to disk.
class PdfDocumentInspector {
  static final RegExp _objRe = RegExp(r'(\d+)\s+\d+\s+obj\b([\s\S]*?)endobj');
  static final RegExp _pageTypeRe = RegExp(r'/Type\s*/Page(?![a-zA-Z])');
  static final RegExp _refRe = RegExp(r'(\d+)\s+\d+\s+R');
  static final RegExp _titleParenRe = RegExp(
    r'/Title\s*(\((?:\\.|[^()\\]|\([^()]*\))*\))',
  );
  static final RegExp _titleHexRe = RegExp(r'/Title\s*(<[0-9a-fA-F\s]*>)');
  static final RegExp _tjParenRe = RegExp(r'(\((?:\\.|[^()\\])*\))\s*Tj');
  static final RegExp _tjHexRe = RegExp(r'(<[0-9a-fA-F\s]+>)\s*Tj');
  static final RegExp _tjArrRe = RegExp(r'\[([^\]]{1,4000})\]\s*TJ');
  static final RegExp _arrTokenRe = RegExp(
    r'(\((?:\\.|[^()\\])*\))|(<[0-9a-fA-F\s]+>)',
  );

  /// Decode either a PDF literal string `(...)` (with escapes / octal /
  /// UTF-16BE `0xFE 0xFF` BOM) or a hex string `<...>` (with UTF-16BE
  /// `FEFF` BOM or UTF-8/Latin-1 bytes).
  static String decodePdfString(String raw) {
    final s = raw.trim();
    if (s.startsWith('<') && s.endsWith('>') && s.length >= 2) {
      var hex = s.substring(1, s.length - 1).replaceAll(RegExp(r'\s+'), '');
      if (hex.isEmpty) return '';
      if (hex.length.isOdd) hex = '${hex}0';
      if (hex.toUpperCase().startsWith('FEFF') && hex.length >= 4) {
        return _decodeUtf16BeHex(hex.substring(4));
      }
      final bytes = _hexToBytes(hex);
      return _decodeBytesSmart(bytes);
    }
    if (s.startsWith('(') && s.endsWith(')') && s.length >= 2) {
      final inner = s.substring(1, s.length - 1);
      final bytes = <int>[];
      for (int i = 0; i < inner.length; i++) {
        final code = inner.codeUnitAt(i);
        if (code == 0x5C && i + 1 < inner.length) {
          i++;
          final esc = inner[i];
          switch (esc) {
            case 'n':
              bytes.add(0x0A);
            case 'r':
              bytes.add(0x0D);
            case 't':
              bytes.add(0x09);
            case 'b':
              bytes.add(0x08);
            case 'f':
              bytes.add(0x0C);
            case '(':
              bytes.add(0x28);
            case ')':
              bytes.add(0x29);
            case '\\':
              bytes.add(0x5C);
            case '\r':
              if (i + 1 < inner.length && inner[i + 1] == '\n') i++;
            case '\n':
              break;
            default:
              if (esc.codeUnitAt(0) >= 0x30 && esc.codeUnitAt(0) <= 0x37) {
                var oct = esc;
                for (int k = 0; k < 2 && i + 1 < inner.length; k++) {
                  final next = inner[i + 1];
                  if (next.codeUnitAt(0) >= 0x30 &&
                      next.codeUnitAt(0) <= 0x37) {
                    oct += next;
                    i++;
                  } else {
                    break;
                  }
                }
                bytes.add(int.parse(oct, radix: 8) & 0xFF);
              } else {
                bytes.add(esc.codeUnitAt(0) & 0xFF);
              }
          }
        } else {
          bytes.add(code & 0xFF);
        }
      }
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        final units = <int>[];
        for (int i = 2; i + 1 < bytes.length; i += 2) {
          units.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(units);
      }
      return _decodeBytesSmart(bytes);
    }
    return s;
  }

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (int i = 0; i + 1 < hex.length; i += 2) {
      final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (v != null) out.add(v);
    }
    return out;
  }

  static String _decodeUtf16BeHex(String hex) {
    final units = <int>[];
    for (int i = 0; i + 3 < hex.length; i += 4) {
      final u = int.tryParse(hex.substring(i, i + 4), radix: 16);
      if (u != null && u != 0) units.add(u);
    }
    if (units.isEmpty && hex.length == 2) {
      final b = int.tryParse(hex, radix: 16);
      if (b != null) return String.fromCharCode(b);
    }
    return String.fromCharCodes(units);
  }

  static String _decodeBytesSmart(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  static Map<int, String> _parseIndirectObjects(String latin) {
    final objects = <int, String>{};
    for (final m in _objRe.allMatches(latin)) {
      final id = int.tryParse(m.group(1) ?? '');
      final body = m.group(2);
      if (id != null && body != null) {
        objects[id] = body;
      }
    }
    return objects;
  }

  static List<int> _collectPageObjIds(Map<int, String> objects) {
    final pages = <int>[];
    final visited = <int>{};

    void walkPagesNode(int nodeId) {
      if (!visited.add(nodeId)) return;
      final body = objects[nodeId];
      if (body == null) return;
      final kidsMatch = RegExp(r'/Kids\s*\[([\s\S]*?)\]').firstMatch(body);
      if (kidsMatch != null) {
        for (final r in _refRe.allMatches(kidsMatch.group(1) ?? '')) {
          final kidId = int.tryParse(r.group(1) ?? '');
          if (kidId != null) walkPagesNode(kidId);
        }
      } else {
        pages.add(nodeId);
      }
    }

    int? rootPagesId;
    for (final body in objects.values) {
      if (RegExp(r'/Type\s*/Catalog\b').hasMatch(body)) {
        final pm = RegExp(r'/Pages\s+(\d+)\s+\d+\s+R').firstMatch(body);
        if (pm != null) {
          rootPagesId = int.tryParse(pm.group(1) ?? '');
          break;
        }
      }
    }
    if (rootPagesId != null) {
      walkPagesNode(rootPagesId);
    }
    if (pages.isEmpty) {
      for (final entry in objects.entries) {
        if (_pageTypeRe.hasMatch(entry.value)) {
          pages.add(entry.key);
        }
      }
    }
    return pages;
  }

  static List<int>? _extractStreamBytes(String body) {
    final streamIdx = body.indexOf('stream');
    if (streamIdx < 0) return null;
    int dataStart = streamIdx + 6;
    if (dataStart < body.length && body.codeUnitAt(dataStart) == 0x0D) {
      dataStart++;
    }
    if (dataStart < body.length && body.codeUnitAt(dataStart) == 0x0A) {
      dataStart++;
    }
    final endIdx = body.indexOf('endstream', dataStart);
    if (endIdx < 0 || endIdx < dataStart) return null;
    final header = body.substring(0, streamIdx);
    if (header.contains('/DCTDecode') ||
        header.contains('/JPXDecode') ||
        header.contains('/CCITTFaxDecode')) {
      return null;
    }
    final raw = body.substring(dataStart, endIdx).codeUnits;
    if (header.contains('/FlateDecode')) {
      try {
        return zlib.decode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  static Map<String, String> _parseToUnicodeCMaps(
    String latin,
    Map<int, String> objects,
  ) {
    final cmap = <String, String>{};

    void parseStreamText(String text) {
      if (!text.contains('beginbfchar') && !text.contains('beginbfrange')) {
        return;
      }
      for (final block in RegExp(
        r'beginbfchar([\s\S]*?)endbfchar',
      ).allMatches(text)) {
        final content = block.group(1) ?? '';
        for (final pair in RegExp(
          r'<([0-9a-fA-F\s]+)>\s*<([0-9a-fA-F\s]+)>',
        ).allMatches(content)) {
          final src =
              (pair.group(1) ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
          final dst =
              (pair.group(2) ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
          if (src.isEmpty || dst.isEmpty) continue;
          cmap[src] = _decodeCMapDestHex(dst);
        }
      }
      for (final block in RegExp(
        r'beginbfrange([\s\S]*?)endbfrange',
      ).allMatches(text)) {
        final content = block.group(1) ?? '';
        for (final arrMatch in RegExp(
          r'<([0-9a-fA-F\s]+)>\s*<([0-9a-fA-F\s]+)>\s*\[([^\]]+)\]',
        ).allMatches(content)) {
          final startHex = (arrMatch.group(1) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final endHex = (arrMatch.group(2) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final start = int.tryParse(startHex, radix: 16);
          final end = int.tryParse(endHex, radix: 16);
          if (start == null || end == null || end < start) continue;
          final items = RegExp(r'<([0-9a-fA-F\s]+)>')
              .allMatches(arrMatch.group(3) ?? '')
              .toList();
          final limit = items.length < 256 ? items.length : 256;
          for (int i = 0; i < limit && start + i <= end; i++) {
            final src =
                (start + i).toRadixString(16).padLeft(startHex.length, '0').toUpperCase();
            final dst = (items[i].group(1) ?? '')
                .replaceAll(RegExp(r'\s+'), '')
                .toUpperCase();
            if (dst.isNotEmpty) {
              cmap[src] = _decodeCMapDestHex(dst);
            }
          }
        }
        for (final rngMatch in RegExp(
          r'<([0-9a-fA-F\s]+)>\s*<([0-9a-fA-F\s]+)>\s*<([0-9a-fA-F\s]+)>',
        ).allMatches(content)) {
          final startHex = (rngMatch.group(1) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final endHex = (rngMatch.group(2) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final dstHex = (rngMatch.group(3) ?? '')
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
          final start = int.tryParse(startHex, radix: 16);
          final end = int.tryParse(endHex, radix: 16);
          final dstStart = int.tryParse(dstHex, radix: 16);
          if (start == null || end == null || dstStart == null || end < start) {
            continue;
          }
          final count = (end - start + 1).clamp(0, 256);
          for (int i = 0; i < count; i++) {
            final src =
                (start + i).toRadixString(16).padLeft(startHex.length, '0').toUpperCase();
            final dst =
                (dstStart + i).toRadixString(16).padLeft(dstHex.length, '0').toUpperCase();
            cmap[src] = _decodeCMapDestHex(dst);
          }
        }
      }
    }

    if (objects.isNotEmpty) {
      for (final body in objects.values) {
        if (!body.contains('stream')) continue;
        final raw = _extractStreamBytes(body);
        if (raw == null) continue;
        parseStreamText(String.fromCharCodes(raw));
      }
    }
    if (cmap.isEmpty) {
      for (final body in _scanRawStreams(latin)) {
        parseStreamText(body);
      }
    }
    return cmap;
  }

  static String _decodeCMapDestHex(String hex) {
    if (hex.length >= 4 && hex.length % 4 == 0) {
      return _decodeUtf16BeHex(hex);
    }
    return _decodeBytesSmart(_hexToBytes(hex));
  }

  static String _decodeHexTextToken(
    String rawHexToken,
    Map<String, String> cmap,
  ) {
    var hex = rawHexToken
        .substring(1, rawHexToken.length - 1)
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (hex.isEmpty) return '';
    if (cmap.containsKey(hex)) return cmap[hex]!;

    if (cmap.isNotEmpty && hex.length >= 4 && hex.length % 4 == 0) {
      final buf = StringBuffer();
      int hits = 0;
      for (int i = 0; i + 4 <= hex.length; i += 4) {
        final chunk = hex.substring(i, i + 4);
        final mapped = cmap[chunk];
        if (mapped != null) {
          buf.write(mapped);
          hits++;
        } else {
          final code = int.tryParse(chunk, radix: 16);
          if (code != null && code >= 0x20) {
            buf.writeCharCode(code);
          }
        }
      }
      if (hits > 0) return buf.toString();
    }

    if (cmap.isNotEmpty && hex.length.isEven) {
      final buf = StringBuffer();
      int hits = 0;
      for (int i = 0; i + 2 <= hex.length; i += 2) {
        final chunk = hex.substring(i, i + 2);
        final mapped = cmap[chunk];
        if (mapped != null) {
          buf.write(mapped);
          hits++;
        } else {
          final b = int.tryParse(chunk, radix: 16);
          if (b != null && b >= 0x20 && b < 0x7F) {
            buf.writeCharCode(b);
          }
        }
      }
      if (hits > 0) return buf.toString();
    }

    return decodePdfString('<$hex>');
  }

  static String _extractTextFromContentStream(
    String decoded,
    Map<String, String> cmap,
  ) {
    if (!decoded.contains('Tj') && !decoded.contains('TJ')) return '';
    final buf = StringBuffer();
    for (final m in _tjParenRe.allMatches(decoded)) {
      buf.write(decodePdfString(m.group(1) ?? ''));
      buf.write(' ');
    }
    for (final m in _tjHexRe.allMatches(decoded)) {
      buf.write(_decodeHexTextToken(m.group(1) ?? '', cmap));
      buf.write(' ');
    }
    for (final m in _tjArrRe.allMatches(decoded)) {
      final inner = m.group(1) ?? '';
      for (final tok in _arrTokenRe.allMatches(inner)) {
        final paren = tok.group(1);
        final hex = tok.group(2);
        if (paren != null) {
          buf.write(decodePdfString(paren));
        } else if (hex != null) {
          buf.write(_decodeHexTextToken(hex, cmap));
        }
      }
      buf.write(' ');
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _scanRawStreams(String latin) {
    final out = <String>[];
    int cursor = 0;
    while (cursor < latin.length) {
      final startMarker = latin.indexOf('stream', cursor);
      if (startMarker < 0) break;
      int dataStart = startMarker + 6;
      if (dataStart < latin.length && latin.codeUnitAt(dataStart) == 0x0D) {
        dataStart++;
      }
      if (dataStart < latin.length && latin.codeUnitAt(dataStart) == 0x0A) {
        dataStart++;
      }
      final endMarker = latin.indexOf('endstream', dataStart);
      if (endMarker < 0) break;
      final headerStart = (startMarker - 220).clamp(0, startMarker);
      final header = latin.substring(headerStart, startMarker);
      if (!header.contains('/DCTDecode') &&
          !header.contains('/JPXDecode') &&
          !header.contains('/CCITTFaxDecode')) {
        final slice = latin.substring(dataStart, endMarker);
        if (header.contains('/FlateDecode')) {
          try {
            out.add(String.fromCharCodes(zlib.decode(slice.codeUnits)));
          } catch (_) {}
        } else {
          out.add(slice);
        }
      }
      cursor = endMarker + 9;
    }
    return out;
  }

  /// Extract page text strings aligned 1:1 with the PDF `/Pages` tree when
  /// available, decoding both literal strings and `/ToUnicode` CMap hex tokens.
  static List<String> extractPageTexts(Uint8List bytes) {
    final latin = String.fromCharCodes(bytes);
    final objects = _parseIndirectObjects(latin);
    final cmap = _parseToUnicodeCMaps(latin, objects);
    final pageIds = _collectPageObjIds(objects);

    if (pageIds.isNotEmpty) {
      final perPage = <String>[];
      for (final pid in pageIds) {
        final pageBody = objects[pid] ?? '';
        final contentIds = <int>[];
        final arrMatch =
            RegExp(r'/Contents\s*\[([\s\S]*?)\]').firstMatch(pageBody);
        if (arrMatch != null) {
          for (final r in _refRe.allMatches(arrMatch.group(1) ?? '')) {
            final cid = int.tryParse(r.group(1) ?? '');
            if (cid != null) contentIds.add(cid);
          }
        } else {
          final singleMatch =
              RegExp(r'/Contents\s+(\d+)\s+\d+\s+R').firstMatch(pageBody);
          if (singleMatch != null) {
            final cid = int.tryParse(singleMatch.group(1) ?? '');
            if (cid != null) contentIds.add(cid);
          }
        }

        final pageBuf = StringBuffer();
        for (final cid in contentIds) {
          final objBody = objects[cid];
          if (objBody == null) continue;
          final raw = _extractStreamBytes(objBody);
          if (raw == null) continue;
          final txt =
              _extractTextFromContentStream(String.fromCharCodes(raw), cmap);
          if (txt.isNotEmpty) {
            if (pageBuf.isNotEmpty) pageBuf.write(' ');
            pageBuf.write(txt);
          }
        }
        perPage.add(pageBuf.toString());
      }
      if (perPage.any((t) => t.isNotEmpty)) {
        return perPage;
      }
    }

    final streams = <String>[];
    for (final decoded in _scanRawStreams(latin)) {
      final txt = _extractTextFromContentStream(decoded, cmap);
      if (txt.isNotEmpty) {
        streams.add(txt);
      }
    }
    return streams;
  }

  /// Extract PDF bookmarks from `/Outlines` with real `/Dest` / `/A` GoTo
  /// target page resolution and UTF-16BE / literal title decoding.
  static List<PdfOutlineItem> extractOutline(Uint8List bytes, int totalPages) {
    final latin = String.fromCharCodes(bytes);
    final objects = _parseIndirectObjects(latin);
    final pageIds = _collectPageObjIds(objects);
    final objIdToPageIndex = <int, int>{
      for (int i = 0; i < pageIds.length; i++) pageIds[i]: i,
    };
    final effectivePages = totalPages > 0
        ? totalPages
        : (pageIds.isNotEmpty ? pageIds.length : 1);

    int? resolveDestPageIndex(String body) {
      final destMatch = RegExp(r'/Dest\s*\[\s*(\d+)\s+\d+\s+R').firstMatch(body);
      if (destMatch != null) {
        final pid = int.tryParse(destMatch.group(1) ?? '');
        if (pid != null && objIdToPageIndex.containsKey(pid)) {
          return objIdToPageIndex[pid];
        }
      }
      final inlineAction = RegExp(
        r'/A\s*<<[\s\S]*?/D\s*\[\s*(\d+)\s+\d+\s+R',
      ).firstMatch(body);
      if (inlineAction != null) {
        final pid = int.tryParse(inlineAction.group(1) ?? '');
        if (pid != null && objIdToPageIndex.containsKey(pid)) {
          return objIdToPageIndex[pid];
        }
      }
      final actionRef = RegExp(r'/A\s+(\d+)\s+\d+\s+R').firstMatch(body);
      if (actionRef != null) {
        final aid = int.tryParse(actionRef.group(1) ?? '');
        final actionBody = aid != null ? objects[aid] : null;
        if (actionBody != null) {
          final targetMatch =
              RegExp(r'/D\s*\[\s*(\d+)\s+\d+\s+R').firstMatch(actionBody);
          if (targetMatch != null) {
            final pid = int.tryParse(targetMatch.group(1) ?? '');
            if (pid != null && objIdToPageIndex.containsKey(pid)) {
              return objIdToPageIndex[pid];
            }
          }
        }
      }
      return null;
    }

    int? outlinesRootId;
    for (final body in objects.values) {
      if (RegExp(r'/Type\s*/Catalog\b').hasMatch(body)) {
        final om = RegExp(r'/Outlines\s+(\d+)\s+\d+\s+R').firstMatch(body);
        if (om != null) {
          outlinesRootId = int.tryParse(om.group(1) ?? '');
          break;
        }
      }
    }
    outlinesRootId ??= objects.entries
        .where((e) => RegExp(r'/Type\s*/Outlines\b').hasMatch(e.value))
        .map((e) => e.key)
        .firstOrNull;

    final items = <PdfOutlineItem>[];
    if (outlinesRootId != null && objects.containsKey(outlinesRootId)) {
      final rootBody = objects[outlinesRootId]!;
      final firstId = int.tryParse(
        RegExp(r'/First\s+(\d+)\s+\d+\s+R').firstMatch(rootBody)?.group(1) ?? '',
      );
      final visited = <int>{outlinesRootId};

      void walkOutline(int? startId, int level) {
        if (startId == null || level > 6 || items.length >= 200) return;
        int? curr = startId;
        while (curr != null && items.length < 200) {
          if (!visited.add(curr)) break;
          final body = objects[curr];
          if (body == null) break;

          final rawTitle = _titleParenRe.firstMatch(body)?.group(1) ??
              _titleHexRe.firstMatch(body)?.group(1);
          final title = rawTitle != null ? decodePdfString(rawTitle).trim() : '';
          final pageIndex = (resolveDestPageIndex(body) ?? 0)
              .clamp(0, (effectivePages - 1).clamp(0, 1000000));
          if (title.isNotEmpty) {
            items.add(
              PdfOutlineItem(title: title, pageIndex: pageIndex, level: level),
            );
          }

          final childFirst = int.tryParse(
            RegExp(r'/First\s+(\d+)\s+\d+\s+R').firstMatch(body)?.group(1) ?? '',
          );
          if (childFirst != null) {
            walkOutline(childFirst, level + 1);
          }

          curr = int.tryParse(
            RegExp(r'/Next\s+(\d+)\s+\d+\s+R').firstMatch(body)?.group(1) ?? '',
          );
        }
      }

      walkOutline(firstId, 0);
      if (items.isNotEmpty) return items;
    }

    // Legacy heuristic fallback (e.g. compressed ObjStm where objects aren't
    // visible as plain top-level `obj ... endobj` blocks).
    final rawTitles = <String>[];
    final combinedTitleRe = RegExp(
      r'/Title\s*(\((?:\\.|[^()\\]|\([^()]*\))*\)|<[0-9a-fA-F\s]*>)',
    );
    final seen = <String>{};
    for (final m in combinedTitleRe.allMatches(latin)) {
      final title = decodePdfString(m.group(1) ?? '').trim();
      if (title.isEmpty || !seen.add(title)) continue;
      rawTitles.add(title);
      if (rawTitles.length >= 100) break;
    }
    for (int i = 0; i < rawTitles.length; i++) {
      final approxPage = effectivePages <= 1
          ? 0
          : ((i * (effectivePages - 1)) ~/ rawTitles.length.clamp(1, 100000));
      items.add(PdfOutlineItem(title: rawTitles[i], pageIndex: approxPage));
    }
    return items;
  }

  static int estimatePageCount(Uint8List bytes) {
    final latin = String.fromCharCodes(bytes);
    final count = _pageTypeRe.allMatches(latin).length;
    return count > 0 ? count : 1;
  }
}

/// Built-in cross-platform PDF viewer that renders directly from memory bytes
/// streamed from the Rust VFS — keeping remote, archive, and Privacy Vault PDFs
/// completely off the temporary filesystem.
class PdfViewerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;

  /// Optional pre-loaded bytes (useful in tests or already-buffered callers).
  final Uint8List? initialBytes;

  const PdfViewerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    this.initialBytes,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  static const int _maxPdfBytes = 128 * 1024 * 1024;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  int _totalPages = 0;
  int _currentPage = 0;
  double _zoomScale = 1.0;
  double _dpi = 144.0;

  final Map<int, ui.Image> _renderedPages = {};
  final Set<int> _renderingPages = {};
  final PageController _pageController = PageController();
  final TransformationController _transformController = TransformationController();

  List<PdfOutlineItem> _outline = const [];
  List<String> _pageTexts = const [];
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  List<int> _searchHitPages = const [];
  int _searchHitCursor = 0;

  bool get _isVault => vaultIdFromRoot(widget.root) != null;

  @override
  void initState() {
    super.initState();
    VaultService.instance.addListener(_onVaultChanged);
    _loadPdf();
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    _pageController.dispose();
    _transformController.dispose();
    _searchController.dispose();
    for (final img in _renderedPages.values) {
      img.dispose();
    }
    _renderedPages.clear();
    super.dispose();
  }

  void _onVaultChanged() {
    final vid = vaultIdFromRoot(widget.root);
    if (vid != null && !VaultService.instance.isUnlocked(vid) && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadPdf() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = widget.initialBytes ??
          await readFileBytes(
            root: widget.root,
            path: widget.path,
            maxBytes: BigInt.from(_maxPdfBytes),
          );
      if (!mounted) return;
      _pdfBytes = bytes;
      // Count pages & render the first page via native rasterizer.
      int pageCount = 0;
      try {
        await for (final page in Printing.raster(bytes, dpi: 72)) {
          if (pageCount == 0 && mounted) {
            final img = await page.toImage();
            _renderedPages[0] = img;
          }
          pageCount++;
        }
      } catch (_) {
        pageCount = PdfDocumentInspector.estimatePageCount(bytes);
      }
      if (!mounted) return;
      final total = pageCount > 0 ? pageCount : 1;
      _outline = PdfDocumentInspector.extractOutline(bytes, total);
      _pageTexts = PdfDocumentInspector.extractPageTexts(bytes);
      setState(() {
        _totalPages = total;
        _currentPage = 0;
        _loading = false;
      });
      // Re-render page 0 at crisp DPI and prefetch page 1.
      unawaited(_ensurePageRendered(0, force: true));
      if (total > 1) unawaited(_ensurePageRendered(1));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _ensurePageRendered(int pageIndex, {bool force = false}) async {
    final bytes = _pdfBytes;
    if (bytes == null || pageIndex < 0 || pageIndex >= _totalPages) return;
    if (!force && (_renderedPages.containsKey(pageIndex) || _renderingPages.contains(pageIndex))) {
      return;
    }
    _renderingPages.add(pageIndex);
    try {
      await for (final page in Printing.raster(bytes, pages: [pageIndex], dpi: _dpi)) {
        final img = await page.toImage();
        if (!mounted) {
          img.dispose();
          return;
        }
        final old = _renderedPages[pageIndex];
        _renderedPages[pageIndex] = img;
        old?.dispose();
        // Evict distant pages to keep memory bounded on large PDFs.
        if (_renderedPages.length > 8) {
          final distant = _renderedPages.keys
              .where((k) => (k - _currentPage).abs() > 3)
              .toList();
          for (final k in distant) {
            _renderedPages.remove(k)?.dispose();
          }
        }
        if (mounted) setState(() {});
      }
    } catch (_) {
      // Ignore single-page raster errors; fallback icon stays visible.
    } finally {
      _renderingPages.remove(pageIndex);
    }
  }

  void _goToPage(int index) {
    if (_totalPages <= 0) return;
    final clamped = index.clamp(0, _totalPages - 1);
    setState(() => _currentPage = clamped);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(clamped);
    }
    unawaited(_ensurePageRendered(clamped));
    if (clamped + 1 < _totalPages) unawaited(_ensurePageRendered(clamped + 1));
    if (clamped - 1 >= 0) unawaited(_ensurePageRendered(clamped - 1));
  }

  void _setZoom(double scale) {
    final next = scale.clamp(0.5, 4.0);
    setState(() {
      _zoomScale = next;
      _transformController.value = Matrix4.diagonal3Values(next, next, 1.0);
    });
    final targetDpi = next > 1.8 ? 216.0 : 144.0;
    if ((targetDpi - _dpi).abs() > 10) {
      _dpi = targetDpi;
      unawaited(_ensurePageRendered(_currentPage, force: true));
    }
  }

  void _runSearch(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty || _pageTexts.isEmpty) {
      setState(() {
        _searchHitPages = const [];
        _searchHitCursor = 0;
      });
      return;
    }
    final hits = <int>[];
    for (int i = 0; i < _pageTexts.length; i++) {
      if (_pageTexts[i].toLowerCase().contains(needle)) {
        final mappedPage = _totalPages <= 1
            ? 0
            : (i * _totalPages ~/ _pageTexts.length).clamp(0, _totalPages - 1);
        if (hits.isEmpty || hits.last != mappedPage) {
          hits.add(mappedPage);
        }
      }
    }
    setState(() {
      _searchHitPages = hits;
      _searchHitCursor = 0;
    });
    if (hits.isNotEmpty) {
      _goToPage(hits.first);
    }
  }

  void _stepSearch(int delta) {
    if (_searchHitPages.isEmpty) return;
    final next = (_searchHitCursor + delta) % _searchHitPages.length;
    setState(() => _searchHitCursor = next < 0 ? next + _searchHitPages.length : next);
    _goToPage(_searchHitPages[_searchHitCursor]);
  }

  Future<void> _showJumpToPageDialog() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: '${_currentPage + 1}');
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pdfJumpToPage),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '1 - $_totalPages',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null) Navigator.of(ctx).pop(n - 1);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              Navigator.of(ctx).pop(n != null ? n - 1 : null);
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked != null && mounted) {
      _goToPage(picked);
    }
  }

  void _showOutlineSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.toc),
              title: Text(
                l10n.pdfOutline,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            if (_outline.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.pdfNoOutline),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _outline.length,
                  itemBuilder: (_, i) {
                    final item = _outline[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.only(
                        left: 16.0 + item.level * 16.0,
                        right: 16.0,
                      ),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Text('${item.pageIndex + 1}'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _goToPage(item.pageIndex);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _goToPage(_currentPage + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _goToPage(_currentPage - 1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _goToPage(_currentPage + 1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _goToPage(_currentPage - 1),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _showSearch = !_showSearch),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            setState(() => _showSearch = !_showSearch),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            _setZoom(_zoomScale + 0.25),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            _setZoom(_zoomScale - 0.25),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.fileName, overflow: TextOverflow.ellipsis),
                if (_isVault)
                  Text(
                    l10n.pdfZeroDiskBadge,
                    style: TextStyle(fontSize: 10, color: scheme.primary),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: l10n.pdfSearchHint,
                onPressed: () => setState(() => _showSearch = !_showSearch),
              ),
              IconButton(
                icon: const Icon(Icons.toc),
                tooltip: l10n.pdfOutline,
                onPressed: _showOutlineSheet,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                onPressed: () => _setZoom(_zoomScale - 0.25),
              ),
              TextButton(
                onPressed: () => _setZoom(1.0),
                child: Text('${(_zoomScale * 100).round()}%'),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                onPressed: () => _setZoom(_zoomScale + 0.25),
              ),
            ],
          ),
          body: Column(
            children: [
              if (_showSearch)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: scheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.pdfSearchHint,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: _runSearch,
                          onChanged: _runSearch,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_searchHitPages.isNotEmpty)
                        Text('${_searchHitCursor + 1}/${_searchHitPages.length}'),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up),
                        onPressed: () => _stepSearch(-1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        onPressed: () => _stepSearch(1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _showSearch = false),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!, style: TextStyle(color: scheme.error)),
                            ),
                          )
                        : PageView.builder(
                            controller: _pageController,
                            itemCount: _totalPages,
                            onPageChanged: (idx) {
                              setState(() => _currentPage = idx);
                              unawaited(_ensurePageRendered(idx));
                              if (idx + 1 < _totalPages) {
                                unawaited(_ensurePageRendered(idx + 1));
                              }
                            },
                            itemBuilder: (_, index) {
                              final img = _renderedPages[index];
                              if (img == null) {
                                unawaited(_ensurePageRendered(index));
                                return const Center(child: CircularProgressIndicator());
                              }
                              return InteractiveViewer(
                                transformationController: _transformController,
                                minScale: 0.5,
                                maxScale: 4.0,
                                child: Center(
                                  child: Container(
                                    margin: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: RawImage(
                                      image: img,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              if (!_loading && _error == null && _totalPages > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.first_page),
                        onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
                      ),
                      TextButton(
                        onPressed: _showJumpToPageDialog,
                        child: Text(l10n.pdfPageOf(_currentPage + 1, _totalPages)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _currentPage + 1 < _totalPages
                            ? () => _goToPage(_currentPage + 1)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page),
                        onPressed: _currentPage + 1 < _totalPages
                            ? () => _goToPage(_totalPages - 1)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
