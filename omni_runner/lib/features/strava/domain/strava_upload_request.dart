import 'dart:typed_data';

import 'package:omni_runner/features/integrations_export/domain/export_format.dart';

/// Input DTO for uploading a workout to Strava.
///
/// Domain-only — no Flutter imports.
/// Contains the file bytes and metadata needed for the Strava upload API.
final class StravaUploadRequest {
  /// Unique session ID used as `external_id` for deduplication.
  final String sessionId;

  /// File bytes (GPX/TCX/FIT encoded workout).
  final Uint8List fileBytes;

  /// File format (determines `data_type` field in the API call).
  final ExportFormat format;

  /// Activity name shown on Strava (e.g. "Morning Run").
  final String activityName;

  /// Optional description visible on the Strava activity.
  final String description;

  const StravaUploadRequest({
    required this.sessionId,
    required this.fileBytes,
    required this.format,
    this.activityName = 'Omni Runner',
    this.description = 'Tracked with Omni Runner',
  });
}
