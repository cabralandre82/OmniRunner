import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';

/// Concrete implementation of [IStravaAuthRepository].
///
/// Manages Strava OAuth2 token lifecycle:
/// - Authorization via system browser
/// - Token exchange and refresh
/// - Secure token persistence via [StravaSecureStore]
/// - Deauthorization (disconnect)
///
/// Client ID and Secret are injected — never hardcoded.
final class StravaAuthRepositoryImpl implements IStravaAuthRepository {
  final StravaSecureStore _store;
  final StravaHttpClient _httpClient;
  final String _clientId;
  final String _clientSecret;

  /// In-memory cache of the current auth state.
  StravaAuthState? _cachedState;

  static const _tag = 'StravaAuth';

  StravaAuthRepositoryImpl({
    required StravaSecureStore store,
    required StravaHttpClient httpClient,
    required String clientId,
    required String clientSecret,
  })  : _store = store,
        _httpClient = httpClient,
        _clientId = clientId,
        _clientSecret = clientSecret;

  // ── IStravaAuthRepository ─────────────────────────────────────

  @override
  Future<StravaAuthState> getAuthState() async {
    if (_cachedState != null) return _cachedState!;

    final hasTokens = await _store.hasTokens;
    if (!hasTokens) {
    _cachedState = const StravaDisconnected();
    return _cachedState!;
    }

    final expiresAt = await _store.expiresAt;
    final athleteId = await _store.athleteId;
    final athleteName = await _store.athleteName;

    if (expiresAt == null || athleteId == null) {
      _cachedState = const StravaDisconnected();
      return _cachedState!;
    }

    final connected = StravaConnected(
      athleteId: athleteId,
      athleteName: athleteName ?? 'Strava User',
      expiresAt: expiresAt,
    );

    if (connected.isExpired) {
      _cachedState = const StravaReauthRequired(reason: 'Token expired');
      return _cachedState!;
    }

    _cachedState = connected;
    return _cachedState!;
  }

  @override
  Future<StravaConnected> authenticate() async {
    _cachedState = const StravaConnecting();
    AppLogger.info('OAuth flow started', tag: _tag);

    final url = _httpClient.buildAuthorizationUrl(clientId: _clientId);

    try {
      final resultUrl = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: 'omnirunner',
      );

      final resultUri = Uri.parse(resultUrl);
      final code = resultUri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        final error = resultUri.queryParameters['error'];
        _cachedState = const StravaDisconnected();
        if (error == 'access_denied') throw const AuthCancelled();
        throw AuthFailed('No authorization code received: $error');
      }

      AppLogger.info('Authorization code received, exchanging', tag: _tag);
      return await exchangeCode(code);
    } on AuthCancelled {
      _cachedState = const StravaDisconnected();
      rethrow;
    } on IntegrationFailure {
      _cachedState = const StravaDisconnected();
      rethrow;
    } on Exception catch (e) {
      _cachedState = const StravaDisconnected();
      throw AuthFailed('OAuth flow failed: $e');
    }
  }

  @override
  Future<StravaConnected> exchangeCode(String code) async {
    AppLogger.info('Exchanging code', tag: _tag);

    try {
      final json = await _httpClient.exchangeToken(
        clientId: _clientId,
        clientSecret: _clientSecret,
        code: code,
      );

      return await _persistTokenResponse(json);
    } on IntegrationFailure {
      _cachedState = const StravaDisconnected();
      rethrow;
    } on Exception catch (e) {
      _cachedState = const StravaDisconnected();
      throw AuthFailed('Token exchange failed: $e');
    }
  }

  @override
  Future<StravaConnected> refreshToken() async {
    AppLogger.info('Refreshing token', tag: _tag);

    final storedRefresh = await _store.refreshToken;
    if (storedRefresh == null || storedRefresh.isEmpty) {
      _cachedState = const StravaReauthRequired(reason: 'No refresh token');
      throw const TokenExpired();
    }

    try {
      final json = await _httpClient.refreshToken(
        clientId: _clientId,
        clientSecret: _clientSecret,
        refreshToken: storedRefresh,
      );

      final connected = await _persistTokenResponse(json);
      AppLogger.info(
        'Token refreshed (expires_at=${connected.expiresAt})',
        tag: _tag,
      );
      return connected;
    } on TokenExpired {
      // 401 from Strava = user revoked access
      await _store.clearAll();
      _cachedState = const StravaReauthRequired(reason: 'Token revoked');
      throw const AuthRevoked();
    } on IntegrationFailure {
      _cachedState = const StravaReauthRequired(reason: 'Refresh failed');
      rethrow;
    } on Exception catch (e) {
      _cachedState = StravaReauthRequired(reason: e.toString());
      throw const TokenExpired();
    }
  }

  @override
  Future<StravaDisconnected> disconnect() async {
    AppLogger.info('Disconnecting', tag: _tag);

    final token = await _store.accessToken;

    if (token != null && token.isNotEmpty) {
      try {
        await _httpClient.deauthorize(accessToken: token);
      } on Exception catch (e) {
        // Best-effort: if deauthorize fails, still clear local tokens
        AppLogger.warn('Deauthorize API call failed (non-blocking): $e', tag: _tag);
      }
    }

    await _store.clearAll();
    _cachedState = const StravaDisconnected();

    AppLogger.info('Disconnected', tag: _tag);
    return const StravaDisconnected();
  }

  @override
  Future<String> getValidAccessToken() async {
    final state = await getAuthState();

    switch (state) {
      case StravaConnected(isExpired: false):
        return (await _store.accessToken)!;
      case StravaConnected(isExpired: true):
        await refreshToken();
        return (await _store.accessToken) ??
            (throw const TokenExpired());
      case StravaReauthRequired():
        // Try refresh one more time
        try {
          await refreshToken();
          return (await _store.accessToken)!;
        } on IntegrationFailure {
          rethrow;
        }
      case StravaDisconnected():
      case StravaConnecting():
        throw const AuthFailed('Not connected to Strava');
    }
  }

  // ── Private helpers ───────────────────────────────────────────

  /// Parse a token response JSON and persist to secure storage.
  Future<StravaConnected> _persistTokenResponse(
    Map<String, dynamic> json,
  ) async {
    final accessToken = json['access_token'] as String? ?? '';
    final refreshToken = json['refresh_token'] as String? ?? '';
    final expiresAt = json['expires_at'] as int? ?? 0;

    if (accessToken.isEmpty || refreshToken.isEmpty || expiresAt == 0) {
      throw const AuthFailed('Invalid token response: missing fields');
    }

    await _store.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );

    // Extract athlete info if present (only in initial exchange, not refresh)
    final athlete = json['athlete'] as Map<String, dynamic>?;
    final athleteId = athlete?['id'] as int? ?? await _store.athleteId ?? 0;
    final athleteName = athlete?['firstname'] as String? ??
        await _store.athleteName ??
        'Strava User';

    if (athlete != null) {
      await _store.saveAthlete(
        athleteId: athleteId,
        athleteName: athleteName,
      );
    }

    final connected = StravaConnected(
      athleteId: athleteId,
      athleteName: athleteName,
      expiresAt: expiresAt,
    );
    _cachedState = connected;

    return connected;
  }
}
