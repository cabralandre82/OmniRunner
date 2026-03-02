import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/config/app_config.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenges_remote_source.dart';

class SupabaseChallengesRemoteSource implements IChallengesRemoteSource {
  static const _tag = 'ChallengesRemoteSource';

  @override
  Future<List<ChallengeEntity>> fetchMyChallenges() async {
    if (!AppConfig.isSupabaseReady) return const [];
    try {
      final res = await Supabase.instance.client.functions
          .invoke('challenge-list-mine', body: {})
          .timeout(const Duration(seconds: 10));

      final data = res.data as Map<String, dynamic>?;
      if (data == null) return const [];

      final raw = data['challenges'] as List<dynamic>? ?? [];
      return raw.map((e) => _mapRemoteToEntity(e as Map<String, dynamic>)).toList();
    } on TimeoutException {
      AppLogger.warn('Challenge fetch timed out', tag: _tag);
      return const [];
    } on Exception catch (e) {
      AppLogger.warn('Challenge fetch failed: $e', tag: _tag);
      return const [];
    }
  }

  @override
  Future<void> syncNewChallenge(Map<String, dynamic> payload) async {
    if (!AppConfig.isSupabaseReady) return;
    await _syncWithRetry(payload);
  }

  @override
  Future<bool> settleChallenge(String challengeId) async {
    if (!AppConfig.isSupabaseReady) return false;
    try {
      await Supabase.instance.client.functions
          .invoke('settle-challenge', body: {'challenge_id': challengeId})
          .timeout(const Duration(seconds: 15));
      AppLogger.info('Challenge $challengeId settled via backend', tag: _tag);
      return true;
    } on Exception catch (e) {
      AppLogger.warn('Backend settle failed for $challengeId: $e', tag: _tag);
      return false;
    }
  }

  Future<void> _syncWithRetry(
    Map<String, dynamic> payload, {
    int attempt = 1,
    int maxAttempts = 3,
  }) async {
    try {
      await Supabase.instance.client.functions
          .invoke('challenge-create', body: payload)
          .timeout(const Duration(seconds: 15));
      AppLogger.info(
          'Challenge synced to backend (attempt $attempt)', tag: _tag);
    } on Exception catch (e) {
      if (attempt < maxAttempts) {
        final delay = Duration(seconds: attempt * 2);
        AppLogger.warn(
          'Challenge sync attempt $attempt failed, retrying in ${delay.inSeconds}s: $e',
          tag: _tag,
        );
        await Future.delayed(delay);
        await _syncWithRetry(payload,
            attempt: attempt + 1, maxAttempts: maxAttempts);
      } else {
        AppLogger.error(
          'Challenge sync failed after $maxAttempts attempts: $e',
          tag: _tag,
        );
      }
    }
  }

  static ChallengeEntity _mapRemoteToEntity(Map<String, dynamic> m) {
    final typeStr = m['type'] as String? ?? 'one_vs_one';
    final type = switch (typeStr) {
      'group' => ChallengeType.group,
      'team' => ChallengeType.team,
      _ => ChallengeType.oneVsOne,
    };

    final goalStr =
        (m['goal'] as String?) ?? (m['metric'] as String?) ?? 'most_distance';
    final goal = switch (goalStr) {
      'fastest_at_distance' => ChallengeGoal.fastestAtDistance,
      'best_pace_at_distance' => ChallengeGoal.bestPaceAtDistance,
      'collective_distance' => ChallengeGoal.collectiveDistance,
      'pace' => ChallengeGoal.bestPaceAtDistance,
      'distance' => ChallengeGoal.mostDistance,
      _ => ChallengeGoal.mostDistance,
    };

    final startModeStr = m['start_mode'] as String? ?? 'on_accept';
    final startMode = startModeStr == 'scheduled'
        ? ChallengeStartMode.scheduled
        : ChallengeStartMode.onAccept;

    final antiCheatStr = m['anti_cheat_policy'] as String? ?? 'standard';
    final antiCheat = antiCheatStr == 'strict'
        ? ChallengeAntiCheatPolicy.strict
        : ChallengeAntiCheatPolicy.standard;

    final rawParts = m['participants'] as List<dynamic>? ?? [];
    final participants = rawParts.map((p) {
      final pm = p as Map<String, dynamic>;
      final statusStr = pm['status'] as String? ?? 'invited';
      final pStatus = switch (statusStr) {
        'accepted' => ParticipantStatus.accepted,
        'declined' => ParticipantStatus.declined,
        'withdrawn' => ParticipantStatus.withdrawn,
        _ => ParticipantStatus.invited,
      };
      final hasSubmitted = pm['has_submitted'] as bool? ?? false;
      return ChallengeParticipantEntity(
        userId: pm['user_id'] as String? ?? '',
        displayName: pm['display_name'] as String? ?? '',
        status: pStatus,
        respondedAtMs: pm['responded_at_ms'] as int?,
        progressValue: (pm['progress_value'] as num?)?.toDouble() ?? 0.0,
        contributingSessionIds: hasSubmitted ? const ['_submitted'] : const [],
        groupId: pm['group_id'] as String?,
        team: pm['team'] as String?,
      );
    }).toList();

    final statusStr = m['status'] as String? ?? 'pending';
    final status = switch (statusStr) {
      'active' => ChallengeStatus.active,
      'completing' => ChallengeStatus.completing,
      'completed' => ChallengeStatus.completed,
      'cancelled' => ChallengeStatus.cancelled,
      'expired' => ChallengeStatus.expired,
      _ => ChallengeStatus.pending,
    };

    return ChallengeEntity(
      id: m['id'] as String,
      creatorUserId: m['creator_user_id'] as String? ?? '',
      status: status,
      type: type,
      rules: ChallengeRulesEntity(
        goal: goal,
        target: (m['target'] as num?)?.toDouble(),
        windowMs: (m['window_ms'] as num?)?.toInt() ?? 604800000,
        startMode: startMode,
        fixedStartMs: (m['fixed_start_ms'] as num?)?.toInt(),
        entryFeeCoins: (m['entry_fee_coins'] as num?)?.toInt() ?? 0,
        minSessionDistanceM:
            (m['min_session_distance_m'] as num?)?.toDouble() ?? 1000.0,
        antiCheatPolicy: antiCheat,
        acceptWindowMin: (m['accept_window_min'] as num?)?.toInt(),
      ),
      participants: participants,
      createdAtMs: (m['created_at_ms'] as num?)?.toInt() ?? 0,
      startsAtMs: (m['starts_at_ms'] as num?)?.toInt(),
      endsAtMs: (m['ends_at_ms'] as num?)?.toInt(),
      title: m['title'] as String?,
      acceptDeadlineMs: (m['accept_deadline_ms'] as num?)?.toInt(),
    );
  }
}
