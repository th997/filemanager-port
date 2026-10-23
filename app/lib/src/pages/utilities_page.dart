import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/servers.dart';
import '../services/file_open_service.dart';
import '../services/platform_paths.dart';
import '../services/sharing_service.dart';
import '../services/storage_service.dart';
import '../theme/app_ui_tokens.dart';
import 'trash_page.dart';

class UtilitiesPage extends StatefulWidget {
  const UtilitiesPage({super.key});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  int _trashCount = 0;
  int _cacheSizeBytes = 0;
  int _archiveCacheBytes = 0;
  bool _clearingCache = false;

  bool _serverRunning = false;
  ServerStatusDto? _serverStatus;
  bool _starting = false;

  late String _shareRoot;
  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  final TextEditingController _pwdCtrl = TextEditingController();
  bool _readOnly = true;
  bool _obscurePwd = true;

  @override
  void initState() {
    super.initState();
    _shareRoot = PlatformPaths.defaultRoot();
    _serverRunning = SharingService.instance.isRunning;
    _serverStatus = SharingService.instance.currentStatus;
    _loadData();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final List<meta_api.TrashItemDto> trash;
    final int cacheBytes;
    try {
      trash = await StorageService.instance.getTrashItems();
      cacheBytes = await FileOpenService.instance.getExportCacheSizeBytes();
    } catch (e) {
      // Pull-to-refresh used to fail silently, leaving the old counts on
      // screen with no hint that they were stale.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not read storage stats: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    int archiveBytes = 0;
    try {
      archiveBytes = fm_api.archiveCacheSize().toInt();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _trashCount = trash.length;
        _cacheSizeBytes = cacheBytes;
        _archiveCacheBytes = archiveBytes;
      });
    }
  }

  Future<void> _clearArchiveCache() async {
    try {
      fm_api.clearArchiveCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not clear archive cache: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() => _archiveCacheBytes = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archive cache cleared')),
      );
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      await FileOpenService.instance.clearExports();
      // Re-reading the size can fail on its own; the `finally` below is what
      // guarantees the spinner stops either way.
      final cacheBytes = await FileOpenService.instance.getExportCacheSizeBytes();
      if (mounted) {
        setState(() => _cacheSizeBytes = cacheBytes);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary cache cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not clear cache: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  Future<void> _emptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Recycle Bin'),
        content: Text('Permanently delete all $_trashCount items? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Empty All'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await StorageService.instance.clearTrash();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recycle bin emptied')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not empty trash: $e'), backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }
    }
  }

  Future<void> _pickShareFolder() async {
    final picked = await FolderPickerDialog.show(
      context,
      title: 'Choose shared folder',
      initialRoot: _shareRoot,
    );
    if (picked != null && mounted) {
      setState(() => _shareRoot = picked.path);
    }
  }

  Future<void> _toggleServer(bool start) async {
    if (start) {
      final portText = _portCtrl.text.trim();
      final port = int.tryParse(portText);
      if (portText.isNotEmpty && (port == null || port < 1 || port > 65535)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Port must be a number between 1 and 65535 (got "$portText")'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      setState(() => _starting = true);
      try {
        final pwd = _pwdCtrl.text.trim().isEmpty ? null : _pwdCtrl.text.trim();

        final status = await SharingService.instance.startHttp(
          rootDir: _shareRoot,
          port: port,
          password: pwd,
          readOnly: _readOnly,
        );

        if (mounted) {
          setState(() {
            _serverRunning = true;
            _serverStatus = status;
            _starting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _starting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start server: $e'), backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }
    } else {
      // The backend reports whether it actually stopped; ignoring the result
      // left the UI claiming "stopped" while the server kept serving.
      bool stopped;
      try {
        stopped = SharingService.instance.stopHttp();
      } catch (_) {
        stopped = false;
      }
      if (mounted) {
        setState(() {
          _serverRunning = !stopped;
          _serverStatus = stopped ? null : _serverStatus;
        });
        if (!stopped) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not stop the LAN server'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _friendlyPath(String path) {
    if (Platform.isIOS && path.contains('/Containers/Data/Application/')) {
      final docIdx = path.indexOf('/Documents');
      if (docIdx != -1) {
        final sub = path.substring(docIdx);
        return sub == '/Documents' ? 'Documents' : 'Documents${sub.substring('/Documents'.length)}';
      }
      return 'Documents';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).utilities, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppUiTokens.pagePadding,
        children: [
          // 1. Recycle Bin Card
          _buildSectionHeader(AppLocalizations.of(context).recycleBin),
          Card(
            child: ListTile(
              leading: const AppCircleBadge(
                icon: Icons.delete_outline,
                color: Colors.deepOrange,
              ),
              title: Text(AppLocalizations.of(context).recycleBin),
              subtitle: Text(
                isZh ? '回收站共有 $_trashCount 项' : '$_trashCount items in trash',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_trashCount > 0)
                    AppIconButton(
                      icon: Icons.delete_sweep_outlined,
                      size: 28,
                      iconSize: 18,
                      color: Colors.redAccent,
                      tooltip: isZh ? '清空回收站' : 'Empty Recycle Bin',
                      onPressed: _emptyTrash,
                    ),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashPage()),
                ).then((_) => _loadData());
              },
            ),
          ),

          const SizedBox(height: 12),

          // 2. LAN HTTP Sharing Card
          _buildSectionHeader(AppLocalizations.of(context).lanSharing),
          Card(
            elevation: _serverRunning ? 2 : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: _serverRunning
                  ? const BorderSide(color: Colors.green, width: 1.5)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.wifi_tethering,
                            size: 22,
                            color: _serverRunning ? Colors.green : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isZh ? '局域网网页共享服务' : 'Web Sharing Server',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              Text(
                                _serverRunning
                                    ? (isZh ? '🟢 局域网运行中' : '🟢 Running on LAN')
                                    : (isZh ? '⚪ 已停止' : '⚪ Stopped'),
                                style: TextStyle(fontSize: 10, color: _serverRunning ? Colors.green : Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      _starting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _serverRunning,
                                onChanged: _toggleServer,
                              ),
                            ),
                    ],
                  ),

                  if (_serverRunning && _serverStatus != null) ...[
                    const Divider(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.folder_shared, size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${isZh ? '共享目录' : 'Shared'}: ${_friendlyPath(_shareRoot)}${_readOnly ? (isZh ? ' (只读)' : ' (read-only)') : ''}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isZh
                          ? '同一 Wi-Fi 下任何浏览器输入以下地址即可访问：'
                          : 'Access files from any browser on the same Wi-Fi:',
                      style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    if (_serverStatus!.addresses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          isZh
                              ? '未检测到局域网 IP，请连接 Wi-Fi 或网线。'
                              : 'No local IP address detected. Connect to Wi-Fi or LAN.',
                          style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                        ),
                      )
                    else
                      ..._serverStatus!.addresses.map((ip) {
                      final url = 'http://$ip:${_serverStatus!.port}';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SelectableText(
                              url,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Colors.green),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 15),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(2),
                              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                              tooltip: isZh ? '复制网址' : 'Copy URL',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(isZh ? '网址已复制到剪贴板' : 'URL copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      isZh
                          ? '在局域网内免数据线共享文件。任何浏览器均可直接访问、串流媒体、下载或上传。'
                          : 'Share files on your local network without cables. Stream media, download or upload through any web browser.',
                      style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_shared, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isZh ? '共享目录' : 'Shared Folder',
                                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                                ),
                                Text(
                                  _friendlyPath(_shareRoot),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: _serverRunning ? null : _pickShareFolder,
                            child: Text(isZh ? '更改' : 'Change', style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 85,
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 11.5),
                            decoration: InputDecoration(
                              labelText: isZh ? '端口' : 'Port',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _pwdCtrl,
                            obscureText: _obscurePwd,
                            style: const TextStyle(fontSize: 11.5),
                            decoration: InputDecoration(
                              labelText: isZh ? '访问密码 (可选)' : 'Password (Optional)',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility, size: 15),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                tooltip: _obscurePwd ? 'Show password' : 'Hide password',
                                onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      title: Text(
                        isZh ? '只读模式 (禁止网页端上传)' : 'Read Only (disallow web uploads)',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: _readOnly,
                      onChanged: (v) => setState(() => _readOnly = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 3. Cache cleaner
          _buildSectionHeader(AppLocalizations.of(context).storageAndCache),
          Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            ListTile(
              leading: const AppCircleBadge(
                icon: Icons.cleaning_services,
                color: Colors.teal,
              ),
              title: Text(isZh ? '导出与预览缓存' : 'Export & Preview Cache'),
              subtitle: Text(
                isZh
                    ? '外部应用打开文件产生的临时缓存 (${_formatSize(_cacheSizeBytes)})'
                    : 'Temporary files cached when opening with external apps (${_formatSize(_cacheSizeBytes)})',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: _clearingCache
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: _cacheSizeBytes > 0 ? _clearCache : null,
                      child: Text(isZh ? '清理' : 'Clear', style: const TextStyle(fontSize: 11)),
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const AppCircleBadge(
                icon: Icons.archive_outlined,
                color: Colors.deepPurple,
              ),
              title: Text(isZh ? '远程与压缩包缓存' : 'Remote Archive Cache'),
              subtitle: Text(
                isZh
                    ? '浏览远程服务器时产生的临时文件 (${_formatSize(_archiveCacheBytes)})'
                    : 'Archives downloaded from remote servers for browsing (${_formatSize(_archiveCacheBytes)})',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _archiveCacheBytes > 0 ? _clearArchiveCache : null,
                child: Text(isZh ? '清理' : 'Clear', style: const TextStyle(fontSize: 11)),
              ),
            ),
              ],
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
