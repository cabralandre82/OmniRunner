import 'dart:typed_data';

import 'package:isar/isar.dart';

import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/data/datasources/sync_service.dart';
import 'package:omni_runner/data/models/isar/workout_session_record.dart';
import 'package:omni_runner/data/models/proto/workout_proto_mapper.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/failures/sync_failure.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/domain/repositories/i_sync_repo.dart';
import 'package:omni_runner/features/integrations_export/data/fit/fit_encoder.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';

/// Implements [ISyncRepo] using Supabase (via [SyncService]) and Isar.
///
/// Offline-first: sessions are synced only when connectivity is available.
/// Upload order: points (Storage) -> metadata (Postgres) -> mark synced.
class SyncRepo implements ISyncRepo {
  static const _tag = 'SyncRepo';
  final SyncService _svc;
  final Isar _isar;
  final IPointsRepo _pointsRepo;

  const SyncRepo({
    required SyncService service,
    required Isar isar,
    required IPointsRepo pointsRepo,
  })  : _svc = service,
        _isar = isar,
        _pointsRepo = pointsRepo;

  /// Status int for completed sessions (matches [WorkoutStatus.completed]).
  static const _completedStatus = 3;

  @override
  Future<void> enqueue(String sessionId) async {
    // Sessions already default to isSynced = false.
    // This is a no-op verification; future: could set a dedicated flag.
    final record = await _isar.workoutSessionRecords
        .where()
        .sessionUuidEqualTo(sessionId)
        .findFirst();
    if (record == null || record.status != _completedStatus) return;
  }

  @override
  Future<SyncFailure?> syncPending() async {
    if (!_svc.isConfigured) return const SyncNotConfigured();
    if (!await _svc.hasConnection()) return const SyncNoConnection();
    final userId = _svc.userId;
    if (userId == null || userId.isEmpty) return const SyncNotAuthenticated();

    final pending = await _isar.workoutSessionRecords
        .where()
        .isSyncedEqualTo(false)
        .filter()
        .statusEqualTo(_completedStatus)
        .findAll();

    AppLogger.info('Syncing ${pending.length} pending session(s)', tag: _tag);
    SyncFailure? firstFailure;
    for (final record in pending) {
      final failure = await _syncOne(record, userId);
      if (failure != null) {
        AppLogger.warn('Sync failed for ${record.sessionUuid}: $failure', tag: _tag);
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
    await _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(sessionId)
          .findFirst();
      if (record == null) return;
      record.isSynced = true;
      await _isar.workoutSessionRecords.put(record);
    });
  }

  // ── Private ──

  Future<SyncFailure?> _syncOne(
    WorkoutSessionRecord record,
    String userId,
  ) async {
    try {
      final points = await _pointsRepo.getBySessionId(record.sessionUuid);
      if (points.isEmpty) {
        await markSynced(record.sessionUuid);
        return null;
      }

      // 1. Upload points to Storage
      final storagePath = await _svc.uploadPoints(
        userId: userId,
        sessionId: record.sessionUuid,
        points: points,
      );

      // 2. Upsert metadata to Postgres
      await _svc.upsertSession(
        WorkoutProtoMapper.sessionToPayload(
          record: record,
          userId: userId,
          pointsPath: storagePath,
        ),
      );

      // 3. Mark synced locally
      await markSynced(record.sessionUuid);

      // 4. Server-side verification (fire-and-forget)
      _triggerVerification(record, userId, points);

      // 5. Auto-upload to Strava (fire-and-forget)
      _autoUploadStrava(record, points);

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

  void _autoUploadStrava(
    WorkoutSessionRecord record,
    List<LocationPointEntity> points,
  ) {
    Future<void>(() async {
      try {
        final authRepo = sl<IStravaAuthRepository>();
        final state = await authRepo.getAuthState();
        if (state is! StravaConnected) return;

        final session = WorkoutSessionEntity(
          id: record.sessionUuid,
          userId: record.userId,
          startTimeMs: record.startTimeMs,
          endTimeMs: record.endTimeMs ?? record.startTimeMs,
          totalDistanceM: record.totalDistanceM,
          status: WorkoutStatus.completed,
          route: points,
          isSynced: true,
        );

        final fitBytes = const FitEncoder().encode(
          session: session,
          route: points,
        );

        final uploadRepo = sl<IStravaUploadRepository>();
        final status = await uploadRepo.uploadAndWait(
          StravaUploadRequest(
            sessionId: record.sessionUuid,
            fileBytes: Uint8List.fromList(fitBytes),
            format: ExportFormat.fit,
            activityName: 'Corrida — Omni Runner',
          ),
        );

        AppLogger.info(
          'Strava auto-upload: ${status.runtimeType}',
          tag: _tag,
        );
      } catch (e) {
        AppLogger.warn('Strava auto-upload failed (non-blocking): $e', tag: _tag);
      }
    });
  }

  void _triggerVerification(
    WorkoutSessionRecord record,
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
      sessionId: record.sessionUuid,
      userId: userId,
      route: route,
      totalDistanceM: record.totalDistanceM,
      startTimeMs: record.startTimeMs,
      endTimeMs: record.endTimeMs ?? record.startTimeMs,
      avgCadenceSpm: record.avgCadenceSpm,
    );
  }
}
