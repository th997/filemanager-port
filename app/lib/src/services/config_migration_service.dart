import 'dart:convert';

import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/pool.dart' as pool_api;
import '../rust/api/remotes.dart' as rem_api;
import 'pool_service.dart';
import 'preferences_service.dart';
import 'remote_transfer_service.dart';
import 'storage_service.dart';

enum MigrationEnvelopeKind {
  plaintext,
  fmbakEncrypted,
  legacyRemotesEncrypted,
}

class PoolRefInfo {
  final String id;
  final String name;
  final List<String> remoteIds;
  final int replicationFactor;
  final bool encrypted;

  const PoolRefInfo({
    required this.id,
    required this.name,
    required this.remoteIds,
    this.replicationFactor = 1,
    this.encrypted = false,
  });

  factory PoolRefInfo.fromSummary(pool_api.PoolSummaryDto p) => PoolRefInfo(
        id: p.id,
        name: p.name,
        remoteIds: p.nodes.map((n) => n.remoteId).toList(growable: false),
        replicationFactor: p.replicationFactor,
        encrypted: p.encrypted,
      );

  factory PoolRefInfo.fromConfig(pool_api.PoolConfigDto p) => PoolRefInfo(
        id: p.id,
        name: p.name,
        remoteIds: p.nodes.map((n) => n.remoteId).toList(growable: false),
        replicationFactor: p.replicationFactor,
        encrypted: p.encrypt,
      );
}

class ParsedConfigBundle {
  final List<rem_api.RemoteConfigDto> remotes;
  final List<pool_api.PoolConfigDto> pools;
  final List<meta_api.BookmarkDto> bookmarks;
  final Map<String, dynamic> preferences;
  final DateTime? exportedAt;
  final int version;

  const ParsedConfigBundle({
    this.remotes = const [],
    this.pools = const [],
    this.bookmarks = const [],
    this.preferences = const {},
    this.exportedAt,
    this.version = 3,
  });

  bool get hasRemotes => remotes.isNotEmpty;
  bool get hasPools => pools.isNotEmpty;
  bool get hasBookmarks => bookmarks.isNotEmpty;
  bool get hasPreferences => preferences.isNotEmpty;
  bool get isEmpty =>
      !hasRemotes && !hasPools && !hasBookmarks && !hasPreferences;
}

class ConfigExportResult {
  final String payload;
  final bool encrypted;
  final String suggestedFilename;
  final int remotesCount;
  final int poolsCount;
  final int bookmarksCount;
  final int preferencesCount;

  const ConfigExportResult({
    required this.payload,
    required this.encrypted,
    required this.suggestedFilename,
    required this.remotesCount,
    required this.poolsCount,
    required this.bookmarksCount,
    required this.preferencesCount,
  });
}

class ConfigImportResult {
  final int remotes;
  final int pools;
  final int bookmarks;
  final int preferences;
  final List<String> failedRemotes;
  final List<String> failedPools;

  const ConfigImportResult({
    required this.remotes,
    required this.pools,
    required this.bookmarks,
    required this.preferences,
    this.failedRemotes = const [],
    this.failedPools = const [],
  });
}

class ConfigMigrationService {
  ConfigMigrationService._();

  static final ConfigMigrationService instance = ConfigMigrationService._();

  static const int currentBundleVersion = 3;
  static const String envelopeFormat = 'fp-migration-v1';

  static Map<String, dynamic> poolConfigToMap(pool_api.PoolConfigDto c) => {
        'id': c.id,
        'name': c.name,
        'chunkSize': c.chunkSize,
        'replicationFactor': c.replicationFactor,
        'encrypt': c.encrypt,
        if (c.passphrase != null) 'passphrase': c.passphrase,
        if (c.kdfSalt != null) 'kdfSalt': c.kdfSalt,
        'nodes': c.nodes
            .map(
              (n) => <String, dynamic>{
                'nodeId': n.nodeId,
                'remoteId': n.remoteId,
                'basePrefix': n.basePrefix,
                'failureDomain': n.failureDomain,
                'quotaBytes': n.quotaBytes.toString(),
                'weight': n.weight,
                'role': n.role,
                'isMetaBackup': n.isMetaBackup,
              },
            )
            .toList(),
      };

  static BigInt _parseBigInt(dynamic value) {
    if (value is BigInt) return value;
    if (value is int) return BigInt.from(value);
    if (value is num) return BigInt.from(value.toInt());
    if (value is String) {
      return BigInt.tryParse(value.trim()) ?? BigInt.zero;
    }
    return BigInt.zero;
  }

  static pool_api.PoolConfigDto poolConfigFromMap(Map<String, dynamic> m) {
    final rawNodes = m['nodes'];
    final nodes = <pool_api.PoolNodeConfigDto>[];
    if (rawNodes is List) {
      for (final item in rawNodes) {
        if (item is! Map) continue;
        final nm = item.cast<String, dynamic>();
        nodes.add(
          pool_api.PoolNodeConfigDto(
            nodeId: nm['nodeId']?.toString() ?? '',
            remoteId: nm['remoteId']?.toString() ?? '',
            basePrefix: nm['basePrefix']?.toString() ?? '',
            failureDomain: nm['failureDomain']?.toString() ?? 'default',
            quotaBytes: _parseBigInt(nm['quotaBytes']),
            weight: (nm['weight'] as num?)?.toInt() ?? 100,
            role: nm['role']?.toString() ?? 'data_and_meta',
            isMetaBackup: nm['isMetaBackup'] as bool? ?? false,
          ),
        );
      }
    }
    return pool_api.PoolConfigDto(
      id: m['id']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      chunkSize: (m['chunkSize'] as num?)?.toInt() ?? (4 * 1024 * 1024),
      replicationFactor: (m['replicationFactor'] as num?)?.toInt() ?? 1,
      encrypt: m['encrypt'] as bool? ?? false,
      passphrase: m['passphrase']?.toString(),
      kdfSalt: m['kdfSalt']?.toString(),
      nodes: nodes,
    );
  }

  static Set<String> requiredRemoteIdsForRefs({
    required Iterable<String> selectedPoolIds,
    required Iterable<PoolRefInfo> pools,
  }) {
    final selectedSet = selectedPoolIds.toSet();
    final requiredIds = <String>{};
    for (final p in pools) {
      if (!selectedSet.contains(p.id)) continue;
      for (final remoteId in p.remoteIds) {
        if (remoteId.isNotEmpty) {
          requiredIds.add(remoteId);
        }
      }
    }
    return requiredIds;
  }

  static Map<String, List<String>> dependentPoolNamesByRemoteForRefs({
    required Iterable<String> selectedPoolIds,
    required Iterable<PoolRefInfo> pools,
  }) {
    final selectedSet = selectedPoolIds.toSet();
    final result = <String, List<String>>{};
    for (final p in pools) {
      if (!selectedSet.contains(p.id)) continue;
      for (final remoteId in p.remoteIds) {
        if (remoteId.isEmpty) continue;
        final list = result.putIfAbsent(remoteId, () => <String>[]);
        if (!list.contains(p.name)) {
          list.add(p.name);
        }
      }
    }
    return result;
  }

  static Set<String> requiredRemoteIdsForPoolSummaries({
    required Iterable<String> selectedPoolIds,
    required List<pool_api.PoolSummaryDto> pools,
  }) =>
      requiredRemoteIdsForRefs(
        selectedPoolIds: selectedPoolIds,
        pools: pools.map(PoolRefInfo.fromSummary),
      );

  static Map<String, List<String>> dependentPoolNamesByRemoteForSummaries({
    required Iterable<String> selectedPoolIds,
    required List<pool_api.PoolSummaryDto> pools,
  }) =>
      dependentPoolNamesByRemoteForRefs(
        selectedPoolIds: selectedPoolIds,
        pools: pools.map(PoolRefInfo.fromSummary),
      );

  static Set<String> requiredRemoteIdsForPoolConfigs({
    required Iterable<String> selectedPoolIds,
    required List<pool_api.PoolConfigDto> pools,
  }) =>
      requiredRemoteIdsForRefs(
        selectedPoolIds: selectedPoolIds,
        pools: pools.map(PoolRefInfo.fromConfig),
      );

  static Map<String, List<String>> dependentPoolNamesByRemoteForConfigs({
    required Iterable<String> selectedPoolIds,
    required List<pool_api.PoolConfigDto> pools,
  }) =>
      dependentPoolNamesByRemoteForRefs(
        selectedPoolIds: selectedPoolIds,
        pools: pools.map(PoolRefInfo.fromConfig),
      );

  static bool requiresPassword({
    required Iterable<String> selectedRemoteIds,
    required Iterable<String> selectedPoolIds,
  }) =>
      selectedRemoteIds.isNotEmpty || selectedPoolIds.isNotEmpty;

  static MigrationEnvelopeKind detectEnvelopeKind(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return MigrationEnvelopeKind.plaintext;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return MigrationEnvelopeKind.plaintext;
      }
      final salt = decoded['salt'];
      final nonce = decoded['nonce'];
      final ciphertext = decoded['ciphertext'];
      final hasCipherFields = salt is String &&
          salt.isNotEmpty &&
          nonce is String &&
          nonce.isNotEmpty &&
          ciphertext is String &&
          ciphertext.isNotEmpty;
      if (!hasCipherFields) {
        return MigrationEnvelopeKind.plaintext;
      }
      final fmt = decoded['format']?.toString() ?? '';
      if (fmt == 'fm-remotes-v1') {
        return MigrationEnvelopeKind.legacyRemotesEncrypted;
      }
      if (fmt == envelopeFormat ||
          fmt == 'fm-migration-v1' ||
          decoded.containsKey('kdf') ||
          decoded.containsKey('cipher')) {
        return MigrationEnvelopeKind.fmbakEncrypted;
      }
      return MigrationEnvelopeKind.fmbakEncrypted;
    } catch (_) {
      return MigrationEnvelopeKind.plaintext;
    }
  }

  static ConfigExportResult encodeSelectiveBundle({
    required List<rem_api.RemoteConfigDto> remotes,
    required List<pool_api.PoolConfigDto> pools,
    required List<meta_api.BookmarkDto> bookmarks,
    required Map<String, dynamic> preferences,
    required bool includeBookmarks,
    required bool includePreferences,
    String password = '',
    BundleEncryptFn? encryptFn,
    DateTime? now,
  }) {
    final requiredByPools = requiredRemoteIdsForPoolConfigs(
      selectedPoolIds: pools.map((p) => p.id),
      pools: pools,
    );
    final selectedRemoteSet = {
      for (final r in remotes) r.id,
      ...requiredByPools,
    };
    final effectiveRemotes = remotes
        .where((r) => selectedRemoteSet.contains(r.id))
        .toList(growable: false);

    if (requiresPassword(
          selectedRemoteIds: selectedRemoteSet,
          selectedPoolIds: pools.map((p) => p.id),
        ) &&
        password.isEmpty) {
      throw ArgumentError(
        'Encryption password is required when exporting remote connections or storage pools.',
      );
    }

    final exportedBookmarks =
        includeBookmarks ? bookmarks : const <meta_api.BookmarkDto>[];
    final exportedPrefs =
        includePreferences ? preferences : const <String, dynamic>{};

    final sections = <String>[
      if (effectiveRemotes.isNotEmpty) 'remotes',
      if (pools.isNotEmpty) 'pools',
      if (includeBookmarks && exportedBookmarks.isNotEmpty) 'bookmarks',
      if (includePreferences) 'preferences',
    ];

    final payloadMap = <String, dynamic>{
      'version': currentBundleVersion,
      'exportedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'sections': sections,
      if (effectiveRemotes.isNotEmpty)
        'remotes': effectiveRemotes.map(StorageService.remoteConfigToMap).toList(),
      if (pools.isNotEmpty) 'pools': pools.map(poolConfigToMap).toList(),
      if (includeBookmarks)
        'bookmarks': exportedBookmarks.map(StorageService.bookmarkToMap).toList(),
      if (includePreferences) 'preferences': exportedPrefs,
    };

    final encrypted = password.isNotEmpty;
    final payload = encrypted
        ? (encryptFn ?? meta_api.encryptMigrationBundle)(
            plaintextJson: jsonEncode(payloadMap),
            password: password,
          )
        : const JsonEncoder.withIndent('  ').convert(payloadMap);

    return ConfigExportResult(
      payload: payload,
      encrypted: encrypted,
      suggestedFilename:
          encrypted ? 'filemanager_backup.fmbak' : 'filemanager_config.json',
      remotesCount: effectiveRemotes.length,
      poolsCount: pools.length,
      bookmarksCount: exportedBookmarks.length,
      preferencesCount: exportedPrefs.length,
    );
  }

  Future<ConfigExportResult> exportSelectiveBundle({
    required Set<String> selectedRemoteIds,
    required Set<String> selectedPoolIds,
    required bool includeBookmarks,
    required bool includePreferences,
    required String password,
    BundleEncryptFn? encryptFn,
  }) async {
    StorageService.instance.ensureInitialized();

    final pools = selectedPoolIds.isNotEmpty
        ? await PoolService.instance.exportConfigs(selectedPoolIds.toList())
        : const <pool_api.PoolConfigDto>[];

    final requiredByPools = requiredRemoteIdsForPoolConfigs(
      selectedPoolIds: pools.map((p) => p.id),
      pools: pools,
    );
    final effectiveRemoteIds = <String>{
      ...selectedRemoteIds,
      ...requiredByPools,
    };

    if (requiresPassword(
          selectedRemoteIds: effectiveRemoteIds,
          selectedPoolIds: pools.map((p) => p.id),
        ) &&
        password.isEmpty) {
      throw ArgumentError(
        'Encryption password is required when exporting remote connections or storage pools.',
      );
    }

    final allRemotes = effectiveRemoteIds.isNotEmpty
        ? await StorageService.instance.getRemotes()
        : const <rem_api.RemoteConfigDto>[];
    final selectedRemotes = allRemotes
        .where((r) => effectiveRemoteIds.contains(r.id))
        .toList(growable: false);

    final bookmarks = includeBookmarks
        ? await StorageService.instance.getBookmarks()
        : const <meta_api.BookmarkDto>[];
    final preferences = includePreferences
        ? PreferencesService.instance.exportPreferencesMap()
        : const <String, dynamic>{};

    return encodeSelectiveBundle(
      remotes: selectedRemotes,
      pools: pools,
      bookmarks: bookmarks,
      preferences: preferences,
      includeBookmarks: includeBookmarks,
      includePreferences: includePreferences,
      password: password,
      encryptFn: encryptFn,
    );
  }

  static ParsedConfigBundle decodeBundle(
    String rawText, {
    String? password,
    BundleDecryptFn? decryptFn,
  }) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty configuration payload.');
    }
    final kind = detectEnvelopeKind(trimmed);
    switch (kind) {
      case MigrationEnvelopeKind.legacyRemotesEncrypted:
        final decodedRemotes = RemoteTransferService.decryptRemotesBundle(
          trimmed,
          password: password ?? '',
          decryptFn: decryptFn,
        );
        return ParsedConfigBundle(
          remotes: decodedRemotes.remotes,
          exportedAt: decodedRemotes.exportedAt,
          version: 1,
        );
      case MigrationEnvelopeKind.fmbakEncrypted:
        if (password == null || password.isEmpty) {
          throw ArgumentError('Decryption password is required.');
        }
        final plaintext = (decryptFn ?? meta_api.decryptMigrationBundle)(
          envelopeJson: trimmed,
          password: password,
        );
        return _parsePlaintextPayload(plaintext);
      case MigrationEnvelopeKind.plaintext:
        return _parsePlaintextPayload(trimmed);
    }
  }

  static ParsedConfigBundle _parsePlaintextPayload(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is List) {
      final remotes = _parseRemotesList(decoded);
      if (remotes.isEmpty) {
        throw const FormatException('No valid configuration entries found.');
      }
      return ParsedConfigBundle(remotes: remotes, version: 1);
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid configuration bundle JSON.');
    }
    final map = decoded.cast<String, dynamic>();

    // Single raw remote object fallback.
    final looksSingleRemote = !map.containsKey('remotes') &&
        !map.containsKey('pools') &&
        !map.containsKey('bookmarks') &&
        !map.containsKey('preferences') &&
        (map.containsKey('kind') || map.containsKey('host'));
    if (looksSingleRemote) {
      final remotes = _parseRemotesList([map]);
      return ParsedConfigBundle(remotes: remotes, version: 1);
    }

    final remotes = map['remotes'] is List
        ? _parseRemotesList(map['remotes'] as List)
        : const <rem_api.RemoteConfigDto>[];

    final pools = <pool_api.PoolConfigDto>[];
    final seenPoolIds = <String>{};
    if (map['pools'] is List) {
      for (final item in map['pools'] as List) {
        if (item is! Map) continue;
        final pool = poolConfigFromMap(item.cast<String, dynamic>());
        if (pool.name.trim().isEmpty || pool.nodes.isEmpty) continue;
        final normalizedId =
            pool.id.trim().isEmpty ? 'pool_${pools.length + 1}' : pool.id;
        if (!seenPoolIds.add(normalizedId)) continue;
        pools.add(
          normalizedId == pool.id
              ? pool
              : pool_api.PoolConfigDto(
                  id: normalizedId,
                  name: pool.name,
                  chunkSize: pool.chunkSize,
                  replicationFactor: pool.replicationFactor,
                  encrypt: pool.encrypt,
                  passphrase: pool.passphrase,
                  kdfSalt: pool.kdfSalt,
                  nodes: pool.nodes,
                ),
        );
      }
    }

    final bookmarks = <meta_api.BookmarkDto>[];
    if (map['bookmarks'] is List) {
      for (final item in map['bookmarks'] as List) {
        if (item is! Map) continue;
        final bm = StorageService.bookmarkFromMap(item.cast<String, dynamic>());
        if (bm.name.trim().isEmpty || bm.root.trim().isEmpty) continue;
        bookmarks.add(bm);
      }
    }

    final preferences = map['preferences'] is Map
        ? (map['preferences'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    final exportedAt = map['exportedAt'] is String
        ? DateTime.tryParse(map['exportedAt'] as String)
        : null;
    final version = (map['version'] as num?)?.toInt() ?? 1;

    return ParsedConfigBundle(
      remotes: remotes,
      pools: pools,
      bookmarks: bookmarks,
      preferences: preferences,
      exportedAt: exportedAt,
      version: version,
    );
  }

  static List<rem_api.RemoteConfigDto> _parseRemotesList(List<dynamic> rawList) {
    final result = <rem_api.RemoteConfigDto>[];
    final usedIds = <String>{};
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) continue;
      final dto = StorageService.remoteConfigFromMap(item.cast<String, dynamic>());
      if (dto.name.trim().isEmpty && dto.kind.trim().isEmpty) continue;
      if (dto.id.trim().isEmpty) {
        final slug = '${dto.kind}_${dto.name}'
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), '');
        var candidate = slug.isEmpty ? 'remote_${i + 1}' : slug;
        var suffix = 2;
        while (!usedIds.add(candidate)) {
          candidate = '${slug.isEmpty ? 'remote' : slug}_$suffix';
          suffix++;
        }
        result.add(
          rem_api.RemoteConfigDto(
            id: candidate,
            name: dto.name,
            kind: dto.kind,
            endpoint: dto.endpoint,
            bucket: dto.bucket,
            region: dto.region,
            accessKeyId: dto.accessKeyId,
            secretAccessKey: dto.secretAccessKey,
            host: dto.host,
            port: dto.port,
            username: dto.username,
            password: dto.password,
            privateKey: dto.privateKey,
            passphrase: dto.passphrase,
            rootPath: dto.rootPath,
            pathStyle: dto.pathStyle,
          ),
        );
      } else {
        if (!usedIds.add(dto.id)) continue;
        result.add(dto);
      }
    }
    return result;
  }

  Future<ConfigImportResult> applySelectiveImport({
    required ParsedConfigBundle bundle,
    required Set<String> selectedRemoteIds,
    required Set<String> selectedPoolIds,
    required bool includeBookmarks,
    required bool includePreferences,
  }) async {
    StorageService.instance.ensureInitialized();

    final requiredRemoteIds = requiredRemoteIdsForPoolConfigs(
      selectedPoolIds: selectedPoolIds,
      pools: bundle.pools,
    );
    final effectiveRemoteIds = <String>{
      ...selectedRemoteIds,
      ...requiredRemoteIds,
    };

    // 1. Import selected remotes FIRST so pool member remoteId references exist.
    var importedRemotes = 0;
    var failedRemotes = const <String>[];
    final remotesToSave = bundle.remotes
        .where((r) => effectiveRemoteIds.contains(r.id))
        .toList(growable: false);
    if (remotesToSave.isNotEmpty) {
      final res = await StorageService.instance.saveRemotesBatch(remotesToSave);
      importedRemotes = res.saved;
      failedRemotes = res.failures;
    }

    // 2. Import selected storage pools SECOND.
    var importedPools = 0;
    final failedPools = <String>[];
    final poolsToSave = bundle.pools
        .where((p) => selectedPoolIds.contains(p.id))
        .toList(growable: false);
    if (poolsToSave.isNotEmpty) {
      for (final pool in poolsToSave) {
        try {
          await pool_api.savePoolConfig(
            dbPath: StorageService.instance.dbPath,
            config: pool,
          );
          importedPools++;
        } catch (_) {
          failedPools.add(pool.name);
        }
      }
      try {
        await PoolService.instance.refresh();
      } catch (_) {}
    }

    // 3. Import favorites (deduplicating against existing root+path pairs).
    var importedBookmarks = 0;
    if (includeBookmarks && bundle.bookmarks.isNotEmpty) {
      final existing = await StorageService.instance.getBookmarks();
      final seenKeys = <String>{
        for (final b in existing) '${b.root}\u0000${b.path}',
      };
      for (final b in bundle.bookmarks) {
        if (b.name.trim().isEmpty || b.root.trim().isEmpty) continue;
        final key = '${b.root}\u0000${b.path}';
        if (!seenKeys.add(key)) continue;
        try {
          await StorageService.instance.addBookmark(
            name: b.name,
            root: b.root,
            path: b.path,
          );
          importedBookmarks++;
        } catch (_) {}
      }
    }

    // 4. Import preferences.
    var importedPrefs = 0;
    if (includePreferences && bundle.preferences.isNotEmpty) {
      importedPrefs =
          PreferencesService.instance.importPreferencesMap(bundle.preferences);
    }

    return ConfigImportResult(
      remotes: importedRemotes,
      pools: importedPools,
      bookmarks: importedBookmarks,
      preferences: importedPrefs,
      failedRemotes: failedRemotes,
      failedPools: failedPools,
    );
  }
}
