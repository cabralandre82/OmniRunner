import 'package:omni_runner/domain/entities/location_point_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/wearables_ble/heart_rate_sample.dart';

/// Input DTO for a workout export operation.
///
/// Groups all data needed to generate an export file.
/// Domain-only — no Flutter or platform imports.
final class ExportRequest {
  /// The workout session to export.
  final WorkoutSessionEntity session;

  /// GPS route points for the session.
  final List<LocationPointEntity> route;

  /// Heart rate samples captured during the session.
  final List<HeartRateSample> hrSamples;

  /// Desired output format.
  final ExportFormat format;

  /// Activity name (used in file metadata).
  final String activityName;

  const ExportRequest({
    required this.session,
    required this.route,
    this.hrSamples = const [],
    required this.format,
    this.activityName = 'Omni Runner',
  });
}
