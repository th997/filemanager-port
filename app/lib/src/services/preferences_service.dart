import 'dart:convert';
import 'dart:io';

import 'platform_paths.dart';

/// Small persisted key/value store for UI preferences.
///
/// Values are read synchronously from an in-memory map loaded at startup;
/// writes are fire-and-forget so callers do not have to await them.
class PreferencesService {
  static final PreferencesService instance = PreferencesService._();
  PreferencesService._();

  Map<String, String> _values = {};
  bool _loaded = false;
  File? _file;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _file = File('${PlatformPaths.appDataDir()}/preferences.json');
    try {
      if (_file!.existsSync()) {
        final decoded = jsonDecode(await _file!.readAsString());
        if (decoded is Map) {
          _values = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {
      _values = {};
    }
  }

  String? getString(String key) => _values[key];

  bool? getBool(String key) {
    final value = _values[key];
    if (value == null) return null;
    return value == 'true';
  }

  void setString(String key, String value) {
    _values[key] = value;
    _persist();
  }

  void setBool(String key, bool value) => setString(key, value.toString());

  void _persist() {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(jsonEncode(_values));
    } catch (_) {}
  }
}
