import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

/// A sustained high-speed segment detected during integrity verification.
final class SpeedViolation {
  /// Timestamp (ms) of the first point in the violating window.
  final int startMs;

  /// Timestamp (ms) of the point where the window reached [minWindowMs].
  final int endMs;

  /// Average speed across the violating window in m/s.
  final double avgSpeedMps;

  const SpeedViolation({
    required this.startMs,
    required this.endMs,
    required this.avgSpeedMps,
  });
}

/// Detects segments where sustained speed exceeds a plausible threshold.
///
/// **Rule:** average pair-wise speed > [maxSpeedMps] for a consecutive
/// window >= [minWindowMs] raises a `HIGH_SPEED` flag.
///
/// Short bursts (< [minWindowMs]) are tolerated so that legitimate
/// sprints are not penalised.
///
/// Returns a list of [SpeedViolation]s. Empty list = clean session.
///
/// Conforms to [O4]: single `call()` method.
final class IntegrityDetectSpeed {
  /// The integrity flag name emitted by this detector.
  static const String flag = 'HIGH_SPEED';

  /// Default maximum plausible speed (11.5 m/s ≈ 41.4 km/h).
  static const double defaultMaxSpeedMps = 11.5;

  /// Default minimum sustained window to trigger a violation (10 s).
  static const int defaultMinWindowMs = 10000;

  const IntegrityDetectSpeed();

  /// Scans [points] for sustained high-speed segments.
  ///
  /// Algorithm:
  /// 1. Walk consecutive pairs computing instant speed via Haversine.
  /// 2. While speed > [maxSpeedMps], grow a window from the first
  ///    high-speed point.
  /// 3. If the window duration >= [minWindowMs], record a violation
  ///    and advance past it.
  /// 4. If speed drops below threshold, reset the window.
  List<SpeedViolation> call(
    List<LocationPointEntity> points, {
    double maxSpeedMps = defaultMaxSpeedMps,
    int minWindowMs = defaultMinWindowMs,
  }) {
    if (points.length < 2) return const [];

    final violations = <SpeedViolation>[];
    int? windowStartMs;
    double windowDistM = 0;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dtMs = curr.timestampMs - prev.timestampMs;
      if (dtMs <= 0) continue;

      final dist = haversineMeters(
        lat1: prev.lat,
        lng1: prev.lng,
        lat2: curr.lat,
        lng2: curr.lng,
      );
      final speedMps = dist / (dtMs / 1000.0);

      if (speedMps > maxSpeedMps) {
        // Start or extend the high-speed window.
        windowStartMs ??= prev.timestampMs;
        windowDistM += dist;

        final windowDurMs = curr.timestampMs - windowStartMs;
        if (windowDurMs >= minWindowMs) {
          final avgSpeed = windowDistM / (windowDurMs / 1000.0);
          violations.add(SpeedViolation(
            startMs: windowStartMs,
            endMs: curr.timestampMs,
            avgSpeedMps: avgSpeed,
          ),);
          // Reset to detect further independent violations.
          windowStartMs = null;
          windowDistM = 0;
        }
      } else {
        // Speed dropped — reset window.
        windowStartMs = null;
        windowDistM = 0;
      }
    }

    return violations;
  }
}
