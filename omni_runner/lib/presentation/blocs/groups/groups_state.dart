import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';

sealed class GroupsState extends Equatable {
  const GroupsState();

  @override
  List<Object?> get props => [];
}

final class GroupsInitial extends GroupsState {
  const GroupsInitial();
}

final class GroupsLoading extends GroupsState {
  const GroupsLoading();
}

final class GroupsLoaded extends GroupsState {
  final List<GroupEntity> groups;

  const GroupsLoaded({required this.groups});

  @override
  List<Object?> get props => [groups];
}

final class GroupsError extends GroupsState {
  final String message;
  const GroupsError(this.message);

  @override
  List<Object?> get props => [message];
}
