import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Thin wrapper around [FlutterSecureStorage] for Strava tokens.
///
/// All keys are prefixed with `strava_` to avoid collision.
/// Values are always strings; numeric types are serialized.
///
/// This class owns NO business logic — it is a pure data-access layer.
class StravaSecureStore {
  final FlutterSecureStorage _storage;

  static const _keyAccessToken = 'strava_access_token';
  static const _keyRefreshToken = 'strava_refresh_token';
  static const _keyExpiresAt = 'strava_expires_at';
  static const _keyAthleteId = 'strava_athlete_id';
  static const _keyAthleteName = 'strava_athlete_name';

  static const _tag = 'StravaStore';

  const StravaSecureStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  // ── Read ──────────────────────────────────────────────────────

  Future<String?> get accessToken => _storage.read(key: _keyAccessToken);

  Future<String?> get refreshToken => _storage.read(key: _keyRefreshToken);

  Future<int?> get expiresAt async {
    final raw = await _storage.read(key: _keyExpiresAt);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<int?> get athleteId async {
    final raw = await _storage.read(key: _keyAthleteId);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<String?> get athleteName => _storage.read(key: _keyAthleteName);

  // ── Write ─────────────────────────────────────────────────────

  /// Persist a complete token set from a token exchange or refresh.
  ///
  /// [refreshTokenValue] can be the same or a new one — Strava may
  /// rotate the refresh token on each refresh.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresAt,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: accessToken),
      _storage.write(key: _keyRefreshToken, value: refreshToken),
      _storage.write(key: _keyExpiresAt, value: expiresAt.toString()),
    ]);
    AppLogger.debug('Tokens saved (expires_at=$expiresAt)', tag: _tag);
  }

  /// Persist athlete profile info for display in the UI.
  Future<void> saveAthlete({
    required int athleteId,
    required String athleteName,
  }) async {
    await Future.wait([
      _storage.write(key: _keyAthleteId, value: athleteId.toString()),
      _storage.write(key: _keyAthleteName, value: athleteName),
    ]);
  }

  // ── Delete ────────────────────────────────────────────────────

  /// Wipe all Strava-related data from secure storage.
  ///
  /// Called on disconnect / deauthorize.
  Future<void> clearAll() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyExpiresAt),
      _storage.delete(key: _keyAthleteId),
      _storage.delete(key: _keyAthleteName),
    ]);
    AppLogger.info('All tokens cleared', tag: _tag);
  }

  // ── Convenience ───────────────────────────────────────────────

  /// Whether tokens exist in storage (does NOT check expiry).
  Future<bool> get hasTokens async {
    final token = await accessToken;
    return token != null && token.isNotEmpty;
  }
}
