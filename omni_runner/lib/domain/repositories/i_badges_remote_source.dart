import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';

/// Remote data source for badge catalog, awards, and retroactive evaluation.
///
/// The BLoC calls this to sync server state, then reads from local repos.
abstract interface class IBadgesRemoteSource {
  /// Triggers server-side retroactive badge evaluation for [userId].
  /// No-op when offline.
  Future<void> evaluateRetroactive(String userId);

  /// Fetches the full badge catalog from the server.
  Future<List<BadgeEntity>> fetchCatalog();

  /// Fetches badge awards for [userId] from the server.
  Future<List<BadgeAwardEntity>> fetchAwards(String userId);
}
