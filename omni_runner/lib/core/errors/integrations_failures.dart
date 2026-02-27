/// Failures related to external integrations (Strava, file export).
///
/// Sealed hierarchy — enables exhaustive pattern matching in BLoC.
/// Follows the same convention as [HealthFailure], [BleFailure], etc.
sealed class IntegrationFailure {
  const IntegrationFailure();
}

// ── Auth ──────────────────────────────────────────────────────

/// OAuth2 flow was cancelled by the user.
final class AuthCancelled extends IntegrationFailure {
  const AuthCancelled();
}

/// OAuth2 flow failed (network, server error, invalid response).
final class AuthFailed extends IntegrationFailure {
  final String reason;
  const AuthFailed(this.reason);
  @override
  String toString() => reason;
}

/// Token refresh failed — user must re-authenticate.
final class TokenExpired extends IntegrationFailure {
  const TokenExpired();
}

/// User revoked access on the provider side.
final class AuthRevoked extends IntegrationFailure {
  const AuthRevoked();
}

// ── Upload ────────────────────────────────────────────────────

/// Upload rejected by provider (4xx — bad file, duplicate, etc.).
final class UploadRejected extends IntegrationFailure {
  final int statusCode;
  final String message;
  const UploadRejected(this.statusCode, this.message);
}

/// Upload failed due to network error (retryable).
final class UploadNetworkError extends IntegrationFailure {
  final String message;
  const UploadNetworkError(this.message);
}

/// Upload failed due to server error (5xx, retryable).
final class UploadServerError extends IntegrationFailure {
  final int statusCode;
  const UploadServerError(this.statusCode);
}

/// Rate limit exceeded (429).
final class UploadRateLimited extends IntegrationFailure {
  final int retryAfterSeconds;
  const UploadRateLimited(this.retryAfterSeconds);
}

/// Upload processing timed out on the provider side.
final class UploadProcessingTimeout extends IntegrationFailure {
  final String uploadId;
  const UploadProcessingTimeout(this.uploadId);
}

// ── File Export ───────────────────────────────────────────────

/// Failed to generate the export file (GPX/FIT/TCX).
final class ExportGenerationFailed extends IntegrationFailure {
  final String format;
  final String reason;
  const ExportGenerationFailed(this.format, this.reason);
}

/// Failed to write the file to disk.
final class ExportWriteFailed extends IntegrationFailure {
  final String path;
  final String reason;
  const ExportWriteFailed(this.path, this.reason);
}

/// Requested export format is not yet implemented.
final class ExportNotImplemented extends IntegrationFailure {
  final String format;
  const ExportNotImplemented(this.format);
}
