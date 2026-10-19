import 'package:flutter/material.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/metadata.dart';
import '../rust/api/remotes.dart';
import '../services/platform_paths.dart';
import '../services/storage_service.dart';
import 'browser_page.dart';
import 'settings_page.dart';
import 'trash_page.dart';

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
  int _currentIndex = 0;
  final GlobalKey<BrowserPageState> _browserKey = GlobalKey<BrowserPageState>();

  late String _currentRoot;
  late String _currentRelPath;

  List<RemoteConfigDto> _remotes = [];
  List<BookmarkDto> _bookmarks = [];
  List<HistoryDto> _history = [];
  int _trashCount = 0;

  @override
  void initState() {
    super.initState();
    _currentRoot = PlatformPaths.defaultRoot();
    _currentRelPath = '';
    _loadMetadata();
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

  void _onQuickTargetSelected(QuickTarget target) {
    setState(() {
      _currentRoot = target.root;
      _currentRelPath = target.relPath;
      _currentIndex = 0;
    });
    _browserKey.currentState?.navigateTo(target.root, target.relPath);
  }

  void _openRemote(RemoteConfigDto remote) {
    final root = 'remote://${remote.id}';
    setState(() {
      _currentRoot = root;
      _currentRelPath = '';
      _currentIndex = 0;
    });
    _browserKey.currentState?.navigateTo(root, '');
  }

  void _openBookmark(BookmarkDto bm) {
    setState(() {
      _currentRoot = bm.root;
      _currentRelPath = bm.path;
      _currentIndex = 0;
    });
    _browserKey.currentState?.navigateTo(bm.root, bm.path);
  }

  void _openHistory(HistoryDto h) {
    setState(() {
      _currentRoot = h.root;
      _currentRelPath = h.path;
      _currentIndex = 0;
    });
    _browserKey.currentState?.navigateTo(h.root, h.path);
  }

  Future<void> _addRemote() async {
    final created = await showDialog<RemoteConfigDto>(
      context: context,
      builder: (ctx) => const RemoteWizardDialog(),
    );
    if (created != null) {
      _loadMetadata();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added remote: ${created.name}')),
        );
      }
    }
  }

  Future<void> _deleteRemote(RemoteConfigDto remote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Remote'),
        content: Text('Remove "${remote.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.instance.deleteRemote(remote.id);
      _loadMetadata();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BrowserPage(
            key: _browserKey,
            initialRoot: _currentRoot,
            initialPath: _currentRelPath,
          ),
          _buildLocationsPage(),
          SettingsPage(
            currentThemeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
          if (idx == 1) _loadMetadata();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildLocationsPage() {
    final targets = PlatformPaths.quickTargets();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Locations & Cloud'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadMetadata,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick Access
          _sectionHeader('Local Storage'),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
            ),
            itemCount: targets.length,
            itemBuilder: (ctx, i) {
              final t = targets[i];
              IconData icon = Icons.folder;
              if (t.name.contains('Download')) icon = Icons.download;
              if (t.name.contains('Photos') || t.name.contains('DCIM')) icon = Icons.photo_library;
              if (t.name.contains('Document')) icon = Icons.description;
              if (t.name.contains('Home')) icon = Icons.home;
              if (t.name.contains('Root')) icon = Icons.storage;

              return InkWell(
                onTap: () => _onQuickTargetSelected(t),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            Text(t.path, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // Remote & Cloud Storage (S3, OSS, WebDAV, SFTP, etc.)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionHeader('Cloud & Remote Protocols (S3 / OSS / SFTP / WebDAV)'),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Colors.blue),
                tooltip: 'Add Remote',
                onPressed: _addRemote,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_remotes.isEmpty)
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: ListTile(
                leading: const Icon(Icons.cloud_queue, size: 32, color: Colors.blue),
                title: const Text('No remote connections configured'),
                subtitle: const Text('Tap "+" to connect Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP or SMB'),
                trailing: FilledButton.tonal(
                  onPressed: _addRemote,
                  child: const Text('Add Remote'),
                ),
              ),
            )
          else
            ..._remotes.map((r) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: _protocolBadge(r.kind),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      r.endpoint ?? (r.bucket != null ? 'Bucket: ${r.bucket}' : '${r.host ?? ""}:${r.port ?? ""}'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Delete',
                          onPressed: () => _deleteRemote(r),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _openRemote(r),
                  ),
                )),

          const SizedBox(height: 24),

          // Recycle Bin Tile
          _sectionHeader('Utilities'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, size: 28, color: Colors.deepOrange),
              title: const Text('Recycle Bin'),
              subtitle: Text('$_trashCount items in trash'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashPage()),
                ).then((_) => _loadMetadata());
              },
            ),
          ),

          const SizedBox(height: 24),

          // Bookmarks
          if (_bookmarks.isNotEmpty) ...[
            _sectionHeader('Bookmarks'),
            const SizedBox(height: 8),
            ..._bookmarks.map((b) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.bookmark, color: Colors.amber),
                    title: Text(b.name),
                    subtitle: Text('${b.root}${b.path}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove',
                      onPressed: () async {
                        await StorageService.instance.deleteBookmark(b.id);
                        _loadMetadata();
                      },
                    ),
                    onTap: () => _openBookmark(b),
                  ),
                )),
            const SizedBox(height: 24),
          ],

          // History
          if (_history.isNotEmpty) ...[
            _sectionHeader('Recent History'),
            const SizedBox(height: 8),
            ..._history.take(5).map((h) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(h.path.isEmpty ? h.root : h.path),
                  subtitle: Text(h.root, style: const TextStyle(fontSize: 10)),
                  onTap: () => _openHistory(h),
                )),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _protocolBadge(String kind) {
    Color bg = Colors.blue;
    String label = kind.toUpperCase();
    if (kind == 's3') {
      bg = Colors.deepOrange;
      label = 'S3';
    } else if (kind == 'oss') {
      bg = Colors.orange;
      label = 'OSS';
    } else if (kind == 'webdav') {
      bg = Colors.teal;
      label = 'DAV';
    } else if (kind == 'sftp') {
      bg = Colors.indigo;
      label = 'SFTP';
    } else if (kind == 'ftp') {
      bg = Colors.blueGrey;
      label = 'FTP';
    } else if (kind == 'smb') {
      bg = Colors.purple;
      label = 'SMB';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        border: Border.all(color: bg),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: bg),
      ),
    );
  }
}
