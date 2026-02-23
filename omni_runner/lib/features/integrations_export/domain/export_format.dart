/// Supported workout export file formats.
///
/// Each format targets different ecosystems:
/// - [gpx] — Universal (Garmin, Coros, Suunto, Strava, etc.)
/// - [tcx] — Garmin Connect, TrainingPeaks
/// - [fit] — Garmin, Strava, TrainingPeaks (binary, most complete)
enum ExportFormat {
  /// GPX 1.1 — XML-based, widely supported.
  gpx,

  /// TCX — Garmin Training Center XML.
  tcx,

  /// FIT — Flexible and Interoperable Data Transfer (binary).
  fit;

  /// File extension including the dot.
  String get extension => switch (this) {
        gpx => '.gpx',
        tcx => '.tcx',
        fit => '.fit',
      };

  /// MIME type for sharing via OS share sheet.
  String get mimeType => switch (this) {
        gpx => 'application/gpx+xml',
        tcx => 'application/vnd.garmin.tcx+xml',
        fit => 'application/vnd.ant.fit',
      };

  /// Human-readable label.
  String get label => switch (this) {
        gpx => 'GPX',
        tcx => 'TCX',
        fit => 'FIT',
      };
}
