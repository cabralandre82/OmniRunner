import 'package:omni_runner/domain/value_objects/workout_completion_status.dart';

/// Result of a feedback-streak computation: the *current* streak of
/// consecutive calendar days with at least one complete-feedback
/// workout, the *longest* streak observed in the input window, and a
/// flag indicating whether the 30-day bronze badge is unlocked.
class FeedbackStreakResult {
  const FeedbackStreakResult({
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.badgeBronzeUnlocked,
  });

  final int currentStreakDays;
  final int longestStreakDays;
  final bool badgeBronzeUnlocked;

  @override
  String toString() =>
      'FeedbackStreakResult(current: $currentStreakDays, longest: '
      '$longestStreakDays, bronze: $badgeBronzeUnlocked)';
}

/// L23-13 — Pure calculator for the athlete's feedback streak.
///
/// Contract
/// --------
///   - Pure: zero I/O, zero async, deterministic.
///   - The caller provides a flat list of [DateTime] values — each
///     representing the *finishedAt* of a workout whose feedback
///     reached [WorkoutCompletionStatus.complete]. Incomplete
///     feedback must NOT be passed in (that's the evaluator's job).
///   - Dates are quantised to UTC calendar day; two feedbacks on the
///     same UTC day count as one. This matches the "daily streak"
///     mental model users carry over from [ProfileProgressEntity].
///   - The "current" streak ends at a reference day (default: today
///     in UTC). If the most recent feedback is older than that day
///     minus 1 (i.e. yesterday had no feedback AND today had none),
///     the current streak resets to 0. A single-day gap breaks the
///     streak on purpose — "consecutivo" means consecutivo.
///   - The bronze badge flag follows
///     [WorkoutFeedbackBounds.bronzeStreakDays] (30 by default).
class FeedbackStreakCalculator {
  const FeedbackStreakCalculator();

  FeedbackStreakResult calculate({
    required List<DateTime> completeFeedbackDates,
    DateTime? referenceDay,
  }) {
    if (completeFeedbackDates.isEmpty) {
      return const FeedbackStreakResult(
        currentStreakDays: 0,
        longestStreakDays: 0,
        badgeBronzeUnlocked: false,
      );
    }

    final refDay = _asUtcDay(referenceDay ?? DateTime.now().toUtc());

    final days = completeFeedbackDates
        .map(_asUtcDay)
        .toSet()
        .toList()
      ..sort();

    int longest = 1;
    int running = 1;
    for (var i = 1; i < days.length; i++) {
      final prev = days[i - 1];
      final curr = days[i];
      final diff = curr.difference(prev).inDays;
      if (diff == 1) {
        running += 1;
        if (running > longest) longest = running;
      } else {
        running = 1;
      }
    }

    final mostRecent = days.last;
    final daysBehind = refDay.difference(mostRecent).inDays;
    int current;
    if (daysBehind < 0) {
      current = 0;
    } else if (daysBehind <= 1) {
      current = 1;
      for (var i = days.length - 2; i >= 0; i--) {
        final next = days[i + 1];
        final here = days[i];
        if (next.difference(here).inDays == 1) {
          current += 1;
        } else {
          break;
        }
      }
    } else {
      current = 0;
    }

    final bronze = current >= WorkoutFeedbackBounds.bronzeStreakDays;
    return FeedbackStreakResult(
      currentStreakDays: current,
      longestStreakDays: longest,
      badgeBronzeUnlocked: bronze,
    );
  }

  static DateTime _asUtcDay(DateTime d) {
    final utc = d.isUtc ? d : d.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}
