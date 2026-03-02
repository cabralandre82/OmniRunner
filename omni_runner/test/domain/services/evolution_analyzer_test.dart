import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/services/evolution_analyzer.dart';

void main() {
  const analyzer = EvolutionAnalyzer();

  AthleteBaselineEntity baseline({
    EvolutionMetric metric = EvolutionMetric.avgPace,
    double value = 300,
    int sampleSize = 5,
  }) =>
      AthleteBaselineEntity(
        id: 'b-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: metric,
        value: value,
        sampleSize: sampleSize,
        windowStartMs: 0,
        windowEndMs: 1000000,
        computedAtMs: 1000000,
      );

  List<PeriodDataPoint> periods(List<double> values) => values
      .asMap()
      .entries
      .map((e) => PeriodDataPoint(
            periodKey: '2026-W${(e.key + 1).toString().padLeft(2, '0')}',
            value: e.value,
          ))
      .toList();

  group('EvolutionAnalyzer', () {
    test('returns insufficient when fewer data points than minimum', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(),
        recentPeriods: periods([290]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.insufficient);
    });

    test('returns insufficient when baseline is unreliable (sampleSize < 3)', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(sampleSize: 2),
        recentPeriods: periods([290, 285]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.insufficient);
    });

    test('returns insufficient when baseline value is zero', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(value: 0),
        recentPeriods: periods([290, 285]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.insufficient);
    });

    test('avgPace improving when current is lower (faster)', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(value: 300),
        recentPeriods: periods([295, 270]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.improving);
      expect(result.changePercent, -10.0);
      expect(result.currentValue, 270);
    });

    test('avgPace declining when current is higher (slower)', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(value: 300),
        recentPeriods: periods([310, 330]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.declining);
      expect(result.changePercent, 10.0);
    });

    test('weeklyVolume improving when current is higher', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.weeklyVolume,
        period: EvolutionPeriod.weekly,
        baseline: baseline(metric: EvolutionMetric.weeklyVolume, value: 20000),
        recentPeriods: periods([22000, 24000]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.improving);
      expect(result.changePercent, 20.0);
    });

    test('stable when change is within threshold', () {
      final result = analyzer.analyze(
        id: 't-1',
        userId: 'u-1',
        groupId: 'g-1',
        metric: EvolutionMetric.avgPace,
        period: EvolutionPeriod.weekly,
        baseline: baseline(value: 300),
        recentPeriods: periods([298, 303]),
        nowMs: 2000000,
      );
      expect(result.direction, TrendDirection.stable);
      expect(result.changePercent, 1.0);
    });

    test('findSignificantDrops filters declining trends above threshold', () {
      final trends = [
        analyzer.analyze(
          id: 't-drop',
          userId: 'u-1',
          groupId: 'g-1',
          metric: EvolutionMetric.weeklyVolume,
          period: EvolutionPeriod.weekly,
          baseline: baseline(metric: EvolutionMetric.weeklyVolume, value: 20000),
          recentPeriods: periods([18000, 16000]),
          nowMs: 2000000,
        ),
        analyzer.analyze(
          id: 't-stable',
          userId: 'u-1',
          groupId: 'g-1',
          metric: EvolutionMetric.avgPace,
          period: EvolutionPeriod.weekly,
          baseline: baseline(value: 300),
          recentPeriods: periods([298, 303]),
          nowMs: 2000000,
        ),
      ];

      final drops = analyzer.findSignificantDrops(trends);
      expect(drops.length, 1);
      expect(drops.first.id, 't-drop');
    });

    test('findImprovements filters improving trends', () {
      final trends = [
        analyzer.analyze(
          id: 't-improving',
          userId: 'u-1',
          groupId: 'g-1',
          metric: EvolutionMetric.avgPace,
          period: EvolutionPeriod.weekly,
          baseline: baseline(value: 300),
          recentPeriods: periods([280, 270]),
          nowMs: 2000000,
        ),
        analyzer.analyze(
          id: 't-declining',
          userId: 'u-1',
          groupId: 'g-1',
          metric: EvolutionMetric.weeklyVolume,
          period: EvolutionPeriod.weekly,
          baseline: baseline(metric: EvolutionMetric.weeklyVolume, value: 20000),
          recentPeriods: periods([18000, 16000]),
          nowMs: 2000000,
        ),
      ];

      final improvements = analyzer.findImprovements(trends);
      expect(improvements.length, 1);
      expect(improvements.first.id, 't-improving');
    });

    test('analyzeAll handles missing baselines as insufficient', () {
      final results = analyzer.analyzeAll(
        userId: 'u-1',
        groupId: 'g-1',
        period: EvolutionPeriod.weekly,
        baselines: {},
        periodData: {},
        nowMs: 2000000,
        idGenerator: (m) => 'id-${m.name}',
      );

      expect(results.length, EvolutionMetric.values.length);
      for (final r in results) {
        expect(r.direction, TrendDirection.insufficient);
      }
    });
  });
}
