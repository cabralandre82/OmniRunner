import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/features/watch_bridge/watch_bridge.dart';
import 'package:omni_runner/features/watch_bridge/watch_session_payload.dart';

/// Use case: receive a [WatchSessionPayload] from the watch bridge,
/// persist it as a [WorkoutSessionEntity] + GPS points, and send an ACK.
///
/// Idempotent: if a session with the same ID already exists, it is skipped
/// to avoid duplicates from retransmissions.
///
/// Follows Clean Architecture: depends only on domain interfaces.
class ProcessWatchSession {
  ProcessWatchSession({
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
    required WatchBridge watchBridge,
  })  : _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo,
        _watchBridge = watchBridge;

  static const _tag = 'ProcessWatchSession';

  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;
  final WatchBridge _watchBridge;

  /// Process a complete watch session.
  ///
  /// Returns `true` if the session was persisted successfully
  /// (or already existed). Returns `false` on error.
  Future<bool> call(WatchSessionPayload payload) async {
    try {
      // ── Idempotency check ──────────────────────────────────────
      final existing = await _sessionRepo.getById(payload.sessionId);
      if (existing != null) {
        AppLogger.debug(
          'Session ${payload.sessionId} already exists — skipping (idempotent)',
          tag: _tag,
        );
        await _watchBridge.acknowledgeSession(payload.sessionId);
        return true;
      }

      // ── Create session entity ──────────────────────────────────
      final session = WorkoutSessionEntity(
        id: payload.sessionId,
        status: WorkoutStatus.completed,
        startTimeMs: payload.startMs,
        endTimeMs: payload.endMs,
        totalDistanceM: payload.totalDistanceM,
        route: payload.points,
        isVerified: payload.isVerified,
        integrityFlags: payload.integrityFlags,
        avgBpm: payload.avgBpm > 0 ? payload.avgBpm : null,
        maxBpm: payload.maxBpm > 0 ? payload.maxBpm : null,
      );

      // ── Persist ────────────────────────────────────────────────
      await _sessionRepo.save(session);

      if (payload.points.isNotEmpty) {
        await _pointsRepo.savePoints(payload.sessionId, payload.points);
      }

      AppLogger.info(
        'Persisted session ${payload.sessionId} '
        '(${payload.source}: ${payload.points.length} GPS, '
        '${payload.hrSamples.length} HR, '
        '${payload.totalDistanceM.toStringAsFixed(0)} m)',
        tag: _tag,
      );

      // ── ACK the watch ──────────────────────────────────────────
      await _watchBridge.acknowledgeSession(payload.sessionId);

      return true;
    } on Exception catch (e, st) {
      AppLogger.error(
        'Failed to process ${payload.sessionId}: $e',
        tag: _tag,
        error: e,
        stack: st,
      );
      return false;
    }
  }
}
