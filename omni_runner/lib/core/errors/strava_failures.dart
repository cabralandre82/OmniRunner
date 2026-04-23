/// Strava-specific failure types.
///
/// Re-exports the relevant [IntegrationFailure] subclasses and adds
/// Strava-specific convenience aliases for exhaustive matching in BLoCs.
///
/// These are NOT new classes — they are the same sealed hierarchy from
/// [integrations_failures.dart]. This file exists as a focused barrel
/// export so Strava feature code doesn't need to import the entire
/// integration failure tree.
///
/// For new Strava-only failure types that don't belong in the general
/// integration hierarchy, add them here as extensions of
/// [IntegrationFailure].
library;

export 'package:omni_runner/core/errors/integrations_failures.dart'
    show
        IntegrationFailure,
        // Auth
        AuthCancelled,
        AuthFailed,
        TokenExpired,
        AuthRevoked,
        OAuthCsrfViolation,
        // Upload
        UploadRejected,
        UploadNetworkError,
        UploadServerError,
        UploadRateLimited,
        UploadProcessingTimeout;
