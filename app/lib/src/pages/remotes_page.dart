import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/remotes.dart';
import '../../l10n/app_localizations.dart';
import '../services/semantic_colors.dart';
import '../services/error_text.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
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
    try {
      final rems = await StorageService.instance.getRemotes();
      if (!mounted) return;
      setState(() {
        _remotes = rems;
        _loading = false;
      });
      // Probe reachability in the background so the list shows live
      // status dots without blocking the page on slow servers.
      for (final r in rems) {
        _probeStatus(r);
      }
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load connections: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _probeStatus(RemoteConfigDto remote) async {
    if (_status[remote.id] == _ConnStatus.checking) return;
    if (mounted) {
      setState(() => _status[remote.id] = _ConnStatus.checking);
    }
    bool ok;
    try {
      // Bounded: a host whose packets are silently dropped by a
      // firewall otherwise keeps the dot on "checking" for the whole
      // OS TCP timeout (~2 minutes), which reads as the app hanging.
      ok = await StorageService.instance
          .testConnection(remote)
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
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
    // Tapping again while a check is in flight started a second connection
    // whose result could overwrite the first one's.
    if (_status[remote.id] == _ConnStatus.checking) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Testing "${remote.name}"…'), duration: const Duration(seconds: 2)),
    );
    bool ok;
    String? error;
    setState(() => _status[remote.id] = _ConnStatus.checking);
    try {
      // A firewalled host sits in the OS TCP timeout for minutes, leaving the
      // row on "checking" and the button looking dead. Bound it like the
      // background probe already is.
      ok = await StorageService.instance
          .testConnection(remote)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      ok = false;
      error = 'timed out after 8 seconds';
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

    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).cloudRemoteStorage),
        actions: [
          if (_remotes.isNotEmpty)
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
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
            icon: const Icon(Icons.add),
            tooltip: 'Add Connection',
            onPressed: _addRemote,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
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
                                padding: AppUiTokens.pagePadding,
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
                                    child: ListTile(
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          AppCircleBadge(icon: icon, color: color),
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
                                      title: Text(r.name),
                                      subtitle: Text(
                                        '${r.kind.toUpperCase()} • $sub',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AppIconButton(
                                            icon: Icons.copy_outlined,
                                            tooltip: 'Copy Connection URI',
                                            onPressed: () => _copyRemoteUri(r),
                                          ),
                                          AppIconButton(
                                            icon: Icons.network_check,
                                            tooltip: 'Test Connection',
                                            onPressed: () => _testRemote(r),
                                          ),
                                          AppIconButton(
                                            icon: Icons.edit_outlined,
                                            tooltip: 'Edit',
                                            onPressed: () => _editRemote(r),
                                          ),
                                          AppIconButton(
                                            icon: Icons.delete_outline,
                                            color: Colors.red,
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
      ),
    );
  }
}
