import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../dialogs/remote_wizard_dialog.dart';
import '../rust/api/file_manager.dart' show invalidateRoot;
import '../rust/api/remotes.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../services/semantic_colors.dart';
import '../services/error_text.dart';
import '../services/platform_capabilities.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'browser_page.dart';

import '../services/external_file_service.dart';

enum _ConnStatus { unknown, checking, online, offline }

class RemotesPage extends StatefulWidget {
  final ExternalPickRequest? pickRequest;

  const RemotesPage({super.key, this.pickRequest});

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

  void _copyRemoteUri(RemoteConfigDto r) {
    final uri = r.endpoint ??
        (r.bucket != null
            ? '${r.kind}://${r.bucket}'
            : '${r.kind}://${r.host ?? ""}:${r.port ?? ""}');
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copiedValue(uri))),
    );
  }

  /// The stored config could not be decrypted, so every field but the
  /// name and kind is empty. Editing or testing it would just fail.
  static bool _isUnreadable(RemoteConfigDto r) =>
      r.rootPath == null &&
      r.host == null &&
      r.endpoint == null &&
      r.bucket == null;

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
    final sub = r.endpoint ??
        (r.bucket != null ? 'Bucket: ${r.bucket}' : '${r.host ?? ""}:${r.port ?? ""}');

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
                title: Text(AppLocalizations.of(context).connectAndBrowse),
                onTap: () {
                  Navigator.pop(ctx);
                  _openRemote(r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.network_check),
                title: Text(AppLocalizations.of(context).testConnection),
                onTap: () {
                  Navigator.pop(ctx);
                  _testRemote(r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(AppLocalizations.of(context).copyUri),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyRemoteUri(r);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(AppLocalizations.of(context).editConfiguration),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRemote(r);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text(
                  AppLocalizations.of(context).deleteRemote,
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
      _loadRemotes();
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
      _loadRemotes();
    }
  }

  Future<void> _deleteRemote(RemoteConfigDto remote) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).deleteRemote),
        content: Text(
          AppLocalizations.of(context).deleteRemoteConfirm(remote.name)

          ,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(AppLocalizations.of(context).delete)),
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
              content: Text(AppLocalizations.of(context).couldNotDeleteNamed(remote.name, '$e')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }
      _loadRemotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).deletedItem(remote.name))),
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
      error = 'timed out after 8 seconds';
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

  Future<void> _exportRemotes() async {
    try {
      if (_remotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noConnectionsToExport)),
        );
        return;
      }
      final jsonStr = await StorageService.instance.exportRemotesJson();
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context).backupConnectionsCount(_remotes.length),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).backupConnectionsDesc,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(AppLocalizations.of(context).copyToClipboard),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocalizations.of(context).connectionsCopied)),
                    );
                  },
                ),
                if (PlatformCapabilities.supportsNativeShareSheet) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(AppLocalizations.of(context).shareSaveToFiles),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      SharePlus.instance.share(ShareParams(
                        text: jsonStr,
                        subject: 'remotes_backup.json',
                      ));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).exportFailed('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _importRemotes() async {
    final controller = TextEditingController();
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (clip?.text != null &&
          (clip!.text!.trim().startsWith('[') || clip.text!.trim().startsWith('{'))) {
        controller.text = clip.text!.trim();
      }
    } catch (_) {}

    if (!mounted) {
      controller.dispose();
      return;
    }
    bool? imported;
    try {
      var importing = false;
      imported = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(AppLocalizations.of(context).restoreConnections),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).pasteJsonBackupHint,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '[{"id": "...", "name": "...", "kind": "s3", ...}]',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: importing ? null : () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: importing
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        setDialogState(() => importing = true);
                        try {
                          final count = await StorageService.instance.importRemotesJson(text);
                          final failures = StorageService.instance.lastImportFailures;
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop(true);
                          }
                          if (mounted) {
                            final detail = failures.isEmpty
                                ? ''
                                : '; ${failures.length} failed: ${failures.join(', ')}';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context).importedConnections(count, detail)),
                                backgroundColor: failures.isEmpty
                                    ? Theme.of(context).colorScheme.success
                                    : Theme.of(context).colorScheme.error,
                              ),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => importing = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(ctx).importFailed('$e')),
                                backgroundColor: Theme.of(ctx).colorScheme.error,
                              ),
                            );
                          }
                        }
                      },
                child: importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppLocalizations.of(context).importAction),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
    if (imported == true) {
      _loadRemotes();
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
          PopupMenuButton<String>(
            tooltip: AppLocalizations.of(context).backupRestore,
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'export') {
                _exportRemotes();
              } else if (val == 'import') {
                _importRemotes();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).backupExport),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline, size: 18),
                    SizedBox(width: 8),
                    Text(AppLocalizations.of(context).restoreImport),
                  ],
                ),
              ),
            ],
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
                                    label: Text(AppLocalizations.of(context).addRemoteStorage),
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
                                  final unreadable = _isUnreadable(r);
                                  final sub = unreadable
                                      ? AppLocalizations.of(context).detailsUnavailableReconnect
                                      : (r.endpoint ??
                                          (r.bucket != null
                                              ? 'Bucket: ${r.bucket}'
                                              : '${r.host ?? ""}:${r.port ?? ""}'));

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
      ),
    );
  }
}
