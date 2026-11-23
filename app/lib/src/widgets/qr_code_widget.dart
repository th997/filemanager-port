import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Pure-Dart, zero-dependency ISO/IEC 18004 QR Code widget (Byte mode, ECC-M,
/// Versions 1..10, up to 213 UTF-8 bytes — suitable for LAN share URLs).
class QrCodeWidget extends StatelessWidget {
  final String data;
  final double size;
  final Color foregroundColor;
  final Color backgroundColor;
  final int quietZoneModules;

  const QrCodeWidget({
    super.key,
    required this.data,
    this.size = 200,
    this.foregroundColor = Colors.black,
    this.backgroundColor = Colors.white,
    this.quietZoneModules = 4,
  });

  @override
  Widget build(BuildContext context) {
    final matrix = QrCodeEncoder.encode(data);
    if (matrix == null) {
      return SizedBox(
        width: size,
        height: size,
        child: const Center(child: Icon(Icons.qr_code_2, size: 48)),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrCodePainter(
          matrix: matrix,
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          quietZone: quietZoneModules,
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  final List<List<bool>> matrix;
  final Color foregroundColor;
  final Color backgroundColor;
  final int quietZone;

  const _QrCodePainter({
    required this.matrix,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.quietZone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = matrix.length;
    final total = n + quietZone * 2;
    final moduleSize = size.shortestSide / total;
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final fgPaint = Paint()
      ..color = foregroundColor
      ..isAntiAlias = false;

    for (var r = 0; r < n; r++) {
      final row = matrix[r];
      for (var c = 0; c < n; c++) {
        if (row[c]) {
          canvas.drawRect(
            Rect.fromLTWH(
              (c + quietZone) * moduleSize,
              (r + quietZone) * moduleSize,
              moduleSize + 0.15,
              moduleSize + 0.15,
            ),
            fgPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCodePainter oldDelegate) =>
      oldDelegate.matrix != matrix ||
      oldDelegate.foregroundColor != foregroundColor ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.quietZone != quietZone;
}

class _QrVersionSpec {
  final int version;
  final int totalDataCodewords;
  final int ecPerBlock;
  final int g1Blocks;
  final int g1Data;
  final int g2Blocks;
  final int g2Data;
  final List<int> alignmentCenters;

  const _QrVersionSpec({
    required this.version,
    required this.totalDataCodewords,
    required this.ecPerBlock,
    required this.g1Blocks,
    required this.g1Data,
    required this.g2Blocks,
    required this.g2Data,
    required this.alignmentCenters,
  });
}

/// Minimal ISO/IEC 18004 QR encoder (Byte mode, ECC Level M, Versions 1..10).
class QrCodeEncoder {
  static const List<_QrVersionSpec> _specs = [
    _QrVersionSpec(version: 1, totalDataCodewords: 16, ecPerBlock: 10, g1Blocks: 1, g1Data: 16, g2Blocks: 0, g2Data: 0, alignmentCenters: []),
    _QrVersionSpec(version: 2, totalDataCodewords: 28, ecPerBlock: 16, g1Blocks: 1, g1Data: 28, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 18]),
    _QrVersionSpec(version: 3, totalDataCodewords: 44, ecPerBlock: 26, g1Blocks: 1, g1Data: 44, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 22]),
    _QrVersionSpec(version: 4, totalDataCodewords: 64, ecPerBlock: 18, g1Blocks: 2, g1Data: 32, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 26]),
    _QrVersionSpec(version: 5, totalDataCodewords: 86, ecPerBlock: 24, g1Blocks: 2, g1Data: 43, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 30]),
    _QrVersionSpec(version: 6, totalDataCodewords: 108, ecPerBlock: 16, g1Blocks: 4, g1Data: 27, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 34]),
    _QrVersionSpec(version: 7, totalDataCodewords: 124, ecPerBlock: 18, g1Blocks: 4, g1Data: 31, g2Blocks: 0, g2Data: 0, alignmentCenters: [6, 22, 38]),
    _QrVersionSpec(version: 8, totalDataCodewords: 154, ecPerBlock: 22, g1Blocks: 2, g1Data: 38, g2Blocks: 2, g2Data: 39, alignmentCenters: [6, 24, 42]),
    _QrVersionSpec(version: 9, totalDataCodewords: 182, ecPerBlock: 22, g1Blocks: 3, g1Data: 36, g2Blocks: 2, g2Data: 37, alignmentCenters: [6, 26, 46]),
    _QrVersionSpec(version: 10, totalDataCodewords: 216, ecPerBlock: 26, g1Blocks: 4, g1Data: 43, g2Blocks: 1, g2Data: 44, alignmentCenters: [6, 28, 50]),
  ];

  /// Precomputed 15-bit format strings for ECC Level M (00) and masks 0..7.
  static const List<int> _formatBitsM = [
    0x5412, 0x5125, 0x5E7C, 0x5B4B, 0x45F9, 0x40CE, 0x4F97, 0x4AA0,
  ];

  /// Precomputed 18-bit version info strings for Versions 7..10.
  static const Map<int, int> _versionBits = {
    7: 0x07C94,
    8: 0x085BC,
    9: 0x09A99,
    10: 0x0A4D3,
  };

  static List<List<bool>>? encode(String text) {
    final bytes = Uint8List.fromList(utf8.encode(text));
    _QrVersionSpec? spec;
    for (final s in _specs) {
      final countBits = s.version <= 9 ? 8 : 16;
      final neededBits = 4 + countBits + bytes.length * 8;
      if (neededBits <= s.totalDataCodewords * 8) {
        spec = s;
        break;
      }
    }
    if (spec == null) return null;

    final dataCodewords = _buildDataCodewords(bytes, spec);
    final finalCodewords = _interleaveBlocks(dataCodewords, spec);

    final size = 17 + 4 * spec.version;
    final base = List.generate(size, (_) => List<bool>.filled(size, false));
    final isFunc = List.generate(size, (_) => List<bool>.filled(size, false));

    _placeFinderPatterns(base, isFunc, size);
    _placeTimingPatterns(base, isFunc, size);
    _placeAlignmentPatterns(base, isFunc, spec.alignmentCenters, size);
    _reserveFormatAreas(base, isFunc, size);
    if (spec.version >= 7) {
      _placeVersionInfo(base, isFunc, size, spec.version);
    }
    _placeDataBits(base, isFunc, size, finalCodewords);

    // Choose mask 0..7 with lowest penalty score.
    List<List<bool>>? bestMatrix;
    var bestPenalty = 1 << 30;
    for (var mask = 0; mask < 8; mask++) {
      final candidate = List.generate(
        size,
        (r) => List<bool>.generate(size, (c) {
          final v = base[r][c];
          if (isFunc[r][c]) return v;
          return _maskBit(mask, r, c) ? !v : v;
        }),
      );
      _applyFormatBits(candidate, size, _formatBitsM[mask]);
      final penalty = _penaltyScore(candidate, size);
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMatrix = candidate;
      }
    }
    return bestMatrix;
  }

  static Uint8List _buildDataCodewords(Uint8List bytes, _QrVersionSpec spec) {
    final bits = <int>[];
    void pushBits(int val, int len) {
      for (var i = len - 1; i >= 0; i--) {
        bits.add((val >> i) & 1);
      }
    }

    // Mode indicator: Byte mode = 0100
    pushBits(0x4, 4);
    final countBits = spec.version <= 9 ? 8 : 16;
    pushBits(bytes.length, countBits);
    for (final b in bytes) {
      pushBits(b, 8);
    }

    final maxBits = spec.totalDataCodewords * 8;
    // Terminator up to 4 zero bits
    final term = (maxBits - bits.length).clamp(0, 4);
    for (var i = 0; i < term; i++) {
      bits.add(0);
    }
    // Pad to byte boundary
    while (bits.length % 8 != 0) {
      bits.add(0);
    }

    final out = Uint8List(spec.totalDataCodewords);
    var byteIdx = 0;
    for (var i = 0; i < bits.length; i += 8) {
      var v = 0;
      for (var b = 0; b < 8; b++) {
        v = (v << 1) | bits[i + b];
      }
      out[byteIdx++] = v;
    }
    const padBytes = [0xEC, 0x11];
    var padIdx = 0;
    while (byteIdx < spec.totalDataCodewords) {
      out[byteIdx++] = padBytes[padIdx & 1];
      padIdx++;
    }
    return out;
  }

  static Uint8List _interleaveBlocks(Uint8List data, _QrVersionSpec spec) {
    final dataBlocks = <Uint8List>[];
    final ecBlocks = <Uint8List>[];
    final gen = _rsGenerator(spec.ecPerBlock);

    var offset = 0;
    for (var i = 0; i < spec.g1Blocks; i++) {
      final blk = Uint8List.sublistView(data, offset, offset + spec.g1Data);
      offset += spec.g1Data;
      dataBlocks.add(blk);
      ecBlocks.add(_rsRemainder(blk, gen));
    }
    for (var i = 0; i < spec.g2Blocks; i++) {
      final blk = Uint8List.sublistView(data, offset, offset + spec.g2Data);
      offset += spec.g2Data;
      dataBlocks.add(blk);
      ecBlocks.add(_rsRemainder(blk, gen));
    }

    final maxDataLen = spec.g2Blocks > 0 ? spec.g2Data : spec.g1Data;
    final result = <int>[];
    for (var i = 0; i < maxDataLen; i++) {
      for (final blk in dataBlocks) {
        if (i < blk.length) result.add(blk[i]);
      }
    }
    for (var i = 0; i < spec.ecPerBlock; i++) {
      for (final ec in ecBlocks) {
        result.add(ec[i]);
      }
    }
    return Uint8List.fromList(result);
  }

  static int _gfMul(int x, int y) {
    var z = 0;
    for (var i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >> 7) * 0x11D);
      z ^= ((y >> i) & 1) * x;
    }
    return z;
  }

  static Uint8List _rsGenerator(int degree) {
    final poly = Uint8List(degree);
    poly[degree - 1] = 1;
    var root = 1;
    for (var i = 0; i < degree; i++) {
      for (var j = 0; j < degree; j++) {
        poly[j] = _gfMul(poly[j], root);
        if (j + 1 < degree) {
          poly[j] ^= poly[j + 1];
        }
      }
      root = _gfMul(root, 0x02);
    }
    return poly;
  }

  static Uint8List _rsRemainder(Uint8List data, Uint8List gen) {
    final rem = Uint8List(gen.length);
    for (final b in data) {
      final factor = b ^ rem[0];
      for (var i = 0; i < rem.length - 1; i++) {
        rem[i] = rem[i + 1];
      }
      rem[rem.length - 1] = 0;
      for (var i = 0; i < gen.length; i++) {
        rem[i] ^= _gfMul(gen[i], factor);
      }
    }
    return rem;
  }

  static void _setFunc(
    List<List<bool>> m,
    List<List<bool>> f,
    int r,
    int c,
    bool val,
  ) {
    m[r][c] = val;
    f[r][c] = true;
  }

  static void _placeFinderPatterns(
    List<List<bool>> m,
    List<List<bool>> f,
    int size,
  ) {
    final origins = [
      (0, 0),
      (0, size - 7),
      (size - 7, 0),
    ];
    for (final (or, oc) in origins) {
      for (var dr = -1; dr <= 7; dr++) {
        for (var dc = -1; dc <= 7; dc++) {
          final r = or + dr;
          final c = oc + dc;
          if (r < 0 || r >= size || c < 0 || c >= size) continue;
          final dark = dr >= 0 &&
              dr <= 6 &&
              dc >= 0 &&
              dc <= 6 &&
              (dr == 0 ||
                  dr == 6 ||
                  dc == 0 ||
                  dc == 6 ||
                  (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4));
          _setFunc(m, f, r, c, dark);
        }
      }
    }
  }

  static void _placeTimingPatterns(
    List<List<bool>> m,
    List<List<bool>> f,
    int size,
  ) {
    for (var i = 8; i < size - 8; i++) {
      final dark = i.isEven;
      if (!f[6][i]) _setFunc(m, f, 6, i, dark);
      if (!f[i][6]) _setFunc(m, f, i, 6, dark);
    }
  }

  static void _placeAlignmentPatterns(
    List<List<bool>> m,
    List<List<bool>> f,
    List<int> centers,
    int size,
  ) {
    for (final cr in centers) {
      for (final cc in centers) {
        final inTopLeft = cr <= 8 && cc <= 8;
        final inTopRight = cr <= 8 && cc >= size - 9;
        final inBottomLeft = cr >= size - 9 && cc <= 8;
        if (inTopLeft || inTopRight || inBottomLeft) continue;
        for (var dr = -2; dr <= 2; dr++) {
          for (var dc = -2; dc <= 2; dc++) {
            final dist = dr.abs() > dc.abs() ? dr.abs() : dc.abs();
            _setFunc(m, f, cr + dr, cc + dc, dist != 1);
          }
        }
      }
    }
  }

  static void _reserveFormatAreas(
    List<List<bool>> m,
    List<List<bool>> f,
    int size,
  ) {
    for (var i = 0; i <= 8; i++) {
      if (i != 6) {
        _setFunc(m, f, 8, i, false);
        _setFunc(m, f, i, 8, false);
      }
    }
    for (var i = size - 8; i < size; i++) {
      _setFunc(m, f, 8, i, false);
      _setFunc(m, f, i, 8, false);
    }
    // Dark module (always dark)
    _setFunc(m, f, size - 8, 8, true);
  }

  static void _placeVersionInfo(
    List<List<bool>> m,
    List<List<bool>> f,
    int size,
    int version,
  ) {
    final bits = _versionBits[version];
    if (bits == null) return;
    for (var i = 0; i < 18; i++) {
      final dark = ((bits >> i) & 1) == 1;
      final a = size - 11 + (i % 3);
      final b = i ~/ 3;
      _setFunc(m, f, a, b, dark);
      _setFunc(m, f, b, a, dark);
    }
  }

  static void _placeDataBits(
    List<List<bool>> m,
    List<List<bool>> f,
    int size,
    Uint8List codewords,
  ) {
    var bitIdx = 0;
    final totalBits = codewords.length * 8;
    var upward = true;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        final r = upward ? (size - 1 - vert) : vert;
        for (var j = 0; j < 2; j++) {
          final c = right - j;
          if (!f[r][c]) {
            var dark = false;
            if (bitIdx < totalBits) {
              dark = ((codewords[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1) == 1;
              bitIdx++;
            }
            m[r][c] = dark;
          }
        }
      }
      upward = !upward;
    }
  }

  static bool _maskBit(int mask, int r, int c) {
    switch (mask) {
      case 0:
        return (r + c) % 2 == 0;
      case 1:
        return r % 2 == 0;
      case 2:
        return c % 3 == 0;
      case 3:
        return (r + c) % 3 == 0;
      case 4:
        return ((r ~/ 2) + (c ~/ 3)) % 2 == 0;
      case 5:
        return ((r * c) % 2) + ((r * c) % 3) == 0;
      case 6:
        return ((((r * c) % 2) + ((r * c) % 3)) % 2) == 0;
      default:
        return ((((r + c) % 2) + ((r * c) % 3)) % 2) == 0;
    }
  }

  static void _applyFormatBits(List<List<bool>> m, int size, int fmt) {
    for (var i = 0; i <= 5; i++) {
      m[8][i] = ((fmt >> (14 - i)) & 1) == 1;
    }
    m[8][7] = ((fmt >> 8) & 1) == 1;
    m[8][8] = ((fmt >> 7) & 1) == 1;
    m[7][8] = ((fmt >> 6) & 1) == 1;
    for (var i = 9; i < 15; i++) {
      m[14 - i][8] = ((fmt >> (14 - i)) & 1) == 1;
    }

    for (var i = 0; i < 8; i++) {
      m[8][size - 1 - i] = ((fmt >> i) & 1) == 1;
    }
    for (var i = 8; i < 15; i++) {
      m[size - 15 + i][8] = ((fmt >> i) & 1) == 1;
    }
    m[size - 8][8] = true;
  }

  static int _penaltyScore(List<List<bool>> m, int size) {
    var score = 0;
    // Rule 1: 5+ adjacent same-color modules in row/col
    for (var r = 0; r < size; r++) {
      var run = 1;
      for (var c = 1; c < size; c++) {
        if (m[r][c] == m[r][c - 1]) {
          run++;
        } else {
          if (run >= 5) score += 3 + (run - 5);
          run = 1;
        }
      }
      if (run >= 5) score += 3 + (run - 5);
    }
    for (var c = 0; c < size; c++) {
      var run = 1;
      for (var r = 1; r < size; r++) {
        if (m[r][c] == m[r - 1][c]) {
          run++;
        } else {
          if (run >= 5) score += 3 + (run - 5);
          run = 1;
        }
      }
      if (run >= 5) score += 3 + (run - 5);
    }
    // Rule 2: 2x2 blocks
    for (var r = 0; r < size - 1; r++) {
      for (var c = 0; c < size - 1; c++) {
        final v = m[r][c];
        if (v == m[r][c + 1] && v == m[r + 1][c] && v == m[r + 1][c + 1]) {
          score += 3;
        }
      }
    }
    // Rule 4: balance of dark modules
    var dark = 0;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (m[r][c]) dark++;
      }
    }
    final total = size * size;
    final k = ((dark * 20 - total * 10).abs() / total).floor();
    score += k * 10;
    return score;
  }
}
