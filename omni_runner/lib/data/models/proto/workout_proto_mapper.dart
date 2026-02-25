import 'dart:convert';
import 'dart:typed_data';

import 'package:omni_runner/data/models/isar/workout_session_record.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Serialises workout data for backend upload.
///
/// Despite the "proto" directory name (reserved for future Protobuf),
/// this mapper currently produces **JSON** as defined by DECISAO 010
/// and `contracts/sync_payload.md`.
///
/// Swapping to Protobuf post-MVP requires changing only this file.
abstract final class WorkoutProtoMapper {
  /// Serialise a list of GPS points to compact JSON bytes.
  ///
  /// Null fields are omitted to reduce payload (~20% smaller).
  /// Returns a UTF-8 encoded `Uint8List` ready for Storage upload.
  static Uint8List pointsToBytes(List<LocationPointEntity> points) {
    final list = points.map(_pointToMap).toList();
    return Uint8List.fromList(utf8.encode(jsonEncode(list)));
  }

  /// Serialise a list of GPS points to a JSON string.
  ///
  /// Useful for debugging and tests.
  static String pointsToJson(List<LocationPointEntity> points) {
    return jsonEncode(points.map(_pointToMap).toList());
  }

  /// Build the Postgres upsert payload from a local Isar record.
  ///
  /// Matches the `sessions` table schema in `contracts/sync_payload.md`.
  static Map<String, Object?> sessionToPayload({
    required WorkoutSessionRecord record,
    required String userId,
    required String pointsPath,
  }) {
    return {
      'id': record.sessionUuid,
      'user_id': userId,
      'status': record.status,
      'start_time_ms': record.startTimeMs,
      'end_time_ms': record.endTimeMs,
      'total_distance_m': record.totalDistanceM,
      'moving_ms': record.movingMs,
      'is_verified': record.isVerified,
      'integrity_flags': record.integrityFlags,
      'ghost_session_id': record.ghostSessionId,
      'points_path': pointsPath,
      'source': record.source,
      if (record.deviceName != null) 'device_name': record.deviceName,
    };
  }

  static Map<String, Object> _pointToMap(LocationPointEntity p) {
    final m = <String, Object>{
      'lat': p.lat,
      'lng': p.lng,
      'timestampMs': p.timestampMs,
    };
    if (p.alt != null) m['alt'] = p.alt!;
    if (p.accuracy != null) m['accuracy'] = p.accuracy!;
    if (p.speed != null) m['speed'] = p.speed!;
    if (p.bearing != null) m['bearing'] = p.bearing!;
    return m;
  }
}
