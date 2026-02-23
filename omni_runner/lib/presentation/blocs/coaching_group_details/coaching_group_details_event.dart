import 'package:equatable/equatable.dart';

sealed class CoachingGroupDetailsEvent extends Equatable {
  const CoachingGroupDetailsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCoachingGroupDetails extends CoachingGroupDetailsEvent {
  final String groupId;
  final String callerUserId;

  const LoadCoachingGroupDetails({
    required this.groupId,
    required this.callerUserId,
  });

  @override
  List<Object?> get props => [groupId, callerUserId];
}

final class RefreshCoachingGroupDetails extends CoachingGroupDetailsEvent {
  const RefreshCoachingGroupDetails();
}
