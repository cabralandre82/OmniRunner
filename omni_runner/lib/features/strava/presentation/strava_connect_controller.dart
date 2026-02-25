import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/data/strava_secure_store.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Controller for Strava connect/disconnect and upload actions.
///
/// Bridges between UI events and the domain repositories.
/// Stateless — delegates all state to [IStravaAuthRepository].
///
/// Designed to be used by a BLoC or directly by a widget.
final class StravaConnectController {
  final IStravaAuthRepository _authRepo;
  final IStravaUploadRepository _uploadRepo;
  final StravaSecureStore _store;

  static const _tag = 'StravaController';

  const StravaConnectController({
    required IStravaAuthRepository authRepo,
    required IStravaUploadRepository uploadRepo,
    required StravaSecureStore store,
  })  : _authRepo = authRepo,
        _uploadRepo = uploadRepo,
        _store = store;

  // ── Auth Actions ──────────────────────────────────────────────

  /// Get the current connection state.
  Future<StravaAuthState> getState() => _authRepo.getAuthState();

  /// Start the OAuth2 connect flow.
  ///
  /// Opens the system browser for Strava consent.
  /// The actual token exchange happens when [handleCallback] is called
  /// with the authorization code from the deep-link.
  Future<void> startConnect() async {
    try {
      await _authRepo.authenticate();
    } on AuthCancelled {
      AppLogger.info('Auth flow started — awaiting callback', tag: _tag);
    } on IntegrationFailure catch (e) {
      AppLogger.warn('Auth failed: $e', tag: _tag);
      rethrow;
    }
  }

  /// Handle the deep-link callback with the authorization code.
  ///
  /// Called when `omnirunner://strava/callback?code=XXX` is received.
  /// Returns the connected state on success.
  /// Also syncs tokens to `strava_connections` so the webhook can import
  /// activities from Garmin/watches without needing the phone.
  Future<StravaConnected> handleCallback(String code) async {
    AppLogger.info('Callback received, exchanging code', tag: _tag);
    final connected = await _authRepo.exchangeCode(code);
    await _syncTokensToServer(connected);
    return connected;
  }

  /// Persist Strava tokens server-side for webhook-triggered imports.
  Future<void> _syncTokensToServer(StravaConnected state) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final accessToken = await _store.accessToken;
      final refreshToken = await _store.refreshToken;
      if (accessToken == null || refreshToken == null) return;

      await Supabase.instance.client.from('strava_connections').upsert({
        'user_id': uid,
        'strava_athlete_id': state.athleteId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': state.expiresAt,
        'scope': 'activity:read_all,activity:write',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      AppLogger.info('Strava tokens synced to server', tag: _tag);
    } catch (e) {
      AppLogger.warn('Failed to sync Strava tokens to server: $e', tag: _tag);
    }
  }

  /// Disconnect from Strava.
  ///
  /// Revokes access, clears stored tokens, and removes server-side tokens.
  Future<void> disconnect() async {
    AppLogger.info('Disconnect requested', tag: _tag);
    await _authRepo.disconnect();

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Supabase.instance.client
            .from('strava_connections')
            .delete()
            .eq('user_id', uid);
        AppLogger.info('Server-side Strava tokens removed', tag: _tag);
      }
    } catch (e) {
      AppLogger.warn('Failed to remove server tokens: $e', tag: _tag);
    }
  }

  // ── Upload Actions ────────────────────────────────────────────

  /// Upload a workout to Strava and wait for processing.
  ///
  /// Returns the final upload status (ready, duplicate, or error).
  /// Throws [IntegrationFailure] on auth or network errors.
  Future<StravaUploadStatus> uploadWorkout(
    StravaUploadRequest request,
  ) async {
    AppLogger.info(
      'Upload requested: session=${request.sessionId}',
      tag: _tag,
    );

    // Ensure we're connected before attempting upload
    final state = await _authRepo.getAuthState();
    if (state is! StravaConnected) {
      throw const AuthFailed('Not connected to Strava');
    }

    return _uploadRepo.uploadAndWait(request);
  }

  /// Check if the user is connected and tokens are valid.
  Future<bool> get isConnected async {
    final state = await _authRepo.getAuthState();
    return state is StravaConnected && !state.isExpired;
  }
}
