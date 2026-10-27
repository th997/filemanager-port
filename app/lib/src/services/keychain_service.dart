import 'dart:io';
import 'package:flutter/services.dart';

/// Lightweight platform Keychain storage.
///
/// On iOS, items stored in the Keychain persist across application
/// uninstallations and reinstalls under the same Team ID.
class KeychainService {
  static const MethodChannel _channel =
      MethodChannel('com.github.th997.filemanager/keychain');

  static bool get isSupported => Platform.isIOS;

  static Future<bool> save(String key, String value) async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('save', {
        'key': key,
        'value': value,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> read(String key) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String?>('read', {'key': key});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> delete(String key) async {
    if (!isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('delete', {'key': key});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
