import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';

sealed class GroupEvolutionEvent extends Equatable {
  const GroupEvolutionEvent();

  @override
  List<Object?> get props => [];
}

final class LoadGroupEvolution extends GroupEvolutionEvent {
  final String groupId;
  final TrendDirection? directionFilter;

  const LoadGroupEvolution({
    required this.groupId,
    this.directionFilter,
  });

  @override
  List<Object?> get props => [groupId, directionFilter];
}

final class ChangeDirectionFilter extends GroupEvolutionEvent {
  final TrendDirection? direction;
  const ChangeDirectionFilter(this.direction);

  @override
  List<Object?> get props => [direction];
}

final class RefreshGroupEvolution extends GroupEvolutionEvent {
  const RefreshGroupEvolution();
}
