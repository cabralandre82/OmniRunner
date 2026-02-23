import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';

sealed class BadgesState extends Equatable {
  const BadgesState();

  @override
  List<Object?> get props => [];
}

final class BadgesInitial extends BadgesState {
  const BadgesInitial();
}

final class BadgesLoading extends BadgesState {
  const BadgesLoading();
}

final class BadgesLoaded extends BadgesState {
  final List<BadgeEntity> catalog;
  final List<BadgeAwardEntity> awards;

  const BadgesLoaded({required this.catalog, required this.awards});

  Set<String> get unlockedIds => {for (final a in awards) a.badgeId};

  bool isUnlocked(String badgeId) => unlockedIds.contains(badgeId);

  @override
  List<Object?> get props => [catalog, awards];
}

final class BadgesError extends BadgesState {
  final String message;

  const BadgesError(this.message);

  @override
  List<Object?> get props => [message];
}
