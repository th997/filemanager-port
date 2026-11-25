import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:filemanager/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../dialogs/folder_picker_dialog.dart';
import '../rust/api/servers.dart' as srv_api;
import '../services/background_keepalive_service.dart';
import '../services/path_utils.dart';
import '../services/platform_paths.dart';
import '../services/semantic_colors.dart';
import '../services/sharing_service.dart';
import '../services/vault_service.dart';
import '../theme/app_ui_tokens.dart';
import '../widgets/qr_code_widget.dart';
import 'browser_page.dart';

class PeerTransferPage extends StatefulWidget {
  final String? initialSrcRoot;
  final List<String> initialSrcPaths;

  const PeerTransferPage({
    super.key,
    this.initialSrcRoot,
    this.initialSrcPaths = const [],
  });

  /// Extracts a `<a.b.c>.x` placeholder from the first usable local IPv4 address.
  static String? subnetHostPlaceholder(List<String> lanIps) {
    for (final raw in lanIps) {
      final parts = raw.trim().split('.');
      if (parts.length != 4) continue;
      final octets = <int>[];
      var valid = true;
      for (final part in parts) {
        final v = int.tryParse(part);
        if (v == null || v < 0 || v > 255) {
          valid = false;
          break;
        }
        octets.add(v);
      }
      if (!valid) continue;
      final a = octets[0];
      final b = octets[1];
      if (a == 0 || a == 127) continue;
      if (a == 169 && b == 254) continue;
      if (a == 198 && (b == 18 || b == 19)) continue;
      return '$a.$b.${octets[2]}.x';
    }
    return null;
  }

  @override
  State<PeerTransferPage> createState() => _PeerTransferPageState();
}

class _PeerTransferPageState extends State<PeerTransferPage> {
  static String? _activeDeviceName;
  static String? _activeSaveDir;

  final TextEditingController _deviceNameCtrl = TextEditingController();
  final TextEditingController _manualUrlCtrl = TextEditingController();
  late String _saveDir;

  bool _receiverRunning = false;
  srv_api.ServerStatusDto? _receiverStatus;
  bool _togglingReceiver = false;

  bool _scanning = false;
  List<srv_api.PeerInfoDto> _peers = const [];
  String? _selectedPeerUrl;
  List<String> _localLanIps = const [];

  List<srv_api.PeerOfferDto> _offers = const [];
  Timer? _pollTimer;
  bool _sending = false;
  late String? _pendingRoot;
  late List<String> _pendingPaths;

  // WebDAV Share + Browser Upload/Download
  bool _webdavRunning = false;
  srv_api.ServerStatusDto? _webdavStatus;
  bool _startingWebdav = false;
  int _webdavNicIndex = 0;
  late String _webdavRoot;
  String _webdavRelPath = '';
  final TextEditingController _webdavPortCtrl =
      TextEditingController(text: '8081');
  final TextEditingController _webdavUserCtrl = TextEditingController();
  final TextEditingController _webdavPwdCtrl = TextEditingController();
  bool _webdavReadOnly = true;
  bool _obscureWebdavPwd = true;

  @override
  void initState() {
    super.initState();
    _deviceNameCtrl.text = Platform.localHostname.isNotEmpty
        ? Platform.localHostname
        : 'FP Device';
    _saveDir = PlatformPaths.defaultRoot();
    _pendingRoot = widget.initialSrcRoot;
    _pendingPaths = List<String>.from(widget.initialSrcPaths);

    try {
      final status = srv_api.peerReceiverStatus();
      if (status != null && status.running) {
        _receiverRunning = true;
        _receiverStatus = status;
        if (_activeDeviceName != null) {
          _deviceNameCtrl.text = _activeDeviceName!;
        }
        if (_activeSaveDir != null) {
          _saveDir = _activeSaveDir!;
        }
        try {
          _offers = srv_api.pollPeerOffers();
        } catch (_) {}
        _startPolling();
        unawaited(_refreshReceiverIps(status));
      }
    } catch (_) {}

    final sharing = SharingService.instance;
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
    if (_webdavRunning && _webdavStatus != null) {
      _webdavPortCtrl.text = '${_webdavStatus!.port}';
    }

    unawaited(_refreshLocalLanIps());
    _scanPeers();
  }

  Future<void> _refreshLocalLanIps() async {
    try {
      final ips = await SharingService.getAccurateLanIps();
      if (!mounted) return;
      setState(() => _localLanIps = ips);
    } catch (_) {}
  }

  String _dynamicManualAddressHint(AppLocalizations l10n) {
    final ips = _localLanIps.isNotEmpty
        ? _localLanIps
        : (_receiverStatus?.addresses ??
            _webdavStatus?.addresses ??
            const <String>[]);
    final subnetPlaceholder = PeerTransferPage.subnetHostPlaceholder(ips);
    return subnetPlaceholder != null
        ? l10n.peerManualAddressExample(subnetPlaceholder)
        : l10n.peerManualAddressHint;
  }

  Future<void> _refreshReceiverIps(srv_api.ServerStatusDto status) async {
    final ips = await SharingService.getAccurateLanIps();
    if (!mounted || !_receiverRunning) return;
    final effectiveIps = ips.isNotEmpty ? ips : status.addresses;
    final primaryIp =
        effectiveIps.isNotEmpty ? effectiveIps.first : '127.0.0.1';
    setState(() {
      if (effectiveIps.isNotEmpty) {
        _localLanIps = effectiveIps;
      }
      _receiverStatus = srv_api.ServerStatusDto(
        running: status.running,
        port: status.port,
        addresses: effectiveIps,
        url: 'http://$primaryIp:${status.port}',
      );
    });
  }

  static bool _offersEqual(
    List<srv_api.PeerOfferDto> a,
    List<srv_api.PeerOfferDto> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].offerId != b[i].offerId ||
          a[i].status != b[i].status ||
          a[i].receivedFiles != b[i].receivedFiles ||
          a[i].items.length != b[i].items.length) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _deviceNameCtrl.dispose();
    _manualUrlCtrl.dispose();
    _webdavPortCtrl.dispose();
    _webdavUserCtrl.dispose();
    _webdavPwdCtrl.dispose();
    super.dispose();
  }

  void _pollOffersOnce() {
    if (!mounted || !_receiverRunning) return;
    try {
      final list = srv_api.pollPeerOffers();
      if (!_offersEqual(_offers, list)) {
        setState(() => _offers = list);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _pollOffersOnce();
    });
  }

  Future<void> _toggleReceiver(bool start) async {
    if (_togglingReceiver) return;
    final l10n = AppLocalizations.of(context);
    if (start && !isNativeRoot(_saveDir)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.peerReceiveFolderMustBeLocal),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    setState(() => _togglingReceiver = true);
    try {
      if (start) {
        final name = _deviceNameCtrl.text.trim().isEmpty
            ? 'FP Device'
            : _deviceNameCtrl.text.trim();
        final status = await srv_api.startPeerReceiver(
          deviceName: name,
          saveDir: _saveDir,
        );
        _activeDeviceName = name;
        _activeSaveDir = _saveDir;
        final ips = await SharingService.getAccurateLanIps();
        final effectiveIps = ips.isNotEmpty ? ips : status.addresses;
        final primaryIp =
            effectiveIps.isNotEmpty ? effectiveIps.first : '127.0.0.1';
        final enriched = srv_api.ServerStatusDto(
          running: status.running,
          port: status.port,
          addresses: effectiveIps,
          url: 'http://$primaryIp:${status.port}',
        );
        unawaited(
          BackgroundKeepAliveService.instance.acquire(
            'lan_peer_receiver',
            title: 'LAN Direct Drop Ready',
            detail: 'Receiving files as $name',
          ),
        );
        if (!mounted) return;
        setState(() {
          if (effectiveIps.isNotEmpty) {
            _localLanIps = effectiveIps;
          }
          _receiverRunning = true;
          _receiverStatus = enriched;
          _togglingReceiver = false;
        });
        _pollOffersOnce();
        _startPolling();
      } else {
        srv_api.stopPeerReceiver();
        _activeDeviceName = null;
        _activeSaveDir = null;
        _pollTimer?.cancel();
        unawaited(
          BackgroundKeepAliveService.instance.release('lan_peer_receiver'),
        );
        if (!mounted) return;
        setState(() {
          _receiverRunning = false;
          _receiverStatus = null;
          _offers = const [];
          _togglingReceiver = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _togglingReceiver = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pickSaveDir() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.chooseSharedFolder,
      initialRoot: _saveDir,
    );
    if (picked != null && mounted) {
      if (!isNativeRoot(picked.root)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.peerReceiveFolderMustBeLocal),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      setState(() => _saveDir = joinNative(picked.root, picked.relPath));
    }
  }

  Future<void> _scanPeers() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    unawaited(_refreshLocalLanIps());
    try {
      final found = await srv_api.discoverLanPeers(timeoutMs: 2500);
      if (!mounted) return;
      setState(() {
        _peers = found;
        _scanning = false;
        if (_selectedPeerUrl == null && found.isNotEmpty) {
          _selectedPeerUrl = found.first.url;
          _manualUrlCtrl.text = found.first.url;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
    }
  }

  String _activeTargetUrl() {
    final manual = _manualUrlCtrl.text.trim();
    if (manual.isNotEmpty) return manual;
    return _selectedPeerUrl ?? '';
  }

  Future<void> _sendFiles() async {
    final l10n = AppLocalizations.of(context);
    final targetUrl = _activeTargetUrl();
    if (targetUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.peerNoDevicesFound)),
      );
      return;
    }

    final Map<String, List<String>> batches = {};
    if (_pendingRoot != null && _pendingPaths.isNotEmpty) {
      batches[_pendingRoot!] = List<String>.from(_pendingPaths);
    } else {
      final picked = await openFiles();
      if (picked.isEmpty) return;
      for (final f in picked) {
        final dir = p.dirname(f.path);
        final base = p.basename(f.path);
        batches.putIfAbsent(dir, () => <String>[]).add(base);
      }
    }

    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final senderName = _deviceNameCtrl.text.trim().isEmpty
          ? 'FP Device'
          : _deviceNameCtrl.text.trim();
      var count = 0;
      for (final entry in batches.entries) {
        count += await srv_api.sendPeerFiles(
          peerUrl: targetUrl,
          senderName: senderName,
          srcRoot: entry.key,
          srcPaths: entry.value,
        );
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _pendingRoot = null;
        _pendingPaths = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.peerSentSuccess(count))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _sendClipboardText() async {
    final l10n = AppLocalizations.of(context);
    final targetUrl = _activeTargetUrl();
    if (targetUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.peerNoDevicesFound)),
      );
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.peerSendClipboard}: ${l10n.folderIsEmpty}'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final senderName = _deviceNameCtrl.text.trim().isEmpty
          ? 'FP Device'
          : _deviceNameCtrl.text.trim();
      await srv_api.sendPeerText(
        peerUrl: targetUrl,
        senderName: senderName,
        text: text,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.peerOfferSent)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _respondOffer(srv_api.PeerOfferDto offer, bool accept) {
    srv_api.respondPeerOffer(
      offerId: offer.offerId,
      accept: accept,
      saveDir: accept ? _saveDir : null,
    );
    if (accept &&
        offer.kind == 'text' &&
        (offer.textPayload?.isNotEmpty ?? false)) {
      Clipboard.setData(ClipboardData(text: offer.textPayload!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).pathCopied)),
      );
    }
    setState(() {
      _offers = srv_api.pollPeerOffers();
    });
  }

  bool _isSameOrSubdir(String candidate, String base) {
    String normalize(String raw) {
      var s = raw.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
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

  String _friendlyPath(String path) {
    if (Platform.isIOS && path.contains('/Containers/Data/Application/')) {
      final docIdx = path.indexOf('/Documents');
      if (docIdx != -1) {
        final sub = path.substring(docIdx);
        return sub == '/Documents'
            ? AppLocalizations.of(context).documentsDir
            : '${AppLocalizations.of(context).documentsDir}${sub.substring('/Documents'.length)}';
      }
      return AppLocalizations.of(context).documentsDir;
    }
    return path;
  }

  String get _webdavDisplayPath => _webdavRelPath.isEmpty
      ? _friendlyPath(_webdavRoot)
      : '${_friendlyPath(_webdavRoot)}/$_webdavRelPath';

  Future<void> _pickWebDavFolder() async {
    final l10n = AppLocalizations.of(context);
    final picked = await FolderPickerDialog.show(
      context,
      title: l10n.chooseSharedFolder,
      initialRoot: _webdavRoot,
      initialPath: _webdavRelPath,
      includeRemotes: true,
      includePools: true,
    );
    if (picked != null && mounted) {
      if (_isForbiddenShareRoot(picked.root)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToStartServer(l10n.privacyFolder)),
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
          _webdavNicIndex = 0;
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

  void _showQrDialog(String url) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
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
                border: Border.all(
                  color: Theme.of(ctx).dividerColor.withValues(alpha: 0.25),
                ),
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

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

  Widget _buildWebDavShareCard(AppLocalizations l10n, ColorScheme scheme) {
    final successColor = scheme.success;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: _webdavRunning
            ? BorderSide(color: successColor, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  size: 22,
                  color: _webdavRunning ? successColor : scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.lanWebdavShareTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        _webdavRunning
                            ? l10n.runningOnLan
                            : l10n.lanWebdavShareSubtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _webdavRunning ? successColor : scheme.outline,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                    : Switch(
                        value: _webdavRunning,
                        onChanged: _toggleWebDavServer,
                      ),
              ],
            ),
            if (_webdavRunning && _webdavStatus != null) ...[
              const Divider(height: 14),
              Text(
                '${l10n.shared}: $_webdavDisplayPath${_webdavReadOnly ? l10n.readOnly : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.lanWebdavBrowserHint,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_webdavStatus!.addresses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l10n.noLanIpFound,
                    style: TextStyle(fontSize: 11, color: scheme.warning),
                  ),
                )
              else ...[
                Builder(
                  builder: (ctx) {
                    final addrs = _webdavStatus!.addresses;
                    final idx = _webdavNicIndex.clamp(0, addrs.length - 1);
                    final activeIp = addrs[idx];
                    final activeUrl = 'http://$activeIp:${_webdavStatus!.port}/';
                    return Column(
                      children: [
                        if (addrs.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Wrap(
                              spacing: 6,
                              children: [
                                for (var i = 0; i < addrs.length; i++)
                                  ChoiceChip(
                                    label: Text(
                                      addrs[i],
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    selected: i == idx,
                                    onSelected: (_) =>
                                        setState(() => _webdavNicIndex = i),
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
                                color: Theme.of(ctx)
                                    .dividerColor
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: QrCodeWidget(data: activeUrl, size: 150),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                for (final ip in _webdavStatus!.addresses)
                  Builder(
                    builder: (ctx) {
                      final davUrl = 'http://$ip:${_webdavStatus!.port}/';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: successColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: successColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                davUrl,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: successColor,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_2, size: 18),
                              tooltip: l10n.showQrCode,
                              onPressed: () => _showQrDialog(davUrl),
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
              Text(
                l10n.lanWebdavBrowserHint,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.folder_shared, size: 20),
                title: Text(
                  _webdavDisplayPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: _webdavRunning ? null : _pickWebDavFolder,
                  child: Text(l10n.change),
                ),
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final portField = TextField(
                    controller: _webdavPortCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: l10n.port,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  );
                  final userField = TextField(
                    controller: _webdavUserCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: l10n.webdavUsernameOptional,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  );
                  final pwdField = TextField(
                    controller: _webdavPwdCtrl,
                    obscureText: _obscureWebdavPwd,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: l10n.passwordFieldLabel,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureWebdavPwd
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 16,
                        ),
                        onPressed: () => setState(
                          () => _obscureWebdavPwd = !_obscureWebdavPwd,
                        ),
                      ),
                    ),
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        portField,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: userField),
                            const SizedBox(width: 8),
                            Expanded(child: pwdField),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 88, child: portField),
                      const SizedBox(width: 8),
                      Expanded(child: userField),
                      const SizedBox(width: 8),
                      Expanded(child: pwdField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                title: Text(
                  l10n.readOnlyMode,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  l10n.lanWebdavReadOnlyHint,
                  style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                ),
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
    );
  }

  String _localizedOfferStatus(AppLocalizations l10n, String status) {
    return switch (status) {
      'accepted' => l10n.peerOfferStatusAccepted,
      'completed' => l10n.peerOfferStatusCompleted,
      'rejected' => l10n.peerOfferStatusRejected,
      'receiving' => l10n.peerOfferStatusReceiving,
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: AppSwipeBack(
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.lanTransferAndShareTitle),
            bottom: TabBar(
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: [
                Tab(
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  child: Text(
                    l10n.peerTabDirectTransfer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tab(
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  child: Text(
                    l10n.peerTabWebdavShare,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader(context, l10n.lanPeerTransferTitle),
                  if (_pendingPaths.isNotEmpty)
                    Card(
                      color: scheme.primaryContainer.withValues(alpha: 0.4),
                      child: ListTile(
                        leading: Icon(Icons.attach_file, color: scheme.primary),
                        title: Text(
                          l10n.peerPendingItemsToSend(_pendingPaths.length),
                        ),
                        subtitle: Text(
                          _pendingPaths.join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: l10n.cancel,
                          onPressed: _sending
                              ? null
                              : () => setState(() {
                                    _pendingRoot = null;
                                    _pendingPaths = const [];
                                  }),
                        ),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.peerReceiveMode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _receiverRunning,
                                onChanged:
                                    _togglingReceiver ? null : _toggleReceiver,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _deviceNameCtrl,
                            enabled: !_receiverRunning,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: l10n.peerDeviceName,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.folder_outlined, size: 20),
                            title: Text(
                              _friendlyPath(_saveDir),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: _receiverRunning ? null : _pickSaveDir,
                              child: Text(l10n.change),
                            ),
                          ),
                          if (_receiverRunning && _receiverStatus != null) ...[
                            const SizedBox(height: 4),
                            for (final ip in (_receiverStatus!.addresses.isNotEmpty
                                ? _receiverStatus!.addresses
                                : ['127.0.0.1']))
                              SelectableText(
                                'http://$ip:${_receiverStatus!.port}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_offers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final offer in _offers)
                      Card(
                        color: scheme.secondaryContainer.withValues(alpha: 0.5),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.peerIncomingOfferTitle(offer.senderName),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                offer.textPreview ?? offer.items.join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              if (offer.status == 'pending')
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => _respondOffer(offer, false),
                                      child: Text(l10n.peerReject),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: () => _respondOffer(offer, true),
                                      child: Text(l10n.peerAccept),
                                    ),
                                  ],
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      (offer.kind == 'text' || offer.items.isEmpty)
                                          ? _localizedOfferStatus(l10n, offer.status)
                                          : '${_localizedOfferStatus(l10n, offer.status)} (${offer.receivedFiles}/${offer.items.length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (offer.kind == 'text' &&
                                        (offer.textPayload?.isNotEmpty ?? false) &&
                                        offer.status != 'rejected')
                                      TextButton.icon(
                                        icon: const Icon(Icons.copy, size: 15),
                                        label: Text(l10n.peerCopyReceivedText),
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: offer.textPayload!),
                                          );
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(l10n.peerTextCopied),
                                            ),
                                          );
                                        },
                                      ),
                                    if (offer.kind != 'text' &&
                                        offer.status == 'completed')
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.folder_open,
                                          size: 15,
                                        ),
                                        label: Text(l10n.peerOpenReceivedFolder),
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => BrowserPage(
                                                initialRoot: _saveDir,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  l10n.peerScanDevices,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _scanning ? null : _scanPeers,
                                  icon: _scanning
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.radar, size: 18),
                                  label: Text(
                                    _scanning
                                        ? l10n.peerScanning
                                        : l10n.peerScanDevices,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_peers.isEmpty && !_scanning)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                l10n.peerNoDevicesFound,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            for (final peer in _peers)
                              Builder(
                                builder: (context) {
                                  final selected = _selectedPeerUrl == peer.url;
                                  return ListTile(
                                    dense: true,
                                    selected: selected,
                                    leading: Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked,
                                      color: selected ? scheme.primary : null,
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedPeerUrl = peer.url;
                                        _manualUrlCtrl.text = peer.url;
                                      });
                                    },
                                    title: Text(
                                      '${peer.deviceName} (${peer.platform})',
                                    ),
                                    subtitle: Text(peer.url),
                                  );
                                },
                              ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _manualUrlCtrl,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: l10n.peerManualAddressLabel,
                              hintText: _dynamicManualAddressHint(l10n),
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_sending) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              l10n.peerWaitingForAccept,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: _sending ? null : _sendFiles,
                                icon: _sending
                                    ? SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: scheme.onPrimary,
                                        ),
                                      )
                                    : const Icon(Icons.send_outlined, size: 18),
                                label: Text(l10n.peerSendFiles),
                              ),
                              OutlinedButton.icon(
                                onPressed: _sending ? null : _sendClipboardText,
                                icon: _sending
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.content_paste_go,
                                        size: 18,
                                      ),
                                label: Text(l10n.peerSendClipboard),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader(context, l10n.lanWebdavShareTitle),
                  _buildWebDavShareCard(l10n, scheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
