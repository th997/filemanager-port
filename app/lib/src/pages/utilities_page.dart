import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dialogs/folder_picker_dialog.dart';
import '../rust/api/servers.dart';
import '../services/file_open_service.dart';
import '../services/platform_paths.dart';
import '../services/sharing_service.dart';
import '../services/storage_service.dart';
import 'trash_page.dart';

class UtilitiesPage extends StatefulWidget {
  const UtilitiesPage({super.key});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  int _trashCount = 0;
  int _cacheSizeBytes = 0;
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
    final trash = await StorageService.instance.getTrashItems();
    final cacheBytes = await FileOpenService.instance.getExportCacheSizeBytes();
    if (mounted) {
      setState(() {
        _trashCount = trash.length;
        _cacheSizeBytes = cacheBytes;
      });
    }
  }

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      await FileOpenService.instance.clearExports();
    } catch (e) {
      if (mounted) {
        setState(() => _clearingCache = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not clear cache: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }
    final cacheBytes = await FileOpenService.instance.getExportCacheSizeBytes();
    if (mounted) {
      setState(() {
        _cacheSizeBytes = cacheBytes;
        _clearingCache = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporary cache cleared')),
      );
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
            backgroundColor: Colors.red.shade700,
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
            SnackBar(content: Text('Failed to start server: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      SharingService.instance.stopHttp();
      setState(() {
        _serverRunning = false;
        _serverStatus = null;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilities', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          // 1. Recycle Bin Card
          _buildSectionHeader('Recycle Bin'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              minTileHeight: 42,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline, size: 18, color: Colors.deepOrange),
              ),
              title: const Text('Recycle Bin', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text('$_trashCount items in trash', style: const TextStyle(fontSize: 10)),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashPage()),
                ).then((_) => _loadData());
              },
            ),
          ),

          const SizedBox(height: 12),

          // 2. LAN HTTP Sharing Card
          _buildSectionHeader('LAN HTTP Web Sharing'),
          Card(
            elevation: _serverRunning ? 2 : 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: _serverRunning ? Colors.green : Theme.of(context).dividerColor.withValues(alpha: 0.15),
                width: _serverRunning ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
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
                              const Text('Web Sharing Server', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              Text(
                                _serverRunning ? '🟢 Running on LAN' : '⚪ Stopped',
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
                    Text(
                      'Access files from any browser on the same Wi-Fi:',
                      style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
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
                              tooltip: 'Copy URL',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: url));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('URL copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(
                      'Share files on your local network without cables. Stream media, download or upload through any web browser.',
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_shared, size: 18, color: Colors.blue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Shared Folder', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                Text(
                                  _shareRoot,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
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
                            child: const Text('Change', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _portCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 11.5),
                            decoration: const InputDecoration(
                              labelText: 'Port',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                              labelText: 'Password (Optional)',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePwd ? Icons.visibility_off : Icons.visibility, size: 15),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
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
                      title: const Text('Read Only (disallow web uploads)', style: TextStyle(fontSize: 11)),
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
          _buildSectionHeader('Storage & Cache'),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
              minTileHeight: 40,
              leading: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cleaning_services, size: 18, color: Colors.teal),
              ),
              title: const Text('Export & Preview Cache', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Temporary files cached when opening with external apps (${_formatSize(_cacheSizeBytes)})',
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
                      child: const Text('Clear', style: TextStyle(fontSize: 11)),
                    ),
            ),
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
