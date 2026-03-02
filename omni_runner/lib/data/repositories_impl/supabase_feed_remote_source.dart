import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/feed_item_entity.dart';
import 'package:omni_runner/domain/repositories/i_feed_remote_source.dart';

class SupabaseFeedRemoteSource implements IFeedRemoteSource {
  @override
  Future<List<FeedItemEntity>> fetchFeed({
    required String groupId,
    required int limit,
    int? beforeMs,
  }) async {
    final params = <String, dynamic>{
      'p_group_id': groupId,
      'p_limit': limit,
    };
    if (beforeMs != null) {
      params['p_before_ms'] = beforeMs;
    }

    final rows = await Supabase.instance.client
        .rpc('fn_get_assessoria_feed', params: params) as List<dynamic>;

    return rows.map((dynamic row) {
      final r = row as Map<String, dynamic>;
      return FeedItemEntity(
        id: r['id'] as String,
        actorUserId: r['actor_user_id'] as String,
        actorName: (r['actor_name'] as String?) ?? 'Corredor',
        eventType: _parseEventType(r['event_type'] as String),
        payload: (r['payload'] as Map<String, dynamic>?) ?? {},
        createdAtMs: (r['created_at_ms'] as num).toInt(),
      );
    }).toList();
  }

  static FeedEventType _parseEventType(String raw) => switch (raw) {
        'session_completed' => FeedEventType.sessionCompleted,
        'challenge_won' => FeedEventType.challengeWon,
        'badge_unlocked' => FeedEventType.badgeUnlocked,
        'championship_started' => FeedEventType.championshipStarted,
        'streak_milestone' => FeedEventType.streakMilestone,
        'level_up' => FeedEventType.levelUp,
        'member_joined' => FeedEventType.memberJoined,
        _ => FeedEventType.sessionCompleted,
      };
}
