import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/event_participation_entity.dart';

/// Contract for persisting and retrieving events and participations.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class IEventRepo {
  // ── Events ──

  Future<void> saveEvent(EventEntity event);

  Future<void> updateEvent(EventEntity event);

  Future<EventEntity?> getEventById(String id);

  /// All events the user is participating in.
  Future<List<EventEntity>> getEventsByUserId(String userId);

  /// Events with the given status.
  Future<List<EventEntity>> getEventsByStatus(EventStatus status);

  // ── Participations ──

  Future<void> saveParticipation(EventParticipationEntity participation);

  Future<void> updateParticipation(EventParticipationEntity participation);

  Future<EventParticipationEntity?> getParticipation(
      String eventId, String userId);

  /// All participations for an event.
  Future<List<EventParticipationEntity>> getParticipationsByEvent(
      String eventId);

  /// All participations for a user.
  Future<List<EventParticipationEntity>> getParticipationsByUser(
      String userId);

  Future<int> countParticipants(String eventId);
}
