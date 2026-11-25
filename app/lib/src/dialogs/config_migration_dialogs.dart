import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../rust/api/remotes.dart';
import '../services/config_migration_service.dart';
import '../services/platform_capabilities.dart';
import '../services/pool_service.dart';
import '../services/preferences_service.dart';
import '../services/remote_transfer_service.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../services/vault_service.dart';

enum ConfigExportMethod { saveFile, shareFile, copyClipboard }

class ConfigExportOutcome {
  final ConfigExportMethod method;
  final String? savedPath;
  final ConfigExportResult summary;

  const ConfigExportOutcome({
    required this.method,
    this.savedPath,
    required this.summary,
  });
}

Rect? _dialogShareOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      !renderObject.size.isEmpty) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
  return null;
}

String _formatRemoteSubtitle(RemoteConfigDto r) {
  final kind = r.kind.toUpperCase();
  if (r.endpoint != null && r.endpoint!.isNotEmpty) {
    final base = r.endpoint!;
    return r.bucket != null && r.bucket!.isNotEmpty
        ? '$kind • $base (${r.bucket})'
        : '$kind • $base';
  }
  if (r.bucket != null && r.bucket!.isNotEmpty) {
    return '$kind • ${r.bucket}';
  }
  final portSuffix = r.port != null ? ':${r.port}' : '';
  final host = r.host ?? r.rootPath ?? '';
  return host.isEmpty ? kind : '$kind • $host$portSuffix';
}

class _SelectiveConfigCategoriesView extends StatelessWidget {
  final List<RemoteConfigDto> remotes;
  final List<PoolRefInfo> pools;
  final int bookmarksCount;
  final int preferencesCount;
  final bool allowEmptySettings;

  final Set<String> selectedRemoteIds;
  final Set<String> selectedPoolIds;
  final bool includeBookmarks;
  final bool includePreferences;

  final bool remotesExpanded;
  final bool poolsExpanded;

  final VoidCallback onToggleRemotesExpanded;
  final VoidCallback onTogglePoolsExpanded;
  final VoidCallback onToggleAllRemotes;
  final VoidCallback onToggleAllPools;
  final void Function(String remoteId, bool checked) onToggleRemote;
  final void Function(String poolId, bool checked) onTogglePool;
  final ValueChanged<bool> onToggleBookmarks;
  final ValueChanged<bool> onTogglePreferences;

  const _SelectiveConfigCategoriesView({
    required this.remotes,
    required this.pools,
    required this.bookmarksCount,
    required this.preferencesCount,
    required this.allowEmptySettings,
    required this.selectedRemoteIds,
    required this.selectedPoolIds,
    required this.includeBookmarks,
    required this.includePreferences,
    required this.remotesExpanded,
    required this.poolsExpanded,
    required this.onToggleRemotesExpanded,
    required this.onTogglePoolsExpanded,
    required this.onToggleAllRemotes,
    required this.onToggleAllPools,
    required this.onToggleRemote,
    required this.onTogglePool,
    required this.onToggleBookmarks,
    required this.onTogglePreferences,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final dependentPoolsMap =
        ConfigMigrationService.dependentPoolNamesByRemoteForRefs(
      selectedPoolIds: selectedPoolIds,
      pools: pools,
    );
    final availableRemoteIds = {for (final r in remotes) r.id};
    final effectiveSelectedRemoteIds = {
      for (final id in selectedRemoteIds)
        if (availableRemoteIds.contains(id)) id,
      for (final reqId in dependentPoolsMap.keys)
        if (availableRemoteIds.contains(reqId)) reqId,
    };

    final bool? remotesMasterValue;
    if (remotes.isEmpty || effectiveSelectedRemoteIds.isEmpty) {
      remotesMasterValue = false;
    } else if (effectiveSelectedRemoteIds.length >= remotes.length) {
      remotesMasterValue = true;
    } else {
      remotesMasterValue = null;
    }

    final bool? poolsMasterValue;
    if (pools.isEmpty || selectedPoolIds.isEmpty) {
      poolsMasterValue = false;
    } else if (selectedPoolIds.length >= pools.length) {
      poolsMasterValue = true;
    } else {
      poolsMasterValue = null;
    }

    final missingRemoteDeps = dependentPoolsMap.keys
        .where((id) => !availableRemoteIds.contains(id))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Remote connections (expandable)
        _ExpandableCategoryCard(
          icon: Icons.cloud_outlined,
          iconColor: const Color(0xFF1E88E5),
          title: l10n.remote,
          subtitle: remotes.isEmpty
              ? l10n.configMigrationNoRemotes
              : l10n.configMigrationSelectedRatio(
                  effectiveSelectedRemoteIds.length,
                  remotes.length,
                ),
          masterValue: remotesMasterValue,
          onMasterChanged: remotes.isEmpty ? null : (_) => onToggleAllRemotes(),
          expanded: remotesExpanded && remotes.isNotEmpty,
          canExpand: remotes.isNotEmpty,
          expandButtonKey: const ValueKey('config_migration_remotes_expand_btn'),
          onToggleExpand: onToggleRemotesExpanded,
          children: [
            if (dependentPoolsMap.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.configMigrationPoolDependencyHint,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final r in remotes) ...[
              Builder(
                builder: (_) {
                  final depPools = dependentPoolsMap[r.id];
                  final lockedByPool = depPools != null && depPools.isNotEmpty;
                  final checked =
                      lockedByPool || effectiveSelectedRemoteIds.contains(r.id);
                  return CheckboxListTile(
                    key: ValueKey('config_remote_cb_${r.id}'),
                    dense: true,
                    visualDensity:
                        const VisualDensity(horizontal: -2, vertical: -2),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    onChanged: lockedByPool
                        ? null
                        : (v) => onToggleRemote(r.id, v ?? false),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (lockedByPool) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatRemoteSubtitle(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (lockedByPool)
                          Text(
                            l10n.configMigrationPoolDependencyBadge(
                              depPools.join(', '),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // 2. Storage pools (expandable)
        _ExpandableCategoryCard(
          icon: Icons.hub_outlined,
          iconColor: const Color(0xFF00897B),
          title: l10n.storagePools,
          subtitle: pools.isEmpty
              ? l10n.configMigrationNoPools
              : l10n.configMigrationSelectedRatio(
                  selectedPoolIds.length,
                  pools.length,
                ),
          masterValue: poolsMasterValue,
          onMasterChanged: pools.isEmpty ? null : (_) => onToggleAllPools(),
          expanded: poolsExpanded && pools.isNotEmpty,
          canExpand: pools.isNotEmpty,
          expandButtonKey: const ValueKey('config_migration_pools_expand_btn'),
          onToggleExpand: onTogglePoolsExpanded,
          children: [
            for (final pool in pools)
              CheckboxListTile(
                key: ValueKey('config_pool_cb_${pool.id}'),
                dense: true,
                visualDensity:
                    const VisualDensity(horizontal: -2, vertical: -2),
                controlAffinity: ListTileControlAffinity.leading,
                value: selectedPoolIds.contains(pool.id),
                onChanged: (v) => onTogglePool(pool.id, v ?? false),
                title: Text(
                  pool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${l10n.poolNodesCount(pool.remoteIds.length)} • ${pool.replicationFactor}x'
                  '${pool.encrypted ? ' • Encrypted' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            if (missingRemoteDeps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Text(
                  l10n.configMigrationMissingPoolRemoteNotice,
                  style: TextStyle(fontSize: 11, color: scheme.warning),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // 3. Favorites
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: CheckboxListTile(
            key: const ValueKey('config_favorites_cb'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: bookmarksCount > 0 && includeBookmarks,
            onChanged: bookmarksCount > 0
                ? (v) => onToggleBookmarks(v ?? false)
                : null,
            secondary: const Icon(
              Icons.star_outline,
              size: 18,
              color: Color(0xFFFB8C00),
            ),
            title: Text(
              l10n.bookmarks,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              bookmarksCount > 0
                  ? l10n.configMigrationFavoritesCount(bookmarksCount)
                  : l10n.configMigrationNoFavorites,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 4. Settings
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: CheckboxListTile(
            key: const ValueKey('config_settings_cb'),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: (preferencesCount > 0 || allowEmptySettings) &&
                includePreferences,
            onChanged: (preferencesCount > 0 || allowEmptySettings)
                ? (v) => onTogglePreferences(v ?? false)
                : null,
            secondary: const Icon(
              Icons.settings_outlined,
              size: 18,
              color: Color(0xFF546E7A),
            ),
            title: Text(
              l10n.configMigrationSettingsCategory,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.configMigrationSettingsCount(preferencesCount),
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandableCategoryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool? masterValue;
  final ValueChanged<bool?>? onMasterChanged;
  final bool expanded;
  final bool canExpand;
  final Key expandButtonKey;
  final VoidCallback onToggleExpand;
  final List<Widget> children;

  const _ExpandableCategoryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.masterValue,
    required this.onMasterChanged,
    required this.expanded,
    required this.canExpand,
    required this.expandButtonKey,
    required this.onToggleExpand,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: canExpand ? onToggleExpand : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  Checkbox(
                    tristate: true,
                    value: masterValue,
                    onChanged: onMasterChanged,
                  ),
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canExpand)
                    IconButton(
                      key: expandButtonKey,
                      icon: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleExpand,
                    ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ConfigExportDialog extends StatefulWidget {
  final List<RemoteConfigDto>? remotesOverride;
  final List<PoolRefInfo>? poolsOverride;
  final int? bookmarksCountOverride;
  final int? preferencesCountOverride;
  final BundleEncryptFn? encryptFn;
  final Future<ConfigExportResult> Function({
    required Set<String> selectedRemoteIds,
    required Set<String> selectedPoolIds,
    required bool includeBookmarks,
    required bool includePreferences,
    required String password,
  })? exportBundleFn;
  final Future<String?> Function(
    String suggestedName,
    String payload,
    bool encrypted,
  )? saveFileFn;
  final Future<void> Function(
    String fileName,
    String payload,
    Rect? shareOrigin,
  )? shareFileFn;
  final Future<void> Function(String payload)? copyClipboardFn;
  final Future<bool> Function()? canUseSystemAuthFn;
  final Future<bool> Function(String localizedReason)? authenticateSystemFn;

  const ConfigExportDialog({
    super.key,
    this.remotesOverride,
    this.poolsOverride,
    this.bookmarksCountOverride,
    this.preferencesCountOverride,
    this.encryptFn,
    this.exportBundleFn,
    this.saveFileFn,
    this.shareFileFn,
    this.copyClipboardFn,
    this.canUseSystemAuthFn,
    this.authenticateSystemFn,
  });

  static Future<ConfigExportOutcome?> show(BuildContext context) {
    return showDialog<ConfigExportOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConfigExportDialog(),
    );
  }

  @override
  State<ConfigExportDialog> createState() => _ConfigExportDialogState();
}

class _ConfigExportDialogState extends State<ConfigExportDialog> {
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  List<RemoteConfigDto> _remotes = [];
  List<PoolRefInfo> _pools = [];
  int _bookmarksCount = 0;
  int _preferencesCount = 0;

  final Set<String> _selectedRemoteIds = {};
  final Set<String> _selectedPoolIds = {};
  bool _includeBookmarks = false;
  bool _includePreferences = true;

  bool _remotesExpanded = true;
  bool _poolsExpanded = true;

  @override
  void initState() {
    super.initState();
    if (widget.remotesOverride != null || widget.poolsOverride != null) {
      _remotes = List<RemoteConfigDto>.of(widget.remotesOverride ?? const []);
      _pools = List<PoolRefInfo>.of(widget.poolsOverride ?? const []);
      _bookmarksCount = widget.bookmarksCountOverride ?? 0;
      _preferencesCount = widget.preferencesCountOverride ?? 0;
      _selectDefaults();
      _loading = false;
    } else {
      _loadExportInventory();
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _selectDefaults() {
    _selectedRemoteIds
      ..clear()
      ..addAll(_remotes.map((r) => r.id));
    _selectedPoolIds
      ..clear()
      ..addAll(_pools.map((p) => p.id));
    _includeBookmarks = _bookmarksCount > 0;
    _includePreferences = true;
  }

  Future<void> _loadExportInventory() async {
    try {
      final remotes = await StorageService.instance.getRemotes();
      try {
        await PoolService.instance.refresh();
      } catch (_) {}
      final pools = PoolService.instance.pools
          .map(PoolRefInfo.fromSummary)
          .toList(growable: false);
      final bookmarks = await StorageService.instance.getBookmarks();
      final prefsMap = PreferencesService.instance.exportPreferencesMap();
      if (!mounted) return;
      setState(() {
        _remotes = remotes;
        _pools = pools;
        _bookmarksCount = bookmarks.length;
        _preferencesCount = prefsMap.length;
        _selectDefaults();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Set<String> get _lockedRemoteIds =>
      ConfigMigrationService.requiredRemoteIdsForRefs(
        selectedPoolIds: _selectedPoolIds,
        pools: _pools,
      );

  bool get _needsPassword => ConfigMigrationService.requiresPassword(
        selectedRemoteIds: _selectedRemoteIds,
        selectedPoolIds: _selectedPoolIds,
      );

  bool get _hasAnySelection =>
      _selectedRemoteIds.isNotEmpty ||
      _selectedPoolIds.isNotEmpty ||
      (_bookmarksCount > 0 && _includeBookmarks) ||
      _includePreferences;

  bool get _isPasswordValid {
    final pwd = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (_needsPassword) {
      return pwd.isNotEmpty && pwd == confirm;
    }
    if (pwd.isEmpty) return true;
    return pwd == confirm;
  }

  bool get _canExport => !_loading && !_busy && _hasAnySelection && _isPasswordValid;

  void _toggleAllRemotes() {
    setState(() {
      _error = null;
      final availableIds = {for (final r in _remotes) r.id};
      final locked = _lockedRemoteIds.intersection(availableIds);
      if (_selectedRemoteIds.containsAll(availableIds)) {
        _selectedRemoteIds
          ..clear()
          ..addAll(locked);
      } else {
        _selectedRemoteIds.addAll(availableIds);
      }
    });
  }

  void _toggleAllPools() {
    setState(() {
      _error = null;
      if (_selectedPoolIds.length >= _pools.length) {
        _selectedPoolIds.clear();
      } else {
        _selectedPoolIds
          ..clear()
          ..addAll(_pools.map((p) => p.id));
        final availableIds = {for (final r in _remotes) r.id};
        _selectedRemoteIds.addAll(_lockedRemoteIds.intersection(availableIds));
      }
    });
  }

  void _toggleRemote(String remoteId, bool checked) {
    final locked = _lockedRemoteIds;
    if (!checked && locked.contains(remoteId)) {
      return;
    }
    setState(() {
      _error = null;
      if (checked) {
        _selectedRemoteIds.add(remoteId);
      } else {
        _selectedRemoteIds.remove(remoteId);
      }
    });
  }

  void _togglePool(String poolId, bool checked) {
    setState(() {
      _error = null;
      if (checked) {
        _selectedPoolIds.add(poolId);
        final pool = _pools.where((p) => p.id == poolId).firstOrNull;
        if (pool != null) {
          final availableIds = {for (final r in _remotes) r.id};
          for (final rid in pool.remoteIds) {
            if (availableIds.contains(rid)) {
              _selectedRemoteIds.add(rid);
            }
          }
        }
      } else {
        _selectedPoolIds.remove(poolId);
      }
    });
  }

  Future<String?> _defaultSaveFile(
    String suggestedName,
    String payload,
    bool encrypted,
  ) async {
    final loc = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: encrypted
              ? 'FileManager Encrypted Backup'
              : 'FileManager JSON Config',
          extensions: [encrypted ? 'fmbak' : 'json'],
        ),
      ],
    );
    if (loc == null) return null;
    await File(loc.path).writeAsString(payload);
    return loc.path;
  }

  Future<void> _defaultShareFile(
    String fileName,
    String payload,
    Rect? shareOrigin,
  ) async {
    final tempRoot = await getTemporaryDirectory();
    final exportDir = Directory(p.join(tempRoot.path, 'fm_config_exports'));
    if (exportDir.existsSync()) {
      try {
        for (final entity in exportDir.listSync()) {
          if (entity is File) {
            entity.deleteSync();
          }
        }
      } catch (_) {}
    } else {
      exportDir.createSync(recursive: true);
    }
    final outFile = File(p.join(exportDir.path, fileName));
    await outFile.writeAsString(payload);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            outFile.path,
            name: fileName,
            mimeType: 'application/json',
          ),
        ],
        subject: fileName,
        sharePositionOrigin: shareOrigin,
      ),
    );
  }

  Future<void> _runExport(ConfigExportMethod method) async {
    final l10n = AppLocalizations.of(context);
    if (!_hasAnySelection) {
      setState(() => _error = l10n.configMigrationSelectAtLeastOne);
      return;
    }
    final pwd = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (_needsPassword && pwd.isEmpty) {
      setState(() => _error = l10n.configMigrationPasswordRequiredHint);
      return;
    }
    if ((_needsPassword || pwd.isNotEmpty) && pwd != confirm) {
      setState(() => _error = l10n.configMigrationPasswordMismatch);
      return;
    }

    final shareOrigin = _dialogShareOrigin(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    if (_needsPassword &&
        (widget.authenticateSystemFn != null ||
            VaultService.isSystemAuthPlatform)) {
      try {
        final supported = widget.canUseSystemAuthFn != null
            ? await widget.canUseSystemAuthFn!()
            : (widget.authenticateSystemFn != null
                ? true
                : await VaultService.instance.canUseSystemAuth());
        if (!mounted) return;
        if (!supported) {
          setState(() {
            _busy = false;
            _error = l10n.configMigrationSystemAuthUnavailable;
          });
          return;
        }
        final authed = widget.authenticateSystemFn != null
            ? await widget.authenticateSystemFn!(
                l10n.configMigrationSystemAuthPrompt,
              )
            : await VaultService.instance.authenticateSystem(
                l10n.configMigrationSystemAuthPrompt,
              );
        if (!mounted) return;
        if (!authed) {
          setState(() {
            _busy = false;
            _error = l10n.configMigrationSystemAuthFailed;
          });
          return;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = l10n.configMigrationSystemAuthFailed;
        });
        return;
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    try {
      final result = widget.exportBundleFn != null
          ? await widget.exportBundleFn!(
              selectedRemoteIds: Set<String>.from(_selectedRemoteIds),
              selectedPoolIds: Set<String>.from(_selectedPoolIds),
              includeBookmarks: _includeBookmarks && _bookmarksCount > 0,
              includePreferences: _includePreferences,
              password: pwd,
            )
          : await ConfigMigrationService.instance.exportSelectiveBundle(
              selectedRemoteIds: Set<String>.from(_selectedRemoteIds),
              selectedPoolIds: Set<String>.from(_selectedPoolIds),
              includeBookmarks: _includeBookmarks && _bookmarksCount > 0,
              includePreferences: _includePreferences,
              password: pwd,
              encryptFn: widget.encryptFn,
            );

      switch (method) {
        case ConfigExportMethod.saveFile:
          final save = widget.saveFileFn ?? _defaultSaveFile;
          final savedPath = await save(
            result.suggestedFilename,
            result.payload,
            result.encrypted,
          );
          if (!mounted) return;
          if (savedPath == null) {
            setState(() => _busy = false);
            return;
          }
          Navigator.of(context).pop(
            ConfigExportOutcome(
              method: ConfigExportMethod.saveFile,
              savedPath: savedPath,
              summary: result,
            ),
          );
        case ConfigExportMethod.shareFile:
          final share = widget.shareFileFn ?? _defaultShareFile;
          await share(result.suggestedFilename, result.payload, shareOrigin);
          if (!mounted) return;
          Navigator.of(context).pop(
            ConfigExportOutcome(
              method: ConfigExportMethod.shareFile,
              summary: result,
            ),
          );
        case ConfigExportMethod.copyClipboard:
          if (widget.copyClipboardFn != null) {
            await widget.copyClipboardFn!(result.payload);
          } else {
            await Clipboard.setData(ClipboardData(text: result.payload));
          }
          if (!mounted) return;
          Navigator.of(context).pop(
            ConfigExportOutcome(
              method: ConfigExportMethod.copyClipboard,
              summary: result,
            ),
          );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final showConfirm = _needsPassword || _passwordCtrl.text.isNotEmpty;
    final willEncrypt = _needsPassword || _passwordCtrl.text.isNotEmpty;
    final hasPasswordMismatch = _confirmCtrl.text.isNotEmpty &&
        _passwordCtrl.text != _confirmCtrl.text;

    return AlertDialog(
      title: Text(l10n.exportMigrationTitle),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SelectiveConfigCategoriesView(
                      remotes: _remotes,
                      pools: _pools,
                      bookmarksCount: _bookmarksCount,
                      preferencesCount: _preferencesCount,
                      allowEmptySettings: true,
                      selectedRemoteIds: _selectedRemoteIds,
                      selectedPoolIds: _selectedPoolIds,
                      includeBookmarks: _includeBookmarks,
                      includePreferences: _includePreferences,
                      remotesExpanded: _remotesExpanded,
                      poolsExpanded: _poolsExpanded,
                      onToggleRemotesExpanded: () => setState(
                        () => _remotesExpanded = !_remotesExpanded,
                      ),
                      onTogglePoolsExpanded: () => setState(
                        () => _poolsExpanded = !_poolsExpanded,
                      ),
                      onToggleAllRemotes: _toggleAllRemotes,
                      onToggleAllPools: _toggleAllPools,
                      onToggleRemote: _toggleRemote,
                      onTogglePool: _togglePool,
                      onToggleBookmarks: (v) => setState(() {
                        _error = null;
                        _includeBookmarks = v;
                      }),
                      onTogglePreferences: (v) => setState(() {
                        _error = null;
                        _includePreferences = v;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (_needsPassword) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 15,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.configMigrationSystemAuthRequiredNote,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      _needsPassword
                          ? l10n.configMigrationPasswordRequiredHint
                          : l10n.configMigrationPasswordOptionalHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: (_needsPassword && _passwordCtrl.text.isEmpty)
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('config_export_password'),
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      enabled: !_busy,
                      onChanged: (_) => setState(() => _error = null),
                      decoration: InputDecoration(
                        labelText: _needsPassword
                            ? '${l10n.exportMigrationPasswordLabel} *'
                            : l10n.exportMigrationPasswordLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    if (showConfirm) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('config_export_confirm_password'),
                        controller: _confirmCtrl,
                        obscureText: _obscureConfirm,
                        enabled: !_busy,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: InputDecoration(
                          labelText: l10n.configMigrationConfirmPasswordLabel,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                      ),
                      if (hasPasswordMismatch) ...[
                        const SizedBox(height: 6),
                        Text(
                          l10n.configMigrationPasswordMismatch,
                          style: TextStyle(fontSize: 11.5, color: scheme.error),
                        ),
                      ],
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(fontSize: 12, color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('config_export_copy_btn'),
          onPressed: _canExport
              ? () => _runExport(ConfigExportMethod.copyClipboard)
              : null,
          child: Text(
            willEncrypt ? l10n.copyEncryptedAction : l10n.copyJsonAction,
          ),
        ),
        FilledButton(
          key: const ValueKey('config_export_file_btn'),
          onPressed: _canExport
              ? () => _runExport(
                    PlatformCapabilities.isMobile
                        ? ConfigExportMethod.shareFile
                        : ConfigExportMethod.saveFile,
                  )
              : null,
          child: Text(
            PlatformCapabilities.isMobile
                ? (willEncrypt
                    ? l10n.configMigrationShareBackupAction
                    : l10n.configMigrationShareJsonAction)
                : (willEncrypt
                    ? l10n.saveBackupFileAction
                    : l10n.saveJsonFileAction),
          ),
        ),
      ],
    );
  }
}

enum _ImportStep { input, preview }

class ConfigImportDialog extends StatefulWidget {
  final BundleDecryptFn? decryptFn;
  final Future<String?> Function()? pickFileFn;
  final Future<ConfigImportResult> Function({
    required ParsedConfigBundle bundle,
    required Set<String> selectedRemoteIds,
    required Set<String> selectedPoolIds,
    required bool includeBookmarks,
    required bool includePreferences,
  })? applyImportFn;

  const ConfigImportDialog({
    super.key,
    this.decryptFn,
    this.pickFileFn,
    this.applyImportFn,
  });

  static Future<ConfigImportResult?> show(BuildContext context) {
    return showDialog<ConfigImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ConfigImportDialog(),
    );
  }

  @override
  State<ConfigImportDialog> createState() => _ConfigImportDialogState();
}

class _ConfigImportDialogState extends State<ConfigImportDialog> {
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  _ImportStep _step = _ImportStep.input;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  ParsedConfigBundle? _bundle;
  final Set<String> _selectedRemoteIds = {};
  final Set<String> _selectedPoolIds = {};
  bool _includeBookmarks = false;
  bool _includePreferences = false;
  bool _remotesExpanded = true;
  bool _poolsExpanded = true;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  MigrationEnvelopeKind get _envelopeKind =>
      ConfigMigrationService.detectEnvelopeKind(_contentCtrl.text);

  bool get _needsPasswordForInput =>
      _envelopeKind != MigrationEnvelopeKind.plaintext;

  bool get _canParseInput =>
      !_busy &&
      _contentCtrl.text.trim().isNotEmpty &&
      (!_needsPasswordForInput || _passwordCtrl.text.isNotEmpty);

  Future<void> _pickFile() async {
    try {
      String? content;
      if (widget.pickFileFn != null) {
        content = await widget.pickFileFn!();
      } else {
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'FileManager Backup',
              extensions: ['fmbak', 'fmremotes', 'json'],
            ),
          ],
        );
        if (file == null) return;
        content = await file.readAsString();
      }
      if (content == null || !mounted) return;
      setState(() {
        _contentCtrl.text = content!;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _parseAndPreview() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    try {
      final parsed = ConfigMigrationService.decodeBundle(
        _contentCtrl.text,
        password: _passwordCtrl.text,
        decryptFn: widget.decryptFn,
      );
      if (parsed.isEmpty) {
        setState(() {
          _busy = false;
          _error = l10n.configMigrationInvalidBundleFormat;
        });
        return;
      }
      setState(() {
        _bundle = parsed;
        _selectedRemoteIds
          ..clear()
          ..addAll(parsed.remotes.map((r) => r.id));
        _selectedPoolIds
          ..clear()
          ..addAll(parsed.pools.map((p) => p.id));
        _includeBookmarks = parsed.bookmarks.isNotEmpty;
        _includePreferences = parsed.preferences.isNotEmpty;
        _remotesExpanded = true;
        _poolsExpanded = true;
        _step = _ImportStep.preview;
        _busy = false;
        _error = null;
      });
    } on RemoteBundleException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == RemoteBundleErrorCode.wrongPasswordOrCorrupted
            ? l10n.configMigrationWrongPassword
            : l10n.configMigrationInvalidBundleFormat;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.configMigrationInvalidBundleFormat;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.toLowerCase();
      setState(() {
        _busy = false;
        _error = (msg.contains('password') || msg.contains('corrupted'))
            ? l10n.configMigrationWrongPassword
            : '$e';
      });
    }
  }

  Set<String> get _lockedRemoteIds {
    final bundle = _bundle;
    if (bundle == null) return const {};
    return ConfigMigrationService.requiredRemoteIdsForPoolConfigs(
      selectedPoolIds: _selectedPoolIds,
      pools: bundle.pools,
    );
  }

  bool get _hasAnyPreviewSelection {
    final bundle = _bundle;
    if (bundle == null) return false;
    return _selectedRemoteIds.isNotEmpty ||
        _selectedPoolIds.isNotEmpty ||
        (bundle.bookmarks.isNotEmpty && _includeBookmarks) ||
        (bundle.preferences.isNotEmpty && _includePreferences);
  }

  void _toggleAllRemotes() {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() {
      _error = null;
      final availableIds = {for (final r in bundle.remotes) r.id};
      final locked = _lockedRemoteIds.intersection(availableIds);
      if (_selectedRemoteIds.containsAll(availableIds)) {
        _selectedRemoteIds
          ..clear()
          ..addAll(locked);
      } else {
        _selectedRemoteIds.addAll(availableIds);
      }
    });
  }

  void _toggleAllPools() {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() {
      _error = null;
      if (_selectedPoolIds.length >= bundle.pools.length) {
        _selectedPoolIds.clear();
      } else {
        _selectedPoolIds
          ..clear()
          ..addAll(bundle.pools.map((p) => p.id));
        final availableIds = {for (final r in bundle.remotes) r.id};
        _selectedRemoteIds.addAll(_lockedRemoteIds.intersection(availableIds));
      }
    });
  }

  void _toggleRemote(String remoteId, bool checked) {
    if (!checked && _lockedRemoteIds.contains(remoteId)) {
      return;
    }
    setState(() {
      _error = null;
      if (checked) {
        _selectedRemoteIds.add(remoteId);
      } else {
        _selectedRemoteIds.remove(remoteId);
      }
    });
  }

  void _togglePool(String poolId, bool checked) {
    final bundle = _bundle;
    if (bundle == null) return;
    setState(() {
      _error = null;
      if (checked) {
        _selectedPoolIds.add(poolId);
        final pool = bundle.pools.where((p) => p.id == poolId).firstOrNull;
        if (pool != null) {
          final availableIds = {for (final r in bundle.remotes) r.id};
          for (final n in pool.nodes) {
            if (availableIds.contains(n.remoteId)) {
              _selectedRemoteIds.add(n.remoteId);
            }
          }
        }
      } else {
        _selectedPoolIds.remove(poolId);
      }
    });
  }

  Future<void> _confirmImport() async {
    final bundle = _bundle;
    final l10n = AppLocalizations.of(context);
    if (bundle == null || !_hasAnyPreviewSelection) {
      setState(() => _error = l10n.configMigrationSelectAtLeastOne);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.applyImportFn != null
          ? await widget.applyImportFn!(
              bundle: bundle,
              selectedRemoteIds: Set<String>.from(_selectedRemoteIds),
              selectedPoolIds: Set<String>.from(_selectedPoolIds),
              includeBookmarks: _includeBookmarks && bundle.bookmarks.isNotEmpty,
              includePreferences:
                  _includePreferences && bundle.preferences.isNotEmpty,
            )
          : await ConfigMigrationService.instance.applySelectiveImport(
              bundle: bundle,
              selectedRemoteIds: Set<String>.from(_selectedRemoteIds),
              selectedPoolIds: Set<String>.from(_selectedPoolIds),
              includeBookmarks: _includeBookmarks && bundle.bookmarks.isNotEmpty,
              includePreferences:
                  _includePreferences && bundle.preferences.isNotEmpty,
            );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (_step == _ImportStep.input) {
      return AlertDialog(
        title: Text(l10n.importMigrationTitle),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.configMigrationPasteOrPickHint,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(l10n.configMigrationChooseBackupAction),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('config_import_content'),
                  controller: _contentCtrl,
                  maxLines: 5,
                  enabled: !_busy,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.importPasteHint,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('config_import_password'),
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  enabled: !_busy,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: _needsPasswordForInput
                        ? '${l10n.importPasswordLabel} *'
                        : l10n.importPasswordLabel,
                    hintText: l10n.importPasswordHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
                if (_needsPasswordForInput && _passwordCtrl.text.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.importPasswordRequiredError,
                    style: TextStyle(fontSize: 11.5, color: scheme.warning),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('config_import_parse_btn'),
            onPressed: _canParseInput ? _parseAndPreview : null,
            child: Text(
              _needsPasswordForInput
                  ? l10n.configMigrationDecryptAndPreview
                  : l10n.configMigrationNextSelectAction,
            ),
          ),
        ],
      );
    }

    final bundle = _bundle!;
    final poolRefs =
        bundle.pools.map(PoolRefInfo.fromConfig).toList(growable: false);

    return AlertDialog(
      title: Text(l10n.configMigrationImportSelectTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SelectiveConfigCategoriesView(
                remotes: bundle.remotes,
                pools: poolRefs,
                bookmarksCount: bundle.bookmarks.length,
                preferencesCount: bundle.preferences.length,
                allowEmptySettings: false,
                selectedRemoteIds: _selectedRemoteIds,
                selectedPoolIds: _selectedPoolIds,
                includeBookmarks: _includeBookmarks,
                includePreferences: _includePreferences,
                remotesExpanded: _remotesExpanded,
                poolsExpanded: _poolsExpanded,
                onToggleRemotesExpanded: () => setState(
                  () => _remotesExpanded = !_remotesExpanded,
                ),
                onTogglePoolsExpanded: () => setState(
                  () => _poolsExpanded = !_poolsExpanded,
                ),
                onToggleAllRemotes: _toggleAllRemotes,
                onToggleAllPools: _toggleAllPools,
                onToggleRemote: _toggleRemote,
                onTogglePool: _togglePool,
                onToggleBookmarks: (v) => setState(() {
                  _error = null;
                  _includeBookmarks = v;
                }),
                onTogglePreferences: (v) => setState(() {
                  _error = null;
                  _includePreferences = v;
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = _ImportStep.input;
                    _error = null;
                  }),
          child: Text(l10n.remoteBatchBackStep),
        ),
        FilledButton(
          key: const ValueKey('config_import_confirm_btn'),
          onPressed: (!_busy && _hasAnyPreviewSelection) ? _confirmImport : null,
          child: Text(l10n.configMigrationConfirmImportAction),
        ),
      ],
    );
  }
}
