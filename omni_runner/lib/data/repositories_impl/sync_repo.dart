import 'dart:typed_data';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/data/datasources/sync_service.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/failures/sync_failure.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/features/integrations_export/data/fit/fit_encoder.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';

class SyncRepo implements ISyncRepo {
  static const _tag = 'SyncRepo';
  final SyncService _svc;
  final ISessionRepo _sessionRepo;
  final IPointsRepo _pointsRepo;

  const SyncRepo({
    required SyncService service,
    required ISessionRepo sessionRepo,
    required IPointsRepo pointsRepo,
  })  : _svc = service,
        _sessionRepo = sessionRepo,
        _pointsRepo = pointsRepo;

  @override
  Future<void> enqueue(String sessionId) async {
    final session = await _sessionRepo.getById(sessionId);
    if (session == null) return;
  }

  @override
  Future<SyncFailure?> syncPending() async {
    if (!_svc.isConfigured) return const SyncNotConfigured();
    if (!await _svc.hasConnection()) return const SyncNoConnection();
    final userId = _svc.userId;
    if (userId == null || userId.isEmpty) return const SyncNotAuthenticated();

    final pending = await _sessionRepo.getUnsyncedCompleted();

    AppLogger.info('Syncing ${pending.length} pending session(s)', tag: _tag);
    SyncFailure? firstFailure;
    for (final session in pending) {
      final failure = await _syncOne(session, userId);
      if (failure != null) {
        AppLogger.warn('Sync failed for ${session.id}: $failure', tag: _tag);
        firstFailure ??= failure;
      }
    }
    if (firstFailure == null && pending.isNotEmpty) {
      AppLogger.info('All ${pending.length} session(s) synced', tag: _tag);
    }
    return firstFailure;
  }

  @override
  Future<void> markSynced(String sessionId) async {
    await _sessionRepo.markSynced(sessionId);
  }

  Future<SyncFailure?> _syncOne(
    WorkoutSessionEntity session,
    String userId,
  ) async {
    try {
      final points = await _pointsRepo.getBySessionId(session.id);
      if (points.isEmpty) {
        await markSynced(session.id);
        return null;
      }

      final storagePath = await _svc.uploadPoints(
        userId: userId,
        sessionId: session.id,
        points: points,
      );

      await _svc.upsertSession(
        _sessionToPayload(session, userId, storagePath),
      );

      await markSynced(session.id);

      _triggerVerification(session, userId, points);
      _autoUploadStrava(session, points);

      return null;
    } on Exception catch (e, st) {
      final msg = e.toString();
      AppLogger.error('Sync error: $msg', tag: _tag, error: e, stack: st);
      if (msg.contains('TimeoutException') || msg.contains('timeout')) {
        return const SyncTimeout();
      }
      return SyncServerError(msg);
    }
  }

  Map<String, Object?> _sessionToPayload(
    WorkoutSessionEntity session,
    String userId,
    String pointsPath,
  ) {
    return {
      'session_uuid': session.id,
      'user_id': userId,
      'status': 3,
      'start_time_ms': session.startTimeMs,
      'end_time_ms': session.endTimeMs,
      'total_distance_m': session.totalDistanceM,
      'points_path': pointsPath,
      'is_verified': session.isVerified,
      'avg_bpm': session.avgBpm,
      'max_bpm': session.maxBpm,
      'avg_cadence_spm': session.avgCadenceSpm,
      'source': session.source,
      'device_name': session.deviceName,
    };
  }

  void _autoUploadStrava(
    WorkoutSessionEntity session,
    List<LocationPointEntity> points,
  ) {
    Future<void>(() async {
      try {
        final authRepo = sl<IStravaAuthRepository>();
        final state = await authRepo.getAuthState();
        if (state is! StravaConnected) return;

        final fitBytes = const FitEncoder().encode(
          session: session,
          route: points,
        );

        final uploadRepo = sl<IStravaUploadRepository>();
        await uploadRepo.uploadAndWait(
          StravaUploadRequest(
            sessionId: session.id,
            fileBytes: Uint8List.fromList(fitBytes),
            format: ExportFormat.fit,
            activityName: 'Corrida — Omni Runner',
          ),
        );
      } on Object catch (e) {
        AppLogger.warn('Strava auto-upload failed (non-blocking): $e', tag: _tag);
      }
    });
  }

  void _triggerVerification(
    WorkoutSessionEntity session,
    String userId,
    List<LocationPointEntity> points,
  ) {
    final route = points
        .map((p) => <String, Object>{
              'lat': p.lat,
              'lng': p.lng,
              'timestamp_ms': p.timestampMs,
              if (p.alt != null) 'alt': p.alt!,
              if (p.accuracy != null) 'accuracy': p.accuracy!,
              if (p.speed != null) 'speed': p.speed!,
            })
        .toList();

    _svc.verifySession(
      sessionId: session.id,
      userId: userId,
      route: route,
      totalDistanceM: session.totalDistanceM ?? 0,
      startTimeMs: session.startTimeMs,
      endTimeMs: session.endTimeMs ?? session.startTimeMs,
      avgCadenceSpm: session.avgCadenceSpm,
    );
  }
}
