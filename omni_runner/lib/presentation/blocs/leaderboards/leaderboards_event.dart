import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/leaderboard_entity.dart';

sealed class LeaderboardsEvent extends Equatable {
  const LeaderboardsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadLeaderboard extends LeaderboardsEvent {
  final LeaderboardScope scope;
  final LeaderboardPeriod period;
  final LeaderboardMetric metric;
  final String? groupId;
  final String? championshipId;
  final int nowMs;

  LoadLeaderboard({
    required this.scope,
    required this.period,
    this.metric = LeaderboardMetric.composite,
    this.groupId,
    this.championshipId,
    int? nowMs,
  }) : nowMs = nowMs ?? DateTime.now().millisecondsSinceEpoch;

  @override
  List<Object?> get props =>
      [scope, period, metric, groupId, championshipId, nowMs];
}

final class RefreshLeaderboard extends LeaderboardsEvent {
  const RefreshLeaderboard();
}
