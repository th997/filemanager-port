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
import '../services/sharing_service.dart';
import '../theme/app_ui_tokens.dart';

class PeerTransferPage extends StatefulWidget {
  final String? initialSrcRoot;
  final List<String> initialSrcPaths;

  const PeerTransferPage({
    super.key,
    this.initialSrcRoot,
    this.initialSrcPaths = const [],
  });

  @override
  State<PeerTransferPage> createState() => _PeerTransferPageState();
}

class _PeerTransferPageState extends State<PeerTransferPage> {
  final TextEditingController _deviceNameCtrl = TextEditingController();
  final TextEditingController _manualUrlCtrl = TextEditingController();
  late String _saveDir;

  bool _receiverRunning = false;
  srv_api.ServerStatusDto? _receiverStatus;
  bool _togglingReceiver = false;

  bool _scanning = false;
  List<srv_api.PeerInfoDto> _peers = const [];
  String? _selectedPeerUrl;

  List<srv_api.PeerOfferDto> _offers = const [];
  Timer? _pollTimer;
  bool _sending = false;
  late String? _pendingRoot;
  late List<String> _pendingPaths;

  @override
  void initState() {
    super.initState();
    _deviceNameCtrl.text = Platform.localHostname.isNotEmpty
        ? Platform.localHostname
        : 'FP Device';
    _saveDir = PlatformPaths.defaultRoot();
    _pendingRoot = widget.initialSrcRoot;
    _pendingPaths = List<String>.from(widget.initialSrcPaths);

    final status = srv_api.peerReceiverStatus();
    if (status != null && status.running) {
      _receiverRunning = true;
      _receiverStatus = status;
      _startPolling();
      unawaited(_refreshReceiverIps(status));
    }
    _scanPeers();
  }

  Future<void> _refreshReceiverIps(srv_api.ServerStatusDto status) async {
    final ips = await SharingService.getAccurateLanIps();
    if (!mounted || !_receiverRunning) return;
    final effectiveIps = ips.isNotEmpty ? ips : status.addresses;
    final primaryIp =
        effectiveIps.isNotEmpty ? effectiveIps.first : '127.0.0.1';
    setState(() {
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
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted || !_receiverRunning) return;
      try {
        final list = srv_api.pollPeerOffers();
        if (!_offersEqual(_offers, list)) {
          setState(() => _offers = list);
        }
      } catch (_) {}
    });
  }

  Future<void> _toggleReceiver(bool start) async {
    if (_togglingReceiver) return;
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
          _receiverRunning = true;
          _receiverStatus = enriched;
          _togglingReceiver = false;
        });
        _startPolling();
      } else {
        srv_api.stopPeerReceiver();
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
            content: Text(l10n.failedToStartServer(l10n.localStorage)),
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
          SnackBar(content: Text('${l10n.peerSendClipboard}: ${l10n.folderIsEmpty}')),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AppSwipeBack(
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.lanPeerTransferTitle),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_pendingPaths.isNotEmpty)
              Card(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                child: ListTile(
                  leading: Icon(Icons.attach_file, color: scheme.primary),
                  title: Text('${_pendingPaths.length} item(s) ready to send'),
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
                          onChanged: _togglingReceiver ? null : _toggleReceiver,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deviceNameCtrl,
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
                      title: Text(_saveDir,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: TextButton(
                        onPressed: _receiverRunning ? null : _pickSaveDir,
                        child: Text(l10n.change),
                      ),
                    ),
                    if (_receiverRunning && _receiverStatus != null)
                      SelectableText(
                        _receiverStatus!.url,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                          Text(
                            '${offer.status} (${offer.receivedFiles}/${offer.items.length})',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.primary,
                            ),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.peerScanDevices,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
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
                              title: Text('${peer.deviceName} (${peer.platform})'),
                              subtitle: Text(peer.url),
                            );
                          },
                        ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualUrlCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: l10n.peerManualAddressHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _sending ? null : _sendFiles,
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: Text(l10n.peerSendFiles),
                        ),
                        OutlinedButton.icon(
                          onPressed: _sending ? null : _sendClipboardText,
                          icon: const Icon(Icons.content_paste_go, size: 18),
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
      ),
    );
  }
}
