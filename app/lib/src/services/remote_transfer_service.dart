import 'dart:convert';

import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/remotes.dart';
import 'storage_service.dart';

typedef BundleEncryptFn = String Function({
  required String plaintextJson,
  required String password,
});

typedef BundleDecryptFn = String Function({
  required String envelopeJson,
  required String password,
});

typedef SaveRemoteBatchFn =
    Future<({int saved, List<String> failedIds, List<String> failures})>
    Function(List<RemoteConfigDto> configs);

enum RemoteImportConflictStrategy { overwrite, skip, keepBoth }

enum RemoteImportItemAction { create, overwrite, skip, duplicate }

enum RemoteBundleErrorCode {
  emptyPassword,
  passwordTooShort,
  noRemotesSelected,
  invalidFormat,
  notEncrypted,
  wrongPasswordOrCorrupted,
  emptyBundle,
}

class RemoteBundleException implements Exception {
  final RemoteBundleErrorCode code;
  final String? detail;

  const RemoteBundleException(this.code, {this.detail});

  @override
  String toString() =>
      detail == null ? 'RemoteBundleException(${code.name})' : 'RemoteBundleException(${code.name}: $detail)';
}

class DecodedRemotesBundle {
  final List<RemoteConfigDto> remotes;
  final DateTime? exportedAt;
  final String sourceType;

  const DecodedRemotesBundle({
    required this.remotes,
    this.exportedAt,
    required this.sourceType,
  });
}

class RemoteImportPlanItem {
  final RemoteConfigDto original;
  final RemoteConfigDto resolved;
  final bool hasConflict;
  final RemoteImportItemAction action;

  const RemoteImportPlanItem({
    required this.original,
    required this.resolved,
    required this.hasConflict,
    required this.action,
  });
}

class RemoteBatchImportResult {
  final int added;
  final int overwritten;
  final int duplicated;
  final int skipped;
  final List<String> failures;

  const RemoteBatchImportResult({
    required this.added,
    required this.overwritten,
    required this.duplicated,
    required this.skipped,
    required this.failures,
  });

  int get totalImported => added + overwritten + duplicated;
}

class RemoteTransferService {
  RemoteTransferService._();

  static const String bundleType = 'fm_remotes_bundle';
  static const int bundleVersion = 1;
  static const String envelopeFormat = 'fp-migration-v1';
  static const String fileExtension = 'fmremotes';
  static const int minExportPasswordLength = 6;
  static const int maxImportFileBytes = 10 * 1024 * 1024;

  static bool isReadableRemote(RemoteConfigDto r) =>
      !StorageService.isUnreadableRemote(r);

  static bool looksLikeEncryptedEnvelope(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) return false;
      if (decoded['format'] != envelopeFormat) return false;
      final salt = decoded['salt'];
      final nonce = decoded['nonce'];
      final ciphertext = decoded['ciphertext'];
      return salt is String &&
          salt.isNotEmpty &&
          nonce is String &&
          nonce.isNotEmpty &&
          ciphertext is String &&
          ciphertext.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String suggestedExportFileName({DateTime? now}) {
    final dt = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${dt.year}${two(dt.month)}${two(dt.day)}-${two(dt.hour)}${two(dt.minute)}';
    return 'remotes-backup-$stamp.$fileExtension';
  }

  static String encryptRemotesBundle(
    List<RemoteConfigDto> remotes, {
    required String password,
    BundleEncryptFn? encryptFn,
    DateTime? now,
  }) {
    final readable = remotes.where(isReadableRemote).toList();
    if (readable.isEmpty) {
      throw const RemoteBundleException(RemoteBundleErrorCode.noRemotesSelected);
    }
    if (password.isEmpty) {
      throw const RemoteBundleException(RemoteBundleErrorCode.emptyPassword);
    }
    if (password.length < minExportPasswordLength) {
      throw const RemoteBundleException(RemoteBundleErrorCode.passwordTooShort);
    }

    final payload = <String, dynamic>{
      'type': bundleType,
      'version': bundleVersion,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'remotes': readable.map(StorageService.remoteConfigToMap).toList(),
    };

    final encrypt = encryptFn ?? meta_api.encryptMigrationBundle;
    return encrypt(plaintextJson: jsonEncode(payload), password: password);
  }

  static DecodedRemotesBundle decryptRemotesBundle(
    String rawContent, {
    required String password,
    BundleDecryptFn? decryptFn,
  }) {
    final trimmed = rawContent.trim();
    if (password.isEmpty) {
      throw const RemoteBundleException(RemoteBundleErrorCode.emptyPassword);
    }
    dynamic envelopeJson;
    try {
      envelopeJson = jsonDecode(trimmed);
    } catch (e) {
      throw RemoteBundleException(
        RemoteBundleErrorCode.invalidFormat,
        detail: '$e',
      );
    }
    if (envelopeJson is! Map<String, dynamic> && envelopeJson is! List) {
      throw const RemoteBundleException(RemoteBundleErrorCode.invalidFormat);
    }
    if (!looksLikeEncryptedEnvelope(trimmed)) {
      throw const RemoteBundleException(RemoteBundleErrorCode.notEncrypted);
    }

    final String plaintext;
    try {
      final decrypt = decryptFn ?? meta_api.decryptMigrationBundle;
      plaintext = decrypt(envelopeJson: trimmed, password: password);
    } catch (e) {
      throw RemoteBundleException(
        RemoteBundleErrorCode.wrongPasswordOrCorrupted,
        detail: '$e',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(plaintext);
    } catch (e) {
      throw RemoteBundleException(
        RemoteBundleErrorCode.invalidFormat,
        detail: '$e',
      );
    }

    List<dynamic>? rawList;
    DateTime? exportedAt;
    var sourceType = bundleType;

    if (decoded is Map<String, dynamic>) {
      final rawType = decoded['type'];
      if (rawType is String && rawType.isNotEmpty) {
        sourceType = rawType;
      } else if (decoded.containsKey('bookmarks') ||
          decoded.containsKey('preferences') ||
          decoded['version'] == 2) {
        sourceType = 'fp_migration_v2';
      }
      final rawExportedAt = decoded['exportedAt'];
      if (rawExportedAt is String && rawExportedAt.isNotEmpty) {
        exportedAt = DateTime.tryParse(rawExportedAt);
      }
      final remotesField = decoded['remotes'];
      if (remotesField is List) {
        rawList = remotesField;
      } else if (decoded.containsKey('kind') || decoded.containsKey('name')) {
        rawList = [decoded];
      }
    } else if (decoded is List) {
      rawList = decoded;
      sourceType = 'remotes_list';
    } else {
      throw const RemoteBundleException(RemoteBundleErrorCode.invalidFormat);
    }

    if (rawList == null) {
      throw const RemoteBundleException(RemoteBundleErrorCode.invalidFormat);
    }

    final parsed = <RemoteConfigDto>[];
    final synthesizedIds = <String>{};
    for (var i = 0; i < rawList.length; i++) {
      final entry = rawList[i];
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final dto = StorageService.remoteConfigFromMap(map);
      if (dto.name.trim().isEmpty && dto.kind.trim().isEmpty) continue;
      if (!isReadableRemote(dto)) continue;
      if (dto.id.trim().isEmpty) {
        final slug = _sanitizeIdSlug('${dto.kind}_${dto.name}');
        var candidate = slug.isEmpty ? '${dto.kind}_imported_$i' : slug;
        var suffix = 2;
        while (synthesizedIds.contains(candidate)) {
          candidate = '${slug.isEmpty ? '${dto.kind}_imported' : slug}_$suffix';
          suffix++;
        }
        synthesizedIds.add(candidate);
        parsed.add(_copyWithIdAndName(dto, id: candidate, name: dto.name));
      } else {
        synthesizedIds.add(dto.id);
        parsed.add(dto);
      }
    }

    if (parsed.isEmpty) {
      throw const RemoteBundleException(RemoteBundleErrorCode.emptyBundle);
    }

    return DecodedRemotesBundle(
      remotes: parsed,
      exportedAt: exportedAt,
      sourceType: sourceType,
    );
  }

  static List<RemoteImportPlanItem> buildImportPlan({
    required List<RemoteConfigDto> incoming,
    required List<RemoteConfigDto> existing,
    required RemoteImportConflictStrategy strategy,
  }) {
    final usedIds = existing.map((e) => e.id).toSet();
    final usedNames = existing.map((e) => e.name).toSet();
    final plan = <RemoteImportPlanItem>[];

    for (final item in incoming) {
      final hasConflict = usedIds.contains(item.id);
      if (!hasConflict) {
        usedIds.add(item.id);
        usedNames.add(item.name);
        plan.add(
          RemoteImportPlanItem(
            original: item,
            resolved: item,
            hasConflict: false,
            action: RemoteImportItemAction.create,
          ),
        );
        continue;
      }

      switch (strategy) {
        case RemoteImportConflictStrategy.overwrite:
          usedNames.add(item.name);
          plan.add(
            RemoteImportPlanItem(
              original: item,
              resolved: item,
              hasConflict: true,
              action: RemoteImportItemAction.overwrite,
            ),
          );
        case RemoteImportConflictStrategy.skip:
          plan.add(
            RemoteImportPlanItem(
              original: item,
              resolved: item,
              hasConflict: true,
              action: RemoteImportItemAction.skip,
            ),
          );
        case RemoteImportConflictStrategy.keepBoth:
          final newId = _uniqueCopyId(item.id, usedIds);
          final newName = _uniqueCopyName(item.name, usedNames);
          usedIds.add(newId);
          usedNames.add(newName);
          plan.add(
            RemoteImportPlanItem(
              original: item,
              resolved: _copyWithIdAndName(item, id: newId, name: newName),
              hasConflict: true,
              action: RemoteImportItemAction.duplicate,
            ),
          );
      }
    }
    return plan;
  }

  static Future<RemoteBatchImportResult> executeImportPlan({
    required List<RemoteImportPlanItem> plan,
    SaveRemoteBatchFn? saveBatchFn,
  }) async {
    final toSave = plan
        .where((item) => item.action != RemoteImportItemAction.skip)
        .toList();
    final skipped = plan.length - toSave.length;

    if (toSave.isEmpty) {
      return RemoteBatchImportResult(
        added: 0,
        overwritten: 0,
        duplicated: 0,
        skipped: skipped,
        failures: const [],
      );
    }

    final saveBatch = saveBatchFn ?? StorageService.instance.saveRemotesBatch;
    final res = await saveBatch(toSave.map((item) => item.resolved).toList());
    final remainingFailedIds = List<String>.of(res.failedIds);

    var added = 0;
    var overwritten = 0;
    var duplicated = 0;
    for (final item in toSave) {
      if (remainingFailedIds.remove(item.resolved.id)) {
        continue;
      }
      switch (item.action) {
        case RemoteImportItemAction.create:
          added++;
        case RemoteImportItemAction.overwrite:
          overwritten++;
        case RemoteImportItemAction.duplicate:
          duplicated++;
        case RemoteImportItemAction.skip:
          break;
      }
    }

    return RemoteBatchImportResult(
      added: added,
      overwritten: overwritten,
      duplicated: duplicated,
      skipped: skipped,
      failures: res.failures,
    );
  }

  static String _uniqueCopyId(String baseId, Set<String> usedIds) {
    var candidate = '${baseId}_copy';
    if (!usedIds.contains(candidate)) return candidate;
    var n = 2;
    while (true) {
      candidate = '${baseId}_copy_$n';
      if (!usedIds.contains(candidate)) return candidate;
      n++;
    }
  }

  static String _uniqueCopyName(String baseName, Set<String> usedNames) {
    var n = 2;
    while (true) {
      final candidate = '$baseName ($n)';
      if (!usedNames.contains(candidate)) return candidate;
      n++;
    }
  }

  static String _sanitizeIdSlug(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static RemoteConfigDto _copyWithIdAndName(
    RemoteConfigDto r, {
    required String id,
    required String name,
  }) =>
      RemoteConfigDto(
        id: id,
        name: name,
        kind: r.kind,
        endpoint: r.endpoint,
        bucket: r.bucket,
        region: r.region,
        accessKeyId: r.accessKeyId,
        secretAccessKey: r.secretAccessKey,
        host: r.host,
        port: r.port,
        username: r.username,
        password: r.password,
        privateKey: r.privateKey,
        passphrase: r.passphrase,
        rootPath: r.rootPath,
        pathStyle: r.pathStyle,
      );
}
