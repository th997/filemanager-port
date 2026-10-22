import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/remotes.dart';
import '../../l10n/app_localizations.dart';
import '../services/semantic_colors.dart';
import '../services/error_text.dart';
import '../services/storage_service.dart';
import 'browser_page.dart';

enum _ConnStatus { unknown, checking, online, offline }

class RemotesPage extends StatefulWidget {
  const RemotesPage({super.key});

  @override
  State<RemotesPage> createState() => _RemotesPageState();
}

class _RemotesPageState extends State<RemotesPage> {
  List<RemoteConfigDto> _remotes = [];
  final Map<String, _ConnStatus> _status = {};
  bool _loading = true;
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRemotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Alphabetical, so a saved connection does not drift around the list as
  /// new ones are added.
  List<RemoteConfigDto> get _visibleRemotes {
    final q = _searchQuery.trim().toLowerCase();
    final list = q.isEmpty
        ? [..._remotes]
        : _remotes.where((r) {
            final sub = r.endpoint ??
                (r.bucket != null ? r.bucket! : '${r.host ?? ""}:${r.port ?? ""}');
            return r.name.toLowerCase().contains(q) ||
                r.kind.toLowerCase().contains(q) ||
                sub.toLowerCase().contains(q);
          }).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  void _copyRemoteUri(RemoteConfigDto r) {
    final uri = r.endpoint ??
        (r.bucket != null
            ? '${r.kind}://${r.bucket}'
            : '${r.kind}://${r.host ?? ""}:${r.port ?? ""}');
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $uri')),
    );
  }

  Future<void> _loadRemotes() async {
    final rems = await StorageService.instance.getRemotes();
    if (mounted) {
      setState(() {
        _remotes = rems;
        _loading = false;
      });
      // Probe reachability in the background so the list shows live
      // status dots without blocking the page on slow servers.
      for (final r in rems) {
        _probeStatus(r);
      }
    }
  }

  Future<void> _probeStatus(RemoteConfigDto remote) async {
    if (_status[remote.id] == _ConnStatus.checking) return;
    if (mounted) {
      setState(() => _status[remote.id] = _ConnStatus.checking);
    }
    bool ok;
    try {
      ok = await StorageService.instance.testConnection(remote);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() =>
        _status[remote.id] = ok ? _ConnStatus.online : _ConnStatus.offline);
  }

  Color _statusColor(_ConnStatus s) {
    final scheme = Theme.of(context).colorScheme;
    switch (s) {
      case _ConnStatus.online:
        return scheme.success;
      case _ConnStatus.offline:
        return scheme.error;
      case _ConnStatus.checking:
        return scheme.warning;
      case _ConnStatus.unknown:
        return scheme.onSurfaceVariant;
    }
  }

  void _openRemote(RemoteConfigDto remote) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: 'remote://${remote.id}',
          initialPath: '',
        ),
      ),
    ).then((_) => _loadRemotes());
  }

  Future<void> _addRemote() async {
    final created = await showDialog<RemoteConfigDto>(
      context: context,
      builder: (ctx) => const RemoteWizardDialog(),
    );
    if (created != null) {
      _loadRemotes();
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
      invalidateRoot(root: 'remote://${updated.id}');
      _loadRemotes();
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
      try {
        await StorageService.instance.deleteRemote(remote.id);
        invalidateRoot(root: 'remote://${remote.id}');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not delete "${remote.name}": $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _loadRemotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${remote.name}"')),
        );
      }
    }
  }

  /// Quick reachability check without opening the edit wizard.
  Future<void> _testRemote(RemoteConfigDto remote) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Testing "${remote.name}"…'), duration: const Duration(seconds: 2)),
    );
    bool ok;
    String? error;
    setState(() => _status[remote.id] = _ConnStatus.checking);
    try {
      ok = await StorageService.instance.testConnection(remote);
    } catch (e) {
      ok = false;
      error = friendlyErrorText(e);
    }
    if (!mounted) return;
    setState(() =>
        _status[remote.id] = ok ? _ConnStatus.online : _ConnStatus.offline);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Connected to "${remote.name}"' : 'Cannot reach "${remote.name}"${error == null ? '' : ': $error'}',
        ),
        backgroundColor: ok ? Theme.of(context).colorScheme.success : Theme.of(context).colorScheme.error,
      ),
    );
  }

  (IconData, Color) _remoteVisuals(String kind) {
    switch (kind.toLowerCase()) {
      case 's3':
        return (Icons.cloud, Colors.deepOrange);
      case 'oss':
        return (Icons.cloud_queue, Colors.orange);
      case 'webdav':
        return (Icons.cloud_sync, Colors.teal);
      case 'sftp':
        return (Icons.terminal, Colors.indigo);
      case 'ftp':
        return (Icons.folder_shared, Colors.blueGrey);
      case 'smb':
        return (Icons.lan, Colors.purple);
      default:
        return (Icons.cloud, Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedRemotes = _visibleRemotes;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).cloudRemoteStorage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (_remotes.isNotEmpty)
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search, size: 20),
              tooltip: _showSearch ? 'Close Search' : 'Search Remotes',
              onPressed: () {
                setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.add, size: 22),
            tooltip: 'Add Connection',
            onPressed: _addRemote,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadRemotes,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Filter remote connections...',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadRemotes,
                    child: _remotes.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) => SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_queue, size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No remote connections configured',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Connect Amazon S3, Aliyun OSS, WebDAV, SFTP, FTP or SMB network storage.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _addRemote,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Add Remote Storage'),
                                  ),
                                ],
                              ),
                            ),
                                ),
                              ),
                            ),
                          )
                        : displayedRemotes.isEmpty
                            ? LayoutBuilder(
                                builder: (context, constraints) => SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                    child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No matching connections',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Nothing matches "$_searchQuery".',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                itemCount: displayedRemotes.length + 1,
                                itemBuilder: (ctx, i) {
                                  if (i == displayedRemotes.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Center(
                                        child: OutlinedButton.icon(
                                          onPressed: _addRemote,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Add Another Remote'),
                                        ),
                                      ),
                                    );
                                  }

                                  final r = displayedRemotes[i];
                                  final (icon, color) = _remoteVisuals(r.kind);
                                  final sub = r.endpoint ??
                                      (r.bucket != null ? 'Bucket: ${r.bucket}' : '${r.host ?? ""}:${r.port ?? ""}');

                                  return Card(
                                    elevation: 0,
                                    margin: const EdgeInsets.symmetric(vertical: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                                    ),
                                    child: ListTile(
                                      dense: true,
                                      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                                      minTileHeight: 40,
                                      minLeadingWidth: 24,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(icon, size: 16, color: color),
                                          ),
                                          Positioned(
                                            right: -1,
                                            bottom: -1,
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: _statusColor(_status[r.id] ?? _ConnStatus.unknown),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(context).cardColor,
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                                      subtitle: Text(
                                        '${r.kind.toUpperCase()} • $sub',
                                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy_outlined, size: 15),
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            tooltip: 'Copy Connection URI',
                                            onPressed: () => _copyRemoteUri(r),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.network_check, size: 16),
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            tooltip: 'Test Connection',
                                            onPressed: () => _testRemote(r),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 16),
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            tooltip: 'Edit',
                                            onPressed: () => _editRemote(r),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                            visualDensity: VisualDensity.compact,
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                            tooltip: 'Delete',
                                            onPressed: () => _deleteRemote(r),
                                          ),
                                          const Icon(Icons.chevron_right, size: 16),
                                        ],
                                      ),
                                      onTap: () => _openRemote(r),
                                      onLongPress: () => _copyRemoteUri(r),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
    );
  }
}
