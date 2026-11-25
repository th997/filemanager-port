import 'dart:async';
import 'dart:io';

import '../rust/api/servers.dart' as srv_api;
import 'background_keepalive_service.dart';
import 'path_utils.dart';
import 'preferences_service.dart';

class SharingService {
  static final SharingService instance = SharingService._();
  SharingService._();

  srv_api.ServerStatusDto? _webDavStatus;
  srv_api.ServerStatusDto? get webDavStatus => _webDavStatus;
  bool get isWebDavRunning => _webDavStatus?.running ?? false;
  String? _webDavRoot;
  String? get webDavRoot => _webDavRoot;
  String _webDavRelPath = '';
  String get webDavRelPath => _webDavRelPath;
  bool _webDavReadOnly = true;
  bool get webDavReadOnly => _webDavReadOnly;
  String? _webDavUsername;
  String? get webDavUsername => _webDavUsername;
  String? _webDavPassword;
  String? get webDavPassword => _webDavPassword;

  static bool _isRfc1918(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  static bool _isCgnat(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    return a == 100 && (b & 0xC0) == 64;
  }

  /// Discovers active LAN IPv4 addresses, strictly prioritizing physical
  /// Wi-Fi and Ethernet interfaces while filtering out Docker bridges,
  /// virtual hypervisor NICs and TUN/VPN proxies (such as Clash Meta 198.18.x.x).
  static Future<List<String>> getAccurateLanIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      final physicalPrivate = <String>[];
      final physicalOther = <String>[];
      final physicalCgnat = <String>[];
      final secondary = <String>[];

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        // Virtual / tunnel / container interfaces to deprioritize
        final isVirtual = name.startsWith('lo') ||
            name.startsWith('utun') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('wg') ||
            name.startsWith('awdl') ||
            name.startsWith('llw') ||
            name.startsWith('anpi') ||
            name.startsWith('bridge') ||
            name.startsWith('gif') ||
            name.startsWith('stf') ||
            name == 'ap1' ||
            name.startsWith('docker') ||
            name.startsWith('br-') ||
            name.startsWith('veth') ||
            name.startsWith('virbr') ||
            name.startsWith('meta') ||
            name.startsWith('tailscale') ||
            name.startsWith('zt') ||
            name.startsWith('pdp_ip') ||
            name.startsWith('rmnet') ||
            name.startsWith('ccmni') ||
            name.startsWith('wwan') ||
            name.startsWith('cell') ||
            name.contains('virtual') ||
            name.contains('vmware') ||
            name.contains('vbox') ||
            name.contains('hyper-v');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Filter out loopback, link-local, unspecified, and benchmark/fake-ip ranges
          if (ip == '0.0.0.0' ||
              ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip.startsWith('198.18.') ||
              ip.startsWith('198.19.')) {
            continue;
          }
          if (isVirtual) {
            secondary.add(ip);
          } else if (_isRfc1918(ip)) {
            physicalPrivate.add(ip);
          } else if (_isCgnat(ip)) {
            physicalCgnat.add(ip);
          } else {
            physicalOther.add(ip);
          }
        }
      }

      final combined = <String>[
        ...physicalPrivate,
        ...physicalOther,
        ...physicalCgnat,
      ];
      if (combined.isNotEmpty) {
        return combined;
      }
      if (secondary.isNotEmpty) {
        return secondary;
      }
    } catch (_) {}
    try {
      final rustIps = srv_api
          .getLanIpList()
          .where((ip) => ip != '127.0.0.1' && !ip.startsWith('198.18.') && !ip.startsWith('198.19.'))
          .toList();
      if (rustIps.isNotEmpty) return rustIps;
    } catch (_) {}
    return [];
  }

  Future<srv_api.ServerStatusDto> startWebDav({
    required String root,
    String relPath = '',
    int? port,
    String? username,
    String? password,
    bool readOnly = true,
    String? defaultLang,
  }) async {
    final cleanUsername =
        (username != null && username.trim().isNotEmpty) ? username.trim() : null;
    final cleanPassword =
        (password != null && password.trim().isNotEmpty) ? password.trim() : null;
    final savedLang = defaultLang ?? PreferencesService.instance.getString('app.language');
    final effectiveLang = (savedLang == null || savedLang == 'system') ? null : savedLang;
    final status = await srv_api.startLanWebdavServer(
      root: root,
      relPath: relPath,
      port: port,
      username: cleanUsername,
      password: cleanPassword,
      readOnly: readOnly,
      defaultLang: effectiveLang,
    );

    final accurateIps = await getAccurateLanIps();
    final effectiveAddresses =
        accurateIps.isNotEmpty ? accurateIps : status.addresses;
    final primaryIp =
        effectiveAddresses.isNotEmpty ? effectiveAddresses.first : '127.0.0.1';
    final effectiveUrl = 'http://$primaryIp:${status.port}/';

    final effectiveStatus = srv_api.ServerStatusDto(
      running: status.running,
      port: status.port,
      addresses: effectiveAddresses,
      url: effectiveUrl,
    );

    _webDavStatus = effectiveStatus;
    _webDavRoot = root;
    _webDavRelPath = relPath;
    _webDavReadOnly = readOnly;
    _webDavUsername = cleanUsername;
    _webDavPassword = cleanPassword;
    unawaited(
      BackgroundKeepAliveService.instance.acquire(
        'lan_webdav_share',
        title: 'LAN WebDAV Server Active',
        detail: 'Serving over WebDAV',
      ),
    );
    return effectiveStatus;
  }

  bool stopWebDav() {
    final ok = srv_api.stopLanWebdavServer();
    if (ok) {
      _webDavStatus = null;
      _webDavRoot = null;
      _webDavRelPath = '';
      _webDavUsername = null;
      _webDavPassword = null;
      unawaited(
        BackgroundKeepAliveService.instance.release('lan_webdav_share'),
      );
    }
    return ok;
  }

  /// Stops any active LAN WebDAV shares backed by the locked or deleted
  /// privacy folder [vaultId] (or all vault-backed shares when [vaultId] is null).
  void stopSharesForVault(String? vaultId, {String? vaultDirPath}) {
    final webdavRoot = _webDavRoot;
    if (webdavRoot != null) {
      final davVault = vaultIdFromRoot(webdavRoot);
      if (davVault != null && (vaultId == null || davVault == vaultId)) {
        stopWebDav();
      }
    }
  }

  Future<List<String>> getLocalIps() async {
    final accurate = await getAccurateLanIps();
    if (accurate.isNotEmpty) return accurate;
    return srv_api.getLanIpList();
  }
}
