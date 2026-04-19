import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Minimal key/value contract the guard needs from secure storage.
///
/// Decoupling from `FlutterSecureStorage` directly lets tests inject
/// an in-memory fake without going through the platform-channel mock
/// dance, and keeps the guard portable to other backings (e.g.
/// encrypted shared prefs) if storage needs change.
abstract class OAuthStateStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default backing — thin adapter over [FlutterSecureStorage].
class _SecureStorageAdapter implements OAuthStateStorage {
  final FlutterSecureStorage _storage;
  const _SecureStorageAdapter(this._storage);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// CSRF defence for the Strava OAuth2 authorisation flow (L01-29).
///
/// OAuth 2.0 §10.12 (RFC 6749) requires the client to send an opaque,
/// non-guessable `state` value to the authorisation server and reject
/// any callback whose `state` does not match. Without it, an attacker
/// can phish a victim into authorising the **attacker's** Strava
/// account into the victim's Omni Runner profile (login CSRF) — the
/// attacker's activities would then surface as the victim's runs and
/// affect ranking, anti-cheat baselines, and challenge participation.
///
/// In practice the production OAuth flow uses `flutter_web_auth_2`,
/// which the OS scopes to a single in-flight web auth session — that
/// gives some implicit protection on iOS (ASWebAuthenticationSession
/// is per-session) and Android (Custom Tabs callback). However:
///
///   1. Defence-in-depth: any malicious app on Android that registers
///      the same `omnirunnerauth://` scheme could intercept the
///      callback. Without `state`, a forged callback with an
///      attacker-controlled `code` would be processed.
///   2. The legacy deep-link branches in `DeepLinkHandler` accepted
///      `omnirunner://strava/callback?code=...` from any source. They
///      have been removed in this same change, but `state` is the
///      contract-level defence — it stays correct even if a future
///      consumer re-introduces deep-link-driven OAuth.
///   3. Strava-side: Strava echoes the `state` on the redirect, so a
///      mismatch is the canonical signal that the response did not
///      originate from our authorisation request.
///
/// Lifecycle:
///
///   ```
///   beginFlow()          → generate(32 bytes CSPRNG, base64url) +
///                          persist (secure_storage, TTL 10 min)
///                          → return token to embed in auth URL
///   callback received    → validateAndConsume(returnedState):
///                            ✓ matches stored + within TTL → true (delete)
///                            ✗ mismatch / expired / missing → false
///   abort/cancel         → clear() (housekeeping)
///   ```
///
/// The guard is process-local: there is no concurrent-flow concern
/// because [authenticate] in `StravaAuthRepositoryImpl` is gated by
/// `_cachedState = StravaConnecting` and the call is awaited end to
/// end. If the user kills the app mid-flow, the persisted state
/// expires after 10 minutes (well below the OAuth code TTL of ~1 h).
class StravaOAuthStateGuard {
  final OAuthStateStorage _storage;
  final Random _random;

  /// Wall-clock function — injectable for tests.
  final DateTime Function() _now;

  static const _storageKey = 'strava_oauth_state';
  static const _expiresKey = 'strava_oauth_state_expires_at';
  static const _tag = 'StravaOAuthState';

  /// How long a generated `state` is valid before it is considered
  /// stale. RFC 6749 leaves this to the implementation; 10 minutes is
  /// long enough for the slowest legitimate consent flow (user reads
  /// scopes, switches to Strava login, MFA) and short enough that a
  /// user-abandoned flow does not pile orphan state in storage.
  static const Duration ttl = Duration(minutes: 10);

  /// Number of CSPRNG bytes per token. 32 bytes (256 bits) leaves a
  /// brute-force search space well beyond any conceivable timing
  /// attack against the redirect callback.
  static const int tokenBytes = 32;

  StravaOAuthStateGuard({
    OAuthStateStorage? storage,
    Random? random,
    DateTime Function()? now,
  })  : _storage = storage ?? const _SecureStorageAdapter(FlutterSecureStorage()),
        _random = random ?? Random.secure(),
        _now = now ?? DateTime.now;

  /// Mint a fresh CSPRNG state token, persist it (along with its
  /// absolute expiry timestamp), and return the value to embed in the
  /// authorisation URL.
  ///
  /// Calling [beginFlow] again before [validateAndConsume] discards
  /// the previous token — at most one OAuth flow can be in flight per
  /// device. This is consistent with how the surrounding
  /// `StravaAuthRepositoryImpl` operates (`_cachedState` is set to
  /// `StravaConnecting` for the duration of the call).
  Future<String> beginFlow() async {
    final bytes =
        List<int>.generate(tokenBytes, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    final expiresAt = _now().add(ttl).millisecondsSinceEpoch;

    await Future.wait([
      _storage.write(_storageKey, token),
      _storage.write(_expiresKey, expiresAt.toString()),
    ]);
    AppLogger.debug('OAuth state minted (expires_ms=$expiresAt)', tag: _tag);
    return token;
  }

  /// Compare the supplied [returnedState] (from the OAuth callback)
  /// against the persisted value, in constant time. On any mismatch /
  /// missing / expired condition, the persisted state is cleared and
  /// `false` is returned. On a successful match the state is also
  /// cleared (consume-once semantics — replaying the same `state` on
  /// a second callback fails by design).
  ///
  /// Returns `true` only when:
  ///   * a state was previously persisted by [beginFlow], AND
  ///   * the callback supplied a non-empty value, AND
  ///   * `now() < expiresAt`, AND
  ///   * the two strings are byte-for-byte equal.
  Future<bool> validateAndConsume(String? returnedState) async {
    final stored = await _storage.read(_storageKey);
    final expiresRaw = await _storage.read(_expiresKey);

    // Always clear after a validation attempt — pass or fail. This
    // makes replay impossible even if the caller forgets to abort
    // explicitly.
    await clear();

    if (stored == null || stored.isEmpty) {
      AppLogger.warn('OAuth callback rejected: no stored state', tag: _tag);
      return false;
    }
    if (returnedState == null || returnedState.isEmpty) {
      AppLogger.warn('OAuth callback rejected: missing state param', tag: _tag);
      return false;
    }

    final expiresAt = int.tryParse(expiresRaw ?? '');
    if (expiresAt == null || _now().millisecondsSinceEpoch >= expiresAt) {
      AppLogger.warn(
        'OAuth callback rejected: state expired (now_ms=${_now().millisecondsSinceEpoch}, expires_ms=$expiresAt)',
        tag: _tag,
      );
      return false;
    }

    if (!_constantTimeEquals(stored, returnedState)) {
      AppLogger.warn('OAuth callback rejected: state mismatch', tag: _tag);
      return false;
    }

    AppLogger.debug('OAuth state validated and consumed', tag: _tag);
    return true;
  }

  /// Drop any persisted state — called after validation (always) and
  /// from the surrounding flow when the user cancels.
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(_storageKey),
      _storage.delete(_expiresKey),
    ]);
  }

  /// Length-aware constant-time string comparison. Compares byte by
  /// byte without short-circuiting on the first mismatch, so an
  /// attacker cannot use response-time variation to brute-force the
  /// stored token byte by byte. (The token lives in encrypted secure
  /// storage and is single-use, so timing leakage is already
  /// implausible — but the check is cheap and idiomatic.)
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
