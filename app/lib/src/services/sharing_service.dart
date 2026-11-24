import 'dart:async';
import 'dart:io';

import '../rust/api/servers.dart' as srv_api;
import 'background_keepalive_service.dart';
import 'path_utils.dart';
import 'preferences_service.dart';

class SharingService {
  static final SharingService instance = SharingService._();
  SharingService._();

  srv_api.ServerStatusDto? _currentStatus;
  srv_api.ServerStatusDto? get currentStatus => _currentStatus;

  bool get isRunning => _currentStatus?.running ?? false;

  // The status DTO carries no share configuration, but the utilities page
  // needs it back when it is re-entered while the server is running.
  String? _rootDir;
  String? get rootDir => _rootDir;
  bool _readOnly = true;
  bool get readOnly => _readOnly;
  String? _password;
  String? get password => _password;

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
      final prioritized = <String>[];
      final secondary = <String>[];

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        // Virtual / tunnel / container interfaces to deprioritize
        final isVirtual = name.startsWith('docker') ||
            name.startsWith('br-') ||
            name.startsWith('veth') ||
            name.startsWith('virbr') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('wg') ||
            name.startsWith('meta') ||
            name.contains('virtual') ||
            name.contains('vmware') ||
            name.contains('vbox') ||
            name.contains('hyper-v');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          // Filter out loopback, link-local, and benchmark/fake-ip ranges
          if (ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip.startsWith('198.18.') ||
              ip.startsWith('198.19.')) {
            continue;
          }
          if (isVirtual) {
            secondary.add(ip);
          } else {
            prioritized.add(ip);
          }
        }
      }

      if (prioritized.isNotEmpty) {
        return prioritized;
      }
      if (secondary.isNotEmpty) {
        return secondary;
      }
    } catch (_) {}
    return [];
  }

  Future<srv_api.ServerStatusDto> startHttp({
    required String rootDir,
    int? port,
    String? password,
    bool readOnly = true,
    String? defaultLang,
  }) async {
    final savedLang = defaultLang ?? PreferencesService.instance.getString('app.language');
    final effectiveLang = (savedLang == null || savedLang == 'system') ? null : savedLang;
    final status = await srv_api.startLanHttpServerWithLang(
      rootDir: rootDir,
      port: port,
      password: password,
      readOnly: readOnly,
      defaultLang: effectiveLang,
    );

    // Enrich and prioritize with true physical LAN IPs detected across OS interfaces
    final accurateIps = await getAccurateLanIps();
    final effectiveAddresses = accurateIps.isNotEmpty ? accurateIps : status.addresses;
    final primaryIp = effectiveAddresses.isNotEmpty ? effectiveAddresses.first : '127.0.0.1';
    final query = Uri.tryParse(status.url)?.query ?? '';
    final effectiveUrl = 'http://$primaryIp:${status.port}${query.isEmpty ? '' : '?$query'}';

    final effectiveStatus = srv_api.ServerStatusDto(
      running: status.running,
      port: status.port,
      addresses: effectiveAddresses,
      url: effectiveUrl,
    );

    _currentStatus = effectiveStatus;
    _rootDir = rootDir;
    _readOnly = readOnly;
    _password = password;
    unawaited(
      BackgroundKeepAliveService.instance.acquire(
        'lan_http_share',
        title: 'LAN HTTP Share Active',
        detail: 'Serving over LAN',
      ),
    );
    return effectiveStatus;
  }

  bool stopHttp() {
    final ok = srv_api.stopLanHttpServer();
    if (ok) {
    _currentStatus = null;
      _rootDir = null;
      _password = null;
      unawaited(BackgroundKeepAliveService.instance.release('lan_http_share'));
    }
    return ok;
  }

  Future<srv_api.ServerStatusDto> startWebDav({
    required String root,
    String relPath = '',
    int? port,
    String? username,
    String? password,
    bool readOnly = true,
  }) async {
    final cleanUsername =
        (username != null && username.trim().isNotEmpty) ? username.trim() : null;
    final cleanPassword =
        (password != null && password.trim().isNotEmpty) ? password.trim() : null;
    final status = await srv_api.startLanWebdavServer(
      root: root,
      relPath: relPath,
      port: port,
      username: cleanUsername,
      password: cleanPassword,
      readOnly: readOnly,
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

  /// Stops any active LAN HTTP / WebDAV shares backed by the locked or deleted
  /// privacy folder [vaultId] (or all vault-backed shares when [vaultId] is null).
  void stopSharesForVault(String? vaultId, {String? vaultDirPath}) {
    final webdavRoot = _webDavRoot;
    if (webdavRoot != null) {
      final davVault = vaultIdFromRoot(webdavRoot);
      if (davVault != null && (vaultId == null || davVault == vaultId)) {
        stopWebDav();
      }
    }

    final httpRoot = _rootDir;
    if (httpRoot != null) {
      final normHttp = httpRoot.replaceAll('\\', '/');
      final normVaultDir = vaultDirPath?.replaceAll('\\', '/');
      final matchesVaultDir = normVaultDir != null &&
          normVaultDir.isNotEmpty &&
          (normHttp == normVaultDir || normHttp.startsWith('$normVaultDir/'));
      final matchesExportDir = vaultId == null
          ? normHttp.contains('/open-with/vault_')
          : (normHttp.endsWith('/open-with/vault_$vaultId') ||
              normHttp.contains('/open-with/vault_$vaultId/'));
      if (matchesVaultDir || matchesExportDir) {
        stopHttp();
      }
    }
  }

  Future<List<String>> getLocalIps() async {
    final accurate = await getAccurateLanIps();
    if (accurate.isNotEmpty) return accurate;
    return srv_api.getLanIpList();
  }
}
