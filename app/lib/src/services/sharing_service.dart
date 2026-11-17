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
    _rootDir = rootDir;
    _readOnly = readOnly;
    _password = password;
    return status;
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

  List<String> getLocalIps() {
    return srv_api.getLanIpList();
  }
}
