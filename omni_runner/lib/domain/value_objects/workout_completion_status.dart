/// L23-13 — Workout completion status (feedback gate).
///
/// A workout is not considered 100% complete until the athlete has
/// filed *both* RPE (perceived effort, 1-10) and mood (1-5). Rating
/// (of the workout itself, 1-5) and free-text fields stay optional.
///
/// The coach surface consumes this status to:
///   - keep "next week's plan" gated behind complete feedback, so
///     progression decisions use signal, not null.
///   - surface which workouts are blocking the athlete's next cycle.
///
/// This value object is the single source of truth for what "complete
/// feedback" means. CI enforces the RPE + mood requirement via
/// `tools/audit/check-athlete-feedback-gate.ts`.
///
/// See `docs/runbooks/ATHLETE_FEEDBACK_GATE_RUNBOOK.md`.
enum WorkoutCompletionStatus {
  /// Athlete has not filed the execution yet (no CompletedWorkout).
  pending,

  /// Execution filed but RPE and/or mood are missing or out of range.
  /// Coach surface renders this as "aguardando feedback".
  partial,

  /// Execution filed + RPE in [1, 10] + mood in [1, 5].
  complete;

  bool get isTerminal => this == complete;
  bool get blocksCoach => this == pending || this == partial;
}

/// Canonical bounds for required feedback fields.
class WorkoutFeedbackBounds {
  const WorkoutFeedbackBounds._();

  static const int rpeMin = 1;
  static const int rpeMax = 10;

  static const int moodMin = 1;
  static const int moodMax = 5;

  /// Number of consecutive calendar days of feedback required to
  /// unlock the bronze streak badge (L23-13 UX reward).
  static const int bronzeStreakDays = 30;
}
