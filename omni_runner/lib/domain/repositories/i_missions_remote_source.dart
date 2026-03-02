import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';

/// Remote data source for mission definitions and progress.
///
/// The BLoC calls this to sync server state, then reads from local repos.
abstract interface class IMissionsRemoteSource {
  /// Fetches the full mission catalog from the server.
  Future<List<MissionEntity>> fetchMissionDefs();

  /// Fetches mission progress entries for [userId].
  Future<List<MissionProgressEntity>> fetchProgress(String userId);
}
