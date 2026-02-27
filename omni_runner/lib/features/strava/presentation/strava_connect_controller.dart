import 'package:omni_runner/core/errors/strava_failures.dart';
import 'package:omni_runner/core/logging/logger.dart';
import 'package:omni_runner/features/strava/data/strava_http_client.dart';
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
///
/// ## Integration Strategy: Strava as Primary Data Source
///
/// **Decision:** Athletes run with any device/app they want, but all activity
/// data flows through Strava to Omni Runner. Strava is the single source of
/// truth for anti-cheat and challenge validation.
///
/// **Why Strava only (for now):**
///
/// 1. **Universal compatibility** — Garmin, Coros, Suunto, Polar, Apple Watch,
///    and even phone-only runners all sync to Strava natively.
/// 2. **Rich free-tier API** — `activity:read_all` scope gives us: GPS streams,
///    heart rate, cadence, elapsed vs moving time, splits, summary polyline.
///    All required for anti-cheat validation without needing Strava Summit.
/// 3. **Anti-cheat data on free tier:**
///    - GPS coordinates (polyline + detailed stream) → teleportation detection
///    - Heart rate data → effort-vs-pace plausibility
///    - Elapsed time vs moving time → pause manipulation
///    - Pace consistency → bike-as-run detection
///    - Elevation data → terrain cross-reference
/// 4. **Webhook support** — `strava_connections` table enables automatic import
///    of new activities without the athlete needing the phone/app open.
/// 5. **Single integration to maintain** — One OAuth flow, one webhook, one
///    data format. Nike Run Club, adidas Running, etc. would each require a
///    separate integration with less data availability.
/// 6. **Strong adoption** — Strava is dominant in the running community,
///    especially in Brazil among assessoria-linked athletes.
///
/// **Why NOT Nike Run Club / adidas Running / others (for now):**
///
/// - Nike Run Club API is not publicly available (no OAuth, no webhook).
/// - adidas Running (Runtastic) has limited API access.
/// - MapMyRun, Under Armour — same issue.
/// - Fragmenting effort across multiple integrations with less data would
///   weaken the anti-cheat system.
/// - Athletes using these apps can still sync them to Strava, which then
///   syncs to us — one extra step but zero data loss.
///
/// **Future extensibility:** The architecture (domain interfaces, sealed
/// states) allows adding new data sources later if needed. The anti-cheat
/// engine works on normalized activity data, not Strava-specific formats.
final class StravaConnectController {
  final IStravaAuthRepository _authRepo;
  final IStravaUploadRepository _uploadRepo;
  final StravaSecureStore _store;
  final StravaHttpClient _httpClient;

  static const _tag = 'StravaController';

  const StravaConnectController({
    required IStravaAuthRepository authRepo,
    required IStravaUploadRepository uploadRepo,
    required StravaSecureStore store,
    required StravaHttpClient httpClient,
  })  : _authRepo = authRepo,
        _uploadRepo = uploadRepo,
        _store = store,
        _httpClient = httpClient;

  // ── Auth Actions ──────────────────────────────────────────────

  /// Get the current connection state.
  Future<StravaAuthState> getState() => _authRepo.getAuthState();

  /// Start the full OAuth2 connect flow.
  ///
  /// Opens Chrome Custom Tab for Strava consent, waits for callback,
  /// exchanges code for tokens, syncs to server, imports history,
  /// backfills sessions, and triggers verification evaluation.
  /// Returns [StravaConnected] on success.
  Future<StravaConnected> startConnect() async {
    try {
      final connected = await _authRepo.authenticate();
      await _syncTokensToServer(connected);
      _importAndBackfill().ignore();
      AppLogger.info('Strava connected: ${connected.athleteName}', tag: _tag);
      return connected;
    } on IntegrationFailure catch (e) {
      AppLogger.warn('Auth failed: $e', tag: _tag);
      rethrow;
    }
  }

  /// Import history → backfill sessions → trigger verification.
  Future<void> _importAndBackfill() async {
    final imported = await importStravaHistory();
    if (imported > 0) {
      await _backfillStravaSessions();
      await _triggerVerificationEval();
    }
  }

  /// Convert strava_activity_history rows into sessions so they
  /// count for athlete verification.
  Future<void> _backfillStravaSessions() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final result = await Supabase.instance.client
          .rpc('backfill_strava_sessions', params: {'p_user_id': uid});

      final count = result as int? ?? 0;
      AppLogger.info(
        'Backfilled $count Strava sessions for verification',
        tag: _tag,
      );
    } catch (e) {
      AppLogger.warn('Failed to backfill Strava sessions: $e', tag: _tag);
    }
  }

  /// Trigger server-side verification evaluation after backfill.
  Future<void> _triggerVerificationEval() async {
    try {
      await Supabase.instance.client.functions
          .invoke('eval-athlete-verification', body: {});
      AppLogger.info('Verification evaluation triggered', tag: _tag);
    } catch (e) {
      AppLogger.warn('Failed to trigger verification eval: $e', tag: _tag);
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

    _importAndBackfill().ignore();

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

  /// Retry import + backfill if connected but the main flow was interrupted.
  Future<void> retryBackfillIfNeeded() async {
    try {
      final state = await _authRepo.getAuthState();
      if (state is! StravaConnected) return;
      await _importAndBackfill();
    } catch (e) {
      AppLogger.warn('retryBackfillIfNeeded failed: $e', tag: _tag);
    }
  }

  // ── History Import ──────────────────────────────────────────────

  /// Fetch the athlete's last [count] running activities from Strava
  /// and save them to `strava_activity_history` for anti-cheat
  /// baseline bootstrapping.
  ///
  /// Called automatically after a successful Strava connect.
  /// Non-critical — failures are logged but do not block the user.
  Future<int> importStravaHistory({int count = 20}) async {
    try {
      final token = await _authRepo.getValidAccessToken();
      final activities = await _httpClient.getAthleteActivities(
        accessToken: token,
        perPage: count,
      );

      const runTypes = {'Run', 'TrailRun', 'VirtualRun'};
      final runs = activities
          .where((a) => runTypes.contains(a['type']))
          .toList();

      if (runs.isEmpty) {
        AppLogger.info('No running activities found in Strava history',
            tag: _tag);
        return 0;
      }

      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return 0;

      final rows = runs.map((a) => {
        'user_id': uid,
        'strava_activity_id': a['id'],
        'name': a['name'],
        'distance_m': (a['distance'] as num?)?.toDouble() ?? 0.0,
        'moving_time_s': a['moving_time'] ?? 0,
        'elapsed_time_s': a['elapsed_time'] ?? 0,
        'average_speed': (a['average_speed'] as num?)?.toDouble(),
        'max_speed': (a['max_speed'] as num?)?.toDouble(),
        'average_heartrate': (a['average_heartrate'] as num?)?.toDouble(),
        'max_heartrate': (a['max_heartrate'] as num?)?.toDouble(),
        'start_date': a['start_date'],
        'summary_polyline': (a['map'] as Map?)?['summary_polyline'],
        'activity_type': a['type'],
        'imported_at': DateTime.now().toUtc().toIso8601String(),
      }).toList();

      await Supabase.instance.client
          .from('strava_activity_history')
          .upsert(rows, onConflict: 'user_id,strava_activity_id');

      AppLogger.info(
        'Imported ${rows.length} running activities from Strava history',
        tag: _tag,
      );
      return rows.length;
    } on Exception catch (e) {
      AppLogger.warn('Failed to import Strava history: $e', tag: _tag);
      return 0;
    }
  }
}
