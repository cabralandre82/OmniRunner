import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/utils/calculate_moving_ms.dart';
import 'package:omni_runner/domain/entities/workout_metrics_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/domain/usecases/accumulate_distance.dart';
import 'package:omni_runner/domain/usecases/calculate_pace.dart';
import 'package:omni_runner/domain/usecases/filter_location_points.dart';

/// Result of finishing a workout session.
final class FinishSessionResult {
  /// Whether the session was found and finalized.
  final bool success;

  /// Computed final metrics. Null if session not found.
  final WorkoutMetricsEntity? metrics;

  const FinishSessionResult({required this.success, this.metrics});
}

/// Finalizes a workout session: computes totals and persists summary.
///
/// Steps:
/// 1. Load all points for the session.
/// 2. Run filter -> accumulate -> pace pipeline.
/// 3. Calculate moving time and average pace.
/// 4. Update session record with final metrics.
/// 5. Set status to [WorkoutStatus.completed].
///
/// Conforms to [O4]: single `call()` method.
final class FinishSession {
  static const _tag = 'FinishSession';

  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;
  final ISyncRepo? _syncRepo;
  final FilterLocationPoints _filter;
  final AccumulateDistance _accumulate;
  final CalculatePace _pace;

  const FinishSession({
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
    ISyncRepo? syncRepo,
    FilterLocationPoints filter = const FilterLocationPoints(),
    AccumulateDistance accumulate = const AccumulateDistance(),
    CalculatePace pace = const CalculatePace(),
  })  : _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo,
        _syncRepo = syncRepo,
        _filter = filter,
        _accumulate = accumulate,
        _pace = pace;

  /// Finalize the session with the given [sessionId].
  ///
  /// [endTimeMs] is the timestamp when the user pressed "Finish".
  /// If null, uses the timestamp of the last GPS point.
  /// [ghostSessionId] stores the ghost session used during this run.
  /// [isVerified] and [integrityFlags] store anti-cheat verification results.
  ///
  /// Returns [FinishSessionResult] with success flag and final metrics.
  Future<FinishSessionResult> call({
    required String sessionId,
    int? endTimeMs,
    String? ghostSessionId,
    bool isVerified = true,
    List<String> integrityFlags = const [],
  }) async {
    try {
      final session = await _sessionRepo.getById(sessionId);
      if (session == null) {
        return const FinishSessionResult(success: false);
      }

      final rawPoints = await _pointsRepo.getBySessionId(sessionId);

      final resolvedEndTimeMs = endTimeMs ??
          (rawPoints.isNotEmpty
              ? rawPoints.last.timestampMs
              : session.startTimeMs);

      // Phase 03 math engine.
      final filteredPoints = _filter(rawPoints);
      final totalDistanceM = _accumulate(filteredPoints);
      final currentPace = _pace(filteredPoints);
      final elapsedMs = resolvedEndTimeMs - session.startTimeMs;
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

      await _sessionRepo.updateMetrics(
        id: sessionId,
        totalDistanceM: totalDistanceM,
        movingMs: movingMs,
        endTimeMs: resolvedEndTimeMs,
      );
      await _sessionRepo.updateStatus(sessionId, WorkoutStatus.completed);
      if (ghostSessionId != null) {
        await _sessionRepo.updateGhostSessionId(sessionId, ghostSessionId);
      }
      if (!isVerified || integrityFlags.isNotEmpty) {
        await _sessionRepo.updateIntegrityFlags(
          sessionId,
          isVerified: isVerified,
          flags: integrityFlags,
        );
      }

      await _syncRepo?.enqueue(sessionId);
      return FinishSessionResult(success: true, metrics: metrics);
    } on Exception catch (e, st) {
      AppLogger.error(
        'Failed to finish session $sessionId',
        tag: _tag,
        error: e,
        stack: st,
      );
      return const FinishSessionResult(success: false);
    }
  }
}
