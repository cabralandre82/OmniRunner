import 'package:omni_runner/core/utils/generate_uuid_v4.dart';
import 'package:omni_runner/domain/entities/token_intent_entity.dart';
import 'package:omni_runner/domain/repositories/i_token_intent_repo.dart';

/// Mock implementation that simulates intent creation with a 5-minute expiry.
final class StubTokenIntentRepo implements ITokenIntentRepo {
  /// Default intent TTL for stub: 5 minutes.
  static const _ttl = Duration(minutes: 5);

  const StubTokenIntentRepo();

  @override
  Future<StaffQrPayload> createIntent({
    required TokenIntentType type,
    required String groupId,
    required int amount,
    String? targetUserId,
    String? championshipId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final now = DateTime.now();
    return StaffQrPayload(
      intentId: generateUuidV4(),
      type: type,
      groupId: groupId,
      amount: amount,
      nonce: generateUuidV4(),
      expiresAtMs: now.add(_ttl).millisecondsSinceEpoch,
      championshipId: championshipId,
    );
  }

  @override
  Future<void> consumeIntent(StaffQrPayload payload) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (payload.isExpired) {
      throw Exception('Intent expired (stub)');
    }
  }
}
