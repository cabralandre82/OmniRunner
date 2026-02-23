import 'package:isar/isar.dart';

import 'package:omni_runner/data/models/isar/location_point_record.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';

/// Isar implementation of [IPointsRepo].
///
/// Data layer. Converts between domain entities and Isar records.
/// Uses composite index (sessionId + timestampMs) for ordered retrieval.
final class IsarPointsRepo implements IPointsRepo {
  final Isar _isar;

  const IsarPointsRepo(this._isar);

  @override
  Future<void> savePoint(
    String sessionId,
    LocationPointEntity point,
  ) async {
    final record = _toRecord(sessionId, point);
    await _isar.writeTxn(() async {
      await _isar.locationPointRecords.put(record);
    });
  }

  @override
  Future<void> savePoints(
    String sessionId,
    List<LocationPointEntity> points,
  ) async {
    final records = points.map((p) => _toRecord(sessionId, p)).toList();
    await _isar.writeTxn(() async {
      await _isar.locationPointRecords.putAll(records);
    });
  }

  @override
  Future<List<LocationPointEntity>> getBySessionId(
    String sessionId,
  ) async {
    final records = await _isar.locationPointRecords
        .where()
        .sessionIdEqualToAnyTimestampMs(sessionId)
        .sortByTimestampMs()
        .findAll();
    return records.map(_toEntity).toList();
  }

  @override
  Future<void> deleteBySessionId(String sessionId) async {
    await _isar.writeTxn(() async {
      await _isar.locationPointRecords
          .where()
          .sessionIdEqualToAnyTimestampMs(sessionId)
          .deleteAll();
    });
  }

  @override
  Future<int> countBySessionId(String sessionId) async {
    return _isar.locationPointRecords
        .where()
        .sessionIdEqualToAnyTimestampMs(sessionId)
        .count();
  }

  // ── Mappers ──

  LocationPointRecord _toRecord(
    String sessionId,
    LocationPointEntity entity,
  ) {
    return LocationPointRecord()
      ..sessionId = sessionId
      ..lat = entity.lat
      ..lng = entity.lng
      ..alt = entity.alt
      ..accuracy = entity.accuracy
      ..speed = entity.speed
      ..bearing = entity.bearing
      ..timestampMs = entity.timestampMs;
  }

  LocationPointEntity _toEntity(LocationPointRecord record) {
    return LocationPointEntity(
      lat: record.lat,
      lng: record.lng,
      alt: record.alt,
      accuracy: record.accuracy,
      speed: record.speed,
      bearing: record.bearing,
      timestampMs: record.timestampMs,
    );
  }
}
