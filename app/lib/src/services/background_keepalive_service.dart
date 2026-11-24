import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

typedef KeepAliveChannelInvoker = Future<bool> Function(
  String method,
  Map<String, dynamic>? arguments,
);

/// Ref-counted bridge to Android Foreground Service (`dataSync`) and iOS
/// BackgroundTasks / `beginBackgroundTask` so active file transfers, directory
/// sync jobs, and LAN HTTP sharing are kept alive across app backgrounding.
class BackgroundKeepAliveService {
  BackgroundKeepAliveService({this.channelInvoker});

  static final BackgroundKeepAliveService instance =
      BackgroundKeepAliveService();

  static const MethodChannel _channel = MethodChannel(
    'com.github.th997.filemanager/background_keepalive',
  );

  final KeepAliveChannelInvoker? channelInvoker;
  final Map<String, ({String title, String detail})> _activeTokens = {};
  Future<void> _invokeChain = Future<void>.value();

  bool get isSupported =>
      channelInvoker != null || Platform.isAndroid || Platform.isIOS;

  bool get isActive => _activeTokens.isNotEmpty;

  int get activeCount => _activeTokens.length;

  List<String> get activeTokens => _activeTokens.keys.toList(growable: false);

  /// Marks [token] as requiring background execution keep-alive.
  ///
  /// Starts the platform keep-alive service on transition from 0 -> 1 active
  /// tokens or updates the foreground notification text if another token updates it.
  Future<void> acquire(
    String token, {
    String title = 'FileManager Background Task',
    String detail = 'Keeping active transfer or LAN share running',
  }) async {
    final wasEmpty = _activeTokens.isEmpty;
    final prev = _activeTokens[token];
    _activeTokens[token] = (title: title, detail: detail);
    if (wasEmpty || prev == null || prev.title != title || prev.detail != detail) {
      await _invoke('start', <String, dynamic>{
        'title': title,
        'detail': detail,
      });
    }
  }

  /// Releases [token] and stops the platform keep-alive service once no active
  /// tokens remain.
  Future<void> release(String token) async {
    final removed = _activeTokens.remove(token);
    if (removed == null) return;
    if (_activeTokens.isEmpty) {
      await _invoke('stop', null);
    } else {
      final remaining = _activeTokens.values.last;
      await _invoke('start', <String, dynamic>{
        'title': remaining.title,
        'detail': remaining.detail,
      });
    }
  }

  /// Releases all tokens (for cleanup or testing) and stops the platform service.
  Future<void> releaseAll() async {
    if (_activeTokens.isEmpty) return;
    _activeTokens.clear();
    await _invoke('stop', null);
  }

  /// Runs [action] while holding a keep-alive token, always releasing it on
  /// completion or error.
  Future<T> runWithKeepAlive<T>(
    String token,
    Future<T> Function() action, {
    String title = 'FileManager Background Task',
    String detail = 'Keeping active transfer or LAN share running',
  }) async {
    await acquire(token, title: title, detail: detail);
    try {
      return await action();
    } finally {
      await release(token);
    }
  }

  Future<void> _invoke(
    String method,
    Map<String, dynamic>? arguments,
  ) {
    final next = _invokeChain.then((_) async {
      if (!isSupported) return;
      try {
        final invoker = channelInvoker;
        if (invoker != null) {
          await invoker(method, arguments);
        } else {
          await _channel.invokeMethod<bool>(method, arguments);
        }
      } catch (_) {
        // Non-fatal: e.g. unit tests or platform channel unavailable.
      }
    });
    _invokeChain = next;
    return next;
  }
}
