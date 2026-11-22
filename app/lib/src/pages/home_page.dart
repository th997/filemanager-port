import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../rust/api/vault.dart';
import '../dialogs/vault_dialogs.dart';
import '../services/permission_service.dart';
import '../services/preferences_service.dart';
import '../services/semantic_colors.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'bookmarks_page.dart';
import 'browser_page.dart';
import 'gallery_page.dart';
import 'recent_page.dart';
import 'remotes_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'utilities_page.dart';
import '../services/external_file_service.dart';
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
  bool _hasStorageAccess = true;
  bool _requestingAccess = false;
  bool _welcomeDismissed = false;

  static const _prefWelcomeDismissed = 'home.welcome_dismissed';

  @override
  void initState() {
    super.initState();
    _welcomeDismissed =
        PreferencesService.instance.getBool(_prefWelcomeDismissed) ?? false;
    WidgetsBinding.instance.addObserver(this);
    VaultService.instance.addListener(_onVaultChanged);
    _loadMetadata();
    _checkStorageAccess();
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onVaultChanged() {
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
      if (mounted && active != _activeTaskCount) {
        setState(() => _activeTaskCount = active);
      }
    } catch (_) {
      // Tasks registry not ready yet (first frames): leave the count at 0.
    }
  }

  Future<void> _checkStorageAccess() async {
    if (!Platform.isAndroid) return;
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
  }

  bool get _pickMode => widget.pickRequest != null;

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
    return Scaffold(
      appBar: AppBar(
        leading: _pickMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: AppLocalizations.of(context).cancel,
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          _pickMode
              ? (widget.pickRequest!.allowMultiple
                  ? AppLocalizations.of(context).pickFilesTitle
                  : AppLocalizations.of(context).pickFileTitle)
              : AppLocalizations.of(context).appTitle,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refresh,
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMetadata,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppUiTokens.pagePadding,
          children: [
            if (!_hasStorageAccess) ...[
              _buildPermissionBanner(),
              const SizedBox(height: 8),
            ],
            if (_showWelcome) ...[
              _buildWelcomeBanner(),
              const SizedBox(height: 8),
            ],
            _sectionHeader(AppLocalizations.of(context).localStorage),
            _buildLocalStorageGrid(),

            const SizedBox(height: 12),

            _sectionHeader(AppLocalizations.of(context).cloudToolsSettings),
            _buildCategoriesGrid(),

            const SizedBox(height: 16),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : (constraints.maxWidth > 520 ? 3 : 2);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: childAspectRatio,
          children: children,
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

  Widget _buildLocalStorageGrid() {
    final targets = PlatformPaths.quickTargets()
        .where((t) => !_pickMode || t.kind != 'inbox')
        .toList();
    return _buildSectionGrid(
      children: [
        _buildGridCard(
          icon: Icons.photo_library,
          iconColor: const Color(0xFFD81B60),
          title: AppLocalizations.of(context).gallery,
          subtitle: AppLocalizations.of(context).allPhotos,
          onTap: () async {
            final picked = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(builder: (_) => GalleryPage(pickRequest: widget.pickRequest)),
            );
            if (picked != null && picked.isNotEmpty && mounted) {
              Navigator.of(context).pop(picked);
            }
          },
        ),
        ...targets.map((t) {
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
          title: t.displayName(AppLocalizations.of(context)),
          subtitle: t.kind == 'inbox'
              ? AppLocalizations.of(context).privateInboxSubtitle
              : t.path,
          onTap: () => _openTarget(t.root, t.relPath),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: t.path));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context).copiedPathValue(t.path))),
            );
          },
        );
        }),
        if (!_pickMode)
          ...VaultService.instance.unlockedVaults.map((vault) {
            final l10n = AppLocalizations.of(context);
            return _buildGridCard(
              icon: Icons.lock_open_rounded,
              iconColor: Colors.indigo,
              title: vault.name,
              subtitle: l10n.unlockedBadge,
              onTap: () => _openTarget('vault://${vault.id}', ''),
              onLongPress: () => _showUnlockedVaultActions(vault),
            );
          }),
      ],
    );
  }

  void _showUnlockedVaultActions(UnlockedVaultDto vault) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      content: Text(l10n.privacyFolderRenamedNotice(updated.name)),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.lockAndHide),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                VaultService.instance.lockVault(vault.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.vaultLockedNotice(vault.name))),
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
                      content: Text(l10n.privacyFolderDeletedNotice(vault.name)),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesGrid() {
    return _buildSectionGrid(
      children: [
        // 1. Remote (S3, OSS, SFTP, WebDAV secondary page)
        _buildGridCard(
          icon: Icons.cloud,
          iconColor: const Color(0xFF1E88E5),
          title: AppLocalizations.of(context).remote,
          subtitle: _remotes.isEmpty
              ? AppLocalizations.of(context).remoteProtocolsSubtitle
              : '${_remotes.length} connection${_remotes.length > 1 ? "s" : ""}',
          onTap: () async {
            final picked = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(builder: (_) => RemotesPage(pickRequest: widget.pickRequest)),
            );
            if (picked != null && picked.isNotEmpty && mounted) {
              Navigator.of(context).pop(picked);
              return;
            }
            _loadMetadata();
          },
        ),

        // 2. Bookmarks (Saved favorite folders secondary page)
        _buildGridCard(
          icon: Icons.bookmark,
          iconColor: const Color(0xFFFB8C00),
          title: AppLocalizations.of(context).bookmarks,
          subtitle: _bookmarks.isEmpty
              ? AppLocalizations.of(context).bookmarksDefaultSubtitle
              : '${_bookmarks.length} bookmark${_bookmarks.length > 1 ? "s" : ""}',
          onTap: () async {
            final picked = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(builder: (_) => BookmarksPage(pickRequest: widget.pickRequest)),
            );
            if (picked != null && picked.isNotEmpty && mounted) {
              Navigator.of(context).pop(picked);
              return;
            }
            _loadMetadata();
          },
        ),

        // 3. Recent (History secondary page)
        _buildGridCard(
          icon: Icons.history,
          iconColor: const Color(0xFF3949AB),
          title: AppLocalizations.of(context).recent,
          subtitle: _history.isEmpty
              ? AppLocalizations.of(context).recentDefaultSubtitle
              : '${_history.length} location${_history.length > 1 ? "s" : ""}',
          onTap: () async {
            final picked = await Navigator.of(context).push<List<String>>(
              MaterialPageRoute(builder: (_) => RecentPage(pickRequest: widget.pickRequest)),
            );
            if (picked != null && picked.isNotEmpty && mounted) {
              Navigator.of(context).pop(picked);
              return;
            }
            _loadMetadata();
          },
        ),

        if (!_pickMode) ...[
          // 4. Utilities (Recycle bin, Web sharing, Cache secondary page)
          _buildGridCard(
            icon: Icons.build_outlined,
            iconColor: const Color(0xFF5E35B1),
            title: AppLocalizations.of(context).utilities,
            subtitle: _trashCount > 0 ? AppLocalizations.of(context).utilitiesTrashSubtitle(_trashCount) : AppLocalizations.of(context).utilitiesDefaultSubtitle,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UtilitiesPage()),
              ).then((_) => _loadMetadata());
            },
          ),

          // 5. Tasks (background transfers & operations)
          _buildGridCard(
            icon: Icons.task_alt,
            iconColor: const Color(0xFF00897B),
            title: AppLocalizations.of(context).tasks,
            subtitle: _activeTaskCount > 0
                ? '$_activeTaskCount running'
                : AppLocalizations.of(context).tasksDefaultSubtitle,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TasksPage()),
              ).then((_) => _loadMetadata());
            },
          ),

          // 6. Settings (Preferences secondary page)
          _buildGridCard(
            icon: Icons.settings,
            iconColor: const Color(0xFF546E7A),
            title: AppLocalizations.of(context).settings,
            subtitle: AppLocalizations.of(context).settingsCardSubtitle,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    currentThemeMode: widget.themeMode,
                    onThemeModeChanged: widget.onThemeModeChanged ?? (_) {},
                    localeCode: widget.localeCode ?? 'system',
                    onLocaleChanged: widget.onLocaleChanged ?? (_) {},
                    accentCode: widget.accentCode ?? 'dynamic',
                    onAccentChanged: widget.onAccentChanged ?? (_) {},
                  ),
                ),
              ).then((_) => _loadMetadata());
            },
          ),
        ],
      ],
    );
  }
}
