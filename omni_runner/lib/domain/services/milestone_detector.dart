import 'package:omni_runner/domain/entities/milestone_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/value_objects/milestone_kind.dart';

/// Input bundle fed to [MilestoneDetector.detect].
///
/// Kept as a value object so the use-case layer (and its tests)
/// can compose it without touching repositories — a
/// deterministic, pure-Dart detector is the only way to
/// exhaustively test the 9 kinds × {fires|does-not-fire} matrix
/// without hitting SQLite / network.
///
/// Finding reference: L22-09.
final class MilestoneDetectionInput {
  /// Progress snapshot **before** the new session was credited.
  /// `null` is equivalent to an all-zero snapshot (first-ever
  /// session path).
  final ProfileProgressEntity? previousProgress;

  /// Progress snapshot **after** the new session was credited.
  final ProfileProgressEntity currentProgress;

  /// Distance of the new session in meters.
  final double sessionDistanceM;

  /// Previous lifetime longest run in meters (before this
  /// session). Used solely for [MilestoneKind.longestRunEver].
  final double previousMaxDistanceM;

  /// Milestone dedup keys already celebrated for this user. A
  /// kind whose dedup key is in this set never re-fires (even if
  /// its condition trivially still holds — e.g. user has 6 5 km
  /// runs in a row).
  final Set<String> alreadyCelebratedKeys;

  /// Timestamp the detector should stamp on newly-minted
  /// [MilestoneEntity]s. Injected for deterministic tests.
  final int achievedAtMs;

  const MilestoneDetectionInput({
    required this.previousProgress,
    required this.currentProgress,
    required this.sessionDistanceM,
    required this.previousMaxDistanceM,
    required this.alreadyCelebratedKeys,
    required this.achievedAtMs,
  });
}

/// Pure, stateless milestone detector.
///
/// `detect(input)` returns the set of [MilestoneEntity]s newly
/// achieved by the session that produced [input.currentProgress],
/// sorted by [MilestoneKind.priority] ascending so the UI can
/// render the most dramatic one first.
///
/// Dedup is the caller's responsibility **after** the celebration
/// is shown — the detector reports what's newly achieved; the
/// persistence layer records the dedup key so it doesn't re-fire
/// tomorrow.
///
/// Finding reference: L22-09.
class MilestoneDetector {
  /// Minimum sessions in a single ISO week to count as "first
  /// week" for the amateur persona. Matches the narrative
  /// threshold ("ran 3 times in week 1").
  static const int firstWeekSessionThreshold = 3;

  const MilestoneDetector();

  List<MilestoneEntity> detect(MilestoneDetectionInput input) {
    final found = <MilestoneEntity>[];

    final prevLifetime = input.previousProgress?.lifetimeSessionCount ?? 0;
    final currLifetime = input.currentProgress.lifetimeSessionCount;
    final prevStreak = input.previousProgress?.dailyStreakCount ?? 0;
    final currStreak = input.currentProgress.dailyStreakCount;
    final prevWeekly = input.previousProgress?.weeklySessionCount ?? 0;
    final currWeekly = input.currentProgress.weeklySessionCount;

    void maybeAdd(
      MilestoneKind kind, {
      double? triggerDistanceM,
      int? triggerCount,
    }) {
      final entity = MilestoneEntity(
        kind: kind,
        achievedAtMs: input.achievedAtMs,
        triggerDistanceM: triggerDistanceM,
        triggerCount: triggerCount,
      );
      if (input.alreadyCelebratedKeys.contains(entity.dedupKey)) return;
      found.add(entity);
    }

    // firstRun: lifetimeSessionCount crossed 0 → ≥1.
    if (prevLifetime == 0 && currLifetime >= 1) {
      maybeAdd(MilestoneKind.firstRun);
    }

    // Distance-anchored: fire each of 5K/10K/Half/Marathon the
    // first time the new session's distance crosses the threshold
    // AND the previous lifetime max was below it.
    for (final kind in const [
      MilestoneKind.firstFiveK,
      MilestoneKind.firstTenK,
      MilestoneKind.firstHalfMarathon,
      MilestoneKind.firstMarathon,
    ]) {
      final threshold = kind.distanceThresholdM!;
      if (input.sessionDistanceM >= threshold &&
          input.previousMaxDistanceM < threshold) {
        maybeAdd(kind, triggerDistanceM: input.sessionDistanceM);
      }
    }

    // firstWeek: fires the first time weeklySessionCount crosses
    // [firstWeekSessionThreshold] AND the user had not previously
    // hit that count in any prior week (dedup prevents re-fire).
    if (prevWeekly < firstWeekSessionThreshold &&
        currWeekly >= firstWeekSessionThreshold) {
      maybeAdd(MilestoneKind.firstWeek, triggerCount: currWeekly);
    }

    // Streak milestones — integer crossings only. Upstream
    // UpdateStreak is the sole writer of dailyStreakCount so we
    // trust the delta.
    if (prevStreak < 7 && currStreak >= 7) {
      maybeAdd(MilestoneKind.streakSeven, triggerCount: currStreak);
    }
    if (prevStreak < 30 && currStreak >= 30) {
      maybeAdd(MilestoneKind.streakThirty, triggerCount: currStreak);
    }

    // longestRunEver: current session strictly greater than prior
    // max. The dedup key bakes in the rounded distance so a new
    // record in the future fires again (unlike first_5k which is
    // a once-per-lifetime moment).
    if (input.sessionDistanceM > input.previousMaxDistanceM &&
        input.sessionDistanceM > 0) {
      maybeAdd(
        MilestoneKind.longestRunEver,
        triggerDistanceM: input.sessionDistanceM,
      );
    }

    found.sort((a, b) => a.kind.priority.compareTo(b.kind.priority));
    return found;
  }
}
