import 'package:flutter/material.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/properties.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/github.dart';

/// Maps file extensions to highlight.js language names and renders source as
/// styled spans.
class HighlightService {
  static final HighlightService instance = HighlightService._();

  final Highlight _highlight = Highlight();
  Highlight get highlight => _highlight;
  final Map<String, String> _extensions = const {
    'html': 'xml',
    'htm': 'xml',
    'xhtml': 'xml',
    'xml': 'xml',
    'svg': 'xml',
    'plist': 'xml',
    'md': 'markdown',
    'markdown': 'markdown',
    'dart': 'dart',
    'rs': 'rust',
    'json': 'json',
    'jsonc': 'json',
    'json5': 'json',
    'geojson': 'json',
    'topojson': 'json',
    'map': 'json',
    'lock': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'css': 'css',
    'js': 'javascript',
    'mjs': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'jsx': 'javascript',
    'py': 'python',
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'bash',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'hpp': 'cpp',
    'java': 'java',
    'kt': 'kotlin',
    'go': 'go',
    'swift': 'swift',
    'sql': 'sql',
    'ini': 'ini',
    'cfg': 'ini',
    'toml': 'ini',
    'properties': 'properties',
    'diff': 'diff',
    'patch': 'diff',
    'dockerfile': 'dockerfile',
    'txt': 'plaintext',
    'log': 'plaintext',
  };

  HighlightService._() {
    _highlight.registerLanguages({
      'xml': langXml,
      'markdown': langMarkdown,
      'dart': langDart,
      'rust': langRust,
      'json': langJson,
      'yaml': langYaml,
      'css': langCss,
      'javascript': langJavascript,
      'typescript': langTypescript,
      'python': langPython,
      'bash': langBash,
      'c': langC,
      'cpp': langCpp,
      'java': langJava,
      'kotlin': langKotlin,
      'go': langGo,
      'swift': langSwift,
      'sql': langSql,
      'ini': langIni,
      'properties': langProperties,
      'diff': langDiff,
      'dockerfile': langDockerfile,
      'plaintext': langPlaintext,
    });
  }

  static final Map<String, TextStyle> _lightTheme = {
    ...githubTheme,
    'string': const TextStyle(color: Color(0xFF098658)),
    'attr': const TextStyle(color: Color(0xFF005CC5)),
    'number': const TextStyle(color: Color(0xFF098658)),
    'literal': const TextStyle(color: Color(0xFFD73A49)),
    'keyword': const TextStyle(color: Color(0xFFD73A49)),
    'punctuation': const TextStyle(color: Color(0xFF586069)),
  };

  static final Map<String, TextStyle> _darkTheme = {
    ...atomOneDarkTheme,
    'attr': const TextStyle(color: Color(0xFF9CDCFE)),
    'string': const TextStyle(color: Color(0xFF98C379)),
    'number': const TextStyle(color: Color(0xFFD19A66)),
    'literal': const TextStyle(color: Color(0xFF56B6C2)),
    'keyword': const TextStyle(color: Color(0xFFC678DD)),
    'punctuation': const TextStyle(color: Color(0xFFABB2BF)),
  };

  String? languageFor(String fileName) {
    var end = fileName.indexOf('?');
    if (end < 0) end = fileName.length;
    var start = end;
    while (start > 0) {
      final ch = fileName.codeUnitAt(start - 1);
      if (ch == 47 || ch == 92) break;
      start--;
    }
    final cleanName = fileName.substring(start, end);
    final lower = cleanName.toLowerCase();
    if (lower == 'dockerfile') return 'dockerfile';
    if (lower == 'makefile') return 'bash';
    if (lower == '.eslintrc' || lower == '.prettierrc' || lower == '.stylelintrc') return 'json';
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return null;
    return _extensions[lower.substring(dot + 1)];
  }

  String? _cachedCode;
  String? _cachedFileName;
  Brightness? _cachedBrightness;
  double? _cachedFontSize;
  TextSpan? _cachedResult;

  /// Highlighted spans for `code`, or `null` when the language is unknown.
  TextSpan? spanFor(
    String code,
    String fileName,
    Brightness brightness, {
    double fontSize = 13.0,
  }) {
    if ((identical(code, _cachedCode) || code == _cachedCode) &&
        fileName == _cachedFileName &&
        brightness == _cachedBrightness &&
        fontSize == _cachedFontSize) {
      return _cachedResult;
    }

    final language = languageFor(fileName);
    if (language == null) {
      _cachedCode = code;
      _cachedFileName = fileName;
      _cachedBrightness = brightness;
      _cachedFontSize = fontSize;
      _cachedResult = null;
      return null;
    }

    final theme = brightness == Brightness.dark ? _darkTheme : _lightTheme;
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.35,
      color: theme['root']?.color,
    );

    // Fast guards against freezing the UI isolate with regex backtracking.
    // Pure Dart AST tokenization is fast for typical source files, but large
    // files, data dumps, minified scripts, and long logs should render cleanly
    // with base monospace styling to ensure instant file opening with zero lag.
    if (code.length > 48 * 1024) return null;
    int lineCount = 1;
    int lineStart = 0;
    for (int i = 0; i < code.length; i++) {
      if (code.codeUnitAt(i) == 10) {
        // Guard against minified code with very long lines causing exponential regex backtracking
        if (i - lineStart > 500) return null;
        lineCount++;
        if (lineCount > 1000) return null;
        lineStart = i + 1;
      }
    }
    if (code.length - lineStart > 500) return null;

    try {
      final result = _highlight.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(base, theme);
      result.render(renderer);
      final span = renderer.span ?? TextSpan(text: code, style: base);
      _cachedCode = code;
      _cachedFileName = fileName;
      _cachedBrightness = brightness;
      _cachedFontSize = fontSize;
      _cachedResult = span;
      return span;
    } catch (_) {
      final span = TextSpan(text: code, style: base);
      _cachedCode = code;
      _cachedFileName = fileName;
      _cachedBrightness = brightness;
      _cachedFontSize = fontSize;
      _cachedResult = span;
      return span;
    }
  }

  Color backgroundFor(Brightness brightness) {
    final theme = brightness == Brightness.dark ? _darkTheme : _lightTheme;
    return theme['root']?.backgroundColor ?? Colors.transparent;
  }
}
