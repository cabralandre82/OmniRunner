import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';

/// Contract for managing Strava OAuth2 authentication.
///
/// Domain interface. Implementation lives in the data layer.
/// Dependency direction: data → domain (implements this).
///
/// All methods are async because they involve secure storage and HTTP calls.
abstract interface class IStravaAuthRepository {
  /// Current authentication state.
  ///
  /// Reads from secure storage on first call, then caches.
  Future<StravaAuthState> getAuthState();

  /// Start the OAuth2 Authorization Code flow.
  ///
  /// Opens the Strava consent page in the system browser.
  /// Returns a [StravaConnected] state on success.
  ///
  /// Throws [AuthCancelled] if the user dismisses the browser.
  /// Throws [AuthFailed] on network / server errors.
  Future<StravaConnected> authenticate();

  /// Exchange an authorization code for tokens.
  ///
  /// Called internally after the deep-link callback provides the code.
  /// Stores tokens in secure storage.
  Future<StravaConnected> exchangeCode(String code);

  /// Refresh the access token using the stored refresh token.
  ///
  /// Should be called proactively (5 min before expiry) or
  /// reactively (on 401).
  ///
  /// Throws [TokenExpired] if refresh fails and user must re-auth.
  /// Throws [AuthRevoked] if the refresh token has been revoked.
  Future<StravaConnected> refreshToken();

  /// Disconnect from Strava: revoke access and clear stored tokens.
  ///
  /// Calls POST /oauth/deauthorize, then wipes secure storage.
  /// Returns [StravaDisconnected].
  Future<StravaDisconnected> disconnect();

  /// Get a valid access token, refreshing if necessary.
  ///
  /// Convenience method used by the upload repository.
  /// Throws [TokenExpired] or [AuthRevoked] if refresh fails.
  Future<String> getValidAccessToken();
}
