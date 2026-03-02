import 'package:omni_runner/domain/entities/athlete_verification_entity.dart';

/// Remote operations needed by [VerificationBloc].
///
/// Implementations talk to the server (Supabase RPCs, Edge Functions)
/// and to Strava (via [StravaConnectController]). The BLoC never
/// touches these infrastructure details directly.
abstract interface class IVerificationRemoteSource {
  /// Whether the backend connection is initialised and usable.
  bool get isBackendReady;

  /// Currently authenticated user id, or `null` if not logged in.
  String? get currentUserId;

  /// If Strava is connected, re-import latest activities and
  /// run server-side backfill RPCs (sessions, parks, progress).
  ///
  /// Swallows errors internally so callers can treat it as
  /// best-effort.
  Future<void> backfillStravaIfConnected();

  /// Trigger server-side re-evaluation of the athlete's
  /// verification checklist.
  Future<void> evaluateMyVerification();

  /// Fetch the current verification snapshot from the server RPC
  /// `get_verification_state`.
  Future<AthleteVerificationEntity> fetchVerificationState();
}
