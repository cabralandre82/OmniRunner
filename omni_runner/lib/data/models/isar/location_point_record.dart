import 'package:isar/isar.dart';

part 'location_point_record.g.dart';

/// Isar collection for persisting GPS location points.
///
/// Each record belongs to a workout session via [sessionId].
/// Stored locally for offline-first operation.
///
/// Maps to/from [LocationPointEntity] in the domain layer.
@collection
class LocationPointRecord {
  /// Auto-incremented primary key.
  Id id = Isar.autoIncrement;

  /// Foreign key linking to the parent workout session.
  /// Composite index with [timestampMs] for ordered retrieval.
  @Index(composite: [CompositeIndex('timestampMs')])
  late String sessionId;

  /// Latitude in decimal degrees (-90 to 90).
  late double lat;

  /// Longitude in decimal degrees (-180 to 180).
  late double lng;

  /// Altitude in meters above sea level. Null if unavailable.
  double? alt;

  /// Horizontal accuracy in meters. Null if unavailable.
  double? accuracy;

  /// Speed in meters per second. Null if unavailable.
  double? speed;

  /// Bearing in degrees (0-360). Null if unavailable.
  double? bearing;

  /// Timestamp in milliseconds since Unix epoch (UTC).
  late int timestampMs;
}
