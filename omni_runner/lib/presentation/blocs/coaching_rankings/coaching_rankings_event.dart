import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';

sealed class CoachingRankingsEvent extends Equatable {
  const CoachingRankingsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCoachingRanking extends CoachingRankingsEvent {
  final String groupId;
  final CoachingRankingMetric metric;
  final CoachingRankingPeriod period;
  final String periodKey;

  const LoadCoachingRanking({
    required this.groupId,
    required this.metric,
    required this.period,
    required this.periodKey,
  });

  @override
  List<Object?> get props => [groupId, metric, period, periodKey];
}

final class ChangeMetricFilter extends CoachingRankingsEvent {
  final CoachingRankingMetric metric;
  const ChangeMetricFilter(this.metric);

  @override
  List<Object?> get props => [metric];
}

final class ChangePeriodFilter extends CoachingRankingsEvent {
  final CoachingRankingPeriod period;
  final String periodKey;

  const ChangePeriodFilter({
    required this.period,
    required this.periodKey,
  });

  @override
  List<Object?> get props => [period, periodKey];
}

final class RefreshCoachingRanking extends CoachingRankingsEvent {
  const RefreshCoachingRanking();
}
