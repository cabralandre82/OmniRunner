import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

/// A single period's aggregated metric value in a time series.
///
/// The caller pre-aggregates session data into one value per period
/// (e.g. average pace of all sessions in week W08).
final class PeriodDataPoint {
  /// Human-readable period key, e.g. "2026-W08" or "2026-02".
  final String periodKey;

  /// Aggregated metric value for this period.
  final double value;

  /// Number of sessions that contributed to [value].
  final int sessionCount;

  const PeriodDataPoint({
    required this.periodKey,
    required this.value,
    this.sessionCount = 0,
  });
}

/// Pure, stateless evolution analyzer for the coaching analytics engine.
///
/// No I/O, no repos — takes baselines and period data in, returns trends out.
///
/// Analysis rules:
/// - **changePercent**: `(current - baseline) / baseline × 100` (signed)
/// - **Stable threshold**: ±[stableThresholdPercent] (default 5%)
/// - **Significant drop threshold**: ≤ -[significantDropPercent] (default 15%)
/// - **Direction for lower-is-better** (avgPace): negative change = improving
/// - **Direction for higher-is-better** (all others): positive change = improving
/// - **Insufficient**: baseline is zero, unreliable, or fewer than [minDataPoints] periods
final class EvolutionAnalyzer {
  /// Percentage threshold within which a metric is considered stable.
  final double stableThresholdPercent;

  /// Percentage drop (negative direction) that qualifies as significant.
  final double significantDropPercent;

  /// Minimum number of period data points required for a valid trend.
  final int minDataPoints;

  const EvolutionAnalyzer({
    this.stableThresholdPercent = 5.0,
    this.significantDropPercent = 15.0,
    this.minDataPoints = 2,
  });

  /// Analyze a single metric's trend.
  ///
  /// [baseline] is the reference snapshot.
  /// [recentPeriods] is the time series ordered chronologically (oldest first).
  /// The most recent entry becomes [AthleteTrendEntity.currentValue].
  AthleteTrendEntity analyze({
    required String id,
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
    required EvolutionPeriod period,
    required AthleteBaselineEntity baseline,
    required List<PeriodDataPoint> recentPeriods,
    required int nowMs,
  }) {
    if (recentPeriods.length < minDataPoints ||
        !baseline.isReliable ||
        baseline.value == 0) {
      return AthleteTrendEntity(
        id: id,
        userId: userId,
        groupId: groupId,
        metric: metric,
        period: period,
        direction: TrendDirection.insufficient,
        currentValue: recentPeriods.isEmpty ? 0 : recentPeriods.last.value,
        baselineValue: baseline.value,
        changePercent: 0,
        dataPoints: recentPeriods.length,
        latestPeriodKey:
            recentPeriods.isEmpty ? '' : recentPeriods.last.periodKey,
        analyzedAtMs: nowMs,
      );
    }

    final current = recentPeriods.last.value;
    final change = _changePercent(current, baseline.value);
    final direction = _direction(metric, change);

    return AthleteTrendEntity(
      id: id,
      userId: userId,
      groupId: groupId,
      metric: metric,
      period: period,
      direction: direction,
      currentValue: current,
      baselineValue: baseline.value,
      changePercent: change,
      dataPoints: recentPeriods.length,
      latestPeriodKey: recentPeriods.last.periodKey,
      analyzedAtMs: nowMs,
    );
  }

  /// Analyze all 6 evolution metrics at once.
  ///
  /// [baselines] and [periodData] are keyed by [EvolutionMetric].
  /// Missing entries produce [TrendDirection.insufficient].
  List<AthleteTrendEntity> analyzeAll({
    required String userId,
    required String groupId,
    required EvolutionPeriod period,
    required Map<EvolutionMetric, AthleteBaselineEntity> baselines,
    required Map<EvolutionMetric, List<PeriodDataPoint>> periodData,
    required int nowMs,
    required String Function(EvolutionMetric metric) idGenerator,
  }) {
    return EvolutionMetric.values.map((m) {
      final baseline = baselines[m];
      final periods = periodData[m] ?? const [];

      if (baseline == null) {
        return AthleteTrendEntity(
          id: idGenerator(m),
          userId: userId,
          groupId: groupId,
          metric: m,
          period: period,
          direction: TrendDirection.insufficient,
          currentValue: periods.isEmpty ? 0 : periods.last.value,
          baselineValue: 0,
          changePercent: 0,
          dataPoints: periods.length,
          latestPeriodKey: periods.isEmpty ? '' : periods.last.periodKey,
          analyzedAtMs: nowMs,
        );
      }

      return analyze(
        id: idGenerator(m),
        userId: userId,
        groupId: groupId,
        metric: m,
        period: period,
        baseline: baseline,
        recentPeriods: periods,
        nowMs: nowMs,
      );
    }).toList();
  }

  /// Filter trends that represent a significant performance drop.
  ///
  /// Useful for generating coach alerts.
  List<AthleteTrendEntity> findSignificantDrops(
    List<AthleteTrendEntity> trends,
  ) {
    return trends.where((t) {
      if (t.direction != TrendDirection.declining) return false;
      return t.absoluteChange >= significantDropPercent;
    }).toList();
  }

  /// Filter trends that are actively improving beyond the stable band.
  List<AthleteTrendEntity> findImprovements(
    List<AthleteTrendEntity> trends,
  ) {
    return trends
        .where((t) => t.direction == TrendDirection.improving)
        .toList();
  }

  // ── Internal ──

  static double _changePercent(double current, double baseline) {
    if (baseline == 0) return 0;
    return (current - baseline) / baseline * 100;
  }

  TrendDirection _direction(EvolutionMetric metric, double changePercent) {
    final isLowerBetter = metric == EvolutionMetric.avgPace;
    final absChange = changePercent.abs();

    if (absChange <= stableThresholdPercent) return TrendDirection.stable;

    if (isLowerBetter) {
      return changePercent < 0
          ? TrendDirection.improving
          : TrendDirection.declining;
    } else {
      return changePercent > 0
          ? TrendDirection.improving
          : TrendDirection.declining;
    }
  }
}
