import 'dart:io';
import 'package:flutter/material.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/permission_service.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import 'bookmarks_page.dart';
import 'browser_page.dart';
import 'recent_page.dart';
import 'remotes_page.dart';
import 'settings_page.dart';
import 'utilities_page.dart';

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<RemoteConfigDto> _remotes = [];
  List<BookmarkDto> _bookmarks = [];
  List<HistoryDto> _history = [];
  int _trashCount = 0;
  bool _hasStorageAccess = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
    _checkStorageAccess();
  }

  Future<void> _checkStorageAccess() async {
    if (!Platform.isAndroid) return;
    final granted = await PermissionService.instance.hasStorageAccess();
    if (mounted) setState(() => _hasStorageAccess = granted);
  }

  Future<void> _requestStorageAccess() async {
    final granted = await PermissionService.instance.requestStorageAccess();
    if (mounted) setState(() => _hasStorageAccess = granted);
  }

  Future<void> _loadMetadata() async {
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
        title: const Text('File Manager', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMetadata,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            if (!_hasStorageAccess) ...[
              _buildPermissionBanner(),
              const SizedBox(height: 8),
            ],
            _sectionHeader('Local Storage'),
            _buildLocalStorageGrid(),

            const SizedBox(height: 12),

            _sectionHeader('Cloud, Tools & Settings'),
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
              backgroundColor: Colors.orange.shade800,
            ),
            onPressed: _requestStorageAccess,
            child: const Text('Grant', style: TextStyle(fontSize: 11)),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
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
      children: targets.map((t) {
        IconData icon = Icons.folder;
        Color iconColor = Colors.blue;
        if (t.name.contains('Download')) {
          icon = Icons.download;
          iconColor = Colors.teal;
        } else if (t.name.contains('Photos') || t.name.contains('DCIM') || t.name.contains('Pictures')) {
          icon = Icons.photo_library;
          iconColor = Colors.purple;
        } else if (t.name.contains('Document')) {
          icon = Icons.description;
          iconColor = Colors.indigo;
        } else if (t.name.contains('Home')) {
          icon = Icons.home;
          iconColor = Colors.deepOrange;
        } else if (t.name.contains('Root')) {
          icon = Icons.storage;
          iconColor = Colors.blueGrey;
        }

        return _buildGridCard(
          icon: icon,
          iconColor: iconColor,
          title: t.name,
          subtitle: t.path,
          onTap: () => _openTarget(t.root, t.relPath),
        );
      }).toList(),
    );
  }

  Widget _buildCategoriesGrid() {
    return _buildSectionGrid(
      children: [
        // 1. Remote (S3, OSS, SFTP, WebDAV secondary page)
        _buildGridCard(
          icon: Icons.cloud,
          iconColor: Colors.blue,
          title: 'Remote',
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
          iconColor: Colors.purple,
          title: 'Utilities',
          subtitle: _trashCount > 0 ? '$_trashCount in trash • Web share' : 'Recycle bin, Web share, Cache',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UtilitiesPage()),
            ).then((_) => _loadMetadata());
          },
        ),

        // 3. Bookmarks (Saved favorite folders secondary page)
        _buildGridCard(
          icon: Icons.bookmark,
          iconColor: Colors.amber,
          title: 'Bookmarks',
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
          iconColor: Colors.indigo,
          title: 'Recent',
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
          iconColor: Colors.blueGrey,
          title: 'Settings',
          subtitle: 'Theme, System info, About',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsPage(
                  currentThemeMode: widget.themeMode,
                  onThemeModeChanged: widget.onThemeModeChanged,
                ),
              ),
            ).then((_) => _loadMetadata());
          },
        ),
      ],
    );
  }
}
