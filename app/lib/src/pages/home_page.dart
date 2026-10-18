import 'package:flutter/material.dart';
import '../services/platform_paths.dart';
import 'browser_page.dart';
import 'settings_page.dart';

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

  @override
  void initState() {
    super.initState();
    _currentRoot = PlatformPaths.defaultRoot();
    _currentRelPath = '';
  }

  void _onQuickTargetSelected(QuickTarget target) {
    setState(() {
      _currentRoot = target.root;
      _currentRelPath = target.relPath;
      _currentIndex = 0;
    });
    _browserKey.currentState?.navigateTo(target.root, target.relPath);
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
          _buildQuickAccessPage(),
          SettingsPage(
            currentThemeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
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

  Widget _buildQuickAccessPage() {
    final targets = PlatformPaths.quickTargets();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locations & Storage'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Quick Access',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
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
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              t.path,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
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
          ),
          const SizedBox(height: 24),
          Text(
            'Remotes (M4 Preview)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.add_circle_outline),
              title: Text('Add Remote Storage'),
              subtitle: Text('SFTP, FTP, FTPS, SMB, WebDAV (M4)'),
            ),
          ),
        ],
      ),
    );
  }
}
