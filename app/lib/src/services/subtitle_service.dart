import 'package:flutter/material.dart';

import '../rust/api/file_manager.dart';

/// A single timed subtitle cue.
class SubtitleCue {
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Pure-Dart parser for `.srt`, `.vtt`, and `.ass`/`.ssa` subtitle files.
class SubtitleParser {
  static final RegExp _srtTimeRe = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
  );
  static final RegExp _vttShortTimeRe = RegExp(
    r'(\d{2}):(\d{2})[.](\d{1,3})\s*-->\s*(\d{2}):(\d{2})[.](\d{1,3})',
  );
  static final RegExp _assTagRe = RegExp(r'\{[^}]*\}');
  static final RegExp _htmlTagRe = RegExp(r'<[^>]+>');

  static Duration _ms(int h, int m, int s, String frac) {
    final padded = frac.padRight(3, '0').substring(0, 3);
    return Duration(
      hours: h,
      minutes: m,
      seconds: s,
      milliseconds: int.tryParse(padded) ?? 0,
    );
  }

  static List<SubtitleCue> parse(String content, {String ext = 'srt'}) {
    final lower = ext.toLowerCase().replaceFirst('.', '');
    if (lower == 'ass' || lower == 'ssa') {
      return _parseAss(content);
    }
    return _parseSrtOrVtt(content);
  }

  static List<SubtitleCue> _parseSrtOrVtt(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n{2,}'));
    final cues = <SubtitleCue>[];

    for (final block in blocks) {
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      int timeLineIdx = -1;
      Duration? start;
      Duration? end;

      for (int i = 0; i < lines.length; i++) {
        final m = _srtTimeRe.firstMatch(lines[i]);
        if (m != null) {
          timeLineIdx = i;
          start = _ms(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
            m.group(4)!,
          );
          end = _ms(
            int.parse(m.group(5)!),
            int.parse(m.group(6)!),
            int.parse(m.group(7)!),
            m.group(8)!,
          );
          break;
        }
        final ms = _vttShortTimeRe.firstMatch(lines[i]);
        if (ms != null) {
          timeLineIdx = i;
          start = _ms(0, int.parse(ms.group(1)!), int.parse(ms.group(2)!), ms.group(3)!);
          end = _ms(0, int.parse(ms.group(4)!), int.parse(ms.group(5)!), ms.group(6)!);
          break;
        }
      }

      if (timeLineIdx < 0 || start == null || end == null || timeLineIdx + 1 >= lines.length) {
        continue;
      }
      final text = lines
          .sublist(timeLineIdx + 1)
          .join('\n')
          .replaceAll(_htmlTagRe, '')
          .trim();
      if (text.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: text));
      }
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static List<SubtitleCue> _parseAss(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final cues = <SubtitleCue>[];
    final timeRe = RegExp(r'(\d+):(\d{2}):(\d{2})[.](\d{2})');

    for (final line in normalized.split('\n')) {
      if (!line.startsWith('Dialogue:')) continue;
      final body = line.substring('Dialogue:'.length).trim();
      final parts = body.split(',');
      if (parts.length < 10) continue;
      final sm = timeRe.firstMatch(parts[1].trim());
      final em = timeRe.firstMatch(parts[2].trim());
      if (sm == null || em == null) continue;
      final start = Duration(
        hours: int.parse(sm.group(1)!),
        minutes: int.parse(sm.group(2)!),
        seconds: int.parse(sm.group(3)!),
        milliseconds: int.parse(sm.group(4)!) * 10,
      );
      final end = Duration(
        hours: int.parse(em.group(1)!),
        minutes: int.parse(em.group(2)!),
        seconds: int.parse(em.group(3)!),
        milliseconds: int.parse(em.group(4)!) * 10,
      );
      final rawText = parts.sublist(9).join(',');
      final cleaned = rawText
          .replaceAll(_assTagRe, '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ')
          .trim();
      if (cleaned.isNotEmpty) {
        cues.add(SubtitleCue(start: start, end: end, text: cleaned));
      }
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  /// Binary-search lookup of active subtitle text at [position].
  static String? activeTextAt(List<SubtitleCue> cues, Duration position) {
    if (cues.isEmpty) return null;
    int lo = 0;
    int hi = cues.length - 1;
    int candidate = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].start <= position) {
        candidate = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (candidate < 0) return null;
    // Scan backwards slightly to catch overlapping cues.
    final active = <String>[];
    for (int i = candidate; i >= 0 && i >= candidate - 4; i--) {
      final c = cues[i];
      if (position >= c.start && position <= c.end) {
        active.insert(0, c.text);
      }
    }
    return active.isEmpty ? null : active.join('\n');
  }
}

/// Loaded external subtitle bundle.
class LoadedSubtitle {
  final String name;
  final String rawContent;
  final List<SubtitleCue> cues;

  const LoadedSubtitle({
    required this.name,
    required this.rawContent,
    required this.cues,
  });
}

/// Discovers and loads external `.srt` / `.ass` / `.vtt` subtitles from any VFS
/// backend (local, remote, archive, or Privacy Vault).
class SubtitleService {
  static const supportedExtensions = {'srt', 'vtt', 'ass', 'ssa'};

  static bool isSubtitleFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return false;
    return supportedExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Auto-detect same-directory, same-basename subtitle files (e.g. `video.mp4`
  /// -> `video.srt`, `video.zh.srt`, `video.en.vtt`, `video.ass`).
  static Future<LoadedSubtitle?> findMatchingSubtitle({
    required String root,
    required String mediaPath,
  }) async {
    try {
      final slash = mediaPath.lastIndexOf('/');
      final dir = slash >= 0 ? mediaPath.substring(0, slash) : '';
      final fileName = slash >= 0 ? mediaPath.substring(slash + 1) : mediaPath;
      final dot = fileName.lastIndexOf('.');
      final stem = (dot > 0 ? fileName.substring(0, dot) : fileName).toLowerCase();

      final entries = await listDir(root: root, path: dir);
      EntryDto? best;
      int bestScore = -1;
      for (final e in entries) {
        if (e.isDir || !isSubtitleFile(e.name)) continue;
        final lower = e.name.toLowerCase();
        final eDot = lower.lastIndexOf('.');
        final eStem = eDot > 0 ? lower.substring(0, eDot) : lower;
        int score = -1;
        if (eStem == stem) {
          score = 100;
        } else if (eStem.startsWith('$stem.')) {
          score = 80;
        } else if (eStem.startsWith('${stem}_') || eStem.startsWith('$stem-')) {
          score = 60;
        }
        if (score > bestScore) {
          bestScore = score;
          best = e;
        }
      }
      if (best == null) return null;
      return await loadFromVfs(root: root, path: best.path, name: best.name);
    } catch (_) {
      return null;
    }
  }

  static Future<LoadedSubtitle?> loadFromVfs({
    required String root,
    required String path,
    required String name,
  }) async {
    final content = await readTextFile(root: root, path: path);
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1) : 'srt';
    final cues = SubtitleParser.parse(content, ext: ext);
    return LoadedSubtitle(name: name, rawContent: content, cues: cues);
  }
}

/// Cross-platform video subtitle overlay rendered smoothly above any player
/// (both `media_kit` and iOS `AVPlayer`).
class VideoSubtitleOverlay extends StatelessWidget {
  final String? text;
  final double bottomPadding;

  const VideoSubtitleOverlay({
    super.key,
    required this.text,
    this.bottomPadding = 48,
  });

  @override
  Widget build(BuildContext context) {
    final value = text;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 24,
      right: 24,
      bottom: bottomPadding,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.3,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
