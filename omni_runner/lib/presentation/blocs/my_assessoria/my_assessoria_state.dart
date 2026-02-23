import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';

sealed class MyAssessoriaState extends Equatable {
  const MyAssessoriaState();
  @override
  List<Object?> get props => [];
}

final class MyAssessoriaInitial extends MyAssessoriaState {
  const MyAssessoriaInitial();
}

final class MyAssessoriaLoading extends MyAssessoriaState {
  const MyAssessoriaLoading();
}

final class MyAssessoriaLoaded extends MyAssessoriaState {
  final CoachingGroupEntity? currentGroup;
  final CoachingMemberEntity? membership;
  final List<CoachingGroupEntity> availableGroups;

  const MyAssessoriaLoaded({
    this.currentGroup,
    this.membership,
    this.availableGroups = const [],
  });

  @override
  List<Object?> get props => [currentGroup, membership, availableGroups];
}

final class MyAssessoriaSwitching extends MyAssessoriaState {
  const MyAssessoriaSwitching();
}

final class MyAssessoriaSwitched extends MyAssessoriaState {
  final String newGroupId;
  const MyAssessoriaSwitched(this.newGroupId);
  @override
  List<Object?> get props => [newGroupId];
}

final class MyAssessoriaError extends MyAssessoriaState {
  final String message;
  const MyAssessoriaError(this.message);
  @override
  List<Object?> get props => [message];
}
