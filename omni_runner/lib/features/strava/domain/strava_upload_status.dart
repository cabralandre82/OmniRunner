/// Status of a Strava upload, returned by the upload/polling endpoints.
///
/// Domain-only — no Flutter imports.
///
/// Lifecycle: queued → processing → ready | duplicate | error
sealed class StravaUploadStatus {
  const StravaUploadStatus();

  /// Whether this status represents a terminal (non-pollable) state.
  bool get isTerminal => switch (this) {
        StravaUploadQueued() => false,
        StravaUploadProcessing() => false,
        StravaUploadReady() => true,
        StravaUploadDuplicate() => true,
        StravaUploadError() => true,
      };
}

/// Upload accepted by Strava (HTTP 201) — waiting in queue.
///
/// This is the initial state returned by POST /api/v3/uploads.
/// Strava's status string: "Your activity is still being processed."
/// At this point the file has been received but not yet parsed.
final class StravaUploadQueued extends StravaUploadStatus {
  /// The upload ID for polling.
  final String uploadId;

  const StravaUploadQueued({required this.uploadId});
}

/// Upload is actively being processed by Strava.
///
/// Returned during polling when Strava is parsing the file.
/// Status string: "Your activity is still being processed."
final class StravaUploadProcessing extends StravaUploadStatus {
  /// The upload ID for continued polling.
  final String uploadId;

  const StravaUploadProcessing({required this.uploadId});
}

/// Upload completed successfully; activity is ready on Strava.
///
/// Status string: "Your activity is ready."
final class StravaUploadReady extends StravaUploadStatus {
  /// The upload ID.
  final String uploadId;

  /// The Strava activity ID created from this upload.
  final int activityId;

  const StravaUploadReady({
    required this.uploadId,
    required this.activityId,
  });
}

/// Upload was a duplicate — the activity already exists on Strava.
///
/// This is treated as a logical success (idempotent upload).
/// Error string contains "duplicate of activity NNN".
final class StravaUploadDuplicate extends StravaUploadStatus {
  /// The upload ID.
  final String uploadId;

  /// Error message from Strava (e.g. "duplicate of activity 123").
  final String message;

  const StravaUploadDuplicate({
    required this.uploadId,
    required this.message,
  });
}

/// Upload failed on the Strava side (processing error).
final class StravaUploadError extends StravaUploadStatus {
  /// The upload ID.
  final String uploadId;

  /// Error message from Strava.
  final String error;

  const StravaUploadError({
    required this.uploadId,
    required this.error,
  });
}
