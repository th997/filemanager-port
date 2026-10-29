import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:markdown/markdown.dart' as md;

import '../rust/api/file_manager.dart';
import '../services/highlight_service.dart';
import '../services/markdown_pdf_service.dart';
import '../services/preferences_service.dart';
import '../theme/app_ui_tokens.dart';
import '../theme/markdown_themes.dart';
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
  final List<int> _matchIndices = [];
  int _currentMatchIndex = 0;
  int _cursorLine = 1;
  int _cursorCol = 1;

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
    if (_currentMatchIndex >= _matchIndices.length) {
      _currentMatchIndex = _matchIndices.isEmpty ? 0 : _matchIndices.length - 1;
    }
    _selectCurrentMatch();
    setState(() {});
  }

  void _nextMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _matchIndices.length;
    });
    _selectCurrentMatch();
  }

  void _prevMatch() {
    if (_matchIndices.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _matchIndices.length) % _matchIndices.length;
    });
    _selectCurrentMatch();
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
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => _showFind = true);
          _findFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _showFind = true);
          _findFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          if (widget.readOnly) return;
          setState(() {
            _showFind = true;
            _showReplace = true;
          });
          _findFocusNode.requestFocus();
        },
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
            setState(() => _showFind = false);
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
          canPop: !_isDirty,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
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
                    setState(() => _showFind = !_showFind);
                    if (_showFind) {
                      _findFocusNode.requestFocus();
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
                else if (_mode != TextFileMode.edit)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                    onPressed: () => _setMode(TextFileMode.edit),
                  ),
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
            onPressed: () => setState(() => _showFind = false),
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

    return Container(
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
        ],
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
        return HtmlWidget(
          _controller.text,
          textStyle: TextStyle(fontSize: _fontSize + 2),
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
            undoController: _undoController,
            maxLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
            onChanged: (_) {
              if (!_isDirty) setState(() => _isDirty = true);
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
    );
    final background = HighlightService.instance.backgroundFor(brightness);

    Widget textWidget = SelectableText.rich(
      TextSpan(
        style: TextStyle(fontFamily: 'monospace', fontSize: _fontSize),
        children: span != null ? [span] : [TextSpan(text: _controller.text)],
      ),
    );

    if (!_wordWrap) {
      textWidget = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: textWidget,
      );
    }

    return Container(
      color: background,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(16),
        child: textWidget,
      ),
    );
  }
}

class SyntaxHighlightingEditingController extends TextEditingController {
  final String fileName;
  final Brightness Function() brightnessProvider;
  final double Function()? fontSizeProvider;

  SyntaxHighlightingEditingController({
    super.text,
    required this.fileName,
    required this.brightnessProvider,
    this.fontSizeProvider,
  });

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = HighlightService.instance.spanFor(
      text,
      fileName,
      brightnessProvider(),
    );
    final size = fontSizeProvider?.call() ?? 13.0;
    final baseStyle = (style ?? const TextStyle()).copyWith(
      fontFamily: 'monospace',
      fontSize: size,
    );
    if (span != null) {
      return TextSpan(
        style: baseStyle,
        children: [span],
      );
    }
    return super.buildTextSpan(
      context: context,
      style: baseStyle,
      withComposing: withComposing,
    );
  }
}

