import 'dart:async';
import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../models/entry_item.dart';
import '../rust/api/metadata.dart';
import '../services/auto_sync_service.dart';
import '../services/error_text.dart';
import '../widgets/error_recovery_action.dart';
import '../services/file_open_service.dart';
import '../services/preferences_service.dart';
import '../services/storage_service.dart';
import '../services/task_service.dart';
import 'pdf_viewer_page.dart';
import 'structured_viewer_page.dart';
import 'text_editor_page.dart';

/// Manages remote files pinned for offline access with LRU cache cap control.
class OfflinePinnedPage extends StatefulWidget {
  const OfflinePinnedPage({super.key});

  @override
  State<OfflinePinnedPage> createState() => _OfflinePinnedPageState();
}

class _OfflinePinnedPageState extends State<OfflinePinnedPage> {
  static const _prefCapMb = 'offline.pin_cap_mb';
  List<PinnedFileDto> _items = const [];
  int _capMb = 512;
  bool _loading = true;
  bool _checkingUpdates = false;
  final Set<String> _syncingKeys = {};
  final Map<String, PinnedSyncStatusDto> _statuses = {};

  @override
  void initState() {
    super.initState();
    _capMb = int.tryParse(PreferencesService.instance.getString(_prefCapMb) ?? '') ?? 512;
    _reload();
    if (AutoSyncService.instance.isOfflineAutoSyncEnabled && _items.isNotEmpty) {
      unawaited(_autoReconcileAndRefresh());
    }
  }

  Future<void> _autoReconcileAndRefresh() async {
    await AutoSyncService.instance.reconcileOfflinePinnedFiles();
    if (!mounted) return;
    _reload();
    await _checkAllUpdates();
  }

  void _reload() {
    try {
      final list = listPinnedFiles(dbPath: StorageService.instance.dbPath);
      if (mounted) {
        setState(() {
          _items = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  BigInt get _totalBytes =>
      _items.fold(BigInt.zero, (acc, e) => acc + e.size);

  Future<void> _resync(PinnedFileDto item, {bool reloadAfter = true}) async {
    final key = '${item.remoteRoot}::${item.remotePath}';
    setState(() => _syncingKeys.add(key));
    try {
      await pinRemoteFile(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: item.remoteRoot,
        remotePath: item.remotePath,
        maxCacheBytes: BigInt.from(_capMb * 1024 * 1024),
      );
      _statuses.remove(key);
      if (reloadAfter) {
        _reload();
        await _checkStatusFor(item);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorText(e, AppLocalizations.of(context))),
            action: ErrorRecoveryActionButton.buildSnackBarAction(
              context,
              rawError: e,
              root: item.remoteRoot,
              onRetry: () => _resync(item),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingKeys.remove(key));
    }
  }

  Future<void> _checkStatusFor(PinnedFileDto item) async {
    final key = '${item.remoteRoot}::${item.remotePath}';
    try {
      final st = await checkPinnedFileStatus(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: item.remoteRoot,
        remotePath: item.remotePath,
      );
      if (mounted) {
        setState(() => _statuses[key] = st);
      }
    } catch (_) {}
  }

  Future<void> _checkAllUpdates() async {
    if (_items.isEmpty || _checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    try {
      for (final item in List<PinnedFileDto>.of(_items)) {
        if (!mounted) break;
        await _checkStatusFor(item);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _pushLocalChanges(PinnedFileDto item, {bool isConflict = false}) async {
    final l10n = AppLocalizations.of(context);
    if (isConflict) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Overwrite remote changes?'),
          content: Text(
            'Both the local cached copy and remote file for "${item.displayName}" have changed. Upload local version anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }

    final key = '${item.remoteRoot}::${item.remotePath}';
    setState(() => _syncingKeys.add(key));
    try {
      await pushPinnedFile(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: item.remoteRoot,
        remotePath: item.remotePath,
      );
      _statuses.remove(key);
      _reload();
      await _checkStatusFor(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded "${item.displayName}" to remote.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyErrorText(e, l10n)),
            action: ErrorRecoveryActionButton.buildSnackBarAction(
              context,
              rawError: e,
              root: item.remoteRoot,
              onRetry: () => _pushLocalChanges(item, isConflict: isConflict),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingKeys.remove(key));
    }
  }

  Future<void> _resyncAll() async {
    if (_items.isEmpty || _syncingKeys.isNotEmpty) return;
    final snapshot = List<PinnedFileDto>.of(_items);
    for (final item in snapshot) {
      if (!mounted) break;
      final key = '${item.remoteRoot}::${item.remotePath}';
      final status = _statuses[key]?.status;
      if (status == 'local_modified' || status == 'conflict') {
        continue;
      }
      await _resync(item, reloadAfter: false);
    }
    if (!mounted) return;
    _reload();
    await _checkAllUpdates();
  }

  void _unpin(PinnedFileDto item) {
    unpinRemoteFile(
      dbPath: StorageService.instance.dbPath,
      remoteRoot: item.remoteRoot,
      remotePath: item.remotePath,
    );
    _reload();
  }

  Future<void> _openOffline(PinnedFileDto item) async {
    final file = File(item.localCachePath);
    if (!file.existsSync()) {
      await _resync(item);
      return;
    }
    final parent = file.parent.path;
    final baseName = file.uri.pathSegments.last;
    final lower = item.displayName.toLowerCase();
    if (!mounted) return;
    final dot = lower.lastIndexOf('.');
    final ext = dot >= 0 && dot < lower.length - 1 ? lower.substring(dot + 1) : '';
    if (lower.endsWith('.pdf')) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
          ),
        ),
      );
    } else if (StructuredViewerPage.supports(item.displayName)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StructuredViewerPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
            readOnly: false,
          ),
        ),
      );
      if (mounted) {
        _reload();
        await _checkStatusFor(item);
      }
    } else if (EntryItem.isTextExtension(ext) || lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.log')) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
            readOnly: false,
          ),
        ),
      );
      if (mounted) {
        _reload();
        await _checkStatusFor(item);
      }
    } else {
      await FileOpenService.instance.openWith(parent, baseName);
    }
  }

  void _updateCap(int mb) {
    setState(() => _capMb = mb);
    PreferencesService.instance.setString(_prefCapMb, '$mb');
    evictPinnedCache(
      dbPath: StorageService.instance.dbPath,
      maxBytes: BigInt.from(mb * 1024 * 1024),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offlinePinned),
        actions: [
          if (_items.isNotEmpty) ...[
            IconButton(
              icon: _checkingUpdates
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              tooltip: 'Check Updates',
              onPressed: _checkingUpdates ? null : _checkAllUpdates,
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync All',
              onPressed: _syncingKeys.isEmpty ? _resyncAll : null,
            ),
          ],
          PopupMenuButton<int>(
            tooltip: 'LRU Cache Cap',
            icon: const Icon(Icons.storage),
            onSelected: _updateCap,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 128, child: Text('LRU Cap: 128 MB')),
              PopupMenuItem(value: 512, child: Text('LRU Cap: 512 MB')),
              PopupMenuItem(value: 1024, child: Text('LRU Cap: 1 GB')),
              PopupMenuItem(value: 2048, child: Text('LRU Cap: 2 GB')),
              PopupMenuItem(value: 5120, child: Text('LRU Cap: 5 GB')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: scheme.surfaceContainerLow,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_items.length} pinned · ${formatBytes(_totalBytes)} / $_capMb MB',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (_totalBytes.toDouble() / (_capMb * 1024 * 1024)).clamp(0.0, 1.0),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          l10n.offlineAutoSyncTitle,
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: AutoSyncService.instance.isOfflineAutoSyncEnabled,
                        onChanged: (v) {
                          setState(() {
                            AutoSyncService.instance.isOfflineAutoSyncEnabled = v;
                          });
                          if (v && _items.isNotEmpty) {
                            unawaited(_autoReconcileAndRefresh());
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? Center(child: Text(l10n.offlinePinnedSubtitle))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final key = '${item.remoteRoot}::${item.remotePath}';
                            final syncing = _syncingKeys.contains(key);
                            final st = _statuses[key];
                            final (String? statusText, Color? statusColor) = switch (st?.status) {
                              'local_modified' => ('Local Modified', Colors.orange),
                              'remote_newer' => ('Remote Newer', Colors.blue),
                              'conflict' => ('Conflict', Colors.red),
                              'synced' => ('Synced', Colors.green),
                              'missing_local' => ('Missing Local', Colors.red),
                              'remote_error' => ('Offline', Colors.grey),
                              _ => (null, null),
                            };
                            final canPush = st?.status == 'local_modified' || st?.status == 'conflict';
                            return ListTile(
                              leading: Icon(
                                item.localExists ? Icons.offline_pin : Icons.cloud_download,
                                color: item.localExists ? scheme.primary : scheme.outline,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (statusText != null && statusColor != null)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                '${formatBytes(item.size)} · ${item.remotePath}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (canPush && !syncing)
                                    IconButton(
                                      icon: Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 18,
                                        color: st?.status == 'conflict' ? scheme.error : scheme.primary,
                                      ),
                                      tooltip: 'Upload local changes to remote',
                                      onPressed: () => _pushLocalChanges(
                                        item,
                                        isConflict: st?.status == 'conflict',
                                      ),
                                    ),
                                  if (syncing)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else
                                    IconButton(
                                      icon: const Icon(Icons.refresh, size: 18),
                                      onPressed: () => _resync(item),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.push_pin_outlined, size: 18),
                                    tooltip: l10n.unpinOffline,
                                    onPressed: () => _unpin(item),
                                  ),
                                ],
                              ),
                              onTap: () => _openOffline(item),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
