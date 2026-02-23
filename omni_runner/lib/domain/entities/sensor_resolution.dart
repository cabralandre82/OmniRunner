import 'package:equatable/equatable.dart';

/// Which data source was selected for a given sensor type.
enum SensorSourceType {
  /// External BLE heart rate monitor (Polar, Garmin, Wahoo, etc.).
  ble,

  /// Apple HealthKit (iOS).
  healthKit,

  /// Google Health Connect (Android).
  healthConnect,

  /// No source available.
  none,
}

/// The result of resolving which data sources to use for HR and Steps.
///
/// Immutable value object produced by [SensorSourceResolver].
/// Contains the selected source type and a human-readable reason
/// for each decision — useful for debugging and logging.
final class SensorResolution extends Equatable {
  /// Selected HR data source.
  final SensorSourceType hrSource;

  /// Why this HR source was chosen (e.g. "BLE connected: Polar H10").
  final String hrReason;

  /// Selected Steps data source.
  final SensorSourceType stepsSource;

  /// Why this Steps source was chosen (e.g. "Health Connect available").
  final String stepsReason;

  const SensorResolution({
    required this.hrSource,
    required this.hrReason,
    required this.stepsSource,
    required this.stepsReason,
  });

  /// True if at least one source is active for HR.
  bool get hasHr => hrSource != SensorSourceType.none;

  /// True if at least one source is active for Steps.
  bool get hasSteps => stepsSource != SensorSourceType.none;

  @override
  List<Object?> get props => [hrSource, hrReason, stepsSource, stepsReason];

  @override
  String toString() =>
      'SensorResolution(hr=$hrSource [$hrReason], steps=$stepsSource [$stepsReason])';
}
