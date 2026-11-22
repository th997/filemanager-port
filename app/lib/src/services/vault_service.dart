import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../rust/api/vault.dart';
import 'file_open_service.dart';
import 'global_playback_service.dart';
import 'keychain_service.dart';
import 'path_utils.dart';
import 'platform_paths.dart';
import 'preferences_service.dart';

enum PasswordValidationError { none, tooShort, tooLong }

class VaultAuthCancelledException implements Exception {
  final String message;
  const VaultAuthCancelledException([this.message = 'Authentication cancelled']);
  @override
  String toString() => message;
}

class VaultService extends ChangeNotifier {
  static final VaultService instance = VaultService._();
  VaultService._();

  static const MethodChannel _nativeChannel =
      MethodChannel('com.github.th997.filemanager/vault_native');
  static const Duration backgroundAutoLockTimeout = Duration(minutes: 10);

  final LocalAuthentication _localAuth = LocalAuthentication();
  final List<void Function(String? vaultId)> _lockCleanups = [];

  List<UnlockedVaultDto> _unlocked = const [];
  bool _initialized = false;
  bool _authInProgress = false;
  int _externalFlowDepth = 0;
  DateTime? _backgroundedAt;
  Timer? _backgroundLockTimer;
  int _secureScreenRefCount = 0;

  List<UnlockedVaultDto> get unlockedVaults => List.unmodifiable(_unlocked);
  bool get hasUnlockedVaults => _unlocked.isNotEmpty;

  Duration? get autoLockTimeout {
    final sec = PreferencesService.instance.vaultAutoLockTimeoutSec;
    if (sec < 0) return null;
    if (sec == 0) return Duration.zero;
    return Duration(seconds: sec);
  }

  Future<T> runWithAutoLockSuppressed<T>(Future<T> Function() action) async {
    _externalFlowDepth++;
    try {
      return await action();
    } finally {
      if (_externalFlowDepth > 0) {
        _externalFlowDepth--;
      }
    }
  }

  void registerLockCleanup(void Function(String? vaultId) callback) {
    if (!_lockCleanups.contains(callback)) {
      _lockCleanups.add(callback);
    }
  }

  static PasswordValidationError validatePassword(String password) {
    final len = password.runes.length;
    if (len < 8) return PasswordValidationError.tooShort;
    if (len > 128) return PasswordValidationError.tooLong;
    return PasswordValidationError.none;
  }

  static bool shouldAutoLock({
    required DateTime? backgroundedAt,
    required DateTime now,
    Duration timeout = backgroundAutoLockTimeout,
  }) {
    if (backgroundedAt == null) return false;
    return now.difference(backgroundedAt) >= timeout;
  }

  static String? extractAlreadyExistsName(Object error) {
    final text = error.toString().trim();
    const marker = 'privacy folder already exists:';
    final idx = text.indexOf(marker);
    if (idx < 0) return null;
    final prefix = text.substring(0, idx);
    var rest = text.substring(idx + marker.length).trim();
    final nl = rest.indexOf('\n');
    if (nl >= 0) {
      rest = rest.substring(0, nl).trim();
    }
    final wrapperOpen = RegExp(r'[A-Za-z_]\w*\(\s*$').hasMatch(prefix);
    if (wrapperOpen && rest.endsWith(')')) {
      rest = rest.substring(0, rest.length - 1).trim();
    }
    return rest.isEmpty ? null : rest;
  }

  static bool get isSystemAuthPlatform =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  Future<bool> canUseSystemAuth() async {
    if (!isSystemAuthPlatform) return false;
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateSystem(String localizedReason) async {
    if (!isSystemAuthPlatform) return false;
    _authInProgress = true;
    try {
      return await _localAuth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } finally {
      _authInProgress = false;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    vaultInitStore(appDataDir: PlatformPaths.appDataDir());
    vaultLockAll();
    _unlocked = const [];
    unawaited(FileOpenService.instance.clearVaultExports());
  }

  void _refreshUnlocked() {
    try {
      _unlocked = vaultListUnlocked();
    } catch (_) {
      _unlocked = const [];
    }
  }

  bool isUnlocked(String vaultId) => _unlocked.any((v) => v.id == vaultId);

  UnlockedVaultDto? findUnlockedById(String vaultId) {
    for (final v in _unlocked) {
      if (v.id == vaultId) return v;
    }
    return null;
  }

  String _dekKey(String vaultId) => 'vault_dek_$vaultId';

  Future<bool> _saveSystemDek(String vaultId, String dekB64) async {
    final key = _dekKey(vaultId);
    if (Platform.isIOS) {
      return KeychainService.save(key, dekB64, thisDeviceOnly: true);
    }
    if (Platform.isAndroid) {
      final res = await _nativeChannel.invokeMethod<bool>('keystoreSave', {
        'key': key,
        'value': dekB64,
      });
      return res ?? false;
    }
    if (Platform.isMacOS || Platform.isWindows) {
      await vaultDesktopKeystoreSave(key: key, value: dekB64);
      return true;
    }
    return false;
  }

  Future<String?> _readSystemDek(String vaultId) async {
    final key = _dekKey(vaultId);
    if (Platform.isIOS) {
      return KeychainService.read(key);
    }
    if (Platform.isAndroid) {
      return _nativeChannel.invokeMethod<String?>('keystoreRead', {'key': key});
    }
    if (Platform.isMacOS || Platform.isWindows) {
      return vaultDesktopKeystoreRead(key: key);
    }
    return null;
  }

  Future<void> _deleteSystemDek(String vaultId) async {
    final key = _dekKey(vaultId);
    try {
      if (Platform.isIOS) {
        await KeychainService.delete(key);
      } else if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod('keystoreDelete', {'key': key});
      } else if (Platform.isMacOS || Platform.isWindows) {
        await vaultDesktopKeystoreDelete(key: key);
      }
    } catch (_) {}
  }

  Future<void> _excludeFromBackup(String dirPath) async {
    if (!Platform.isIOS) return;
    try {
      await _nativeChannel.invokeMethod('excludeFromBackup', {'path': dirPath});
    } catch (_) {}
  }

  Future<void> pushSecureScreen() async {
    _secureScreenRefCount++;
    if (_secureScreenRefCount == 1) {
      await _applySecureScreen(true);
    }
  }

  Future<void> popSecureScreen() async {
    if (_secureScreenRefCount <= 0) return;
    _secureScreenRefCount--;
    if (_secureScreenRefCount == 0) {
      await _applySecureScreen(false);
    }
  }

  Future<void> _resetSecureScreen() async {
    _secureScreenRefCount = 0;
    await _applySecureScreen(false);
  }

  Future<void> _applySecureScreen(bool enabled) async {
    try {
      if (Platform.isAndroid) {
        await _nativeChannel.invokeMethod('setSecureScreen', {'enabled': enabled});
      } else if (Platform.isIOS) {
        await _nativeChannel.invokeMethod('setPrivacyMask', {'enabled': enabled});
      }
    } catch (_) {}
  }

  Future<VaultLookupDto> lookupVault(String name) async {
    return vaultLookup(name: name);
  }

  Future<UnlockedVaultDto> createVault({
    required String name,
    required String storageRoot,
    required String cipher,
    required String authMode,
    String? password,
    required String systemAuthReason,
  }) async {
    if (authMode == 'system') {
      final supported = await canUseSystemAuth();
      if (!supported) {
        throw StateError('System authentication is not available on this device');
      }
      final authed = await authenticateSystem(systemAuthReason);
      if (!authed) {
        throw const VaultAuthCancelledException();
      }
    }

    final created = await vaultCreate(
      name: name,
      storageRoot: storageRoot,
      cipher: cipher,
      authMode: authMode,
      password: password,
    );

    if (authMode == 'system' && created.systemDekB64 != null) {
      bool saved = false;
      try {
        saved = await _saveSystemDek(created.vault.id, created.systemDekB64!);
      } catch (_) {
        saved = false;
      }
      if (!saved) {
        try {
          await vaultDelete(vaultId: created.vault.id);
        } catch (_) {}
        throw StateError('Could not save system encryption key to secure storage');
      }
    }

    await _excludeFromBackup(created.vault.dirPath);
    _refreshUnlocked();
    notifyListeners();
    return created.vault;
  }

  Future<UnlockedVaultDto> unlockVault({
    required String name,
    required VaultLookupDto lookup,
    String? password,
    required String systemAuthReason,
  }) async {
    if (!lookup.exists || lookup.id == null) {
      throw StateError('Privacy folder does not exist');
    }

    UnlockedVaultDto unlocked;
    if (lookup.authMode == 'system') {
      final supported = await canUseSystemAuth();
      if (!supported) {
        throw StateError('System authentication is not available on this device');
      }
      final authed = await authenticateSystem(systemAuthReason);
      if (!authed) {
        throw const VaultAuthCancelledException();
      }
      String? dek;
      if (lookup.cipher != 'none') {
        dek = await _readSystemDek(lookup.id!);
      }
      unlocked = await vaultUnlockWithSystemKey(name: name, systemDekB64: dek);
    } else {
      unlocked = await vaultUnlockWithPassword(
        name: name,
        password: password ?? '',
      );
    }

    _refreshUnlocked();
    notifyListeners();
    return unlocked;
  }

  void lockVault(String vaultId) {
    final activeRoot = GlobalPlaybackService.instance.currentRoot;
    if (activeRoot != null && vaultIdFromRoot(activeRoot) == vaultId) {
      GlobalPlaybackService.instance.stop();
    }
    vaultLock(vaultId: vaultId);
    for (final cb in _lockCleanups) {
      try {
        cb(vaultId);
      } catch (_) {}
    }
    unawaited(FileOpenService.instance.clearVaultExports(vaultId));
    _refreshUnlocked();
    if (_unlocked.isEmpty) {
      unawaited(_resetSecureScreen());
    }
    notifyListeners();
  }

  void lockAll() {
    _backgroundLockTimer?.cancel();
    _backgroundLockTimer = null;
    _backgroundedAt = null;

    final activeRoot = GlobalPlaybackService.instance.currentRoot;
    if (activeRoot != null && vaultIdFromRoot(activeRoot) != null) {
      GlobalPlaybackService.instance.stop();
    }
    vaultLockAll();
    for (final cb in _lockCleanups) {
      try {
        cb(null);
      } catch (_) {}
    }
    unawaited(FileOpenService.instance.clearVaultExports());
    _unlocked = const [];
    unawaited(_resetSecureScreen());
    notifyListeners();
  }

  void onAppBackgrounded() {
    if (_authInProgress || _externalFlowDepth > 0 || _unlocked.isEmpty) return;
    final timeout = autoLockTimeout;
    if (timeout == null) return;
    if (timeout == Duration.zero) {
      lockAll();
      return;
    }
    _backgroundedAt ??= DateTime.now();
    _backgroundLockTimer?.cancel();
    _backgroundLockTimer = Timer(timeout, () {
      if (_unlocked.isNotEmpty) {
        lockAll();
      }
    });
  }

  void onAppResumed() {
    _backgroundLockTimer?.cancel();
    _backgroundLockTimer = null;
    final bgAt = _backgroundedAt;
    _backgroundedAt = null;
    final timeout = autoLockTimeout;
    if (timeout == null) return;
    if (_unlocked.isNotEmpty &&
        shouldAutoLock(
          backgroundedAt: bgAt,
          now: DateTime.now(),
          timeout: timeout,
        )) {
      lockAll();
    }
  }

  Future<String> startExportBackup({
    required String vaultId,
    String? backupPassword,
    required String destArchivePath,
  }) {
    return vaultStartExportBackup(
      vaultId: vaultId,
      backupPassword: backupPassword,
      destArchivePath: destArchivePath,
    );
  }

  Future<String> startImportBackup({
    required String archivePath,
    String? vaultName,
    required String targetStorageRoot,
    String? backupPassword,
    required String targetAuthMode,
    String? newLocalPassword,
  }) {
    return vaultStartImportBackup(
      archivePath: archivePath,
      vaultName: vaultName,
      targetStorageRoot: targetStorageRoot,
      backupPassword: backupPassword,
      targetAuthMode: targetAuthMode,
      newLocalPassword: newLocalPassword,
    );
  }

  VaultBackupTaskProgressDto? getBackupTaskProgress(String taskId) =>
      vaultBackupTaskProgress(taskId: taskId);

  bool cancelBackupTask(String taskId) =>
      vaultCancelBackupTask(taskId: taskId);

  void removeBackupTask(String taskId) =>
      vaultRemoveBackupTask(taskId: taskId);

  Future<UnlockedVaultDto> finalizeImportedVault(
    VaultImportResultDto res, {
    required String targetAuthMode,
  }) async {
    if (targetAuthMode == 'system' && res.systemDekB64 != null) {
      bool saved = false;
      try {
        saved = await _saveSystemDek(res.vault.id, res.systemDekB64!);
      } catch (_) {
        saved = false;
      }
      if (!saved) {
        try {
          await vaultDelete(vaultId: res.vault.id);
        } catch (_) {}
        throw StateError('Could not save system encryption key to secure storage');
      }
    }

    await _excludeFromBackup(res.vault.dirPath);
    _refreshUnlocked();
    notifyListeners();
    return res.vault;
  }

  Future<UnlockedVaultDto> changePassword({
    required String vaultId,
    String? currentPassword,
    required String newPassword,
    required String systemAuthReason,
  }) async {
    final current = findUnlockedById(vaultId);
    if (current != null && current.authMode == 'system') {
      final supported = await canUseSystemAuth();
      if (!supported) {
        throw StateError('System authentication is not available on this device');
      }
      final authed = await authenticateSystem(systemAuthReason);
      if (!authed) {
        throw const VaultAuthCancelledException();
      }
    }

    final updated = await vaultChangePassword(
      vaultId: vaultId,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    await _deleteSystemDek(vaultId);
    _refreshUnlocked();
    notifyListeners();
    return updated;
  }

  Future<UnlockedVaultDto> switchToSystemAuth({
    required String vaultId,
    required String currentPassword,
    required String systemAuthReason,
  }) async {
    final supported = await canUseSystemAuth();
    if (!supported) {
      throw StateError('System authentication is not available on this device');
    }
    final dekB64 = await vaultPrepareSwitchToSystem(
      vaultId: vaultId,
      currentPassword: currentPassword,
    );
    final authed = await authenticateSystem(systemAuthReason);
    if (!authed) {
      throw const VaultAuthCancelledException();
    }
    if (dekB64 != null) {
      bool saved = false;
      try {
        saved = await _saveSystemDek(vaultId, dekB64);
      } catch (_) {
        saved = false;
      }
      if (!saved) {
        throw StateError('Could not save system encryption key to secure storage');
      }
    }
    try {
      final updated = await vaultCommitSwitchToSystem(vaultId: vaultId);
      _refreshUnlocked();
      notifyListeners();
      return updated;
    } catch (_) {
      await _deleteSystemDek(vaultId);
      rethrow;
    }
  }

  Future<VaultStatsDto> getStats(String vaultId) => vaultStats(vaultId: vaultId);

  Future<VaultGcResultDto> gcVault(String vaultId) => vaultGc(vaultId: vaultId);

  Future<void> exportBackup({
    required String vaultId,
    String? backupPassword,
    required String destArchivePath,
  }) {
    return vaultExportBackup(
      vaultId: vaultId,
      backupPassword: backupPassword,
      destArchivePath: destArchivePath,
    );
  }

  Future<VaultBackupInfoDto> inspectBackup(String archivePath) {
    return vaultInspectBackup(archivePath: archivePath);
  }

  Future<UnlockedVaultDto> importBackup({
    required String archivePath,
    String? vaultName,
    required String targetStorageRoot,
    String? backupPassword,
    required String targetAuthMode,
    String? newLocalPassword,
    required String systemAuthReason,
  }) async {
    if (targetAuthMode == 'system') {
      final supported = await canUseSystemAuth();
      if (!supported) {
        throw StateError('System authentication is not available on this device');
      }
      final authed = await authenticateSystem(systemAuthReason);
      if (!authed) {
        throw const VaultAuthCancelledException();
      }
    }

    final res = await vaultImportBackup(
      archivePath: archivePath,
      vaultName: vaultName,
      targetStorageRoot: targetStorageRoot,
      backupPassword: backupPassword,
      targetAuthMode: targetAuthMode,
      newLocalPassword: newLocalPassword,
    );

    if (targetAuthMode == 'system' && res.systemDekB64 != null) {
      bool saved = false;
      try {
        saved = await _saveSystemDek(res.vault.id, res.systemDekB64!);
      } catch (_) {
        saved = false;
      }
      if (!saved) {
        try {
          await vaultDelete(vaultId: res.vault.id);
        } catch (_) {}
        throw StateError('Could not save system encryption key to secure storage');
      }
    }

    await _excludeFromBackup(res.vault.dirPath);
    _refreshUnlocked();
    notifyListeners();
    return res.vault;
  }

  Future<UnlockedVaultDto> renameVault({
    required String vaultId,
    required String newName,
  }) async {
    final updated = await vaultRename(vaultId: vaultId, newName: newName);
    _refreshUnlocked();
    notifyListeners();
    return updated;
  }

  Future<void> deleteVault(String vaultId) async {
    final activeRoot = GlobalPlaybackService.instance.currentRoot;
    if (activeRoot != null && vaultIdFromRoot(activeRoot) == vaultId) {
      GlobalPlaybackService.instance.stop();
    }
    await vaultDelete(vaultId: vaultId);
    await _deleteSystemDek(vaultId);
    for (final cb in _lockCleanups) {
      try {
        cb(vaultId);
      } catch (_) {}
    }
    unawaited(FileOpenService.instance.clearVaultExports(vaultId));
    _refreshUnlocked();
    if (_unlocked.isEmpty) {
      unawaited(_resetSecureScreen());
    }
    notifyListeners();
  }
}
