import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/member_status_entity.dart';

sealed class CrmListEvent extends Equatable {
  const CrmListEvent();

  @override
  List<Object?> get props => [];
}

final class LoadCrmAthletes extends CrmListEvent {
  final String groupId;
  final List<String>? tagIds;
  final MemberStatusValue? status;

  const LoadCrmAthletes({
    required this.groupId,
    this.tagIds,
    this.status,
  });

  @override
  List<Object?> get props => [groupId, tagIds, status];
}

final class RefreshCrmAthletes extends CrmListEvent {
  const RefreshCrmAthletes();
}

final class LoadMoreCrmAthletes extends CrmListEvent {
  const LoadMoreCrmAthletes();
}

final class LoadGroupTags extends CrmListEvent {
  final String groupId;

  const LoadGroupTags(this.groupId);

  @override
  List<Object?> get props => [groupId];
}
