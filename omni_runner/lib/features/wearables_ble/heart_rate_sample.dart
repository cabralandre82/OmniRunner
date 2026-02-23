import 'package:equatable/equatable.dart';

/// A single heart rate reading from a BLE sensor.
///
/// Immutable value object. Follows the same pattern as [LocationPointEntity].
final class HeartRateSample extends Equatable {
  /// Heart rate in beats per minute.
  final int bpm;

  /// Whether the sensor has skin contact.
  ///
  /// `null` if the sensor does not report contact status.
  final bool? sensorContact;

  /// RR intervals in milliseconds (beat-to-beat intervals).
  ///
  /// Empty if the sensor does not report RR data.
  /// Multiple values may be present per notification (accumulated).
  final List<int> rrIntervalsMs;

  /// Energy expended in kilojoules (cumulative since last reset).
  ///
  /// `null` if not reported by the sensor.
  final int? energyExpendedKj;

  /// Timestamp in milliseconds since Unix epoch (UTC).
  final int timestampMs;

  const HeartRateSample({
    required this.bpm,
    this.sensorContact,
    this.rrIntervalsMs = const [],
    this.energyExpendedKj,
    required this.timestampMs,
  });

  @override
  List<Object?> get props => [
        bpm,
        sensorContact,
        rrIntervalsMs,
        energyExpendedKj,
        timestampMs,
      ];
}
