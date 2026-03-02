import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/domain/entities/leaderboard_entity.dart';
import 'package:omni_runner/domain/repositories/i_leaderboard_repo.dart';

class SupabaseLeaderboardRepo implements ILeaderboardRepo {
  @override
  Future<LeaderboardEntity?> fetchLeaderboard({
    required LeaderboardScope scope,
    required LeaderboardPeriod period,
    required LeaderboardMetric metric,
    String? groupId,
    String? championshipId,
  }) async {
    final sb = Supabase.instance.client;

    final scopeStr = switch (scope) {
      LeaderboardScope.assessoria => 'assessoria',
      LeaderboardScope.championship => 'championship',
      _ => 'global',
    };
    final periodStr =
        period == LeaderboardPeriod.monthly ? 'monthly' : 'weekly';

    var query = sb
        .from('leaderboards')
        .select(
            'id, scope, period, metric, period_key, computed_at_ms, is_final, coaching_group_id, championship_id')
        .eq('scope', scopeStr)
        .eq('period', periodStr);

    if (scope == LeaderboardScope.assessoria && groupId != null) {
      query = query.eq('coaching_group_id', groupId);
    } else if (scope == LeaderboardScope.championship &&
        championshipId != null) {
      query = query.eq('championship_id', championshipId);
    }

    final lbRows =
        await query.order('computed_at_ms', ascending: false).limit(1);

    if (lbRows.isEmpty) return null;

    final lb = lbRows.first;
    final lbId = lb['id'] as String;

    final entryRows = await sb
        .from('leaderboard_entries')
        .select()
        .eq('leaderboard_id', lbId)
        .order('rank', ascending: true)
        .limit(200);

    final entries = entryRows
        .map((e) => LeaderboardEntryEntity(
              userId: e['user_id'] as String,
              displayName: (e['display_name'] as String?) ?? 'Runner',
              avatarUrl: e['avatar_url'] as String?,
              level: (e['level'] as num?)?.toInt() ?? 0,
              value: (e['value'] as num?)?.toDouble() ?? 0,
              rank: (e['rank'] as num?)?.toInt() ?? 0,
              periodKey: (e['period_key'] as String?) ?? '',
            ))
        .toList();

    final lbMetricStr = (lb['metric'] as String?) ?? 'composite';
    final resolvedMetric = _parseMetric(lbMetricStr);

    return LeaderboardEntity(
      id: lbId,
      scope: scope,
      groupId: groupId,
      period: period,
      metric: resolvedMetric,
      periodKey: (lb['period_key'] as String?) ?? '',
      entries: entries,
      computedAtMs: (lb['computed_at_ms'] as num?)?.toInt() ?? 0,
      isFinal: (lb['is_final'] as bool?) ?? false,
    );
  }

  static LeaderboardMetric _parseMetric(String s) => switch (s) {
        'distance' => LeaderboardMetric.distance,
        'sessions' => LeaderboardMetric.sessions,
        'moving_time' => LeaderboardMetric.movingTime,
        'avg_pace' => LeaderboardMetric.avgPace,
        'season_xp' => LeaderboardMetric.seasonXp,
        'pace' => LeaderboardMetric.avgPace,
        'time' => LeaderboardMetric.movingTime,
        _ => LeaderboardMetric.composite,
      };
}
