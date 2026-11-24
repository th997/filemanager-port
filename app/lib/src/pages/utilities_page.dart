import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../dialogs/vault_dialogs.dart';
import '../rust/api/file_manager.dart' as fm_api;
import '../rust/api/metadata.dart' as meta_api;
import '../rust/api/servers.dart';
import '../services/file_open_service.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/semantic_colors.dart';
import '../services/sharing_service.dart';
import '../services/storage_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/qr_code_widget.dart';
import 'duplicate_finder_page.dart';
import 'peer_transfer_page.dart';
import 'photo_backup_page.dart';
import 'storage_analyzer_page.dart';
import 'sync_page.dart';
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
  int _selectedNicIndex = 0;

  bool _serverRunning = false;
  ServerStatusDto? _serverStatus;
  bool _starting = false;

  late String _shareRoot;
  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  final TextEditingController _pwdCtrl = TextEditingController();
  bool _readOnly = true;
  bool _obscurePwd = true;

  bool _webdavRunning = false;
  ServerStatusDto? _webdavStatus;
  bool _startingWebdav = false;
  late String _webdavRoot;
  String _webdavRelPath = '';
  final TextEditingController _webdavPortCtrl = TextEditingController(text: '8081');
  final TextEditingController _webdavUserCtrl = TextEditingController();
  final TextEditingController _webdavPwdCtrl = TextEditingController();
  bool _webdavReadOnly = true;
  bool _obscureWebdavPwd = true;

  @override
  void initState() {
    super.initState();
    final sharing = SharingService.instance;
    _shareRoot = sharing.rootDir ?? PlatformPaths.defaultRoot();
    _readOnly = sharing.readOnly;
    final savedPwd = sharing.password;
    if (savedPwd != null) _pwdCtrl.text = savedPwd;
    _serverRunning = sharing.isRunning;
    _serverStatus = sharing.currentStatus;

    _webdavRoot = sharing.webDavRoot ?? PlatformPaths.defaultRoot();
    _webdavRelPath = sharing.webDavRelPath;
    _webdavReadOnly = sharing.webDavReadOnly;
    if (sharing.webDavUsername != null) {
      _webdavUserCtrl.text = sharing.webDavUsername!;
    }
    if (sharing.webDavPassword != null) {
      _webdavPwdCtrl.text = sharing.webDavPassword!;
    }
    _webdavRunning = sharing.isWebDavRunning;
    _webdavStatus = sharing.webDavStatus;

    VaultService.instance.addListener(_onVaultChanged);
    _loadData();
  }

  @override
  void dispose() {
    VaultService.instance.removeListener(_onVaultChanged);
    _portCtrl.dispose();
    _pwdCtrl.dispose();
    _webdavPortCtrl.dispose();
    _webdavUserCtrl.dispose();
    _webdavPwdCtrl.dispose();
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _backupPrivacyFolder() async {
    final l10n = AppLocalizations.of(context);
    final outPath = await BackupVaultDialog.show(context);
    if (outPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.backupExportSuccess(outPath))),
      );
    }
  }

  Future<void> _importPrivacyFolder() async {
    final l10n = AppLocalizations.of(context);
    final imported = await ImportVaultDialog.show(context);
    if (imported != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.importSuccessNotice(imported.name))),
      );
    }
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
          content: Text(AppLocalizations.of(context).couldNotReadStorageStats('$e')),
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
            content: Text(AppLocalizations.of(context).couldNotClearArchiveCache('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() => _archiveCacheBytes = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).archiveCacheCleared)),
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
          SnackBar(content: Text(AppLocalizations.of(context).tempCacheCleared)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).couldNotClearCache('$e')),
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
        title: Text(AppLocalizations.of(context).emptyRecycleBin),
        actionsOverflowButtonSpacing: 8,
        content: Text(AppLocalizations.of(context).emptyTrashUtilityConfirm(_trashCount)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(context).emptyAll),
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
            SnackBar(content: Text(AppLocalizations.of(context).recycleBinEmptied)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).couldNotEmptyTrashError('$e')), backgroundColor: Theme.of(context).colorScheme.error),
          );
        }
      }
    }
  }

  Future<void> _pickShareFolder() async {
    final picked = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).chooseSharedFolder,
      initialRoot: _shareRoot,
    );
    if (picked != null && mounted) {
      setState(() => _shareRoot = picked.path);
    }
  }

  bool _isSameOrSubdir(String candidate, String base) {
    String normalize(String p) {
      var s = p.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
      if (Platform.isWindows) s = s.toLowerCase();
      return s;
    }

    final c = normalize(candidate);
    final b = normalize(base);
    if (b.isEmpty) return false;
    return c == b || c.startsWith('$b/');
  }

  bool _isForbiddenShareRoot(String root) {
    if (isVaultRoot(root)) return true;
    if (_isSameOrSubdir(root, PlatformPaths.defaultVaultStorageDir())) {
      return true;
    }
    for (final v in VaultService.instance.unlockedVaults) {
      if (_isSameOrSubdir(root, v.dirPath)) return true;
    }
    return false;
  }

  String get _webdavDisplayPath => _webdavRelPath.isEmpty
      ? _friendlyPath(_webdavRoot)
      : '${_friendlyPath(_webdavRoot)}/$_webdavRelPath';

  Future<void> _pickWebDavFolder() async {
    final picked = await FolderPickerDialog.show(
      context,
      title: AppLocalizations.of(context).chooseSharedFolder,
      initialRoot: _webdavRoot,
      initialPath: _webdavRelPath,
    );
    if (picked != null && mounted) {
      if (_isForbiddenShareRoot(picked.root)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).failedToStartServer(
                AppLocalizations.of(context).privacyFolder,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      setState(() {
        _webdavRoot = picked.root;
        _webdavRelPath = picked.relPath;
      });
    }
  }

  Future<void> _toggleWebDavServer(bool start) async {
    final l10n = AppLocalizations.of(context);
    if (start) {
      if (_isForbiddenShareRoot(_webdavRoot)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToStartServer(l10n.privacyFolder)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      final portText = _webdavPortCtrl.text.trim();
      final port = int.tryParse(portText);
      if (portText.isNotEmpty && (port == null || port < 1 || port > 65535)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.portValidationError(portText)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      setState(() => _startingWebdav = true);
      try {
        final status = await SharingService.instance.startWebDav(
          root: _webdavRoot,
          relPath: _webdavRelPath,
          port: port,
          username: _webdavUserCtrl.text.trim(),
          password: _webdavPwdCtrl.text.trim(),
          readOnly: _webdavReadOnly,
        );
        if (!mounted) return;
        setState(() {
          _webdavRunning = true;
          _webdavStatus = status;
          _startingWebdav = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _startingWebdav = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToStartServer('$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } else {
      final stopped = SharingService.instance.stopWebDav();
      if (mounted) {
        setState(() {
          _webdavRunning = !stopped;
          _webdavStatus = stopped ? null : _webdavStatus;
        });
      }
    }
  }

  Future<void> _toggleServer(bool start) async {
    if (start) {
      if (_isForbiddenShareRoot(_shareRoot)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).failedToStartServer(
                AppLocalizations.of(context).privacyFolder,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      final portText = _portCtrl.text.trim();
      final port = int.tryParse(portText);
      if (portText.isNotEmpty && (port == null || port < 1 || port > 65535)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).portValidationError(portText)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      setState(() => _starting = true);
      try {
        final pwd = _pwdCtrl.text.trim();

        final status = await SharingService.instance.startHttp(
          rootDir: _shareRoot,
          port: port,
          password: pwd.isEmpty ? null : pwd,
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
            SnackBar(content: Text(AppLocalizations.of(context).failedToStartServer('$e')), backgroundColor: Theme.of(context).colorScheme.error),
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
              content: Text(AppLocalizations.of(context).couldNotStopLanServer),
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
        return sub == '/Documents' ? AppLocalizations.of(context).documentsDir : '${AppLocalizations.of(context).documentsDir}${sub.substring('/Documents'.length)}';
      }
      return AppLocalizations.of(context).documentsDir;
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSwipeBack(
      child: Scaffold(
      appBar: AppBar(
        title: Text(l10n.utilities, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: l10n.refresh,
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
          // 0. Privacy Folders Card
          _buildPrivacyFoldersSection(l10n),

          const SizedBox(height: 12),

          // 1. Recycle Bin Card
          _buildSectionHeader(l10n.recycleBin),
          Card(
            child: ListTile(
              leading: const AppCircleBadge(
                icon: Icons.delete_outline,
                color: Colors.deepOrange,
              ),
              title: Text(l10n.recycleBin),
              subtitle: Text(
                l10n.trashCountNotice(_trashCount),
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
                      color: Theme.of(context).colorScheme.error,
                      tooltip: l10n.emptyRecycleBin,
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

          // Professional Toolbox: Storage Analyzer, Duplicate Finder, Directory Sync, Offline Pinned
          _buildSectionHeader(l10n.utilities),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.pie_chart_outline,
                    color: Colors.teal,
                    size: 32,
                    iconSize: 18,
                  ),
                  title: Text(l10n.storageAnalyzer, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(l10n.storageAnalyzerSubtitle, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StorageAnalyzerPage(
                          root: PlatformPaths.defaultRoot(),
                          title: l10n.localStorage,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.find_replace,
                    color: Colors.orange,
                    size: 32,
                    iconSize: 18,
                  ),
                  title: Text(l10n.duplicateFinder, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(l10n.duplicateFinderSubtitle, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DuplicateFinderPage(
                          root: PlatformPaths.defaultRoot(),
                          title: l10n.localStorage,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.sync,
                    color: Colors.blue,
                    size: 32,
                    iconSize: 18,
                  ),
                  title: Text(l10n.directorySync, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(l10n.directorySyncSubtitle, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SyncPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.swap_horiz,
                    color: Colors.indigo,
                    size: 32,
                    iconSize: 18,
                  ),
                  title: Text(l10n.lanPeerTransferTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(l10n.lanPeerTransferSubtitle, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PeerTransferPage()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const AppCircleBadge(
                    icon: Icons.backup_outlined,
                    color: Colors.green,
                    size: 32,
                    iconSize: 18,
                  ),
                  title: Text(l10n.photoBackupTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(l10n.photoBackupSubtitle, style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PhotoBackupPage()),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 2. LAN HTTP Sharing Card
          _buildSectionHeader(l10n.lanSharing),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: _serverRunning
                  ? BorderSide(color: Theme.of(context).colorScheme.success, width: 1.5)
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
                            color: _serverRunning ? Theme.of(context).colorScheme.success : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.webSharingServer,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                _serverRunning
                                    ? l10n.runningOnLan
                                    : l10n.stopped,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _serverRunning
                                      ? Theme.of(context).colorScheme.success
                                      : Theme.of(context).colorScheme.outline,
                                ),
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
                        Icon(Icons.folder_shared, size: 16, color: Theme.of(context).colorScheme.success),
                        const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: _shareRoot));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.sharedPathCopied)),
                              );
                            },
                            child: Text(
                              '${l10n.shared}: ${_friendlyPath(_shareRoot)}${_readOnly ? l10n.readOnly : ''}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.shareInstructions,
                      style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    if (_serverStatus!.addresses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.noLanIpFound,
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.warning),
                        ),
                      )
                    else ...[
                      Builder(
                        builder: (ctx) {
                          final addrs = _serverStatus!.addresses;
                          final idx = _selectedNicIndex.clamp(0, addrs.length - 1);
                          final activeIp = addrs[idx];
                          final query = Uri.tryParse(_serverStatus!.url)?.query ?? '';
                          final activeUrl =
                              'http://$activeIp:${_serverStatus!.port}${query.isEmpty ? '' : '?$query'}';
                          return Column(
                            children: [
                              if (addrs.length > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Wrap(
                                    spacing: 6,
                                    children: [
                                      for (int i = 0; i < addrs.length; i++)
                                        ChoiceChip(
                                          label: Text(addrs[i], style: const TextStyle(fontSize: 11)),
                                          selected: i == idx,
                                          onSelected: (_) => setState(() => _selectedNicIndex = i),
                                        ),
                                    ],
                                  ),
                                ),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Theme.of(ctx).dividerColor.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: QrCodeWidget(data: activeUrl, size: 150),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      ..._serverStatus!.addresses.map((ip) {
                      // The backend URL carries a random per-share session
                      // token. Keep it on every listed address: a copied link
                      // then works directly, and the password itself never
                      // appears in a URL, history or Referer header.
                      final query = Uri.tryParse(_serverStatus!.url)?.query ?? '';
                      final url =
                          'http://$ip:${_serverStatus!.port}${query.isEmpty ? '' : '?$query'}';
                      final successColor = Theme.of(context).colorScheme.success;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: successColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: successColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                url,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: successColor),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_2, size: 18),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              tooltip: l10n.showQrCode,
                              onPressed: () => _showLanQrDialog(url),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              tooltip: l10n.copyUrl,
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.urlCopied)),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    ],
                    if ((SharingService.instance.password ?? _pwdCtrl.text.trim()).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final activePwd =
                              SharingService.instance.password ?? _pwdCtrl.text.trim();
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.key, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SelectableText(
                                    '${l10n.sharePasswordLabel}: $activePwd',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  tooltip: l10n.copyPassword,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: activePwd));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l10n.passwordCopied)),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.lanSharingDesc,
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
                                  l10n.shared,
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
                            child: Text(l10n.change, style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 85,
                          height: 44,
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              labelText: l10n.port,
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _pwdCtrl,
                              obscureText: _obscurePwd,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                labelText: l10n.passwordFieldLabel,
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  tooltip: _obscurePwd ? l10n.showPassword : l10n.hidePassword,
                                  onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 2, bottom: 2),
                      child: Text(
                        l10n.passwordFieldHelper,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      title: Text(
                        l10n.readOnlyMode,
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

          // 2b. LAN WebDAV Server Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: _webdavRunning
                  ? BorderSide(color: Theme.of(context).colorScheme.success, width: 1.5)
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
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 22,
                              color: _webdavRunning
                                  ? Theme.of(context).colorScheme.success
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.lanWebdavShareTitle,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    _webdavRunning
                                        ? l10n.runningOnLan
                                        : l10n.lanWebdavShareSubtitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _webdavRunning
                                          ? Theme.of(context).colorScheme.success
                                          : Theme.of(context).colorScheme.outline,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      _startingWebdav
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: _webdavRunning,
                                onChanged: _toggleWebDavServer,
                              ),
                            ),
                    ],
                  ),
                  if (_webdavRunning && _webdavStatus != null) ...[
                    const Divider(height: 12),
                    Text(
                      '${l10n.shared}: $_webdavDisplayPath',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_webdavStatus!.addresses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          l10n.noLanIpFound,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.warning,
                          ),
                        ),
                      )
                    else ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: QrCodeWidget(
                            data:
                                'http://${_webdavStatus!.addresses.first}:${_webdavStatus!.port}/',
                            size: 140,
                          ),
                        ),
                      ),
                      for (final ip in _webdavStatus!.addresses)
                        Builder(
                          builder: (ctx) {
                            final davUrl = 'http://$ip:${_webdavStatus!.port}/';
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(ctx).colorScheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      davUrl,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Theme.of(ctx).colorScheme.success,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.qr_code_2, size: 18),
                                    tooltip: l10n.showQrCode,
                                    onPressed: () => _showLanQrDialog(davUrl),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16),
                                    tooltip: l10n.copyUrl,
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: davUrl));
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text(l10n.webdavUrlCopied)),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _webdavDisplayPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: _webdavRunning ? null : _pickWebDavFolder,
                          child: Text(l10n.change, style: const TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _webdavPortCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              labelText: l10n.port,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _webdavUserCtrl,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              labelText: l10n.webdavUsernameOptional,
                              isDense: true,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _webdavPwdCtrl,
                            obscureText: _obscureWebdavPwd,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              labelText: l10n.passwordFieldLabel,
                              isDense: true,
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureWebdavPwd ? Icons.visibility_off : Icons.visibility,
                                  size: 16,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureWebdavPwd = !_obscureWebdavPwd),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    CheckboxListTile(
                      title: Text(l10n.readOnlyMode, style: const TextStyle(fontSize: 11)),
                      value: _webdavReadOnly,
                      onChanged: (v) => setState(() => _webdavReadOnly = v ?? true),
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
          _buildSectionHeader(l10n.storageAndCache),
          Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            ListTile(
              leading: const AppCircleBadge(
                icon: Icons.cleaning_services,
                color: Colors.teal,
              ),
              title: Text(l10n.exportPreviewCache),
              subtitle: Text(
                '${l10n.exportPreviewCache} (${_formatSize(_cacheSizeBytes)})',
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
                      child: Text(l10n.clear, style: const TextStyle(fontSize: 11)),
                    ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const AppCircleBadge(
                icon: Icons.archive_outlined,
                color: Colors.deepPurple,
              ),
              title: Text(l10n.remoteArchiveCache),
              subtitle: Text(
                '${l10n.remoteArchiveCache} (${_formatSize(_archiveCacheBytes)})',
                style: const TextStyle(fontSize: 10),
              ),
              trailing: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _archiveCacheBytes > 0 ? _clearArchiveCache : null,
                child: Text(l10n.clear, style: const TextStyle(fontSize: 11)),
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

  Widget _buildPrivacyFoldersSection(AppLocalizations l10n) {
    final unlockedCount = VaultService.instance.unlockedVaults.length;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(l10n.privacyFolders),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const AppCircleBadge(
                  icon: Icons.enhanced_encryption_outlined,
                  color: Colors.indigo,
                ),
                title: Text(l10n.privacyFolders),
                subtitle: Text(
                  l10n.privacyFoldersDesc,
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: unlockedCount > 0
                    ? TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: colorScheme.error,
                        ),
                        onPressed: () {
                          VaultService.instance.lockAll();
                        },
                        icon: const Icon(Icons.lock_outline, size: 15),
                        label: Text(
                          l10n.lockAllPrivacyFolders(unlockedCount),
                          style: const TextStyle(fontSize: 11),
                        ),
                      )
                    : null,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.archive_outlined, size: 19),
                title: Text(l10n.backupPrivacyFolder, style: const TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _backupPrivacyFolder,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(Icons.unarchive_outlined, size: 19),
                title: Text(l10n.importPrivacyFolder, style: const TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.chevron_right, size: 16),
                onTap: _importPrivacyFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }


  void _showLanQrDialog(String url) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.showQrCode),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(ctx).dividerColor.withValues(alpha: 0.25)),
              ),
              child: QrCodeWidget(data: url, size: 220),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.scanQrToConnect,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            SelectableText(
              url,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.copyUrl),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.urlCopied)),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.close),
          ),
        ],
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
