import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';

sealed class CoachingRankingsState extends Equatable {
  const CoachingRankingsState();

  @override
  List<Object?> get props => [];
}

final class CoachingRankingsInitial extends CoachingRankingsState {
  const CoachingRankingsInitial();
}

final class CoachingRankingsLoading extends CoachingRankingsState {
  final CoachingRankingMetric metric;
  final CoachingRankingPeriod period;

  const CoachingRankingsLoading({
    required this.metric,
    required this.period,
  });

  @override
  List<Object?> get props => [metric, period];
}

final class CoachingRankingsLoaded extends CoachingRankingsState {
  final CoachingGroupRankingEntity ranking;
  final CoachingRankingMetric selectedMetric;
  final CoachingRankingPeriod selectedPeriod;

  const CoachingRankingsLoaded({
    required this.ranking,
    required this.selectedMetric,
    required this.selectedPeriod,
  });

  @override
  List<Object?> get props => [ranking, selectedMetric, selectedPeriod];
}

final class CoachingRankingsEmpty extends CoachingRankingsState {
  final CoachingRankingMetric selectedMetric;
  final CoachingRankingPeriod selectedPeriod;

  const CoachingRankingsEmpty({
    required this.selectedMetric,
    required this.selectedPeriod,
  });

  @override
  List<Object?> get props => [selectedMetric, selectedPeriod];
}

final class CoachingRankingsError extends CoachingRankingsState {
  final String message;
  const CoachingRankingsError(this.message);

  @override
  List<Object?> get props => [message];
}
