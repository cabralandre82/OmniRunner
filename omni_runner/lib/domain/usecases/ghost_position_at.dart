import 'package:omni_runner/domain/entities/ghost_session_entity.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// Estimates the ghost's position at a given elapsed time via linear
/// interpolation (LERP) between the two nearest route points.
///
/// The ghost's route is time-indexed: each point has a `timestampMs`.
/// Given an elapsed time since the ghost session started, we find the
/// two bracketing points and interpolate lat/lng by the time fraction.
///
/// Edge cases:
/// - Empty or single-point route: returns `null`.
/// - Before first point: clamps to first point.
/// - After last point: clamps to last point.
///
/// Conforms to [O4]: single `call()` method.
final class GhostPositionAt {
  const GhostPositionAt();

  /// Returns the interpolated [LocationPointEntity] at [elapsedMs]
  /// into the ghost session, or `null` if the route is too short.
  ///
  /// [elapsedMs] is relative to the ghost session start (0 = start).
  LocationPointEntity? call(
    GhostSessionEntity ghost,
    int elapsedMs,
  ) {
    final route = ghost.route;
    if (route.length < 2) return null;

    final originMs = route.first.timestampMs;
    final targetMs = originMs + elapsedMs;

    // Clamp: before first point.
    if (targetMs <= route.first.timestampMs) return route.first;
    // Clamp: after last point.
    if (targetMs >= route.last.timestampMs) return route.last;

    // Binary search for the segment containing targetMs.
    var lo = 0;
    var hi = route.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (route[mid].timestampMs <= targetMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final a = route[lo];
    final b = route[hi];
    final segMs = b.timestampMs - a.timestampMs;

    // Degenerate segment (same timestamp) — return the earlier point.
    if (segMs <= 0) return a;

    final t = (targetMs - a.timestampMs) / segMs;

    return LocationPointEntity(
      lat: a.lat + (b.lat - a.lat) * t,
      lng: a.lng + (b.lng - a.lng) * t,
      timestampMs: targetMs,
    );
  }
}
