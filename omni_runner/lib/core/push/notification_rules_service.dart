import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Client-side convenience for triggering smart push notification rules.
///
/// Calls the `notify-rules` Edge Function with a specific rule + context.
/// Fire-and-forget — never blocks UI. The Edge Function handles dedup,
/// token lookup, and FCM delivery.
///
/// Rules:
///   - [notifyChallengeReceived] — after creating a challenge with invitees
///   - [notifyChampionshipStarting] — after launching a championship
///   - [evaluateAll] — trigger all rules (typically called by cron, not client)
class NotificationRulesService {
  static const _tag = 'NotifyRules';
  static const _fn = 'notify-rules';

  /// Notify invited users about a new challenge.
  void notifyChallengeReceived({
    required String challengeId,
    List<String>? userIds,
  }) {
    _invoke('challenge_received', {
      if (userIds != null) 'user_ids': userIds,
      'challenge_id': challengeId,
    });
  }

  /// Notify participants that a championship is starting soon.
  void notifyChampionshipStarting({required String championshipId}) {
    _invoke('championship_starting', {
      'championship_id': championshipId,
    });
  }

  /// Notify staff of a group about a championship invite.
  void notifyChampionshipInviteReceived({
    required String championshipId,
    required List<String> userIds,
  }) {
    _invoke('championship_invite_received', {
      'championship_id': championshipId,
      'user_ids': userIds,
    });
  }

  /// Notify staff of a group about a team challenge invite.
  void notifyChallengeTeamInviteReceived({
    required String challengeId,
    required List<String> userIds,
  }) {
    _invoke('challenge_team_invite_received', {
      'challenge_id': challengeId,
      'user_ids': userIds,
    });
  }

  /// Notify staff that an athlete requested to join their group.
  void notifyJoinRequestReceived({
    required String groupId,
    required String athleteName,
  }) {
    _invoke('join_request_received', {
      'group_id': groupId,
      'athlete_name': athleteName,
    });
  }

  /// Notify an athlete their streak is about to expire (no run today yet).
  void notifyStreakAtRisk({required String userId, required int currentStreak}) {
    _invoke('streak_at_risk', {
      'user_id': userId,
      'current_streak': currentStreak,
    });
  }

  /// Evaluate all notification rules (streak_at_risk, etc.).
  /// Typically called by a server-side cron, but available for manual trigger.
  void evaluateAll() {
    _invoke(null, null);
  }

  Future<void> _invoke(
    String? rule,
    Map<String, dynamic>? context,
  ) async {
    if (!AppConfig.isSupabaseReady) return;

    try {
      final body = <String, dynamic>{};
      if (rule != null) body['rule'] = rule;
      if (context != null) body['context'] = context;

      await Supabase.instance.client.functions.invoke(_fn, body: body);
      AppLogger.debug('Notify rule dispatched: ${rule ?? "all"}', tag: _tag);
    } catch (e) {
      AppLogger.warn('Notify rule failed: $e', tag: _tag);
    }
  }
}
