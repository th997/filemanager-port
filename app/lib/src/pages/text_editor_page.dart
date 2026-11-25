import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../rust/api/file_manager.dart';
import '../services/file_open_service.dart';
import '../services/global_playback_service.dart';
import '../services/highlight_service.dart';
import '../services/markdown_pdf_service.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import '../theme/markdown_themes.dart';
import '../widgets/editor/editor_find_replace_bar.dart';
import '../widgets/editor/editor_preview_pane.dart';
import '../widgets/json_formatted_preview.dart' show JsonFormatter;

enum TextFileMode { preview, code, edit }

/// Text file viewer and editor.
///
/// Markdown and HTML open in a rendered preview; source is one tap away in the
/// highlighted code view. Every other text file starts in the code view.
class TextEditorPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;

  /// True when the containing location cannot be written (archive
  /// contents, read-only servers): the editor opens view-only instead of
  /// letting the user type and only failing at save time.
  final bool readOnly;
  final int? fileSizeBytes;

  /// Optional 1-based line number to jump to once loaded (e.g. from Grep search).
  final int? initialLine;

  const TextEditorPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    this.readOnly = false,
    this.fileSizeBytes,
    this.initialLine,
  });

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final SyntaxHighlightingEditingController _controller;
  late String _root;
  late String _path;
  late String _fileName;
  late bool _readOnly;
  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;
  late TextFileMode _mode;
  static const int _largeTextThresholdBytes = 20 * 1024 * 1024;
  static const int _chunkPageBytes = 256 * 1024;
  bool _largeFileMode = false;
  int _chunkStart = 0;
  int _chunkEnd = 0;
  int _chunkTotal = 0;
  bool _chunkHasPrev = false;
  bool _chunkHasNext = false;
  String _chunkEncoding = 'utf-8';
  bool _loadingChunk = false;
  final List<int> _prevChunkOffsets = [];

  static const _prefFontSize = 'editor.font_size';
  static const _prefWordWrap = 'editor.word_wrap';
  static const _prefMarkdownTheme = 'markdown.theme';
  static const _prefPdfMargin = 'markdown.pdf_margin';
  double _fontSize = 13.0;
  bool _wordWrap = false;
  MarkdownThemeType _markdownTheme = MarkdownThemeType.github;
  PdfMarginMode _pdfMargin = PdfMarginMode.standard;
  bool _showFind = false;
  bool _showReplace = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  final FocusNode _replaceFocusNode = FocusNode();
  final UndoHistoryController _undoController = UndoHistoryController();
  final ScrollController _codeScrollController = ScrollController();
  final ScrollController _codeHorizontalScrollController = ScrollController();
  final ScrollController _editScrollController = ScrollController();
  final List<int> _matchIndices = [];
  int _currentMatchIndex = 0;
  Timer? _findDebounce;
  String _lastFindQuery = '';
  String? _cachedDocForLower;
  String? _cachedDocLower;

  String? _cachedLinesText;
  List<String>? _cachedLinesList;
  List<int>? _cachedLineStarts;
  int _maxLineChars = 0;
  double? _cachedCharWidth;
  double? _cachedCharWidthFontSize;

  void _clearLineCache() {
    _cachedDocForLower = null;
    _cachedDocLower = null;
    _cachedLinesText = null;
    _cachedLinesList = null;
    _cachedLineStarts = null;
    _maxLineChars = 0;
  }

  void _ensureLineCache(String text) {
    if (identical(text, _cachedLinesText) || text == _cachedLinesText) {
      if (_cachedLinesList != null && _cachedLineStarts != null) return;
    }
    _cachedLinesText = text;
    final lines = <String>[];
    final starts = <int>[0];
    int start = 0;
    int maxChars = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        final line = text.substring(start, i);
        lines.add(line);
        if (line.length > maxChars) maxChars = line.length;
        start = i + 1;
        starts.add(start);
      }
    }
    final lastLine = text.substring(start);
    lines.add(lastLine);
    if (lastLine.length > maxChars) maxChars = lastLine.length;
    _cachedLinesList = lines;
    _cachedLineStarts = starts;
    _maxLineChars = maxChars;
  }

  int _getLineIndexForOffset(int charOffset) {
    if (_cachedLineStarts == null || _cachedLineStarts!.isEmpty) return 0;
    final starts = _cachedLineStarts!;
    int low = 0;
    int high = starts.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (starts[mid] <= charOffset) {
        if (mid == starts.length - 1 || starts[mid + 1] > charOffset) {
          return mid;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return 0;
  }

  bool _isLargeDocument(String text) {
    _ensureLineCache(text);
    return (_cachedLinesList != null && _cachedLinesList!.length > 500) ||
        text.length > 32 * 1024;
  }

  double _getCharWidth(TextStyle style) {
    if (_cachedCharWidth != null && _cachedCharWidthFontSize == _fontSize) {
      return _cachedCharWidth!;
    }
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _cachedCharWidth = painter.width;
    _cachedCharWidthFontSize = _fontSize;
    return _cachedCharWidth!;
  }

  String _getDocLower(String doc) {
    if (identical(doc, _cachedDocForLower) || doc == _cachedDocForLower) {
      if (_cachedDocLower != null) return _cachedDocLower!;
    }
    _cachedDocForLower = doc;
    _cachedDocLower = doc.toLowerCase();
    return _cachedDocLower!;
  }

  void _onFindChanged(String query) {
    _findDebounce?.cancel();
    if (query.isEmpty) {
      _updateMatches(jumpToMatch: false);
      return;
    }
    _findDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _updateMatches(jumpToMatch: true, forceScroll: false);
    });
  }

  final ValueNotifier<({int line, int col})> _cursorPosNotifier =
      ValueNotifier<({int line, int col})>((line: 1, col: 1));
  int get _cursorLine => _cursorPosNotifier.value.line;
  int get _cursorCol => _cursorPosNotifier.value.col;
  WebViewController? _webViewController;
  String? _cachedStatsText;
  int _cachedLines = 1;
  int? _cachedWords = 0;

  bool get _isTemporaryInbox =>
      !PlatformPaths.isInsidePrivateInbox(_root) &&
      (_root.contains('/cache/inbox') ||
          _root.contains('\\cache\\inbox') ||
          _root.endsWith('/inbox') ||
          _root.endsWith('\\inbox'));

  String get _lowerName => _fileName.toLowerCase();
  bool get _isMarkdown => _lowerName.endsWith('.md') || _lowerName.endsWith('.markdown');
  bool get _isHtml => _lowerName.endsWith('.html') || _lowerName.endsWith('.htm') || _lowerName.endsWith('.xhtml');
  bool get _isJson =>
      _lowerName.endsWith('.json') ||
      _lowerName.endsWith('.geojson') ||
      _lowerName.endsWith('.topojson');

  bool _vaultAutoClosing = false;

  void _onVaultChanged() {
    final vid = vaultIdFromRoot(_root);
    if (vid != null && !VaultService.instance.isUnlocked(vid)) {
      _controller.clear();
      _clearLineCache();
      if (!_vaultAutoClosing && mounted) {
        _vaultAutoClosing = true;
        final route = ModalRoute.of(context);
        if (route != null && route.isActive && !route.isFirst) {
          Navigator.of(context).removeRoute(route);
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    VaultService.instance.addListener(_onVaultChanged);
    _root = widget.root;
    _path = widget.path;
    _fileName = widget.fileName;
    _largeFileMode = (widget.fileSizeBytes ?? 0) > _largeTextThresholdBytes;
    _readOnly = widget.readOnly || _largeFileMode;
    _controller = SyntaxHighlightingEditingController(
      fileName: _fileName,
      brightnessProvider: () => Theme.of(context).brightness,
      fontSizeProvider: () => _fontSize,
    );
    _controller.addListener(_updateCursorPosition);
    final prefs = PreferencesService.instance;
    _fontSize = double.tryParse(prefs.getString(_prefFontSize) ?? '') ?? _fontSize;
    _wordWrap = prefs.getBool(_prefWordWrap) ?? _wordWrap;
    _markdownTheme = MarkdownThemeType.fromId(prefs.getString(_prefMarkdownTheme));
    _pdfMargin = PdfMarginMode.fromId(prefs.getString(_prefPdfMargin));
    _mode = (!_largeFileMode && (_isMarkdown || _isHtml))
        ? TextFileMode.preview
        : TextFileMode.code;
    _loadFile();
  }

  @override
  void dispose() {
    GlobalPlaybackService.instance.setNamedBottomInset('text_editor', 0.0);
    VaultService.instance.removeListener(_onVaultChanged);
    _findDebounce?.cancel();
    _controller.removeListener(_updateCursorPosition);
    _controller.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    _replaceFocusNode.dispose();
    _undoController.dispose();
    _codeScrollController.dispose();
    _codeHorizontalScrollController.dispose();
    _editScrollController.dispose();
    _cursorPosNotifier.dispose();
    super.dispose();
  }

  void _updateCursorPosition() {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid || sel.baseOffset < 0 || sel.baseOffset > text.length) {
      if (_cursorLine != 1 || _cursorCol != 1) {
        _cursorPosNotifier.value = (line: 1, col: 1);
      }
      return;
    }
    final offset = sel.baseOffset;
    int newLine = 1;
    int lastNewline = -1;
    for (int i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 10) {
        newLine++;
        lastNewline = i;
      }
    }
    final newCol = offset - lastNewline;
    if (_cursorLine != newLine || _cursorCol != newCol) {
      _cursorPosNotifier.value = (line: newLine, col: newCol);
    }
  }

  Future<void> _showGoToLineDialog() async {
    final text = _controller.text;
    int totalLines = text.isEmpty ? 1 : 1;
    if (text.isNotEmpty) {
      for (int i = 0; i < text.length; i++) {
        if (text.codeUnitAt(i) == 10) totalLines++;
      }
    }
    final ctrl = TextEditingController();
    final String? input;
    try {
      input = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).goToLine),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context).lineNumberRange(totalLines),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(AppLocalizations.of(context).cancel)),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: Text(AppLocalizations.of(context).go)),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (input == null || input.isEmpty) return;
    final targetLine = int.tryParse(input);
    if (targetLine == null || targetLine < 1 || targetLine > totalLines) {
      // The dialog used to close and quietly do nothing.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).enterLineNumberBetween(totalLines)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final switchedFromPreview = _mode == TextFileMode.preview;
    if (switchedFromPreview) {
      setState(() => _mode = TextFileMode.code);
    }

    _ensureLineCache(text);
    final targetLineIdx = (targetLine - 1).clamp(0, (_cachedLinesList?.length ?? 1) - 1);
    final offset = (_cachedLineStarts != null && targetLineIdx < _cachedLineStarts!.length)
        ? _cachedLineStarts![targetLineIdx]
        : 0;
    int lineEnd = text.indexOf('\n', offset);
    if (lineEnd == -1) lineEnd = text.length;
    _controller.selection = TextSelection(baseOffset: offset, extentOffset: lineEnd);
    if (switchedFromPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToMatch(offset, force: true);
      });
    } else {
      _scrollToMatch(offset, force: true);
    }
  }

  void _openFind({bool replace = false}) {
    if (_mode == TextFileMode.preview) {
      _setMode(TextFileMode.code);
    }
    setState(() {
      _showFind = true;
      if (replace && !_readOnly) _showReplace = true;
    });
    _findFocusNode.requestFocus();
    _updateMatches(jumpToMatch: false);
  }

  void _updateMatches({bool jumpToMatch = true, bool forceScroll = false}) {
    final query = _findController.text;
    _lastFindQuery = query;
    _matchIndices.clear();
    if (query.isNotEmpty) {
      final text = _controller.text;
      final lowerText = _getDocLower(text);
      final lowerQuery = query.toLowerCase();
      int start = 0;
      const int maxMatches = 10000;
      while (_matchIndices.length < maxMatches) {
        final index = lowerText.indexOf(lowerQuery, start);
        if (index == -1) break;
        _matchIndices.add(index);
        start = index + lowerQuery.length;
      }
    }
    if (_matchIndices.isEmpty) {
      _currentMatchIndex = 0;
    } else {
      int activeOffset = -1;
      if (_mode == TextFileMode.code && _codeScrollController.hasClients) {
        final textStyle = TextStyle(
          fontFamily: 'monospace',
          fontSize: _fontSize,
          height: 1.35,
        );
        final metricPainter = TextPainter(
          text: TextSpan(text: 'M', style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final lineHeight = metricPainter.preferredLineHeight;

        _ensureLineCache(_controller.text);
        final scrollY = _codeScrollController.offset;
        final approxLine = (scrollY / lineHeight).floor().clamp(0, (_cachedLinesList?.length ?? 1) - 1);
        activeOffset = (_cachedLineStarts != null && approxLine < _cachedLineStarts!.length)
            ? _cachedLineStarts![approxLine]
            : 0;
      } else if (_mode == TextFileMode.edit) {
        activeOffset = _controller.selection.baseOffset;
      }

      if (activeOffset > 0) {
        final nearest = _matchIndices.indexWhere((idx) => idx >= activeOffset);
        _currentMatchIndex = nearest != -1 ? nearest : 0;
      } else {
        _currentMatchIndex = 0;
      }
    }
    if (jumpToMatch && _matchIndices.isNotEmpty) {
      _selectCurrentMatch(forceScroll: forceScroll);
    }
    if (_showFind && query.isNotEmpty) {
      _controller.updateSearch(
        query: query,
        matches: _matchIndices,
        currentMatch: _currentMatchIndex,
      );
    } else {
      _controller.updateSearch(query: null, matches: null, currentMatch: null);
    }
    setState(() {});
  }

  void _closeFind() {
    _findDebounce?.cancel();
    setState(() {
      _showFind = false;
      _showReplace = false;
      _matchIndices.clear();
      _currentMatchIndex = 0;
    });
    _controller.updateSearch(query: null, matches: null, currentMatch: null);
  }

  void _nextMatch() {
    _findDebounce?.cancel();
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchIndices.length;
    });
    _selectCurrentMatch(forceScroll: true);
    _controller.updateSearch(
      query: _findController.text,
      matches: _matchIndices,
      currentMatch: _currentMatchIndex,
    );
  }

  void _prevMatch() {
    _findDebounce?.cancel();
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchIndices.length) % _matchIndices.length;
    });
    _selectCurrentMatch(forceScroll: true);
    _controller.updateSearch(
      query: _findController.text,
      matches: _matchIndices,
      currentMatch: _currentMatchIndex,
    );
  }

  void _ensureEditing() {
    if (_mode != TextFileMode.edit) _setMode(TextFileMode.edit);
  }

  /// Replaces the currently selected match. Matching is case-insensitive,
  /// mirroring find; the replacement text is inserted verbatim.
  void _replaceCurrent() {
    if (_readOnly) return;
    _ensureEditing();
    if (_matchIndices.isEmpty) return;
    final query = _findController.text;
    final replacement = _replaceController.text;
    final idx = _matchIndices[_currentMatchIndex];
    final text = _controller.text;
    if (idx < 0 ||
        idx + query.length > text.length ||
        text.substring(idx, idx + query.length).toLowerCase() !=
            query.toLowerCase()) {
      _updateMatches(jumpToMatch: true, forceScroll: true); // stale indices — rescan instead of corrupting text
      return;
    }
    _clearLineCache();
    _controller.value = _controller.value.copyWith(
      text: text.replaceRange(idx, idx + query.length, replacement),
      selection:
          TextSelection.collapsed(offset: idx + replacement.length),
    );
    setState(() => _isDirty = true);
    _updateMatches(jumpToMatch: true, forceScroll: true);
  }

  void _replaceAll() {
    if (_readOnly) return;
    _ensureEditing();
    final query = _findController.text;
    if (query.isEmpty) return;
    final replacement = _replaceController.text;
    final text = _controller.text;
    final lowerText = _getDocLower(text);
    final lowerQuery = query.toLowerCase();
    final buf = StringBuffer();
    var start = 0;
    var count = 0;
    while (true) {
      final i = lowerText.indexOf(lowerQuery, start);
      if (i == -1) break;
      buf.write(text.substring(start, i));
      buf.write(replacement);
      start = i + lowerQuery.length;
      count++;
    }
    if (count == 0) return;
    buf.write(text.substring(start));
    _clearLineCache();
    _controller.value = _controller.value.copyWith(
      text: buf.toString(),
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() => _isDirty = true);
    _updateMatches(jumpToMatch: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).replacedOccurrences(count),
        ),
      ),
    );
  }

  void _selectCurrentMatch({bool forceScroll = false}) {
    if (_matchIndices.isEmpty) return;
    final idx = _matchIndices[_currentMatchIndex];
    final len = _findController.text.length;
    // The match list can lag the buffer by the 300ms debounce after an
    // edit; selecting a stale offset would throw or land past the text.
    if (idx < 0 || idx + len > _controller.text.length) {
      _updateMatches(jumpToMatch: true, forceScroll: forceScroll);
      return;
    }
    _controller.selection = TextSelection(baseOffset: idx, extentOffset: idx + len);
    _scrollToMatch(idx, force: forceScroll);
  }

  void _scrollToMatch(int charIndex, {bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _controller.text;
      if (charIndex < 0 || charIndex > text.length) return;

      final ScrollController activeVerticalController;
      final ScrollController? activeHorizontalController;
      switch (_mode) {
        case TextFileMode.code:
          activeVerticalController = _codeScrollController;
          activeHorizontalController = _codeHorizontalScrollController;
          break;
        case TextFileMode.edit:
          activeVerticalController = _editScrollController;
          activeHorizontalController = null;
          break;
        case TextFileMode.preview:
          return;
      }

      if (!activeVerticalController.hasClients) return;

      final textStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: _fontSize,
        height: 1.35,
      );

      final metricPainter = TextPainter(
        text: TextSpan(text: 'M', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final lineHeight = metricPainter.preferredLineHeight;

      _ensureLineCache(text);
      final targetLine = _getLineIndexForOffset(charIndex);
      final lineStart = _cachedLineStarts != null && targetLine < _cachedLineStarts!.length
          ? _cachedLineStarts![targetLine]
          : 0;

      const contentPadding = 16.0;
      final isWrapping = (_mode == TextFileMode.edit) || _wordWrap;
      double caretDy = 0.0;
      double caretDx = 0.0;

      if (!isWrapping) {
        caretDy = targetLine * lineHeight;
        final linePrefixLen = charIndex.clamp(lineStart, text.length) - lineStart;
        caretDx = linePrefixLen * _getCharWidth(textStyle);
      } else {
        if (!_isLargeDocument(text)) {
          final renderBox = context.findRenderObject() as RenderBox?;
          final availableWidth = (renderBox != null && renderBox.hasSize)
              ? renderBox.size.width
              : MediaQuery.of(context).size.width;
          final viewWidth = (availableWidth - 32.0).clamp(100.0, double.infinity);

          final queryLen = _findController.text.length;
          final nextNewline = text.indexOf('\n', (charIndex + queryLen).clamp(0, text.length));
          final lineEnd = nextNewline == -1 ? text.length : (nextNewline + 1).clamp(0, text.length);
          final subtext = text.substring(0, lineEnd);
          final painter = TextPainter(
            text: TextSpan(text: subtext, style: textStyle),
            textDirection: TextDirection.ltr,
          );
          painter.layout(maxWidth: viewWidth);

          final caretOffset = painter.getOffsetForCaret(
            TextPosition(offset: charIndex),
            Rect.zero,
          );
          caretDy = caretOffset.dy;
          caretDx = caretOffset.dx;
        } else {
          final renderBox = context.findRenderObject() as RenderBox?;
          final availableWidth = (renderBox != null && renderBox.hasSize)
              ? renderBox.size.width
              : MediaQuery.of(context).size.width;
          final viewWidth = (availableWidth - 32.0).clamp(100.0, double.infinity);
          final charWidth = _getCharWidth(textStyle);
          final charsPerLine = (viewWidth / charWidth).floor().clamp(1, 10000);

          int visualLines = 0;
          if (_cachedLinesList != null) {
            final maxLine = targetLine.clamp(0, _cachedLinesList!.length);
            for (var i = 0; i < maxLine; i++) {
              final len = _cachedLinesList![i].length;
              visualLines += (len == 0) ? 1 : ((len + charsPerLine - 1) ~/ charsPerLine).clamp(1, 1000);
            }
          } else {
            visualLines = targetLine;
          }
          final offsetInLine = (charIndex - lineStart).clamp(0, 100000);
          visualLines += (offsetInLine ~/ charsPerLine);
          caretDy = visualLines * lineHeight;
          caretDx = (offsetInLine % charsPerLine) * charWidth;
        }
      }

      final viewport = activeVerticalController.position.viewportDimension;
      final currentY = activeVerticalController.position.pixels;
      final targetMatchY = contentPadding + caretDy;
      final isComfortablyVisible = targetMatchY >= (currentY + 40) &&
          (targetMatchY + lineHeight) <= (currentY + viewport - 40);

      if (force || !isComfortablyVisible) {
        final targetY = ((targetMatchY) - (viewport - lineHeight) / 2).clamp(
          0.0,
          activeVerticalController.position.maxScrollExtent,
        );

        activeVerticalController.animateTo(
          targetY,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }

      if (!isWrapping && activeHorizontalController != null && activeHorizontalController.hasClients) {
        final hViewport = activeHorizontalController.position.viewportDimension;
        final currentX = activeHorizontalController.position.pixels;
        final targetMatchX = contentPadding + caretDx;
        final isHorizontallyVisible = targetMatchX >= (currentX + 32) &&
            targetMatchX <= (currentX + hViewport - 32);

        if (force || !isHorizontallyVisible) {
          final targetX = ((targetMatchX) - (hViewport / 2)).clamp(
            0.0,
            activeHorizontalController.position.maxScrollExtent,
          );
          activeHorizontalController.animateTo(
            targetX,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  String _formatByteOffset(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _loadChunkAt(
    int offset, {
    bool resetHistory = false,
    bool pushCurrentToHistory = false,
  }) async {
    final vid = vaultIdFromRoot(_root);
    if (vid != null && !VaultService.instance.isUnlocked(vid)) return;

    final clampedOffset = offset < 0
        ? 0
        : (_chunkTotal > 0 ? offset.clamp(0, _chunkTotal) : offset);
    final initialLoad = _controller.text.isEmpty && _chunkTotal == 0;
    final prevStart = _chunkStart;
    setState(() {
      _loadingChunk = true;
      if (initialLoad) _loading = true;
      _error = null;
    });

    try {
      final chunk = await readTextChunk(
        root: _root,
        path: _path,
        offset: BigInt.from(clampedOffset),
        maxBytes: BigInt.from(_chunkPageBytes),
      );
      if (!mounted) return;
      if (resetHistory) {
        _prevChunkOffsets.clear();
      } else if (pushCurrentToHistory && prevStart != chunk.startOffset.toInt()) {
        _prevChunkOffsets.add(prevStart);
      }
      _clearLineCache();
      setState(() {
        _chunkStart = chunk.startOffset.toInt();
        _chunkEnd = chunk.endOffset.toInt();
        _chunkTotal = chunk.totalSize.toInt();
        _chunkHasPrev = chunk.hasPrev;
        _chunkHasNext = chunk.hasNext;
        _chunkEncoding = chunk.encoding;
        _controller.text = chunk.text;
        _loading = false;
        _loadingChunk = false;
        _isDirty = false;
      });
      if (_codeScrollController.hasClients) {
        _codeScrollController.jumpTo(0);
      }
      if (_showFind && _findController.text.isNotEmpty) {
        _updateMatches(jumpToMatch: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingChunk = false;
        if (initialLoad || _controller.text.isEmpty) {
          _error = e.toString();
        }
      });
      if (!initialLoad && _controller.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _nextTextPage() async {
    if (_loadingChunk || !_chunkHasNext) return;
    await _loadChunkAt(_chunkEnd, pushCurrentToHistory: true);
  }

  Future<void> _prevTextPage() async {
    if (_loadingChunk || !_chunkHasPrev) return;
    if (_prevChunkOffsets.isNotEmpty) {
      final target = _prevChunkOffsets.removeLast();
      await _loadChunkAt(target);
      return;
    }
    final fallback = (_chunkStart - _chunkPageBytes).clamp(0, _chunkStart);
    await _loadChunkAt(fallback);
  }

  Future<void> _showJumpPositionDialog() async {
    if (_chunkTotal <= 0) return;
    final l10n = AppLocalizations.of(context);
    final maxStart =
        _chunkTotal > _chunkPageBytes ? _chunkTotal - _chunkPageBytes : 0;
    double fraction =
        maxStart > 0 ? (_chunkStart / maxStart).clamp(0.0, 1.0) : 0.0;
    final ctrl = TextEditingController(
      text: (fraction * 100).toStringAsFixed(1),
    );
    double? pickedFraction;
    try {
      pickedFraction = await showDialog<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(l10n.jumpToPosition),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatByteOffset((fraction * maxStart).round())} / ${_formatByteOffset(_chunkTotal)}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                Slider(
                  value: fraction,
                  onChanged: (v) {
                    setDialogState(() {
                      fraction = v;
                      ctrl.text = (v * 100).toStringAsFixed(1);
                    });
                  },
                ),
                TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '% (0 - 100)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (s) {
                    final parsed = double.tryParse(s.trim());
                    if (parsed != null) {
                      setDialogState(() {
                        fraction = (parsed / 100.0).clamp(0.0, 1.0);
                      });
                    }
                  },
                  onSubmitted: (_) => Navigator.of(ctx).pop(fraction),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(fraction),
                child: Text(l10n.go),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (pickedFraction == null || !mounted) return;
    final targetOffset = (pickedFraction.clamp(0.0, 1.0) * maxStart).round();
    await _loadChunkAt(targetOffset, resetHistory: true);
  }

  Future<void> _loadFile() async {
    if (_largeFileMode) {
      await _loadChunkAt(0, resetHistory: true);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final content = await readTextFile(root: _root, path: _path);
      if (mounted) {
        _clearLineCache();
        // Large preview files (> 128KB for Markdown/HTML, > 2MB for JSON)
        // automatically switch to code mode to keep the UI responsive.
        final previewLimit = _isJson ? 2 * 1024 * 1024 : 128 * 1024;
        if (content.length > previewLimit && _mode == TextFileMode.preview) {
          _mode = TextFileMode.code;
        }
        if (widget.initialLine != null && _mode == TextFileMode.preview) {
          _mode = TextFileMode.code;
        }
        setState(() {
          _controller.text = content;
          _loading = false;
          _isDirty = false;
        });
        if (widget.initialLine != null && widget.initialLine! > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final targetLine = widget.initialLine!;
            final lineHeight = _fontSize * 1.45;
            final offset = ((targetLine - 1) * lineHeight).clamp(0.0, double.infinity);
            if (_codeScrollController.hasClients) {
              _codeScrollController.jumpTo(
                offset.clamp(0.0, _codeScrollController.position.maxScrollExtent),
              );
            }
            // Also move text selection to start of that line for Edit mode.
            final lines = content.split('\n');
            int charOffset = 0;
            for (int i = 0; i < (targetLine - 1).clamp(0, lines.length); i++) {
              charOffset += lines[i].length + 1;
            }
            charOffset = charOffset.clamp(0, content.length);
            _controller.selection = TextSelection.collapsed(offset: charOffset);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('too large')) {
        setState(() {
          _largeFileMode = true;
          _readOnly = true;
          _mode = TextFileMode.code;
        });
        await _loadChunkAt(0, resetHistory: true);
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Re-reads the file, confirming first if there are edits to lose.
  Future<void> _reload() async {
    if (_largeFileMode) {
      await _loadChunkAt(_chunkStart);
      return;
    }
    if (_isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).reloadFile),
          content: Text(
            AppLocalizations.of(context).reloadFileConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(context).reload),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    await _loadFile();
    _webViewController?.reload();
  }

  Future<void> _save() async {
    final vid = vaultIdFromRoot(_root);
    if (vid != null && !VaultService.instance.isUnlocked(vid)) return;
    if (_loading || _error != null || _saving) return;
    setState(() => _saving = true);
    final savedText = _controller.text;
    try {
      await writeTextFile(
        root: _root,
        path: _path,
        content: savedText,
      );
      // Edits made while the write was in flight keep the file dirty.
      if (mounted) {
        setState(() {
          _saving = false;
          _isDirty = _controller.text != savedText;
        });
        _webViewController?.reload();
        if (_isTemporaryInbox) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).savedToCachePrompt),
              action: SnackBarAction(
                label: AppLocalizations.of(context).saveAs,
                onPressed: _saveAs,
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).fileSavedSuccess)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).saveFailed('$e')), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    }
  }

  Future<void> _saveAs() async {
    if (_loading || _error != null || _saving) return;

    final initialRoot = _isTemporaryInbox ? PlatformPaths.defaultRoot() : _root;
    final initialPath = _isTemporaryInbox
        ? ''
        : (_path.contains('/') ? _path.substring(0, _path.lastIndexOf('/')) : '');

    final dest = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).saveAs,
      initialRoot: initialRoot,
      initialPath: initialPath,
      confirmLabel: AppLocalizations.of(context).saveToThisFolder,
    );
    if (dest == null || !mounted) return;

    final nameController = TextEditingController(text: _fileName);
    final confirmedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).saveAs),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).fileNameLabel,
            hintText: AppLocalizations.of(context).fileNameHint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            final t = val.trim();
            if (t.isNotEmpty) Navigator.of(ctx).pop(t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final val = nameController.text.trim();
              if (val.isNotEmpty) Navigator.of(ctx).pop(val);
            },
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    ).whenComplete(nameController.dispose);

    if (confirmedName == null || confirmedName.isEmpty || !mounted) return;

    setState(() => _saving = true);
    final savedText = _controller.text;
    final destRel = dest.relPath.isEmpty ? confirmedName : '${dest.relPath}/$confirmedName';

    try {
      await writeTextFile(
        root: dest.root,
        path: destRel,
        content: savedText,
      );

      if (mounted) {
        setState(() {
          _root = dest.root;
          _path = destRel;
          _fileName = confirmedName;
          _readOnly = false;
          _saving = false;
          _isDirty = _controller.text != savedText;
        });
        _controller.updateFileName(confirmedName);
        _webViewController?.reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).fileSavedSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).saveFailed('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  bool _exportingPdf = false;

  Future<void> _exportPdf({required bool share}) async {
    final text = _controller.text;
    if (text.isEmpty) return;

    setState(() => _exportingPdf = true);
    try {
      final brightness = Theme.of(context).brightness;
      final themeConfig = MarkdownThemeConfig.get(_markdownTheme, brightness);
      if (share) {
        await MarkdownPdfService.instance.sharePdf(
          markdown: text,
          title: _fileName,
          themeConfig: themeConfig,
          marginMode: _pdfMargin,
        );
      } else {
        await MarkdownPdfService.instance.printOrPreview(
          markdown: text,
          title: _fileName,
          themeConfig: themeConfig,
          marginMode: _pdfMargin,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).pdfExportFailed('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  /// Font size and wrapping are viewer preferences, not per-file state, so
  /// they survive closing the file and opening another one.
  void _saveViewPreferences() {
    final prefs = PreferencesService.instance;
    prefs.setString(_prefFontSize, _fontSize.toString());
    prefs.setBool(_prefWordWrap, _wordWrap);
  }

  void _zoomIn() {
    setState(() => _fontSize = (_fontSize + 1).clamp(9.0, 32.0));
    _saveViewPreferences();
  }

  void _zoomOut() {
    setState(() => _fontSize = (_fontSize - 1).clamp(9.0, 32.0));
    _saveViewPreferences();
  }

  void _resetZoom() {
    setState(() => _fontSize = 13.0);
    _saveViewPreferences();
  }

  Future<void> _openInBrowser() async {
    if (isVaultRoot(_root)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).vaultHtmlBrowserWarning)),
      );
      return;
    }
    if (_isDirty) {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context).saveChangesQuestion),
          content: Text(AppLocalizations.of(context).saveBeforeBrowserPrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(context).openWithoutSaving),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(context).saveAndOpen),
            ),
          ],
        ),
      );
      if (shouldSave == null || !mounted) return;
      if (shouldSave == true) {
        await _save();
        if (_isDirty || !mounted) return;
      }
    }
    try {
      await FileOpenService.instance.openWith(_root, _path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).failedOpenInBrowser('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _setMode(TextFileMode mode) {
    if (mode == TextFileMode.preview && !_isMarkdown && !_isHtml && !_isJson) return;
    if (mode == TextFileMode.edit && _readOnly) return;
    setState(() => _mode = mode);
  }

  void _formatJsonInEditor() {
    final result = JsonFormatter.format(_controller.text, indentSpaces: 2);
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context).jsonInvalidFormat}: ${result.errorMessage ?? ''}',
          ),
        ),
      );
      return;
    }
    if (result.formatted != _controller.text) {
      _controller.text = result.formatted;
      _clearLineCache();
      setState(() => _isDirty = true);
      _updateMatches(jumpToMatch: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = !_largeFileMode && (_isMarkdown || _isHtml || _isJson);
    GlobalPlaybackService.instance.setNamedBottomInset(
      'text_editor',
      (!_loading && _error == null) ? 40.0 : 0.0,
    );

    return AppSwipeBack(
      child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_isDirty && _error == null) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (_isDirty && _error == null) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () {
          if (_error == null && !_largeFileMode) _saveAs();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true): () {
          if (_error == null && !_largeFileMode) _saveAs();
        },
        // The file may have changed on disk (another editor, a sync client);
        // reloading is the only way to see it without leaving the page.
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _reload,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): _reload,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () => _openFind(replace: true),
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () => _openFind(replace: true),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): _showGoToLineDialog,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): _showGoToLineDialog,
        const SingleActivator(LogicalKeyboardKey.f3): _nextMatch,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true): _prevMatch,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canUndo) {
            _undoController.undo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canUndo) {
            _undoController.undo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canRedo) {
            _undoController.redo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canRedo) {
            _undoController.redo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canRedo) {
            _undoController.redo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () {
          if (_mode == TextFileMode.edit && _undoController.value.canRedo) {
            _undoController.redo();
          }
        },
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, meta: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _resetZoom,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _resetZoom,
        const SingleActivator(LogicalKeyboardKey.numpad0, control: true): _resetZoom,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_showFind) {
            _closeFind();
          } else if (_mode == TextFileMode.edit) {
            // Leave the editor without leaving the file; the dirty guard still
            // runs on the way out.
            _setMode(canPreview ? TextFileMode.preview : TextFileMode.code);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (_mode == TextFileMode.preview && _isHtml && _webViewController != null) {
              if (await _webViewController!.canGoBack()) {
                await _webViewController!.goBack();
                return;
              }
            }
            if (!context.mounted) return;
            if (!_isDirty) {
              Navigator.of(context).pop();
              return;
            }
            final discard = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(AppLocalizations.of(context).unsavedChanges),
                content: Text(AppLocalizations.of(context).saveBeforeClosingPrompt),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('cancel'),
                    child: Text(AppLocalizations.of(context).cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('discard'),
                    child: Text(AppLocalizations.of(context).discard),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop('save'),
                    child: Text(AppLocalizations.of(context).save),
                  ),
                ],
              ),
            );
            if (discard == 'save') {
              await _save();
              if (context.mounted && !_isDirty) {
                Navigator.of(context).pop();
              }
            } else if (discard == 'discard' && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_fileName${_isDirty ? ' •' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_isTemporaryInbox)
                    Text(
                      AppLocalizations.of(context).temporaryCache,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(_showFind ? Icons.search_off : Icons.search),
                  tooltip: AppLocalizations.of(context).findInFileTooltip,
                  onPressed: () {
                    if (_showFind) {
                      _closeFind();
                    } else {
                      _openFind();
                    }
                  },
                ),
                if (canPreview)
                  IconButton(
                    icon: Icon(_mode == TextFileMode.preview ? Icons.code : Icons.visibility),
                    tooltip: _mode == TextFileMode.preview ? AppLocalizations.of(context).showSource : AppLocalizations.of(context).showPreview,
                    onPressed: () => _setMode(
                      _mode == TextFileMode.preview ? TextFileMode.code : TextFileMode.preview,
                    ),
                  ),
                if (_isJson && !_readOnly && _mode == TextFileMode.edit)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high),
                    tooltip: AppLocalizations.of(context).jsonFormatInEditor,
                    onPressed: _formatJsonInEditor,
                  ),
                if (_isHtml && !_largeFileMode)
                  IconButton(
                    icon: const Icon(Icons.open_in_browser),
                    tooltip: AppLocalizations.of(context).openInBrowser,
                    onPressed: _openInBrowser,
                  ),
                if (_isMarkdown && _mode == TextFileMode.preview) ...[
                  PopupMenuButton<MarkdownThemeType>(
                    tooltip: AppLocalizations.of(context).markdownTheme,
                    icon: const Icon(Icons.palette_outlined),
                    initialValue: _markdownTheme,
                    onSelected: (theme) {
                      setState(() => _markdownTheme = theme);
                      PreferencesService.instance.setString(_prefMarkdownTheme, theme.id);
                    },
                    itemBuilder: (ctx) => [
                      for (final theme in MarkdownThemeType.values)
                        PopupMenuItem(
                          value: theme,
                          child: Row(
                            children: [
                              Icon(
                                theme.icon,
                                size: 18,
                                color: _markdownTheme == theme
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  theme.label,
                                  style: TextStyle(
                                    fontWeight: _markdownTheme == theme
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _markdownTheme == theme
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                              ),
                              if (_markdownTheme == theme)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (_exportingPdf)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(context).exportToPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onSelected: (val) {
                        if (val == 'preview') {
                          _exportPdf(share: false);
                        } else if (val == 'share') {
                          _exportPdf(share: true);
                        } else if (val.startsWith('margin_')) {
                          final modeId = val.substring('margin_'.length);
                          final mode = PdfMarginMode.fromId(modeId);
                          setState(() => _pdfMargin = mode);
                          PreferencesService.instance.setString(_prefPdfMargin, mode.id);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'preview',
                          child: Row(
                            children: [
                              Icon(Icons.print_outlined, size: 18),
                              SizedBox(width: 10),
                              Text(AppLocalizations.of(context).printPreviewPdf),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 10),
                              Text(AppLocalizations.of(context).shareSavePdf),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          height: 28,
                          child: Text(
                            AppLocalizations.of(context).marginsSpacing,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        for (final mode in PdfMarginMode.values)
                          CheckedPopupMenuItem<String>(
                            value: 'margin_${mode.id}',
                            checked: _pdfMargin == mode,
                            child: Text(mode.localizedName(AppLocalizations.of(context))),
                          ),
                      ],
                    ),
                ],
                if (_readOnly)
                  IconButton(
                    icon: Icon(Icons.lock_outline),
                    tooltip: AppLocalizations.of(context).readOnlyCannotEditTooltip,
                    onPressed: null,
                  )
                else ...[
                  if (_mode == TextFileMode.edit || _isDirty)
                    IconButton(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.save_outlined,
                              color: _isDirty ? Theme.of(context).colorScheme.primary : null,
                            ),
                      tooltip: _isDirty ? AppLocalizations.of(context).saveChangesTooltip : AppLocalizations.of(context).savedLabel,
                      onPressed: (_isDirty && !_saving && _error == null)
                          ? () {
                              HapticFeedback.lightImpact();
                              _save();
                            }
                          : null,
                    ),
                  IconButton(
                    icon: Icon(_mode == TextFileMode.edit ? Icons.edit_off_outlined : Icons.edit_outlined),
                    tooltip: _mode == TextFileMode.edit
                        ? AppLocalizations.of(context).readOnlyViewMode
                        : AppLocalizations.of(context).editLabel,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _setMode(_mode == TextFileMode.edit ? TextFileMode.code : TextFileMode.edit);
                    },
                  ),
                ],
                PopupMenuButton<String>(
                  tooltip: AppLocalizations.of(context).textOptions,
                  icon: const Icon(Icons.tune),
                    onSelected: (val) {
                      if (val == 'zoom_in') {
                        setState(() => _fontSize = (_fontSize + 1).clamp(9.0, 32.0));
                        _saveViewPreferences();
                      } else if (val == 'zoom_out') {
                        setState(() => _fontSize = (_fontSize - 1).clamp(9.0, 32.0));
                        _saveViewPreferences();
                      } else if (val == 'reset_zoom') {
                        setState(() => _fontSize = 13.0);
                        _saveViewPreferences();
                      } else if (val == 'toggle_wrap') {
                        setState(() => _wordWrap = !_wordWrap);
                        _saveViewPreferences();
                      } else if (val == 'goto_line') {
                        _showGoToLineDialog();
                      } else if (val == 'open_in_browser') {
                        _openInBrowser();
                      } else if (val == 'reload') {
                        _reload();
                      } else if (val == 'save_as') {
                        _saveAs();
                      } else if (val == 'copy_all') {
                        Clipboard.setData(ClipboardData(text: _controller.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context).allTextCopied)),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (_isHtml && !_largeFileMode)
                        PopupMenuItem(
                          value: 'open_in_browser',
                          child: Row(
                            children: [
                              const Icon(Icons.open_in_browser, size: 20),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context).openInBrowser),
                            ],
                          ),
                        ),
                      if (!_largeFileMode)
                        PopupMenuItem(
                          value: 'save_as',
                          child: Row(
                            children: [
                              const Icon(Icons.save_as_outlined, size: 20),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context).saveAs),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'reload',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 8),
                            Text(AppLocalizations.of(context).reloadFromDiskShortcut),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'copy_all',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 20),
                            SizedBox(width: 8),
                            Text(AppLocalizations.of(context).copyAllText),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'goto_line',
                        child: Row(
                          children: [
                            Icon(Icons.format_list_numbered, size: 20),
                            SizedBox(width: 8),
                            Text(AppLocalizations.of(context).goToLineShortcut),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'zoom_in',
                        child: Row(
                          children: [
                            const Icon(Icons.zoom_in, size: 20),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context).largerFontShortcut(_fontSize.toInt() + 1)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'zoom_out',
                        child: Row(
                          children: [
                            const Icon(Icons.zoom_out, size: 20),
                            const SizedBox(width: 8),
                            Text(AppLocalizations.of(context).smallerFontShortcut(_fontSize.toInt() - 1)),
                          ],
                        ),
                      ),
                      if (_fontSize != 13.0)
                        PopupMenuItem(
                          value: 'reset_zoom',
                          child: Row(
                            children: [
                              Icon(Icons.restart_alt, size: 20),
                              SizedBox(width: 8),
                              Text(AppLocalizations.of(context).resetFontShortcut),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'toggle_wrap',
                        checked: _wordWrap,
                        child: Text(AppLocalizations.of(context).wordWrap),
                      ),
                    ],
                  ),
                if (_mode == TextFileMode.edit)
                  ValueListenableBuilder<UndoHistoryValue>(
                    valueListenable: _undoController,
                    builder: (context, value, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.undo),
                            tooltip: AppLocalizations.of(context).undoShortcut,
                            onPressed: value.canUndo ? _undoController.undo : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.redo),
                            tooltip: AppLocalizations.of(context).redoShortcut,
                            onPressed: value.canRedo ? _undoController.redo : null,
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text(AppLocalizations.of(context).failedToOpenFile('$_error')),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _loadFile, child: Text(AppLocalizations.of(context).retry)),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          if (_largeFileMode)
                            _buildLargeFileBar()
                          else if (_readOnly)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              color: Colors.amber.withValues(alpha: 0.15),
                              child: Text(
                                AppLocalizations.of(context).readOnlyCannotSave,
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          if (_showFind) _buildFindBar(),
                          Expanded(child: _buildContent()),
                          _buildStatusBar(),
                        ],
                      ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildLargeFileBar() {
    final l10n = AppLocalizations.of(context);
    final notice = l10n.largeFilePagedNotice(
      _formatByteOffset(_chunkStart),
      _formatByteOffset(_chunkEnd),
      _formatByteOffset(_chunkTotal),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.amber.withValues(alpha: 0.15),
      child: Row(
        children: [
          Expanded(
            child: Text(
              notice,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_loadingChunk) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: l10n.previousPage,
            visualDensity: VisualDensity.compact,
            onPressed: (!_loadingChunk && _chunkHasPrev) ? _prevTextPage : null,
          ),
          TextButton.icon(
            onPressed: (!_loadingChunk && _chunkTotal > 0)
                ? _showJumpPositionDialog
                : null,
            icon: const Icon(Icons.my_location, size: 15),
            label: Text(l10n.jumpToPosition, style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: l10n.nextPage,
            visualDensity: VisualDensity.compact,
            onPressed: (!_loadingChunk && _chunkHasNext) ? _nextTextPage : null,
          ),
        ],
      ),
    );
  }

  Widget _buildFindBar() {
    return EditorFindReplaceBar(
      findController: _findController,
      replaceController: _replaceController,
      findFocusNode: _findFocusNode,
      replaceFocusNode: _replaceFocusNode,
      showReplace: _showReplace,
      readOnly: _readOnly,
      matchCount: _matchIndices.length,
      currentMatchIndex: _currentMatchIndex,
      matchCountCapped: _matchIndices.length >= 10000,
      onQueryChanged: _onFindChanged,
      onClearFind: () {
        _findDebounce?.cancel();
        _findController.clear();
        _updateMatches(jumpToMatch: false);
      },
      onFindSubmitted: () {
        _findDebounce?.cancel();
        if (_findController.text != _lastFindQuery) {
          _updateMatches(jumpToMatch: true, forceScroll: true);
        } else {
          _nextMatch();
        }
      },
      onPreviousMatch: _prevMatch,
      onNextMatch: _nextMatch,
      onReplaceOne: _replaceCurrent,
      onReplaceAll: _replaceAll,
      onToggleReplace: () {
        setState(() => _showReplace = !_showReplace);
        if (_showReplace) _replaceFocusNode.requestFocus();
      },
      onClose: _closeFind,
    );
  }
  void _showDocumentStats() {
    HapticFeedback.mediumImpact();
    final text = _controller.text;
    int lines = text.isEmpty ? 1 : 1;
    int crlfCount = 0;
    int lfCount = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) {
        lines++;
        if (i > 0 && text.codeUnitAt(i - 1) == 13) {
          crlfCount++;
        } else {
          lfCount++;
        }
      }
    }
    final words = RegExp(r'[\w一-龥]+').allMatches(text).length;
    final chars = text.length;
    final bytes = utf8.encode(text).length;
    final lineEnding = crlfCount > lfCount ? 'CRLF (Windows)' : 'LF (Unix)';

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_outlined, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context).documentDetails,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: Text(AppLocalizations.of(context).copyAll),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(AppLocalizations.of(context).documentCopied),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Divider(),
                _statRow(AppLocalizations.of(context).fileLabel, _fileName),
                _statRow(AppLocalizations.of(context).linesLabel, '$lines'),
                _statRow(AppLocalizations.of(context).wordsLabel, '$words'),
                _statRow(AppLocalizations.of(context).charactersLabel, '$chars'),
                _statRow(AppLocalizations.of(context).byteSizeLabel, AppLocalizations.of(context).bytesUnit('$bytes')),
                _statRow(AppLocalizations.of(context).lineEndingsLabel, lineEnding),
                _statRow(AppLocalizations.of(context).cursorPositionLabel, AppLocalizations.of(context).cursorLineCol(_cursorLine, _cursorCol)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return ListenableBuilder(
      listenable: Listenable.merge([_cursorPosNotifier, _controller]),
      builder: (context, _) {
        final text = _controller.text;
        final chars = text.length;
        if (_cachedStatsText != text) {
          _cachedStatsText = text;
          if (text.isEmpty) {
            _cachedLines = 1;
            _cachedWords = 0;
          } else {
            int lines = 1;
            int words = 0;
            bool inWord = false;
            final countWords = chars <= 50000;
            for (int i = 0; i < text.length; i++) {
              final code = text.codeUnitAt(i);
              if (code == 10) lines++;
              if (countWords) {
                final isSpace = code <= 32;
                if (isSpace) {
                  inWord = false;
                } else if (!inWord) {
                  inWord = true;
                  words++;
                }
              }
            }
            _cachedLines = lines;
            _cachedWords = countWords ? words : null;
          }
        }
        final lines = _cachedLines;
        final words = _cachedWords;
        final modeLabel = _readOnly
            ? AppLocalizations.of(context).readOnlyLocation
            : _mode == TextFileMode.preview
                ? AppLocalizations.of(context).previewModeLabel
                : (_mode == TextFileMode.code
                    ? AppLocalizations.of(context).viewingSourceLabel
                    : AppLocalizations.of(context).editingModeLabel);

        return EditorStatusBar(
          modeLabel: modeLabel,
          isDirty: _isDirty,
          cursorLine: _cursorLine,
          cursorCol: _cursorCol,
          lines: lines,
          words: words,
          chars: chars,
          largeFileMode: _largeFileMode,
          chunkEncoding: _chunkEncoding,
          fontSize: _fontSize,
          wordWrap: _wordWrap,
          onTapStats: _showDocumentStats,
        );
      },
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case TextFileMode.preview:
        return EditorPreviewPane(
          isMarkdown: _isMarkdown,
          isJson: _isJson,
          readOnly: _readOnly,
          root: _root,
          path: _path,
          text: _controller.text,
          isDirty: _isDirty,
          fontSize: _fontSize,
          markdownTheme: _markdownTheme,
          filterQuery: _showFind ? _findController.text : '',
          onEditSource: () => _setMode(TextFileMode.edit),
          onOpenRawCode: () => _setMode(TextFileMode.code),
          onHtmlControllerCreated: (controller) => _webViewController = controller,
          onOpenHtmlInBrowser: _openInBrowser,
        );
      case TextFileMode.code:
        return _buildCodeView();
      case TextFileMode.edit:
        final brightness = Theme.of(context).brightness;
        final background = HighlightService.instance.backgroundFor(brightness);
        return Container(
          color: background,
          child: TextField(
            controller: _controller,
            scrollController: _editScrollController,
            undoController: _undoController,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: MarkdownThemeConfig.monoFontFamilyFallback,
              fontSize: _fontSize,
              height: 1.35,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            onChanged: (_) {
              if (!_isDirty) setState(() => _isDirty = true);
              _clearLineCache();
              if (_showFind && _findController.text.isNotEmpty) {
                _findDebounce?.cancel();
                _findDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (!mounted) return;
                  _updateMatches(jumpToMatch: false);
                });
              }
            },
          ),
        );
    }
  }

  Widget _buildCodeView() {
    final text = _controller.text;
    final brightness = Theme.of(context).brightness;
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: MarkdownThemeConfig.monoFontFamilyFallback,
      fontSize: _fontSize,
      height: 1.35,
    );
    final background = HighlightService.instance.backgroundFor(brightness);

    final metricPainter = TextPainter(
      text: TextSpan(text: 'M', style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineHeight = metricPainter.preferredLineHeight;

    if (_isLargeDocument(text)) {
      return _buildVirtualizedCodeView(
        lines: _cachedLinesList ?? text.split('\n'),
        baseStyle: baseStyle,
        background: background,
        lineHeight: lineHeight,
      );
    }

    final span = HighlightService.instance.spanFor(
      text,
      _fileName,
      brightness,
      fontSize: _fontSize,
    );

    TextSpan resultSpan = span ?? TextSpan(text: text, style: baseStyle);

    if (_showFind &&
        _findController.text.isNotEmpty &&
        _matchIndices.isNotEmpty) {
      final currentOffset = (_currentMatchIndex >= 0 &&
              _currentMatchIndex < _matchIndices.length)
          ? _matchIndices[_currentMatchIndex]
          : -1;
      resultSpan = _SpanWalker(
        query: _findController.text,
        matches: _matchIndices,
        currentOffset: currentOffset,
        baseStyle: baseStyle,
      ).walk(resultSpan);
    }

    Widget textWidget = SelectableText.rich(
      resultSpan,
      key: const ValueKey('code_view'),
    );

    if (!_wordWrap) {
      textWidget = SingleChildScrollView(
        controller: _codeHorizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: textWidget,
      );
    }

    return Container(
      color: background,
      width: double.infinity,
      child: SingleChildScrollView(
        controller: _codeScrollController,
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(16),
        child: textWidget,
      ),
    );
  }

  Widget _buildVirtualizedCodeView({
    required List<String> lines,
    required TextStyle baseStyle,
    required Color background,
    required double lineHeight,
  }) {
    final activeMatchOffset = (_showFind &&
            _currentMatchIndex >= 0 &&
            _currentMatchIndex < _matchIndices.length)
        ? _matchIndices[_currentMatchIndex]
        : -1;

    Widget listView = SelectionArea(
      child: ListView.builder(
        controller: _codeScrollController,
        padding: const EdgeInsets.all(16),
        itemCount: lines.length,
        itemExtent: !_wordWrap ? lineHeight : null,
        itemBuilder: (context, index) {
          final lineText = lines[index];
          final lineStart = _cachedLineStarts != null && index < _cachedLineStarts!.length
              ? _cachedLineStarts![index]
              : 0;

          if (_showFind && _findController.text.isNotEmpty && _matchIndices.isNotEmpty) {
            return _buildHighlightedLine(
              index,
              lineText,
              baseStyle,
              lineStart,
              activeMatchOffset,
            );
          }
          return Text(
            lineText.isEmpty ? ' ' : lineText,
            style: baseStyle,
            softWrap: _wordWrap,
          );
        },
      ),
    );

    if (!_wordWrap) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final charWidth = _getCharWidth(baseStyle);
          final estimatedContentWidth = (_maxLineChars * charWidth) + 64.0;
          final totalWidth = max(constraints.maxWidth, estimatedContentWidth);

          return Container(
            color: background,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: SingleChildScrollView(
              controller: _codeHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                height: constraints.maxHeight,
                child: listView,
              ),
            ),
          );
        },
      );
    }

    return Container(
      color: background,
      width: double.infinity,
      height: double.infinity,
      child: listView,
    );
  }

  Widget _buildHighlightedLine(
    int lineIndex,
    String lineText,
    TextStyle baseStyle,
    int lineStartOffset,
    int activeMatchOffset,
  ) {
    final query = _findController.text;
    final lowerLine = lineText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerLine.contains(lowerQuery)) {
      return Text(
        lineText.isEmpty ? ' ' : lineText,
        style: baseStyle,
        softWrap: _wordWrap,
      );
    }

    final spans = <InlineSpan>[];
    int start = 0;
    while (true) {
      final idx = lowerLine.indexOf(lowerQuery, start);
      if (idx == -1) {
        if (start < lineText.length) {
          spans.add(TextSpan(text: lineText.substring(start), style: baseStyle));
        }
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: lineText.substring(start, idx), style: baseStyle));
      }
      final globalOffset = lineStartOffset + idx;
      final isCurrent = globalOffset == activeMatchOffset;
      spans.add(TextSpan(
        text: lineText.substring(idx, idx + query.length),
        style: baseStyle.copyWith(
          backgroundColor: isCurrent ? const Color(0xFFFF6D00) : const Color(0xFFFFEB3B),
          color: isCurrent ? Colors.white : Colors.black,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
        ),
      ));
      start = idx + query.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      softWrap: _wordWrap,
    );
  }
}

class _SpanWalker {
  final String query;
  final List<int> matches;
  final int currentOffset;
  final TextStyle baseStyle;
  int _globalOffset = 0;
  int _matchPointer = 0;

  _SpanWalker({
    required this.query,
    required this.matches,
    required this.currentOffset,
    required this.baseStyle,
  });

  TextSpan walk(TextSpan span) {
    final text = span.text;
    List<InlineSpan>? pieceSpans;

    if (text != null && text.isNotEmpty) {
      final spanStart = _globalOffset;
      final spanEnd = spanStart + text.length;
      _globalOffset = spanEnd;

      final qLen = query.length;
      while (_matchPointer < matches.length && matches[_matchPointer] + qLen <= spanStart) {
        _matchPointer++;
      }

      final intersecting = <int>[];
      var cursor = _matchPointer;
      while (cursor < matches.length) {
        final m = matches[cursor];
        if (m >= spanEnd) break;
        intersecting.add(m);
        cursor++;
      }

      if (intersecting.isNotEmpty) {
        final cutPoints = <int>{0, text.length};
        for (final m in intersecting) {
          final relStart = (m - spanStart).clamp(0, text.length);
          final relEnd = (m + qLen - spanStart).clamp(0, text.length);
          cutPoints.add(relStart);
          cutPoints.add(relEnd);
        }
        final sortedCuts = cutPoints.toList()..sort();

        pieceSpans = <InlineSpan>[];
        final parentStyle = span.style ?? baseStyle;

        for (int i = 0; i < sortedCuts.length - 1; i++) {
          final start = sortedCuts[i];
          final end = sortedCuts[i + 1];
          if (start >= end) continue;
          final pieceText = text.substring(start, end);
          final pieceGlobalStart = spanStart + start;
          final pieceGlobalEnd = spanStart + end;

          int matchedAt = -1;
          for (final m in intersecting) {
            if (pieceGlobalStart >= m && pieceGlobalEnd <= m + qLen) {
              matchedAt = m;
              break;
            }
          }

          if (matchedAt != -1) {
            final isCurrent = matchedAt == currentOffset;
            pieceSpans.add(TextSpan(
              text: pieceText,
              style: parentStyle.copyWith(
                backgroundColor: isCurrent ? const Color(0xFFFF6D00) : const Color(0xFFFFEB3B),
                color: isCurrent ? Colors.white : Colors.black,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
              ),
            ));
          } else {
            pieceSpans.add(TextSpan(
              text: pieceText,
              style: parentStyle,
            ));
          }
        }
      }
    }

    List<InlineSpan>? newChildren;
    if (span.children != null && span.children!.isNotEmpty) {
      newChildren = [];
      for (final child in span.children!) {
        if (child is TextSpan) {
          newChildren.add(walk(child));
        } else {
          newChildren.add(child);
        }
      }
    }

    if (pieceSpans != null) {
      if (newChildren != null) {
        pieceSpans.addAll(newChildren);
      }
      return TextSpan(
        children: pieceSpans,
        style: span.style,
        recognizer: span.recognizer,
      );
    }

    if (newChildren != null) {
      return TextSpan(
        text: text,
        children: newChildren,
        style: span.style,
        recognizer: span.recognizer,
      );
    }

    return span;
  }
}

class SyntaxHighlightingEditingController extends TextEditingController {
  String fileName;
  final Brightness Function() brightnessProvider;
  final double Function()? fontSizeProvider;

  String? _searchQuery;
  List<int>? _searchMatches;
  int? _currentMatchIndex;

  SyntaxHighlightingEditingController({
    super.text,
    required this.fileName,
    required this.brightnessProvider,
    this.fontSizeProvider,
  });

  void updateFileName(String newName) {
    fileName = newName;
    notifyListeners();
  }

  void updateSearch({
    String? query,
    List<int>? matches,
    int? currentMatch,
  }) {
    _searchQuery = query;
    _searchMatches = matches;
    _currentMatchIndex = currentMatch;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final size = fontSizeProvider?.call() ?? 13.0;
    final baseStyle = (style ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontSize: size,
      height: 1.35,
    );

    final span = HighlightService.instance.spanFor(
      text,
      fileName,
      brightnessProvider(),
      fontSize: size,
    );

    TextSpan resultSpan = span ?? TextSpan(text: text, style: baseStyle);

    if (_searchQuery != null &&
        _searchQuery!.isNotEmpty &&
        _searchMatches != null &&
        _searchMatches!.isNotEmpty) {
      final currentOffset = (_currentMatchIndex != null &&
              _currentMatchIndex! >= 0 &&
              _currentMatchIndex! < _searchMatches!.length)
          ? _searchMatches![_currentMatchIndex!]
          : -1;
      resultSpan = _SpanWalker(
        query: _searchQuery!,
        matches: _searchMatches!,
        currentOffset: currentOffset,
        baseStyle: baseStyle,
      ).walk(resultSpan);
    }

    return resultSpan;
  }
}

