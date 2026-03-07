import 'package:drift/drift.dart';
import 'package:omni_runner/data/datasources/drift_database.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';

/// Drift implementation of [IPointsRepo].
///
/// Data layer. Converts between domain entities and Drift rows.
/// Uses composite index (sessionId + timestampMs) for ordered retrieval.
final class DriftPointsRepo implements IPointsRepo {
  final AppDatabase _db;

  const DriftPointsRepo(this._db);

  @override
  Future<void> savePoint(
    String sessionId,
    LocationPointEntity point,
  ) async {
    await _db.into(_db.locationPoints).insert(_toCompanion(sessionId, point));
  }

  @override
  Future<void> savePoints(
    String sessionId,
    List<LocationPointEntity> points,
  ) async {
    final companions = points.map((p) => _toCompanion(sessionId, p)).toList();
    await _db.batch((b) {
      b.insertAll(_db.locationPoints, companions);
    });
  }

  @override
  Future<List<LocationPointEntity>> getBySessionId(
    String sessionId,
  ) async {
    final query = _db.select(_db.locationPoints)
      ..where((t) => t.sessionId.equals(sessionId))
      ..orderBy([(t) => OrderingTerm.asc(t.timestampMs)]);
    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> deleteBySessionId(String sessionId) async {
    await (_db.delete(_db.locationPoints)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  @override
  Future<int> countBySessionId(String sessionId) async {
    final count = countAll();
    final query = _db.selectOnly(_db.locationPoints)
      ..addColumns([count])
      ..where(_db.locationPoints.sessionId.equals(sessionId));
    final row = await query.getSingle();
    return row.read(count)!;
  }

  // ── Mappers ──

  static LocationPointsCompanion _toCompanion(
    String sessionId,
    LocationPointEntity entity,
  ) {
    return LocationPointsCompanion.insert(
      sessionId: sessionId,
      lat: entity.lat,
      lng: entity.lng,
      alt: Value(entity.alt),
      accuracy: Value(entity.accuracy),
      speed: Value(entity.speed),
      bearing: Value(entity.bearing),
      timestampMs: entity.timestampMs,
    );
  }

  static LocationPointEntity _toEntity(LocationPoint row) {
    return LocationPointEntity(
      lat: row.lat,
      lng: row.lng,
      alt: row.alt,
      accuracy: row.accuracy,
      speed: row.speed,
      bearing: row.bearing,
      timestampMs: row.timestampMs,
    );
  }
}
