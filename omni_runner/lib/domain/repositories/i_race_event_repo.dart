import 'package:omni_runner/domain/entities/race_event_entity.dart';

/// Contract for persisting coaching race events.
abstract interface class IRaceEventRepo {
  Future<void> save(RaceEventEntity event);
  Future<void> update(RaceEventEntity event);
  Future<RaceEventEntity?> getById(String id);
  Future<List<RaceEventEntity>> getByGroupId(
    String groupId, {
    int limit = 50,
    int offset = 0,
  });

  /// Active events whose window contains [nowMs].
  Future<List<RaceEventEntity>> getActiveByGroupId(String groupId, int nowMs);

  Future<void> deleteById(String id);
}
