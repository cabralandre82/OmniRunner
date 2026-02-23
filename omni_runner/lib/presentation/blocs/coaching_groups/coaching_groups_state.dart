import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';

sealed class CoachingGroupsState extends Equatable {
  const CoachingGroupsState();

  @override
  List<Object?> get props => [];
}

final class CoachingGroupsInitial extends CoachingGroupsState {
  const CoachingGroupsInitial();
}

final class CoachingGroupsLoading extends CoachingGroupsState {
  const CoachingGroupsLoading();
}

/// Each item pairs the group with the user's own membership.
final class CoachingGroupsLoaded extends CoachingGroupsState {
  final List<CoachingGroupItem> groups;

  const CoachingGroupsLoaded({required this.groups});

  @override
  List<Object?> get props => [groups];
}

final class CoachingGroupsError extends CoachingGroupsState {
  final String message;
  const CoachingGroupsError(this.message);

  @override
  List<Object?> get props => [message];
}

/// View-model pairing a coaching group with the current user's membership info.
final class CoachingGroupItem extends Equatable {
  final CoachingGroupEntity group;
  final CoachingMemberEntity membership;
  final int memberCount;

  const CoachingGroupItem({
    required this.group,
    required this.membership,
    required this.memberCount,
  });

  @override
  List<Object?> get props => [group, membership, memberCount];
}
