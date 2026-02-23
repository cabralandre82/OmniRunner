import 'package:omni_runner/core/errors/social_failures.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';
import 'package:omni_runner/domain/repositories/i_event_repo.dart';

/// Enrolls a user in a virtual running event.
///
/// Validates:
/// - Event exists and is [EventStatus.upcoming] or [EventStatus.active].
/// - User has not already joined.
/// - Event is not full (if maxParticipants is set).
/// - User is not in more than 5 simultaneous active events.
///
/// Throws [SocialFailure] on validation error.
/// See `docs/SOCIAL_SPEC.md` §5.5.
final class JoinEvent {
  final IEventRepo _eventRepo;

  static const _maxSimultaneousEvents = 5;

  const JoinEvent({required IEventRepo eventRepo})
      : _eventRepo = eventRepo;

  Future<EventParticipationEntity> call({
    required String eventId,
    required String userId,
    required String displayName,
    required String Function() uuidGenerator,
    required int nowMs,
  }) async {
    final event = await _eventRepo.getEventById(eventId);
    if (event == null) throw EventNotFound(eventId);

    if (event.status != EventStatus.upcoming &&
        event.status != EventStatus.active) {
      throw InvalidEventStatus(
        eventId,
        '${EventStatus.upcoming.name} or ${EventStatus.active.name}',
        event.status.name,
      );
    }

    final existing = await _eventRepo.getParticipation(eventId, userId);
    if (existing != null) {
      throw AlreadyJoinedEvent(userId, eventId);
    }

    if (event.maxParticipants != null) {
      final count = await _eventRepo.countParticipants(eventId);
      if (count >= event.maxParticipants!) {
        throw EventFull(eventId, event.maxParticipants!);
      }
    }

    final activeEvents = await _eventRepo.getParticipationsByUser(userId);
    final activeCount = activeEvents
        .where((p) => !p.completed && !p.rewardsClaimed)
        .length;
    if (activeCount >= _maxSimultaneousEvents) {
      throw const EventLimitReached(_maxSimultaneousEvents);
    }

    final participation = EventParticipationEntity(
      id: uuidGenerator(),
      eventId: eventId,
      userId: userId,
      displayName: displayName,
      joinedAtMs: nowMs,
    );

    await _eventRepo.saveParticipation(participation);
    return participation;
  }
}
