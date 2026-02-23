import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

/// Lightweight projection of a workout session for baseline computation.
///
/// Extends the ranking DTO concept with heart-rate data needed by the
/// Evolution Analytics Engine. The caller maps from persistence records.
final class BaselineSession {
  /// Total verified distance in meters.
  final double distanceM;

  /// Moving time in milliseconds (excludes pauses).
  final int movingMs;

  /// Average pace in sec/km. Null if zero distance.
  final double? avgPaceSecPerKm;

  /// Average heart rate in BPM. Null if no HR sensor was used.
  final int? avgBpm;

  /// Session start time (ms since epoch, UTC).
  final int startTimeMs;

  const BaselineSession({
    required this.distanceM,
    required this.movingMs,
    this.avgPaceSecPerKm,
    this.avgBpm,
    required this.startTimeMs,
  });
}

/// Pure, stateless baseline calculator for the Evolution Analytics Engine.
///
/// No I/O, no repos — takes pre-fetched sessions in, returns baselines out.
///
/// Computes one [AthleteBaselineEntity] per [EvolutionMetric] from the
/// provided session window.
///
/// Computation rules:
/// - **avgPace**: arithmetic mean of non-null `avgPaceSecPerKm`
/// - **avgDistance**: arithmetic mean of `distanceM`
/// - **weeklyVolume**: total `distanceM` / weeks in window
/// - **weeklyFrequency**: session count / weeks in window
/// - **avgHeartRate**: arithmetic mean of non-null `avgBpm`
/// - **avgMovingTime**: arithmetic mean of `movingMs`
///
/// Metrics with zero qualifying data points produce `value = 0`.
final class BaselineCalculator {
  const BaselineCalculator();

  /// Compute baselines for all [EvolutionMetric] values.
  ///
  /// [sessions] must fall within [windowStartMs]..[windowEndMs].
  /// Returns one [AthleteBaselineEntity] per metric (6 total).
  List<AthleteBaselineEntity> computeAll({
    required String userId,
    required String groupId,
    required List<BaselineSession> sessions,
    required int windowStartMs,
    required int windowEndMs,
    required int nowMs,
    required String Function(EvolutionMetric metric) idGenerator,
  }) {
    final weeks = _weeksBetween(windowStartMs, windowEndMs);

    return EvolutionMetric.values
        .map((m) => AthleteBaselineEntity(
              id: idGenerator(m),
              userId: userId,
              groupId: groupId,
              metric: m,
              value: _compute(m, sessions, weeks),
              sampleSize: _sampleSize(m, sessions),
              windowStartMs: windowStartMs,
              windowEndMs: windowEndMs,
              computedAtMs: nowMs,
            ))
        .toList();
  }

  /// Compute baseline for a single metric.
  AthleteBaselineEntity compute({
    required String id,
    required String userId,
    required String groupId,
    required EvolutionMetric metric,
    required List<BaselineSession> sessions,
    required int windowStartMs,
    required int windowEndMs,
    required int nowMs,
  }) {
    final weeks = _weeksBetween(windowStartMs, windowEndMs);
    return AthleteBaselineEntity(
      id: id,
      userId: userId,
      groupId: groupId,
      metric: metric,
      value: _compute(metric, sessions, weeks),
      sampleSize: _sampleSize(metric, sessions),
      windowStartMs: windowStartMs,
      windowEndMs: windowEndMs,
      computedAtMs: nowMs,
    );
  }

  // ── Metric computation ──

  double _compute(
    EvolutionMetric metric,
    List<BaselineSession> sessions,
    double weeks,
  ) {
    if (sessions.isEmpty) return 0;

    switch (metric) {
      case EvolutionMetric.avgPace:
        final paces = sessions
            .where((s) => s.avgPaceSecPerKm != null && s.avgPaceSecPerKm! > 0)
            .map((s) => s.avgPaceSecPerKm!)
            .toList();
        return paces.isEmpty ? 0 : _mean(paces);

      case EvolutionMetric.avgDistance:
        return _mean(sessions.map((s) => s.distanceM).toList());

      case EvolutionMetric.weeklyVolume:
        if (weeks <= 0) return 0;
        final total = sessions.fold(0.0, (sum, s) => sum + s.distanceM);
        return total / weeks;

      case EvolutionMetric.weeklyFrequency:
        if (weeks <= 0) return 0;
        return sessions.length / weeks;

      case EvolutionMetric.avgHeartRate:
        final hrs = sessions
            .where((s) => s.avgBpm != null && s.avgBpm! > 0)
            .map((s) => s.avgBpm!.toDouble())
            .toList();
        return hrs.isEmpty ? 0 : _mean(hrs);

      case EvolutionMetric.avgMovingTime:
        return _mean(sessions.map((s) => s.movingMs.toDouble()).toList());
    }
  }

  int _sampleSize(EvolutionMetric metric, List<BaselineSession> sessions) {
    switch (metric) {
      case EvolutionMetric.avgPace:
        return sessions
            .where((s) => s.avgPaceSecPerKm != null && s.avgPaceSecPerKm! > 0)
            .length;
      case EvolutionMetric.avgHeartRate:
        return sessions
            .where((s) => s.avgBpm != null && s.avgBpm! > 0)
            .length;
      case EvolutionMetric.avgDistance:
      case EvolutionMetric.weeklyVolume:
      case EvolutionMetric.weeklyFrequency:
      case EvolutionMetric.avgMovingTime:
        return sessions.length;
    }
  }

  // ── Helpers ──

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// Number of full or partial weeks between two timestamps.
  /// Minimum 1 to avoid division by zero.
  static double _weeksBetween(int startMs, int endMs) {
    final diffMs = endMs - startMs;
    if (diffMs <= 0) return 1;
    const msPerWeek = 7 * 24 * 60 * 60 * 1000;
    final weeks = diffMs / msPerWeek;
    return weeks < 1 ? 1 : weeks;
  }
}
