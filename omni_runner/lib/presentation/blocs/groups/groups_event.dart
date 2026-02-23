import 'package:equatable/equatable.dart';

sealed class GroupsEvent extends Equatable {
  const GroupsEvent();

  @override
  List<Object?> get props => [];
}

final class LoadGroups extends GroupsEvent {
  final String userId;
  const LoadGroups(this.userId);

  @override
  List<Object?> get props => [userId];
}

final class RefreshGroups extends GroupsEvent {
  const RefreshGroups();
}
