import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/pool_editor_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/pool.dart';
import '../rust/api/remotes.dart';
import '../services/pool_service.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_swipe_back.dart';
import 'browser_page.dart';

class PoolDashboardPage extends StatefulWidget {
  final bool embedded;
  final void Function(PoolSummaryDto pool)? onOpenPool;
  @visibleForTesting
  final List<PoolSummaryDto>? initialPoolsOverride;
  @visibleForTesting
  final List<RemoteConfigDto>? remotesOverride;
  @visibleForTesting
  final Future<void> Function(String poolId, bool deleteRemoteData)?
      onDeletePoolOverride;
  @visibleForTesting
  final Future<void> Function(
    String poolId,
    String nodeId,
    bool deleteRemoteData,
  )? onDrainNodeOverride;
  @visibleForTesting
  final Future<void> Function(
    String poolId,
    String nodeId,
    bool deleteRemoteData,
  )? onOfflineNodeOverride;
  @visibleForTesting
  final Future<void> Function(String poolId, String nodeId)?
      onOnlineNodeOverride;
  @visibleForTesting
  final Future<void> Function(
    String poolId,
    String nodeId,
    bool deleteRemoteData,
  )? onRemoveNodeOverride;

  static bool isRemoteKindSpaceSupported(String? kind) {
    final lower = kind?.trim().toLowerCase();
    return lower != 's3' && lower != 'oss' && lower != 'ftp';
  }

  const PoolDashboardPage({
    super.key,
    this.embedded = false,
    this.onOpenPool,
    this.initialPoolsOverride,
    this.remotesOverride,
    this.onDeletePoolOverride,
    this.onDrainNodeOverride,
    this.onOfflineNodeOverride,
    this.onOnlineNodeOverride,
    this.onRemoveNodeOverride,
  });

  @override
  State<PoolDashboardPage> createState() => _PoolDashboardPageState();
}

class _PoolDashboardPageState extends State<PoolDashboardPage> {
  static const int _maxReplicationFactor = 16;

  List<PoolSummaryDto> _pools = [];
  List<RemoteConfigDto> _remotes = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _busy = false;
  String? _selectedPoolId;
  final Set<String> _autoProbedPools = {};
  final Set<String> _probingPoolIds = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialPoolsOverride != null) {
      _pools = widget.initialPoolsOverride!;
      _remotes = widget.remotesOverride ?? const [];
      _selectedPoolId = _pools.isNotEmpty ? _pools.first.id : null;
      _loading = false;
    } else {
      PoolService.instance.addListener(_onPoolServiceChanged);
      _load();
    }
  }

  @override
  void dispose() {
    if (widget.initialPoolsOverride == null) {
      PoolService.instance.removeListener(_onPoolServiceChanged);
    }
    super.dispose();
  }

  void _onPoolServiceChanged() {
    if (!mounted) return;
    final pools = PoolService.instance.pools;
    setState(() {
      _pools = pools;
      if (_selectedPoolId == null || !pools.any((p) => p.id == _selectedPoolId)) {
        _selectedPoolId = pools.isNotEmpty ? pools.first.id : null;
      }
    });
  }

  Future<void> _load({bool forceSpaceProbe = false}) async {
    if (forceSpaceProbe) {
      _autoProbedPools.clear();
    }
    setState(() {
      if (_pools.isEmpty) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    try {
      final results = await Future.wait([
        PoolService.instance.refresh(),
        StorageService.instance.getRemotes(),
      ]);
      if (!mounted) return;
      final pools = results[0] as List<PoolSummaryDto>;
      final remotes = results[1] as List<RemoteConfigDto>;
      setState(() {
        _pools = pools;
        _remotes = remotes;
        if (_selectedPoolId == null ||
            !pools.any((p) => p.id == _selectedPoolId)) {
          _selectedPoolId = pools.isNotEmpty ? pools.first.id : null;
        }
        _loading = false;
        _refreshing = false;
      });
      _scheduleBackgroundSpaceProbe(_selectedPool);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
        _showSnack('$e', isError: true);
      }
    }
  }

  void _scheduleBackgroundSpaceProbe(PoolSummaryDto? pool) {
    if (widget.initialPoolsOverride != null || pool == null) return;
    if (_autoProbedPools.contains(pool.id) ||
        _probingPoolIds.contains(pool.id)) {
      return;
    }
    _autoProbedPools.add(pool.id);
    final hasSpaceTarget = pool.nodes.any(
      (n) => n.role != 'offline' && _nodeSupportsSpaceQuery(n),
    );
    if (!hasSpaceTarget) return;
    _runBackgroundSpaceProbe(pool.id);
  }

  Future<void> _runBackgroundSpaceProbe(String poolId) async {
    if (mounted) {
      setState(() => _probingPoolIds.add(poolId));
    }
    try {
      await PoolService.instance.probeSpace(poolId);
    } catch (_) {
      // Background probe fails softly; manual probe reports detailed errors.
    } finally {
      if (mounted) {
        setState(() => _probingPoolIds.remove(poolId));
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  PoolSummaryDto? get _selectedPool {
    if (_pools.isEmpty) return null;
    for (final p in _pools) {
      if (p.id == _selectedPoolId) return p;
    }
    return _pools.first;
  }

  String _remoteNameOf(String remoteId) {
    for (final r in _remotes) {
      if (r.id == remoteId) return r.name;
    }
    return remoteId;
  }

  String? _remoteKindOf(String remoteId) {
    for (final r in _remotes) {
      if (r.id == remoteId) return r.kind;
    }
    return null;
  }

  bool _nodeSupportsSpaceQuery(PoolNodeStatusDto node) {
    if (node.spaceSupported == false) return false;
    return PoolDashboardPage.isRemoteKindSpaceSupported(
      _remoteKindOf(node.remoteId),
    );
  }

  Future<({bool confirmed, bool deleteRemote})?>
      _showConfirmWithRemoteDeleteOption({
    required String title,
    required String message,
    required String confirmLabel,
    required String checkboxLabel,
    required String dangerHint,
    bool confirmDestructive = true,
  }) {
    var deleteRemote = false;
    return showDialog<({bool confirmed, bool deleteRemote})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final l10n = AppLocalizations.of(ctx);
          final scheme = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: deleteRemote,
                    title: Text(
                      checkboxLabel,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onChanged: (v) =>
                        setDialogState(() => deleteRemote = v ?? false),
                  ),
                  if (deleteRemote)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        dangerHint,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: confirmDestructive || deleteRemote
                    ? FilledButton.styleFrom(backgroundColor: scheme.error)
                    : null,
                onPressed: () => Navigator.of(ctx).pop(
                  (confirmed: true, deleteRemote: deleteRemote),
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCleanupReportSnack(PoolRemoteCleanupReportDto report) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final failed = report.failedObjects.toInt();
    final deleted = report.deletedObjects.toInt();
    if (failed > 0 || report.failedNodes.isNotEmpty) {
      final nodes = report.failedNodes.map(_remoteNameOf).join(', ');
      _showSnack(
        l10n.poolRemoteCleanupPartial(deleted, failed, nodes),
        isError: true,
      );
    } else {
      _showSnack(l10n.poolRemoteCleanupDone(deleted));
    }
  }

  Future<void> _createPool() async {
    final remotes = _remotes.isNotEmpty
        ? _remotes
        : await StorageService.instance.getRemotes();
    if (!mounted) return;
    final dto = await PoolEditorDialog.show(context, remotes: remotes);
    if (dto == null || !mounted) return;
    try {
      final created = await PoolService.instance.saveConfig(dto);
      _selectedPoolId = created.id;
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _editPool(PoolSummaryDto pool) async {
    try {
      final cfg = await PoolService.instance.getConfig(pool.id);
      if (!mounted) return;
      final updated = await PoolEditorDialog.show(
        context,
        existing: cfg,
        remotes: _remotes,
      );
      if (updated == null || !mounted) return;
      await PoolService.instance.saveConfig(updated);
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _deletePool(PoolSummaryDto pool) async {
    final l10n = AppLocalizations.of(context);
    final choice = await _showConfirmWithRemoteDeleteOption(
      title: l10n.delete,
      message: l10n.poolDeleteConfirm(pool.name),
      confirmLabel: l10n.delete,
      checkboxLabel: l10n.poolDeleteRemoteDataOption,
      dangerHint: l10n.poolDeleteRemoteDataWarning,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    try {
      if (widget.onDeletePoolOverride != null) {
        await widget.onDeletePoolOverride!(pool.id, choice.deleteRemote);
        return;
      }
      final report = await PoolService.instance.deletePool(
        pool.id,
        deleteRemoteData: choice.deleteRemote,
      );
      await _load();
      if (choice.deleteRemote) {
        _showCleanupReportSnack(report);
      }
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _probeHealth(PoolSummaryDto pool) async {
    _autoProbedPools.add(pool.id);
    setState(() {
      _busy = true;
      _probingPoolIds.add(pool.id);
    });
    try {
      await PoolService.instance.probeHealth(pool.id);
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _probingPoolIds.remove(pool.id);
        });
      }
    }
  }

  Future<void> _editReplicationFactor(PoolSummaryDto pool) async {
    final l10n = AppLocalizations.of(context);
    final maxAllowed = [1, pool.nodes.length, pool.replicationFactor]
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, _maxReplicationFactor);
    int selected = pool.replicationFactor.clamp(1, maxAllowed);
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.poolSetReplicationTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.poolReplicationFactorLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (int r = 1; r <= maxAllowed; r++)
                    DropdownMenuItem(value: r, child: Text('${r}x')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selected = v);
                },
              ),
              const SizedBox(height: 10),
              Text(
                l10n.poolSetReplicationHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(selected),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == pool.replicationFactor || !mounted) return;
    if (picked > pool.nodes.length) {
      _showSnack(l10n.poolMinNodesError(picked), isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final cfg = await PoolService.instance.getConfig(pool.id);
      if (!mounted) return;
      await PoolService.instance.saveConfig(
        PoolConfigDto(
          id: cfg.id,
          name: cfg.name,
          chunkSize: cfg.chunkSize,
          replicationFactor: picked,
          encrypt: cfg.encrypt,
          passphrase: cfg.passphrase,
          kdfSalt: cfg.kdfSalt,
          nodes: cfg.nodes,
        ),
      );
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncMetadata(PoolSummaryDto pool) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final report = await PoolService.instance.syncMetadata(pool.id);
      await _load();
      _showSnack(
        l10n.poolSyncDone(
          report.action,
          report.finalVersion.toInt(),
          report.uploadedBackups,
          report.conflictsCreated,
        ),
      );
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runHeal(PoolSummaryDto pool) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final taskId = await PoolService.instance.startHeal(pool.id);
      if (!mounted) return;
      await TaskProgressDialog.show(context, taskId, l10n.poolHeal);
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runGc(PoolSummaryDto pool) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.poolConfirmGcTitle),
        content: Text(l10n.poolConfirmGcBody(pool.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.poolGc),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final taskId = await PoolService.instance.startGc(
        pool.id,
        purgeImmediately: true,
      );
      if (!mounted) return;
      await TaskProgressDialog.show(context, taskId, l10n.poolGc);
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDrain(PoolSummaryDto pool, PoolNodeStatusDto node) async {
    final l10n = AppLocalizations.of(context);
    final label = _remoteNameOf(node.remoteId);
    final choice = await _showConfirmWithRemoteDeleteOption(
      title: l10n.poolDrainNode,
      message: l10n.poolDrainConfirm(label),
      confirmLabel: l10n.poolDrainNode,
      checkboxLabel: l10n.poolDeleteNodeRemoteDataOption,
      dangerHint: l10n.poolDeleteNodeRemoteDataWarning,
      confirmDestructive: false,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    try {
      if (widget.onDrainNodeOverride != null) {
        await widget.onDrainNodeOverride!(
          pool.id,
          node.nodeId,
          choice.deleteRemote,
        );
        return;
      }
      final taskId = await PoolService.instance.startDrain(
        pool.id,
        node.nodeId,
        deleteRemoteData: choice.deleteRemote,
      );
      if (!mounted) return;
      await TaskProgressDialog.show(
        context,
        taskId,
        '${l10n.poolDrainNode}: $label',
      );
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    }
  }

  Future<void> _editNodeWeight(
    PoolSummaryDto pool,
    PoolNodeStatusDto node,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: node.weight.toString());
    String? errorText;
    int? nextWeight;
    try {
      nextWeight = await showDialog<int>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final scheme = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Text(
                '${l10n.poolSetNodeWeightTitle} · ${_remoteNameOf(node.remoteId)}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: l10n.poolNodeWeightLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.poolSetNodeWeightHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = int.tryParse(ctrl.text.trim());
                    if (parsed == null || parsed < 1 || parsed > 1000) {
                      setDialogState(
                        () => errorText = l10n.poolInvalidWeightError,
                      );
                      return;
                    }
                    Navigator.of(ctx).pop(parsed);
                  },
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (nextWeight == null || nextWeight == node.weight || !mounted) return;
    setState(() => _busy = true);
    try {
      final cfg = await PoolService.instance.getConfig(pool.id);
      if (!mounted) return;
      final updatedNodes = [
        for (final n in cfg.nodes)
          PoolNodeConfigDto(
            nodeId: n.nodeId,
            remoteId: n.remoteId,
            basePrefix: n.basePrefix,
            failureDomain: n.failureDomain,
            quotaBytes: n.quotaBytes,
            weight: n.nodeId == node.nodeId ? nextWeight : n.weight,
            role: n.role,
            isMetaBackup: n.isMetaBackup,
          ),
      ];
      await PoolService.instance.saveConfig(
        PoolConfigDto(
          id: cfg.id,
          name: cfg.name,
          chunkSize: cfg.chunkSize,
          replicationFactor: cfg.replicationFactor,
          encrypt: cfg.encrypt,
          passphrase: cfg.passphrase,
          kdfSalt: cfg.kdfSalt,
          nodes: updatedNodes,
        ),
      );
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNodeOffline(
    PoolSummaryDto pool,
    PoolNodeStatusDto node,
  ) async {
    final l10n = AppLocalizations.of(context);
    final label = _remoteNameOf(node.remoteId);
    final choice = await _showConfirmWithRemoteDeleteOption(
      title: l10n.poolOfflineNode,
      message: l10n.poolOfflineConfirm(label),
      confirmLabel: l10n.poolOfflineNode,
      checkboxLabel: l10n.poolDeleteNodeRemoteDataOption,
      dangerHint: l10n.poolDeleteNodeRemoteDataWarning,
      confirmDestructive: false,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.onOfflineNodeOverride != null) {
        await widget.onOfflineNodeOverride!(
          pool.id,
          node.nodeId,
          choice.deleteRemote,
        );
        return;
      }
      final report = await PoolService.instance.setNodeOffline(
        pool.id,
        node.nodeId,
        deleteRemoteData: choice.deleteRemote,
      );
      await _load();
      if (choice.deleteRemote) {
        _showCleanupReportSnack(report);
      }
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNodeOnline(
    PoolSummaryDto pool,
    PoolNodeStatusDto node,
  ) async {
    setState(() => _busy = true);
    try {
      if (widget.onOnlineNodeOverride != null) {
        await widget.onOnlineNodeOverride!(pool.id, node.nodeId);
        return;
      }
      await PoolService.instance.setNodeOnline(pool.id, node.nodeId);
      await _load();
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeNode(
    PoolSummaryDto pool,
    PoolNodeStatusDto node,
  ) async {
    final l10n = AppLocalizations.of(context);
    final label = _remoteNameOf(node.remoteId);
    final choice = await _showConfirmWithRemoteDeleteOption(
      title: l10n.poolRemoveNode,
      message: l10n.poolRemoveNodeConfirm(label),
      confirmLabel: l10n.poolRemoveNode,
      checkboxLabel: l10n.poolDeleteNodeRemoteDataOption,
      dangerHint: l10n.poolDeleteNodeRemoteDataWarning,
    );
    if (choice == null || !choice.confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.onRemoveNodeOverride != null) {
        await widget.onRemoveNodeOverride!(
          pool.id,
          node.nodeId,
          choice.deleteRemote,
        );
        return;
      }
      final report = await PoolService.instance.removeNode(
        pool.id,
        node.nodeId,
        deleteRemoteData: choice.deleteRemote,
      );
      await _load();
      if (choice.deleteRemote) {
        _showCleanupReportSnack(report);
      }
    } catch (e) {
      _showSnack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _browsePool(PoolSummaryDto pool) {
    if (widget.onOpenPool != null) {
      widget.onOpenPool!(pool);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: 'pool://${pool.id}',
          initialPath: '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pool = _selectedPool;

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _pools.isEmpty
            ? AppEmptyState(
                icon: Icons.hub_outlined,
                title: l10n.noStoragePools,
                subtitle: l10n.noStoragePoolsDesc,
                action: FilledButton.icon(
                  onPressed: _createPool,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.createStoragePool),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _load(forceSpaceProbe: true),
                child: Column(
                  children: [
                    if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                    Expanded(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_pools.length > 1) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final p in _pools)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(p.name),
                                        selected: p.id == pool?.id,
                                        onSelected: (_) {
                                          setState(() => _selectedPoolId = p.id);
                                          _scheduleBackgroundSpaceProbe(p);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (pool != null) ...[
                            _buildSummaryCard(l10n, scheme, pool),
                            if (pool.degradedChunks > BigInt.zero) ...[
                              const SizedBox(height: 12),
                              _buildDegradedBanner(l10n, scheme, pool),
                            ],
                            const SizedBox(height: 16),
                            Text(
                              '${l10n.poolSelectNodes} (${l10n.poolNodesCount(pool.nodes.length)})',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final node in pool.nodes)
                              _buildNodeCard(l10n, scheme, pool, node),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );

    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.storagePools,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.refresh,
                  onPressed: _busy ? null : () => _load(forceSpaceProbe: true),
                ),
                FilledButton.tonalIcon(
                  onPressed: _createPool,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.createStoragePool),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      );
    }

    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.storagePools),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: _busy ? null : () => _load(forceSpaceProbe: true),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.createStoragePool,
              onPressed: _createPool,
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildSummaryCard(
    AppLocalizations l10n,
    ColorScheme scheme,
    PoolSummaryDto pool,
  ) {
    final logicalFrac = pool.effectiveLogicalCapacity > BigInt.zero
        ? (pool.logicalUsedBytes.toDouble() /
                pool.effectiveLogicalCapacity.toDouble())
            .clamp(0.0, 1.0)
        : 0.0;
    final physicalFrac = pool.totalPhysicalQuota > BigInt.zero
        ? (pool.totalPhysicalUsed.toDouble() /
                pool.totalPhysicalQuota.toDouble())
            .clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.hub_rounded, color: scheme.primary),
                Text(
                  pool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    pool.encrypted
                        ? l10n.poolEncryptedBadge
                        : l10n.poolPlaintextBadge,
                    style: const TextStyle(fontSize: 11),
                  ),
                  avatar: Icon(
                    pool.encrypted ? Icons.lock : Icons.lock_open,
                    size: 14,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    l10n.poolMetaVersionBadge(pool.metaVersion.toInt()),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.content_copy_outlined, size: 14),
                  label: Text(
                    l10n.poolReplicationBadge(pool.replicationFactor),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _busy ? null : () => _editReplicationFactor(pool),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.poolLogicalCapacity,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${formatBytes(pool.logicalUsedBytes)} / ${formatBytes(pool.effectiveLogicalCapacity)}',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: logicalFrac),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.poolPhysicalCapacity,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${formatBytes(pool.totalPhysicalUsed)} / ${formatBytes(pool.totalPhysicalQuota)}',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: physicalFrac,
              color: scheme.secondary,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _browsePool(pool),
                  icon: const Icon(Icons.folder_open, size: 17),
                  label: Text(l10n.poolBrowse),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _probeHealth(pool),
                  icon: const Icon(Icons.monitor_heart_outlined, size: 17),
                  label: Text(l10n.poolProbeHealth),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _syncMetadata(pool),
                  icon: const Icon(Icons.sync, size: 17),
                  label: Text(l10n.poolSyncMeta),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _runHeal(pool),
                  icon: const Icon(Icons.healing_outlined, size: 17),
                  label: Text(l10n.poolHeal),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _runGc(pool),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                  label: Text(l10n.poolGc),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editPool(pool),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(l10n.editStoragePool),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _deletePool(pool),
                  icon: Icon(Icons.delete_outline, size: 17, color: scheme.error),
                  label: Text(
                    l10n.delete,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDegradedBanner(
    AppLocalizations l10n,
    ColorScheme scheme,
    PoolSummaryDto pool,
  ) {
    return Card(
      elevation: 0,
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.poolDegradedWarning(pool.degradedChunks.toInt()),
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _runHeal(pool),
              child: Text(l10n.poolHeal),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard(
    AppLocalizations l10n,
    ColorScheme scheme,
    PoolSummaryDto pool,
    PoolNodeStatusDto node,
  ) {
    final isOpen = node.circuitState == 'open';
    final isOffline = node.role == 'offline';
    final statusColor = isOffline
        ? Colors.grey
        : isOpen
            ? scheme.error
            : node.healthScore >= 0.7
                ? Colors.green
                : Colors.orange;
    final rawDir = node.basePrefix.trim();
    final dirDisplay = rawDir.isEmpty
        ? '/fm_pool'
        : (rawDir == '/'
            ? '/'
            : '/${rawDir.replaceAll(RegExp(r'^/+|/+$'), '')}');

    final BigInt? remoteFree = node.remoteFreeBytes;
    final BigInt? remoteTotal = node.remoteTotalBytes;
    final bool isProbingSpace = _probingPoolIds.contains(pool.id);
    final bool supportsSpace = _nodeSupportsSpaceQuery(node);
    final double quotaFrac = node.quotaBytes > BigInt.zero
        ? (node.usedBytes.toDouble() / node.quotaBytes.toDouble()).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final String quotaText = l10n.poolNodeUsedAndQuota(
      formatBytes(node.usedBytes),
      formatBytes(node.quotaBytes),
    );
    final String quotaPct = '${(quotaFrac * 100).round()}%';

    final String systemSpaceText;
    if (!supportsSpace) {
      systemSpaceText = l10n.poolNodeSystemSpaceUnsupported;
    } else if (remoteFree != null &&
        remoteTotal != null &&
        remoteTotal > BigInt.zero) {
      systemSpaceText = l10n.poolNodeSystemFreeWithTotal(
        formatBytes(remoteFree),
        formatBytes(remoteTotal),
      );
    } else if (remoteFree != null) {
      systemSpaceText = l10n.poolNodeSystemFreeOnly(formatBytes(remoteFree));
    } else if (isProbingSpace && node.role != 'offline') {
      systemSpaceText = l10n.poolNodeSystemSpaceProbing;
    } else {
      systemSpaceText = l10n.poolNodeSystemSpaceUnavailable;
    }

    final healthPct = (node.healthScore * 100).round();
    final roleLabel = switch (node.role.toLowerCase()) {
      'rw' => l10n.poolRoleShortRw,
      'ro' => l10n.poolRoleShortRo,
      'draining' => l10n.poolRoleShortDraining,
      'offline' => l10n.poolRoleShortOffline,
      _ => node.role.toUpperCase(),
    };
    final circuitLabel = switch (node.circuitState.toLowerCase()) {
      'closed' => l10n.poolCircuitClosed,
      'open' => l10n.poolCircuitOpen,
      'half_open' || 'half-open' => l10n.poolCircuitHalfOpen,
      _ => node.circuitState,
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _remoteNameOf(node.remoteId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (node.isMetaBackup)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Tooltip(
                      message: l10n.poolMetaBackup,
                      child: Icon(
                        Icons.storage_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  tooltip: l10n.moreOptions,
                  enabled: !_busy,
                  onSelected: (action) {
                    switch (action) {
                      case 'weight':
                        _editNodeWeight(pool, node);
                      case 'drain':
                        _runDrain(pool, node);
                      case 'offline':
                        _setNodeOffline(pool, node);
                      case 'online':
                        _setNodeOnline(pool, node);
                      case 'remove':
                        _removeNode(pool, node);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'weight',
                      child: Row(
                        children: [
                          const Icon(Icons.balance_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(l10n.poolSetNodeWeightTitle),
                        ],
                      ),
                    ),
                    if (node.role != 'offline' && node.role != 'draining')
                      PopupMenuItem(
                        value: 'drain',
                        child: Row(
                          children: [
                            const Icon(Icons.drive_file_move_outline, size: 18),
                            const SizedBox(width: 8),
                            Text(l10n.poolDrainNode),
                          ],
                        ),
                      ),
                    if (node.role != 'offline')
                      PopupMenuItem(
                        value: 'offline',
                        child: Row(
                          children: [
                            const Icon(Icons.power_settings_new, size: 18),
                            const SizedBox(width: 8),
                            Text(l10n.poolOfflineNode),
                          ],
                        ),
                      )
                    else
                      PopupMenuItem(
                        value: 'online',
                        child: Row(
                          children: [
                            const Icon(Icons.power_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text(l10n.poolOnlineNode),
                          ],
                        ),
                      ),
                    if (pool.nodes.length > 1)
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.poolRemoveNode,
                              style: TextStyle(color: scheme.error),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    '${node.failureDomain} · $roleLabel',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: const Icon(Icons.balance_outlined, size: 13),
                  label: Text(
                    l10n.poolNodeWeightBadge(node.weight),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _busy ? null : () => _editNodeWeight(pool, node),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: Icon(
                    Icons.folder_outlined,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    l10n.poolNodeDirectoryLabel(dirDisplay),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                if (node.role != 'offline' && node.role != 'draining')
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: _busy ? null : () => _runDrain(pool, node),
                    child: Text(l10n.poolDrainNode),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.poolNodeHealthSummary(
                healthPct,
                node.avgLatencyMs.toInt(),
                circuitLabel,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    quotaText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  quotaPct,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: quotaFrac),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    systemSpaceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: remoteFree != null && supportsSpace
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (supportsSpace && isProbingSpace && node.role != 'offline')
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
                    ),
                  ),
              ],
            ),
            if (node.lastError != null && node.lastError!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                node.lastError!,
                style: TextStyle(fontSize: 11.5, color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
