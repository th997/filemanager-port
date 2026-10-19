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

  String? languageFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower == 'dockerfile') return 'dockerfile';
    if (lower == 'makefile') return 'bash';
    final dot = lower.lastIndexOf('.');
    if (dot < 0 || dot == lower.length - 1) return null;
    return _extensions[lower.substring(dot + 1)];
  }

  /// Highlighted spans for `code`, or `null` when the language is unknown.
  TextSpan? spanFor(
    String code,
    String fileName,
    Brightness brightness,
  ) {
    final language = languageFor(fileName);
    if (language == null) return null;

    final theme = brightness == Brightness.dark ? atomOneDarkTheme : githubTheme;
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.35,
      color: theme['root']?.color,
    );

    try {
      final result = _highlight.highlight(code: code, language: language);
      final renderer = TextSpanRenderer(base, theme);
      result.render(renderer);
      return renderer.span ?? TextSpan(text: code, style: base);
    } catch (_) {
      return TextSpan(text: code, style: base);
    }
  }

  Color backgroundFor(Brightness brightness) {
    final theme = brightness == Brightness.dark ? atomOneDarkTheme : githubTheme;
    return theme['root']?.backgroundColor ?? Colors.transparent;
  }
}
