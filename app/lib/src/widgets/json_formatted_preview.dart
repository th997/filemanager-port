import 'dart:convert';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Result of parsing and formatting a JSON string.
class JsonFormatResult {
  final bool isValid;
  final dynamic parsed;
  final String formatted;
  final String minified;
  final String? errorMessage;

  const JsonFormatResult({
    required this.isValid,
    this.parsed,
    this.formatted = '',
    this.minified = '',
    this.errorMessage,
  });
}

/// Pure-Dart JSON pretty-printer, minifier, key sorter, and O(n) single-line
/// syntax highlighter safe for arbitrarily large JSON documents.
class JsonFormatter {
  static dynamic sortObjectKeys(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      final sorted = <String, dynamic>{};
      for (final key in keys) {
        sorted[key] = sortObjectKeys(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(sortObjectKeys).toList();
    }
    return value;
  }

  static JsonFormatResult format(
    String raw, {
    int indentSpaces = 2,
    bool sortKeys = false,
  }) {
    try {
      final decoded = jsonDecode(raw);
      return formatParsed(
        decoded,
        indentSpaces: indentSpaces,
        sortKeys: sortKeys,
      );
    } catch (e) {
      return JsonFormatResult(
        isValid: false,
        errorMessage: '$e',
      );
    }
  }

  static JsonFormatResult formatParsed(
    dynamic decoded, {
    int indentSpaces = 2,
    bool sortKeys = false,
  }) {
    try {
      final normalized = sortKeys ? sortObjectKeys(decoded) : decoded;
      final indent = ' ' * indentSpaces.clamp(1, 8);
      final formatted = JsonEncoder.withIndent(indent).convert(normalized);
      final minified = jsonEncode(normalized);
      return JsonFormatResult(
        isValid: true,
        parsed: normalized,
        formatted: formatted,
        minified: minified,
      );
    } catch (e) {
      return JsonFormatResult(
        isValid: false,
        errorMessage: '$e',
      );
    }
  }

  /// Linear-time syntax highlighter for one line of formatted JSON.
  /// Supports optional case-insensitive search match highlighting.
  static TextSpan highlightLine(
    String line, {
    required Brightness brightness,
    double fontSize = 13.0,
    String query = '',
    bool isActiveMatchLine = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final keyColor = isDark ? const Color(0xFF9CDCFE) : const Color(0xFF005CC5);
    final stringColor = isDark ? const Color(0xFF98C379) : const Color(0xFF098658);
    final numberColor = isDark ? const Color(0xFFD19A66) : const Color(0xFFB45309);
    final literalColor = isDark ? const Color(0xFF56B6C2) : const Color(0xFFD73A49);
    final punctColor = isDark ? const Color(0xFFABB2BF) : const Color(0xFF586069);
    final defaultColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF24292E);

    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.45,
      color: defaultColor,
    );

    final lowerQuery = query.trim().toLowerCase();
    final spans = <InlineSpan>[];

    void addToken(String text, Color color, {FontWeight? weight}) {
      final style = baseStyle.copyWith(color: color, fontWeight: weight);
      if (lowerQuery.isEmpty) {
        spans.add(TextSpan(text: text, style: style));
        return;
      }
      final lowerText = text.toLowerCase();
      int cursor = 0;
      while (cursor < text.length) {
        final idx = lowerText.indexOf(lowerQuery, cursor);
        if (idx < 0) {
          spans.add(TextSpan(text: text.substring(cursor), style: style));
          break;
        }
        if (idx > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, idx), style: style));
        }
        spans.add(
          TextSpan(
            text: text.substring(idx, idx + lowerQuery.length),
            style: style.copyWith(
              backgroundColor: isActiveMatchLine
                  ? Colors.orange.withValues(alpha: isDark ? 0.55 : 0.45)
                  : Colors.amber.withValues(alpha: isDark ? 0.35 : 0.35),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        cursor = idx + lowerQuery.length;
      }
    }

    int i = 0;
    final len = line.length;
    while (i < len) {
      final ch = line.codeUnitAt(i);

      // Whitespace
      if (ch == 32 || ch == 9) {
        final start = i;
        while (i < len && (line.codeUnitAt(i) == 32 || line.codeUnitAt(i) == 9)) {
          i++;
        }
        spans.add(TextSpan(text: line.substring(start, i), style: baseStyle));
        continue;
      }

      // Quoted string (key or value)
      if (ch == 34) {
        final start = i;
        i++;
        while (i < len) {
          final c = line.codeUnitAt(i);
          if (c == 92 && i + 1 < len) {
            i += 2;
            continue;
          }
          i++;
          if (c == 34) break;
        }
        final token = line.substring(start, i);
        // Peek ahead past spaces to see if followed by ':' -> object key.
        int peek = i;
        while (peek < len && (line.codeUnitAt(peek) == 32 || line.codeUnitAt(peek) == 9)) {
          peek++;
        }
        final isKey = peek < len && line.codeUnitAt(peek) == 58;
        addToken(
          token,
          isKey ? keyColor : stringColor,
          weight: isKey ? FontWeight.w600 : null,
        );
        continue;
      }

      // Punctuation: { } [ ] : ,
      if (ch == 123 || ch == 125 || ch == 91 || ch == 93 || ch == 58 || ch == 44) {
        addToken(line[i], punctColor);
        i++;
        continue;
      }

      // Number: - or 0..9
      if (ch == 45 || (ch >= 48 && ch <= 57)) {
        final start = i;
        i++;
        while (i < len) {
          final c = line.codeUnitAt(i);
          final isNumChar = (c >= 48 && c <= 57) ||
              c == 46 || // .
              c == 101 || // e
              c == 69 || // E
              c == 43 || // +
              c == 45; // -
          if (!isNumChar) break;
          i++;
        }
        addToken(line.substring(start, i), numberColor);
        continue;
      }

      // Literals: true / false / null
      if (line.startsWith('true', i)) {
        addToken('true', literalColor, weight: FontWeight.w600);
        i += 4;
        continue;
      }
      if (line.startsWith('false', i)) {
        addToken('false', literalColor, weight: FontWeight.w600);
        i += 5;
        continue;
      }
      if (line.startsWith('null', i)) {
        addToken('null', literalColor, weight: FontWeight.w600);
        i += 4;
        continue;
      }

      // Fallback character
      addToken(line[i], defaultColor);
      i++;
    }

    return TextSpan(style: baseStyle, children: spans);
  }
}

/// Interactive formatted JSON preview widget with syntax highlighting,
/// line numbers, 2/4-space indent switching, key sorting, word-wrap toggle,
/// match navigation, and one-tap formatted/minified copy.
class JsonFormattedPreviewWidget extends StatefulWidget {
  final String rawText;
  final dynamic preParsed;
  final String filterQuery;
  final double fontSize;
  final VoidCallback? onOpenRawEditor;

  const JsonFormattedPreviewWidget({
    super.key,
    required this.rawText,
    this.preParsed,
    this.filterQuery = '',
    this.fontSize = 13.0,
    this.onOpenRawEditor,
  });

  @override
  State<JsonFormattedPreviewWidget> createState() =>
      _JsonFormattedPreviewWidgetState();
}

class _JsonFormattedPreviewWidgetState extends State<JsonFormattedPreviewWidget> {
  int _indentSpaces = 2;
  bool _sortKeys = false;
  bool _wordWrap = true;
  late JsonFormatResult _result;
  List<String> _lines = const [];
  List<int> _matchLineIndices = const [];
  int _activeMatchCursor = 0;

  final ScrollController _verticalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant JsonFormattedPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawText != widget.rawText ||
        !identical(oldWidget.preParsed, widget.preParsed)) {
      _recompute();
    } else if (oldWidget.filterQuery != widget.filterQuery) {
      _recomputeMatches();
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  void _recompute() {
    if (widget.preParsed != null) {
      _result = JsonFormatter.formatParsed(
        widget.preParsed,
        indentSpaces: _indentSpaces,
        sortKeys: _sortKeys,
      );
    } else {
      _result = JsonFormatter.format(
        widget.rawText,
        indentSpaces: _indentSpaces,
        sortKeys: _sortKeys,
      );
    }
    _lines = _result.isValid ? _result.formatted.split('\n') : const [];
    _recomputeMatches();
  }

  void _recomputeMatches() {
    final q = widget.filterQuery.trim().toLowerCase();
    if (q.isEmpty || !_result.isValid) {
      _matchLineIndices = const [];
      _activeMatchCursor = 0;
      return;
    }
    final hits = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      if (_lines[i].toLowerCase().contains(q)) {
        hits.add(i);
      }
    }
    _matchLineIndices = hits;
    _activeMatchCursor = 0;
  }

  void _jumpToMatch(int delta) {
    if (_matchLineIndices.isEmpty) return;
    setState(() {
      _activeMatchCursor =
          (_activeMatchCursor + delta) % _matchLineIndices.length;
      if (_activeMatchCursor < 0) {
        _activeMatchCursor += _matchLineIndices.length;
      }
    });
    final targetLine = _matchLineIndices[_activeMatchCursor];
    if (_verticalController.hasClients) {
      final estimatedRowHeight = widget.fontSize * 1.45 + 4.0;
      final offset = (targetLine * estimatedRowHeight)
          .clamp(0.0, _verticalController.position.maxScrollExtent);
      _verticalController.animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _copy(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brightness = theme.brightness;

    if (!_result.isValid) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                l10n.jsonInvalidFormat,
                style: theme.textTheme.titleMedium?.copyWith(color: scheme.error),
              ),
              if (_result.errorMessage != null) ...[
                const SizedBox(height: 8),
                SelectableText(
                  _result.errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (widget.onOpenRawEditor != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.code, size: 18),
                  label: Text(l10n.rawTextView),
                  onPressed: widget.onOpenRawEditor,
                ),
              ],
            ],
          ),
        ),
      );
    }

    final gutterDigits = _lines.length.toString().length.clamp(2, 6);
    final gutterWidth = gutterDigits * (widget.fontSize * 0.65) + 18.0;
    final activeLineIdx = _matchLineIndices.isNotEmpty
        ? _matchLineIndices[_activeMatchCursor]
        : -1;
    final codeBg = brightness == Brightness.dark
        ? const Color(0xFF1E222A)
        : const Color(0xFFFAFAFC);

    return Column(
      children: [
        // Formatting control toolbar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 2 / 4 space indent toggle
              ActionChip(
                avatar: const Icon(Icons.format_indent_increase, size: 16),
                label: Text(l10n.jsonIndentSpaces(_indentSpaces)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _indentSpaces = _indentSpaces == 2 ? 4 : 2;
                    _recompute();
                  });
                },
              ),
              // Sort keys toggle
              FilterChip(
                label: Text(l10n.jsonSortKeys),
                selected: _sortKeys,
                visualDensity: VisualDensity.compact,
                onSelected: (v) {
                  setState(() {
                    _sortKeys = v;
                    _recompute();
                  });
                },
              ),
              // Word wrap toggle
              FilterChip(
                avatar: const Icon(Icons.wrap_text, size: 16),
                label: Text(l10n.wordWrap),
                selected: _wordWrap,
                visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() => _wordWrap = v),
              ),
              // Copy formatted
              IconButton(
                icon: const Icon(Icons.copy_all, size: 18),
                tooltip: l10n.jsonCopyFormatted,
                visualDensity: VisualDensity.compact,
                onPressed: () => _copy(_result.formatted, l10n.jsonCopiedFormatted),
              ),
              // Copy minified
              IconButton(
                icon: const Icon(Icons.compress, size: 18),
                tooltip: l10n.jsonCopyMinified,
                visualDensity: VisualDensity.compact,
                onPressed: () => _copy(_result.minified, l10n.jsonCopiedMinified),
              ),
              // Line count badge
              Text(
                l10n.jsonLinesCount(_lines.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              // Match counter & jump buttons when searching
              if (_matchLineIndices.isNotEmpty) ...[
                Text(
                  l10n.jsonMatchesCount(
                    _activeMatchCursor + 1,
                    _matchLineIndices.length,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _jumpToMatch(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _jumpToMatch(1),
                ),
              ],
            ],
          ),
        ),
        // Highlighted formatted lines
        Expanded(
          child: Container(
            color: codeBg,
            child: SelectionArea(
              child: Scrollbar(
                controller: _verticalController,
                child: ListView.builder(
                  controller: _verticalController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    final line = _lines[index];
                    final isActive = index == activeLineIdx;
                    final span = JsonFormatter.highlightLine(
                      line,
                      brightness: brightness,
                      fontSize: widget.fontSize,
                      query: widget.filterQuery,
                      isActiveMatchLine: isActive,
                    );
                    final codeWidget = Text.rich(
                      span,
                      softWrap: _wordWrap,
                    );
                    return Container(
                      color: isActive
                          ? scheme.primaryContainer.withValues(alpha: 0.22)
                          : null,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1.5,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: gutterWidth,
                            child: SelectionContainer.disabled(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Text(
                                  '${index + 1}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: widget.fontSize - 1,
                                    height: 1.45,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _wordWrap
                                ? codeWidget
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: codeWidget,
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
