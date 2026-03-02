import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/usecases/replay_analyzer.dart';

void main() {
  const analyzer = ReplayAnalyzer();

  List<LocationPointEntity> makePoints({
    required int count,
    double latStart = -23.5505,
    double latStep = 0.00001,
    int startMs = 0,
    int stepMs = 1000,
  }) =>
      List.generate(
        count,
        (i) => LocationPointEntity(
          lat: latStart + i * latStep,
          lng: -46.6333,
          alt: 750,
          speed: 3.0,
          timestampMs: startMs + i * stepMs,
        ),
      );

  group('ReplayAnalyzer', () {
    test('returns empty data for less than 2 points', () {
      final result = analyzer.call([]);
      expect(result.splits, isEmpty);
      expect(result.bestSplitIdx, -1);
      expect(result.totalDistanceM, 0);

      final single = analyzer.call(makePoints(count: 1));
      expect(single.splits, isEmpty);
    });

    test('computes splits for multi-km run', () {
      final points = makePoints(count: 1500, latStep: 0.00001, stepMs: 500);
      final result = analyzer.call(points);

      expect(result.splits, isNotEmpty);
      expect(result.totalDistanceM, greaterThan(0));
      expect(result.totalElapsedMs, greaterThan(0));
      expect(result.bestSplitIdx, greaterThanOrEqualTo(0));
    });

    test('best split has the lowest pace', () {
      final points = makePoints(count: 1500, latStep: 0.00001, stepMs: 500);
      final result = analyzer.call(points);

      if (result.splits.length >= 2) {
        final bestPace = result.splits[result.bestSplitIdx].paceSecPerKm;
        for (final split in result.splits) {
          expect(split.paceSecPerKm, greaterThanOrEqualTo(bestPace));
        }
      }
    });

    test('short run with few points returns no sprint', () {
      final points = makePoints(count: 20, latStep: 0.0001, stepMs: 1000);
      final result = analyzer.call(points);
      expect(result.sprint, isNull);
    });
  });
}
