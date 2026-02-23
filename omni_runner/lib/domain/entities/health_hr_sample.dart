import 'package:equatable/equatable.dart';

/// A heart rate reading from the platform health service (HealthKit / Health Connect).
///
/// Immutable value object. Simpler than [HeartRateSample] (BLE) because
/// platform health data does not include RR intervals or sensor contact.
final class HealthHrSample extends Equatable {
  /// Heart rate in beats per minute.
  final int bpm;

  /// Start of the measurement in milliseconds since Unix epoch (UTC).
  final int startMs;

  /// End of the measurement in milliseconds since Unix epoch (UTC).
  final int endMs;

  const HealthHrSample({
    required this.bpm,
    required this.startMs,
    required this.endMs,
  });

  @override
  List<Object?> get props => [bpm, startMs, endMs];
}
