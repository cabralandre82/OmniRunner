import 'package:omni_runner/core/errors/integrations_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/repositories/i_points_repo.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/domain/export_request.dart';
import 'package:omni_runner/features/integrations_export/domain/export_result.dart';
import 'package:omni_runner/features/integrations_export/domain/i_export_service.dart';

/// Controller for the export bottom sheet / dialog.
///
/// No UI code — only orchestration logic. The presentation layer
/// (widget/screen) calls this controller, which delegates to
/// [IExportService] and returns an [ExportResult] or an error.
///
/// This will be connected to a BLoC or Cubit in Sprint 14.5.
final class ExportSheetController {
  final IExportService _exportService;
  final IPointsRepo _pointsRepo;

  static const _tag = 'ExportController';

  const ExportSheetController({
    required IExportService exportService,
    required IPointsRepo pointsRepo,
  })  : _exportService = exportService,
        _pointsRepo = pointsRepo;

  /// Generate an export file for the given session.
  ///
  /// Loads the GPS route from [IPointsRepo], builds an [ExportRequest],
  /// and delegates to [IExportService].
  ///
  /// Returns [ExportResult] on success.
  /// Throws [IntegrationFailure] subclass on error.
  Future<ExportResult> export({
    required WorkoutSessionEntity session,
    required ExportFormat format,
    String activityName = 'Omni Runner',
  }) async {
    AppLogger.info('Exporting ${format.label} for ${session.id}', tag: _tag);

    final route = await _pointsRepo.getBySessionId(session.id);

    final request = ExportRequest(
      session: session,
      route: route,
      format: format,
      activityName: activityName,
    );

    final result = await _exportService.exportWorkout(request);

    AppLogger.info(
      'Generated ${result.filename} (${result.bytes.length} bytes)',
      tag: _tag,
    );

    return result;
  }
}
