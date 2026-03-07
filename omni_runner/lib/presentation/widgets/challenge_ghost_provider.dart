import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:omni_runner/core/service_locator.dart';
import 'package:omni_runner/core/logging/logger.dart';

/// Fetches an opponent's running progress during an active challenge.
///
/// Polls the opponent's latest session data at a fixed interval.
/// Exposes a stream of [ChallengeGhostState] for the overlay widget.
///
/// Privacy: only exposes aggregate progress (total distance, session count),
/// never the opponent's GPS coordinates. The "ghost" is a relative
/// distance indicator, not a real-time location tracker.
class ChallengeGhostProvider {
  final String challengeId;
  final String opponentUserId;
  final Duration pollInterval;

  Timer? _timer;
  final _ctrl = StreamController<ChallengeGhostState>.broadcast();

  ChallengeGhostProvider({
    required this.challengeId,
    required this.opponentUserId,
    this.pollInterval = const Duration(seconds: 15),
  });

  Stream<ChallengeGhostState> get stream => _ctrl.stream;

  void start() {
    _poll();
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final sb = sl<SupabaseClient>();

      final row = await sb
          .from('challenge_participants')
          .select('progress_value, last_submitted_at_ms')
          .eq('challenge_id', challengeId)
          .eq('user_id', opponentUserId)
          .maybeSingle();

      if (row == null) {
        _ctrl.add(const ChallengeGhostState(
          opponentDistanceM: 0,
          lastSyncMs: null,
          isOffline: true,
        ));
        return;
      }

      final progressValue = (row['progress_value'] as num?)?.toDouble() ?? 0;
      final lastSyncMs = (row['last_submitted_at_ms'] as num?)?.toInt();

      final isStale = lastSyncMs != null &&
          (DateTime.now().millisecondsSinceEpoch - lastSyncMs) > 120000;

      _ctrl.add(ChallengeGhostState(
        opponentDistanceM: progressValue,
        lastSyncMs: lastSyncMs,
        isOffline: isStale,
      ));
    } on Exception catch (e) {
      AppLogger.warn('Caught error', tag: 'ChallengeGhostProvider', error: e);
      // Silently fail — overlay shows stale indicator
    }
  }

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
  }
}

class ChallengeGhostState {
  final double opponentDistanceM;
  final int? lastSyncMs;
  final bool isOffline;

  const ChallengeGhostState({
    required this.opponentDistanceM,
    required this.lastSyncMs,
    required this.isOffline,
  });
}
