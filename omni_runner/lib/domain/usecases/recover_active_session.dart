import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/calculate_moving_ms.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';

/// Result of attempting to recover an active (non-finalized) session.
///
/// Contains the session, its points, and recalculated metrics.
final class RecoveredSession {
  final WorkoutSessionEntity session;
  final List<LocationPointEntity> rawPoints;
  final List<LocationPointEntity> filteredPoints;
  final WorkoutMetricsEntity metrics;

  const RecoveredSession({
    required this.session,
    required this.rawPoints,
    required this.filteredPoints,
    required this.metrics,
  });
}

/// Detects and recovers an active (RUNNING or PAUSED) session on app start.
///
/// Use case for crash recovery / app restart scenarios.
/// Queries persistence for non-finalized sessions, loads their points,
/// and recalculates metrics using the Phase 03 math engine.
///
/// Conforms to [O4]: single `call()` method.
final class RecoverActiveSession {
  static const _tag = 'RecoverActiveSession';

  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;
  final FilterLocationPoints _filter;
  final AccumulateDistance _accumulate;
  final CalculatePace _pace;

  const RecoverActiveSession({
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
    FilterLocationPoints filter = const FilterLocationPoints(),
    AccumulateDistance accumulate = const AccumulateDistance(),
    CalculatePace pace = const CalculatePace(),
  })  : _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo,
        _filter = filter,
        _accumulate = accumulate,
        _pace = pace;

  /// Attempt to find and recover an active session.
  ///
  /// Returns [RecoveredSession] if found, `null` otherwise.
  /// Priority: RUNNING first, then PAUSED.
  Future<RecoveredSession?> call() async {
    try {
      var active = await _sessionRepo.getByStatus(WorkoutStatus.running);
      if (active.isEmpty) {
        active = await _sessionRepo.getByStatus(WorkoutStatus.paused);
      }
      if (active.isEmpty) return null;

      final session = active.first;
      final rawPoints = await _pointsRepo.getBySessionId(session.id);

      final sessionWithRoute = WorkoutSessionEntity(
        id: session.id,
        userId: session.userId,
        status: session.status,
        startTimeMs: session.startTimeMs,
        endTimeMs: session.endTimeMs,
        route: rawPoints,
      );

      final filteredPoints = _filter(rawPoints);
      final totalDistanceM = _accumulate(filteredPoints);
      final currentPace = _pace(filteredPoints);
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = (session.endTimeMs ?? now) - session.startTimeMs;
      final movingMs = calculateMovingMs(filteredPoints);

      final double? avgPace;
      if (totalDistanceM > 0 && movingMs > 0) {
        avgPace = (movingMs / 1000.0) / (totalDistanceM / 1000.0);
      } else {
        avgPace = null;
      }

      final metrics = WorkoutMetricsEntity(
        totalDistanceM: totalDistanceM,
        elapsedMs: elapsedMs < 0 ? 0 : elapsedMs,
        movingMs: movingMs,
        currentPaceSecPerKm: currentPace,
        avgPaceSecPerKm: avgPace,
        pointsCount: rawPoints.length,
      );

      return RecoveredSession(
        session: sessionWithRoute,
        rawPoints: rawPoints,
        filteredPoints: filteredPoints,
        metrics: metrics,
      );
    } on Exception catch (e, st) {
      AppLogger.error('Failed to recover active session', tag: _tag, error: e, stack: st);
      return null;
    }
  }
}
