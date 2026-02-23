import 'package:omni_runner/core/utils/haversine.dart';
import 'package:omni_runner/domain/entities/location_point_entity.dart';

// ---------------------------------------------------------------------------
// Step cadence data source
// ---------------------------------------------------------------------------

/// A single step-cadence sample.
final class StepSample {
  /// Timestamp in milliseconds since Unix epoch (UTC).
  final int timestampMs;

  /// Steps per minute at this instant.
  final double spm;

  const StepSample({required this.timestampMs, required this.spm});
}

/// Abstract source of step-cadence data.
///
/// Implementations may read from a pedometer sensor, Health API, or a
/// recorded list. The detector only needs timestamped SPM values.
// ignore: one_member_abstracts
abstract interface class IStepsSource {
  /// Returns step samples covering the session, sorted by timestamp.
  ///
  /// May return an empty list if no sensor data is available.
  Future<List<StepSample>> samplesForSession(String sessionId);
}

// ---------------------------------------------------------------------------
// Violation entity
// ---------------------------------------------------------------------------

/// A window where GPS speed was high but step cadence was suspiciously low,
/// suggesting the user was in a vehicle.
final class VehicleViolation {
  /// Timestamp (ms) where the suspicious window started.
  final int startMs;

  /// Timestamp (ms) where the window ended (or was recorded).
  final int endMs;

  /// Average GPS-derived speed in m/s during the window.
  final double avgSpeedMps;

  /// Average step cadence (SPM) during the window.
  final double avgSpm;

  const VehicleViolation({
    required this.startMs,
    required this.endMs,
    required this.avgSpeedMps,
    required this.avgSpm,
  });
}

// ---------------------------------------------------------------------------
// Detector use case (batch mode)
// ---------------------------------------------------------------------------

/// Detects windows where GPS speed is high but step cadence is low,
/// indicating the device was likely in a vehicle.
///
/// **Rule:** speed > [minSpeedMps] AND cadence < [maxCadenceSpm] sustained
/// for >= [minWindowMs] → flag `VEHICLE_SUSPECT`.
///
/// If [steps] is null or empty the detector returns an empty list — it does
/// **not** invent data or penalise sessions without a pedometer.
///
/// Conforms to [O4]: single `call()` method.
final class IntegrityDetectVehicle {
  /// The integrity flag name emitted by this detector.
  static const String flag = 'VEHICLE_SUSPECT';

  /// Default minimum GPS speed to consider suspicious (4.2 m/s ≈ 15 km/h).
  static const double defaultMinSpeedMps = 4.2;

  /// Default maximum cadence — below this with high speed is suspect (140 SPM).
  static const double defaultMaxCadenceSpm = 140.0;

  /// Default minimum sustained window to trigger a violation (30 s).
  static const int defaultMinWindowMs = 30000;

  const IntegrityDetectVehicle();

  /// Scans [points] against [steps] for vehicle-suspect windows.
  ///
  /// Returns an empty list when [steps] is null, empty, or when there are
  /// fewer than 2 GPS points.
  List<VehicleViolation> call(
    List<LocationPointEntity> points, {
    List<StepSample>? steps,
    double minSpeedMps = defaultMinSpeedMps,
    double maxCadenceSpm = defaultMaxCadenceSpm,
    int minWindowMs = defaultMinWindowMs,
  }) {
    if (steps == null || steps.isEmpty || points.length < 2) return const [];

    final violations = <VehicleViolation>[];
    int? winStartMs;
    double winDistM = 0;
    double winSpmSum = 0;
    int winSpmCount = 0;

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final dtMs = curr.timestampMs - prev.timestampMs;
      if (dtMs <= 0) continue;

      final dist = haversineMeters(
        lat1: prev.lat, lng1: prev.lng,
        lat2: curr.lat, lng2: curr.lng,
      );
      final speedMps = dist / (dtMs / 1000.0);
      final spm = _avgSpmBetween(steps, prev.timestampMs, curr.timestampMs);

      if (speedMps > minSpeedMps && spm != null && spm < maxCadenceSpm) {
        winStartMs ??= prev.timestampMs;
        winDistM += dist;
        winSpmSum += spm;
        winSpmCount++;

        final winDurMs = curr.timestampMs - winStartMs;
        if (winDurMs >= minWindowMs) {
          violations.add(VehicleViolation(
            startMs: winStartMs,
            endMs: curr.timestampMs,
            avgSpeedMps: winDistM / (winDurMs / 1000.0),
            avgSpm: winSpmSum / winSpmCount,
          ));
          winStartMs = null;
          winDistM = 0;
          winSpmSum = 0;
          winSpmCount = 0;
        }
      } else {
        winStartMs = null;
        winDistM = 0;
        winSpmSum = 0;
        winSpmCount = 0;
      }
    }
    return violations;
  }

  /// Returns the average SPM of samples within [fromMs]..[toMs], or null.
  static double? _avgSpmBetween(
    List<StepSample> steps, int fromMs, int toMs,
  ) {
    double sum = 0;
    int count = 0;
    for (final s in steps) {
      if (s.timestampMs >= fromMs && s.timestampMs <= toMs) {
        sum += s.spm;
        count++;
      }
    }
    return count > 0 ? sum / count : null;
  }
}

// ---------------------------------------------------------------------------
// Sliding window detector (live/incremental)
// ---------------------------------------------------------------------------

/// Stateful sliding-window vehicle detector for live tracking.
///
/// Accumulates GPS points and step samples incrementally, running the
/// detection algorithm every [checkIntervalMs] milliseconds on a window
/// of the last [windowMs] milliseconds of data.
///
/// Usage:
/// ```dart
/// final detector = VehicleSlidingDetector();
/// // In tracking loop:
/// detector.addPoint(point);
/// detector.addStepSample(sample);
/// final violations = detector.check();
/// ```
final class VehicleSlidingDetector {
  /// How far back to look (default 30 s).
  final int windowMs;

  /// Minimum interval between checks to avoid CPU waste (default 5 s).
  final int checkIntervalMs;

  /// Speed threshold in m/s.
  final double minSpeedMps;

  /// Maximum cadence below which it's suspicious.
  final double maxCadenceSpm;

  /// Minimum sustained window to trigger a violation.
  final int minWindowMs;

  final _points = <LocationPointEntity>[];
  final _steps = <StepSample>[];
  int _lastCheckMs = 0;

  static const _detector = IntegrityDetectVehicle();

  VehicleSlidingDetector({
    this.windowMs = 60000,
    this.checkIntervalMs = 5000,
    this.minSpeedMps = IntegrityDetectVehicle.defaultMinSpeedMps,
    this.maxCadenceSpm = IntegrityDetectVehicle.defaultMaxCadenceSpm,
    this.minWindowMs = IntegrityDetectVehicle.defaultMinWindowMs,
  });

  /// Add a GPS point to the sliding window.
  void addPoint(LocationPointEntity point) {
    _points.add(point);
  }

  /// Add a step cadence sample to the sliding window.
  void addStepSample(StepSample sample) {
    _steps.add(sample);
  }

  /// Run the detector if enough time has elapsed since the last check.
  ///
  /// Returns violations found in the current window, or an empty list
  /// if not enough time has passed or no data is available.
  List<VehicleViolation> check() {
    if (_points.length < 2) return const [];

    final now = _points.last.timestampMs;
    if (now - _lastCheckMs < checkIntervalMs) return const [];
    _lastCheckMs = now;

    _evict(now);

    if (_points.length < 2) return const [];
    if (_steps.isEmpty) return const [];

    return _detector.call(
      _points,
      steps: _steps,
      minSpeedMps: minSpeedMps,
      maxCadenceSpm: maxCadenceSpm,
      minWindowMs: minWindowMs,
    );
  }

  /// Remove data older than the window.
  void _evict(int nowMs) {
    final cutoff = nowMs - windowMs;
    _points.removeWhere((p) => p.timestampMs < cutoff);
    _steps.removeWhere((s) => s.timestampMs < cutoff);
  }

  /// Reset all accumulated data. Call on session start.
  void reset() {
    _points.clear();
    _steps.clear();
    _lastCheckMs = 0;
  }

  /// Current number of GPS points in the window.
  int get pointCount => _points.length;

  /// Current number of step samples in the window.
  int get stepCount => _steps.length;
}
