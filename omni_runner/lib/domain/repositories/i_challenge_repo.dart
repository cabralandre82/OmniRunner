import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';

/// Contract for persisting and retrieving challenges.
///
/// Domain interface. Implementation lives in data layer.
/// Dependency direction: data → domain (implements this).
abstract interface class IChallengeRepo {
  Future<void> save(ChallengeEntity challenge);

  Future<ChallengeEntity?> getById(String id);

  /// Active + pending challenges the user is involved in.
  Future<List<ChallengeEntity>> getByUserId(String userId);

  Future<List<ChallengeEntity>> getByStatus(ChallengeStatus status);

  Future<void> update(ChallengeEntity challenge);

  Future<void> deleteById(String id);

  /// Persist the finalized result of a completed challenge.
  Future<void> saveResult(ChallengeResultEntity result);

  Future<ChallengeResultEntity?> getResultByChallengeId(String challengeId);
}
