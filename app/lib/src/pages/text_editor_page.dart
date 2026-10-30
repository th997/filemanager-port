import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:webview_flutter/webview_flutter.dart';

import '../rust/api/file_manager.dart';
import '../services/file_open_service.dart';
import '../services/highlight_service.dart';
import '../services/markdown_pdf_service.dart';
import '../services/preferences_service.dart';
import '../theme/app_ui_tokens.dart';
import '../theme/markdown_themes.dart';
import '../widgets/html_preview_widget.dart';
import '../widgets/markdown_callout_builder.dart';
import '../widgets/markdown_code_builder.dart';

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

  const TextEditorPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    this.readOnly = false,
  });

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  late final SyntaxHighlightingEditingController _controller;
  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;
  late TextFileMode _mode;
  static const _prefFontSize = 'editor.font_size';
  static const _prefWordWrap = 'editor.word_wrap';
  static const _prefMarkdownTheme = 'markdown.theme';
  static const _prefPdfMargin = 'markdown.pdf_margin';
  double _fontSize = 13.0;
  bool _wordWrap = true;
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
  int _cursorLine = 1;
  int _cursorCol = 1;
  WebViewController? _webViewController;

  String get _lowerName => widget.fileName.toLowerCase();
  bool get _isMarkdown => _lowerName.endsWith('.md') || _lowerName.endsWith('.markdown');
  bool get _isHtml => _lowerName.endsWith('.html') || _lowerName.endsWith('.htm') || _lowerName.endsWith('.xhtml');

  @override
  void initState() {
    super.initState();
    _controller = SyntaxHighlightingEditingController(
      fileName: widget.fileName,
      brightnessProvider: () => Theme.of(context).brightness,
      fontSizeProvider: () => _fontSize,
    );
    _controller.addListener(_updateCursorPosition);
    final prefs = PreferencesService.instance;
    _fontSize = double.tryParse(prefs.getString(_prefFontSize) ?? '') ?? _fontSize;
    _wordWrap = prefs.getBool(_prefWordWrap) ?? _wordWrap;
    _markdownTheme = MarkdownThemeType.fromId(prefs.getString(_prefMarkdownTheme));
    _pdfMargin = PdfMarginMode.fromId(prefs.getString(_prefPdfMargin));
    _mode = (_isMarkdown || _isHtml) ? TextFileMode.preview : TextFileMode.code;
    _loadFile();
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  void _updateCursorPosition() {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid || sel.baseOffset < 0 || sel.baseOffset > text.length) {
      if (_cursorLine != 1 || _cursorCol != 1) {
        setState(() {
          _cursorLine = 1;
          _cursorCol = 1;
        });
      }
      return;
    }
    final offset = sel.baseOffset;
    final prefix = text.substring(0, offset);
    final lines = prefix.split('\n');
    final newLine = lines.length;
    final newCol = lines.last.length + 1;
    if (_cursorLine != newLine || _cursorCol != newCol) {
      setState(() {
        _cursorLine = newLine;
        _cursorCol = newCol;
      });
    }
  }

  Future<void> _showGoToLineDialog() async {
    final text = _controller.text;
    final totalLines = text.isEmpty ? 1 : text.split('\n').length;
    final ctrl = TextEditingController();
    final String? input;
    try {
      input = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Go to Line'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Line number (1 - $totalLines)',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Go')),
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
          content: Text('Enter a line number between 1 and $totalLines'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final lines = text.split('\n');
    final clampedLine = targetLine.clamp(1, lines.length);
    int offset = 0;
    for (int i = 0; i < clampedLine - 1; i++) {
      offset += lines[i].length + 1;
    }
    final lineEnd = offset + lines[clampedLine - 1].length;
    _controller.selection = TextSelection(baseOffset: offset, extentOffset: lineEnd);
    _scrollToMatch(offset);
  }

  void _openFind({bool replace = false}) {
    if (_mode == TextFileMode.preview) {
      _setMode(TextFileMode.code);
    }
    setState(() {
      _showFind = true;
      if (replace && !widget.readOnly) _showReplace = true;
    });
    _findFocusNode.requestFocus();
    _updateMatches();
  }

  void _updateMatches() {
    final query = _findController.text;
    _matchIndices.clear();
    if (query.isNotEmpty) {
      final lowerText = _controller.text.toLowerCase();
      final lowerQuery = query.toLowerCase();
      int start = 0;
      while (true) {
        final index = lowerText.indexOf(lowerQuery, start);
        if (index == -1) break;
        _matchIndices.add(index);
        start = index + lowerQuery.length;
      }
    }
    if (_matchIndices.isEmpty) {
      _currentMatchIndex = 0;
    } else if (_currentMatchIndex >= _matchIndices.length) {
      _currentMatchIndex = 0;
    }
    _selectCurrentMatch();
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
    setState(() {
      _showFind = false;
      _showReplace = false;
      _matchIndices.clear();
      _currentMatchIndex = 0;
    });
    _controller.updateSearch(query: null, matches: null, currentMatch: null);
  }

  void _nextMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchIndices.length;
    });
    _selectCurrentMatch();
    _controller.updateSearch(
      query: _findController.text,
      matches: _matchIndices,
      currentMatch: _currentMatchIndex,
    );
  }

  void _prevMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchIndices.length) % _matchIndices.length;
    });
    _selectCurrentMatch();
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
    if (widget.readOnly) return;
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
      _updateMatches(); // stale indices — rescan instead of corrupting text
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: text.replaceRange(idx, idx + query.length, replacement),
      selection:
          TextSelection.collapsed(offset: idx + replacement.length),
    );
    setState(() => _isDirty = true);
    _updateMatches();
  }

  void _replaceAll() {
    if (widget.readOnly) return;
    _ensureEditing();
    final query = _findController.text;
    if (query.isEmpty) return;
    final replacement = _replaceController.text;
    final text = _controller.text;
    final lowerText = text.toLowerCase();
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
    _controller.value = _controller.value.copyWith(
      text: buf.toString(),
      selection: const TextSelection.collapsed(offset: 0),
    );
    setState(() => _isDirty = true);
    _updateMatches();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Replaced $count occurrence${count == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  void _selectCurrentMatch() {
    if (_matchIndices.isEmpty) return;
    final idx = _matchIndices[_currentMatchIndex];
    final len = _findController.text.length;
    _controller.selection = TextSelection(baseOffset: idx, extentOffset: idx + len);
    _scrollToMatch(idx);
  }

  void _scrollToMatch(int charIndex) {
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

      final mediaWidth = MediaQuery.of(context).size.width;
      final viewWidth = mediaWidth > 32 ? mediaWidth - 32 : mediaWidth;
      final lineHeight = _fontSize * 1.35;
      const contentPadding = 16.0;

      double caretDy = 0.0;
      double caretDx = 0.0;

      if (!_wordWrap && _mode == TextFileMode.code) {
        // Fast O(1) path for non-wrapping code view: each line is exactly lineHeight tall
        int lineCount = 0;
        int lineStart = 0;
        for (int i = 0; i < charIndex; i++) {
          if (text.codeUnitAt(i) == 10) {
            lineCount++;
            lineStart = i + 1;
          }
        }
        caretDy = lineCount * lineHeight;

        final linePrefix = text.substring(lineStart, charIndex);
        final linePainter = TextPainter(
          text: TextSpan(text: linePrefix, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        caretDx = linePainter.width;
      } else {
        // Wrapping mode (or edit mode): layout text up to the line containing charIndex
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
      }

      final viewport = activeVerticalController.position.viewportDimension;
      final targetY = ((contentPadding + caretDy) - (viewport - lineHeight) / 2).clamp(
        0.0,
        activeVerticalController.position.maxScrollExtent,
      );

      activeVerticalController.animateTo(
        targetY,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );

      if (!_wordWrap && activeHorizontalController != null && activeHorizontalController.hasClients) {
        final hViewport = activeHorizontalController.position.viewportDimension;
        final targetX = ((contentPadding + caretDx) - (hViewport / 2)).clamp(
          0.0,
          activeHorizontalController.position.maxScrollExtent,
        );
        activeHorizontalController.animateTo(
          targetX,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final content = await readTextFile(root: widget.root, path: widget.path);
      if (mounted) {
        setState(() {
          _controller.text = content;
          _loading = false;
          _isDirty = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Re-reads the file, confirming first if there are edits to lose.
  Future<void> _reload() async {
    if (_isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reload File'),
          content: const Text(
            'Discard unsaved changes and reload the file from disk?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reload'),
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
    if (_loading || _error != null) return;
    setState(() => _saving = true);
    final savedText = _controller.text;
    try {
      await writeTextFile(
        root: widget.root,
        path: widget.path,
        content: savedText,
      );
      // Edits made while the write was in flight keep the file dirty.
      if (mounted) {
        setState(() {
          _saving = false;
          _isDirty = _controller.text != savedText;
        });
        _webViewController?.reload();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Theme.of(context).colorScheme.error),
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
          title: widget.fileName,
          themeConfig: themeConfig,
          marginMode: _pdfMargin,
        );
      } else {
        await MarkdownPdfService.instance.printOrPreview(
          markdown: text,
          title: widget.fileName,
          themeConfig: themeConfig,
          marginMode: _pdfMargin,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF Export failed: $e'),
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
    if (_isDirty) {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save Changes?'),
          content: const Text('Do you want to save your changes before opening in the external browser?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Open without Saving'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save and Open'),
            ),
          ],
        ),
      );
      if (shouldSave == true) {
        await _save();
      }
    }
    try {
      await FileOpenService.instance.openWith(widget.root, widget.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open in browser: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _setMode(TextFileMode mode) {
    if (mode == TextFileMode.preview && !_isMarkdown && !_isHtml) return;
    if (mode == TextFileMode.edit && widget.readOnly) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _isMarkdown || _isHtml;

    return AppSwipeBack(
      child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_isDirty && _error == null) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (_isDirty && _error == null) _save();
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
            if (_mode == TextFileMode.preview && !_isMarkdown && _webViewController != null) {
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
                title: const Text('Unsaved Changes'),
                content: const Text('You have unsaved changes. Save them before closing?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('cancel'),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop('discard'),
                    child: const Text('Discard'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop('save'),
                    child: const Text('Save'),
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
              title: Text(
                '${widget.fileName}${_isDirty ? ' •' : ''}',
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  icon: Icon(_showFind ? Icons.search_off : Icons.search),
                  tooltip: 'Find in file (Ctrl+F)',
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
                    tooltip: _mode == TextFileMode.preview ? 'Show source' : 'Show preview',
                    onPressed: () => _setMode(
                      _mode == TextFileMode.preview ? TextFileMode.code : TextFileMode.preview,
                    ),
                  ),
                if (_isHtml)
                  IconButton(
                    icon: const Icon(Icons.open_in_browser),
                    tooltip: '在系统浏览器中打开 (Open in Browser)',
                    onPressed: _openInBrowser,
                  ),
                if (_isMarkdown && _mode == TextFileMode.preview) ...[
                  PopupMenuButton<MarkdownThemeType>(
                    tooltip: 'Markdown Theme',
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
                      tooltip: 'Export to PDF',
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
                        const PopupMenuItem(
                          value: 'preview',
                          child: Row(
                            children: [
                              Icon(Icons.print_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Print / Preview PDF'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Share / Save PDF'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          height: 28,
                          child: Text(
                            '页间距 / 边距',
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
                            child: Text(mode.label),
                          ),
                      ],
                    ),
                ],
                if (widget.readOnly)
                  const IconButton(
                    icon: Icon(Icons.lock_outline),
                    tooltip: 'Read-only location — this file cannot be edited here',
                    onPressed: null,
                  )
                else ...[
                  if (_mode == TextFileMode.edit)
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
                      tooltip: _isDirty ? 'Save changes (Ctrl+S)' : 'Saved',
                      onPressed: (_isDirty && !_saving && _error == null)
                          ? () {
                              HapticFeedback.lightImpact();
                              _save();
                            }
                          : null,
                    ),
                  if (_mode != TextFileMode.edit)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () => _setMode(TextFileMode.edit),
                    ),
                ],
                PopupMenuButton<String>(
                  tooltip: 'Text Options',
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
                      } else if (val == 'copy_all') {
                        Clipboard.setData(ClipboardData(text: _controller.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('All text copied to clipboard')),
                        );
                      }
                    },
                    itemBuilder: (ctx) => [
                      if (_isHtml)
                        const PopupMenuItem(
                          value: 'open_in_browser',
                          child: Row(
                            children: [
                              Icon(Icons.open_in_browser, size: 20),
                              SizedBox(width: 8),
                              Text('在系统浏览器中打开'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'reload',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, size: 20),
                            SizedBox(width: 8),
                            Text('Reload from Disk (Ctrl+R)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy_all',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 20),
                            SizedBox(width: 8),
                            Text('Copy All Text'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'goto_line',
                        child: Row(
                          children: [
                            Icon(Icons.format_list_numbered, size: 20),
                            SizedBox(width: 8),
                            Text('Go to Line... (Ctrl+G)'),
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
                            Text('Larger (Ctrl+=) (${_fontSize.toInt() + 1}pt)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'zoom_out',
                        child: Row(
                          children: [
                            const Icon(Icons.zoom_out, size: 20),
                            const SizedBox(width: 8),
                            Text('Smaller (Ctrl+-) (${_fontSize.toInt() - 1}pt)'),
                          ],
                        ),
                      ),
                      if (_fontSize != 13.0)
                        const PopupMenuItem(
                          value: 'reset_zoom',
                          child: Row(
                            children: [
                              Icon(Icons.restart_alt, size: 20),
                              SizedBox(width: 8),
                              Text('Reset Size (Ctrl+0) (13pt)'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      CheckedPopupMenuItem(
                        value: 'toggle_wrap',
                        checked: _wordWrap,
                        child: const Text('Word Wrap'),
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
                            tooltip: 'Undo (Ctrl+Z)',
                            onPressed: value.canUndo ? _undoController.undo : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.redo),
                            tooltip: 'Redo (Ctrl+Y)',
                            onPressed: value.canRedo ? _undoController.redo : null,
                          ),
                        ],
                      );
                    },
                  ),
                if (_mode == TextFileMode.edit && _saving)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_mode == TextFileMode.edit)
                  IconButton(
                    icon: const Icon(Icons.save),
                    tooltip: 'Save (Ctrl+S)',
                    onPressed: _isDirty && _error == null ? _save : null,
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
                              Text('Failed to open file: $_error'),
                              const SizedBox(height: 16),
                              FilledButton(onPressed: _loadFile, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          if (widget.readOnly)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              color: Colors.amber.withValues(alpha: 0.15),
                              child: const Text(
                                'Read-only location — changes cannot be saved here.',
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

  Widget _buildFindBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
          const Icon(Icons.search, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _findController,
              focusNode: _findFocusNode,
              decoration: InputDecoration(
                hintText: 'Find in file...',
                isDense: true,
                border: InputBorder.none,
                suffixIcon: _findController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        tooltip: 'Clear',
                        onPressed: () {
                          _findController.clear();
                          _updateMatches();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => _updateMatches(),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          if (_findController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _matchIndices.isEmpty
                    ? '0/0'
                    : '${_currentMatchIndex + 1}/${_matchIndices.length}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            tooltip: 'Previous match',
            onPressed: _matchIndices.isEmpty ? null : _prevMatch,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            tooltip: 'Next match',
            onPressed: _matchIndices.isEmpty ? null : _nextMatch,
          ),
          if (!widget.readOnly)
            IconButton(
              icon: Icon(
                _showReplace ? Icons.find_replace : Icons.find_replace_outlined,
                size: 18,
              ),
              tooltip: 'Toggle replace (Ctrl+H)',
              onPressed: () {
                setState(() => _showReplace = !_showReplace);
                if (_showReplace) _replaceFocusNode.requestFocus();
              },
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close find (Esc)',
            onPressed: _closeFind,
          ),
            ],
          ),
          if (_showReplace && !widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_alt, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _replaceController,
                      focusNode: _replaceFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Replace with...',
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                  TextButton(
                    onPressed: _matchIndices.isEmpty ? null : _replaceCurrent,
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: _matchIndices.isEmpty ? null : _replaceAll,
                    child: const Text('Replace All'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDocumentStats() {
    HapticFeedback.mediumImpact();
    final text = _controller.text;
    final lines = text.isEmpty ? 1 : text.split('\n').length;
    final words = RegExp(r'[\w一-龥]+').allMatches(text).length;
    final chars = text.length;
    final bytes = utf8.encode(text).length;
    final crlfCount = RegExp(r'\r\n').allMatches(text).length;
    final lfCount = RegExp(r'[^\r]\n').allMatches(text).length;
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
                      'Document Details',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy All'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Document copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const Divider(),
                _statRow('File', widget.fileName),
                _statRow('Lines', '$lines'),
                _statRow('Words', '$words'),
                _statRow('Characters', '$chars'),
                _statRow('Byte Size', '$bytes bytes'),
                _statRow('Line Endings', lineEnding),
                _statRow('Cursor Position', 'Line $_cursorLine, Col $_cursorCol'),
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
    final text = _controller.text;
    final lines = text.isEmpty ? 1 : text.split('\n').length;
    final chars = text.length;
    // Counting words on every cursor move is wasted work on a large file, so
    // the count is skipped past a size where it would stall typing.
    final words = chars > 200000
        ? null
        : text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final modeLabel = widget.readOnly
        ? 'Read-only location'
        : _mode == TextFileMode.preview
            ? 'Preview'
            : (_mode == TextFileMode.code ? 'Viewing source' : 'Editing');

    return InkWell(
      onTap: _showDocumentStats,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Row(
          children: [
            Text(
              modeLabel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            if (_isDirty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Modified', style: TextStyle(fontSize: 10, color: Colors.amber)),
              ),
            ],
            const Spacer(),
            Text(
              'Ln $_cursorLine, Col $_cursorCol  •  Lines: $lines  •  '
              '${words == null ? '' : 'Words: $words  •  '}Chars: $chars  •  '
              '${_fontSize.toInt()}pt${_wordWrap ? '  •  Wrap' : ''}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case TextFileMode.preview:
        if (_isMarkdown) {
          final brightness = Theme.of(context).brightness;
          final themeConfig = MarkdownThemeConfig.get(_markdownTheme, brightness);
          return Container(
            color: themeConfig.backgroundColor,
            width: double.infinity,
            height: double.infinity,
            child: Markdown(
              data: _controller.text,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              selectable: true,
              extensionSet: md.ExtensionSet.gitHubFlavored,
              styleSheet: themeConfig.toStyleSheet(context, fontSize: _fontSize),
              builders: {
                'code': HighlightCodeElementBuilder(
                  themeConfig: themeConfig,
                  fontSize: _fontSize,
                ),
                'blockquote': CalloutBlockquoteBuilder(
                  themeConfig: themeConfig,
                  fontSize: _fontSize,
                ),
              },
            ),
          );
        }
        return HtmlPreviewWidget(
          root: widget.root,
          path: widget.path,
          rawHtml: _controller.text,
          isDirty: _isDirty,
          fontSize: _fontSize,
          onControllerCreated: (controller) => _webViewController = controller,
          onOpenInBrowser: _openInBrowser,
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
              fontSize: _fontSize,
              height: 1.35,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            onChanged: (_) {
              if (!_isDirty) setState(() => _isDirty = true);
              if (_showFind && _findController.text.isNotEmpty) {
                _updateMatches();
              }
            },
          ),
        );
    }
  }

  Widget _buildCodeView() {
    final brightness = Theme.of(context).brightness;
    final span = HighlightService.instance.spanFor(
      _controller.text,
      widget.fileName,
      brightness,
      fontSize: _fontSize,
    );
    final background = HighlightService.instance.backgroundFor(brightness);
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.35,
    );

    TextSpan resultSpan = span ?? TextSpan(text: _controller.text, style: baseStyle);

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
}

class _SpanWalker {
  final String query;
  final List<int> matches;
  final int currentOffset;
  final TextStyle baseStyle;
  int _globalOffset = 0;

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
      final intersecting = <int>[];
      for (final m in matches) {
        if (m + qLen <= spanStart) continue;
        if (m >= spanEnd) break;
        intersecting.add(m);
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
  final String fileName;
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

