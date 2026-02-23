import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/leaderboard_entity.dart';

sealed class LeaderboardsState extends Equatable {
  const LeaderboardsState();

  @override
  List<Object?> get props => [];
}

final class LeaderboardsInitial extends LeaderboardsState {
  const LeaderboardsInitial();
}

final class LeaderboardsLoading extends LeaderboardsState {
  const LeaderboardsLoading();
}

final class LeaderboardsLoaded extends LeaderboardsState {
  final LeaderboardEntity leaderboard;

  const LeaderboardsLoaded({required this.leaderboard});

  @override
  List<Object?> get props => [leaderboard];
}

final class LeaderboardsError extends LeaderboardsState {
  final String message;
  const LeaderboardsError(this.message);

  @override
  List<Object?> get props => [message];
}
