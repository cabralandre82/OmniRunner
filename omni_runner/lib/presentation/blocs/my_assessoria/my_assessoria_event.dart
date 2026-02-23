import 'package:equatable/equatable.dart';

sealed class MyAssessoriaEvent extends Equatable {
  const MyAssessoriaEvent();
  @override
  List<Object?> get props => [];
}

/// Load the user's current assessoria membership.
final class LoadMyAssessoria extends MyAssessoriaEvent {
  final String userId;
  const LoadMyAssessoria(this.userId);
  @override
  List<Object?> get props => [userId];
}

/// User confirmed switch — execute it.
final class ConfirmSwitchAssessoria extends MyAssessoriaEvent {
  final String newGroupId;
  const ConfirmSwitchAssessoria(this.newGroupId);
  @override
  List<Object?> get props => [newGroupId];
}
