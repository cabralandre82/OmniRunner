/// L23-14 — Canonical time-trial protocols for threshold/zone estimation.
///
/// A time trial (TT) is a controlled all-out effort whose result
/// calibrates the athlete's training zones. The three protocols
/// below are the de-facto standards that the audit (L23-14) calls
/// out — any protocol added in the future MUST go through the
/// runbook's "how-to add" flow so the threshold estimator and CI
/// guard stay aligned.
///
/// Contract
/// --------
///   - [kind] is the stable identifier used for analytics and for
///     persisting scheduled workouts (`plan_workouts.time_trial_kind`).
///   - [distanceM] / [durationS] pin the *target* — the execution
///     may come in slightly over/under but the estimator uses the
///     *actual* values from [TimeTrialResult].
///   - [pacingMultiplier] converts the TT's average pace to the
///     athlete's threshold pace. Rationale per protocol:
///       * 3 km is run at ~110% of threshold (shorter = hotter).
///       * 5 km is run at ~105% of threshold (classic proxy).
///       * 30 min TT is *defined* as threshold — multiplier = 1.00.
///     Negative drift (multiplier < 1) would mean TT pace is slower
///     than threshold — impossible by construction, CI guards that.
///   - [hrMultiplier] mirrors [pacingMultiplier] for average HR.
///
/// See `docs/runbooks/TIME_TRIAL_RUNBOOK.md`.
enum TimeTrialProtocol {
  threeKm(
    kind: 'three_km',
    label: '3 km time trial',
    distanceM: 3000,
    durationS: null,
    pacingMultiplier: 1.10,
    hrMultiplier: 0.92,
  ),
  fiveKm(
    kind: 'five_km',
    label: '5 km time trial',
    distanceM: 5000,
    durationS: null,
    pacingMultiplier: 1.05,
    hrMultiplier: 0.95,
  ),
  thirtyMinute(
    kind: 'thirty_minute',
    label: '30 min tempo trial',
    distanceM: null,
    durationS: 1800,
    pacingMultiplier: 1.00,
    hrMultiplier: 1.00,
  );

  const TimeTrialProtocol({
    required this.kind,
    required this.label,
    required this.distanceM,
    required this.durationS,
    required this.pacingMultiplier,
    required this.hrMultiplier,
  });

  final String kind;
  final String label;
  final int? distanceM;
  final int? durationS;
  final double pacingMultiplier;
  final double hrMultiplier;

  static TimeTrialProtocol? fromKind(String? raw) {
    if (raw == null) return null;
    for (final p in TimeTrialProtocol.values) {
      if (p.kind == raw) return p;
    }
    return null;
  }

  /// True when the protocol is pinned to a distance (run until x km).
  bool get isDistanceBased => distanceM != null;

  /// True when the protocol is pinned to a duration (run for y min).
  bool get isDurationBased => durationS != null;
}

/// Minimum recency for a TT result to be considered "current" when
/// calibrating zones. Older results are still stored historically
/// but the zone updater ignores them — athletes drift too much in
/// 12 weeks for a stale TT to drive Z2 load prescription.
class TimeTrialFreshness {
  const TimeTrialFreshness._();

  /// 84 days ≈ 12 weeks. Anything beyond this needs a re-test.
  static const int maxAgeDays = 84;
}
