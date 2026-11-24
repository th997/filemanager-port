import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../dialogs/task_progress_dialog.dart';
import '../dialogs/vault_dialogs.dart';
import '../pages/bookmarks_page.dart';
import '../pages/browser_workspace_page.dart';
import '../pages/gallery_page.dart';
import '../pages/offline_pinned_page.dart';
import '../pages/peer_transfer_page.dart';
import '../pages/photo_backup_page.dart';
import '../pages/recent_page.dart';
import '../pages/remotes_page.dart';
import '../pages/settings_page.dart';
import '../pages/tasks_page.dart';
import '../pages/trash_page.dart';
import '../pages/utilities_page.dart';
import '../rust/api/inspect.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../rust/api/tasks.dart';
import '../rust/api/vault.dart';
import '../services/platform_paths.dart';
import '../services/preferences_service.dart';
import '../services/task_service.dart';
import '../services/vault_service.dart';
import 'active_tasks_banner.dart';

enum _SidebarSection {
  browser,
  gallery,
  remotes,
  bookmarks,
  recent,
  offlinePinned,
  peerTransfer,
  photoBackup,
  utilities,
  tasks,
  trash,
  settings,
}

/// Wide-screen (`width >= 900`) persistent left sidebar + multi-tab/dual-pane
/// browser workspace shell. Supports collapsing the sidebar to a compact 52px
/// icon rail, folding individual sidebar section groups, dragging to resize,
/// and dropping files onto sidebar destinations.
class DesktopSidebarShell extends StatefulWidget {
  final List<RemoteConfigDto> remotes;
  final List<BookmarkDto> bookmarks;
  final List<HistoryDto> history;
  final int trashCount;
  final int activeTaskCount;
  final DiskSpaceDto? diskSpace;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final String? localeCode;
  final ValueChanged<String>? onLocaleChanged;
  final String? accentCode;
  final ValueChanged<String>? onAccentChanged;
  final VoidCallback onRefreshMetadata;
  final Future<void> Function({
    String? root,
    String? relPath,
    void Function(String root, String relPath, String title)? onNavigate,
  }) onOpenGlobalSearch;

  @visibleForTesting
  final Widget? workspaceOverride;
  final Widget? topBanner;

  const DesktopSidebarShell({
    super.key,
    required this.remotes,
    required this.bookmarks,
    required this.history,
    required this.trashCount,
    required this.activeTaskCount,
    required this.diskSpace,
    required this.themeMode,
    this.onThemeModeChanged,
    this.localeCode,
    this.onLocaleChanged,
    this.accentCode,
    this.onAccentChanged,
    required this.onRefreshMetadata,
    required this.onOpenGlobalSearch,
    this.workspaceOverride,
    this.topBanner,
  });

  @override
  State<DesktopSidebarShell> createState() => _DesktopSidebarShellState();
}

class _DesktopSidebarShellState extends State<DesktopSidebarShell> {
  static const double _collapsedWidth = 52.0;

  final GlobalKey<BrowserWorkspacePageState> _workspaceKey =
      GlobalKey<BrowserWorkspacePageState>();
  _SidebarSection _section = _SidebarSection.browser;
  String? _activeKey;
  double _sidebarWidth = 240.0;
  bool _collapsed = false;
  bool _draggingSplitter = false;
  Set<String> _collapsedGroups = <String>{};

  @override
  void initState() {
    super.initState();
    _activeKey = 'local:$_defaultRoot:';
    final prefs = PreferencesService.instance;
    _collapsed = prefs.sidebarCollapsed;
    _collapsedGroups = prefs.sidebarCollapsedGroups;
    _sidebarWidth = prefs.sidebarWidth;
  }

  String get _defaultRoot => PlatformPaths.defaultRoot();

  void _toggleSidebarCollapsed() {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    PreferencesService.instance.sidebarCollapsed = next;
  }

  void _toggleGroup(String groupId) {
    final next = Set<String>.from(_collapsedGroups);
    if (!next.add(groupId)) {
      next.remove(groupId);
    }
    setState(() => _collapsedGroups = next);
    PreferencesService.instance.sidebarCollapsedGroups = next;
  }

  void _openGlobalSearch() {
    final active = _section == _SidebarSection.browser
        ? _workspaceKey.currentState?.activeLocation
        : null;
    final isLocal = active != null &&
        !active.root.startsWith('remote://') &&
        !active.root.startsWith('vault://');
    widget.onOpenGlobalSearch(
      root: isLocal ? active.root : null,
      relPath: isLocal ? active.relPath : null,
      onNavigate: (root, relPath, title) => _navigateBrowser(
        root,
        relPath,
        title,
        'search:$root:$relPath',
      ),
    );
  }

  void _selectSection(_SidebarSection section) {
    final leavingMutable = _section == _SidebarSection.remotes ||
        _section == _SidebarSection.bookmarks ||
        _section == _SidebarSection.trash ||
        _section == _SidebarSection.utilities;
    final switching = _section != section;
    setState(() => _section = section);
    if (switching && leavingMutable) {
      widget.onRefreshMetadata();
    }
  }

  void _navigateBrowser(String root, String relPath, String title, String key) {
    final leavingMutable = _section == _SidebarSection.remotes ||
        _section == _SidebarSection.bookmarks ||
        _section == _SidebarSection.trash ||
        _section == _SidebarSection.utilities;
    setState(() {
      _section = _SidebarSection.browser;
      _activeKey = key;
    });
    if (leavingMutable) {
      widget.onRefreshMetadata();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceKey.currentState?.navigateActivePane(
        root: root,
        relPath: relPath,
        title: title,
      );
    });
  }

  Future<void> _openVaultViaDialog() async {
    final unlocked = await OpenVaultDialog.show(context);
    if (unlocked != null && mounted) {
      _navigateBrowser(
        'vault://${unlocked.id}',
        '',
        unlocked.name,
        'vault:${unlocked.id}',
      );
      widget.onRefreshMetadata();
    }
  }

  Future<void> _createVaultViaDialog() async {
    final created = await CreateVaultDialog.show(context);
    if (created != null && mounted) {
      _navigateBrowser(
        'vault://${created.id}',
        '',
        created.name,
        'vault:${created.id}',
      );
      widget.onRefreshMetadata();
    }
  }

  Future<void> _acceptSidebarDrop(
    ({String root, List<String> paths}) data, {
    required String dstRoot,
    required String dstRelPath,
    required String label,
  }) async {
    if (data.paths.isEmpty) return;
    try {
      final taskId = await startCopyTask(
        srcRoot: data.root,
        srcPaths: data.paths,
        dstRoot: dstRoot,
        dstDir: dstRelPath,
        dstName: null,
        conflictPolicy: 'rename',
      );
      if (!mounted) return;
      await TaskProgressDialog.show(
        context,
        taskId,
        '${AppLocalizations.of(context).copy} → $label',
      );
      widget.onRefreshMetadata();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Widget _collapsibleSection({
    required String groupId,
    required String title,
    int? itemCount,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isCollapsed = _collapsedGroups.contains(groupId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: ValueKey('sidebar_group_$groupId'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _toggleGroup(groupId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: isCollapsed ? -0.25 : 0.0,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (isCollapsed && itemCount != null && itemCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$itemCount',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isCollapsed
              ? const SizedBox.shrink()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
        ),
      ],
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? badge,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
    String? dropDstRoot,
    String dropDstRelPath = '',
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget buildTile(bool hoveringDrop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Material(
          color: hoveringDrop
              ? scheme.primaryContainer
              : selected
                  ? scheme.secondaryContainer
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: hoveringDrop
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.primary, width: 1.5),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(icon, size: 17, color: iconColor),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (dropDstRoot == null) return buildTile(false);
    return DragTarget<({String root, List<String> paths})>(
      onAcceptWithDetails: (details) => _acceptSidebarDrop(
        details.data,
        dstRoot: dropDstRoot,
        dstRelPath: dropDstRelPath,
        label: title,
      ),
      builder: (_, candidate, _) => buildTile(candidate.isNotEmpty),
    );
  }

  Widget _railItem({
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
    String? badge,
    String? dropDstRoot,
    String dropDstRelPath = '',
  }) {
    final scheme = Theme.of(context).colorScheme;

    Widget buildButton(bool hoveringDrop) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Material(
            color: hoveringDrop
                ? scheme.primaryContainer
                : selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                height: 36,
                decoration: hoveringDrop
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.primary, width: 1.5),
                      )
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 19, color: iconColor),
                    if (badge != null)
                      Positioned(
                        top: 3,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (dropDstRoot == null) return buildButton(false);
    return DragTarget<({String root, List<String> paths})>(
      onAcceptWithDetails: (details) => _acceptSidebarDrop(
        details.data,
        dstRoot: dropDstRoot,
        dstRelPath: dropDstRelPath,
        label: tooltip,
      ),
      builder: (_, candidate, _) => buildButton(candidate.isNotEmpty),
    );
  }

  Widget _buildCollapsedRail(
    AppLocalizations l10n,
    ColorScheme scheme,
    List<QuickTarget> targets,
    List<UnlockedVaultDto> vaults,
    List<PinnedVaultEntry> lockedPinned,
  ) {
    final homeTarget = targets.isNotEmpty ? targets.first : null;
    return Column(
      children: [
        const SizedBox(height: 8),
        IconButton(
          key: const ValueKey('sidebar_expand_btn'),
          icon: const Icon(Icons.menu, size: 19),
          tooltip: l10n.expandSidebar,
          visualDensity: VisualDensity.compact,
          onPressed: _toggleSidebarCollapsed,
        ),
        IconButton(
          icon: const Icon(Icons.search, size: 18),
          tooltip: l10n.globalSearchHint,
          visualDensity: VisualDensity.compact,
          onPressed: _openGlobalSearch,
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              if (homeTarget != null)
                _railItem(
                  icon: Icons.home_outlined,
                  iconColor: scheme.primary,
                  tooltip: homeTarget.displayName(l10n),
                  selected: _section == _SidebarSection.browser &&
                      _activeKey == 'local:${homeTarget.root}:${homeTarget.relPath}',
                  dropDstRoot: homeTarget.root,
                  dropDstRelPath: homeTarget.relPath,
                  onTap: () => _navigateBrowser(
                    homeTarget.root,
                    homeTarget.relPath,
                    homeTarget.displayName(l10n),
                    'local:${homeTarget.root}:${homeTarget.relPath}',
                  ),
                ),
              _railItem(
                icon: Icons.photo_library_outlined,
                iconColor: const Color(0xFFD81B60),
                tooltip: l10n.gallery,
                selected: _section == _SidebarSection.gallery,
                onTap: () => setState(() => _section = _SidebarSection.gallery),
              ),
              for (final v in vaults)
                _railItem(
                  icon: Icons.lock_open_rounded,
                  iconColor: Colors.indigo,
                  tooltip: v.name,
                  selected: _section == _SidebarSection.browser &&
                      _activeKey == 'vault:${v.id}',
                  dropDstRoot: 'vault://${v.id}',
                  onTap: () => _navigateBrowser(
                    'vault://${v.id}',
                    '',
                    v.name,
                    'vault:${v.id}',
                  ),
                ),
              for (final p in lockedPinned)
                _railItem(
                  icon: Icons.lock_outline,
                  iconColor: scheme.onSurfaceVariant,
                  tooltip: p.name,
                  selected: false,
                  onTap: () async {
                    final unlocked = await OpenVaultDialog.show(
                      context,
                      initialName: p.name,
                    );
                    if (unlocked != null && mounted) {
                      _navigateBrowser(
                        'vault://${unlocked.id}',
                        '',
                        unlocked.name,
                        'vault:${unlocked.id}',
                      );
                    }
                  },
                ),
              if (vaults.isEmpty && lockedPinned.isEmpty)
                _railItem(
                  icon: Icons.enhanced_encryption_outlined,
                  iconColor: Colors.indigo,
                  tooltip: l10n.openPrivacyFolder,
                  selected: false,
                  onTap: _openVaultViaDialog,
                ),
              _railItem(
                icon: Icons.cloud_outlined,
                iconColor: const Color(0xFF1E88E5),
                tooltip: l10n.remote,
                selected: _section == _SidebarSection.remotes,
                onTap: () => _selectSection(_SidebarSection.remotes),
              ),
              _railItem(
                icon: Icons.bookmark_outline,
                iconColor: const Color(0xFFFB8C00),
                tooltip: l10n.bookmarks,
                selected: _section == _SidebarSection.bookmarks,
                onTap: () => _selectSection(_SidebarSection.bookmarks),
              ),
              _railItem(
                icon: Icons.history,
                iconColor: const Color(0xFF3949AB),
                tooltip: l10n.recent,
                selected: _section == _SidebarSection.recent,
                onTap: () => _selectSection(_SidebarSection.recent),
              ),
              _railItem(
                icon: Icons.offline_pin_outlined,
                iconColor: Colors.indigo,
                tooltip: l10n.offlinePinned,
                selected: _section == _SidebarSection.offlinePinned,
                onTap: () => _selectSection(_SidebarSection.offlinePinned),
              ),
              _railItem(
                icon: Icons.wifi_tethering,
                iconColor: const Color(0xFF00897B),
                tooltip: l10n.lanPeerTransferTitle,
                selected: _section == _SidebarSection.peerTransfer,
                onTap: () => _selectSection(_SidebarSection.peerTransfer),
              ),
              _railItem(
                icon: Icons.add_photo_alternate_outlined,
                iconColor: const Color(0xFF7B1FA2),
                tooltip: l10n.photoBackupTitle,
                selected: _section == _SidebarSection.photoBackup,
                onTap: () => _selectSection(_SidebarSection.photoBackup),
              ),
              _railItem(
                icon: Icons.build_outlined,
                iconColor: const Color(0xFF5E35B1),
                tooltip: l10n.utilities,
                selected: _section == _SidebarSection.utilities,
                onTap: () => _selectSection(_SidebarSection.utilities),
              ),
              _railItem(
                icon: Icons.task_alt,
                iconColor: const Color(0xFF00897B),
                tooltip: l10n.tasks,
                badge: widget.activeTaskCount > 0 ? '${widget.activeTaskCount}' : null,
                selected: _section == _SidebarSection.tasks,
                onTap: () => _selectSection(_SidebarSection.tasks),
              ),
              _railItem(
                icon: Icons.delete_outline,
                iconColor: Colors.redAccent,
                tooltip: l10n.recycleBin,
                badge: widget.trashCount > 0 ? '${widget.trashCount}' : null,
                selected: _section == _SidebarSection.trash,
                onTap: () => _selectSection(_SidebarSection.trash),
              ),
              _railItem(
                icon: Icons.settings_outlined,
                iconColor: const Color(0xFF546E7A),
                tooltip: l10n.settings,
                selected: _section == _SidebarSection.settings,
                onTap: () => _selectSection(_SidebarSection.settings),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedSidebar(
    AppLocalizations l10n,
    ColorScheme scheme,
    List<QuickTarget> targets,
    List<UnlockedVaultDto> vaults,
    List<PinnedVaultEntry> lockedPinned,
    DiskSpaceDto? disk,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
          child: Row(
            children: [
              Icon(Icons.folder_special, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.appTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 18),
                tooltip: l10n.globalSearchHint,
                visualDensity: VisualDensity.compact,
                onPressed: _openGlobalSearch,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 17),
                tooltip: l10n.refresh,
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRefreshMetadata,
              ),
              IconButton(
                key: const ValueKey('sidebar_collapse_btn'),
                icon: const Icon(Icons.menu_open, size: 18),
                tooltip: l10n.collapseSidebar,
                visualDensity: VisualDensity.compact,
                onPressed: _toggleSidebarCollapsed,
              ),
            ],
          ),
        ),
        if (disk != null && disk.totalBytes > BigInt.zero)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: (disk.usedBytes.toDouble() / disk.totalBytes.toDouble())
                        .clamp(0.0, 1.0),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.storageUsedOf(
                    formatBytes(disk.usedBytes),
                    formatBytes(disk.totalBytes),
                    formatBytes(disk.availableBytes),
                  ),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              _collapsibleSection(
                groupId: 'local',
                title: l10n.localStorage,
                itemCount: targets.length,
                children: [
                  for (final t in targets)
                    _sidebarItem(
                      icon: t.kind == 'home'
                          ? Icons.home_outlined
                          : t.kind == 'downloads' || t.kind == 'download'
                              ? Icons.download_outlined
                              : Icons.storage_outlined,
                      iconColor: scheme.primary,
                      title: t.displayName(l10n),
                      selected: _section == _SidebarSection.browser &&
                          _activeKey == 'local:${t.root}:${t.relPath}',
                      dropDstRoot: t.root,
                      dropDstRelPath: t.relPath,
                      onTap: () => _navigateBrowser(
                        t.root,
                        t.relPath,
                        t.displayName(l10n),
                        'local:${t.root}:${t.relPath}',
                      ),
                    ),
                ],
              ),
              _collapsibleSection(
                groupId: 'vaults',
                title: l10n.privacyFolders,
                itemCount: vaults.length + lockedPinned.length,
                trailing: IconButton(
                  key: const ValueKey('sidebar_create_vault_btn'),
                  icon: Icon(
                    Icons.add,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  tooltip: l10n.createPrivacyFolder,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: _createVaultViaDialog,
                ),
                children: [
                  for (final v in vaults)
                    _sidebarItem(
                      icon: Icons.lock_open_rounded,
                      iconColor: Colors.indigo,
                      title: v.name,
                      selected: _section == _SidebarSection.browser &&
                          _activeKey == 'vault:${v.id}',
                      dropDstRoot: 'vault://${v.id}',
                      onTap: () => _navigateBrowser(
                        'vault://${v.id}',
                        '',
                        v.name,
                        'vault:${v.id}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.lock_outline, size: 15),
                        tooltip: l10n.lockVaultNow,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => VaultService.instance.lockVault(v.id),
                      ),
                    ),
                  for (final p in lockedPinned)
                    _sidebarItem(
                      icon: Icons.lock_outline,
                      iconColor: scheme.onSurfaceVariant,
                      title: p.name,
                      badge: l10n.lockedBadge,
                      selected: false,
                      onTap: () async {
                        final unlocked = await OpenVaultDialog.show(
                          context,
                          initialName: p.name,
                        );
                        if (unlocked != null && mounted) {
                          _navigateBrowser(
                            'vault://${unlocked.id}',
                            '',
                            unlocked.name,
                            'vault:${unlocked.id}',
                          );
                        }
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: l10n.vaultUnpinAlwaysVisible,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => VaultService.instance.unpinVault(p.id),
                      ),
                    ),
                  _sidebarItem(
                    icon: Icons.enhanced_encryption_outlined,
                    iconColor: Colors.indigo,
                    title: l10n.openPrivacyFolder,
                    selected: false,
                    onTap: _openVaultViaDialog,
                  ),
                  _sidebarItem(
                    icon: Icons.create_new_folder_outlined,
                    iconColor: Colors.teal,
                    title: l10n.createPrivacyFolder,
                    selected: false,
                    onTap: _createVaultViaDialog,
                  ),
                ],
              ),
              _collapsibleSection(
                groupId: 'remotes',
                title: l10n.remote,
                itemCount: widget.remotes.length,
                trailing: IconButton(
                  key: const ValueKey('sidebar_add_remote_btn'),
                  icon: Icon(
                    Icons.add,
                    size: 16,
                    color: _section == _SidebarSection.remotes
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  tooltip: l10n.remote,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setState(() => _section = _SidebarSection.remotes),
                ),
                children: [
                  for (final r in widget.remotes)
                    _sidebarItem(
                      icon: Icons.cloud_outlined,
                      iconColor: const Color(0xFF1E88E5),
                      title: r.name,
                      selected: _section == _SidebarSection.browser &&
                          _activeKey == 'remote:${r.id}',
                      dropDstRoot: 'remote://${r.id}',
                      onTap: () => _navigateBrowser(
                        'remote://${r.id}',
                        '',
                        r.name,
                        'remote:${r.id}',
                      ),
                    ),
                  if (widget.remotes.isEmpty)
                    _sidebarItem(
                      icon: Icons.add_circle_outline,
                      iconColor: const Color(0xFF1E88E5),
                      title: l10n.addConnection,
                      selected: _section == _SidebarSection.remotes,
                      onTap: () => setState(() => _section = _SidebarSection.remotes),
                    ),
                ],
              ),
              if (widget.bookmarks.isNotEmpty)
                _collapsibleSection(
                  groupId: 'bookmarks',
                  title: l10n.bookmarks,
                  itemCount: widget.bookmarks.length,
                  trailing: IconButton(
                    key: const ValueKey('sidebar_manage_bookmarks_btn'),
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 15,
                      color: _section == _SidebarSection.bookmarks
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    tooltip: l10n.bookmarkActions,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    onPressed: () => setState(() => _section = _SidebarSection.bookmarks),
                  ),
                  children: [
                    for (final bm in widget.bookmarks)
                      _sidebarItem(
                        icon: Icons.bookmark_outline,
                        iconColor: const Color(0xFFFB8C00),
                        title: bm.name,
                        selected: _section == _SidebarSection.browser &&
                            _activeKey == 'bm:${bm.id}',
                        dropDstRoot: bm.root,
                        dropDstRelPath: bm.path,
                        onTap: () => _navigateBrowser(
                          bm.root,
                          bm.path,
                          bm.name,
                          'bm:${bm.id}',
                        ),
                      ),
                  ],
                ),
              _collapsibleSection(
                groupId: 'discover',
                title: l10n.navDomainDiscover,
                itemCount: widget.bookmarks.isEmpty ? 4 : 3,
                children: [
                  _sidebarItem(
                    icon: Icons.photo_library_outlined,
                    iconColor: const Color(0xFFD81B60),
                    title: l10n.gallery,
                    selected: _section == _SidebarSection.gallery,
                    onTap: () => setState(() => _section = _SidebarSection.gallery),
                  ),
                  if (widget.bookmarks.isEmpty)
                    _sidebarItem(
                      icon: Icons.bookmark_border,
                      iconColor: const Color(0xFFFB8C00),
                      title: l10n.bookmarks,
                      selected: _section == _SidebarSection.bookmarks,
                      onTap: () => setState(() => _section = _SidebarSection.bookmarks),
                    ),
                  _sidebarItem(
                    icon: Icons.history,
                    iconColor: const Color(0xFF3949AB),
                    title: l10n.recent,
                    selected: _section == _SidebarSection.recent,
                    onTap: () => setState(() => _section = _SidebarSection.recent),
                  ),
                  _sidebarItem(
                    icon: Icons.offline_pin_outlined,
                    iconColor: Colors.indigo,
                    title: l10n.offlinePinned,
                    selected: _section == _SidebarSection.offlinePinned,
                    onTap: () => setState(() => _section = _SidebarSection.offlinePinned),
                  ),
                ],
              ),
              _collapsibleSection(
                groupId: 'tools',
                title: l10n.navDomainTools,
                itemCount: 6,
                children: [
                  _sidebarItem(
                    icon: Icons.wifi_tethering,
                    iconColor: const Color(0xFF00897B),
                    title: l10n.lanPeerTransferTitle,
                    selected: _section == _SidebarSection.peerTransfer,
                    onTap: () => _selectSection(_SidebarSection.peerTransfer),
                  ),
                  _sidebarItem(
                    icon: Icons.add_photo_alternate_outlined,
                    iconColor: const Color(0xFF7B1FA2),
                    title: l10n.photoBackupTitle,
                    selected: _section == _SidebarSection.photoBackup,
                    onTap: () => _selectSection(_SidebarSection.photoBackup),
                  ),
                  _sidebarItem(
                    icon: Icons.build_outlined,
                    iconColor: const Color(0xFF5E35B1),
                    title: l10n.utilities,
                    selected: _section == _SidebarSection.utilities,
                    onTap: () => _selectSection(_SidebarSection.utilities),
                  ),
                  _sidebarItem(
                    icon: Icons.task_alt,
                    iconColor: const Color(0xFF00897B),
                    title: l10n.tasks,
                    badge: widget.activeTaskCount > 0 ? '${widget.activeTaskCount}' : null,
                    selected: _section == _SidebarSection.tasks,
                    onTap: () => _selectSection(_SidebarSection.tasks),
                  ),
                  _sidebarItem(
                    icon: Icons.delete_outline,
                    iconColor: Colors.redAccent,
                    title: l10n.recycleBin,
                    badge: widget.trashCount > 0 ? '${widget.trashCount}' : null,
                    selected: _section == _SidebarSection.trash,
                    onTap: () => _selectSection(_SidebarSection.trash),
                  ),
                  _sidebarItem(
                    icon: Icons.settings_outlined,
                    iconColor: const Color(0xFF546E7A),
                    title: l10n.settings,
                    selected: _section == _SidebarSection.settings,
                    onTap: () => _selectSection(_SidebarSection.settings),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final targets = PlatformPaths.quickTargets();
    final vaults = VaultService.instance.unlockedVaults;
    final lockedPinned = VaultService.instance.lockedPinnedVaults;
    final disk = widget.diskSpace;
    final targetWidth = _collapsed ? _collapsedWidth : _sidebarWidth;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // Persistent Left Sidebar (collapsible to 52px rail, user-resizable)
            AnimatedContainer(
              duration: _draggingSplitter
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: targetWidth,
              color: scheme.surfaceContainerLow,
              child: ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.topStart,
                  minWidth: targetWidth,
                  maxWidth: targetWidth,
                  child: _collapsed
                      ? _buildCollapsedRail(l10n, scheme, targets, vaults, lockedPinned)
                      : _buildExpandedSidebar(l10n, scheme, targets, vaults, lockedPinned, disk),
                ),
              ),
            ),
            // Draggable sidebar splitter (static divider when collapsed)
            if (_collapsed)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).dividerColor,
              )
            else
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) => setState(() => _draggingSplitter = true),
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _sidebarWidth =
                          (_sidebarWidth + details.delta.dx).clamp(196.0, 360.0);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    setState(() => _draggingSplitter = false);
                    PreferencesService.instance.sidebarWidth = _sidebarWidth;
                  },
                  onHorizontalDragCancel: () =>
                      setState(() => _draggingSplitter = false),
                  child: SizedBox(
                    width: 5,
                    height: double.infinity,
                    child: Center(
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                ),
              ),
            // Right Main Workspace Area
            Expanded(
              child: Column(
                children: [
                  if (widget.topBanner != null) widget.topBanner!,
                  Expanded(
                    child: widget.workspaceOverride ??
                        IndexedStack(
                          index: _section == _SidebarSection.browser ? 0 : 1,
                          children: [
                            BrowserWorkspacePage(
                              key: _workspaceKey,
                              initialRoot: _defaultRoot,
                              initialTitle: l10n.localStorage,
                              embedded: true,
                            ),
                            _buildSecondarySection(),
                          ],
                        ),
                  ),
                  ActiveTasksBanner(
                    onTap: () => setState(() => _section = _SidebarSection.tasks),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondarySection() {
    switch (_section) {
      case _SidebarSection.gallery:
        return const GalleryPage();
      case _SidebarSection.remotes:
        return const RemotesPage();
      case _SidebarSection.bookmarks:
        return const BookmarksPage();
      case _SidebarSection.recent:
        return const RecentPage();
      case _SidebarSection.offlinePinned:
        return const OfflinePinnedPage();
      case _SidebarSection.peerTransfer:
        return const PeerTransferPage();
      case _SidebarSection.photoBackup:
        return const PhotoBackupPage();
      case _SidebarSection.utilities:
        return const UtilitiesPage();
      case _SidebarSection.tasks:
        return const TasksPage();
      case _SidebarSection.trash:
        return const TrashPage();
      case _SidebarSection.settings:
        return SettingsPage(
          currentThemeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
          localeCode: widget.localeCode ?? 'system',
          onLocaleChanged: widget.onLocaleChanged ?? (_) {},
          accentCode: widget.accentCode ?? 'dynamic',
          onAccentChanged: widget.onAccentChanged ?? (_) {},
        );
      case _SidebarSection.browser:
        return const SizedBox.shrink();
    }
  }
}
