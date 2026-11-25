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
import '../theme/app_ui_tokens.dart';
import 'image_viewer_page.dart';
import 'media_player_page.dart';
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

  Future<bool> _confirmDiscardLocalChanges(PinnedFileDto item) async {
    final key = '${item.remoteRoot}::${item.remotePath}';
    final status = _statuses[key]?.status;
    if (status != 'local_modified' && status != 'conflict') {
      return true;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.offlineDiscardLocalConfirmTitle),
        content: Text(l10n.offlineDiscardLocalConfirmBody(item.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _pushLocalChanges(PinnedFileDto item, {bool isConflict = false}) async {
    final l10n = AppLocalizations.of(context);
    if (isConflict) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.offlineOverwriteConfirmTitle),
          content: Text(l10n.offlineOverwriteConfirmBody(item.displayName)),
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
          SnackBar(content: Text(l10n.offlineUploadedNotice(item.displayName))),
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

  Future<void> _resyncWithConfirm(PinnedFileDto item) async {
    if (!await _confirmDiscardLocalChanges(item)) return;
    await _resync(item);
  }

  Future<void> _unpin(PinnedFileDto item) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirmDiscardLocalChanges(item)) return;
    try {
      unpinRemoteFile(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: item.remoteRoot,
        remotePath: item.remotePath,
      );
      _statuses.remove('${item.remoteRoot}::${item.remotePath}');
      _reload();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(friendlyErrorText(e, l10n))),
        );
      }
    }
  }

  Future<void> _openOffline(PinnedFileDto item) async {
    final file = File(item.localCachePath);
    if (!file.existsSync()) {
      await _resync(item);
      if (!mounted || !File(item.localCachePath).existsSync()) return;
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
    } else if (EntryItem.isImageExtension(ext)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            filePath: file.path,
            fileName: item.displayName,
          ),
        ),
      );
    } else if (EntryItem.isMediaExtension(ext)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaPlayerPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
            isAudio: EntryItem.isAudioExtension(ext),
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
      try {
        await FileOpenService.instance.openWith(parent, baseName);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyErrorText(e, AppLocalizations.of(context)))),
          );
        }
      }
    }
  }

  void _updateCap(int mb) {
    final prev = _capMb;
    setState(() => _capMb = mb);
    try {
      evictPinnedCache(
        dbPath: StorageService.instance.dbPath,
        maxBytes: BigInt.from(mb * 1024 * 1024),
      );
      PreferencesService.instance.setString(_prefCapMb, '$mb');
      _reload();
    } catch (e) {
      setState(() => _capMb = prev);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorText(e, AppLocalizations.of(context)))),
        );
      }
    }
  }

  String _capLabel(int mb) =>
      mb >= 1024 && mb % 1024 == 0 ? '${mb ~/ 1024} GB' : '$mb MB';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 480;

    return AppSwipeBack(
      child: Scaffold(
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
                tooltip: l10n.offlineCheckUpdatesTooltip,
                onPressed: _checkingUpdates ? null : _checkAllUpdates,
              ),
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: l10n.offlineSyncAllTooltip,
                onPressed: _syncingKeys.isEmpty ? _resyncAll : null,
              ),
            ],
            PopupMenuButton<int>(
              tooltip: l10n.offlineLruCapTooltip,
              icon: const Icon(Icons.storage),
              onSelected: _updateCap,
              itemBuilder: (_) => [
                PopupMenuItem(value: 128, child: Text(l10n.offlineLruCapOption('128 MB'))),
                PopupMenuItem(value: 512, child: Text(l10n.offlineLruCapOption('512 MB'))),
                PopupMenuItem(value: 1024, child: Text(l10n.offlineLruCapOption('1 GB'))),
                PopupMenuItem(value: 2048, child: Text(l10n.offlineLruCapOption('2 GB'))),
                PopupMenuItem(value: 5120, child: Text(l10n.offlineLruCapOption('5 GB'))),
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
                          l10n.offlineBannerSummary(
                            _items.length,
                            formatBytes(_totalBytes),
                            _capLabel(_capMb),
                          ),
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
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _reload();
                        await _checkAllUpdates();
                      },
                      child: _items.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) => SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                  child: AppEmptyState(
                                    icon: Icons.offline_pin_outlined,
                                    title: l10n.offlinePinned,
                                    subtitle: l10n.offlinePinnedSubtitle,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: AppUiTokens.pagePadding,
                              itemCount: _items.length,
                              itemBuilder: (_, i) {
                                final item = _items[i];
                                final key = '${item.remoteRoot}::${item.remotePath}';
                                final syncing = _syncingKeys.contains(key);
                                final st = _statuses[key];
                                final (String? statusText, Color? statusColor) = switch (st?.status) {
                                  'local_modified' => (l10n.offlineStatusLocalModified, Colors.orange),
                                  'remote_newer' => (l10n.offlineStatusRemoteNewer, Colors.blue),
                                  'conflict' => (l10n.offlineStatusConflict, Colors.red),
                                  'synced' => (l10n.offlineStatusSynced, Colors.green),
                                  'missing_local' => (l10n.offlineStatusMissingLocal, Colors.red),
                                  'remote_error' => (l10n.offlineStatusOffline, Colors.grey),
                                  _ => (null, null),
                                };
                                final canPush = st?.status == 'local_modified' || st?.status == 'conflict';
                                return Card(
                                  margin: AppUiTokens.cardMargin,
                                  child: ListTile(
                                    leading: Icon(
                                      item.localExists ? Icons.offline_pin : Icons.cloud_download,
                                      color: item.localExists ? scheme.primary : scheme.outline,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
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
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: statusColor,
                                              ),
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
                                    trailing: syncing
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : isCompact
                                            ? PopupMenuButton<String>(
                                                onSelected: (action) {
                                                  if (action == 'push') {
                                                    _pushLocalChanges(
                                                      item,
                                                      isConflict: st?.status == 'conflict',
                                                    );
                                                  } else if (action == 'resync') {
                                                    _resyncWithConfirm(item);
                                                  } else if (action == 'unpin') {
                                                    _unpin(item);
                                                  }
                                                },
                                                itemBuilder: (_) => [
                                                  if (canPush)
                                                    PopupMenuItem(
                                                      value: 'push',
                                                      child: ListTile(
                                                        leading: Icon(
                                                          Icons.cloud_upload_outlined,
                                                          size: 18,
                                                          color: st?.status == 'conflict'
                                                              ? scheme.error
                                                              : scheme.primary,
                                                        ),
                                                        title: Text(l10n.offlineUploadLocalTooltip),
                                                        dense: true,
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                  PopupMenuItem(
                                                    value: 'resync',
                                                    child: ListTile(
                                                      leading: const Icon(Icons.refresh, size: 18),
                                                      title: Text(l10n.refresh),
                                                      dense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'unpin',
                                                    child: ListTile(
                                                      leading: const Icon(Icons.push_pin_outlined, size: 18),
                                                      title: Text(l10n.unpinOffline),
                                                      dense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (canPush)
                                                    IconButton(
                                                      icon: Icon(
                                                        Icons.cloud_upload_outlined,
                                                        size: 18,
                                                        color: st?.status == 'conflict'
                                                            ? scheme.error
                                                            : scheme.primary,
                                                      ),
                                                      tooltip: l10n.offlineUploadLocalTooltip,
                                                      onPressed: () => _pushLocalChanges(
                                                        item,
                                                        isConflict: st?.status == 'conflict',
                                                      ),
                                                    ),
                                                  IconButton(
                                                    icon: const Icon(Icons.refresh, size: 18),
                                                    tooltip: l10n.refresh,
                                                    onPressed: () => _resyncWithConfirm(item),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.push_pin_outlined, size: 18),
                                                    tooltip: l10n.unpinOffline,
                                                    onPressed: () => _unpin(item),
                                                  ),
                                                ],
                                              ),
                                    onTap: () => _openOffline(item),
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
