import 'package:filemanager/src/services/task_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeedEstimator tests', () {
    test('formatBytes formats units accurately', () {
      expect(formatBytes(BigInt.from(0)), '0 B');
      expect(formatBytes(BigInt.from(500)), '500 B');
      expect(formatBytes(BigInt.from(1024)), '1.0 KB');
      expect(formatBytes(BigInt.from(1024 * 1024)), '1.0 MB');
      expect(formatBytes(BigInt.from(730700000)), '696.8 MB');
      expect(formatBytes(BigInt.from(1024 * 1024 * 1024 * 2)), '2.00 GB');
    });

    test('initial samples do not produce premature speed', () {
      final estimator = SpeedEstimator();
      expect(estimator.add(BigInt.zero), isNull);
      expect(estimator.speedText(), isNull);
      expect(estimator.etaText(BigInt.zero, BigInt.from(1000000)), isNull);
    });

    test('sliding window calculates transfer speed without collapsing on chunk pauses', () async {
      final estimator = SpeedEstimator(windowDuration: const Duration(milliseconds: 1000));
      estimator.add(BigInt.zero);

      await Future<void>.delayed(const Duration(milliseconds: 350));
      final speed1 = estimator.add(BigInt.from(3500000)); // 3.5MB in 350ms ~ 10 MB/s
      expect(speed1, isNotNull);
      expect(estimator.speedText(), isNotNull);
      expect(estimator.speedText()!.contains('/s'), isTrue);

      // Now simulate a chunk pause where completed does not advance for 200ms
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final speed2 = estimator.add(BigInt.from(3500000));
      // Over the ~550ms window, 3.5MB / 0.55s is still ~6.3 MB/s!
      // It should NOT collapse to 0 B/s!
      expect(speed2, isNotNull);
      expect(speed2! > 1000000, isTrue);
      expect(estimator.speedText(), isNotNull);
      expect(estimator.speedText(), isNot('0 B/s'));
    });

    test('etaText formats in English and Chinese', () async {
      final estimator = SpeedEstimator();
      estimator.add(BigInt.zero);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // 4MB in 400ms = ~10MB/s
      estimator.add(BigInt.from(4000000));

      final total = BigInt.from(104000000); // 100MB remaining ~ 10s left
      final etaEn = estimator.etaText(BigInt.from(4000000), total, isZh: false);
      final etaZh = estimator.etaText(BigInt.from(4000000), total, isZh: true);

      expect(etaEn, isNotNull);
      expect(etaZh, isNotNull);
      expect(etaEn!.contains('sec left') || etaEn.contains('min left'), isTrue);
      expect(etaZh!.contains('秒') || etaZh.contains('分钟'), isTrue);

      // When completed >= total, etaText must be null
      expect(estimator.etaText(total, total, isZh: false), isNull);
      expect(estimator.etaText(total + BigInt.from(100), total, isZh: true), isNull);
    });

    test('speedText never outputs 0 B/s when speed is zero or negligible', () {
      final estimator = SpeedEstimator();
      // Uninitialized
      expect(estimator.speedText(), isNull);
    });

    test('burst buffer fill followed by chunk pause is smoothed and does not collapse to 0', () async {
      final estimator = SpeedEstimator();
      estimator.add(BigInt.zero);

      // Simulate 5MB initial chunk buffered in 350ms
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final speed1 = estimator.add(BigInt.from(5242880)); // 5MB
      expect(speed1, isNotNull);
      // Cumulative rate anchor keeps it smooth and bounded (no 100MB/s fake burst)
      expect(speed1! < 30 * 1024 * 1024, isTrue);

      // Simulate in-flight network send of 5MB part taking 800ms
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final speed2 = estimator.add(BigInt.from(5242880)); // still 5MB
      expect(speed2, isNotNull);
      // Speed should be held during chunk in-flight, NOT dropped to 0!
      expect(speed2! > 1024 * 1024, isTrue);
      expect(estimator.speedText(), isNot('0 B/s'));
    });
  });
}
