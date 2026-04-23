import 'package:omni_runner/domain/entities/plan_workout_entity.dart';
import 'package:omni_runner/domain/value_objects/workout_completion_status.dart';

/// L23-13 — Pure evaluator that decides whether a workout's feedback
/// is "complete enough" to unblock the coach's next-week prescription.
///
/// Contract
/// --------
///   - Zero platform calls, zero I/O, zero async.
///   - Deterministic: same inputs ⇒ same output, every time.
///   - RPE is sourced from [CompletedWorkoutSummary.perceivedEffort]
///     (integer 1-10). Mood is sourced from
///     [WorkoutFeedbackSummary.mood] (integer 1-5). Both are required
///     to reach [WorkoutCompletionStatus.complete].
///   - Out-of-range values are treated as missing (not "complete with
///     invalid value") — the UI is expected to clamp before submit,
///     but the domain defends against stale/legacy rows.
///
/// See [WorkoutFeedbackBounds] for the canonical ranges, and the
/// runbook for the "why" (the coach uses RPE + mood as the single
/// most-informative signal for the next week's load).
class WorkoutFeedbackEvaluator {
  const WorkoutFeedbackEvaluator();

  WorkoutCompletionStatus evaluate({
    required CompletedWorkoutSummary? completed,
    required WorkoutFeedbackSummary? feedback,
  }) {
    if (completed == null) return WorkoutCompletionStatus.pending;

    final rpe = completed.perceivedEffort;
    final mood = feedback?.mood;

    final rpeValid = rpe != null
        && rpe >= WorkoutFeedbackBounds.rpeMin
        && rpe <= WorkoutFeedbackBounds.rpeMax;
    final moodValid = mood != null
        && mood >= WorkoutFeedbackBounds.moodMin
        && mood <= WorkoutFeedbackBounds.moodMax;

    if (rpeValid && moodValid) return WorkoutCompletionStatus.complete;
    return WorkoutCompletionStatus.partial;
  }

  /// Convenience: reports which specific required fields are missing
  /// for a [WorkoutCompletionStatus.partial] workout. Returns an
  /// empty set for pending or complete statuses.
  Set<WorkoutFeedbackMissingField> missingFields({
    required CompletedWorkoutSummary? completed,
    required WorkoutFeedbackSummary? feedback,
  }) {
    final out = <WorkoutFeedbackMissingField>{};
    if (completed == null) return out;

    final rpe = completed.perceivedEffort;
    final mood = feedback?.mood;

    final rpeValid = rpe != null
        && rpe >= WorkoutFeedbackBounds.rpeMin
        && rpe <= WorkoutFeedbackBounds.rpeMax;
    final moodValid = mood != null
        && mood >= WorkoutFeedbackBounds.moodMin
        && mood <= WorkoutFeedbackBounds.moodMax;

    if (!rpeValid) out.add(WorkoutFeedbackMissingField.rpe);
    if (!moodValid) out.add(WorkoutFeedbackMissingField.mood);

    return out;
  }
}

/// Required fields enumerated for UX messaging ("preenche RPE para
/// liberar a próxima semana").
enum WorkoutFeedbackMissingField { rpe, mood }
