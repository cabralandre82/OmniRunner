import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';

/// Result of evaluating (settling) a completed event.
final class EventEvaluationResult {
  /// Participations eligible for completion rewards.
  final List<EventParticipationEntity> completers;

  /// Participations eligible for participation-only rewards (≥ 1 session).
  final List<EventParticipationEntity> participants;

  /// Ranked list of all participations (highest value first).
  final List<EventParticipationEntity> ranked;

  const EventEvaluationResult({
    this.completers = const [],
    this.participants = const [],
    this.ranked = const [],
  });
}

/// Evaluates a finished event: computes final rankings and identifies
/// completers vs. participants for reward distribution.
///
/// Called after [EventEntity.endsAtMs] has elapsed.
/// Transitions event status to [EventStatus.completed].
/// Assigns final [rank] to each participation.
///
/// Idempotent: if event is already [EventStatus.completed], returns
/// the existing state without modifications.
///
/// Throws [SocialFailure] if event not found.
/// See `docs/SOCIAL_SPEC.md` §5.3, §5.5.
final class EvaluateEvent {
  final IEventRepo _eventRepo;

  const EvaluateEvent({required IEventRepo eventRepo})
      : _eventRepo = eventRepo;

  Future<EventEvaluationResult> call({
    required String eventId,
    required int nowMs,
  }) async {
    final event = await _eventRepo.getEventById(eventId);
    if (event == null) throw EventNotFound(eventId);

    if (event.status == EventStatus.completed) {
      return _buildResult(event, await _loadRanked(eventId));
    }

    if (!event.hasEnded(nowMs)) {
      throw InvalidEventStatus(
        eventId,
        'past endsAtMs',
        'endsAtMs=${event.endsAtMs}, nowMs=$nowMs (${event.status.name})',
      );
    }

    final participations = await _eventRepo.getParticipationsByEvent(eventId);

    // Sort by value descending (higher is better for all metrics).
    final sorted = List<EventParticipationEntity>.of(participations)
      ..sort((a, b) => b.currentValue.compareTo(a.currentValue));

    // Assign ranks — ties share rank, next rank skips.
    final ranked = <EventParticipationEntity>[];
    int currentRank = 0;
    double lastValue = double.negativeInfinity;
    int skipped = 0;

    for (final p in sorted) {
      if (p.contributingSessionCount == 0) {
        ranked.add(p.copyWith(rank: 0));
        continue;
      }

      if (p.currentValue != lastValue) {
        currentRank += 1 + skipped;
        skipped = 0;
      } else {
        skipped++;
      }
      lastValue = p.currentValue;
      ranked.add(p.copyWith(rank: currentRank));
    }

    // Persist ranked participations.
    for (final p in ranked) {
      await _eventRepo.updateParticipation(p);
    }

    // Transition event to completed.
    await _eventRepo.updateEvent(
      event.copyWith(status: EventStatus.completed),
    );

    return _buildResult(event, ranked);
  }

  Future<List<EventParticipationEntity>> _loadRanked(String eventId) async {
    final all = await _eventRepo.getParticipationsByEvent(eventId);
    return List<EventParticipationEntity>.of(all)
      ..sort((a, b) => (a.rank ?? 999).compareTo(b.rank ?? 999));
  }

  static EventEvaluationResult _buildResult(
    EventEntity event,
    List<EventParticipationEntity> ranked,
  ) {
    final completers = ranked.where((p) => p.completed).toList();
    final participants = ranked
        .where((p) => p.contributingSessionCount > 0 && !p.completed)
        .toList();

    return EventEvaluationResult(
      completers: completers,
      participants: participants,
      ranked: ranked,
    );
  }
}
