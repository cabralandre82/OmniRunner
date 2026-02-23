import 'package:equatable/equatable.dart';

sealed class AssessoriaFeedEvent extends Equatable {
  const AssessoriaFeedEvent();

  @override
  List<Object?> get props => [];
}

/// Load the initial page of feed items for a coaching group.
final class LoadFeed extends AssessoriaFeedEvent {
  final String groupId;
  const LoadFeed(this.groupId);

  @override
  List<Object?> get props => [groupId];
}

/// Load older items (pagination).
final class LoadMoreFeed extends AssessoriaFeedEvent {
  const LoadMoreFeed();
}

/// Pull-to-refresh: reload from the top.
final class RefreshFeed extends AssessoriaFeedEvent {
  const RefreshFeed();
}
