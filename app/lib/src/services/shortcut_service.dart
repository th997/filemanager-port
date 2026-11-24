import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class ShortcutTarget {
  /// `'folder'`, `'remote'`, or `'sync'`.
  final String type;
  final String id;
  final String label;
  final String root;
  final String path;

  const ShortcutTarget({
    required this.type,
    required this.id,
    required this.label,
    this.root = '',
    this.path = '',
  });

  factory ShortcutTarget.fromMap(Map<Object?, Object?> map) {
    return ShortcutTarget(
      type: (map['targetType'] ?? map['type'] ?? 'folder').toString(),
      id: (map['id'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      root: (map['root'] ?? '').toString(),
      path: (map['path'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'targetType': type,
        'root': root,
        'path': path,
      };
}

/// Manages mobile Home Screen shortcuts (`Android` `ShortcutManager` and `iOS`
/// `UIApplication.shortcutItems`) over a MethodChannel.
class ShortcutService {
  static final ShortcutService instance = ShortcutService();

  final MethodChannel _channel;
  final bool Function()? platformSupportedOverride;
  final StreamController<ShortcutTarget> _openedController =
      StreamController<ShortcutTarget>.broadcast();

  ShortcutService({
    MethodChannel? channel,
    this.platformSupportedOverride,
  }) : _channel = channel ??
            const MethodChannel('com.github.th997.filemanager/shortcuts') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Stream<ShortcutTarget> get onShortcutOpened => _openedController.stream;

  Future<bool> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onShortcutOpened' && call.arguments is Map) {
      _openedController.add(
        ShortcutTarget.fromMap(call.arguments as Map<Object?, Object?>),
      );
      return true;
    }
    return false;
  }

  Future<bool> isSupported() async {
    final override = platformSupportedOverride;
    if (override != null) {
      if (!override()) return false;
    } else if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pinShortcut(ShortcutTarget target) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'pinShortcut',
        target.toMap(),
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<ShortcutTarget?> consumeInitialShortcut() async {
    final override = platformSupportedOverride;
    if (override != null) {
      if (!override()) return null;
    } else if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<dynamic>('getInitialShortcut');
      if (raw is Map) {
        return ShortcutTarget.fromMap(raw);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
