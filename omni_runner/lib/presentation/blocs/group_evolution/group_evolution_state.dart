import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';

sealed class GroupEvolutionState extends Equatable {
  const GroupEvolutionState();

  @override
  List<Object?> get props => [];
}

final class GroupEvolutionInitial extends GroupEvolutionState {
  const GroupEvolutionInitial();
}

final class GroupEvolutionLoading extends GroupEvolutionState {
  final TrendDirection? directionFilter;

  const GroupEvolutionLoading({this.directionFilter});

  @override
  List<Object?> get props => [directionFilter];
}

final class GroupEvolutionLoaded extends GroupEvolutionState {
  final List<AthleteTrendEntity> trends;
  final TrendDirection? directionFilter;
  final int improvingCount;
  final int stableCount;
  final int decliningCount;
  final int insufficientCount;

  const GroupEvolutionLoaded({
    required this.trends,
    this.directionFilter,
    required this.improvingCount,
    required this.stableCount,
    required this.decliningCount,
    required this.insufficientCount,
  });

  @override
  List<Object?> get props => [
        trends,
        directionFilter,
        improvingCount,
        stableCount,
        decliningCount,
        insufficientCount,
      ];
}

final class GroupEvolutionEmpty extends GroupEvolutionState {
  final TrendDirection? directionFilter;

  const GroupEvolutionEmpty({this.directionFilter});

  @override
  List<Object?> get props => [directionFilter];
}

final class GroupEvolutionError extends GroupEvolutionState {
  final String message;
  const GroupEvolutionError(this.message);

  @override
  List<Object?> get props => [message];
}
