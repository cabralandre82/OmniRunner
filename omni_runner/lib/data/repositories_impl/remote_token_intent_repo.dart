import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/generate_uuid_v4.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';

/// Calls `token-create-intent` and `token-consume-intent` Edge Functions.
final class RemoteTokenIntentRepo implements ITokenIntentRepo {
  static const _tag = 'RemoteTokenIntent';
  static const _ttl = Duration(minutes: 5);

  SupabaseClient get _client => sl<SupabaseClient>();

  const RemoteTokenIntentRepo();

  @override
  Future<StaffQrPayload> createIntent({
    required TokenIntentType type,
    required String groupId,
    required int amount,
    String? targetUserId,
    String? championshipId,
  }) async {
    try {
      final nonce = generateUuidV4();
      final expiresAt = DateTime.now().toUtc().add(_ttl);

      final res = await _client.functions.invoke(
        'token-create-intent',
        body: {
          'type': tokenIntentTypeToString(type),
          'group_id': groupId,
          'amount': amount,
          'nonce': nonce,
          'expires_at_iso': expiresAt.toIso8601String(),
          if (targetUserId != null) 'target_user_id': targetUserId,
          'championship_id': championshipId,
        },
      );
      if (res.data == null) {
        throw TokenIntentFailed('Empty response from token-create-intent');
      }
      final data = res.data as Map<String, dynamic>;
      AppLogger.info('Intent created: ${data['intent_id']}', tag: _tag);
      return StaffQrPayload(
        intentId: data['intent_id'] as String,
        type: type,
        groupId: groupId,
        amount: amount,
        nonce: data['nonce'] as String,
        expiresAtMs:
            DateTime.parse(data['expires_at'] as String).millisecondsSinceEpoch,
        championshipId: championshipId,
      );
    } on FunctionException catch (e) {
      AppLogger.error('Create intent error: ${e.reasonPhrase}', tag: _tag);
      throw TokenIntentFailed(e.reasonPhrase ?? 'Edge Function error');
    } on AuthException catch (e) {
      AppLogger.error('Auth error: ${e.message}', tag: _tag);
      throw TokenIntentFailed(e.message);
    }
  }

  @override
  Future<void> consumeIntent(StaffQrPayload payload) async {
    try {
      await _client.functions.invoke(
        'token-consume-intent',
        body: {
          'intent_id': payload.intentId,
          'nonce': payload.nonce,
        },
      );
      AppLogger.info('Intent consumed: ${payload.intentId}', tag: _tag);
    } on FunctionException catch (e) {
      AppLogger.error('Consume intent error: ${e.reasonPhrase}', tag: _tag);
      throw TokenIntentFailed(e.reasonPhrase ?? 'Edge Function error');
    } on AuthException catch (e) {
      AppLogger.error('Auth error: ${e.message}', tag: _tag);
      throw TokenIntentFailed(e.message);
    }
  }

  @override
  Future<EmissionCapacity> getEmissionCapacity(String groupId) async {
    try {
      final row = await _client
          .from('coaching_token_inventory')
          .select('available_tokens, lifetime_issued, lifetime_burned')
          .eq('group_id', groupId)
          .maybeSingle();

      if (row == null) return EmissionCapacity.empty;

      return EmissionCapacity(
        availableTokens: (row['available_tokens'] as int?) ?? 0,
        lifetimeIssued: (row['lifetime_issued'] as int?) ?? 0,
        lifetimeBurned: (row['lifetime_burned'] as int?) ?? 0,
      );
    } on PostgrestException catch (e) {
      AppLogger.error('Emission capacity error: ${e.message}', tag: _tag);
      return EmissionCapacity.empty;
    }
  }

  @override
  Future<BadgeCapacity> getBadgeCapacity(String groupId) async {
    try {
      final row = await _client
          .from('coaching_badge_inventory')
          .select('available_badges, lifetime_purchased, lifetime_activated')
          .eq('group_id', groupId)
          .maybeSingle();

      if (row == null) return BadgeCapacity.empty;

      return BadgeCapacity(
        availableBadges: (row['available_badges'] as int?) ?? 0,
        lifetimePurchased: (row['lifetime_purchased'] as int?) ?? 0,
        lifetimeActivated: (row['lifetime_activated'] as int?) ?? 0,
      );
    } on PostgrestException catch (e) {
      AppLogger.error('Badge capacity error: ${e.message}', tag: _tag);
      return BadgeCapacity.empty;
    }
  }
}
