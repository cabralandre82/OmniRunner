import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// A single GPS teleport (impossible jump) detected during verification.
final class TeleportViolation {
  /// Timestamp (ms) of the point before the jump.
  final int fromMs;

  /// Timestamp (ms) of the point after the jump.
  final int toMs;

  /// Distance of the jump in meters.
  final double distanceM;

  /// Implied speed of the jump in m/s.
  final double impliedSpeedMps;

  const TeleportViolation({
    required this.fromMs,
    required this.toMs,
    required this.distanceM,
    required this.impliedSpeedMps,
  });
}

/// Detects impossible GPS jumps between consecutive points.
///
/// **Rule:** if distance > [maxJumpDistM] within [maxDeltaMs] (normalised
/// to speed), and **both** points have accuracy ≤ [maxAccuracyM], flag
/// as `TELEPORT`. Pairs where either point has null or poor accuracy are
/// skipped — the jump is likely GPS noise, not deliberate cheating.
///
/// Returns a list of [TeleportViolation]s. Empty list = clean session.
///
/// Conforms to [O4]: single `call()` method.
final class IntegrityDetectTeleport {
  /// The integrity flag name emitted by this detector.
  static const String flag = 'TELEPORT';

  /// Default max jump distance in 1 second (50 m → 50 m/s = 180 km/h).
  static const double defaultMaxJumpDistM = 50.0;

  /// Default time window for the jump threshold (1 second).
  static const int defaultMaxDeltaMs = 1000;

  /// Default maximum accuracy to consider a point trustworthy.
  static const double defaultMaxAccuracyM = 15.0;

  const IntegrityDetectTeleport();

  /// Scans [points] for GPS teleport jumps.
  ///
  /// For each consecutive pair where both points have good accuracy:
  /// - Compute distance and deltaT.
  /// - Normalise threshold: `effectiveMaxDist = maxJumpDistM * (dt / maxDeltaMs)`.
  /// - If distance > effectiveMaxDist, record a [TeleportViolation].
  List<TeleportViolation> call(
    List<LocationPointEntity> points, {
    double maxJumpDistM = defaultMaxJumpDistM,
    int maxDeltaMs = defaultMaxDeltaMs,
    double maxAccuracyM = defaultMaxAccuracyM,
  }) {
    if (points.length < 2) return const [];

    final violations = <TeleportViolation>[];
    final speedThreshold = maxJumpDistM / (maxDeltaMs / 1000.0);

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];

      // Only flag when both points have confirmed good accuracy.
      if (!_accurate(prev, maxAccuracyM) || !_accurate(curr, maxAccuracyM)) {
        continue;
      }

      final dtMs = curr.timestampMs - prev.timestampMs;
      if (dtMs <= 0) continue;

      final dist = haversineMeters(
        lat1: prev.lat,
        lng1: prev.lng,
        lat2: curr.lat,
        lng2: curr.lng,
      );

      final speedMps = dist / (dtMs / 1000.0);
      if (speedMps > speedThreshold) {
        violations.add(TeleportViolation(
          fromMs: prev.timestampMs,
          toMs: curr.timestampMs,
          distanceM: dist,
          impliedSpeedMps: speedMps,
        ),);
      }
    }

    return violations;
  }

  /// Returns true if the point has known, acceptable accuracy.
  static bool _accurate(LocationPointEntity p, double maxM) =>
      p.accuracy != null && p.accuracy! <= maxM;
}
