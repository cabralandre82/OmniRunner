import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_challenge_repo.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/ledger_service.dart';
import 'package:omni_runner/domain/usecases/gamification/settle_challenge.dart';

class _FakeChallengeRepo implements IChallengeRepo {
  ChallengeEntity? stored;
  ChallengeResultEntity? result;
  ChallengeEntity? updatedWith;
  @override Future<ChallengeEntity?> getById(String id) async => stored;
  @override Future<void> update(ChallengeEntity c) async => updatedWith = c;
  @override Future<ChallengeResultEntity?> getResultByChallengeId(String id) async => result;
  @override Future<void> save(ChallengeEntity c) async {}
  @override Future<List<ChallengeEntity>> getByUserId(String u) async => [];
  @override Future<List<ChallengeEntity>> getByStatus(ChallengeStatus s) async => [];
  @override Future<void> deleteById(String id) async {}
  @override Future<void> saveResult(ChallengeResultEntity r) async {}
}

class _FakeLedgerRepo implements ILedgerRepo {
  final List<LedgerEntryEntity> entries = [];
  @override Future<void> append(LedgerEntryEntity e) async => entries.add(e);
  @override Future<List<LedgerEntryEntity>> getByUserId(String u) async => entries.where((e) => e.userId == u).toList();
  @override Future<List<LedgerEntryEntity>> getByRefId(String r) async => entries.where((e) => e.refId == r).toList();
  @override Future<int> countCreditsToday(String u) async => 0;
  @override Future<int> sumByUserId(String u) async {
    var sum = 0;
    for (final e in entries.where((e) => e.userId == u)) {
      sum += e.deltaCoins;
    }
    return sum;
  }
}

class _FakeWalletRepo implements IWalletRepo {
  final Map<String, WalletEntity> wallets = {};
  @override Future<WalletEntity> getByUserId(String u) async => wallets[u] ?? WalletEntity(userId: u);
  @override Future<void> save(WalletEntity w) async => wallets[w.userId] = w;
}

void main() {
  late _FakeChallengeRepo challengeRepo;
  late SettleChallenge usecase;

  setUp(() {
    challengeRepo = _FakeChallengeRepo();
    final ledgerRepo = _FakeLedgerRepo();
    final walletRepo = _FakeWalletRepo();
    final ledgerService = LedgerService(ledgerRepo: ledgerRepo, walletRepo: walletRepo);
    usecase = SettleChallenge(challengeRepo: challengeRepo, ledgerService: ledgerService);
  });

  test('throws when challenge not found', () {
    challengeRepo.stored = null;
    expect(
      () => usecase.call(challengeId: 'x', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<ChallengeNotFound>()),
    );
  });

  test('no-op when already completed', () async {
    challengeRepo.stored = ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.completed,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: const [], createdAtMs: 0,
    );
    await usecase.call(challengeId: 'ch-1', uuidGenerator: () => 'id', nowMs: 1000);
    expect(challengeRepo.updatedWith, isNull);
  });

  test('throws when not completing status', () {
    challengeRepo.stored = ChallengeEntity(
      id: 'ch-1', creatorUserId: 'u1', status: ChallengeStatus.pending,
      type: ChallengeType.oneVsOne,
      rules: const ChallengeRulesEntity(goal: ChallengeGoal.mostDistance, windowMs: 86400000),
      participants: const [], createdAtMs: 0,
    );
    expect(
      () => usecase.call(challengeId: 'ch-1', uuidGenerator: () => 'id', nowMs: 1000),
      throwsA(isA<InvalidChallengeStatus>()),
    );
  });
}
