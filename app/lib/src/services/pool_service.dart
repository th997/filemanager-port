import 'package:flutter/foundation.dart';

import '../rust/api/pool.dart' as pool_api;
import 'storage_service.dart';

class PoolService extends ChangeNotifier {
  static final PoolService instance = PoolService._();
  PoolService._();

  List<pool_api.PoolSummaryDto> _pools = [];
  bool _loaded = false;

  List<pool_api.PoolSummaryDto> get pools => List.unmodifiable(_pools);
  bool get hasLoaded => _loaded;

  String get _dbPath => StorageService.instance.dbPath;

  pool_api.PoolSummaryDto? findById(String id) {
    for (final p in _pools) {
      if (p.id == id) return p;
    }
    return null;
  }

  pool_api.PoolSummaryDto? findByIdOrName(String idOrName) {
    final q = idOrName.trim().toLowerCase();
    for (final p in _pools) {
      if (p.id == idOrName || p.name.toLowerCase() == q) {
        return p;
      }
    }
    return null;
  }

  Future<List<pool_api.PoolSummaryDto>> refresh() async {
    StorageService.instance.ensureInitialized();
    final list = await pool_api.listPools(dbPath: _dbPath);
    _pools = list;
    _loaded = true;
    notifyListeners();
    return list;
  }

  Future<pool_api.PoolConfigDto> getConfig(String poolId) async {
    StorageService.instance.ensureInitialized();
    return pool_api.getPoolConfig(dbPath: _dbPath, poolId: poolId);
  }

  Future<List<pool_api.PoolConfigDto>> exportConfigs(List<String> poolIds) async {
    StorageService.instance.ensureInitialized();
    return pool_api.exportPoolConfigs(
      dbPath: _dbPath,
      poolIds: poolIds,
    );
  }

  Future<pool_api.PoolSummaryDto> saveConfig(pool_api.PoolConfigDto config) async {
    StorageService.instance.ensureInitialized();
    final summary = await pool_api.savePoolConfig(dbPath: _dbPath, config: config);
    await refresh();
    return summary;
  }

  Future<pool_api.PoolRemoteCleanupReportDto> deletePool(
    String poolId, {
    bool deleteRemoteData = false,
  }) async {
    StorageService.instance.ensureInitialized();
    final report = await pool_api.deletePool(
      dbPath: _dbPath,
      poolId: poolId,
      deleteRemoteData: deleteRemoteData,
    );
    _pools = _pools.where((p) => p.id != poolId).toList();
    notifyListeners();
    return report;
  }

  Future<List<pool_api.PoolNodeStatusDto>> probeHealth(String poolId) async {
    final statuses = await pool_api.probePoolHealth(poolId: poolId);
    await refresh();
    return statuses;
  }

  Future<List<pool_api.PoolNodeStatusDto>> probeSpace(String poolId) async {
    final statuses = await pool_api.probePoolSpace(poolId: poolId);
    await refresh();
    return statuses;
  }

  Future<pool_api.PoolSyncReportDto> syncMetadata(String poolId) async {
    final report = await pool_api.syncPoolMetadata(poolId: poolId);
    await refresh();
    return report;
  }

  Future<String> startHeal(String poolId) {
    return pool_api.startPoolHealTask(poolId: poolId);
  }

  Future<String> startDrain(
    String poolId,
    String nodeId, {
    bool deleteRemoteData = false,
  }) {
    StorageService.instance.ensureInitialized();
    return pool_api.startPoolDrainTask(
      dbPath: _dbPath,
      poolId: poolId,
      nodeId: nodeId,
      deleteRemoteData: deleteRemoteData,
    );
  }

  Future<pool_api.PoolRemoteCleanupReportDto> setNodeOffline(
    String poolId,
    String nodeId, {
    bool deleteRemoteData = false,
  }) async {
    StorageService.instance.ensureInitialized();
    final report = await pool_api.setPoolNodeOffline(
      dbPath: _dbPath,
      poolId: poolId,
      nodeId: nodeId,
      deleteRemoteData: deleteRemoteData,
    );
    await refresh();
    return report;
  }

  Future<pool_api.PoolSummaryDto> setNodeOnline(
    String poolId,
    String nodeId,
  ) async {
    StorageService.instance.ensureInitialized();
    final summary = await pool_api.setPoolNodeOnline(
      dbPath: _dbPath,
      poolId: poolId,
      nodeId: nodeId,
    );
    await refresh();
    return summary;
  }

  Future<pool_api.PoolRemoteCleanupReportDto> removeNode(
    String poolId,
    String nodeId, {
    bool deleteRemoteData = false,
  }) async {
    StorageService.instance.ensureInitialized();
    final report = await pool_api.removePoolNode(
      dbPath: _dbPath,
      poolId: poolId,
      nodeId: nodeId,
      deleteRemoteData: deleteRemoteData,
    );
    await refresh();
    return report;
  }

  Future<String> startGc(String poolId, {bool purgeImmediately = false}) {
    return pool_api.startPoolGcTask(
      poolId: poolId,
      purgeImmediately: purgeImmediately,
    );
  }
}
