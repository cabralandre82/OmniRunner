import 'package:omni_runner/domain/entities/token_intent_entity.dart';

/// Repository for creating and consuming token intents via Edge Functions.
///
/// Staff calls [createIntent] → receives a [StaffQrPayload] to render as QR.
/// Athlete (or staff scanning for athlete) calls [consumeIntent] with the scanned payload.
abstract interface class ITokenIntentRepo {
  /// Staff creates a new intent (calls `token-create-intent` Edge Function).
  ///
  /// Returns the full [StaffQrPayload] including server-generated nonce, intentId, expiry.
  /// Throws [TokenIntentFailed] on server error.
  Future<StaffQrPayload> createIntent({
    required TokenIntentType type,
    required String groupId,
    required int amount,
    String? targetUserId,
    String? championshipId,
  });

  /// Consumes a scanned intent (calls `token-consume-intent` Edge Function).
  ///
  /// Throws [TokenIntentFailed] on server error (expired, already consumed, etc.).
  Future<void> consumeIntent(StaffQrPayload payload);

  /// Returns the group's current emission capacity from `coaching_token_inventory`.
  Future<EmissionCapacity> getEmissionCapacity(String groupId);

  /// Returns the group's current badge capacity from `coaching_badge_inventory`.
  Future<BadgeCapacity> getBadgeCapacity(String groupId);
}
