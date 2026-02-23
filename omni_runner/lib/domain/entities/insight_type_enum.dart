/// Category of an automatic coach insight.
///
/// Each value represents a distinct detection rule in the Insight Generator
/// Engine. Used by [CoachInsightEntity] and the `GenerateCoachInsights`
/// use case to classify what triggered the insight.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum InsightType {
  /// An athlete's metric is declining beyond the significant-drop threshold.
  performanceDecline,

  /// An athlete's metric is improving consistently.
  performanceImprovement,

  /// An athlete's training frequency dropped below their baseline.
  consistencyDrop,

  /// An athlete has not logged any session for an extended period.
  inactivityWarning,

  /// An athlete achieved a new personal record in a metric.
  personalRecord,

  /// An athlete's weekly volume spiked well above baseline — injury risk.
  overtrainingRisk,

  /// An athlete's current metrics suggest readiness for a registered race target.
  raceReady,

  /// Periodic summary of group-wide trend distribution (improving / stable / declining).
  groupTrendSummary,

  /// An athlete hit a milestone in an active race event (e.g. 50%, 75% of target).
  eventMilestone,

  /// An athlete's ranking position changed significantly between periods.
  rankingChange,
}

/// Urgency / severity of a coach insight.
///
/// Determines sort order and visual treatment in the coach dashboard.
///
/// Append-only ordinal rule (DECISAO 018): new values at the end only.
enum InsightPriority {
  /// Informational — no action required.
  low,

  /// Noteworthy — the coach may want to review.
  medium,

  /// Actionable — the coach should review soon.
  high,

  /// Urgent — immediate attention recommended (e.g. overtraining risk).
  critical,
}
