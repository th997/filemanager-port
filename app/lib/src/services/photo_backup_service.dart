import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'background_keepalive_service.dart';
import 'platform_paths.dart';
import 'preferences_service.dart';
import 'task_service.dart';
import 'vault_service.dart';
import '../rust/api/tasks.dart' as tasks_api;

class PhotoBackupAsset {
  final String id;
  final String filePath;
  final String fileName;
  final DateTime modified;

  const PhotoBackupAsset({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.modified,
  });
}

class PhotoBackupProgress {
  final bool running;
  final bool scanning;
  final bool cancelled;
  final int uploaded;
  final int total;
  final String? currentFile;
  final String? lastError;

  const PhotoBackupProgress({
    this.running = false,
    this.scanning = false,
    this.cancelled = false,
    this.uploaded = 0,
    this.total = 0,
    this.currentFile,
    this.lastError,
  });
}

typedef PhotoAssetFetcher = Future<List<PhotoBackupAsset>> Function();
typedef ConnectivityChecker = Future<bool> Function();
typedef BackupUploader = Future<void> Function({
  required PhotoBackupAsset asset,
  required String dstRoot,
  required String dstDir,
});

/// Incremental mobile/desktop photo backup service supporting NAS/S3/WebDAV or
/// Privacy Vault destinations. Tracks already backed-up asset IDs in
/// [PreferencesService] so only new media is uploaded each run.
class PhotoBackupService {
  static final PhotoBackupService instance = PhotoBackupService();

  static const String prefEnabled = 'photo_backup.enabled';
  static const String prefWifiOnly = 'photo_backup.wifi_only';
  static const String prefTargetRoot = 'photo_backup.target_root';
  static const String prefTargetDir = 'photo_backup.target_dir';
  static const String prefSourceDirs = 'photo_backup.source_dirs_v1';
  static const String prefSourceAlbumIds = 'photo_backup.source_album_ids_v1';
  static const String prefBackedUpIds = 'photo_backup.backed_up_ids_v1';
  static const String prefLastBackupMs = 'photo_backup.last_backup_ms';
  static const Duration autoBackupInterval = Duration(minutes: 15);

  static const Set<String> _supportedMediaExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.heic',
    '.heif',
    '.webp',
    '.gif',
    '.bmp',
    '.raw',
    '.dng',
    '.cr2',
    '.nef',
    '.arw',
    '.mp4',
    '.mov',
    '.m4v',
    '.mkv',
    '.avi',
    '.3gp',
  };

  final PhotoAssetFetcher? assetFetcher;
  final ConnectivityChecker? wifiChecker;
  final BackupUploader? uploader;
  final DateTime Function() _clock;

  final ValueNotifier<PhotoBackupProgress> progressNotifier =
      ValueNotifier<PhotoBackupProgress>(const PhotoBackupProgress());

  bool _running = false;
  bool _cancelRequested = false;
  DateTime? _lastAutoTick;

  void cancelBackup() {
    if (_running) {
      _cancelRequested = true;
    }
  }

  PhotoBackupService({
    this.assetFetcher,
    this.wifiChecker,
    this.uploader,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  bool get isEnabled =>
      PreferencesService.instance.getBool(prefEnabled) ?? false;

  set isEnabled(bool value) {
    PreferencesService.instance.setBool(prefEnabled, value);
  }

  bool get wifiOnly =>
      PreferencesService.instance.getBool(prefWifiOnly) ?? true;

  set wifiOnly(bool value) {
    PreferencesService.instance.setBool(prefWifiOnly, value);
  }

  String get targetRoot =>
      PreferencesService.instance.getString(prefTargetRoot) ?? '';

  String get targetDir =>
      PreferencesService.instance.getString(prefTargetDir) ?? '';

  int get lastBackupMillis {
    final raw = PreferencesService.instance.getString(prefLastBackupMs);
    return int.tryParse(raw ?? '') ?? 0;
  }

  void setTarget({required String root, required String dir}) {
    PreferencesService.instance.setString(prefTargetRoot, root);
    PreferencesService.instance.setString(prefTargetDir, dir);
  }

  List<String> get sourceDirs {
    final raw = PreferencesService.instance.getString(prefSourceDirs);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  void setSourceDirs(List<String> dirs) {
    final unique = <String>[];
    final seen = <String>{};
    for (final d in dirs) {
      final clean = d.trim();
      if (clean.isNotEmpty && seen.add(clean)) {
        unique.add(clean);
      }
    }
    if (unique.isEmpty) {
      PreferencesService.instance.remove(prefSourceDirs);
    } else {
      PreferencesService.instance.setString(prefSourceDirs, jsonEncode(unique));
    }
  }

  void addSourceDir(String dirPath) {
    final clean = dirPath.trim();
    if (clean.isEmpty) return;
    final next = List<String>.from(sourceDirs);
    if (!next.contains(clean)) {
      next.add(clean);
      setSourceDirs(next);
    }
  }

  void removeSourceDir(String dirPath) {
    final next = sourceDirs.where((d) => d != dirPath).toList();
    setSourceDirs(next);
  }

  List<String> get sourceAlbumIds {
    final raw = PreferencesService.instance.getString(prefSourceAlbumIds);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  void setSourceAlbumIds(List<String> ids) {
    final unique = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      final clean = id.trim();
      if (clean.isNotEmpty && seen.add(clean)) {
        unique.add(clean);
      }
    }
    if (unique.isEmpty) {
      PreferencesService.instance.remove(prefSourceAlbumIds);
    } else {
      PreferencesService.instance.setString(
        prefSourceAlbumIds,
        jsonEncode(unique),
      );
    }
  }

  List<String> effectiveDesktopSourceDirs() {
    final configured = sourceDirs;
    if (configured.isNotEmpty) return configured;
    return PlatformPaths.galleryDirs();
  }

  Set<String> loadBackedUpIds() {
    final raw = PreferencesService.instance.getString(prefBackedUpIds);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
    } catch (_) {}
    return <String>{};
  }

  void _saveBackedUpIds(Set<String> ids) {
    PreferencesService.instance.setString(
      prefBackedUpIds,
      jsonEncode(ids.toList()),
    );
  }

  void clearLedger() {
    _saveBackedUpIds(<String>{});
    PreferencesService.instance.remove(prefLastBackupMs);
  }

  Future<void> tickIfDue({bool fromResume = false}) async {
    if (!isEnabled || _running) return;
    if (targetRoot.isEmpty) return;
    final now = _clock();
    final minGap = fromResume ? const Duration(minutes: 2) : autoBackupInterval;
    if (_lastAutoTick != null && now.difference(_lastAutoTick!) < minGap) {
      return;
    }
    _lastAutoTick = now;
    try {
      await runBackup(force: false);
    } catch (_) {}
  }

  /// Runs one incremental backup pass. Returns the count of newly backed-up
  /// media assets (or 0 if skipped due to Wi-Fi gate / empty queue).
  Future<int> runBackup({bool force = false}) async {
    if (_running) return 0;
    final dstRoot = targetRoot;
    final dstDir = targetDir;
    if (dstRoot.isEmpty) {
      throw StateError('Backup destination is not configured');
    }
    if (dstRoot.startsWith('vault://')) {
      final id = dstRoot.substring('vault://'.length).split('/').first;
      if (!VaultService.instance.isUnlocked(id)) {
        if (force) {
          throw StateError('Target Privacy Vault is locked');
        }
        return 0;
      }
    }

    _running = true;
    _cancelRequested = false;
    try {
      if (!force && wifiOnly) {
        final onWifi = await (wifiChecker ?? _defaultWifiChecker)();
        if (!onWifi) {
          return 0;
        }
      }

      progressNotifier.value = const PhotoBackupProgress(
        running: true,
        scanning: true,
      );

      return await BackgroundKeepAliveService.instance.runWithKeepAlive(
        'photo_backup',
        () async {
          final ledger = loadBackedUpIds();
          final customFetcher = assetFetcher;
          final allAssets = customFetcher != null
              ? await customFetcher()
              : await _defaultAssetFetcherWithLedger(
                  ledger,
                  customDirs: sourceDirs,
                  selectedAlbumIds: sourceAlbumIds,
                );
          if (_cancelRequested) {
            progressNotifier.value = const PhotoBackupProgress(
              running: false,
              cancelled: true,
              uploaded: 0,
              total: 0,
            );
            return 0;
          }
          final pending = allAssets
              .where((a) => !ledger.contains(a.id) && a.filePath.isNotEmpty)
              .toList();

          if (pending.isEmpty) {
            progressNotifier.value = const PhotoBackupProgress(
              running: false,
              uploaded: 0,
              total: 0,
            );
            return 0;
          }

          var uploaded = 0;
          String? lastError;
          progressNotifier.value = PhotoBackupProgress(
            running: true,
            uploaded: 0,
            total: pending.length,
          );

          final doUpload = uploader ?? _defaultUploader;
          for (final asset in pending) {
            if (_cancelRequested) break;
            progressNotifier.value = PhotoBackupProgress(
              running: true,
              uploaded: uploaded,
              total: pending.length,
              currentFile: asset.fileName,
              lastError: lastError,
            );
            try {
              await doUpload(
                asset: asset,
                dstRoot: dstRoot,
                dstDir: dstDir,
              );
              ledger.add(asset.id);
              uploaded++;
              _saveBackedUpIds(ledger);
            } catch (e) {
              lastError = '$e';
              progressNotifier.value = PhotoBackupProgress(
                running: true,
                uploaded: uploaded,
                total: pending.length,
                currentFile: asset.fileName,
                lastError: lastError,
              );
            }
          }

          if (uploaded > 0) {
            PreferencesService.instance.setString(
              prefLastBackupMs,
              '${_clock().millisecondsSinceEpoch}',
            );
          }
          progressNotifier.value = PhotoBackupProgress(
            running: false,
            cancelled: _cancelRequested,
            uploaded: uploaded,
            total: pending.length,
            lastError: lastError,
          );
          return uploaded;
        },
        title: 'Photo Incremental Backup',
        detail: 'Backing up new media to $dstRoot',
      );
    } finally {
      _running = false;
      if (progressNotifier.value.running) {
        final cur = progressNotifier.value;
        progressNotifier.value = PhotoBackupProgress(
          running: false,
          cancelled: _cancelRequested,
          uploaded: cur.uploaded,
          total: cur.total,
          lastError: cur.lastError,
        );
      }
      _cancelRequested = false;
    }
  }

  static Future<bool> _defaultWifiChecker() async {
    // On desktop devices assume unmetered wired/Wi-Fi LAN connection.
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      var sawNonCellular = false;
      for (final iface in ifaces) {
        if (iface.addresses.isEmpty) continue;
        final name = iface.name.toLowerCase();
        final isCellular = name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('pdp_ip') ||
            name.startsWith('cell') ||
            name.startsWith('wwan');
        if (isCellular) continue;
        if (name.startsWith('wlan') ||
            name.startsWith('en') ||
            name.startsWith('eth') ||
            name.startsWith('ap') ||
            name.startsWith('swlan') ||
            name.contains('wifi')) {
          return true;
        }
        sawNonCellular = false;
      }
      return sawNonCellular;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _scanDirectoryAssets(
    String dirPath,
    Set<String> alreadyBackedUpIds,
    Set<String> seenIds,
    List<PhotoBackupAsset> out,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relName = p.basename(entity.path);
        if (relName.startsWith('.')) continue;
        final parts = entity.path.split(Platform.pathSeparator);
        if (parts.any((seg) => seg.startsWith('.') && seg.length > 1)) {
          continue;
        }
        final ext = p.extension(entity.path).toLowerCase();
        if (!_supportedMediaExts.contains(ext)) {
          continue;
        }
        try {
          final st = await entity.stat();
          final id = '${entity.path}:${st.size}:${st.modified.millisecondsSinceEpoch}';
          if (alreadyBackedUpIds.contains(id) || !seenIds.add(id)) continue;
          out.add(
            PhotoBackupAsset(
              id: id,
              filePath: entity.path,
              fileName: relName,
              modified: st.modified,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  static Future<List<PhotoBackupAsset>> _defaultAssetFetcherWithLedger(
    Set<String> alreadyBackedUpIds, {
    List<String> customDirs = const [],
    List<String> selectedAlbumIds = const [],
  }) async {
    final out = <PhotoBackupAsset>[];
    final seenIds = <String>{};

    if (Platform.isAndroid || Platform.isIOS) {
      final perm = await PhotoManager.requestPermissionExtend();
      if (perm.hasAccess) {
        final paths = await PhotoManager.getAssetPathList(
          onlyAll: selectedAlbumIds.isEmpty,
          type: RequestType.common,
        );
        final Iterable<AssetPathEntity> targetAlbums;
        if (selectedAlbumIds.isNotEmpty) {
          final wanted = selectedAlbumIds.toSet();
          final matched = paths.where((a) => wanted.contains(a.id)).toList();
          targetAlbums = matched;
        } else {
          targetAlbums = paths.isNotEmpty ? [paths.first] : const [];
        }
        const pageSize = 200;
        for (final album in targetAlbums) {
          final total = await album.assetCountAsync;
          for (var page = 0; page * pageSize < total && page < 50; page++) {
            final list = await album.getAssetListPaged(page: page, size: pageSize);
            if (list.isEmpty) break;
            for (final asset in list) {
              if (alreadyBackedUpIds.contains(asset.id) || !seenIds.add(asset.id)) {
                continue;
              }
              final f = await asset.file;
              if (f == null || !await f.exists()) continue;
              out.add(
                PhotoBackupAsset(
                  id: asset.id,
                  filePath: f.path,
                  fileName: asset.title ?? p.basename(f.path),
                  modified: asset.modifiedDateTime,
                ),
              );
            }
          }
        }
      }
      for (final customDir in customDirs) {
        await _scanDirectoryAssets(customDir, alreadyBackedUpIds, seenIds, out);
      }
      return out;
    }

    // Desktop fallback: scan custom source folders (if set) or default gallery dirs.
    final scanDirs =
        customDirs.isNotEmpty ? customDirs : PlatformPaths.galleryDirs();
    for (final dirPath in scanDirs) {
      await _scanDirectoryAssets(dirPath, alreadyBackedUpIds, seenIds, out);
    }
    return out;
  }

  static Future<void> _defaultUploader({
    required PhotoBackupAsset asset,
    required String dstRoot,
    required String dstDir,
  }) async {
    final file = File(asset.filePath);
    final srcRoot = file.parent.path;
    final srcRel = p.basename(file.path);
    final taskId = await TaskService.instance.copy(
      srcRoot: srcRoot,
      srcPaths: [srcRel],
      dstRoot: dstRoot,
      dstDir: dstDir,
      conflictPolicy: 'skip',
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
          : 'Photo backup task failed (${lastProgress?.state ?? 'missing'})';
      throw StateError(lastProgress?.error ?? fallbackErr);
    }
  }
}
