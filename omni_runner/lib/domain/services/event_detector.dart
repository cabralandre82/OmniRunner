import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/domain/entities/race_participation_entity.dart';

/// Lightweight projection of a completed workout session for event detection.
///
/// The caller maps from [WorkoutSessionEntity] / Isar records to this DTO,
/// so the detector stays free of persistence and entity coupling.
final class DetectableSession {
  final String sessionId;
  final String userId;

  /// Session start time (ms since epoch, UTC).
  final int startTimeMs;

  /// Session end time (ms since epoch, UTC).
  final int endTimeMs;

  /// Total verified distance in meters.
  final double distanceM;

  /// Moving time in milliseconds (excludes pauses).
  final int movingMs;

  /// Average pace in sec/km. Null if zero distance.
  final double? avgPaceSecPerKm;

  /// Whether the session passed integrity checks.
  final bool isVerified;

  const DetectableSession({
    required this.sessionId,
    required this.userId,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.distanceM,
    required this.movingMs,
    this.avgPaceSecPerKm,
    this.isVerified = true,
  });
}

/// A detected match between a completed session and a race event.
///
/// Contains the event, the athlete's existing participation (if enrolled),
/// and the updated participation with the session's contribution applied.
final class RaceEventMatch {
  final RaceEventEntity event;

  /// The athlete's existing participation before this session.
  /// Null if the athlete was not enrolled (auto-enroll candidates).
  final RaceParticipationEntity? existingParticipation;

  /// Participation with the session's contribution applied.
  final RaceParticipationEntity updatedParticipation;

  /// Whether this session triggered target completion.
  final bool newlyCompleted;

  const RaceEventMatch({
    required this.event,
    required this.existingParticipation,
    required this.updatedParticipation,
    required this.newlyCompleted,
  });
}

/// Pure, stateless service that detects when a workout session coincides
/// with registered race events and computes updated participation values.
///
/// No I/O, no repos — takes pre-fetched data in, returns matches out.
///
/// Detection rules:
/// - Event must be **active** (`RaceEventStatus.active`)
/// - Session start must fall within the event window `[startsAtMs, endsAtMs]`
/// - Session must be **verified** (`isVerified == true`)
/// - Session must not have already contributed (dedup via `contributingSessionIds`)
/// - Athlete must be enrolled (has a participation record)
///
/// The caller is responsible for fetching events and participations from repos,
/// and persisting the updated participations returned in [RaceEventMatch].
final class EventDetector {
  const EventDetector();

  /// Detect all race events that match the given session.
  ///
  /// [activeEvents] should contain only events with status `active`.
  /// [participations] maps each event ID to the user's participation (if any).
  ///
  /// Returns an empty list if the session is unverified or no matches are found.
  List<RaceEventMatch> detect({
    required DetectableSession session,
    required List<RaceEventEntity> activeEvents,
    required Map<String, RaceParticipationEntity> participations,
  }) {
    if (!session.isVerified) return const [];

    final matches = <RaceEventMatch>[];

    for (final event in activeEvents) {
      if (!_sessionFallsWithinEvent(session, event)) continue;

      final participation = participations[event.id];
      if (participation == null) continue;
      if (participation.hasSession(session.sessionId)) continue;

      final updated = _applySession(session, participation, event);
      final wasCompleted = participation.completed;
      final nowCompleted = updated.completed;

      matches.add(RaceEventMatch(
        event: event,
        existingParticipation: participation,
        updatedParticipation: updated,
        newlyCompleted: !wasCompleted && nowCompleted,
      ));
    }

    return matches;
  }

  /// Check if the session's start time falls within the event window.
  bool _sessionFallsWithinEvent(
    DetectableSession session,
    RaceEventEntity event,
  ) {
    return session.startTimeMs >= event.startsAtMs &&
        session.startTimeMs <= event.endsAtMs;
  }

  /// Apply the session's metrics to the existing participation.
  RaceParticipationEntity _applySession(
    DetectableSession session,
    RaceParticipationEntity participation,
    RaceEventEntity event,
  ) {
    final newDistance = participation.totalDistanceM + session.distanceM;
    final newMovingMs = participation.totalMovingMs + session.movingMs;
    final newCount = participation.contributingSessionCount + 1;
    final newSessionIds = [
      ...participation.contributingSessionIds,
      session.sessionId,
    ];

    final newPace = _bestPace(
      participation.bestPaceSecPerKm,
      session.avgPaceSecPerKm,
    );

    final wasCompleted = participation.completed;
    final targetReached = !wasCompleted &&
        event.targetDistanceM != null &&
        newDistance >= event.targetDistanceM!;

    return participation.copyWith(
      totalDistanceM: newDistance,
      totalMovingMs: newMovingMs,
      bestPaceSecPerKm: newPace,
      contributingSessionCount: newCount,
      contributingSessionIds: newSessionIds,
      completed: wasCompleted || targetReached,
      completedAtMs:
          targetReached ? session.endTimeMs : participation.completedAtMs,
    );
  }

  /// Return the better (lower) pace between existing and new.
  /// Null if neither has pace data.
  double? _bestPace(double? existing, double? incoming) {
    if (existing == null) return incoming;
    if (incoming == null) return existing;
    return existing < incoming ? existing : incoming;
  }
}
