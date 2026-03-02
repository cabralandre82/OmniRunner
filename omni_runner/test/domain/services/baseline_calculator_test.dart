import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/services/baseline_calculator.dart';

void main() {
  const calc = BaselineCalculator();
  const msPerDay = 86400000;
  const windowStartMs = 0;
  const windowEndMs = 28 * msPerDay; // 4 weeks

  String idGen(EvolutionMetric m) => 'id-${m.name}';

  List<BaselineSession> makeSessions(int count) => List.generate(
        count,
        (i) => BaselineSession(
          distanceM: 5000 + i * 100.0,
          movingMs: 1800000 + i * 60000, // 30 min + i min
          avgPaceSecPerKm: 300.0 + i * 5,
          avgBpm: 150 + i,
          startTimeMs: i * msPerDay,
        ),
      );

  group('BaselineCalculator', () {
    test('computeAll returns 6 baselines', () {
      final sessions = makeSessions(5);
      final baselines = calc.computeAll(
        userId: 'u1',
        groupId: 'g1',
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: windowEndMs,
        nowMs: windowEndMs,
        idGenerator: idGen,
      );
      expect(baselines.length, EvolutionMetric.values.length);
    });

    test('avgPace computes mean of pace values', () {
      final sessions = [
        const BaselineSession(
            distanceM: 5000, movingMs: 1500000, avgPaceSecPerKm: 300, startTimeMs: 0),
        const BaselineSession(
            distanceM: 5000, movingMs: 1500000, avgPaceSecPerKm: 320, startTimeMs: msPerDay),
      ];
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.avgPace,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: 14 * msPerDay,
        nowMs: 14 * msPerDay,
      );
      expect(result.value, 310.0);
      expect(result.sampleSize, 2);
    });

    test('avgPace ignores null pace values', () {
      final sessions = [
        const BaselineSession(
            distanceM: 5000, movingMs: 1500000, avgPaceSecPerKm: 300, startTimeMs: 0),
        const BaselineSession(
            distanceM: 0, movingMs: 1000, avgPaceSecPerKm: null, startTimeMs: msPerDay),
      ];
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.avgPace,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: 14 * msPerDay,
        nowMs: 14 * msPerDay,
      );
      expect(result.value, 300.0);
      expect(result.sampleSize, 1);
    });

    test('weeklyVolume divides total distance by weeks', () {
      final sessions = [
        const BaselineSession(distanceM: 10000, movingMs: 3000000, startTimeMs: 0),
        const BaselineSession(distanceM: 10000, movingMs: 3000000, startTimeMs: 7 * msPerDay),
      ];
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.weeklyVolume,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: 14 * msPerDay,
        nowMs: 14 * msPerDay,
      );
      expect(result.value, 10000.0); // 20000m / 2 weeks
    });

    test('weeklyFrequency divides count by weeks', () {
      final sessions = makeSessions(6);
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.weeklyFrequency,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: windowEndMs,
        nowMs: windowEndMs,
      );
      expect(result.value, 1.5); // 6 sessions / 4 weeks
    });

    test('avgHeartRate ignores null BPM', () {
      final sessions = [
        const BaselineSession(
            distanceM: 5000, movingMs: 1800000, avgBpm: 150, startTimeMs: 0),
        const BaselineSession(
            distanceM: 5000, movingMs: 1800000, avgBpm: null, startTimeMs: msPerDay),
        const BaselineSession(
            distanceM: 5000, movingMs: 1800000, avgBpm: 160, startTimeMs: 2 * msPerDay),
      ];
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.avgHeartRate,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: 14 * msPerDay,
        nowMs: 14 * msPerDay,
      );
      expect(result.value, 155.0);
      expect(result.sampleSize, 2);
    });

    test('empty sessions produce value 0', () {
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.avgPace,
        sessions: [],
        windowStartMs: windowStartMs,
        windowEndMs: windowEndMs,
        nowMs: windowEndMs,
      );
      expect(result.value, 0);
      expect(result.sampleSize, 0);
    });

    test('avgMovingTime computes mean of movingMs', () {
      final sessions = [
        const BaselineSession(distanceM: 5000, movingMs: 1800000, startTimeMs: 0),
        const BaselineSession(distanceM: 5000, movingMs: 2400000, startTimeMs: msPerDay),
      ];
      final result = calc.compute(
        id: 'b1',
        userId: 'u1',
        groupId: 'g1',
        metric: EvolutionMetric.avgMovingTime,
        sessions: sessions,
        windowStartMs: windowStartMs,
        windowEndMs: 14 * msPerDay,
        nowMs: 14 * msPerDay,
      );
      expect(result.value, 2100000.0);
    });
  });
}
