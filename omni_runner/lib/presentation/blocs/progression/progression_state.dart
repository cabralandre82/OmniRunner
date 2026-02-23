import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/weekly_goal_entity.dart';

sealed class ProgressionState extends Equatable {
  const ProgressionState();

  @override
  List<Object?> get props => [];
}

final class ProgressionInitial extends ProgressionState {
  const ProgressionInitial();
}

final class ProgressionLoading extends ProgressionState {
  const ProgressionLoading();
}

final class ProgressionLoaded extends ProgressionState {
  final ProfileProgressEntity profile;
  final List<XpTransactionEntity> recentXp;
  final WeeklyGoalEntity? weeklyGoal;

  const ProgressionLoaded({
    required this.profile,
    required this.recentXp,
    this.weeklyGoal,
  });

  @override
  List<Object?> get props => [profile, recentXp, weeklyGoal];
}

final class ProgressionError extends ProgressionState {
  final String message;

  const ProgressionError(this.message);

  @override
  List<Object?> get props => [message];
}
