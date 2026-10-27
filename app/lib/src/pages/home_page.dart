import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/permission_service.dart';
import '../services/preferences_service.dart';
import '../services/semantic_colors.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import '../theme/app_ui_tokens.dart';
import '../../l10n/app_localizations.dart';
import 'bookmarks_page.dart';
import 'browser_page.dart';
import 'gallery_page.dart';
import 'recent_page.dart';
import 'remotes_page.dart';
import 'settings_page.dart';
import 'tasks_page.dart';
import 'utilities_page.dart';

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final String localeCode;
  final ValueChanged<String> onLocaleChanged;
  final String accentCode;
  final ValueChanged<String> onAccentChanged;

  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.localeCode,
    required this.onLocaleChanged,
    required this.accentCode,
    required this.onAccentChanged,
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
    _loadMetadata();
    _checkStorageAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
            content: Text('Could not request file access: $e'),
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
      final rems = await StorageService.instance.getRemotes();
      final bms = await StorageService.instance.getBookmarks();
      final hist = await StorageService.instance.getHistory();
      final trash = await StorageService.instance.getTrashItems();

      if (mounted) {
        setState(() {
          _remotes = rems;
          _bookmarks = bms;
          _history = hist;
          _trashCount = trash.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh home data: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(label: 'Retry', onPressed: _loadMetadata),
          ),
        );
      }
    }
    _refreshTaskCount();
  }

  void _openTarget(String root, String relPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: root,
          initialPath: relPath,
        ),
      ),
    ).then((_) => _loadMetadata());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
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
          const Expanded(
            child: Text(
              'Storage permission is required to browse files. Grant "All files access" in the next screen.',
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
              _requestingAccess ? 'Requesting…' : 'Grant',
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
    final targets = PlatformPaths.quickTargets();
    return _buildSectionGrid(
      children: [
        _buildGridCard(
          icon: Icons.photo_library,
          iconColor: const Color(0xFFD81B60),
          title: AppLocalizations.of(context).gallery,
          subtitle: AppLocalizations.of(context).allPhotos,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GalleryPage()),
            );
          },
        ),
        ...targets.map((t) {
        IconData icon = Icons.folder;
        Color iconColor = Colors.blue;
        final key = '${t.name} ${t.relPath} ${t.path}'.toLowerCase();
        if (key.contains('download') || key.contains('下载')) {
          icon = Icons.download;
          iconColor = Colors.teal;
        } else if (key.contains('photo') || key.contains('dcim') || key.contains('picture') || key.contains('图片') || key.contains('相册')) {
          icon = Icons.photo_library;
          iconColor = Colors.purple;
        } else if (key.contains('document') || key.contains('文档')) {
          icon = Icons.description;
          iconColor = Colors.indigo;
        } else if (key.contains('home') || key.contains('主目录') || key.contains('用户')) {
          icon = Icons.home;
          iconColor = Colors.deepOrange;
        } else if (key.contains('root') || key.contains('storage') || key.contains('drive') || key.contains('根目录') || key.contains('存储')) {
          icon = Icons.storage;
          iconColor = Colors.blueGrey;
        }

        return _buildGridCard(
          icon: icon,
          iconColor: iconColor,
          title: t.name,
          subtitle: t.path,
          onTap: () => _openTarget(t.root, t.relPath),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: t.path));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied path: ${t.path}')),
            );
          },
        );
        }),
      ],
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
              ? 'S3, OSS, SFTP, WebDAV...'
              : '${_remotes.length} connection${_remotes.length > 1 ? "s" : ""}',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RemotesPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 2. Utilities (Recycle bin, Web sharing, Cache secondary page)
        _buildGridCard(
          icon: Icons.build_outlined,
          iconColor: const Color(0xFF5E35B1),
          title: AppLocalizations.of(context).utilities,
          subtitle: _trashCount > 0 ? '$_trashCount in trash • Web share' : 'Recycle bin, Web share, Cache',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UtilitiesPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 3. Tasks (background transfers & operations)
        _buildGridCard(
          icon: Icons.task_alt,
          iconColor: const Color(0xFF00897B),
          title: AppLocalizations.of(context).tasks,
          subtitle: _activeTaskCount > 0
              ? '$_activeTaskCount running'
              : 'Transfers and operations',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TasksPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 4. Bookmarks (Saved favorite folders secondary page)
        _buildGridCard(
          icon: Icons.bookmark,
          iconColor: const Color(0xFFFB8C00),
          title: AppLocalizations.of(context).bookmarks,
          subtitle: _bookmarks.isEmpty
              ? 'Saved folders'
              : '${_bookmarks.length} bookmark${_bookmarks.length > 1 ? "s" : ""}',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BookmarksPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 4. Recent (History secondary page)
        _buildGridCard(
          icon: Icons.history,
          iconColor: const Color(0xFF3949AB),
          title: AppLocalizations.of(context).recent,
          subtitle: _history.isEmpty
              ? 'Browsing history'
              : '${_history.length} location${_history.length > 1 ? "s" : ""}',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecentPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 5. Settings (Preferences secondary page)
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
                  onThemeModeChanged: widget.onThemeModeChanged,
                  localeCode: widget.localeCode,
                  onLocaleChanged: widget.onLocaleChanged,
                  accentCode: widget.accentCode,
                  onAccentChanged: widget.onAccentChanged,
                ),
              ),
            ).then((_) => _loadMetadata());
          },
        ),
      ],
    );
  }
}
