import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/domain/usecases/progression/award_xp_for_workout.dart';
import 'package:omni_runner/domain/usecases/progression/claim_rewards.dart';
import 'package:omni_runner/domain/usecases/progression/evaluate_badges.dart';
import 'package:omni_runner/domain/usecases/progression/post_session_progression.dart';
import 'package:omni_runner/domain/usecases/progression/update_mission_progress.dart';

class _FakeXpRepo implements IXpTransactionRepo {
  final List<XpTransactionEntity> _entries = [];
  @override Future<void> append(XpTransactionEntity tx) async => _entries.add(tx);
  @override Future<List<XpTransactionEntity>> getByUserId(String u) async => _entries;
  @override Future<List<XpTransactionEntity>> getByRefId(String r) async =>
      _entries.where((e) => e.refId == r).toList();
  @override Future<int> sumSessionXpToday(String u) async => 0;
  @override Future<int> sumBonusXpToday(String u) async => 0;
  @override Future<int> sumByUserId(String u) async => 0;
  @override Future<int> sumByUserIdInRange(String u, int from, int to) async => 0;
}

class _FakeProfileRepo implements IProfileProgressRepo {
  ProfileProgressEntity? stored;
  @override Future<ProfileProgressEntity> getByUserId(String u) async =>
      stored ?? ProfileProgressEntity(userId: u);
  @override Future<void> save(ProfileProgressEntity p) async => stored = p;
}

class _FakeBadgeAwardRepo implements IBadgeAwardRepo {
  @override Future<List<BadgeAwardEntity>> getByUserId(String u) async => [];
  @override Future<void> save(BadgeAwardEntity a) async {}
  @override Future<bool> isUnlocked(String userId, String badgeId) async => false;
}

class _FakeMissionRepo implements IMissionProgressRepo {
  @override Future<List<MissionProgressEntity>> getActiveByUserId(String u) async => [];
  @override Future<void> save(MissionProgressEntity p) async {}
  @override Future<List<MissionProgressEntity>> getByUserId(String u) async => [];
  @override Future<MissionProgressEntity?> getById(String id) async => null;
  @override Future<MissionProgressEntity?> getByUserAndMission(String u, String m) async => null;
}

class _FakeLedgerRepo implements ILedgerRepo {
  @override Future<void> append(LedgerEntryEntity e) async {}
  @override Future<List<LedgerEntryEntity>> getByUserId(String u) async => [];
  @override Future<List<LedgerEntryEntity>> getByRefId(String r) async => [];
  @override Future<int> countCreditsToday(String u) async => 0;
  @override Future<int> sumByUserId(String u) async => 0;
}

class _FakeWalletRepo implements IWalletRepo {
  @override Future<WalletEntity> getByUserId(String u) async => WalletEntity(userId: u);
  @override Future<void> save(WalletEntity w) async {}
}

void main() {
  late PostSessionProgression usecase;

  setUp(() {
    final xpRepo = _FakeXpRepo();
    final profileRepo = _FakeProfileRepo();
    final badgeAwardRepo = _FakeBadgeAwardRepo();
    final missionRepo = _FakeMissionRepo();
    final ledgerRepo = _FakeLedgerRepo();
    final walletRepo = _FakeWalletRepo();

    usecase = PostSessionProgression(
      awardXp: AwardXpForWorkout(xpRepo: xpRepo, profileRepo: profileRepo),
      evaluateBadges: EvaluateBadges(awardRepo: badgeAwardRepo),
      updateMissions: UpdateMissionProgress(progressRepo: missionRepo),
      claimRewards: ClaimRewards(xpRepo: xpRepo, profileRepo: profileRepo, ledgerRepo: ledgerRepo, walletRepo: walletRepo),
      profileRepo: profileRepo,
      badgeCatalog: const [],
      activeMissionDefs: () => const [],
    );
  });

  test('pipeline runs without throwing for verified session', () async {
    const session = WorkoutSessionEntity(
      id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: [], isVerified: true, totalDistanceM: 5000,
    );

    final result = await usecase.call(
      session: session, totalDistanceM: 5000, movingMs: 1800000,
      avgPaceSecPerKm: 360, isNewPacePr: false, sessionStartHourLocal: 8,
      uuidGenerator: () => 'id', nowMs: 1000,
    );

    expect(result.xpResult, isNotNull);
    expect(result.claimResult, isNotNull);
  });

  test('pipeline handles unverified session gracefully', () async {
    const session = WorkoutSessionEntity(
      id: 'ses-2', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: [], isVerified: false,
    );

    final result = await usecase.call(
      session: session, totalDistanceM: 500, movingMs: 300000,
      avgPaceSecPerKm: 600, isNewPacePr: false, sessionStartHourLocal: 10,
      uuidGenerator: () => 'id', nowMs: 1000,
    );

    expect(result.xpResult.awarded, isFalse);
  });
}
