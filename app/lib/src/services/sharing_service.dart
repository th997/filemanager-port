import '../rust/api/servers.dart' as srv_api;

class SharingService {
  static final SharingService instance = SharingService._();
  SharingService._();

  srv_api.ServerStatusDto? _currentStatus;
  srv_api.ServerStatusDto? get currentStatus => _currentStatus;

  bool get isRunning => _currentStatus?.running ?? false;

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
    _currentStatus = status;
    return status;
  }

  bool stopHttp() {
    final ok = srv_api.stopLanHttpServer();
    if (ok) {
      _currentStatus = null;
    }
    return ok;
  }

  List<String> getLocalIps() {
    return srv_api.getLanIpList();
  }
}
