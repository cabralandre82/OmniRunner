import 'dart:typed_data';

import 'package:omni_runner/features/integrations_export/data/fit/fit_encoder.dart';
import 'package:omni_runner/features/integrations_export/data/gpx/gpx_encoder.dart';
import 'package:omni_runner/features/integrations_export/data/tcx/tcx_encoder.dart';
import 'package:omni_runner/features/integrations_export/domain/export_format.dart';
import 'package:omni_runner/features/integrations_export/domain/export_request.dart';
import 'package:omni_runner/features/integrations_export/domain/export_result.dart';
import 'package:omni_runner/features/integrations_export/domain/i_export_service.dart';

/// Concrete implementation of [IExportService].
///
/// Delegates to the appropriate encoder based on [ExportRequest.format]:
/// - [GpxEncoder] for GPX 1.1
/// - [TcxEncoder] for TCX
/// - [FitEncoder] for FIT (currently throws [ExportNotImplemented])
final class ExportServiceImpl implements IExportService {
  final GpxEncoder _gpxEncoder;
  final TcxEncoder _tcxEncoder;
  final FitEncoder _fitEncoder;

  const ExportServiceImpl({
    GpxEncoder gpxEncoder = const GpxEncoder(),
    TcxEncoder tcxEncoder = const TcxEncoder(),
    FitEncoder fitEncoder = const FitEncoder(),
  })  : _gpxEncoder = gpxEncoder,
        _tcxEncoder = tcxEncoder,
        _fitEncoder = fitEncoder;

  @override
  Future<ExportResult> exportWorkout(ExportRequest request) async {
    final Uint8List bytes;

    switch (request.format) {
      case ExportFormat.gpx:
        bytes = _gpxEncoder.encode(
          session: request.session,
          route: request.route,
          hrSamples: request.hrSamples,
          activityName: request.activityName,
        );
      case ExportFormat.tcx:
        bytes = _tcxEncoder.encode(
          session: request.session,
          route: request.route,
          hrSamples: request.hrSamples,
          activityName: request.activityName,
        );
      case ExportFormat.fit:
        bytes = _fitEncoder.encode(
          session: request.session,
          route: request.route,
          hrSamples: request.hrSamples,
          activityName: request.activityName,
        );
    }

    final filename = _buildFilename(request);

    return ExportResult(
      bytes: bytes,
      filename: filename,
      mimeType: request.format.mimeType,
      format: request.format,
    );
  }

  /// Build a human-readable filename from session metadata.
  ///
  /// Format: `run_YYYY-MM-DD_HHMMSS.ext`
  String _buildFilename(ExportRequest request) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      request.session.startTimeMs,
      isUtc: true,
    );
    final date = '${dt.year}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    final time = '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';

    return 'run_${date}_$time${request.format.extension}';
  }
}
