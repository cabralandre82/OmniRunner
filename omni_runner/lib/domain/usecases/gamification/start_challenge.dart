import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Transitions a challenge from [ChallengeStatus.pending] to
/// [ChallengeStatus.active], opening the competition window.
///
/// Preconditions:
/// - For 1v1: exactly 2 accepted participants.
/// - For group: at least 2 accepted participants.
/// - If [ChallengeStartMode.onAccept]: starts immediately.
/// - If [ChallengeStartMode.scheduled]: [rules.fixedStartMs] must be set.
///
/// Conforms to [O4]: single `call()` method.
final class StartChallenge {
  final IChallengeRepo _challengeRepo;

  const StartChallenge({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// [nowMs] is the current timestamp (ms epoch UTC).
  /// Returns the updated challenge with window timestamps set.
  /// Throws [GamificationFailure] on validation error.
  Future<ChallengeEntity> call({
    required String challengeId,
    required int nowMs,
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

    final acceptedCount = challenge.acceptedCount;

    if (challenge.type == ChallengeType.oneVsOne && acceptedCount != 2) {
      throw InvalidChallengeStatus(
        challengeId,
        '2 accepted participants for 1v1',
        '$acceptedCount accepted',
      );
    }

    if (challenge.type == ChallengeType.group && acceptedCount < 2) {
      throw InvalidChallengeStatus(
        challengeId,
        '≥2 accepted participants for group',
        '$acceptedCount accepted',
      );
    }

    final int startsAt;
    if (challenge.rules.startMode == ChallengeStartMode.scheduled &&
        challenge.rules.fixedStartMs != null) {
      startsAt = challenge.rules.fixedStartMs!;
    } else {
      startsAt = nowMs;
    }

    final endsAt = startsAt + challenge.rules.windowMs;

    final updated = challenge.copyWith(
      status: ChallengeStatus.active,
      startsAtMs: startsAt,
      endsAtMs: endsAt,
    );
    await _challengeRepo.update(updated);
    return updated;
  }
}
