import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/domain/usecases/progression/award_xp_for_workout.dart';

class _FakeXpRepo implements IXpTransactionRepo {
  final List<XpTransactionEntity> _entries = [];
  int todaySessionXp = 0;

  @override
  Future<void> append(XpTransactionEntity tx) async => _entries.add(tx);
  @override
  Future<List<XpTransactionEntity>> getByRefId(String refId) async =>
      _entries.where((tx) => tx.refId == refId).toList();
  @override
  Future<int> sumSessionXpToday(String userId) async => todaySessionXp;
  @override
  Future<int> sumBonusXpToday(String userId) async => 0;
  @override
  Future<List<XpTransactionEntity>> getByUserId(String userId) async => [];
  @override
  Future<int> sumByUserId(String userId) async => 0;
  @override
  Future<int> sumByUserIdInRange(String u, int f, int t) async => 0;
}

class _FakeProfileRepo implements IProfileProgressRepo {
  ProfileProgressEntity? saved;
  ProfileProgressEntity _profile = const ProfileProgressEntity(userId: 'u1');

  @override
  Future<ProfileProgressEntity> getByUserId(String userId) async => _profile;
  @override
  Future<void> save(ProfileProgressEntity p) async {
    _profile = p;
    saved = p;
  }
}

void main() {
  late _FakeXpRepo xpRepo;
  late _FakeProfileRepo profileRepo;
  late AwardXpForWorkout usecase;

  const validSession = WorkoutSessionEntity(
    id: 'ses-1',
    userId: 'u1',
    status: WorkoutStatus.completed,
    startTimeMs: 0,
    route: [],
    isVerified: true,
    avgBpm: 150,
  );

  setUp(() {
    xpRepo = _FakeXpRepo();
    profileRepo = _FakeProfileRepo();
    usecase = AwardXpForWorkout(xpRepo: xpRepo, profileRepo: profileRepo);
  });

  test('awards XP for valid completed session', () async {
    final result = await usecase.call(
      session: validSession,
      totalDistanceM: 5000,
      movingMs: 30 * 60 * 1000,
      uuidGenerator: () => 'tx-1',
      nowMs: 1000,
    );

    expect(result.awarded, isTrue);
    expect(result.xpAwarded, greaterThan(0));
    expect(profileRepo.saved, isNotNull);
    expect(profileRepo.saved!.lifetimeSessionCount, 1);
  });

  test('rejects incomplete session', () async {
    const incomplete = WorkoutSessionEntity(
      id: 'ses-2',
      userId: 'u1',
      status: WorkoutStatus.running,
      startTimeMs: 0,
      route: [],
    );

    final result = await usecase.call(
      session: incomplete,
      totalDistanceM: 5000,
      movingMs: 30 * 60 * 1000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isFalse);
    expect(result.rejectionReason, 'session_not_completed');
  });

  test('rejects unverified session', () async {
    const unverified = WorkoutSessionEntity(
      id: 'ses-2',
      userId: 'u1',
      status: WorkoutStatus.completed,
      startTimeMs: 0,
      route: [],
      isVerified: false,
    );

    final result = await usecase.call(
      session: unverified,
      totalDistanceM: 5000,
      movingMs: 30 * 60 * 1000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isFalse);
    expect(result.rejectionReason, 'session_not_verified');
  });

  test('rejects session below minimum distance', () async {
    final result = await usecase.call(
      session: validSession,
      totalDistanceM: 100,
      movingMs: 60000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isFalse);
    expect(result.rejectionReason, 'below_min_distance');
  });

  test('rejects session without userId', () async {
    const noUser = WorkoutSessionEntity(
      id: 'ses-3',
      status: WorkoutStatus.completed,
      startTimeMs: 0,
      route: [],
    );

    final result = await usecase.call(
      session: noUser,
      totalDistanceM: 5000,
      movingMs: 30 * 60 * 1000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isFalse);
    expect(result.rejectionReason, 'no_user_id');
  });

  test('caps XP at daily limit', () async {
    xpRepo.todaySessionXp = 990;

    final result = await usecase.call(
      session: validSession,
      totalDistanceM: 20000,
      movingMs: 120 * 60 * 1000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isTrue);
    expect(result.xpAwarded, lessThanOrEqualTo(10));
    expect(result.xpCapped, greaterThan(0));
  });

  test('rejects when daily cap already reached', () async {
    xpRepo.todaySessionXp = 1000;

    final result = await usecase.call(
      session: validSession,
      totalDistanceM: 5000,
      movingMs: 30 * 60 * 1000,
      uuidGenerator: () => 'tx',
      nowMs: 1000,
    );

    expect(result.awarded, isFalse);
    expect(result.rejectionReason, 'daily_cap_reached');
  });

  group('calculateSessionXp', () {
    test('base XP is 20', () {
      final xp = AwardXpForWorkout.calculateSessionXp(
        distanceM: 0,
        movingMs: 0,
        hasHr: false,
      );
      expect(xp, 20);
    });

    test('HR bonus adds 10', () {
      final withHr = AwardXpForWorkout.calculateSessionXp(
        distanceM: 0,
        movingMs: 0,
        hasHr: true,
      );
      final withoutHr = AwardXpForWorkout.calculateSessionXp(
        distanceM: 0,
        movingMs: 0,
        hasHr: false,
      );
      expect(withHr - withoutHr, 10);
    });

    test('distance bonus scales with km', () {
      final short = AwardXpForWorkout.calculateSessionXp(
        distanceM: 1000,
        movingMs: 0,
        hasHr: false,
      );
      final long = AwardXpForWorkout.calculateSessionXp(
        distanceM: 10000,
        movingMs: 0,
        hasHr: false,
      );
      expect(long, greaterThan(short));
    });
  });
}
