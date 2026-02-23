import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/coach_insight_entity.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

sealed class CoachInsightsState extends Equatable {
  const CoachInsightsState();

  @override
  List<Object?> get props => [];
}

final class CoachInsightsInitial extends CoachInsightsState {
  const CoachInsightsInitial();
}

final class CoachInsightsLoading extends CoachInsightsState {
  const CoachInsightsLoading();
}

final class CoachInsightsLoaded extends CoachInsightsState {
  final List<CoachInsightEntity> insights;
  final int unreadCount;
  final InsightType? typeFilter;
  final bool unreadOnly;

  const CoachInsightsLoaded({
    required this.insights,
    required this.unreadCount,
    this.typeFilter,
    this.unreadOnly = false,
  });

  @override
  List<Object?> get props => [insights, unreadCount, typeFilter, unreadOnly];
}

final class CoachInsightsEmpty extends CoachInsightsState {
  final InsightType? typeFilter;
  final bool unreadOnly;

  const CoachInsightsEmpty({this.typeFilter, this.unreadOnly = false});

  @override
  List<Object?> get props => [typeFilter, unreadOnly];
}

final class CoachInsightsError extends CoachInsightsState {
  final String message;
  const CoachInsightsError(this.message);

  @override
  List<Object?> get props => [message];
}
