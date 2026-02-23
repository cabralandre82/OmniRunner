import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

sealed class AthleteEvolutionState extends Equatable {
  const AthleteEvolutionState();

  @override
  List<Object?> get props => [];
}

final class AthleteEvolutionInitial extends AthleteEvolutionState {
  const AthleteEvolutionInitial();
}

final class AthleteEvolutionLoading extends AthleteEvolutionState {
  final EvolutionMetric metric;
  final EvolutionPeriod period;

  const AthleteEvolutionLoading({
    required this.metric,
    required this.period,
  });

  @override
  List<Object?> get props => [metric, period];
}

final class AthleteEvolutionLoaded extends AthleteEvolutionState {
  final List<AthleteTrendEntity> trends;
  final List<AthleteBaselineEntity> baselines;
  final EvolutionMetric selectedMetric;
  final EvolutionPeriod selectedPeriod;
  final AthleteTrendEntity? selectedTrend;
  final AthleteBaselineEntity? selectedBaseline;

  const AthleteEvolutionLoaded({
    required this.trends,
    required this.baselines,
    required this.selectedMetric,
    required this.selectedPeriod,
    this.selectedTrend,
    this.selectedBaseline,
  });

  @override
  List<Object?> get props => [
        trends,
        baselines,
        selectedMetric,
        selectedPeriod,
        selectedTrend,
        selectedBaseline,
      ];
}

final class AthleteEvolutionEmpty extends AthleteEvolutionState {
  final EvolutionMetric metric;
  final EvolutionPeriod period;

  const AthleteEvolutionEmpty({
    required this.metric,
    required this.period,
  });

  @override
  List<Object?> get props => [metric, period];
}

final class AthleteEvolutionError extends AthleteEvolutionState {
  final String message;
  const AthleteEvolutionError(this.message);

  @override
  List<Object?> get props => [message];
}
