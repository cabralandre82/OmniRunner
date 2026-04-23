import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/time_trial_result_entity.dart';
import 'package:omni_runner/domain/services/time_trial_threshold_estimator.dart';
import 'package:omni_runner/domain/value_objects/time_trial_protocol.dart';

void main() {
  const estimator = TimeTrialThresholdEstimator();

  DateTime tAt(int year, int month, int day) =>
      DateTime.utc(year, month, day, 8, 0);

  group('TimeTrialThresholdEstimator.estimate', () {
    test('30 min TT: avg pace IS threshold (multiplier 1.0)', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.thirtyMinute,
        actualDistanceM: 7500,
        actualDurationS: 1800,
        finishedAt: tAt(2026, 4, 20),
        avgHrBpm: 170,
      );
      final est = estimator.estimate(result);
      expect(est.valid, isTrue);
      expect(est.thresholdPaceSecKm, 240);
      expect(est.lthrBpm, 170);
      expect(est.sourceProtocol, TimeTrialProtocol.thirtyMinute);
    });

    test('5 km TT: threshold = avg pace × 1.05', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 4, 20),
        avgHrBpm: 180,
      );
      final est = estimator.estimate(result);
      expect(est.valid, isTrue);
      expect(est.thresholdPaceSecKm, 252);
      expect(est.lthrBpm, 171);
    });

    test('3 km TT: threshold = avg pace × 1.10', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.threeKm,
        actualDistanceM: 3000,
        actualDurationS: 660,
        finishedAt: tAt(2026, 4, 20),
        avgHrBpm: 185,
      );
      final est = estimator.estimate(result);
      expect(est.valid, isTrue);
      expect(est.thresholdPaceSecKm, 242);
      expect(est.lthrBpm, 170);
    });

    test('LTHR is absent when avgHr is null', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 4, 20),
      );
      final est = estimator.estimate(result);
      expect(est.valid, isTrue);
      expect(est.lthrBpm, isNull);
    });

    test('LTHR is absent when avgHr is 0 (legacy sentinel)', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 4, 20),
        avgHrBpm: 0,
      );
      final est = estimator.estimate(result);
      expect(est.lthrBpm, isNull);
    });

    test('returns invalid when distance is 0', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 0,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 4, 20),
      );
      final est = estimator.estimate(result);
      expect(est.valid, isFalse);
      expect(est.thresholdPaceSecKm, isNull);
    });

    test('returns invalid when duration is 0', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 0,
        finishedAt: tAt(2026, 4, 20),
      );
      final est = estimator.estimate(result);
      expect(est.valid, isFalse);
    });

    test('floor rounds threshold pace to integer seconds', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.thirtyMinute,
        actualDistanceM: 7250,
        actualDurationS: 1800,
        finishedAt: tAt(2026, 4, 20),
      );
      final est = estimator.estimate(result);
      expect(est.valid, isTrue);
      expect(est.thresholdPaceSecKm, 248);
    });
  });

  group('TimeTrialResultEntity.isFreshOn', () {
    test('same-day result is fresh', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 4, 20),
      );
      expect(result.isFreshOn(referenceDay: tAt(2026, 4, 20)), isTrue);
    });

    test('exactly 84-day-old result is fresh (inclusive bound)', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 1, 1),
      );
      final ref = tAt(2026, 1, 1).add(const Duration(days: 84));
      expect(result.isFreshOn(referenceDay: ref), isTrue);
    });

    test('85-day-old result is stale', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 1, 1),
      );
      final ref = tAt(2026, 1, 1).add(const Duration(days: 85));
      expect(result.isFreshOn(referenceDay: ref), isFalse);
    });

    test('future result is stale (defensive)', () {
      final result = TimeTrialResultEntity(
        protocol: TimeTrialProtocol.fiveKm,
        actualDistanceM: 5000,
        actualDurationS: 1200,
        finishedAt: tAt(2026, 5, 1),
      );
      expect(
        result.isFreshOn(referenceDay: tAt(2026, 4, 20)),
        isFalse,
      );
    });
  });

  group('TimeTrialProtocol invariants', () {
    test('3 protocols pinned', () {
      expect(TimeTrialProtocol.values.length, 3);
    });

    test('multipliers never below 1.0 (TT pace is always ≥ threshold)', () {
      for (final p in TimeTrialProtocol.values) {
        expect(p.pacingMultiplier >= 1.0, isTrue,
            reason: '${p.kind} has pacing multiplier < 1.0');
      }
    });

    test('thirtyMinute is duration-based, others are distance-based', () {
      expect(TimeTrialProtocol.thirtyMinute.isDurationBased, isTrue);
      expect(TimeTrialProtocol.thirtyMinute.isDistanceBased, isFalse);
      expect(TimeTrialProtocol.threeKm.isDistanceBased, isTrue);
      expect(TimeTrialProtocol.fiveKm.isDistanceBased, isTrue);
    });

    test('fromKind round-trips every protocol', () {
      for (final p in TimeTrialProtocol.values) {
        expect(TimeTrialProtocol.fromKind(p.kind), p);
      }
    });

    test('fromKind returns null for unknown or null', () {
      expect(TimeTrialProtocol.fromKind(null), isNull);
      expect(TimeTrialProtocol.fromKind(''), isNull);
      expect(TimeTrialProtocol.fromKind('4_km'), isNull);
    });

    test('freshness constant is 84 days', () {
      expect(TimeTrialFreshness.maxAgeDays, 84);
    });
  });
}
