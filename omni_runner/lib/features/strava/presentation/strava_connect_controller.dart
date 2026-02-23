import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/domain/i_strava_auth_repository.dart';
import 'package:omni_runner/features/strava/domain/i_strava_upload_repository.dart';
import 'package:omni_runner/features/strava/domain/strava_auth_state.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_request.dart';
import 'package:omni_runner/features/strava/domain/strava_upload_status.dart';

/// Controller for Strava connect/disconnect and upload actions.
///
/// Bridges between UI events and the domain repositories.
/// Stateless — delegates all state to [IStravaAuthRepository].
///
/// Designed to be used by a BLoC or directly by a widget.
/// No Flutter imports (pure Dart).
final class StravaConnectController {
  final IStravaAuthRepository _authRepo;
  final IStravaUploadRepository _uploadRepo;

  static const _tag = 'StravaController';

  const StravaConnectController({
    required IStravaAuthRepository authRepo,
    required IStravaUploadRepository uploadRepo,
  })  : _authRepo = authRepo,
        _uploadRepo = uploadRepo;

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
  Future<StravaConnected> handleCallback(String code) async {
    AppLogger.info('Callback received, exchanging code', tag: _tag);
    return _authRepo.exchangeCode(code);
  }

  /// Disconnect from Strava.
  ///
  /// Revokes access and clears stored tokens.
  Future<void> disconnect() async {
    AppLogger.info('Disconnect requested', tag: _tag);
    await _authRepo.disconnect();
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
