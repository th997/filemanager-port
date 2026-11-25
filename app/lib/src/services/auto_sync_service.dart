import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../rust/api/metadata.dart';
import '../rust/api/sync.dart';
import '../rust/api/tasks.dart' as tasks_api;
import 'background_keepalive_service.dart';
import 'photo_backup_service.dart';
import 'preferences_service.dart';
import 'storage_service.dart';
import 'task_service.dart';
import 'vault_service.dart';

/// Persisted directory sync profile supporting optional periodic foreground
/// auto-sync (`autoIntervalMinutes > 0`).
class SyncProfile {
  final String name;
  final String srcRoot;
  final String srcPath;
  final String dstRoot;
  final String dstPath;
  final String mode;
  final int autoIntervalMinutes;
  final int lastAutoSyncMs;
  final List<String> excludeExtensions;
  final List<String> excludeNames;
  final List<String> excludeDirs;

  const SyncProfile({
    required this.name,
    required this.srcRoot,
    required this.srcPath,
    required this.dstRoot,
    required this.dstPath,
    required this.mode,
    this.autoIntervalMinutes = 0,
    this.lastAutoSyncMs = 0,
    this.excludeExtensions = const [],
    this.excludeNames = const [],
    this.excludeDirs = const [],
  });

  SyncProfile copyWith({
    String? name,
    String? srcRoot,
    String? srcPath,
    String? dstRoot,
    String? dstPath,
    String? mode,
    int? autoIntervalMinutes,
    int? lastAutoSyncMs,
    List<String>? excludeExtensions,
    List<String>? excludeNames,
    List<String>? excludeDirs,
  }) {
    return SyncProfile(
      name: name ?? this.name,
      srcRoot: srcRoot ?? this.srcRoot,
      srcPath: srcPath ?? this.srcPath,
      dstRoot: dstRoot ?? this.dstRoot,
      dstPath: dstPath ?? this.dstPath,
      mode: mode ?? this.mode,
      autoIntervalMinutes: autoIntervalMinutes ?? this.autoIntervalMinutes,
      lastAutoSyncMs: lastAutoSyncMs ?? this.lastAutoSyncMs,
      excludeExtensions: excludeExtensions ?? this.excludeExtensions,
      excludeNames: excludeNames ?? this.excludeNames,
      excludeDirs: excludeDirs ?? this.excludeDirs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'srcRoot': srcRoot,
        'srcPath': srcPath,
        'dstRoot': dstRoot,
        'dstPath': dstPath,
        'mode': mode,
        'autoIntervalMinutes': autoIntervalMinutes,
        'lastAutoSyncMs': lastAutoSyncMs,
        if (excludeExtensions.isNotEmpty)
          'excludeExtensions': excludeExtensions,
        if (excludeNames.isNotEmpty) 'excludeNames': excludeNames,
        if (excludeDirs.isNotEmpty) 'excludeDirs': excludeDirs,
      };

  static List<String> _decodeStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static SyncProfile? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final srcRoot = raw['srcRoot']?.toString() ?? '';
    final dstRoot = raw['dstRoot']?.toString() ?? '';
    if (name.isEmpty || srcRoot.isEmpty || dstRoot.isEmpty) return null;
    final intervalRaw = raw['autoIntervalMinutes'];
    final interval = intervalRaw is int
        ? intervalRaw
        : int.tryParse(intervalRaw?.toString() ?? '') ?? 0;
    final lastMsRaw = raw['lastAutoSyncMs'];
    final lastMs = lastMsRaw is int
        ? lastMsRaw
        : int.tryParse(lastMsRaw?.toString() ?? '') ?? 0;
    return SyncProfile(
      name: name,
      srcRoot: srcRoot,
      srcPath: raw['srcPath']?.toString() ?? '',
      dstRoot: dstRoot,
      dstPath: raw['dstPath']?.toString() ?? '',
      mode: raw['mode']?.toString() ?? 'incremental',
      autoIntervalMinutes: interval < 0 ? 0 : interval,
      lastAutoSyncMs: lastMs < 0 ? 0 : lastMs,
      excludeExtensions: _decodeStringList(raw['excludeExtensions']),
      excludeNames: _decodeStringList(raw['excludeNames']),
      excludeDirs: _decodeStringList(raw['excludeDirs']),
    );
  }
}

typedef SyncProfileRunner = Future<void> Function(SyncProfile profile);
typedef OfflinePinSyncRunner = Future<({int pushed, int pulled, int conflicts})>
    Function();

/// Coordinates in-app scheduled directory sync profiles and automatic
/// check/push/pull reconciliation for offline pinned files on app resume and
/// periodic ticks.
class AutoSyncService with ChangeNotifier {
  AutoSyncService({
    this.profileRunner,
    this.offlinePinRunner,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final AutoSyncService instance = AutoSyncService();

  static const String prefSyncProfiles = 'sync.profiles_v1';
  static const String prefOfflineAutoSync = 'offline.auto_sync_enabled';
  static const String _prefCapMb = 'offline.pin_cap_mb';
  static const Duration offlineResumeCooldown = Duration(seconds: 60);

  final SyncProfileRunner? profileRunner;
  final OfflinePinSyncRunner? offlinePinRunner;
  final DateTime Function() _clock;

  Timer? _timer;
  bool _runningTick = false;
  DateTime? _lastOfflineCheckAt;
  String? _lastAutoSyncError;

  String? get lastAutoSyncError => _lastAutoSyncError;

  void clearLastAutoSyncError() {
    if (_lastAutoSyncError == null) return;
    _lastAutoSyncError = null;
    notifyListeners();
  }

  bool get isOfflineAutoSyncEnabled =>
      PreferencesService.instance.getBool(prefOfflineAutoSync) ?? true;

  set isOfflineAutoSyncEnabled(bool value) {
    PreferencesService.instance.setBool(prefOfflineAutoSync, value);
  }

  List<SyncProfile> loadProfiles() {
    final raw = PreferencesService.instance.getString(prefSyncProfiles);
    if (raw == null || raw.isEmpty) return <SyncProfile>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(SyncProfile.fromJson)
            .whereType<SyncProfile>()
            .toList();
      }
    } catch (_) {}
    return <SyncProfile>[];
  }

  void saveProfiles(List<SyncProfile> profiles) {
    PreferencesService.instance.setString(
      prefSyncProfiles,
      jsonEncode(profiles.map((p) => p.toJson()).toList()),
    );
  }

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(tick());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> onAppResumed() => tick(fromResume: true);

  /// Evaluates due scheduled sync profiles and (when due or resumed) reconciles
  /// non-conflicting offline pinned files.
  Future<void> tick({bool fromResume = false}) async {
    if (_runningTick) return;
    _runningTick = true;
    try {
      await _runDueSyncProfiles();
      if (isOfflineAutoSyncEnabled) {
        final now = _clock();
        final shouldCheckOffline = _lastOfflineCheckAt == null ||
            (fromResume &&
                now.difference(_lastOfflineCheckAt!) >= offlineResumeCooldown) ||
            now.difference(_lastOfflineCheckAt!) >= const Duration(minutes: 15);
        if (shouldCheckOffline) {
          _lastOfflineCheckAt = now;
          try {
            await reconcileOfflinePinnedFiles();
          } catch (_) {}
        }
      }
      await PhotoBackupService.instance.tickIfDue(fromResume: fromResume);
    } finally {
      _runningTick = false;
    }
  }

  Future<int> _runDueSyncProfiles() async {
    final profiles = loadProfiles();
    if (profiles.isEmpty) return 0;
    final nowMs = _clock().millisecondsSinceEpoch;
    var executed = 0;
    var mutated = false;
    final updated = List<SyncProfile>.of(profiles);

    final completedTimestamps = <String, int>{};
    String? cycleError;
    var ranAny = false;

    for (var i = 0; i < updated.length; i++) {
      final p = updated[i];
      if (p.autoIntervalMinutes <= 0) continue;
      final intervalMs = p.autoIntervalMinutes * 60 * 1000;
      if (nowMs - p.lastAutoSyncMs < intervalMs) continue;
      if (_involvesLockedVault(p.srcRoot) || _involvesLockedVault(p.dstRoot)) {
        continue;
      }
      ranAny = true;
      final key = '${p.name}|${p.srcRoot}|${p.srcPath}|${p.dstRoot}|${p.dstPath}|${p.mode}';
      try {
        final runner = profileRunner ?? _defaultProfileRunner;
        await runner(p);
        completedTimestamps[key] = _clock().millisecondsSinceEpoch;
        mutated = true;
        executed++;
      } catch (e) {
        cycleError = '${p.name}: $e';
        completedTimestamps[key] = nowMs;
        mutated = true;
      }
    }

    if (ranAny && cycleError != _lastAutoSyncError) {
      _lastAutoSyncError = cycleError;
      notifyListeners();
    }

    if (mutated) {
      final latest = loadProfiles();
      for (var i = 0; i < latest.length; i++) {
        final p = latest[i];
        final key = '${p.name}|${p.srcRoot}|${p.srcPath}|${p.dstRoot}|${p.dstPath}|${p.mode}';
        final ts = completedTimestamps[key];
        if (ts != null) {
          latest[i] = p.copyWith(lastAutoSyncMs: ts);
        }
      }
      saveProfiles(latest);
    }
    return executed;
  }

  static bool _involvesLockedVault(String root) {
    if (!root.startsWith('vault://')) return false;
    final rest = root.substring('vault://'.length);
    final id = rest.split('/').first;
    return !VaultService.instance.unlockedVaults.any((v) => v.id == id);
  }

  static SyncExcludeRulesDto? _rulesForProfile(SyncProfile profile) {
    if (profile.excludeExtensions.isEmpty &&
        profile.excludeNames.isEmpty &&
        profile.excludeDirs.isEmpty) {
      return null;
    }
    return SyncExcludeRulesDto(
      excludeExtensions: profile.excludeExtensions,
      excludeNames: profile.excludeNames,
      excludeDirs: profile.excludeDirs,
    );
  }

  static Future<void> _defaultProfileRunner(SyncProfile profile) async {
    await BackgroundKeepAliveService.instance.runWithKeepAlive(
      'autosync:${profile.name}',
      () async {
        final rules = _rulesForProfile(profile);
        final plan = await previewDirectorySync(
          srcRoot: profile.srcRoot,
          srcPath: profile.srcPath,
          dstRoot: profile.dstRoot,
          dstPath: profile.dstPath,
          mode: profile.mode,
          excludeRules: rules,
        );
        if (plan.items.isEmpty) return;
        final taskId = await startDirectorySyncTask(
          srcRoot: profile.srcRoot,
          srcPath: profile.srcPath,
          dstRoot: profile.dstRoot,
          dstPath: profile.dstPath,
          mode: profile.mode,
          selectedRelPaths: plan.items.map((e) => e.relPath).toList(),
          excludeRules: rules,
        );
        tasks_api.TaskProgressDto? lastProgress;
        await for (final prog in TaskService.instance.watch(taskId)) {
          lastProgress = prog;
        }
        if (lastProgress == null ||
            lastProgress.state != 'completed' ||
            lastProgress.failedItems.isNotEmpty) {
          final fallbackErr = (lastProgress != null && lastProgress.failedItems.isNotEmpty)
              ? lastProgress.failedItems.first.error
              : 'Scheduled sync failed (${lastProgress?.state ?? 'missing'})';
          throw StateError(lastProgress?.error ?? fallbackErr);
        }
      },
      title: 'Scheduled Sync: ${profile.name}',
      detail: '${profile.srcRoot} → ${profile.dstRoot}',
    );
  }

  /// Checks all offline pinned files and automatically pushes `local_modified`
  /// copies and pulls `remote_newer` / `missing_local` copies while leaving
  /// `conflict` items untouched for manual resolution.
  Future<({int pushed, int pulled, int conflicts})>
      reconcileOfflinePinnedFiles() async {
    final runner = offlinePinRunner;
    if (runner != null) {
      return runner();
    }
    return BackgroundKeepAliveService.instance.runWithKeepAlive(
      'autosync:offline_pins',
      () async {
        var pushed = 0;
        var pulled = 0;
        var conflicts = 0;
        final dbPath = StorageService.instance.dbPath;
        final capMb = int.tryParse(
              PreferencesService.instance.getString(_prefCapMb) ?? '',
            ) ??
            512;
        final items = listPinnedFiles(dbPath: dbPath);
        for (final item in items) {
          if (_involvesLockedVault(item.remoteRoot)) continue;
          try {
            final st = await checkPinnedFileStatus(
              dbPath: dbPath,
              remoteRoot: item.remoteRoot,
              remotePath: item.remotePath,
            );
            if (st.status == 'local_modified') {
              await pushPinnedFile(
                dbPath: dbPath,
                remoteRoot: item.remoteRoot,
                remotePath: item.remotePath,
              );
              pushed++;
            } else if (st.status == 'remote_newer' ||
                st.status == 'missing_local') {
              await pinRemoteFile(
                dbPath: dbPath,
                remoteRoot: item.remoteRoot,
                remotePath: item.remotePath,
                maxCacheBytes: BigInt.from(capMb * 1024 * 1024),
              );
              pulled++;
            } else if (st.status == 'conflict') {
              conflicts++;
            }
          } catch (_) {}
        }
        return (pushed: pushed, pulled: pulled, conflicts: conflicts);
      },
      title: 'Syncing Offline Pinned Files',
      detail: 'Checking remote changes and uploading offline edits',
    );
  }
}
