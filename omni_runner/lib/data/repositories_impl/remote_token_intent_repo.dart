import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:omni_runner/core/errors/coaching_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';

/// Calls `token-create-intent` and `token-consume-intent` Edge Functions.
final class RemoteTokenIntentRepo implements ITokenIntentRepo {
  static const _tag = 'RemoteTokenIntent';

  SupabaseClient get _client => Supabase.instance.client;

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
      final res = await _client.functions.invoke(
        'token-create-intent',
        body: {
          'type': tokenIntentTypeToString(type),
          'group_id': groupId,
          'amount': amount,
          if (targetUserId != null) 'target_user_id': targetUserId,
          if (championshipId != null) 'championship_id': championshipId,
        },
      );
      final data = res.data as Map<String, dynamic>;
      AppLogger.info('Intent created: ${data['id']}', tag: _tag);
      return StaffQrPayload(
        intentId: data['id'] as String,
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
}
