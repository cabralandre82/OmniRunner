import 'package:omni_runner/features/integrations_export/domain/export_request.dart';
import 'package:omni_runner/features/integrations_export/domain/export_result.dart';

/// Contract for generating workout export files (GPX, TCX, FIT).
///
/// Domain interface. Implementation lives in the data layer.
/// Returns [ExportResult] on success or throws an
/// [IntegrationFailure] subclass on error.
// ignore: one_member_abstracts
abstract interface class IExportService {
  /// Generate an export file for the given workout.
  ///
  /// The format is determined by [ExportRequest.format].
  /// Returns a byte buffer ready to be written to disk or shared.
  Future<ExportResult> exportWorkout(ExportRequest request);
}
