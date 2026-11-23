import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_paths.dart';

/// Small persisted key/value store for UI preferences.
///
/// Values are read synchronously from an in-memory map loaded at startup;
/// writes are fire-and-forget so callers do not have to await them.
class PreferencesService {
  static final PreferencesService instance = PreferencesService._();
  PreferencesService._();

  /// Live copy of the "toolbar at bottom" setting so an open browser page
  /// follows the switch without being recreated.
  static final ValueNotifier<bool> toolbarAtBottom = ValueNotifier<bool>(false);
  static const String prefToolbarBottom = 'browser.toolbar_bottom';
  static final ValueNotifier<bool> vaultVideoThumbnailsNotifier =
      ValueNotifier<bool>(false);
  static const String prefHistoryRetentionDays = 'history.retention_days';
  static const int defaultHistoryRetentionDays = 30;
  static final ValueNotifier<int> historyRetentionDaysNotifier =
      ValueNotifier<int>(defaultHistoryRetentionDays);

  Map<String, String> _values = {};
  bool _loaded = false;
  File? _file;
  Timer? _persistTimer;
  Future<void> _writeQueue = Future<void>.value();

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
    vaultVideoThumbnailsNotifier.value =
        getBool(prefVaultVideoThumbnails) ?? false;
    historyRetentionDaysNotifier.value = historyRetentionDays;
  }

  /// Loads [toolbarAtBottom] once preferences are available.
  void syncToolbarAtBottom() {
    toolbarAtBottom.value = getBool(prefToolbarBottom) ?? false;
  }

  static const String prefUseSystemPicker = 'upload.use_system_picker';
  static const String prefRecentUploadDirs = 'upload.recent_directories';
  static const String prefBufferDurationSec = 'player.buffer_duration_sec';
  static const String prefBufferSizeMb = 'player.buffer_size_mb';
  static const String prefVaultAutoLockSec = 'vault.auto_lock_timeout_sec';
  static const String prefVaultSkipExternalOpenWarning =
      'vault.skip_external_open_warning';
  static const String prefVaultVideoThumbnails = 'vault.video_thumbnails';
  static const String prefPinnedVaults = 'vault.pinned_entries';
  static const String prefSidebarCollapsed = 'sidebar.collapsed';
  static const String prefSidebarCollapsedGroups = 'sidebar.collapsed_groups';
  static const String prefSidebarWidth = 'sidebar.width';

  int get historyRetentionDays {
    final raw = getString(prefHistoryRetentionDays);
    if (raw != null) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed >= 0) return parsed;
    }
    return defaultHistoryRetentionDays;
  }

  set historyRetentionDays(int value) {
    final clamped = value < 0 ? 0 : value;
    setString(prefHistoryRetentionDays, clamped.toString());
    historyRetentionDaysNotifier.value = clamped;
  }

  bool get sidebarCollapsed => getBool(prefSidebarCollapsed) ?? false;

  set sidebarCollapsed(bool value) => setBool(prefSidebarCollapsed, value);

  Set<String> get sidebarCollapsedGroups {
    final raw = getString(prefSidebarCollapsedGroups);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.split(',').where((e) => e.isNotEmpty).toSet();
  }

  set sidebarCollapsedGroups(Set<String> value) {
    final sorted = value.where((e) => e.isNotEmpty).toList()..sort();
    setString(prefSidebarCollapsedGroups, sorted.join(','));
  }

  double get sidebarWidth {
    final raw = getString(prefSidebarWidth);
    final parsed = raw != null ? double.tryParse(raw) : null;
    if (parsed == null) return 240.0;
    return parsed.clamp(196.0, 360.0);
  }

  set sidebarWidth(double value) =>
      setString(prefSidebarWidth, value.clamp(196.0, 360.0).toStringAsFixed(1));

  int get vaultAutoLockTimeoutSec {
    final raw = getString(prefVaultAutoLockSec);
    if (raw != null) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return 600;
  }

  set vaultAutoLockTimeoutSec(int value) =>
      setString(prefVaultAutoLockSec, value.toString());

  bool get vaultSkipExternalOpenWarning =>
      getBool(prefVaultSkipExternalOpenWarning) ?? false;

  set vaultSkipExternalOpenWarning(bool value) =>
      setBool(prefVaultSkipExternalOpenWarning, value);

  bool get vaultVideoThumbnails =>
      getBool(prefVaultVideoThumbnails) ?? false;

  set vaultVideoThumbnails(bool value) {
    setBool(prefVaultVideoThumbnails, value);
    vaultVideoThumbnailsNotifier.value = value;
  }

  int get bufferDurationSec {
    final raw = getString(prefBufferDurationSec);
    if (raw != null) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 15;
  }

  set bufferDurationSec(int value) => setString(prefBufferDurationSec, value.toString());

  int get bufferSizeMb {
    final raw = getString(prefBufferSizeMb);
    if (raw != null) {
      final parsed = int.tryParse(raw);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 16;
  }

  set bufferSizeMb(int value) => setString(prefBufferSizeMb, value.toString());

  bool get useSystemPicker {
    final val = getBool(prefUseSystemPicker);
    if (val != null) return val;
    // Default to true on Desktop (Linux, Windows, macOS), false on mobile
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  }

  set useSystemPicker(bool value) => setBool(prefUseSystemPicker, value);

  List<String> getRecentUploadDirs() {
    final raw = getString(prefRecentUploadDirs);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((p) => p.isNotEmpty && Directory(p).existsSync())
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  void addRecentUploadDir(String dir) {
    if (dir.isEmpty) return;
    final normalized = dir.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) return;

    final current = getRecentUploadDirs().toList();
    current.removeWhere(
      (p) => p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '') == normalized,
    );
    current.insert(0, normalized);
    if (current.length > 8) {
      current.removeRange(8, current.length);
    }
    setString(prefRecentUploadDirs, jsonEncode(current));
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

  /// Drops a key entirely, so a stale value cannot be read back as a default.
  void remove(String key) {
    if (_values.remove(key) != null) _persist();
  }

  /// Window move/resize fires many times per second and each event writes
  /// four keys. Coalesce them into one asynchronous write so dragging the
  /// window never blocks the UI isolate with synchronous disk I/O.
  void _persist() {
    final file = _file;
    if (file == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () {
      _persistTimer = null;
      _enqueueWrite(file);
    });
  }

  /// Serialize debounced writes so two of them can never interleave, and write
  /// atomically (temp file + rename) so a concurrent [flush] cannot tear the
  /// JSON. The snapshot is taken when the write runs, so a late write still
  /// persists the latest values rather than a stale one.
  void _enqueueWrite(File file) {
    _writeQueue =
        _writeQueue.then((_) => _atomicWrite(file)).catchError((_) {});
  }

  Future<void> _atomicWrite(File file) async {
    final tmp = File('${file.path}.tmp');
    try {
      await tmp.writeAsString(jsonEncode(_values));
      await tmp.rename(file.path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  /// Immediately flush a pending debounced write, e.g. before the window
  /// closes so the last bounds are not lost. Synchronous and atomic so it is
  /// durable even if the process exits right after.
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final file = _file;
    if (file == null) return;
    final tmp = File('${file.path}.flush.tmp');
    try {
      tmp.writeAsStringSync(jsonEncode(_values));
      tmp.renameSync(file.path);
    } catch (_) {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
  }
}
