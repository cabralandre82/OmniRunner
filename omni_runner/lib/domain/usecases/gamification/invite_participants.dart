import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Adds invited participants to a pending challenge.
///
/// Validates:
/// - Challenge exists and is [ChallengeStatus.pending].
/// - No duplicate participants.
/// - Group challenges: max 50 participants.
///
/// Conforms to [O4]: single `call()` method.
final class InviteParticipants {
  final IChallengeRepo _challengeRepo;

  static const _maxGroupSize = 50;

  const InviteParticipants({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// [invitees] is a list of (userId, displayName) pairs.
  /// Returns the updated challenge.
  /// Throws [GamificationFailure] on validation error.
  Future<ChallengeEntity> call({
    required String challengeId,
    required List<({String userId, String displayName})> invitees,
  }) async {
    final challenge = await _challengeRepo.getById(challengeId);
    if (challenge == null) throw ChallengeNotFound(challengeId);

    if (challenge.status != ChallengeStatus.pending) {
      throw InvalidChallengeStatus(
        challengeId,
        ChallengeStatus.pending.name,
        challenge.status.name,
      );
    }

    final existingIds =
        challenge.participants.map((p) => p.userId).toSet();

    final newParticipants = <ChallengeParticipantEntity>[];
    for (final inv in invitees) {
      if (existingIds.contains(inv.userId)) {
        throw AlreadyParticipant(inv.userId, challengeId);
      }
      newParticipants.add(ChallengeParticipantEntity(
        userId: inv.userId,
        displayName: inv.displayName,
      ));
      existingIds.add(inv.userId);
    }

    final totalSize =
        challenge.participants.length + newParticipants.length;
    if (totalSize > _maxGroupSize) {
      throw ChallengeFull(challengeId);
    }

    final updated = challenge.copyWith(
      participants: [...challenge.participants, ...newParticipants],
    );
    await _challengeRepo.update(updated);
    return updated;
  }
}
