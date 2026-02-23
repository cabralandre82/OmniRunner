/// Metric used to rank athletes within a coaching group.
///
/// Distinct from social [LeaderboardMetric] — coaching rankings focus on
/// training-relevant metrics that a coach monitors.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum CoachingRankingMetric {
  /// Total verified distance in meters over the ranking period.
  volumeDistance,

  /// Total moving time in milliseconds over the ranking period.
  totalTime,

  /// Best (lowest) average pace in sec/km among verified sessions.
  bestPace,

  /// Number of distinct calendar days with at least one verified session.
  consistencyDays,
}
