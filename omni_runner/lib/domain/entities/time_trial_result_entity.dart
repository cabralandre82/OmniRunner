import 'package:equatable/equatable.dart';

import 'package:omni_runner/domain/value_objects/time_trial_protocol.dart';

/// L23-14 — Result of a completed time trial.
///
/// This is the bridge between the athlete's executed session and the
/// zone-calibration pipeline. The athlete-monthly-report surface
/// (L23-11) and the coach prescription surfaces (L23-06/L23-07) all
/// read from this entity; the `athlete_zones` table (L21-05,
/// pending) will consume it via a follow-up updater.
///
/// Invariants
/// ----------
///   - [protocol] is required and pins the expected distance/duration.
///   - [actualDistanceM] + [actualDurationS] are the *recorded*
///     values from the session, not the protocol target. The
///     estimator uses these (not the protocol target) to compute
///     threshold.
///   - [finishedAt] is UTC. Same convention as
///     [FeedbackStreakCalculator] (L23-13).
///   - [avgHrBpm] is optional — many athletes run TT without an HR
///     strap; the pace side is authoritative.
///
/// Pure value type. Zero platform binding.
class TimeTrialResultEntity extends Equatable {
  const TimeTrialResultEntity({
    required this.protocol,
    required this.actualDistanceM,
    required this.actualDurationS,
    required this.finishedAt,
    this.avgHrBpm,
    this.sessionId,
    this.note,
  });

  final TimeTrialProtocol protocol;
  final double actualDistanceM;
  final int actualDurationS;
  final DateTime finishedAt;
  final int? avgHrBpm;
  final String? sessionId;
  final String? note;

  /// Average pace in seconds per km. Returns null if the session
  /// covered ≤0 m (corrupt data) — defensive against legacy rows.
  double? get avgPaceSecKm {
    if (actualDistanceM <= 0) return null;
    return actualDurationS / (actualDistanceM / 1000.0);
  }

  /// True when the result is fresh enough to calibrate zones per
  /// [TimeTrialFreshness.maxAgeDays]. [referenceDay] defaults to now
  /// (UTC).
  bool isFreshOn({DateTime? referenceDay}) {
    final ref = (referenceDay ?? DateTime.now()).toUtc();
    final ageDays = ref.difference(finishedAt.toUtc()).inDays;
    return ageDays >= 0 && ageDays <= TimeTrialFreshness.maxAgeDays;
  }

  @override
  List<Object?> get props => [
        protocol,
        actualDistanceM,
        actualDurationS,
        finishedAt,
        avgHrBpm,
        sessionId,
        note,
      ];
}
