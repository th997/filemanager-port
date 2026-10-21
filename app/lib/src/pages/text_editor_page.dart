import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../rust/api/file_manager.dart';
import '../services/highlight_service.dart';
import '../services/preferences_service.dart';

enum TextFileMode { preview, code, edit }

/// Text file viewer and editor.
///
/// Markdown and HTML open in a rendered preview; source is one tap away in the
/// highlighted code view. Every other text file starts in the code view.
class TextEditorPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;

  const TextEditorPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
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
  double _fontSize = 13.0;
  bool _wordWrap = true;
  bool _showFind = false;
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
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
    _mode = (_isMarkdown || _isHtml) ? TextFileMode.preview : TextFileMode.code;
    _loadFile();
  }

  @override
  void dispose() {
    _controller.removeListener(_updateCursorPosition);
    _controller.dispose();
    _findController.dispose();
    _findFocusNode.dispose();
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
    if (targetLine == null || targetLine < 1) return;

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
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
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

  void _setMode(TextFileMode mode) {
    if (mode == TextFileMode.preview && !_isMarkdown && !_isHtml) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _isMarkdown || _isHtml;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_isDirty && _error == null) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (_isDirty && _error == null) _save();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() => _showFind = true);
          _findFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          setState(() => _showFind = true);
          _findFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): _showGoToLineDialog,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): _showGoToLineDialog,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_showFind) {
            setState(() => _showFind = false);
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
                if (_mode != TextFileMode.edit)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                    onPressed: () => _setMode(TextFileMode.edit),
                  ),
                if (_mode != TextFileMode.preview)
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
                      }
                    },
                    itemBuilder: (ctx) => [
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
                            Text('Larger (${_fontSize.toInt() + 1}pt)'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'zoom_out',
                        child: Row(
                          children: [
                            const Icon(Icons.zoom_out, size: 20),
                            const SizedBox(width: 8),
                            Text('Smaller (${_fontSize.toInt() - 1}pt)'),
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
                          if (_showFind) _buildFindBar(),
                          Expanded(child: _buildContent()),
                          _buildStatusBar(),
                        ],
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
      child: Row(
        children: [
          const Icon(Icons.search, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _findController,
              focusNode: _findFocusNode,
              decoration: const InputDecoration(
                hintText: 'Find in file...',
                isDense: true,
                border: InputBorder.none,
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
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Close find (Esc)',
            onPressed: () => setState(() => _showFind = false),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final text = _controller.text;
    final lines = text.isEmpty ? 1 : text.split('\n').length;
    final chars = text.length;
    final modeLabel = _mode == TextFileMode.preview
        ? 'Preview'
        : (_mode == TextFileMode.code ? 'Read-only' : 'Editing');

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
            'Ln $_cursorLine, Col $_cursorCol  •  Lines: $lines  •  Chars: $chars  •  ${_fontSize.toInt()}pt${_wordWrap ? '  •  Wrap' : ''}',
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
          return Markdown(
            data: _controller.text,
            padding: const EdgeInsets.all(16),
            selectable: true,
          );
        }
        return HtmlWidget(
          _controller.text,
          textStyle: const TextStyle(fontSize: 15),
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

