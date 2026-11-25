import 'dart:convert';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rust/api/file_manager.dart';
import '../services/path_utils.dart';
import '../services/semantic_colors.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/json_formatted_preview.dart';
import 'text_editor_page.dart';

/// Pure-Dart RFC 4180 CSV / TSV parser.
class CsvParser {
  static List<List<String>> parse(String input, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else {
        if (ch == '"' && field.isEmpty) {
          inQuotes = true;
        } else if (ch == delimiter) {
          row.add(field.toString());
          field.clear();
        } else if (ch == '\r') {
          if (i + 1 < input.length && input[i + 1] == '\n') i++;
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = <String>[];
        } else if (ch == '\n') {
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = <String>[];
        } else {
          field.write(ch);
        }
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

/// Lightweight XML DOM node for interactive tree preview.
class XmlTreeNode {
  final String tag;
  final Map<String, String> attributes;
  final String text;
  final List<XmlTreeNode> children;

  const XmlTreeNode({
    required this.tag,
    this.attributes = const {},
    this.text = '',
    this.children = const [],
  });

  static List<XmlTreeNode> parse(String xml) {
    final cleaned = xml
        .replaceAll(RegExp(r'<\?[\s\S]*?\?>'), '')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
        .replaceAll(RegExp(r'<!DOCTYPE[^>]*>', caseSensitive: false), '');
    final tokenRe = RegExp(r'<(\/?)([\w:.-]+)([^>]*?)(\/?)>|([^<]+)');
    final roots = <XmlTreeNode>[];
    final stack = <_XmlBuilder>[];

    for (final m in tokenRe.allMatches(cleaned)) {
      final textToken = m.group(5);
      if (textToken != null) {
        final trimmed = textToken.trim();
        if (trimmed.isNotEmpty && stack.isNotEmpty) {
          stack.last.text.write(trimmed);
        }
        continue;
      }
      final isClosing = m.group(1) == '/';
      final tag = m.group(2) ?? '';
      final attrRaw = m.group(3) ?? '';
      final selfClosing = m.group(4) == '/';

      if (isClosing) {
        if (stack.isNotEmpty) {
          final done = stack.removeLast().build();
          if (stack.isEmpty) {
            roots.add(done);
          } else {
            stack.last.children.add(done);
          }
        }
      } else {
        final attrs = <String, String>{};
        for (final am in RegExp(r'([\w:.-]+)\s*=\s*"([^"]*)"').allMatches(attrRaw)) {
          attrs[am.group(1)!] = am.group(2)!;
        }
        final builder = _XmlBuilder(tag, attrs);
        if (selfClosing) {
          final done = builder.build();
          if (stack.isEmpty) {
            roots.add(done);
          } else {
            stack.last.children.add(done);
          }
        } else {
          stack.add(builder);
        }
      }
    }
    while (stack.isNotEmpty) {
      final done = stack.removeLast().build();
      if (stack.isEmpty) {
        roots.add(done);
      } else {
        stack.last.children.add(done);
      }
    }
    return roots;
  }
}

class _XmlBuilder {
  final String tag;
  final Map<String, String> attributes;
  final StringBuffer text = StringBuffer();
  final List<XmlTreeNode> children = [];
  _XmlBuilder(this.tag, this.attributes);
  XmlTreeNode build() => XmlTreeNode(
        tag: tag,
        attributes: attributes,
        text: text.toString().trim(),
        children: children,
      );
}

/// View mode for JSON files in [StructuredViewerPage].
enum JsonPreviewMode { formatted, tree }

/// Interactive viewer for CSV / TSV (sortable table), JSON (formatted preview
/// & collapsible tree with JSONPath copy), and XML (collapsible tree with XPath copy).
class StructuredViewerPage extends StatefulWidget {
  final String root;
  final String path;
  final String fileName;
  final bool readOnly;
  final String? initialContent;
  final JsonPreviewMode initialJsonMode;

  const StructuredViewerPage({
    super.key,
    required this.root,
    required this.path,
    required this.fileName,
    this.readOnly = false,
    this.initialContent,
    this.initialJsonMode = JsonPreviewMode.formatted,
  });

  static bool supports(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.csv') ||
        lower.endsWith('.tsv') ||
        lower.endsWith('.json') ||
        lower.endsWith('.geojson') ||
        lower.endsWith('.topojson') ||
        lower.endsWith('.xml');
  }

  @override
  State<StructuredViewerPage> createState() => _StructuredViewerPageState();
}

class _StructuredViewerPageState extends State<StructuredViewerPage> {
  bool _loading = true;
  String? _error;
  String _rawText = '';
  String _filter = '';

  // CSV state
  List<String> _headers = const [];
  List<List<String>> _rows = const [];
  int? _sortColumn;
  bool _sortAsc = true;

  // JSON / XML state
  dynamic _jsonData;
  late JsonPreviewMode _jsonMode;
  List<XmlTreeNode> _xmlRoots = const [];
  final Set<String> _expandedPaths = {r'$'};

  String get _ext {
    final dot = widget.fileName.lastIndexOf('.');
    return dot < 0 ? '' : widget.fileName.substring(dot + 1).toLowerCase();
  }

  bool get _isJson =>
      _ext == 'json' || _ext == 'geojson' || _ext == 'topojson';

  @override
  void initState() {
    super.initState();
    _jsonMode = widget.initialJsonMode;
    VaultService.instance.addListener(_onVaultChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant StructuredViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.root != oldWidget.root ||
        widget.path != oldWidget.path ||
        widget.fileName != oldWidget.fileName ||
        widget.initialContent != oldWidget.initialContent) {
      _filter = '';
      _jsonMode = widget.initialJsonMode;
      _expandedPaths
        ..clear()
        ..add(r'$');
      _load();
    }
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    final vid = vaultIdFromRoot(widget.root);
    if (vid != null && !VaultService.instance.isUnlocked(vid) && mounted) {
      setState(() {
        _rawText = '';
        _headers = const [];
        _rows = const [];
        _jsonData = null;
        _xmlRoots = const [];
        _expandedPaths.clear();
      });
      final route = ModalRoute.of(context);
      if (route != null && route.isActive && !route.isFirst) {
        Navigator.of(context).removeRoute(route);
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  void _collectAllJsonPaths(String path, dynamic value, Set<String> out) {
    if (value is Map) {
      out.add(path);
      for (final entry in value.entries) {
        final k = '${entry.key}';
        final childPath =
            RegExp(r'^[a-zA-Z_]\w*$').hasMatch(k) ? '$path.$k' : '$path["$k"]';
        _collectAllJsonPaths(childPath, entry.value, out);
      }
    } else if (value is List) {
      out.add(path);
      for (int i = 0; i < value.length; i++) {
        _collectAllJsonPaths('$path[$i]', value[i], out);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = widget.initialContent ??
          await readTextFile(root: widget.root, path: widget.path);
      if (!mounted) return;
      _rawText = text;
      if (_ext == 'csv' || _ext == 'tsv') {
        final parsed = CsvParser.parse(text, delimiter: _ext == 'tsv' ? '\t' : ',');
        if (parsed.isNotEmpty) {
          _headers = parsed.first;
          _rows = parsed.skip(1).toList();
        }
      } else if (_isJson) {
        _jsonData = jsonDecode(text);
      } else if (_ext == 'xml') {
        _xmlRoots = XmlTreeNode.parse(text);
        _expandedPaths
          ..clear()
          ..addAll(_xmlRoots.map((r) => '/${r.tag}'));
      }
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _copyText(String text, {String? label}) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label ?? text),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _openRawEditor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(
          root: widget.root,
          path: widget.path,
          fileName: widget.fileName,
          readOnly: widget.readOnly,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          if (_isJson && !_loading && _error == null && _jsonMode == JsonPreviewMode.tree) ...[
            IconButton(
              icon: const Icon(Icons.unfold_more, size: 20),
              tooltip: l10n.jsonExpandAll,
              onPressed: () {
                setState(() {
                  _collectAllJsonPaths(r'$', _jsonData, _expandedPaths);
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.unfold_less, size: 20),
              tooltip: l10n.jsonCollapseAll,
              onPressed: () {
                setState(() {
                  _expandedPaths
                    ..clear()
                    ..add(r'$');
                });
              },
            ),
          ],
          TextButton.icon(
            icon: const Icon(Icons.code, size: 18),
            label: Text(l10n.rawTextView),
            onPressed: _openRawEditor,
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
                        Icon(
                          Icons.error_outline,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isJson ? l10n.jsonInvalidFormat : _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isJson) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          icon: const Icon(Icons.code, size: 18),
                          onPressed: _openRawEditor,
                          label: Text(l10n.rawTextView),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final searchField = TextField(
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: l10n.searchFiles,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (v) =>
                                setState(() => _filter = v.trim().toLowerCase()),
                          );
                          if (!_isJson) return searchField;

                          final switcher = SegmentedButton<JsonPreviewMode>(
                            segments: [
                              ButtonSegment(
                                value: JsonPreviewMode.formatted,
                                icon: const Icon(Icons.data_object, size: 16),
                                label: Text(l10n.jsonFormattedPreview),
                              ),
                              ButtonSegment(
                                value: JsonPreviewMode.tree,
                                icon: const Icon(Icons.account_tree_outlined, size: 16),
                                label: Text(l10n.jsonTreeView),
                              ),
                            ],
                            selected: {_jsonMode},
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onSelectionChanged: (sel) {
                              if (sel.isNotEmpty) {
                                setState(() => _jsonMode = sel.first);
                              }
                            },
                          );

                          if (constraints.maxWidth < 520) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                switcher,
                                const SizedBox(height: 8),
                                searchField,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              switcher,
                              const SizedBox(width: 8),
                              Expanded(child: searchField),
                            ],
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: _ext == 'csv' || _ext == 'tsv'
                          ? _buildCsvView()
                          : _isJson
                              ? (_jsonMode == JsonPreviewMode.formatted
                                  ? JsonFormattedPreviewWidget(
                                      rawText: _rawText,
                                      preParsed: _jsonData,
                                      filterQuery: _filter,
                                      onOpenRawEditor: _openRawEditor,
                                    )
                                  : _buildJsonView())
                              : _buildXmlView(),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _buildCsvView() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (_headers.isEmpty) {
      return Center(
        child: Text(_rawText.isEmpty ? l10n.structuredEmptyValue : _rawText),
      );
    }
    var visible = _rows.where((row) {
      if (_filter.isEmpty) return true;
      return row.any((cell) => cell.toLowerCase().contains(_filter));
    }).toList();

    if (_sortColumn != null && _sortColumn! < _headers.length) {
      final col = _sortColumn!;
      visible.sort((a, b) {
        final va = col < a.length ? a[col] : '';
        final vb = col < b.length ? b[col] : '';
        final na = double.tryParse(va);
        final nb = double.tryParse(vb);
        final cmp = (na != null && nb != null) ? na.compareTo(nb) : va.compareTo(vb);
        return _sortAsc ? cmp : -cmp;
      });
    }

    final displayRows = visible.take(1000).toList();
    final table = Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: _sortColumn,
            sortAscending: _sortAsc,
            columns: [
              for (int i = 0; i < _headers.length; i++)
                DataColumn(
                  label: Text(_headers[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                  onSort: (colIdx, asc) {
                    setState(() {
                      _sortColumn = colIdx;
                      _sortAsc = asc;
                    });
                  },
                ),
            ],
            rows: [
              for (final row in displayRows)
                DataRow(
                  cells: [
                    for (int i = 0; i < _headers.length; i++)
                      DataCell(
                        Text(i < row.length ? row[i] : ''),
                        onTap: () => _copyText(i < row.length ? row[i] : ''),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (visible.length <= displayRows.length) return table;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: scheme.warning.withValues(alpha: 0.14),
          child: Text(
            l10n.structuredCsvTruncated(displayRows.length, visible.length),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Expanded(child: table),
      ],
    );
  }

  Widget _buildJsonView() {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: _buildJsonNodes(r'$', null, _jsonData, 0),
    );
  }

  bool _jsonNodeMatches(String path, String? keyLabel, dynamic value) {
    if (_filter.isEmpty) return true;
    if ((keyLabel?.toLowerCase().contains(_filter) ?? false) ||
        path.toLowerCase().contains(_filter)) {
      return true;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        final k = '${entry.key}';
        final childPath =
            RegExp(r'^[a-zA-Z_]\w*$').hasMatch(k) ? '$path.$k' : '$path["$k"]';
        if (_jsonNodeMatches(childPath, k, entry.value)) return true;
      }
      return false;
    }
    if (value is List) {
      for (int i = 0; i < value.length; i++) {
        if (_jsonNodeMatches('$path[$i]', '[$i]', value[i])) return true;
      }
      return false;
    }
    final valStr = value == null ? 'null' : '$value';
    return valStr.toLowerCase().contains(_filter);
  }

  List<Widget> _buildJsonNodes(String path, String? keyLabel, dynamic value, int depth) {
    if (!_jsonNodeMatches(path, keyLabel, value)) {
      return const [];
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMap = value is Map;
    final isList = value is List;
    final isContainer = isMap || isList;

    if (!isContainer) {
      final valStr = value == null ? 'null' : '$value';
      final Color valueColor;
      if (value is num) {
        valueColor = isDark ? Colors.lightBlue.shade300 : Colors.blue.shade700;
      } else if (value is bool) {
        valueColor = isDark ? Colors.purple.shade200 : Colors.purple.shade700;
      } else if (value == null) {
        valueColor = scheme.onSurfaceVariant;
      } else {
        valueColor = isDark ? Colors.lightGreen.shade300 : Colors.green.shade700;
      }
      return [
        InkWell(
          onTap: () => _copyText(path, label: '${l10n.copyJsonPath}: $path'),
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4, right: 8),
            child: Row(
              children: [
                if (keyLabel != null) ...[
                  Text(
                    '$keyLabel: ',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12.5),
                  ),
                ],
                Expanded(
                  child: Text(
                    value is String ? '"$valStr"' : valStr,
                    style: TextStyle(color: valueColor, fontFamily: 'monospace', fontSize: 12.5),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14),
                  tooltip: l10n.copyJsonPath,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyText(path, label: '${l10n.copyJsonPath}: $path'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final count = isMap ? value.length : (value as List).length;
    final expanded = _expandedPaths.contains(path) || _filter.isNotEmpty;
    final header = InkWell(
      onTap: () {
        setState(() {
          if (_expandedPaths.contains(path)) {
            _expandedPaths.remove(path);
          } else {
            _expandedPaths.add(path);
          }
        });
      },
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4, right: 8),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 16,
              color: scheme.primary,
            ),
            const SizedBox(width: 4),
            if (keyLabel != null)
              Text(
                '$keyLabel ',
                style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace', fontSize: 12.5),
              ),
            Text(
              isMap ? '{ $count }' : '[ $count ]',
              style: TextStyle(color: scheme.onSurfaceVariant, fontFamily: 'monospace', fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy, size: 14),
              tooltip: l10n.copyJsonPath,
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyText(path, label: '${l10n.copyJsonPath}: $path'),
            ),
          ],
        ),
      ),
    );

    if (!expanded) return [header];

    final children = <Widget>[header];
    if (isMap) {
      for (final entry in value.entries) {
        final k = '${entry.key}';
        final childPath = RegExp(r'^[a-zA-Z_]\w*$').hasMatch(k) ? '$path.$k' : '$path["$k"]';
        children.addAll(_buildJsonNodes(childPath, k, entry.value, depth + 1));
      }
    } else if (isList) {
      for (int i = 0; i < value.length; i++) {
        children.addAll(_buildJsonNodes('$path[$i]', '[$i]', value[i], depth + 1));
      }
    }
    return children;
  }

  Widget _buildXmlView() {
    final l10n = AppLocalizations.of(context);
    if (_xmlRoots.isEmpty) {
      return Center(
        child: Text(_rawText.isEmpty ? l10n.structuredEmptyValue : _rawText),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (int i = 0; i < _xmlRoots.length; i++)
          ..._buildXmlNodes('/${_xmlRoots[i].tag}', _xmlRoots[i], 0),
      ],
    );
  }

  bool _xmlNodeMatches(String xpath, XmlTreeNode node) {
    if (_filter.isEmpty) return true;
    final attrStr =
        node.attributes.entries.map((e) => '${e.key}="${e.value}"').join(' ');
    if (node.tag.toLowerCase().contains(_filter) ||
        node.text.toLowerCase().contains(_filter) ||
        attrStr.toLowerCase().contains(_filter) ||
        xpath.toLowerCase().contains(_filter)) {
      return true;
    }
    for (int i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      if (_xmlNodeMatches('$xpath/${child.tag}[${i + 1}]', child)) return true;
    }
    return false;
  }

  List<Widget> _buildXmlNodes(String xpath, XmlTreeNode node, int depth) {
    if (!_xmlNodeMatches(xpath, node)) {
      return const [];
    }
    final l10n = AppLocalizations.of(context);
    final expanded = _expandedPaths.contains(xpath) || _filter.isNotEmpty;
    final hasChildren = node.children.isNotEmpty;
    final attrSummary = node.attributes.entries.map((e) => '${e.key}="${e.value}"').join(' ');

    final row = InkWell(
      onTap: hasChildren
          ? () {
              setState(() {
                if (_expandedPaths.contains(xpath)) {
                  _expandedPaths.remove(xpath);
                } else {
                  _expandedPaths.add(xpath);
                }
              });
            }
          : () => _copyText(xpath, label: '${l10n.copyXPath}: $xpath'),
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4, right: 8),
        child: Row(
          children: [
            if (hasChildren)
              Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 16)
            else
              const SizedBox(width: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                  children: [
                    TextSpan(
                      text: '<${node.tag}>',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                    ),
                    if (attrSummary.isNotEmpty)
                      TextSpan(
                        text: ' $attrSummary',
                        style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                      ),
                    if (node.text.isNotEmpty)
                      TextSpan(text: '  ${node.text}'),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 14),
              tooltip: l10n.copyXPath,
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyText(xpath, label: '${l10n.copyXPath}: $xpath'),
            ),
          ],
        ),
      ),
    );

    if (!hasChildren || !expanded) return [row];
    final out = <Widget>[row];
    for (int i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      out.addAll(_buildXmlNodes('$xpath/${child.tag}[${i + 1}]', child, depth + 1));
    }
    return out;
  }
}
