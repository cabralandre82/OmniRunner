import 'package:omni_runner/domain/entities/time_trial_result_entity.dart';
import 'package:omni_runner/domain/value_objects/time_trial_protocol.dart';

/// L23-14 — Pure estimator that converts a time-trial result into the
/// athlete's threshold pace + LTHR (lactate-threshold heart rate).
///
/// This is the single source of truth for how a TT maps to threshold
/// — any drift between this estimator and the coach-facing UI copy
/// ("threshold is 4:20/km") will confuse athletes. CI enforces the
/// protocol multipliers (`check-time-trial`), and the runbook
/// documents the physiological rationale.
///
/// Contract
/// --------
///   - Pure: zero I/O, zero async, no platform channels.
///   - Deterministic.
///   - Returns [TimeTrialEstimate] with seconds-per-km pace + optional
///     LTHR. Pace is ROUND-down to integer seconds because athletes
///     read pace in :ss precision, not milliseconds.
///   - Refuses to estimate from a corrupt result (distance ≤ 0,
///     duration ≤ 0). Callers get [TimeTrialEstimate.invalid] back —
///     NOT a thrown exception. Throwing would force every callsite
///     into try/catch; the coach dashboard has 20+ rows and a single
///     bad row must not break the whole table.
class TimeTrialThresholdEstimator {
  const TimeTrialThresholdEstimator();

  TimeTrialEstimate estimate(TimeTrialResultEntity result) {
    if (result.actualDistanceM <= 0 || result.actualDurationS <= 0) {
      return const TimeTrialEstimate.invalid();
    }

    final avgPace = result.avgPaceSecKm;
    if (avgPace == null || avgPace <= 0) {
      return const TimeTrialEstimate.invalid();
    }

    final thresholdPace = (avgPace * result.protocol.pacingMultiplier).floor();
    int? lthrBpm;
    if (result.avgHrBpm != null && result.avgHrBpm! > 0) {
      lthrBpm = (result.avgHrBpm! * result.protocol.hrMultiplier).round();
    }

    return TimeTrialEstimate(
      thresholdPaceSecKm: thresholdPace,
      lthrBpm: lthrBpm,
      sourceProtocol: result.protocol,
      sourceFinishedAt: result.finishedAt,
      valid: true,
    );
  }
}

/// Output of [TimeTrialThresholdEstimator]. [valid] is `false` when
/// the source data was corrupt; in that case all other fields are
/// `null`.
class TimeTrialEstimate {
  const TimeTrialEstimate({
    required this.thresholdPaceSecKm,
    required this.lthrBpm,
    required this.sourceProtocol,
    required this.sourceFinishedAt,
    required this.valid,
  });

  const TimeTrialEstimate.invalid()
      : thresholdPaceSecKm = null,
        lthrBpm = null,
        sourceProtocol = null,
        sourceFinishedAt = null,
        valid = false;

  final int? thresholdPaceSecKm;
  final int? lthrBpm;
  final TimeTrialProtocol? sourceProtocol;
  final DateTime? sourceFinishedAt;
  final bool valid;

  @override
  String toString() => valid
      ? 'TimeTrialEstimate(threshold: ${thresholdPaceSecKm}s/km, lthr: '
          '${lthrBpm ?? '-'} bpm, from ${sourceProtocol?.kind})'
      : 'TimeTrialEstimate.invalid';
}
