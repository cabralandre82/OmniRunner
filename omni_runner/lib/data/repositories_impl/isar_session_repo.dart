// ignore_for_file: uri_has_not_been_generated, undefined_identifier, undefined_getter
import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/workout_session_record.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';

/// Isar implementation of [ISessionRepo].
///
/// Data layer. Converts between domain entities and Isar records.
/// All operations use Isar's async API.
final class IsarSessionRepo implements ISessionRepo {
  final Isar _isar;

  const IsarSessionRepo(this._isar);

  @override
  Future<void> save(WorkoutSessionEntity session) async {
    final record = _toRecord(session);
    await _isar.writeTxn(() async {
      final existing = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(session.id)
          .findFirst();
      if (existing != null) record.isarId = existing.isarId;
      await _isar.workoutSessionRecords.put(record);
    });
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async {
    final record = await _isar.workoutSessionRecords
        .where()
        .sessionUuidEqualTo(id)
        .findFirst();
    return record != null ? _toEntity(record) : null;
  }

  @override
  Future<List<WorkoutSessionEntity>> getAll() async {
    final records = await _isar.workoutSessionRecords
        .where()
        .sortByStartTimeMsDesc()
        .limit(50)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<List<WorkoutSessionEntity>> getByStatus(
    WorkoutStatus status,
  ) async {
    final records = await _isar.workoutSessionRecords
        .where()
        .statusEqualTo(_statusToInt(status))
        .sortByStartTimeMsDesc()
        .limit(50)
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    await _isar.writeTxn(() async {
      await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .deleteAll();
    });
  }

  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async {
    return _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .findFirst();
      if (record == null) return false;

      record.status = _statusToInt(status);
      await _isar.workoutSessionRecords.put(record);
      return true;
    });
  }

  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async {
    return _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .findFirst();
      if (record == null) return false;

      record.totalDistanceM = totalDistanceM;
      record.movingMs = movingMs;
      if (endTimeMs != null) record.endTimeMs = endTimeMs;
      await _isar.workoutSessionRecords.put(record);
      return true;
    });
  }

  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async {
    return _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .findFirst();
      if (record == null) return false;

      record.ghostSessionId = ghostSessionId;
      await _isar.workoutSessionRecords.put(record);
      return true;
    });
  }

  @override
  Future<bool> updateIntegrityFlags(
    String id, {
    required bool isVerified,
    required List<String> flags,
  }) async {
    return _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .findFirst();
      if (record == null) return false;
      record.isVerified = isVerified;
      record.integrityFlags = List.of(flags);
      await _isar.workoutSessionRecords.put(record);
      return true;
    });
  }

  @override
  Future<bool> updateHrMetrics(
    String id, {
    required int avgBpm,
    required int maxBpm,
  }) async {
    return _isar.writeTxn(() async {
      final record = await _isar.workoutSessionRecords
          .where()
          .sessionUuidEqualTo(id)
          .findFirst();
      if (record == null) return false;
      record.avgBpm = avgBpm;
      record.maxBpm = maxBpm;
      await _isar.workoutSessionRecords.put(record);
      return true;
    });
  }

  // ── Mappers ──

  WorkoutSessionRecord _toRecord(WorkoutSessionEntity entity) {
    return WorkoutSessionRecord()
      ..sessionUuid = entity.id
      ..userId = entity.userId
      ..status = _statusToInt(entity.status)
      ..startTimeMs = entity.startTimeMs
      ..endTimeMs = entity.endTimeMs
      ..totalDistanceM = entity.totalDistanceM ?? 0.0
      ..movingMs = 0
      ..isVerified = entity.isVerified
      ..isSynced = entity.isSynced
      ..ghostSessionId = entity.ghostSessionId
      ..integrityFlags = List.of(entity.integrityFlags)
      ..avgBpm = entity.avgBpm
      ..maxBpm = entity.maxBpm
      ..avgCadenceSpm = entity.avgCadenceSpm
      ..source = entity.source
      ..deviceName = entity.deviceName;
  }

  WorkoutSessionEntity _toEntity(WorkoutSessionRecord record) {
    return WorkoutSessionEntity(
      id: record.sessionUuid,
      userId: record.userId,
      status: _statusFromInt(record.status),
      startTimeMs: record.startTimeMs,
      endTimeMs: record.endTimeMs,
      totalDistanceM: record.totalDistanceM,
      route: const [],
      ghostSessionId: record.ghostSessionId,
      isVerified: record.isVerified,
      integrityFlags: List.unmodifiable(record.integrityFlags),
      isSynced: record.isSynced,
      avgBpm: record.avgBpm,
      maxBpm: record.maxBpm,
      avgCadenceSpm: record.avgCadenceSpm,
      source: record.source,
      deviceName: record.deviceName,
    );
  }

  static int _statusToInt(WorkoutStatus status) {
    return switch (status) {
      WorkoutStatus.initial => 0,
      WorkoutStatus.running => 1,
      WorkoutStatus.paused => 2,
      WorkoutStatus.completed => 3,
      WorkoutStatus.discarded => 4,
    };
  }

  static WorkoutStatus _statusFromInt(int value) {
    return switch (value) {
      0 => WorkoutStatus.initial,
      1 => WorkoutStatus.running,
      2 => WorkoutStatus.paused,
      3 => WorkoutStatus.completed,
      4 => WorkoutStatus.discarded,
      _ => WorkoutStatus.initial,
    };
  }
}
