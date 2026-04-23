import 'package:omni_runner/domain/value_objects/time_trial_protocol.dart';

/// L23-14 — Pure scheduler that turns a coach's "let's retest" intent
/// into a deterministic plan-workout payload.
///
/// The actual DB insert lives in the training-plan repo (follow-up
/// L23-14-repo). This service is the pure primitive both the UI
/// wizard and the repo consume to guarantee identical payload shape.
///
/// Rules
/// -----
///   - Scheduled date is quantised to the athlete's local calendar
///     day by passing an already-normalized [scheduledOn] UTC-day
///     `DateTime`. The scheduler does NOT try to infer timezone —
///     that's the presenter's job.
///   - A TT payload always carries `cycleType = 'test'` (matches the
///     existing `training_plan_weeks.cycle_type` enum from the
///     periodization migration, which includes `test`) and a
///     `time_trial_kind` field equal to [TimeTrialProtocol.kind].
///   - The payload does NOT write to the DB here — a follow-up repo
///     issue will persist it via the existing
///     `ITrainingPlanRepo.scheduleWorkout` path, after L21-05 lands.
class TimeTrialScheduler {
  const TimeTrialScheduler();

  TimeTrialScheduledWorkout schedule({
    required TimeTrialProtocol protocol,
    required DateTime scheduledOn,
    required String planId,
    String? coachNote,
  }) {
    if (planId.isEmpty) {
      throw ArgumentError.value(planId, 'planId', 'must be non-empty');
    }

    final normalised = _asUtcDay(scheduledOn);
    final title = _defaultTitle(protocol);
    final description = _defaultDescription(protocol);

    return TimeTrialScheduledWorkout(
      planId: planId,
      scheduledOn: normalised,
      protocol: protocol,
      cycleType: 'test',
      title: title,
      description: description,
      targetDistanceM: protocol.distanceM,
      targetDurationS: protocol.durationS,
      coachNote: coachNote,
    );
  }

  static String _defaultTitle(TimeTrialProtocol p) {
    switch (p) {
      case TimeTrialProtocol.threeKm:
        return 'Time trial 3 km';
      case TimeTrialProtocol.fiveKm:
        return 'Time trial 5 km';
      case TimeTrialProtocol.thirtyMinute:
        return 'Tempo trial 30 min';
    }
  }

  static String _defaultDescription(TimeTrialProtocol p) {
    const warmup = 'Aquecimento 15 min fácil + 4×100m';
    const cooldown = 'Volta à calma 10 min muito fácil';
    switch (p) {
      case TimeTrialProtocol.threeKm:
        return '$warmup. Corrida all-out 3 km. $cooldown.';
      case TimeTrialProtocol.fiveKm:
        return '$warmup. Corrida all-out 5 km. $cooldown.';
      case TimeTrialProtocol.thirtyMinute:
        return '$warmup. Corrida 30 min ritmo constante mais forte '
            'sustentável. $cooldown.';
    }
  }

  static DateTime _asUtcDay(DateTime d) {
    final utc = d.isUtc ? d : d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}

/// Deterministic payload the scheduler produces. The repo maps this
/// to the existing `plan_workouts` row contract.
class TimeTrialScheduledWorkout {
  const TimeTrialScheduledWorkout({
    required this.planId,
    required this.scheduledOn,
    required this.protocol,
    required this.cycleType,
    required this.title,
    required this.description,
    required this.targetDistanceM,
    required this.targetDurationS,
    required this.coachNote,
  });

  final String planId;
  final DateTime scheduledOn;
  final TimeTrialProtocol protocol;
  final String cycleType;
  final String title;
  final String description;
  final int? targetDistanceM;
  final int? targetDurationS;
  final String? coachNote;

  Map<String, Object?> toPlanWorkoutPayload() => {
        'plan_id': planId,
        'scheduled_on': scheduledOn.toIso8601String(),
        'cycle_type': cycleType,
        'title': title,
        'description': description,
        'time_trial_kind': protocol.kind,
        'target_distance_m': targetDistanceM,
        'target_duration_s': targetDurationS,
        if (coachNote != null) 'coach_note': coachNote,
      };
}
