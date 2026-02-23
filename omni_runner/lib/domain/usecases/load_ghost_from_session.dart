import 'package:omni_runner/domain/entities/ghost_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';

/// Loads a ghost session from a previously saved workout.
///
/// Reads the session metadata and its GPS points from persistence,
/// then constructs a [GhostSessionEntity] ready for replay.
///
/// Returns `null` if:
/// - Session does not exist
/// - Session has fewer than 2 points (not enough for interpolation)
///
/// Conforms to [O4]: single `call()` method.
final class LoadGhostFromSession {
  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;

  const LoadGhostFromSession({
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
  })  : _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo;

  /// Load a ghost from the session with [sessionId].
  ///
  /// Returns [GhostSessionEntity] or `null` if not viable.
  Future<GhostSessionEntity?> call(String sessionId) async {
    final session = await _sessionRepo.getById(sessionId);
    if (session == null) return null;

    final points = await _pointsRepo.getBySessionId(sessionId);
    if (points.length < 2) return null;

    final durationMs = points.last.timestampMs - points.first.timestampMs;
    if (durationMs <= 0) return null;

    return GhostSessionEntity(
      sessionId: sessionId,
      route: points,
      startTimeMs: session.startTimeMs,
      durationMs: durationMs,
    );
  }
}
