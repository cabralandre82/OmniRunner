import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/services/milestone_detector.dart';
import 'package:omni_runner/domain/value_objects/milestone_kind.dart';

ProfileProgressEntity _progress({
  required int lifetimeSessionCount,
  double lifetimeDistanceM = 0,
  int dailyStreakCount = 0,
  int weeklySessionCount = 0,
}) {
  return ProfileProgressEntity(
    userId: 'u',
    lifetimeSessionCount: lifetimeSessionCount,
    lifetimeDistanceM: lifetimeDistanceM,
    dailyStreakCount: dailyStreakCount,
    weeklySessionCount: weeklySessionCount,
  );
}

MilestoneDetectionInput _input({
  ProfileProgressEntity? previous,
  required ProfileProgressEntity current,
  required double sessionDistanceM,
  double previousMaxDistanceM = 0,
  Set<String> alreadyCelebratedKeys = const {},
  int achievedAtMs = 1_700_000_000_000,
}) {
  return MilestoneDetectionInput(
    previousProgress: previous,
    currentProgress: current,
    sessionDistanceM: sessionDistanceM,
    previousMaxDistanceM: previousMaxDistanceM,
    alreadyCelebratedKeys: alreadyCelebratedKeys,
    achievedAtMs: achievedAtMs,
  );
}

void main() {
  const det = MilestoneDetector();

  group('MilestoneDetector — firstRun', () {
    test('fires when lifetimeSessionCount crosses 0 → 1', () {
      final milestones = det.detect(_input(
        previous: null,
        current: _progress(lifetimeSessionCount: 1, lifetimeDistanceM: 2000),
        sessionDistanceM: 2000,
      ));
      expect(milestones.map((m) => m.kind), contains(MilestoneKind.firstRun));
    });

    test('does not fire on subsequent runs', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 1, lifetimeDistanceM: 2000),
        current: _progress(lifetimeSessionCount: 2, lifetimeDistanceM: 4000),
        sessionDistanceM: 2000,
        previousMaxDistanceM: 2000,
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.firstRun)));
    });

    test('does not re-fire when already celebrated', () {
      final milestones = det.detect(_input(
        previous: null,
        current: _progress(lifetimeSessionCount: 1),
        sessionDistanceM: 2000,
        alreadyCelebratedKeys: {'first_run'},
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.firstRun)));
    });
  });

  group('MilestoneDetector — distance milestones', () {
    test('firstFiveK fires when session crosses 5 km for the first time', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 3, lifetimeDistanceM: 10000),
        current: _progress(lifetimeSessionCount: 4, lifetimeDistanceM: 15100),
        sessionDistanceM: 5100,
        previousMaxDistanceM: 4800,
      ));
      final fiveK = milestones.firstWhere(
        (m) => m.kind == MilestoneKind.firstFiveK,
        orElse: () => throw TestFailure('firstFiveK not fired'),
      );
      expect(fiveK.triggerDistanceM, 5100);
    });

    test('firstFiveK does NOT fire if prior session already crossed 5 km', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 5, lifetimeDistanceM: 40000),
        current: _progress(lifetimeSessionCount: 6, lifetimeDistanceM: 46000),
        sessionDistanceM: 6000,
        previousMaxDistanceM: 8000,
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.firstFiveK)));
    });

    test('firstTenK fires strictly above 10000 m threshold', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 10, lifetimeDistanceM: 50000),
        current: _progress(lifetimeSessionCount: 11, lifetimeDistanceM: 60500),
        sessionDistanceM: 10500,
        previousMaxDistanceM: 7000,
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.firstTenK));
    });

    test('firstHalfMarathon fires at 21097.5 m', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 20, lifetimeDistanceM: 200000),
        current: _progress(lifetimeSessionCount: 21, lifetimeDistanceM: 221100),
        sessionDistanceM: 21100,
        previousMaxDistanceM: 15000,
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.firstHalfMarathon));
    });

    test('firstMarathon fires at 42195 m', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 40, lifetimeDistanceM: 800000),
        current: _progress(lifetimeSessionCount: 41, lifetimeDistanceM: 843000),
        sessionDistanceM: 43000,
        previousMaxDistanceM: 30000,
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.firstMarathon));
    });

    test('one hero session that crosses both 5K and 10K fires both', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 1, lifetimeDistanceM: 2000),
        current: _progress(lifetimeSessionCount: 2, lifetimeDistanceM: 12000),
        sessionDistanceM: 10000,
        previousMaxDistanceM: 2000,
      ));
      final kinds = milestones.map((m) => m.kind).toSet();
      expect(kinds, containsAll(<MilestoneKind>[
        MilestoneKind.firstFiveK,
        MilestoneKind.firstTenK,
      ]));
    });
  });

  group('MilestoneDetector — firstWeek', () {
    test('fires the first time weekly sessions crosses 3', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 2, weeklySessionCount: 2),
        current: _progress(lifetimeSessionCount: 3, weeklySessionCount: 3),
        sessionDistanceM: 3000,
        previousMaxDistanceM: 3000,
      ));
      final fw = milestones.firstWhere(
        (m) => m.kind == MilestoneKind.firstWeek,
        orElse: () => throw TestFailure('firstWeek not fired'),
      );
      expect(fw.triggerCount, 3);
    });

    test('does not fire if weekly count was already ≥3 last session', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 3, weeklySessionCount: 3),
        current: _progress(lifetimeSessionCount: 4, weeklySessionCount: 4),
        sessionDistanceM: 3000,
        previousMaxDistanceM: 3000,
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.firstWeek)));
    });

    test('does not re-fire when already celebrated', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 2, weeklySessionCount: 2),
        current: _progress(lifetimeSessionCount: 3, weeklySessionCount: 3),
        sessionDistanceM: 3000,
        previousMaxDistanceM: 3000,
        alreadyCelebratedKeys: {'first_week'},
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.firstWeek)));
    });
  });

  group('MilestoneDetector — streaks', () {
    test('streakSeven fires on the first 7th day', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 6, dailyStreakCount: 6),
        current: _progress(lifetimeSessionCount: 7, dailyStreakCount: 7),
        sessionDistanceM: 5000,
        previousMaxDistanceM: 5000,
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.streakSeven));
    });

    test('streakThirty fires independently of streakSeven dedup', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 29, dailyStreakCount: 29),
        current: _progress(lifetimeSessionCount: 30, dailyStreakCount: 30),
        sessionDistanceM: 5000,
        previousMaxDistanceM: 5000,
        alreadyCelebratedKeys: {'streak_7'},
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.streakThirty));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.streakSeven)));
    });

    test('no streak fires when streak drops (0) even if max ≥7', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 10, dailyStreakCount: 7),
        current: _progress(lifetimeSessionCount: 11, dailyStreakCount: 0),
        sessionDistanceM: 5000,
        previousMaxDistanceM: 5000,
      ));
      final kinds = milestones.map((m) => m.kind).toSet();
      expect(kinds, isNot(contains(MilestoneKind.streakSeven)));
      expect(kinds, isNot(contains(MilestoneKind.streakThirty)));
    });
  });

  group('MilestoneDetector — longestRunEver', () {
    test('fires on strictly longer session than previous max', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 5, lifetimeDistanceM: 25000),
        current: _progress(lifetimeSessionCount: 6, lifetimeDistanceM: 32800),
        sessionDistanceM: 7800,
        previousMaxDistanceM: 6200,
      ));
      final lre = milestones.firstWhere(
        (m) => m.kind == MilestoneKind.longestRunEver,
        orElse: () => throw TestFailure('longestRunEver not fired'),
      );
      expect(lre.triggerDistanceM, 7800);
    });

    test('dedupKey bakes in distance so new records re-fire', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 5),
        current: _progress(lifetimeSessionCount: 6),
        sessionDistanceM: 9000,
        previousMaxDistanceM: 7800,
        alreadyCelebratedKeys: {'longest_run_ever:780'},
      ));
      expect(milestones.map((m) => m.kind),
          contains(MilestoneKind.longestRunEver));
    });

    test('same-distance repeat does not fire', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 5),
        current: _progress(lifetimeSessionCount: 6),
        sessionDistanceM: 7800,
        previousMaxDistanceM: 7800,
      ));
      expect(milestones.map((m) => m.kind),
          isNot(contains(MilestoneKind.longestRunEver)));
    });
  });

  group('MilestoneDetector — output contract', () {
    test('milestones are sorted by priority ascending', () {
      final milestones = det.detect(_input(
        previous: _progress(lifetimeSessionCount: 0, dailyStreakCount: 6),
        current: _progress(
          lifetimeSessionCount: 1,
          dailyStreakCount: 7,
          weeklySessionCount: 3,
        ),
        sessionDistanceM: 6000,
        previousMaxDistanceM: 0,
      ));
      final priorities = milestones.map((m) => m.kind.priority).toList();
      expect(priorities, List<int>.from(priorities)..sort());
      expect(priorities.length, greaterThan(1));
    });

    test('every kind has a non-empty, unique dedup key', () {
      final keys =
          MilestoneKind.values.map((k) => k.dedupKey).toList(growable: false);
      expect(keys.toSet().length, keys.length);
      for (final k in keys) {
        expect(k.isNotEmpty, isTrue);
      }
    });

    test('enum cardinality pinned — 9 kinds total', () {
      expect(MilestoneKind.values.length, 9);
    });
  });
}
