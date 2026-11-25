import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/task_progress_dialog.dart';
import '../rust/api/remotes.dart';
import '../rust/api/sync.dart';
import '../services/auto_sync_service.dart';
import '../services/background_keepalive_service.dart';
import '../services/error_text.dart';
import '../services/path_utils.dart';
import '../services/pool_service.dart';
import '../services/semantic_colors.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/error_recovery_action.dart';

/// Directory Sync & Lightweight Backup page (Incremental / Mirror / Bidirectional)
/// with extension, file-name glob, and folder exclusion rules.
class SyncPage extends StatefulWidget {
  final String? initialSrcRoot;
  final String? initialSrcPath;
  final String? initialDstRoot;
  final String? initialDstPath;

  const SyncPage({
    super.key,
    this.initialSrcRoot,
    this.initialSrcPath,
    this.initialDstRoot,
    this.initialDstPath,
  });

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  String? _srcRoot;
  String _srcPath = '';
  String? _dstRoot;
  String _dstPath = '';
  String _mode = 'incremental';

  List<String> _excludeExtensions = [];
  List<String> _excludeNames = [];
  List<String> _excludeDirs = [];
  final TextEditingController _extCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dirCtrl = TextEditingController();

  List<SyncProfile> _profiles = [];
  List<RemoteConfigDto> _remotes = const [];
  String? _activeProfileName;
  bool _previewing = false;
  bool _configExpanded = false;
  SyncPlanDto? _plan;
  final Set<String> _selectedRelPaths = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _srcRoot = widget.initialSrcRoot;
    _srcPath = widget.initialSrcPath ?? '';
    _dstRoot = widget.initialDstRoot;
    _dstPath = widget.initialDstPath ?? '';
    _loadProfiles();
    _loadRemotes();
    AutoSyncService.instance.addListener(_onAutoSyncChanged);
  }

  @override
  void dispose() {
    AutoSyncService.instance.removeListener(_onAutoSyncChanged);
    _extCtrl.dispose();
    _nameCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  void _onAutoSyncChanged() {
    if (!mounted) return;
    setState(() {
      _loadProfiles();
    });
  }

  Future<void> _loadRemotes() async {
    try {
      final list = await StorageService.instance.getRemotes();
      if (mounted) setState(() => _remotes = list);
    } catch (_) {}
  }

  void _loadProfiles() {
    _profiles = AutoSyncService.instance.loadProfiles();
  }

  void _persistProfiles() {
    AutoSyncService.instance.saveProfiles(_profiles);
  }

  SyncExcludeRulesDto? get _excludeRulesDto {
    if (_excludeExtensions.isEmpty &&
        _excludeNames.isEmpty &&
        _excludeDirs.isEmpty) {
      return null;
    }
    return SyncExcludeRulesDto(
      excludeExtensions: List<String>.from(_excludeExtensions),
      excludeNames: List<String>.from(_excludeNames),
      excludeDirs: List<String>.from(_excludeDirs),
    );
  }

  int get _excludeRuleCount =>
      _excludeExtensions.length + _excludeNames.length + _excludeDirs.length;

  void _addTokens(
    TextEditingController ctrl,
    List<String> target, {
    bool stripLeadingDot = false,
  }) {
    final parts = ctrl.text
        .split(RegExp(r'[,，;；]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    var changed = false;
    for (var token in parts) {
      if (stripLeadingDot) {
        token = token.replaceFirst(RegExp(r'^\*?\.+'), '').trim();
      }
      if (token.isNotEmpty && !target.contains(token)) {
        target.add(token);
        changed = true;
      }
    }
    ctrl.clear();
    if (changed) {
      setState(() {
        _plan = null;
        _selectedRelPaths.clear();
      });
    }
  }

  void _togglePreset(List<String> target, String value) {
    setState(() {
      if (target.contains(value)) {
        target.remove(value);
      } else {
        target.add(value);
      }
      _plan = null;
      _selectedRelPaths.clear();
    });
  }

  Future<void> _pickExcludeDir() async {
    if (_srcRoot == null) return;
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.syncPickExcludeDir,
      initialRoot: _srcRoot,
      initialPath: _srcPath,
      confirmLabel: l10n.ok,
      includeRemotes: true,
      includePools: true,
      includeUnlockedVaults: true,
    );
    if (picked == null || !mounted) return;
    var rel = picked.relPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final base = _srcPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    if (picked.root == _srcRoot && base.isNotEmpty) {
      if (rel == base) {
        return;
      }
      if (rel.startsWith('$base/')) {
        rel = rel.substring(base.length + 1);
      }
    }
    if (rel.isEmpty) return;
    if (!_excludeDirs.contains(rel)) {
      setState(() {
        _excludeDirs.add(rel);
        _plan = null;
        _selectedRelPaths.clear();
      });
    }
  }

  Future<void> _saveCurrentProfile() async {
    if (_srcRoot == null || _dstRoot == null) return;
    final l10n = AppLocalizations.of(context);
    final defaultName =
        '${_shortLabel(_srcRoot!, _srcPath)} → ${_shortLabel(_dstRoot!, _dstPath)}';
    final existing = _profiles
            .where((p) => p.name == (_activeProfileName ?? defaultName))
            .firstOrNull ??
        _profiles.where((p) => p.name == defaultName).firstOrNull;
    final controller =
        TextEditingController(text: _activeProfileName ?? defaultName);
    var intervalMinutes = existing?.autoIntervalMinutes ?? 0;
    final saved = await showDialog<({String name, int interval})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.syncSaveProfileTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.syncProfileNameLabel,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('sync_interval_$intervalMinutes'),
                initialValue: intervalMinutes,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText: l10n.autoSyncIntervalLabel,
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text(l10n.autoSyncOff)),
                  for (final m in const [15, 30, 60, 240])
                    DropdownMenuItem(
                      value: m,
                      child: Text(l10n.autoSyncEveryMinutes(m)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => intervalMinutes = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(AppLocalizations.of(ctx).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop((
                name: controller.text.trim(),
                interval: intervalMinutes,
              )),
              child: Text(AppLocalizations.of(ctx).ok),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == null || saved.name.isEmpty || !mounted) return;
    final preservedLastSyncMs = _profiles
            .where((p) => p.name == saved.name)
            .firstOrNull
            ?.lastAutoSyncMs ??
        existing?.lastAutoSyncMs ??
        0;
    setState(() {
      _activeProfileName = saved.name;
      _profiles.removeWhere((p) => p.name == saved.name);
      _profiles.insert(
        0,
        SyncProfile(
          name: saved.name,
          srcRoot: _srcRoot!,
          srcPath: _srcPath,
          dstRoot: _dstRoot!,
          dstPath: _dstPath,
          mode: _mode,
          autoIntervalMinutes: saved.interval,
          lastAutoSyncMs: preservedLastSyncMs,
          excludeExtensions: List<String>.from(_excludeExtensions),
          excludeNames: List<String>.from(_excludeNames),
          excludeDirs: List<String>.from(_excludeDirs),
        ),
      );
      _persistProfiles();
    });
  }

  void _applyProfile(SyncProfile profile) {
    setState(() {
      _activeProfileName = profile.name;
      _srcRoot = profile.srcRoot;
      _srcPath = profile.srcPath;
      _dstRoot = profile.dstRoot;
      _dstPath = profile.dstPath;
      _mode = profile.mode;
      _excludeExtensions = List<String>.from(profile.excludeExtensions);
      _excludeNames = List<String>.from(profile.excludeNames);
      _excludeDirs = List<String>.from(profile.excludeDirs);
      _plan = null;
      _selectedRelPaths.clear();
      _error = null;
    });
  }

  Future<void> _deleteProfile(SyncProfile profile) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.syncConfirmDeleteProfileBody(profile.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      if (_activeProfileName == profile.name) {
        _activeProfileName = null;
      }
      _profiles.removeWhere((p) => p.name == profile.name);
      _persistProfiles();
    });
  }

  String _shortLabel(String root, String rel) {
    if (rel.isEmpty) {
      if (root.startsWith('remote://')) {
        final id = root.substring('remote://'.length);
        final m = _remotes.where((r) => r.id == id).firstOrNull;
        if (m != null) return m.name;
      } else if (poolIdFromRoot(root) != null) {
        final pid = poolIdFromRoot(root)!;
        final m = PoolService.instance.pools.where((p) => p.id == pid).firstOrNull;
        if (m != null) return m.name;
      } else if (vaultIdFromRoot(root) != null) {
        final vid = vaultIdFromRoot(root)!;
        final m = VaultService.instance.unlockedVaults
            .where((v) => v.id == vid)
            .firstOrNull;
        if (m != null) return m.name;
      }
    }
    final target = rel.isEmpty ? root : rel;
    final parts =
        target.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? root : parts.last;
  }

  Future<void> _pickFolder(bool isSource) async {
    final l10n = AppLocalizations.of(context);
    final dest = await FolderPickerDialog.show(
      context,
      title: isSource ? l10n.syncSourceLabel : l10n.syncDestinationLabel,
      initialRoot: isSource ? _srcRoot : _dstRoot,
      initialPath: isSource ? _srcPath : _dstPath,
      confirmLabel: l10n.ok,
      includeRemotes: true,
      includePools: true,
      includeUnlockedVaults: true,
    );
    if (dest == null || !mounted) return;
    setState(() {
      if (isSource) {
        _srcRoot = dest.root;
        _srcPath = dest.relPath;
      } else {
        _dstRoot = dest.root;
        _dstPath = dest.relPath;
      }
      _plan = null;
      _selectedRelPaths.clear();
    });
  }

  void _swapFolders() {
    if (_srcRoot == null && _dstRoot == null) return;
    setState(() {
      final tmpRoot = _srcRoot;
      final tmpPath = _srcPath;
      _srcRoot = _dstRoot;
      _srcPath = _dstPath;
      _dstRoot = tmpRoot;
      _dstPath = tmpPath;
      _plan = null;
      _selectedRelPaths.clear();
      _error = null;
    });
  }

  Future<void> _preview() async {
    if (_srcRoot == null || _dstRoot == null) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final plan = await BackgroundKeepAliveService.instance.runWithKeepAlive(
        'sync:preview',
        () => previewDirectorySync(
          srcRoot: _srcRoot!,
          srcPath: _srcPath,
          dstRoot: _dstRoot!,
          dstPath: _dstPath,
          mode: _mode,
          excludeRules: _excludeRulesDto,
        ),
        title: 'Directory Sync Scan',
        detail:
            'Scanning ${_shortLabel(_srcRoot!, _srcPath)} ↔ ${_shortLabel(_dstRoot!, _dstPath)}',
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _configExpanded = false;
        _selectedRelPaths
          ..clear()
          ..addAll(plan.items.map((e) => e.relPath));
        _previewing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyErrorText(e, AppLocalizations.of(context));
          _previewing = false;
        });
      }
    }
  }

  Future<void> _startSync() async {
    if (_srcRoot == null || _dstRoot == null || _selectedRelPaths.isEmpty) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final deleteCount = _plan?.items
            .where((e) =>
                _selectedRelPaths.contains(e.relPath) && e.action == 'delete')
            .length ??
        0;
    if (deleteCount > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.syncConfirmMirrorDeleteTitle),
          content: Text(l10n.syncConfirmMirrorDeleteBody(deleteCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await BackgroundKeepAliveService.instance.runWithKeepAlive(
        'sync:execute',
        () async {
          final taskId = await startDirectorySyncTask(
            srcRoot: _srcRoot!,
            srcPath: _srcPath,
            dstRoot: _dstRoot!,
            dstPath: _dstPath,
            mode: _mode,
            selectedRelPaths: _selectedRelPaths.toList(),
            excludeRules: _excludeRulesDto,
          );
          if (!mounted) return;
          await TaskProgressDialog.show(
            context,
            taskId,
            AppLocalizations.of(context).directorySync,
          );
        },
        title: 'Directory Sync in Progress',
        detail:
            '${_shortLabel(_srcRoot!, _srcPath)} → ${_shortLabel(_dstRoot!, _dstPath)}',
      );
      if (mounted) {
        await _preview();
      }
    } catch (e) {
      if (mounted) {
        final targetRoot = _dstRoot?.startsWith('remote://') == true
            ? _dstRoot
            : _srcRoot;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            persist: false,
            duration: const Duration(seconds: 5),
            content: Text(friendlyErrorText(e, AppLocalizations.of(context))),
            action: ErrorRecoveryActionButton.buildSnackBarAction(
              context,
              rawError: e,
              root: targetRoot,
              onRetry: _startSync,
            ),
          ),
        );
      }
    }
  }

  String _formatTarget(String? root, String rel) {
    if (root == null) return '—';
    String label = root;
    if (root.startsWith('remote://')) {
      final id = root.substring('remote://'.length);
      final match = _remotes.where((r) => r.id == id).firstOrNull;
      if (match != null) label = '☁️ ${match.name}';
    } else if (poolIdFromRoot(root) != null) {
      final pid = poolIdFromRoot(root)!;
      final match =
          PoolService.instance.pools.where((p) => p.id == pid).firstOrNull;
      if (match != null) label = '🧩 ${match.name}';
    } else if (vaultIdFromRoot(root) != null) {
      final vid = vaultIdFromRoot(root)!;
      final match = VaultService.instance.unlockedVaults
          .where((v) => v.id == vid)
          .firstOrNull;
      if (match != null) label = '🔒 ${match.name}';
    }
    return rel.isEmpty ? label : '$label/$rel';
  }

  Widget _buildExcludeGroup({
    required String label,
    required String hint,
    required TextEditingController controller,
    required List<String> items,
    required String addLabel,
    bool stripLeadingDot = false,
    Widget? extraButton,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addTokens(
                  controller,
                  items,
                  stripLeadingDot: stripLeadingDot,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (extraButton != null) ...[
              extraButton,
              const SizedBox(width: 4),
            ],
            OutlinedButton(
              onPressed: () => _addTokens(
                controller,
                items,
                stripLeadingDot: stripLeadingDot,
              ),
              child: Text(addLabel),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final value in items)
                InputChip(
                  label: Text(value, style: const TextStyle(fontSize: 11.5)),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () {
                    setState(() {
                      items.remove(value);
                      _plan = null;
                      _selectedRelPaths.clear();
                    });
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildExcludeRulesCard(AppLocalizations l10n, ColorScheme scheme) {
    final count = _excludeRuleCount;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: count > 0,
        leading: const Icon(Icons.filter_alt_outlined, size: 20),
        title: Row(
          children: [
            Text(
              l10n.syncExcludeRulesTitle,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${l10n.syncExcludePresets}:',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                for (final ext in const ['tmp', 'log', 'bak'])
                  FilterChip(
                    label: Text('.$ext', style: const TextStyle(fontSize: 11)),
                    selected: _excludeExtensions.contains(ext),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _togglePreset(_excludeExtensions, ext),
                  ),
                for (final name in const ['.DS_Store', 'Thumbs.db', '~\$*'])
                  FilterChip(
                    label: Text(name, style: const TextStyle(fontSize: 11)),
                    selected: _excludeNames.contains(name),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _togglePreset(_excludeNames, name),
                  ),
                for (final dir in const ['.git', 'node_modules', 'build'])
                  FilterChip(
                    label: Text('$dir/', style: const TextStyle(fontSize: 11)),
                    selected: _excludeDirs.contains(dir),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _togglePreset(_excludeDirs, dir),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildExcludeGroup(
            label: l10n.syncExcludeExtensionsLabel,
            hint: l10n.syncExcludeExtensionsHint,
            controller: _extCtrl,
            items: _excludeExtensions,
            addLabel: l10n.syncAddRule,
            stripLeadingDot: true,
          ),
          const SizedBox(height: 10),
          _buildExcludeGroup(
            label: l10n.syncExcludeNamesLabel,
            hint: l10n.syncExcludeNamesHint,
            controller: _nameCtrl,
            items: _excludeNames,
            addLabel: l10n.syncAddRule,
          ),
          const SizedBox(height: 10),
          _buildExcludeGroup(
            label: l10n.syncExcludeDirsLabel,
            hint: l10n.syncExcludeDirsHint,
            controller: _dirCtrl,
            items: _excludeDirs,
            addLabel: l10n.syncAddRule,
            extraButton: _srcRoot != null
                ? IconButton(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    tooltip: l10n.syncPickExcludeDir,
                    onPressed: _pickExcludeDir,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigControls(AppLocalizations l10n, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_profiles.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _profiles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final p = _profiles[i];
                final label = p.autoIntervalMinutes > 0
                    ? '${p.name} (${p.autoIntervalMinutes}m)'
                    : p.name;
                return InputChip(
                  avatar: Icon(
                    p.autoIntervalMinutes > 0 ? Icons.schedule : Icons.sync_alt,
                    size: 15,
                  ),
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _applyProfile(p),
                  onDeleted: () => _deleteProfile(p),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l10n.syncSourceLabel),
                subtitle: Text(
                  _formatTarget(_srcRoot, _srcPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_srcRoot != null || _dstRoot != null)
                      IconButton(
                        icon: const Icon(Icons.swap_vert, size: 18),
                        tooltip: l10n.syncSwapFoldersTooltip,
                        onPressed: _swapFolders,
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _pickFolder(true),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: Text(l10n.syncDestinationLabel),
                subtitle: Text(
                  _formatTarget(_dstRoot, _dstPath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickFolder(false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('sync_mode_$_mode'),
          initialValue: _mode,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'incremental',
              child: Text(l10n.syncModeIncremental),
            ),
            DropdownMenuItem(value: 'mirror', child: Text(l10n.syncModeMirror)),
            DropdownMenuItem(
              value: 'bidirectional',
              child: Text(l10n.syncModeBidirectional),
            ),
          ],
          onChanged: (v) {
            if (v != null && v != _mode) {
              setState(() {
                _mode = v;
                _plan = null;
                _selectedRelPaths.clear();
              });
            }
          },
        ),
        const SizedBox(height: 8),
        _buildExcludeRulesCard(l10n, scheme),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: _previewing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.preview, size: 18),
                label: Text(l10n.syncPreviewChanges),
                onPressed: (_srcRoot != null && _dstRoot != null && !_previewing)
                    ? _preview
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.sync, size: 18),
                label: Text(l10n.syncStart),
                onPressed: (_plan != null && _selectedRelPaths.isNotEmpty)
                    ? _startSync
                    : null,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
              const SizedBox(width: 8),
              ErrorRecoveryActionButton(
                rawError: _error!,
                root: _dstRoot?.startsWith('remote://') == true
                    ? _dstRoot
                    : _srcRoot,
                onRetry: _preview,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _localizedSyncAction(AppLocalizations l10n, String action) {
    return switch (action) {
      'add' => l10n.syncActionCopy,
      'update' => l10n.syncActionUpdate,
      'delete' => l10n.syncActionDelete,
      'pull_add' || 'pull_update' => l10n.syncActionPullUpdate,
      _ => action.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;
    final autoSyncErr = AutoSyncService.instance.lastAutoSyncError;

    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.directorySync),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: l10n.syncSaveProfileTitle,
              onPressed: (_srcRoot != null && _dstRoot != null)
                  ? _saveCurrentProfile
                  : null,
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (autoSyncErr != null && autoSyncErr.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.syncAutoSyncFailed(autoSyncErr),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 16,
                          color: scheme.onErrorContainer,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            AutoSyncService.instance.clearLastAutoSyncError,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: plan == null
                    ? SingleChildScrollView(
                        child: _buildConfigControls(l10n, scheme),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_configExpanded) ...[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.sizeOf(context).height * 0.44,
                              ),
                              child: SingleChildScrollView(
                                child: _buildConfigControls(l10n, scheme),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    setState(() => _configExpanded = false),
                                icon: const Icon(Icons.expand_less, size: 18),
                                label: Text(l10n.syncEditConfig),
                              ),
                            ),
                          ] else
                            Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () =>
                                          setState(() => _configExpanded = true),
                                      icon: const Icon(Icons.tune, size: 16),
                                      label: Text(l10n.syncEditConfig),
                                    ),
                                    OutlinedButton.icon(
                                      icon: _previewing
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.preview, size: 16),
                                      label: Text(l10n.syncPreviewChanges),
                                      onPressed: (_srcRoot != null &&
                                              _dstRoot != null &&
                                              !_previewing)
                                          ? _preview
                                          : null,
                                    ),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.sync, size: 16),
                                      label: Text(l10n.syncStart),
                                      onPressed: _selectedRelPaths.isNotEmpty
                                          ? _startSync
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          if (plan.truncated)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.warning.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: scheme.warning.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: scheme.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.syncScanLimitReached,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${l10n.syncSummaryChanges(plan.items.length, plan.unchangedCount.toInt())} · ${formatBytes(plan.transferBytes)}${plan.excludedCount > BigInt.zero ? ' · ${l10n.syncExcludedCount(plan.excludedCount.toInt())}' : ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (plan.items.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      if (_selectedRelPaths.length ==
                                          plan.items.length) {
                                        _selectedRelPaths.clear();
                                      } else {
                                        _selectedRelPaths
                                          ..clear()
                                          ..addAll(
                                            plan.items.map((e) => e.relPath),
                                          );
                                      }
                                    });
                                  },
                                  child: Text(
                                    _selectedRelPaths.length ==
                                            plan.items.length
                                        ? l10n.syncDeselectAll
                                        : l10n.syncSelectAll,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: plan.items.isEmpty
                                ? Center(child: Text(l10n.syncNoChanges))
                                : ListView.separated(
                                    itemCount: plan.items.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final item = plan.items[i];
                                      final (IconData icon, Color color) =
                                          switch (item.action) {
                                        'add' => (
                                            Icons.add_circle_outline,
                                            scheme.success,
                                          ),
                                        'update' =>
                                          (Icons.update, scheme.primary),
                                        'delete' => (
                                            Icons.delete_outline,
                                            scheme.error,
                                          ),
                                        'pull_add' || 'pull_update' => (
                                            Icons.download_outlined,
                                            Colors.teal,
                                          ),
                                        _ => (Icons.sync, scheme.outline),
                                      };
                                      return CheckboxListTile(
                                        dense: true,
                                        value: _selectedRelPaths
                                            .contains(item.relPath),
                                        secondary:
                                            Icon(icon, color: color, size: 18),
                                        title: Text(
                                          item.relPath,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${_localizedSyncAction(l10n, item.action)} · ${item.srcSize != null ? formatBytes(item.srcSize!) : (item.dstSize != null ? formatBytes(item.dstSize!) : '')}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selectedRelPaths
                                                  .add(item.relPath);
                                            } else {
                                              _selectedRelPaths
                                                  .remove(item.relPath);
                                            }
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
