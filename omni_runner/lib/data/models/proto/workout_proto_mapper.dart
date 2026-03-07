import 'dart:convert';
import 'dart:typed_data';

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
  static String pointsToJson(List<LocationPointEntity> points) {
    return jsonEncode(points.map(_pointToMap).toList());
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
