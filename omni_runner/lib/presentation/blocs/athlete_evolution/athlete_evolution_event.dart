import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';

sealed class AthleteEvolutionEvent extends Equatable {
  const AthleteEvolutionEvent();

  @override
  List<Object?> get props => [];
}

final class LoadAthleteEvolution extends AthleteEvolutionEvent {
  final String userId;
  final String groupId;
  final EvolutionMetric metric;
  final EvolutionPeriod period;

  const LoadAthleteEvolution({
    required this.userId,
    required this.groupId,
    this.metric = EvolutionMetric.avgPace,
    this.period = EvolutionPeriod.weekly,
  });

  @override
  List<Object?> get props => [userId, groupId, metric, period];
}

final class ChangeEvolutionMetric extends AthleteEvolutionEvent {
  final EvolutionMetric metric;
  const ChangeEvolutionMetric(this.metric);

  @override
  List<Object?> get props => [metric];
}

final class ChangeEvolutionPeriod extends AthleteEvolutionEvent {
  final EvolutionPeriod period;
  const ChangeEvolutionPeriod(this.period);

  @override
  List<Object?> get props => [period];
}

final class RefreshAthleteEvolution extends AthleteEvolutionEvent {
  const RefreshAthleteEvolution();
}
