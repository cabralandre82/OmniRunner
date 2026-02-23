import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';

/// Submits a verified workout session to all active events the user is in.
///
/// For each active event:
/// 1. Extracts the metric value from the session.
/// 2. Adds it to the participant's [currentValue].
/// 3. Checks if the target has been reached → marks [completed].
///
/// Only verified sessions count. Same session can contribute to multiple events.
/// Idempotent: skips events where the session was already counted
/// (checked via [contributingSessionCount] — future: session ID list).
///
/// See `docs/SOCIAL_SPEC.md` §5.5.
final class SubmitWorkoutToEvent {
  final IEventRepo _eventRepo;

  const SubmitWorkoutToEvent({required IEventRepo eventRepo})
      : _eventRepo = eventRepo;

  /// Returns the list of updated participations.
  Future<List<EventParticipationEntity>> call({
    required WorkoutSessionEntity session,
    required double totalDistanceM,
    required int movingMs,
    required int nowMs,
  }) async {
    if (!session.isVerified) return const [];

    final userId = session.userId;
    if (userId == null || userId.isEmpty) return const [];

    final participations = await _eventRepo.getParticipationsByUser(userId);
    final results = <EventParticipationEntity>[];

    final sessionId = session.id;

    for (final participation in participations) {
      if (participation.completed || participation.rewardsClaimed) continue;
      if (participation.hasSession(sessionId)) continue;

      final event = await _eventRepo.getEventById(participation.eventId);
      if (event == null) continue;
      if (!event.isActive(nowMs)) continue;

      final delta = _extractMetricValue(event.metric, totalDistanceM, movingMs);
      if (delta <= 0) continue;

      final newValue = participation.currentValue + delta;
      final reachedTarget = event.targetValue != null &&
          newValue >= event.targetValue!;

      final updated = participation.copyWith(
        currentValue: newValue,
        completed: reachedTarget || participation.completed,
        completedAtMs: reachedTarget && participation.completedAtMs == null
            ? nowMs
            : null,
        contributingSessionCount: participation.contributingSessionCount + 1,
        contributingSessionIds: [
          ...participation.contributingSessionIds,
          sessionId,
        ],
      );

      await _eventRepo.updateParticipation(updated);
      results.add(updated);
    }

    return results;
  }

  static double _extractMetricValue(
    GoalMetric metric,
    double totalDistanceM,
    int movingMs,
  ) =>
      switch (metric) {
        GoalMetric.distance => totalDistanceM,
        GoalMetric.sessions => 1.0,
        GoalMetric.movingTime => movingMs.toDouble(),
      };
}
