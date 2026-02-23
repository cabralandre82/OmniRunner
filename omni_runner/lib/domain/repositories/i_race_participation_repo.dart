import 'package:omni_runner/domain/entities/race_participation_entity.dart';

/// Contract for persisting coaching race event participations.
abstract interface class IRaceParticipationRepo {
  Future<void> save(RaceParticipationEntity participation);
  Future<void> update(RaceParticipationEntity participation);
  Future<RaceParticipationEntity?> getById(String id);

  /// Retrieve a specific user's participation in a race event.
  Future<RaceParticipationEntity?> getByEventAndUser({
    required String raceEventId,
    required String userId,
  });

  Future<List<RaceParticipationEntity>> getByEventId(String raceEventId);
  Future<List<RaceParticipationEntity>> getByUserId(String userId);
  Future<int> countByEventId(String raceEventId);

  /// Batch count: returns {eventId → participantCount} for each given event.
  Future<Map<String, int>> countByEventIds(Set<String> raceEventIds);

  Future<void> deleteById(String id);
}
