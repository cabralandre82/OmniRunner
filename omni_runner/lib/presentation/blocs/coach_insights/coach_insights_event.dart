import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/insight_type_enum.dart';

sealed class CoachInsightsEvent extends Equatable {
  const CoachInsightsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCoachInsights extends CoachInsightsEvent {
  final String groupId;
  const LoadCoachInsights({required this.groupId});

  @override
  List<Object?> get props => [groupId];
}

final class RefreshCoachInsights extends CoachInsightsEvent {
  const RefreshCoachInsights();
}

final class FilterByType extends CoachInsightsEvent {
  /// Null means "show all".
  final InsightType? type;
  const FilterByType(this.type);

  @override
  List<Object?> get props => [type];
}

final class FilterUnreadOnly extends CoachInsightsEvent {
  final bool unreadOnly;
  const FilterUnreadOnly(this.unreadOnly);

  @override
  List<Object?> get props => [unreadOnly];
}

final class MarkInsightRead extends CoachInsightsEvent {
  final String insightId;
  const MarkInsightRead(this.insightId);

  @override
  List<Object?> get props => [insightId];
}

final class DismissInsight extends CoachInsightsEvent {
  final String insightId;
  const DismissInsight(this.insightId);

  @override
  List<Object?> get props => [insightId];
}
