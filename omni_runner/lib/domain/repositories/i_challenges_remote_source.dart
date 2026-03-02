import 'package:omni_runner/domain/entities/challenge_entity.dart';

/// Remote data source for challenge sync, creation, and settlement.
///
/// The BLoC calls this to interact with the backend Edge Functions.
/// All methods gracefully degrade when offline (return empty / no-op).
abstract interface class IChallengesRemoteSource {
  /// Fetches challenges for the current user from the backend.
  Future<List<ChallengeEntity>> fetchMyChallenges();

  /// Sends a newly created challenge to the backend (with retry).
  Future<void> syncNewChallenge(Map<String, dynamic> payload);

  /// Delegates challenge settlement to the backend Edge Function.
  /// Returns `true` if the backend handled it, `false` if offline/failed.
  Future<bool> settleChallenge(String challengeId);
}
