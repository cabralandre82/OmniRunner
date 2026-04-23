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

/// OAuth2 authorization-server callback failed the CSRF defence
/// (RFC 6749 §10.12 `state` parameter).
///
/// Raised by [StravaAuthRepositoryImpl.authenticate] when the value
/// echoed back by Strava does not match the CSPRNG token minted by
/// [StravaOAuthStateGuard.beginFlow]. Any of the following trigger it:
///
///   * Missing `state` in the callback (someone crafted the redirect
///     by hand — well-behaved clients always include it).
///   * Wrong `state` value (classic login-CSRF: a forged authorize
///     request tried to graft an attacker-controlled Strava account
///     onto the victim's Omni Runner session).
///   * Expired state (TTL 10 min — almost certainly a stale redirect,
///     not an attack, but handled with the same safety rails).
///   * Replay of a previously consumed state (the guard is
///     consume-once, so a second callback with the same value fails).
///
/// UI should surface this as a distinct, user-safe message — never as
/// a generic "Erro ao conectar". The attempted exchange was aborted
/// BEFORE any token request, so no Strava code was sent to the auth
/// server. Users are free to retry cleanly from scratch.
///
/// L07-04 — see `docs/runbooks/STRAVA_OAUTH_CSRF_RUNBOOK.md`.
final class OAuthCsrfViolation extends IntegrationFailure {
  /// Machine-readable reason for logging / telemetry. One of:
  ///   * `'state_missing'` — callback came back with no `state` query param.
  ///   * `'state_mismatch'` — `state` value does not match the minted token
  ///     (also covers expired or not-previously-minted).
  final String reason;
  const OAuthCsrfViolation({this.reason = 'state_mismatch'});

  @override
  String toString() => 'OAuthCsrfViolation(reason=$reason)';
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
