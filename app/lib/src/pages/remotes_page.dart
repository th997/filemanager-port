import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/metadata.dart' show isSecretEncryptionActive;
import '../rust/api/remotes.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../services/semantic_colors.dart';
import '../services/error_text.dart';
import '../widgets/error_recovery_action.dart';
import '../services/pool_service.dart';
import '../services/shortcut_service.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

import '../services/external_file_service.dart';

enum _ConnStatus { unknown, checking, online, offline }

class RemotesPage extends StatefulWidget {
  final ExternalPickRequest? pickRequest;
  final bool embedded;
  final void Function(RemoteConfigDto remote)? onOpenRemote;
  final VoidCallback? onRemotesChanged;

  const RemotesPage({
    super.key,
    this.pickRequest,
    this.embedded = false,
    this.onOpenRemote,
    this.onRemotesChanged,
  });

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
  bool _secretEncryptionActive = true;
  bool _shortcutsSupported = false;

  @override
  void initState() {
    super.initState();
    _loadRemotes();
    _initShortcutSupport();
    try {
      _secretEncryptionActive = isSecretEncryptionActive(
        dbPath: StorageService.instance.dbPath,
      );
    } catch (_) {}
  }

  Future<void> _initShortcutSupport() async {
    final supported = await ShortcutService.instance.isSupported();
    if (mounted && supported) {
      setState(() => _shortcutsSupported = true);
    }
  }

  Future<void> _pinRemoteShortcut(RemoteConfigDto r) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ShortcutService.instance.pinShortcut(
      ShortcutTarget(
        type: 'remote',
        id: 'remote_${r.id}',
        label: r.name,
        root: 'remote://${r.id}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? l10n.pinToHomeScreenSuccess(r.name)
              : l10n.pinToHomeScreenUnsupported,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RemoteConfigDto>? _visibleRemotesCache;
  List<RemoteConfigDto>? _lastRemotes;
  String? _lastSearchQuery;

  /// Alphabetical, so a saved connection does not drift around the list as
  /// new ones are added.
  List<RemoteConfigDto> get _visibleRemotes {
    if (_visibleRemotesCache != null &&
        identical(_lastRemotes, _remotes) &&
        _lastSearchQuery == _searchQuery) {
      return _visibleRemotesCache!;
    }
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
    _lastRemotes = _remotes;
    _lastSearchQuery = _searchQuery;
    _visibleRemotesCache = list;
    return list;
  }

  String _formatSubtitle(RemoteConfigDto r, AppLocalizations l10n) {
    if (_isUnreadable(r)) return l10n.detailsUnavailableReconnect;
    if (r.endpoint != null) {
      return r.bucket != null
          ? '${r.endpoint!} (${l10n.remoteBucketLabel(r.bucket!)})'
          : r.endpoint!;
    }
    if (r.bucket != null) return l10n.remoteBucketLabel(r.bucket!);
    final portSuffix = r.port != null ? ':${r.port}' : '';
    return '${r.host ?? ""}$portSuffix';
  }

  void _copyRemoteUri(RemoteConfigDto r) {
    final l10n = AppLocalizations.of(context);
    if (_isUnreadable(r)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionNoReadableDetails)),
      );
      return;
    }
    final portSuffix = r.port != null ? ':${r.port}' : '';
    final uri = r.endpoint ??
        (r.bucket != null
            ? '${r.kind}://${r.bucket}'
            : '${r.kind}://${r.host ?? ""}$portSuffix');
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.copiedValue(uri))),
    );
  }

  /// The stored config could not be decrypted, so every field but the
  /// name and kind is empty. Editing or testing it would just fail.
  static bool _isUnreadable(RemoteConfigDto r) =>
      StorageService.isUnreadableRemote(r);

  Future<void> _loadRemotes() async {
    try {
      final rems = await StorageService.instance.getRemotes();
      if (!mounted) return;
      setState(() {
        _remotes = rems;
        _loading = false;
      });
    } catch (e) {
      // Without this the page stays on its spinner after a storage failure.
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).couldNotLoadConnections('$e')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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

  void _openRemote(RemoteConfigDto remote) async {
    if (widget.pickRequest == null && widget.onOpenRemote != null) {
      widget.onOpenRemote!(remote);
      return;
    }
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => BrowserPage(
          initialRoot: 'remote://${remote.id}',
          initialPath: '',
          pickRequest: widget.pickRequest,
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      Navigator.of(context).pop(picked);
      return;
    }
    _loadRemotes();
  }

  void _showRemoteActionSheet(RemoteConfigDto r) {
    HapticFeedback.mediumImpact();
    final l10n = AppLocalizations.of(context);
    final sub = _formatSubtitle(r, l10n);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  r.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${r.kind.toUpperCase()} • $sub',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(l10n.connectAndBrowse),
                onTap: () {
                  Navigator.pop(ctx);
                  _openRemote(r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.network_check),
                title: Text(l10n.testConnection),
                onTap: () {
                  Navigator.pop(ctx);
                  _testRemote(r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.copyUri),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyRemoteUri(r);
                },
              ),
              if (_shortcutsSupported)
                ListTile(
                  leading: const Icon(Icons.add_to_home_screen),
                  title: Text(l10n.pinToHomeScreen),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pinRemoteShortcut(r);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.editConfiguration),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRemote(r);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  l10n.deleteRemote,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteRemote(r);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addRemote() async {
    final created = await showDialog<RemoteConfigDto>(
      context: context,
      builder: (ctx) => const RemoteWizardDialog(),
    );
    if (created != null) {
      await _loadRemotes();
      widget.onRemotesChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).addedRemote(created.name))),
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
      _status.remove(remote.id);
      _status.remove(updated.id);
      await _loadRemotes();
      widget.onRemotesChanged?.call();
    }
  }

  Future<void> _deleteRemote(RemoteConfigDto remote) async {
    final l10n = AppLocalizations.of(context);
    final affectedPools = PoolService.instance.pools
        .where((p) => p.nodes.any((n) => n.remoteId == remote.id))
        .map((p) => p.name)
        .toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteRemote),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.deleteRemoteConfirm(remote.name)),
            if (affectedPools.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l10n.deleteRemotePoolWarning(affectedPools.join(', ')),
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await StorageService.instance.deleteRemote(remote.id);
        invalidateRoot(root: 'remote://${remote.id}');
        await PoolService.instance.refresh();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.couldNotDeleteNamed(remote.name, '$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _status.remove(remote.id);
      await _loadRemotes();
      widget.onRemotesChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.deletedItem(remote.name))),
        );
      }
    }
  }

  /// Quick reachability check without opening the edit wizard.
  Future<void> _testRemote(RemoteConfigDto remote) async {
    // Nothing to test: the stored config could not be decrypted.
    if (_isUnreadable(remote)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).connectionNoReadableDetails),
        ),
      );
      return;
    }
    // Tapping again while a check is in flight started a second connection
    // whose result could overwrite the first one's.
    if (_status[remote.id] == _ConnStatus.checking) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).testingRemote(remote.name)), duration: const Duration(seconds: 2)),
    );
    bool ok;
    String? error;
    setState(() => _status[remote.id] = _ConnStatus.checking);
    final l10n = AppLocalizations.of(context);
    try {
      // A firewalled host sits in the OS TCP timeout for minutes, leaving the
      // row on "checking" and the button looking dead. Bound it like the
      // background probe already is.
      ok = await StorageService.instance
          .testConnection(remote)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      ok = false;
      error = l10n.remoteTestTimedOut;
    } catch (e) {
      ok = false;
      error = friendlyErrorText(e, l10n);
    }
    if (!mounted) return;
    setState(() =>
        _status[remote.id] = ok ? _ConnStatus.online : _ConnStatus.offline);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? AppLocalizations.of(context).connectedToRemote(remote.name) : '${AppLocalizations.of(context).cannotReachRemote(remote.name)}${error == null ? '' : ': $error'}',
        ),
        backgroundColor: ok ? Theme.of(context).colorScheme.success : Theme.of(context).colorScheme.error,
        persist: false,
        duration: const Duration(seconds: 5),
        action: (!ok && error != null)
            ? ErrorRecoveryActionButton.buildSnackBarAction(
                context,
                rawError: error,
                remoteOverride: remote,
                onRetry: () => _testRemote(remote),
              )
            : null,
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
      case 'crypt':
        return (Icons.enhanced_encryption, Colors.deepPurple);
      default:
        return (Icons.cloud, Colors.blue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedRemotes = _visibleRemotes;
    final l10n = AppLocalizations.of(context);

    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(l10n.cloudRemoteStorage),
        actions: [
          if (_remotes.isNotEmpty)
            IconButton(
              icon: Icon(_showSearch ? Icons.search_off : Icons.search),
              tooltip: _showSearch ? AppLocalizations.of(context).closeSearch : AppLocalizations.of(context).searchRemotes,
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
            tooltip: AppLocalizations.of(context).addConnection,
            onPressed: _addRemote,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppLocalizations.of(context).refresh,
            onPressed: _loadRemotes,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (!_secretEncryptionActive)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.unencryptedCredentialsBanner,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).filterRemotesHint,
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
                                child: AppEmptyState(
                                  icon: Icons.cloud_queue,
                                  title: AppLocalizations.of(context).noRemoteConnections,
                                  subtitle: AppLocalizations.of(context).noRemoteConnectionsDesc,
                                  action: FilledButton.icon(
                                    onPressed: _addRemote,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(l10n.addRemoteStorage),
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
                                    child: AppEmptyState(
                                      icon: Icons.search_off,
                                      title: AppLocalizations.of(context).noMatchingConnections,
                                      subtitle: AppLocalizations.of(context).nothingMatchesQuery(_searchQuery),
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
                                          label: Text(AppLocalizations.of(context).addAnotherRemote),
                                        ),
                                      ),
                                    );
                                  }

                                  final r = displayedRemotes[i];
                                  final (icon, color) = _remoteVisuals(r.kind);
                                  final sub = _formatSubtitle(r, l10n);

                                  return Card(
                                    child: ListTile(
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          AppCircleBadge(icon: icon, color: color),
                                          if (_status[r.id] != null && _status[r.id] != _ConnStatus.unknown)
                                            Positioned(
                                              right: -1,
                                              bottom: -1,
                                              child: Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: _statusColor(_status[r.id]!),
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
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, size: 20),
                                            tooltip: AppLocalizations.of(context).remoteActions,
                                            onSelected: (action) {
                                              switch (action) {
                                                case 'test':
                                                  _testRemote(r);
                                                  break;
                                                case 'copy':
                                                  _copyRemoteUri(r);
                                                  break;
                                                case 'pin_shortcut':
                                                  _pinRemoteShortcut(r);
                                                  break;
                                                case 'edit':
                                                  _editRemote(r);
                                                  break;
                                                case 'delete':
                                                  _deleteRemote(r);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (ctx) => [
                                              PopupMenuItem(
                                                value: 'test',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.network_check, size: 18),
                                                    SizedBox(width: 8),
                                                    Text(AppLocalizations.of(context).testConnection),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'copy',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.copy_outlined, size: 18),
                                                    SizedBox(width: 8),
                                                    Text(AppLocalizations.of(context).copyUri),
                                                  ],
                                                ),
                                              ),
                                              if (_shortcutsSupported)
                                                PopupMenuItem(
                                                  value: 'pin_shortcut',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.add_to_home_screen, size: 18),
                                                      const SizedBox(width: 8),
                                                      Text(AppLocalizations.of(context).pinToHomeScreen),
                                                    ],
                                                  ),
                                                ),
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined, size: 18),
                                                    SizedBox(width: 8),
                                                    Text(AppLocalizations.of(context).editLabel),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete_outline,
                                                      size: 18,
                                                      color: Theme.of(context).colorScheme.error,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      AppLocalizations.of(context).delete,
                                                      style: TextStyle(
                                                        color: Theme.of(context).colorScheme.error,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Icon(Icons.chevron_right, size: 16),
                                        ],
                                      ),
                                      onTap: () => _openRemote(r),
                                      onLongPress: () => _showRemoteActionSheet(r),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
    );
    return widget.embedded ? scaffold : AppSwipeBack(child: scaffold);
  }
}
