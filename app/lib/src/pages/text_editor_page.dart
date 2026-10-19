import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../rust/api/file_manager.dart';
import '../services/highlight_service.dart';

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
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _isDirty = false;
  String? _error;
  late TextFileMode _mode;

  String get _lowerName => widget.fileName.toLowerCase();
  bool get _isMarkdown => _lowerName.endsWith('.md') || _lowerName.endsWith('.markdown');
  bool get _isHtml => _lowerName.endsWith('.html') || _lowerName.endsWith('.htm') || _lowerName.endsWith('.xhtml');

  @override
  void initState() {
    super.initState();
    _mode = (_isMarkdown || _isHtml) ? TextFileMode.preview : TextFileMode.code;
    _loadFile();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    setState(() => _saving = true);
    try {
      await writeTextFile(
        root: widget.root,
        path: widget.path,
        content: _controller.text,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _isDirty = false;
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

  void _setMode(TextFileMode mode) {
    if (mode == TextFileMode.preview && !_isMarkdown && !_isHtml) return;
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _isMarkdown || _isHtml;

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved Changes'),
            content: const Text('You have unsaved changes. Discard them?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
          actions: [
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
                tooltip: 'Save',
                onPressed: _isDirty ? _save : null,
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
                : _buildContent(),
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
        return TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(16),
          ),
          onChanged: (_) {
            if (!_isDirty) setState(() => _isDirty = true);
          },
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

    return Container(
      color: background,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: const EdgeInsets.all(16),
        child: SelectableText.rich(
          span ?? TextSpan(
            text: _controller.text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      ),
    );
  }
}
