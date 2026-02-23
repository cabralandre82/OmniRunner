/// Represents the current Strava OAuth2 connection state.
///
/// Domain-only — no Flutter imports.
/// Used by the auth repository and presentation layer.
sealed class StravaAuthState {
  const StravaAuthState();
}

/// User has never connected or has disconnected.
final class StravaDisconnected extends StravaAuthState {
  const StravaDisconnected();
}

/// OAuth2 flow is in progress (browser open, waiting for callback).
final class StravaConnecting extends StravaAuthState {
  const StravaConnecting();
}

/// User is authenticated with valid tokens.
final class StravaConnected extends StravaAuthState {
  /// Strava athlete ID.
  final int athleteId;

  /// Display name (firstname from Strava profile).
  final String athleteName;

  /// Unix epoch seconds when the access token expires.
  final int expiresAt;

  const StravaConnected({
    required this.athleteId,
    required this.athleteName,
    required this.expiresAt,
  });

  /// Whether the access token has expired or is about to (within 5 min).
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt - 300;
}

/// Token refresh or re-auth is needed (refresh failed 3x or 401 received).
final class StravaReauthRequired extends StravaAuthState {
  /// Optional reason for the re-auth requirement.
  final String? reason;

  const StravaReauthRequired({this.reason});
}
