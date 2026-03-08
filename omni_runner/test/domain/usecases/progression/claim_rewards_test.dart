import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_profile_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';
import 'package:omni_runner/domain/usecases/progression/claim_rewards.dart';

class _FakeXpRepo implements IXpTransactionRepo {
  final List<XpTransactionEntity> entries = [];
  @override Future<void> append(XpTransactionEntity tx) async => entries.add(tx);
  @override Future<List<XpTransactionEntity>> getByUserId(String u) async => entries;
  @override Future<List<XpTransactionEntity>> getByRefId(String r) async =>
      entries.where((e) => e.refId == r).toList();
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
  late ClaimRewards usecase;
  late _FakeXpRepo xpRepo;
  int seq = 0;

  setUp(() {
    seq = 0;
    xpRepo = _FakeXpRepo();
    usecase = ClaimRewards(
      xpRepo: xpRepo,
      profileRepo: _FakeProfileRepo(),
      ledgerRepo: _FakeLedgerRepo(),
      walletRepo: _FakeWalletRepo(),
    );
  });

  test('credits XP for badge', () async {
    const badge = BadgeAwardEntity(
      id: 'ba1', userId: 'u1', badgeId: 'b1',
      unlockedAtMs: 0, xpAwarded: 50,
    );

    final result = await usecase.call(
      userId: 'u1', badges: [badge], missions: [],
      missionDefs: {}, uuidGenerator: () => 'id-${seq++}', nowMs: 1000,
    );

    expect(result.totalXpCredited, 50);
    expect(result.entries, hasLength(1));
  });

  test('credits XP for mission', () async {
    const mission = MissionProgressEntity(
      id: 'mp1', userId: 'u1', missionId: 'tpl_daily_3km',
      status: MissionProgressStatus.completed, currentValue: 3000,
      targetValue: 3000, assignedAtMs: 0,
    );

    final result = await usecase.call(
      userId: 'u1', badges: [], missions: [mission],
      missionDefs: {
        'tpl_daily_3km': const MissionEntity(
          id: 'tpl_daily_3km', title: '3K', description: 'd',
          difficulty: MissionDifficulty.easy, slot: MissionSlot.daily,
          xpReward: 30, coinsReward: 5, criteria: AccumulateDistance(3000),
        ),
      },
      uuidGenerator: () => 'id-${seq++}', nowMs: 1000,
    );

    expect(result.totalXpCredited, 30);
  });

  test('skips already claimed badges (idempotent)', () async {
    const badge = BadgeAwardEntity(
      id: 'ba1', userId: 'u1', badgeId: 'b1',
      unlockedAtMs: 0, xpAwarded: 50,
    );

    await usecase.call(
      userId: 'u1', badges: [badge], missions: [],
      missionDefs: {}, uuidGenerator: () => 'id-${seq++}', nowMs: 1000,
    );

    final second = await usecase.call(
      userId: 'u1', badges: [badge], missions: [],
      missionDefs: {}, uuidGenerator: () => 'id-${seq++}', nowMs: 2000,
    );

    expect(second.totalXpCredited, 0);
  });
}
