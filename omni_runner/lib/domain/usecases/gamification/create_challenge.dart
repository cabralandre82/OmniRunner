import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';

/// Creates a new challenge and persists it with [ChallengeStatus.pending].
///
/// The creator is automatically added as the first participant with
/// [ParticipantStatus.accepted].
///
/// Conforms to [O4]: single `call()` method.
final class CreateChallenge {
  final IChallengeRepo _challengeRepo;

  const CreateChallenge({required IChallengeRepo challengeRepo})
      : _challengeRepo = challengeRepo;

  /// [id] must be a pre-generated UUID v4.
  /// [creatorUserId] / [creatorDisplayName] identify the creator.
  Future<ChallengeEntity> call({
    required String id,
    required String creatorUserId,
    required String creatorDisplayName,
    required ChallengeType type,
    required ChallengeRulesEntity rules,
    required int createdAtMs,
    String? title,
    String? teamAGroupId,
    String? teamAGroupName,
  }) async {
    final creator = ChallengeParticipantEntity(
      userId: creatorUserId,
      displayName: creatorDisplayName,
      status: ParticipantStatus.accepted,
      respondedAtMs: createdAtMs,
      groupId: type == ChallengeType.teamVsTeam ? teamAGroupId : null,
    );

    final challenge = ChallengeEntity(
      id: id,
      creatorUserId: creatorUserId,
      status: ChallengeStatus.pending,
      type: type,
      rules: rules,
      participants: [creator],
      createdAtMs: createdAtMs,
      title: title,
      teamAGroupId: type == ChallengeType.teamVsTeam ? teamAGroupId : null,
      teamAGroupName: type == ChallengeType.teamVsTeam ? teamAGroupName : null,
    );

    await _challengeRepo.save(challenge);
    return challenge;
  }
}
