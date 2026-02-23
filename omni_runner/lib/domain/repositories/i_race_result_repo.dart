import 'package:omni_runner/domain/entities/race_result_entity.dart';

/// Contract for persisting coaching race event results.
abstract interface class IRaceResultRepo {
  Future<void> save(RaceResultEntity result);
  Future<void> saveAll(List<RaceResultEntity> results);
  Future<RaceResultEntity?> getById(String id);
  Future<List<RaceResultEntity>> getByEventId(String raceEventId);

  /// Retrieve a specific user's result in a race event.
  Future<RaceResultEntity?> getByEventAndUser({
    required String raceEventId,
    required String userId,
  });

  Future<void> deleteById(String id);
}
