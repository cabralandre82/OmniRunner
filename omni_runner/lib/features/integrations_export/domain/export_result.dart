import 'dart:typed_data';

import 'package:omni_runner/features/integrations_export/domain/export_format.dart';

/// Output of a successful workout export operation.
///
/// Contains the raw file bytes, a suggested filename, and metadata
/// needed to share the file via the OS share sheet.
final class ExportResult {
  /// Raw file content (GPX XML, TCX XML, or FIT binary).
  final Uint8List bytes;

  /// Suggested filename including extension (e.g. "run_2026-02-17.gpx").
  final String filename;

  /// MIME type for the share sheet / intent.
  final String mimeType;

  /// The format that was generated.
  final ExportFormat format;

  const ExportResult({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.format,
  });
}
