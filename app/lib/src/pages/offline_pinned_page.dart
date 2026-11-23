import 'dart:io';

import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../rust/api/metadata.dart';
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
  final Set<String> _syncingKeys = {};

  @override
  void initState() {
    super.initState();
    _capMb = int.tryParse(PreferencesService.instance.getString(_prefCapMb) ?? '') ?? 512;
    _reload();
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

  Future<void> _resync(PinnedFileDto item) async {
    final key = '${item.remoteRoot}::${item.remotePath}';
    setState(() => _syncingKeys.add(key));
    try {
      await pinRemoteFile(
        dbPath: StorageService.instance.dbPath,
        remoteRoot: item.remoteRoot,
        remotePath: item.remotePath,
        maxCacheBytes: BigInt.from(_capMb * 1024 * 1024),
      );
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _syncingKeys.remove(key));
    }
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
    if (lower.endsWith('.pdf')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
          ),
        ),
      );
    } else if (StructuredViewerPage.supports(item.displayName)) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StructuredViewerPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
            readOnly: true,
          ),
        ),
      );
    } else if (lower.endsWith('.txt') || lower.endsWith('.md') || lower.endsWith('.log')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextEditorPage(
            root: parent,
            path: baseName,
            fileName: item.displayName,
            readOnly: true,
          ),
        ),
      );
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
                            return ListTile(
                              leading: Icon(
                                item.localExists ? Icons.offline_pin : Icons.cloud_download,
                                color: item.localExists ? scheme.primary : scheme.outline,
                              ),
                              title: Text(item.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${formatBytes(item.size)} · ${item.remotePath}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
