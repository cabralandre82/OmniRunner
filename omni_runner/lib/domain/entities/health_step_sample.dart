import 'package:equatable/equatable.dart';

/// A step count reading from the platform health service.
///
/// Immutable value object. Represents accumulated steps over a time window.
final class HealthStepSample extends Equatable {
  /// Number of steps in this sample window.
  final int steps;

  /// Start of the measurement window in milliseconds since Unix epoch (UTC).
  final int startMs;

  /// End of the measurement window in milliseconds since Unix epoch (UTC).
  final int endMs;

  const HealthStepSample({
    required this.steps,
    required this.startMs,
    required this.endMs,
  });

  @override
  List<Object?> get props => [steps, startMs, endMs];
}
