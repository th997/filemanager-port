import 'package:flutter/material.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
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

  Future<void> _renameBookmark(BookmarkDto bm) async {
    final ctrl = TextEditingController(text: bm.name);
    final String? newName;
    try {
      newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename Bookmark'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Bookmark Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) {
                Navigator.of(ctx).pop(v.trim());
              }
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Rename')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (newName != null && newName.isNotEmpty && newName != bm.name) {
      await StorageService.instance.renameBookmark(
        id: bm.id,
        newName: newName,
        root: bm.root,
        path: bm.path,
      );
      _loadMetadata();
    }
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

  Future<void> _editRemote(RemoteConfigDto remote) async {
    final updated = await showDialog<RemoteConfigDto>(
      context: context,
      builder: (ctx) => RemoteWizardDialog(initialConfig: remote),
    );
    if (updated != null) {
      // The backend for this remote may already be cached with the old
      // credentials; drop it so the next open reconnects with the new ones.
      invalidateRoot(root: 'remote://${updated.id}');
      _loadMetadata();
    }
  }

  Future<void> _deleteRemote(RemoteConfigDto remote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Remote'),
        content: Text(
          'Remove "${remote.name}"?\n\n'
          'This only removes the saved connection from this app. Files on the '
          'server are not touched.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      await StorageService.instance.deleteRemote(remote.id);
      invalidateRoot(root: 'remote://${remote.id}');
      // If the browser is showing the removed connection, its cached backend
      // still answers; return to local storage instead of browsing a remote
      // that no longer exists.
      if (_currentRoot == 'remote://${remote.id}') {
        _onQuickTargetSelected(PlatformPaths.quickTargets().first);
      }
      _loadMetadata();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
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
      body: RefreshIndicator(
        onRefresh: _loadMetadata,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
          // Quick Access
          _sectionHeader('Local Storage'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 800
                  ? 4
                  : (constraints.maxWidth > 520 ? 3 : 2);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 2.8,
                ),
                itemCount: targets.length,
                itemBuilder: (ctx, i) {
                  final t = targets[i];
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

                  return InkWell(
                    onTap: () => _onQuickTargetSelected(t),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 16, color: iconColor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  t.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  t.path,
                                  style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: _protocolBadge(r.kind),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                      r.endpoint ?? (r.bucket != null ? 'Bucket: ${r.bucket}' : '${r.host ?? ""}:${r.port ?? ""}'),
                      style: const TextStyle(fontSize: 10),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Edit',
                          onPressed: () => _editRemote(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Delete',
                          onPressed: () => _deleteRemote(r),
                        ),
                        const Icon(Icons.chevron_right, size: 16),
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
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.delete_outline, size: 22, color: Colors.deepOrange),
              title: const Text('Recycle Bin', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('$_trashCount items in trash', style: const TextStyle(fontSize: 10)),
              trailing: const Icon(Icons.chevron_right, size: 16),
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
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.bookmark, color: Colors.amber, size: 20),
                    title: Text(b.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('${b.root}${b.path}', style: const TextStyle(fontSize: 10)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Rename Bookmark',
                          onPressed: () => _renameBookmark(b),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Remove',
                          onPressed: () async {
                            await StorageService.instance.deleteBookmark(b.id);
                            _loadMetadata();
                          },
                        ),
                      ],
                    ),
                    onTap: () => _openBookmark(b),
                  ),
                )),
            const SizedBox(height: 24),
          ],

          // History
          if (_history.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionHeader('Recent History'),
                TextButton(
                  onPressed: () {
                    setState(() => _history.clear());
                  },
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._history.take(8).map((h) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(h.path.isEmpty ? h.root : h.path),
                  subtitle: Text(h.root, style: const TextStyle(fontSize: 10)),
                  onTap: () => _openHistory(h),
                )),
          ],
        ],
      ),
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
