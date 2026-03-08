import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/usecases/progression/evaluate_badges.dart';

class _FakeBadgeAwardRepo implements IBadgeAwardRepo {
  final Set<String> _unlocked = {};
  final List<BadgeAwardEntity> _saved = [];

  @override
  Future<bool> isUnlocked(String userId, String badgeId) async =>
      _unlocked.contains(badgeId);
  @override
  Future<void> save(BadgeAwardEntity award) async {
    _unlocked.add(award.badgeId);
    _saved.add(award);
  }
  @override
  Future<List<BadgeAwardEntity>> getByUserId(String userId) async => _saved;
}

void main() {
  late _FakeBadgeAwardRepo awardRepo;
  late EvaluateBadges usecase;
  int seq = 0;

  const session = WorkoutSessionEntity(
    id: 'ses-1',
    userId: 'u1',
    status: WorkoutStatus.completed,
    startTimeMs: 0,
    route: [],
  );

  const profile = ProfileProgressEntity(
    userId: 'u1',
    lifetimeSessionCount: 100,
    lifetimeDistanceM: 500000,
    lifetimeMovingMs: 3600000 * 50,
  );

  setUp(() {
    seq = 0;
    awardRepo = _FakeBadgeAwardRepo();
    usecase = EvaluateBadges(awardRepo: awardRepo);
  });

  test('unlocks SingleSessionDistance badge', () async {
    final catalog = [
      const BadgeEntity(
        id: 'badge-5k',
        category: BadgeCategory.distance,
        tier: BadgeTier.bronze,
        name: '5K Runner',
        description: 'Run 5km in a single session',
        criteria: SingleSessionDistance(5000),
        xpReward: 50,
        coinsReward: 10,
      ),
    ];

    const ctx = BadgeEvalContext(
      session: session,
      profile: profile,
      sessionDistanceM: 5500,
      sessionMovingMs: 1800000,
      sessionStartHourLocal: 8,
    );

    final awards = await usecase.call(
      catalog: catalog,
      ctx: ctx,
      uuidGenerator: () => 'award-${seq++}',
      nowMs: 1000,
    );

    expect(awards, hasLength(1));
    expect(awards[0].badgeId, 'badge-5k');
  });

  test('does not re-unlock already unlocked badge', () async {
    awardRepo._unlocked.add('badge-5k');

    final catalog = [
      const BadgeEntity(
        id: 'badge-5k',
        category: BadgeCategory.distance,
        tier: BadgeTier.bronze,
        name: '5K',
        description: '',
        criteria: SingleSessionDistance(5000),
        xpReward: 50,
        coinsReward: 10,
      ),
    ];

    const ctx = BadgeEvalContext(
      session: session,
      profile: profile,
      sessionDistanceM: 10000,
      sessionMovingMs: 3600000,
      sessionStartHourLocal: 8,
    );

    final awards = await usecase.call(
      catalog: catalog,
      ctx: ctx,
      uuidGenerator: () => 'id',
      nowMs: 1000,
    );

    expect(awards, isEmpty);
  });

  test('returns empty when user has no userId', () async {
    const noUserSession = WorkoutSessionEntity(
      id: 'ses-2',
      status: WorkoutStatus.completed,
      startTimeMs: 0,
      route: [],
    );

    const ctx = BadgeEvalContext(
      session: noUserSession,
      profile: profile,
      sessionDistanceM: 10000,
      sessionMovingMs: 3600000,
      sessionStartHourLocal: 8,
    );

    final awards = await usecase.call(
      catalog: [
        const BadgeEntity(
          id: 'b1',
          category: BadgeCategory.distance,
          tier: BadgeTier.bronze,
          name: 'Test',
          description: '',
          criteria: SingleSessionDistance(1000),
          xpReward: 10,
          coinsReward: 0,
        ),
      ],
      ctx: ctx,
      uuidGenerator: () => 'id',
      nowMs: 1000,
    );

    expect(awards, isEmpty);
  });

  test('unlocks SessionCount badge based on lifetime count', () async {
    final catalog = [
      const BadgeEntity(
        id: 'badge-100',
        category: BadgeCategory.frequency,
        tier: BadgeTier.silver,
        name: '100 runs',
        description: '',
        criteria: SessionCount(100),
        xpReward: 100,
        coinsReward: 20,
      ),
    ];

    const ctx = BadgeEvalContext(
      session: session,
      profile: profile,
      sessionDistanceM: 5000,
      sessionMovingMs: 1800000,
      sessionStartHourLocal: 8,
    );

    final awards = await usecase.call(
      catalog: catalog,
      ctx: ctx,
      uuidGenerator: () => 'award-${seq++}',
      nowMs: 1000,
    );

    expect(awards, hasLength(1));
  });

  test('early bird badge for session before specified hour', () async {
    final catalog = [
      const BadgeEntity(
        id: 'badge-early',
        category: BadgeCategory.special,
        tier: BadgeTier.bronze,
        name: 'Early Bird',
        description: '',
        criteria: SessionBeforeHour(6),
        xpReward: 30,
        coinsReward: 5,
      ),
    ];

    const ctx = BadgeEvalContext(
      session: session,
      profile: profile,
      sessionDistanceM: 3000,
      sessionMovingMs: 900000,
      sessionStartHourLocal: 5,
    );

    final awards = await usecase.call(
      catalog: catalog,
      ctx: ctx,
      uuidGenerator: () => 'award-${seq++}',
      nowMs: 1000,
    );

    expect(awards, hasLength(1));
  });
}
