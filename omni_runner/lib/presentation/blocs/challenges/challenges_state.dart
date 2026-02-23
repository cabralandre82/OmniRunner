import 'package:equatable/equatable.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';

sealed class ChallengesState extends Equatable {
  const ChallengesState();

  @override
  List<Object?> get props => [];
}

final class ChallengesInitial extends ChallengesState {
  const ChallengesInitial();
}

final class ChallengesLoading extends ChallengesState {
  const ChallengesLoading();
}

final class ChallengesLoaded extends ChallengesState {
  final List<ChallengeEntity> challenges;

  const ChallengesLoaded(this.challenges);

  @override
  List<Object?> get props => [challenges];
}

final class ChallengeDetailLoaded extends ChallengesState {
  final ChallengeEntity challenge;
  final ChallengeResultEntity? result;

  const ChallengeDetailLoaded({
    required this.challenge,
    this.result,
  });

  @override
  List<Object?> get props => [challenge, result];
}

final class ChallengeCreated extends ChallengesState {
  final ChallengeEntity challenge;

  const ChallengeCreated(this.challenge);

  @override
  List<Object?> get props => [challenge];
}

final class ChallengesError extends ChallengesState {
  final String message;
  final GamificationFailure? failure;

  const ChallengesError(this.message, {this.failure});

  @override
  List<Object?> get props => [message, failure];
}
