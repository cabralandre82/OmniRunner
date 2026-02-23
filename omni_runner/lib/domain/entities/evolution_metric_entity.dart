/// Metric tracked by the Evolution Analytics Engine.
///
/// Distinct from [CoachingRankingMetric] — evolution metrics focus on
/// per-athlete temporal trends rather than group-wide ranking position.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum EvolutionMetric {
  /// Average pace in sec/km across sessions in a window (lower = faster).
  avgPace,

  /// Average distance in meters per session.
  avgDistance,

  /// Total distance in meters per week.
  weeklyVolume,

  /// Number of sessions per week.
  weeklyFrequency,

  /// Average heart rate in BPM (null-safe: only sessions with HR data).
  avgHeartRate,

  /// Average moving time in milliseconds per session.
  avgMovingTime,
}

/// Granularity of the evolution analysis window.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum EvolutionPeriod {
  /// Week-over-week comparison.
  weekly,

  /// Month-over-month comparison.
  monthly,
}
