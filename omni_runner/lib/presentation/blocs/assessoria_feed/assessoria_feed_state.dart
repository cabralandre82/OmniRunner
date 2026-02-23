import 'package:equatable/equatable.dart';
import 'package:omni_runner/domain/entities/feed_item_entity.dart';

sealed class AssessoriaFeedState extends Equatable {
  const AssessoriaFeedState();

  @override
  List<Object?> get props => [];
}

final class FeedInitial extends AssessoriaFeedState {
  const FeedInitial();
}

final class FeedLoading extends AssessoriaFeedState {
  const FeedLoading();
}

final class FeedLoaded extends AssessoriaFeedState {
  final List<FeedItemEntity> items;
  final bool hasMore;
  final bool loadingMore;

  const FeedLoaded({
    required this.items,
    this.hasMore = true,
    this.loadingMore = false,
  });

  FeedLoaded copyWith({
    List<FeedItemEntity>? items,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      FeedLoaded(
        items: items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  @override
  List<Object?> get props => [items, hasMore, loadingMore];
}

final class FeedEmpty extends AssessoriaFeedState {
  const FeedEmpty();
}

final class FeedError extends AssessoriaFeedState {
  final String message;
  const FeedError(this.message);

  @override
  List<Object?> get props => [message];
}
