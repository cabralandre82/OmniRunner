/// Kinds of celebratable milestones recognised by
/// [MilestoneDetector]. Each value owns:
///
///   * a stable **dedup key** (see [dedupKey]) that is persisted
///     so a milestone never fires twice for the same user
///     (even across app reinstalls / account restorations);
///   * a **priority** (see [priority]) used when multiple
///     milestones trigger on the same session — we celebrate
///     the biggest one first and queue smaller ones behind it;
///   * a **distance threshold** (if any) that anchors detection
///     in a pure function; for non-distance milestones the
///     field is `null` and the detector branches on streaks /
///     session counts.
///
/// Finding reference: L22-09 (Progress celebration tímida).
enum MilestoneKind {
  /// Very first completed run — the single most emotionally
  /// charged moment in the amateur lifecycle.
  firstRun(
    dedupKey: 'first_run',
    priority: 1,
    distanceThresholdM: null,
  ),

  /// First session crossing the 5 km line. Classic "I'm a runner
  /// now" moment.
  firstFiveK(
    dedupKey: 'first_5k',
    priority: 2,
    distanceThresholdM: 5000,
  ),

  /// First 10 km. Non-trivial for the amateur persona.
  firstTenK(
    dedupKey: 'first_10k',
    priority: 3,
    distanceThresholdM: 10000,
  ),

  /// Official half-marathon distance (21.0975 km — rounded to
  /// 21097.5 m for single-precision math that still survives
  /// rounding on GPS-measured sessions).
  firstHalfMarathon(
    dedupKey: 'first_half_marathon',
    priority: 4,
    distanceThresholdM: 21097.5,
  ),

  /// Full-marathon distance (42.195 km).
  firstMarathon(
    dedupKey: 'first_marathon',
    priority: 5,
    distanceThresholdM: 42195,
  ),

  /// First ISO week with 3+ verified sessions — the finding
  /// calls this out as "primeira semana".
  firstWeek(
    dedupKey: 'first_week',
    priority: 6,
    distanceThresholdM: null,
  ),

  /// 7-day streak of daily verified sessions.
  streakSeven(
    dedupKey: 'streak_7',
    priority: 7,
    distanceThresholdM: null,
  ),

  /// 30-day streak — rare, reserved for "hall of fame" copy.
  streakThirty(
    dedupKey: 'streak_30',
    priority: 8,
    distanceThresholdM: null,
  ),

  /// New lifetime longest run (not a one-shot — can fire again
  /// any time the record is broken; the dedup key is therefore
  /// augmented at runtime with the new distance).
  longestRunEver(
    dedupKey: 'longest_run_ever',
    priority: 9,
    distanceThresholdM: null,
  );

  const MilestoneKind({
    required this.dedupKey,
    required this.priority,
    required this.distanceThresholdM,
  });

  /// Stable string persisted in the "already celebrated" set.
  /// Changing a value in-place is a migration — bump the dedup
  /// key with a numeric suffix (`first_5k_v2`) and migrate the
  /// legacy persistence layer at read time.
  final String dedupKey;

  /// Lower priority = bigger, more emotional celebration.
  /// Ties are broken by enum declaration order.
  final int priority;

  /// Distance in meters that must be crossed for the milestone
  /// to fire. `null` for milestones that are not anchored to a
  /// single-session distance (streaks, weekly aggregates).
  final double? distanceThresholdM;
}
