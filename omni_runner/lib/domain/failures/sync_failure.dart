/// Failures related to backend synchronisation.
///
/// Sealed class hierarchy. No exceptions thrown in domain.
sealed class SyncFailure {
  const SyncFailure();
}

/// Device has no internet connection.
final class SyncNoConnection extends SyncFailure {
  const SyncNoConnection();
}

/// Supabase returned a server-side error (5xx or unexpected).
final class SyncServerError extends SyncFailure {
  final String message;
  const SyncServerError([this.message = '']);
}

/// Request timed out.
final class SyncTimeout extends SyncFailure {
  const SyncTimeout();
}

/// Supabase is not configured (missing URL or anon key).
final class SyncNotConfigured extends SyncFailure {
  const SyncNotConfigured();
}

/// User is not authenticated.
final class SyncNotAuthenticated extends SyncFailure {
  const SyncNotAuthenticated();
}
