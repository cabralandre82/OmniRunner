import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_session_repo.dart';

/// Drift implementation of [ISessionRepo].
///
/// Data layer. Converts between domain entities and Drift rows.
/// All operations use Drift's async API.
final class DriftSessionRepo implements ISessionRepo {
  final AppDatabase _db;

  const DriftSessionRepo(this._db);

  @override
  Future<void> save(WorkoutSessionEntity session) async {
    await _db.into(_db.workoutSessions).insertOnConflictUpdate(
          _toCompanion(session),
        );
  }

  @override
  Future<WorkoutSessionEntity?> getById(String id) async {
    final query = _db.select(_db.workoutSessions)
      ..where((t) => t.sessionUuid.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<List<WorkoutSessionEntity>> getAll() async {
    final query = _db.select(_db.workoutSessions)
      ..orderBy([(t) => OrderingTerm.desc(t.startTimeMs)])
      ..limit(50);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<WorkoutSessionEntity>> getByStatus(
    WorkoutStatus status,
  ) async {
    final query = _db.select(_db.workoutSessions)
      ..where((t) => t.status.equals(_statusToInt(status)))
      ..orderBy([(t) => OrderingTerm.desc(t.startTimeMs)])
      ..limit(50);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .go();
  }

  @override
  Future<bool> updateStatus(String id, WorkoutStatus status) async {
    final count = await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(WorkoutSessionsCompanion(
      status: Value(_statusToInt(status)),
    ));
    return count > 0;
  }

  @override
  Future<bool> updateMetrics({
    required String id,
    required double totalDistanceM,
    required int movingMs,
    int? endTimeMs,
  }) async {
    final count = await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(WorkoutSessionsCompanion(
      totalDistanceM: Value(totalDistanceM),
      movingMs: Value(movingMs),
      endTimeMs: endTimeMs != null ? Value(endTimeMs) : const Value.absent(),
    ));
    return count > 0;
  }

  @override
  Future<bool> updateGhostSessionId(String id, String ghostSessionId) async {
    final count = await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(WorkoutSessionsCompanion(
      ghostSessionId: Value(ghostSessionId),
    ));
    return count > 0;
  }

  @override
  Future<bool> updateIntegrityFlags(
    String id, {
    required bool isVerified,
    required List<String> flags,
  }) async {
    final count = await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(WorkoutSessionsCompanion(
      isVerified: Value(isVerified),
      integrityFlags: Value(flags),
    ));
    return count > 0;
  }

  @override
  Future<bool> updateHrMetrics(
    String id, {
    required int avgBpm,
    required int maxBpm,
  }) async {
    final count = await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(WorkoutSessionsCompanion(
      avgBpm: Value(avgBpm),
      maxBpm: Value(maxBpm),
    ));
    return count > 0;
  }

  @override
  Future<List<WorkoutSessionEntity>> getUnsyncedCompleted() async {
    final query = _db.select(_db.workoutSessions)
      ..where((t) =>
          t.isSynced.equals(false) &
          t.status.equals(_statusToInt(WorkoutStatus.completed)))
      ..orderBy([(t) => OrderingTerm.asc(t.startTimeMs)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> markSynced(String id) async {
    await (_db.update(_db.workoutSessions)
          ..where((t) => t.sessionUuid.equals(id)))
        .write(const WorkoutSessionsCompanion(isSynced: Value(true)));
  }

  // ── Mappers ──

  static WorkoutSessionsCompanion _toCompanion(WorkoutSessionEntity entity) {
    return WorkoutSessionsCompanion.insert(
      sessionUuid: entity.id,
      userId: Value(entity.userId),
      status: _statusToInt(entity.status),
      startTimeMs: entity.startTimeMs,
      endTimeMs: Value(entity.endTimeMs),
      totalDistanceM: entity.totalDistanceM ?? 0.0,
      movingMs: 0, // initial; updated via updateMetrics() during session
      isVerified: entity.isVerified,
      isSynced: entity.isSynced,
      ghostSessionId: Value(entity.ghostSessionId),
      integrityFlags: Value(List.of(entity.integrityFlags)),
      avgBpm: Value(entity.avgBpm),
      maxBpm: Value(entity.maxBpm),
      avgCadenceSpm: Value(entity.avgCadenceSpm),
      source: Value(entity.source),
      deviceName: Value(entity.deviceName),
    );
  }

  static WorkoutSessionEntity _toEntity(WorkoutSession row) {
    return WorkoutSessionEntity(
      id: row.sessionUuid,
      userId: row.userId,
      status: _statusFromInt(row.status),
      startTimeMs: row.startTimeMs,
      endTimeMs: row.endTimeMs,
      totalDistanceM: row.totalDistanceM,
      route: const [], // loaded separately via IPointsRepo.getBySessionId()
      ghostSessionId: row.ghostSessionId,
      isVerified: row.isVerified,
      integrityFlags: List.unmodifiable(row.integrityFlags),
      isSynced: row.isSynced,
      avgBpm: row.avgBpm,
      maxBpm: row.maxBpm,
      avgCadenceSpm: row.avgCadenceSpm,
      source: row.source,
      deviceName: row.deviceName,
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
