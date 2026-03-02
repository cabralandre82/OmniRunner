import 'package:omni_runner/domain/entities/feed_item_entity.dart';

/// Remote data source for the assessoria social feed.
///
/// Abstracts the Supabase RPC so the BLoC can be tested without a backend.
abstract interface class IFeedRemoteSource {
  /// Fetches a page of feed items for [groupId].
  ///
  /// If [beforeMs] is provided, returns items older than that timestamp
  /// (cursor-based pagination). Returns up to [limit] items.
  Future<List<FeedItemEntity>> fetchFeed({
    required String groupId,
    required int limit,
    int? beforeMs,
  });
}
