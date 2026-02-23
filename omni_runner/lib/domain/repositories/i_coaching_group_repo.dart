import 'package:omni_runner/domain/entities/coaching_group_entity.dart';

/// Contract for persisting and retrieving coaching groups.
///
/// Domain interface. Implementation lives in data layer.
abstract interface class ICoachingGroupRepo {
  Future<void> save(CoachingGroupEntity group);

  Future<void> update(CoachingGroupEntity group);

  Future<CoachingGroupEntity?> getById(String id);

  /// All coaching groups owned by a coach.
  Future<List<CoachingGroupEntity>> getByCoachUserId(String coachUserId);

  /// How many coaching groups this user owns.
  Future<int> countByCoachUserId(String coachUserId);

  Future<void> deleteById(String id);
}
