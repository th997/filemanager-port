import 'dart:io';

import '../rust/api/servers.dart' as srv_api;

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
  }) async {
    final status = await srv_api.startLanHttpServer(
      rootDir: rootDir,
      port: port,
      password: password,
      readOnly: readOnly,
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
    return effectiveStatus;
  }

  bool stopHttp() {
    final ok = srv_api.stopLanHttpServer();
    if (ok) {
      _currentStatus = null;
      _rootDir = null;
      _password = null;
    }
    return ok;
  }

  Future<List<String>> getLocalIps() async {
    final accurate = await getAccurateLanIps();
    if (accurate.isNotEmpty) return accurate;
    return srv_api.getLanIpList();
  }
}
