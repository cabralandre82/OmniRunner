import 'package:equatable/equatable.dart';

sealed class CoachingGroupsEvent extends Equatable {
  const CoachingGroupsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCoachingGroups extends CoachingGroupsEvent {
  final String userId;
  const LoadCoachingGroups(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshCoachingGroups extends CoachingGroupsEvent {
  const RefreshCoachingGroups();
}
