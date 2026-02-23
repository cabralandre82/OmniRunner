import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';

sealed class ChallengesEvent extends Equatable {
  const ChallengesEvent();

  @override
  List<Object?> get props => [];
}

final class LoadChallenges extends ChallengesEvent {
  final String userId;
  const LoadChallenges(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class CreateChallengeRequested extends ChallengesEvent {
  final String creatorUserId;
  final String creatorDisplayName;
  final String type;
  final ChallengeRulesEntity rules;
  final String? title;
  final String? teamAGroupId;
  final String? teamAGroupName;

  const CreateChallengeRequested({
    required this.creatorUserId,
    required this.creatorDisplayName,
    required this.type,
    required this.rules,
    this.title,
    this.teamAGroupId,
    this.teamAGroupName,
  });

  @override
  List<Object?> get props => [creatorUserId, creatorDisplayName, type, rules, title, teamAGroupId, teamAGroupName];
}

final class InviteToChallengeRequested extends ChallengesEvent {
  final String challengeId;
  final String inviteeUserId;
  final String inviteeDisplayName;

  const InviteToChallengeRequested({
    required this.challengeId,
    required this.inviteeUserId,
    required this.inviteeDisplayName,
  });

  @override
  List<Object?> get props => [challengeId, inviteeUserId, inviteeDisplayName];
}

final class JoinChallengeRequested extends ChallengesEvent {
  final String challengeId;
  final String userId;

  const JoinChallengeRequested({
    required this.challengeId,
    required this.userId,
  });

  @override
  List<Object?> get props => [challengeId, userId];
}

final class CancelChallengeRequested extends ChallengesEvent {
  final String challengeId;
  final String userId;

  const CancelChallengeRequested({
    required this.challengeId,
    required this.userId,
  });

  @override
  List<Object?> get props => [challengeId, userId];
}

final class DeclineChallengeRequested extends ChallengesEvent {
  final String challengeId;
  final String userId;

  const DeclineChallengeRequested({
    required this.challengeId,
    required this.userId,
  });

  @override
  List<Object?> get props => [challengeId, userId];
}

final class ViewChallengeDetails extends ChallengesEvent {
  final String challengeId;

  const ViewChallengeDetails(this.challengeId);

  @override
  List<Object?> get props => [challengeId];
}
