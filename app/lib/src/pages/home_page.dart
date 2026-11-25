import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/inspect.dart';
import '../rust/api/metadata.dart';
import '../rust/api/pool.dart';
import '../rust/api/remotes.dart';
import '../rust/api/vault.dart';
import '../dialogs/advanced_search_dialog.dart';
import '../dialogs/vault_dialogs.dart';
import '../services/app_route_observer.dart';
import '../services/global_playback_service.dart';
import '../services/permission_service.dart';
import '../services/pool_service.dart';
import '../services/preferences_service.dart';
import '../services/semantic_colors.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/active_tasks_banner.dart';
import '../widgets/desktop_sidebar_shell.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'bookmarks_page.dart';
import 'browser_page.dart';
import 'category_files_page.dart';
import 'gallery_page.dart';
import 'offline_pinned_page.dart';
import 'peer_transfer_page.dart';
import 'photo_backup_page.dart';
import 'pool_dashboard_page.dart';
import 'recent_page.dart';
import 'remotes_page.dart';
import 'storage_analyzer_page.dart';
import 'settings_page.dart';
import 'sync_page.dart';
import 'tasks_page.dart';
import 'trash_page.dart';
import 'utilities_page.dart';
import '../services/external_file_service.dart';
import '../services/platform_capabilities.dart';
import '../services/shortcut_service.dart';
import '../services/vault_service.dart';

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final String? localeCode;
  final ValueChanged<String>? onLocaleChanged;
  final String? accentCode;
  final ValueChanged<String>? onAccentChanged;
  final ExternalPickRequest? pickRequest;

  const HomePage({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.localeCode,
    this.onLocaleChanged,
    this.accentCode,
    this.onAccentChanged,
    this.pickRequest,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<RemoteConfigDto> _remotes = [];
  List<BookmarkDto> _bookmarks = [];
  List<HistoryDto> _history = [];
  int _trashCount = 0;
  int _activeTaskCount = 0;
  DiskSpaceDto? _diskSpace;
  bool _hasStorageAccess = true;
  bool _requestingAccess = false;
  bool _welcomeDismissed = false;
  int _domainIndex = 0;

  static const _prefWelcomeDismissed = 'home.welcome_dismissed';
  StreamSubscription<ShortcutTarget>? _shortcutSub;
  Timer? _taskBadgeTimer;

  @override
  void initState() {
    super.initState();
    _welcomeDismissed =
        PreferencesService.instance.getBool(_prefWelcomeDismissed) ?? false;
    WidgetsBinding.instance.addObserver(this);
    VaultService.instance.addListener(_onVaultChanged);
    PoolService.instance.addListener(_onPoolChanged);
    _loadMetadata();
    _checkStorageAccess();
    _shortcutSub = ShortcutService.instance.onShortcutOpened.listen((target) {
      if (mounted) _openShortcutTarget(target);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePendingShortcut();
    });
  }

  Future<void> _consumePendingShortcut() async {
    final target = await ShortcutService.instance.consumeInitialShortcut();
    if (target != null && mounted) {
      _openShortcutTarget(target);
    }
  }

  void _openShortcutTarget(ShortcutTarget target) {
    if (target.type == 'sync') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SyncPage()),
      );
      return;
    }
    if (target.root.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: target.root,
          initialPath: target.path,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _taskBadgeTimer?.cancel();
    _shortcutSub?.cancel();
    VaultService.instance.removeListener(_onVaultChanged);
    PoolService.instance.removeListener(_onPoolChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) setState(() {});
  }

  void _onPoolChanged() {
    if (mounted) setState(() {});
  }

  /// The grant happens in the system Settings app, so the banner only clears
  /// on the next resume unless the check runs again here.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkStorageAccess();
  }

  /// First-run guidance: shown only while there is nothing configured
  /// yet — no connections, no bookmarks, no history — and until dismissed.
  bool get _showWelcome =>
      !_welcomeDismissed &&
      _remotes.isEmpty &&
      _bookmarks.isEmpty &&
      _history.isEmpty;

  Widget _buildWelcomeBanner() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.waving_hand_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).welcomeTitle,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).welcomeBody,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RemotesPage()),
                      ).then((_) => _loadMetadata());
                    },
                    child: Text(AppLocalizations.of(context).connectServer),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: AppLocalizations.of(context).dismiss,
              onPressed: () {
                PreferencesService.instance.setBool(_prefWelcomeDismissed, true);
                setState(() => _welcomeDismissed = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Live count of running tasks for the Tasks card subtitle. Cheap sync
  /// FFI call; refreshed alongside the other home metadata.
  void _refreshTaskCount() {
    try {
      final active = TaskService.instance
          .list()
          .where((t) => t.state == 'pending' || t.state == 'running')
          .length;
      if (active > 0) {
        _taskBadgeTimer ??= Timer.periodic(
          const Duration(seconds: 2),
          (_) => _refreshTaskCount(),
        );
      } else {
        _taskBadgeTimer?.cancel();
        _taskBadgeTimer = null;
      }
      if (mounted && active != _activeTaskCount) {
        setState(() => _activeTaskCount = active);
      }
    } catch (_) {
      // Tasks registry not ready yet (first frames): leave the count at 0.
    }
  }

  Future<void> _checkStorageAccess() async {
    if (!PlatformCapabilities.supportsStoragePermissionBanner) return;
    bool granted;
    try {
      granted = await PermissionService.instance.hasStorageAccess();
    } catch (_) {
      // Keep the banner hidden rather than claiming access is fine; the
      // first real file operation still reports the missing permission.
      return;
    }
    if (mounted) setState(() => _hasStorageAccess = granted);
  }

  Future<void> _requestStorageAccess() async {
    // No busy state meant a slow permission prompt looked like a dead button,
    // and a throw left the banner with no explanation.
    if (_requestingAccess) return;
    setState(() => _requestingAccess = true);
    try {
      final granted = await PermissionService.instance.requestStorageAccess();
      if (mounted) setState(() => _hasStorageAccess = granted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRequestFileAccess('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingAccess = false);
    }
  }

  Future<void> _loadMetadata() async {
    // A failing metadata read used to leave the cards showing stale counts
    // with no hint that they were stale.
    try {
      final results = await Future.wait([
        StorageService.instance.getRemotes(),
        StorageService.instance.getBookmarks(),
        StorageService.instance.getHistory(),
        StorageService.instance.getTrashCount(),
      ]);

      if (mounted) {
        setState(() {
          _remotes = results[0] as List<RemoteConfigDto>;
          _bookmarks = results[1] as List<BookmarkDto>;
          _history = results[2] as List<HistoryDto>;
          _trashCount = results[3] as int;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotRefreshHome('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(label: AppLocalizations.of(context).retry, onPressed: _loadMetadata),
          ),
        );
      }
    }
    _refreshTaskCount();
    try {
      await PoolService.instance.refresh();
    } catch (_) {}
    try {
      final space = getDiskSpace(path: PlatformPaths.defaultRoot());
      if (mounted) setState(() => _diskSpace = space);
    } catch (_) {}
  }

  Future<void> _openGlobalSearch({
    String initialCategory = 'all',
    String? initialRoot,
    String? initialRelPath,
    void Function(String root, String relPath, String title)? onNavigate,
  }) async {
    final l10n = AppLocalizations.of(context);
    final defaultRoot = PlatformPaths.defaultRoot();
    final searchRoot = initialRoot ?? defaultRoot;
    final searchRel = initialRelPath ?? '';

    final extraScopes = <({String root, String relPath})>[];
    if (searchRoot != defaultRoot) {
      extraScopes.add((root: defaultRoot, relPath: ''));
    }
    var localBookmarkScopes = 0;
    for (final bm in _bookmarks) {
      if (localBookmarkScopes >= 5) break;
      final r = bm.root;
      if (r.startsWith('remote://') || r.startsWith('vault://') || r.startsWith('pool://')) continue;
      final normRoot = r.replaceAll('\\', '/');
      final isBare = bm.path.isEmpty &&
          (normRoot == '/' || RegExp(r'^[A-Za-z]:/?$').hasMatch(normRoot));
      if (isBare) continue;
      extraScopes.add((root: bm.root, relPath: bm.path));
      localBookmarkScopes++;
    }

    final sources = GlobalSearchSources(
      bookmarks: _bookmarks,
      history: _history,
      remotes: _remotes,
      pools: PoolService.instance.pools,
      quickTargets: PlatformPaths.quickTargets(),
      unlockedVaults: VaultService.instance.unlockedVaults,
      lockedPinnedVaults: VaultService.instance.lockedPinnedVaults,
    );

    final picked = await showAdvancedSearchDialog(
      context,
      root: searchRoot,
      relPath: searchRel,
      initialCategory: initialCategory,
      globalSources: sources,
      extraSearchScopes: extraScopes,
    );
    if (picked == null || !mounted) return;

    void navigate(String root, String relPath, String title) {
      if (onNavigate != null) {
        onNavigate(root, relPath, title);
      } else {
        _openTarget(root, relPath);
      }
    }

    switch (picked.kind) {
      case AdvancedSearchSelectionKind.entry:
        final entry = picked.entry;
        if (entry == null) return;
        final targetRoot = picked.entryRoot ?? searchRoot;
        final rel = entry.isDir
            ? entry.path
            : (entry.path.contains('/')
                ? entry.path.substring(0, entry.path.lastIndexOf('/'))
                : '');
        navigate(targetRoot, rel, entry.name);
      case AdvancedSearchSelectionKind.bookmark:
        final bm = picked.bookmark;
        if (bm == null) return;
        navigate(bm.root, bm.path, bm.name);
      case AdvancedSearchSelectionKind.history:
        final h = picked.history;
        if (h == null) return;
        final title = h.path.isEmpty ? h.root : h.path.split('/').last;
        navigate(h.root, h.path, title);
      case AdvancedSearchSelectionKind.remote:
        final r = picked.remote;
        if (r == null) return;
        navigate('remote://${r.id}', '', r.name);
      case AdvancedSearchSelectionKind.pool:
        final pool = picked.pool;
        if (pool == null) return;
        navigate('pool://${pool.id}', '', pool.name);
      case AdvancedSearchSelectionKind.quickTarget:
        final t = picked.quickTarget;
        if (t == null) return;
        navigate(t.root, t.relPath, t.displayName(l10n));
      case AdvancedSearchSelectionKind.unlockedVault:
        final v = picked.unlockedVault;
        if (v == null) return;
        navigate('vault://${v.id}', '', v.name);
      case AdvancedSearchSelectionKind.lockedPinnedVault:
        final v = picked.lockedPinnedVault;
        if (v == null) return;
        final unlocked = await OpenVaultDialog.show(context, initialName: v.name);
        if (unlocked != null && mounted) {
          navigate('vault://${unlocked.id}', '', unlocked.name);
        }
    }
  }

  bool get _pickMode => widget.pickRequest != null;

  Future<void> _openCategory(String category) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CategoryFilesPage(
          category: category,
          root: PlatformPaths.defaultRoot(),
        ),
      ),
    );
    if (mounted) _loadMetadata();
  }

  void _openTarget(String root, String relPath) async {
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: root,
          initialPath: relPath,
          pickRequest: widget.pickRequest,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      Navigator.of(context).pop(picked);
      return;
    }
    _loadMetadata();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    if (isWide && !_pickMode) {
      return DesktopSidebarShell(
        remotes: _remotes,
        bookmarks: _bookmarks,
        history: _history,
        trashCount: _trashCount,
        activeTaskCount: _activeTaskCount,
        diskSpace: _diskSpace,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        localeCode: widget.localeCode,
        onLocaleChanged: widget.onLocaleChanged,
        accentCode: widget.accentCode,
        onAccentChanged: widget.onAccentChanged,
        onRefreshMetadata: _loadMetadata,
        onOpenGlobalSearch: ({root, relPath, onNavigate}) => _openGlobalSearch(
          initialRoot: root,
          initialRelPath: relPath,
          onNavigate: onNavigate,
        ),
        topBanner: !_hasStorageAccess
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _buildPermissionBanner(),
              )
            : null,
      );
    }

    final l10n = AppLocalizations.of(context);
    final effectiveDomain = _pickMode ? _domainIndex.clamp(0, 1) : _domainIndex.clamp(0, 2);
    return _HomeBottomInsetReporter(
      inset: 80.0,
      child: Scaffold(
      appBar: AppBar(
        leading: _pickMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          _pickMode
              ? (widget.pickRequest!.allowMultiple
                  ? l10n.pickFilesTitle
                  : l10n.pickFileTitle)
              : l10n.appTitle,
        ),
        actions: [
          if (!_pickMode)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: l10n.globalSearchHint,
              onPressed: () => _openGlobalSearch(),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMetadata,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppUiTokens.pagePadding,
                children: switch (effectiveDomain) {
                  0 => _buildStorageDomainChildren(l10n),
                  1 => _buildDiscoverDomainChildren(l10n),
                  _ => _buildToolsDomainChildren(l10n),
                },
              ),
            ),
          ),
          if (!_pickMode) const ActiveTasksBanner(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: effectiveDomain,
        onDestinationSelected: (idx) {
          setState(() => _domainIndex = idx);
          _refreshTaskCount();
        },
        destinations: [
          NavigationDestination(
            key: const ValueKey('home_nav_storage'),
            icon: const Icon(Icons.storage_outlined),
            selectedIcon: const Icon(Icons.storage),
            label: l10n.navDomainStorage,
          ),
          NavigationDestination(
            key: const ValueKey('home_nav_discover'),
            icon: const Icon(Icons.manage_search_outlined),
            selectedIcon: const Icon(Icons.manage_search),
            label: l10n.navDomainDiscover,
          ),
          if (!_pickMode)
            NavigationDestination(
              key: const ValueKey('home_nav_tools'),
              icon: Badge(
                isLabelVisible: _activeTaskCount > 0,
                label: Text('$_activeTaskCount'),
                child: const Icon(Icons.handyman_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _activeTaskCount > 0,
                label: Text('$_activeTaskCount'),
                child: const Icon(Icons.handyman),
              ),
              label: l10n.navDomainTools,
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildGlobalSearchBar(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: AppUiTokens.borderRadiusMd,
      onTap: () => _openGlobalSearch(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: AppUiTokens.borderRadiusMd,
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.globalSearchHint,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskSpaceBar(AppLocalizations l10n, DiskSpaceDto disk) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = (disk.usedBytes.toDouble() / disk.totalBytes.toDouble()).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: AppUiTokens.borderRadiusMd,
      onTap: () {
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => StorageAnalyzerPage(
                  root: PlatformPaths.defaultRoot(),
                  title: l10n.localStorage,
                ),
              ),
            )
            .then((_) => _loadMetadata());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: AppUiTokens.borderRadiusMd,
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_outline, size: 15, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.storageUsedOf(
                      formatBytes(disk.usedBytes),
                      formatBytes(disk.totalBytes),
                      formatBytes(disk.availableBytes),
                    ),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: ratio, minHeight: 5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_off_outlined, size: 20, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).storagePermissionRequired,
              style: TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: Theme.of(context).colorScheme.warning,
            ),
            onPressed: _requestingAccess ? null : _requestStorageAccess,
            child: Text(
              _requestingAccess ? AppLocalizations.of(context).requesting : AppLocalizations.of(context).grant,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSectionGrid({
    required List<Widget> children,
    double childAspectRatio = 2.8,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final mainExtent = (60.0 * textScale).clamp(60.0, 96.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : (constraints.maxWidth > 520 ? 3 : 2);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            mainAxisExtent: math.max(mainExtent, 150 / childAspectRatio),
          ),
          itemCount: children.length,
          itemBuilder: (_, i) => children[i],
        );
      },
    );
  }

  Widget _buildGridCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: AppUiTokens.borderRadiusMd,
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppUiTokens.borderRadiusMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                AppCircleBadge(
                  icon: icon,
                  color: iconColor,
                  size: 28,
                  iconSize: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 9.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 14, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStorageDomainChildren(AppLocalizations l10n) {
    final targets = PlatformPaths.quickTargets()
        .where((t) => !_pickMode || t.kind != 'inbox')
        .toList();
    final unlocked = VaultService.instance.unlockedVaults;
    final lockedPinned = VaultService.instance.lockedPinnedVaults;
    final pools = PoolService.instance.pools;

    return [
      if (!_hasStorageAccess) ...[
        _buildPermissionBanner(),
        const SizedBox(height: 8),
      ],
      if (_showWelcome) ...[
        _buildWelcomeBanner(),
        const SizedBox(height: 8),
      ],
      _sectionHeader(l10n.localStorage),
      if (_diskSpace != null && _diskSpace!.totalBytes > BigInt.zero) ...[
        _buildDiskSpaceBar(l10n, _diskSpace!),
        const SizedBox(height: 8),
      ],
      _buildSectionGrid(
        children: targets.map((t) {
          IconData icon;
          Color iconColor;
          switch (t.kind) {
            case 'download':
            case 'downloads':
              icon = Icons.download;
              iconColor = Colors.teal;
            case 'inbox':
              icon = Icons.inbox_rounded;
              iconColor = Colors.amber.shade700;
            case 'dcim':
            case 'pictures':
              icon = Icons.photo_library;
              iconColor = Colors.purple;
            case 'documents':
              icon = Icons.description;
              iconColor = Colors.indigo;
            case 'home':
              icon = Icons.home;
              iconColor = Colors.deepOrange;
            default:
              icon = Icons.storage;
              iconColor = Colors.blueGrey;
          }
          return _buildGridCard(
            icon: icon,
            iconColor: iconColor,
            title: t.displayName(l10n),
            subtitle: t.kind == 'inbox' ? l10n.privateInboxSubtitle : t.path,
            onTap: () => _openTarget(t.root, t.relPath),
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: t.path));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.copiedPathValue(t.path))),
              );
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      _sectionHeader(l10n.remote),
      _buildSectionGrid(
        children: [
          for (final r in _remotes)
            _buildGridCard(
              icon: Icons.cloud_done_outlined,
              iconColor: const Color(0xFF1E88E5),
              title: r.name,
              subtitle: r.kind.toUpperCase(),
              onTap: () => _openTarget('remote://${r.id}', ''),
            ),
          _buildGridCard(
            icon: Icons.cloud,
            iconColor: const Color(0xFF1E88E5),
            title: l10n.manageRemotes,
            subtitle: _remotes.isEmpty
                ? l10n.remoteProtocolsSubtitle
                : l10n.itemCountConnections(_remotes.length),
            onTap: () async {
              final picked = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => RemotesPage(pickRequest: widget.pickRequest),
                ),
              );
              if (picked != null && picked.isNotEmpty && mounted) {
                Navigator.of(context).pop(picked);
                return;
              }
              _loadMetadata();
            },
          ),
        ],
      ),
      if (!_pickMode) ...[
        const SizedBox(height: 12),
        _sectionHeader(l10n.storagePools),
        _buildSectionGrid(
          children: [
            for (final PoolSummaryDto p in pools)
              _buildGridCard(
                icon: Icons.hub_rounded,
                iconColor: p.degradedChunks > BigInt.zero
                    ? Colors.orange
                    : const Color(0xFF00897B),
                title: p.name,
                subtitle: p.degradedChunks > BigInt.zero
                    ? '${l10n.poolNodesCount(p.nodes.length)} · ⚠ ${p.degradedChunks}'
                    : '${l10n.poolNodesCount(p.nodes.length)} · ${formatBytes(p.effectiveLogicalCapacity)}',
                onTap: () => _openTarget('pool://${p.id}', ''),
              ),
            _buildGridCard(
              icon: Icons.hub_outlined,
              iconColor: const Color(0xFF00897B),
              title: l10n.manageStoragePools,
              subtitle: pools.isEmpty
                  ? l10n.storagePoolsSubtitle
                  : l10n.itemCountPools(pools.length),
              onTap: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const PoolDashboardPage()))
                    .then((_) => _loadMetadata());
              },
            ),
          ],
        ),
        if (unlocked.isNotEmpty || lockedPinned.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionHeader(l10n.privacyFolders),
          _buildSectionGrid(
            children: [
              for (final vault in unlocked)
                _buildGridCard(
                  icon: Icons.lock_open_rounded,
                  iconColor: Colors.indigo,
                  title: vault.name,
                  subtitle: l10n.unlockedBadge,
                  onTap: () => _openTarget('vault://${vault.id}', ''),
                  onLongPress: () => _showUnlockedVaultActions(vault),
                ),
              for (final pinned in lockedPinned)
                _buildGridCard(
                  icon: Icons.lock_outline,
                  iconColor: Colors.blueGrey,
                  title: pinned.name,
                  subtitle: l10n.lockedBadge,
                  onTap: () => _openLockedPinnedVault(pinned),
                  onLongPress: () => _showLockedPinnedVaultActions(pinned),
                ),
            ],
          ),
        ],
      ],
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildDiscoverDomainChildren(AppLocalizations l10n) {
    return [
      if (!_pickMode) ...[
        _buildGlobalSearchBar(l10n),
        const SizedBox(height: 12),
      ],
      _sectionHeader(l10n.navDomainDiscover),
      _buildSectionGrid(
        children: [
          _buildGridCard(
            icon: Icons.photo_library,
            iconColor: const Color(0xFFD81B60),
            title: l10n.gallery,
            subtitle: l10n.allPhotos,
            onTap: () async {
              final picked = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => GalleryPage(pickRequest: widget.pickRequest),
                ),
              );
              if (picked != null && picked.isNotEmpty && mounted) {
                Navigator.of(context).pop(picked);
                return;
              }
              _loadMetadata();
            },
          ),
          if (!_pickMode &&
              PlatformCapabilities.supportsHomeSmartCategories) ...[
            _buildGridCard(
              icon: Icons.description_outlined,
              iconColor: const Color(0xFF1E88E5),
              title: l10n.categoryDocuments,
              subtitle: 'PDF · DOC · MD',
              onTap: () => _openCategory('document'),
            ),
            _buildGridCard(
              icon: Icons.movie_outlined,
              iconColor: const Color(0xFFE53935),
              title: l10n.categoryVideos,
              subtitle: 'MP4 · MKV · MOV',
              onTap: () => _openCategory('video'),
            ),
            _buildGridCard(
              icon: Icons.audiotrack_outlined,
              iconColor: const Color(0xFF8E24AA),
              title: l10n.categoryAudio,
              subtitle: 'MP3 · FLAC · WAV',
              onTap: () => _openCategory('audio'),
            ),
            _buildGridCard(
              icon: Icons.folder_zip_outlined,
              iconColor: const Color(0xFFFB8C00),
              title: l10n.categoryArchives,
              subtitle: 'ZIP · 7Z · TAR',
              onTap: () => _openCategory('archive'),
            ),
            if (PlatformCapabilities.supportsInstallersCategory)
              _buildGridCard(
                icon: PlatformCapabilities.installerCategoryIcon,
                iconColor: const Color(0xFF00ACC1),
                title: l10n.categoryApks,
                subtitle: PlatformCapabilities.installerCategorySubtitle,
                onTap: () => _openCategory('apk'),
              ),
          ],
          _buildGridCard(
            icon: Icons.bookmark,
            iconColor: const Color(0xFFFB8C00),
            title: l10n.bookmarks,
            subtitle: _bookmarks.isEmpty
                ? l10n.bookmarksDefaultSubtitle
                : l10n.itemCountBookmarks(_bookmarks.length),
            onTap: () async {
              final picked = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => BookmarksPage(pickRequest: widget.pickRequest),
                ),
              );
              if (picked != null && picked.isNotEmpty && mounted) {
                Navigator.of(context).pop(picked);
                return;
              }
              _loadMetadata();
            },
          ),
          _buildGridCard(
            icon: Icons.history,
            iconColor: const Color(0xFF3949AB),
            title: l10n.recent,
            subtitle: _history.isEmpty
                ? l10n.recentDefaultSubtitle
                : l10n.itemCountLocations(_history.length),
            onTap: () async {
              final picked = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => RecentPage(pickRequest: widget.pickRequest),
                ),
              );
              if (picked != null && picked.isNotEmpty && mounted) {
                Navigator.of(context).pop(picked);
                return;
              }
              _loadMetadata();
            },
          ),
          if (!_pickMode)
            _buildGridCard(
              icon: Icons.offline_pin_outlined,
              iconColor: Colors.indigo,
              title: l10n.offlinePinned,
              subtitle: l10n.offlinePinnedSubtitle,
              onTap: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const OfflinePinnedPage()))
                    .then((_) => _loadMetadata());
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildToolsDomainChildren(AppLocalizations l10n) {
    return [
      _sectionHeader(l10n.navDomainTools),
      _buildSectionGrid(
        children: [
          _buildGridCard(
            icon: Icons.sync,
            iconColor: Colors.blue,
            title: l10n.directorySync,
            subtitle: l10n.directorySyncSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const SyncPage()),
                  )
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.swap_horiz,
            iconColor: Colors.indigo,
            title: l10n.lanTransferAndShareTitle,
            subtitle: l10n.lanTransferAndShareSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const PeerTransferPage()),
                  )
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.cloud_upload_outlined,
            iconColor: Colors.green,
            title: l10n.photoBackupTitle,
            subtitle: l10n.photoBackupSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(builder: (_) => const PhotoBackupPage()),
                  )
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.build_outlined,
            iconColor: const Color(0xFF5E35B1),
            title: l10n.utilities,
            subtitle: l10n.utilitiesDefaultSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const UtilitiesPage()))
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.task_alt,
            iconColor: const Color(0xFF00897B),
            title: l10n.tasks,
            subtitle: _activeTaskCount > 0
                ? l10n.activeTasksRunningCount(_activeTaskCount)
                : l10n.tasksDefaultSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TasksPage()))
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.delete_outline,
            iconColor: Colors.redAccent,
            title: l10n.recycleBin,
            subtitle: _trashCount > 0
                ? l10n.utilitiesTrashSubtitle(_trashCount)
                : l10n.emptyLabel,
            onTap: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const TrashPage()))
                  .then((_) => _loadMetadata());
            },
          ),
          _buildGridCard(
            icon: Icons.settings,
            iconColor: const Color(0xFF546E7A),
            title: l10n.settings,
            subtitle: l10n.settingsCardSubtitle,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(
                        currentThemeMode: widget.themeMode,
                        onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
                        localeCode: widget.localeCode ?? 'system',
                        onLocaleChanged: widget.onLocaleChanged ?? (_) {},
                        accentCode: widget.accentCode ?? 'dynamic',
                        onAccentChanged: widget.onAccentChanged ?? (_) {},
                        onConfigImported: _loadMetadata,
                      ),
                    ),
                  )
                  .then((_) => _loadMetadata());
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  Future<void> _openLockedPinnedVault(PinnedVaultEntry pinned) async {
    final unlocked = await OpenVaultDialog.show(
      context,
      initialName: pinned.name,
    );
    if (unlocked != null && mounted) {
      _openTarget('vault://${unlocked.id}', '');
    }
  }

  void _showLockedPinnedVaultActions(PinnedVaultEntry pinned) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: Text(l10n.vaultUnlockToOpen),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                if (!mounted) return;
                _openLockedPinnedVault(pinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: Text(l10n.vaultUnpinAlwaysVisible),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                VaultService.instance.unpinVault(pinned.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.vaultUnpinnedNotice(pinned.name))),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showUnlockedVaultActions(UnlockedVaultDto vault) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.push_pin_outlined),
                title: Text(l10n.vaultAlwaysVisibleTitle),
                subtitle: Text(
                  l10n.vaultAlwaysVisibleDesc,
                  style: const TextStyle(fontSize: 11),
                ),
                value: VaultService.instance.isAlwaysVisible(vault.id),
                onChanged: (val) {
                  VaultService.instance.setAlwaysVisible(
                    vaultId: vault.id,
                    name: vault.name,
                    alwaysVisible: val,
                  );
                  setSheetState(() {});
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.vaultFolderInfo),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  VaultInfoDialog.show(context, vault);
                },
              ),
              ListTile(
                leading: const Icon(Icons.security_outlined),
                title: Text(l10n.vaultSecuritySettings),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  final updated =
                      await ChangeVaultSecurityDialog.show(context, vault);
                  if (updated != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.vaultSecurityUpdatedNotice)),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.renamePrivacyFolder),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  final updated = await RenameVaultDialog.show(context, vault);
                  if (updated != null &&
                      updated.name != vault.name &&
                      mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(l10n.privacyFolderRenamedNotice(updated.name)),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.lockAndHide),
                onTap: () {
                  final keepVisible =
                      VaultService.instance.isAlwaysVisible(vault.id);
                  Navigator.of(sheetCtx).pop();
                  VaultService.instance.lockVault(vault.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          keepVisible
                              ? l10n.vaultLockedKeepVisibleNotice(vault.name)
                              : l10n.vaultLockedNotice(vault.name),
                        ),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  l10n.deletePrivacyFolder,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  final deleted = await DeleteVaultDialog.show(context, vault);
                  if (deleted && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(l10n.privacyFolderDeletedNotice(vault.name)),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBottomInsetReporter extends StatefulWidget {
  final double inset;
  final Widget child;

  const _HomeBottomInsetReporter({
    required this.inset,
    required this.child,
  });

  @override
  State<_HomeBottomInsetReporter> createState() =>
      _HomeBottomInsetReporterState();
}

class _HomeBottomInsetReporterState extends State<_HomeBottomInsetReporter>
    with RouteAware {
  ModalRoute<dynamic>? _subscribedRoute;
  bool _routeObscured = false;

  void _syncInset() {
    GlobalPlaybackService.instance.setNamedBottomInset(
      'home_nav',
      _routeObscured ? 0.0 : widget.inset,
    );
  }

  @override
  void initState() {
    super.initState();
    _syncInset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      if (route != null) {
        appRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _HomeBottomInsetReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inset != widget.inset) {
      _syncInset();
    }
  }

  @override
  void didPushNext() {
    _routeObscured = true;
    _syncInset();
  }

  @override
  void didPopNext() {
    _routeObscured = false;
    _syncInset();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _subscribedRoute = null;
    GlobalPlaybackService.instance.setNamedBottomInset('home_nav', 0.0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
