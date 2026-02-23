import 'package:omni_runner/core/errors/health_export_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/domain/entities/health_hr_sample.dart';
import 'package:omni_runner/domain/entities/workout_export_result.dart';
import 'package:omni_runner/features/health_export/domain/i_health_export_service.dart';

const String _tag = 'HealthExportCtrl';

/// Result returned to the presentation layer after a health export attempt.
///
/// Wraps [WorkoutExportResult] with a user-facing message and a flag
/// indicating whether the export was at least partially successful.
final class HealthExportUiResult {
  /// `true` if the workout record was saved (route may or may not be attached).
  final bool success;

  /// The underlying export result from the health service.
  final WorkoutExportResult? result;

  /// User-facing message suitable for a snackbar or dialog.
  final String message;

  const HealthExportUiResult({
    required this.success,
    this.result,
    required this.message,
  });
}

/// Controller for exporting workouts to the platform health store.
///
/// Orchestrates [IHealthExportService] calls and maps domain errors
/// (sealed [HealthExportFailure] hierarchy) into user-friendly
/// [HealthExportUiResult] objects.
///
/// No UI code — only orchestration. Connected to a screen or bottom sheet
/// by the presentation layer.
///
/// ## Usage
/// ```dart
/// final controller = sl<HealthExportController>();
///
/// // Check support before showing the button
/// final supported = await controller.isPlatformSupported();
///
/// // Export
/// final result = await controller.exportWorkout(
///   sessionId: session.id,
///   startMs: session.startTimeMs,
///   endMs: session.endTimeMs!,
///   totalDistanceM: session.totalDistanceM ?? 0,
/// );
///
/// if (result.success) {
///   showSnackBar(result.message);
/// } else {
///   showErrorDialog(result.message);
/// }
/// ```
class HealthExportController {
  final IHealthExportService _service;

  const HealthExportController({
    required IHealthExportService service,
  }) : _service = service;

  /// Whether the current platform supports health export.
  ///
  /// Use this to conditionally show the "Export to Health" button.
  Future<bool> isPlatformSupported() async {
    try {
      return await _service.isSupported();
    } on Exception catch (e) {
      AppLogger.warn('isSupported check failed: $e', tag: _tag);
      return false;
    }
  }

  /// Export a workout to the platform health store.
  ///
  /// Returns [HealthExportUiResult] — never throws.
  /// All [HealthExportFailure] subtypes are caught and converted to
  /// user-facing messages.
  Future<HealthExportUiResult> exportWorkout({
    required String sessionId,
    required int startMs,
    required int endMs,
    required double totalDistanceM,
    int? totalCalories,
    int? avgBpm,
    int? maxBpm,
    List<HealthHrSample> hrSamples = const [],
  }) async {
    try {
      final result = await _service.exportWorkout(
        sessionId: sessionId,
        startMs: startMs,
        endMs: endMs,
        totalDistanceM: totalDistanceM,
        totalCalories: totalCalories,
        avgBpm: avgBpm,
        maxBpm: maxBpm,
        hrSamples: hrSamples,
      );

      AppLogger.info(
        'Export success: workout=${result.workoutSaved} '
        'route=${result.routeAttached} (${result.routePointCount} pts)',
        tag: _tag,
      );

      final msg = result.routeAttached
          ? 'Treino exportado com rota GPS.'
          : 'Treino exportado (sem rota GPS).';

      return HealthExportUiResult(
        success: true,
        result: result,
        message: msg,
      );
    } on HealthExportNotAvailable catch (e) {
      return HealthExportUiResult(
        success: false,
        message: e.reason,
      );
    } on HealthExportNeedsUpdate catch (_) {
      return const HealthExportUiResult(
        success: false,
        message: 'O Health Connect precisa ser atualizado. '
            'Atualize pelo Google Play e tente novamente.',
      );
    } on HealthExportPermissionDenied catch (e) {
      AppLogger.warn(
        'Permission denied: ${e.missingScopes.join(', ')}',
        tag: _tag,
      );
      return const HealthExportUiResult(
        success: false,
        message: 'Permissão negada. Abra as configurações '
            'de saúde do dispositivo e autorize o Omni Runner '
            'a gravar treinos.',
      );
    } on HealthExportWriteFailed catch (e) {
      AppLogger.error('Export write failed: ${e.reason}', tag: _tag);
      return HealthExportUiResult(
        success: false,
        message: 'Falha ao gravar treino: ${e.reason}',
      );
    } on HealthExportRouteAttachFailed catch (e) {
      AppLogger.warn('Route attach failed: ${e.reason}', tag: _tag);
      return HealthExportUiResult(
        success: true,
        message: 'Treino exportado, mas a rota GPS não foi anexada: '
            '${e.reason}',
      );
    } on HealthExportHrWriteFailed catch (e) {
      AppLogger.warn(
        'HR write partial: ${e.written}/${e.attempted}',
        tag: _tag,
      );
      return HealthExportUiResult(
        success: true,
        message: 'Treino exportado. Dados de frequência cardíaca parciais '
            '(${e.written}/${e.attempted}).',
      );
    } on Exception catch (e) {
      AppLogger.error('Unexpected export error', tag: _tag, error: e);
      return HealthExportUiResult(
        success: false,
        message: 'Erro inesperado ao exportar: $e',
      );
    }
  }
}
