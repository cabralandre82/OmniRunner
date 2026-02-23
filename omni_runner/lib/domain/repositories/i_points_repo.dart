import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Contract for persisting and retrieving GPS location points.
///
/// Domain interface. Implementation lives in data layer.
/// Points are always associated with a session via sessionId.
///
/// Dependency direction: data → domain (implements this).
abstract interface class IPointsRepo {
  /// Save a single location point for a session.
  Future<void> savePoint(String sessionId, LocationPointEntity point);

  /// Save multiple location points for a session in a batch.
  ///
  /// More efficient than saving one at a time during tracking.
  Future<void> savePoints(
    String sessionId,
    List<LocationPointEntity> points,
  );

  /// Retrieve all points for a session, ordered by timestamp ascending.
  Future<List<LocationPointEntity>> getBySessionId(String sessionId);

  /// Delete all points for a session.
  ///
  /// Called when a session is deleted or discarded.
  Future<void> deleteBySessionId(String sessionId);

  /// Count the number of points for a session.
  ///
  /// Lightweight query without loading point data.
  Future<int> countBySessionId(String sessionId);
}
