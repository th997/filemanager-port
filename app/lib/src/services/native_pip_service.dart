import 'dart:io';

import 'package:flutter/services.dart';

/// Descriptor for an embedded legible subtitle/closed-caption track reported
/// by `AVPlayerItem.asset` on iOS.
class EmbeddedSubtitleTrack {
  final int index;
  final String title;
  final String language;
  final bool selected;

  const EmbeddedSubtitleTrack({
    required this.index,
    required this.title,
    required this.language,
    required this.selected,
  });

  factory EmbeddedSubtitleTrack.fromMap(Map<dynamic, dynamic> raw) {
    final idxRaw = raw['index'];
    final index = idxRaw is int ? idxRaw : int.tryParse('$idxRaw') ?? 0;
    final titleRaw = (raw['title'] ?? '').toString().trim();
    final language = (raw['language'] ?? '').toString().trim();
    return EmbeddedSubtitleTrack(
      index: index,
      title: titleRaw.isNotEmpty
          ? titleRaw
          : (language.isNotEmpty ? language : 'Track ${index + 1}'),
      language: language,
      selected: raw['selected'] == true,
    );
  }
}

/// Bridge to native iOS Picture-in-Picture (`AVPictureInPictureController`)
/// and embedded legible subtitle selection hosted in `AppDelegate.swift`.
class NativePipService {
  static const MethodChannel _channel =
      MethodChannel('com.github.th997.filemanager/pip');

  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isPipSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('startPip') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('stopPip');
    } catch (_) {}
  }

  static Future<List<EmbeddedSubtitleTrack>> listEmbeddedSubtitles() async {
    if (!Platform.isIOS) return const [];
    try {
      final raw = await _channel
          .invokeListMethod<Map<dynamic, dynamic>>('listEmbeddedSubtitles');
      if (raw == null) return const [];
      return raw.map(EmbeddedSubtitleTrack.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> selectEmbeddedSubtitle(int? index) async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('selectEmbeddedSubtitle', {
            'index': index,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
