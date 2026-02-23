import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/core/errors/gamification_failures.dart';
import 'package:omni_runner/domain/entities/challenge_entity.dart';
import 'package:omni_runner/domain/entities/challenge_participant_entity.dart';
import 'package:omni_runner/domain/entities/challenge_result_entity.dart';
import 'package:omni_runner/domain/entities/challenge_rules_entity.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/ledger_service.dart';

// ── In-memory fakes ─────────────────────────────────────────────

class _FakeLedgerRepo implements ILedgerRepo {
  final List<LedgerEntryEntity> entries = [];

  @override
  Future<void> append(LedgerEntryEntity entry) async {
    if (entries.any((e) => e.id == entry.id)) {
      throw DuplicateLedgerEntry(entry.id);
    }
    entries.add(entry);
  }

  @override
  Future<List<LedgerEntryEntity>> getByUserId(String userId) async =>
      entries.where((e) => e.userId == userId).toList();

  @override
  Future<List<LedgerEntryEntity>> getByRefId(String refId) async =>
      entries.where((e) => e.refId == refId).toList();

  @override
  Future<int> countCreditsToday(String userId) async =>
      entries.where((e) => e.userId == userId && e.isCredit).length;

  @override
  Future<int> sumByUserId(String userId) async => entries
      .where((e) => e.userId == userId)
      .fold<int>(0, (sum, e) => sum + e.deltaCoins);
}

class _FakeWalletRepo implements IWalletRepo {
  final Map<String, WalletEntity> _wallets = {};

  @override
  Future<WalletEntity> getByUserId(String userId) async =>
      _wallets[userId] ?? WalletEntity(userId: userId);

  @override
  Future<void> save(WalletEntity wallet) async {
    _wallets[wallet.userId] = wallet;
  }

  int balanceOf(String userId) =>
      _wallets[userId]?.balanceCoins ?? 0;

  int lifetimeSpentOf(String userId) =>
      _wallets[userId]?.lifetimeSpentCoins ?? 0;

  int lifetimeEarnedOf(String userId) =>
      _wallets[userId]?.lifetimeEarnedCoins ?? 0;
}

// ── Helpers ─────────────────────────────────────────────────────

ChallengeParticipantEntity _p(String userId) =>
    ChallengeParticipantEntity(
      userId: userId,
      displayName: userId,
      status: ParticipantStatus.accepted,
    );

ChallengeEntity _challenge({
  int entryFee = 10,
  List<ChallengeParticipantEntity>? participants,
}) =>
    ChallengeEntity(
      id: 'ch1',
      creatorUserId: 'u1',
      status: ChallengeStatus.active,
      type: ChallengeType.oneVsOne,
      rules: ChallengeRulesEntity(
        metric: ChallengeMetric.distance,
        windowMs: 604800000,
        entryFeeCoins: entryFee,
      ),
      participants: participants ?? [_p('u1'), _p('u2')],
      createdAtMs: 1000,
    );

ChallengeResultEntity _result({
  List<ParticipantResult>? results,
}) =>
    ChallengeResultEntity(
      challengeId: 'ch1',
      metric: ChallengeMetric.distance,
      results: results ??
          [
            const ParticipantResult(
              userId: 'u1',
              finalValue: 10000,
              rank: 1,
              outcome: ParticipantOutcome.won,
              coinsEarned: 40,
              sessionIds: ['s1'],
            ),
            const ParticipantResult(
              userId: 'u2',
              finalValue: 5000,
              rank: 2,
              outcome: ParticipantOutcome.lost,
              coinsEarned: 25,
              sessionIds: ['s2'],
            ),
          ],
      totalCoinsDistributed: 65,
      calculatedAtMs: 9000,
    );

void main() {
  late _FakeLedgerRepo ledgerRepo;
  late _FakeWalletRepo walletRepo;
  late LedgerService service;
  var uuidCounter = 0;
  String uuidGen() => 'uuid-${uuidCounter++}';

  setUp(() {
    ledgerRepo = _FakeLedgerRepo();
    walletRepo = _FakeWalletRepo();
    service = LedgerService(
      ledgerRepo: ledgerRepo,
      walletRepo: walletRepo,
    );
    uuidCounter = 0;
  });

  // ── DEBIT ENTRY FEES ──────────────────────────────────────────

  group('debitEntryFees', () {
    test('debits each accepted participant', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 100),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 50),
      );

      final result = await service.debitEntryFees(
        challenge: _challenge(entryFee: 10),
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      expect(result.success, isTrue);
      expect(result.entriesWritten, 2);
      expect(walletRepo.balanceOf('u1'), 90);
      expect(walletRepo.balanceOf('u2'), 40);
      expect(walletRepo.lifetimeSpentOf('u1'), 10);
      expect(walletRepo.lifetimeSpentOf('u2'), 10);
    });

    test('skips when entryFee is 0', () async {
      final result = await service.debitEntryFees(
        challenge: _challenge(entryFee: 0),
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      expect(result.success, isTrue);
      expect(result.entriesWritten, 0);
      expect(ledgerRepo.entries, isEmpty);
    });

    test('rejects participant with insufficient balance', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 100),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 5),
      );

      final result = await service.debitEntryFees(
        challenge: _challenge(entryFee: 10),
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      expect(result.success, isFalse);
      expect(result.failure, isA<InsufficientBalance>());

      // u1 was still debited successfully.
      expect(walletRepo.balanceOf('u1'), 90);
      // u2 was not debited.
      expect(walletRepo.balanceOf('u2'), 5);
    });

    test('never produces negative balance', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );

      final result = await service.debitEntryFees(
        challenge: _challenge(
          entryFee: 10,
          participants: [_p('u1')],
        ),
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      expect(result.success, isFalse);
      expect(walletRepo.balanceOf('u1'), 0);
      expect(ledgerRepo.entries, isEmpty);
    });

    test('idempotent — calling twice writes entries only once', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 100),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 100),
      );

      final challenge = _challenge(entryFee: 10);

      final first = await service.debitEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );
      expect(first.entriesWritten, 2);

      final second = await service.debitEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 3000,
      );
      expect(second.success, isTrue);
      expect(second.entriesWritten, 0);

      // Balance only debited once.
      expect(walletRepo.balanceOf('u1'), 90);
      expect(walletRepo.balanceOf('u2'), 90);
      expect(ledgerRepo.entries.length, 2);
    });

    test('ledger entries have correct reason and negative delta', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 50),
      );

      await service.debitEntryFees(
        challenge: _challenge(
          entryFee: 15,
          participants: [_p('u1')],
        ),
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      expect(ledgerRepo.entries.length, 1);
      final entry = ledgerRepo.entries.first;
      expect(entry.deltaCoins, -15);
      expect(entry.reason, LedgerReason.challengeEntryFee);
      expect(entry.refId, 'ch1');
      expect(entry.userId, 'u1');
    });
  });

  // ── TRANSFER POOL TO WINNERS ──────────────────────────────────

  group('transferPoolToWinners', () {
    test('credits full pool to single winner', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );

      final result = await service.transferPoolToWinners(
        challenge: _challenge(entryFee: 10),
        result: _result(),
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      expect(result.success, isTrue);
      expect(result.entriesWritten, 1);
      // Pool = 10 * 2 participants = 20
      expect(walletRepo.balanceOf('u1'), 20);
      expect(walletRepo.lifetimeEarnedOf('u1'), 20);
    });

    test('splits pool equally among tied winners', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 0),
      );

      final tiedResult = _result(results: [
        const ParticipantResult(
          userId: 'u1',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
        const ParticipantResult(
          userId: 'u2',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
      ]);

      final result = await service.transferPoolToWinners(
        challenge: _challenge(entryFee: 10),
        result: tiedResult,
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      expect(result.entriesWritten, 2);
      // Pool = 20, split 2 ways = 10 each.
      expect(walletRepo.balanceOf('u1'), 10);
      expect(walletRepo.balanceOf('u2'), 10);
    });

    test('remainder goes to first winner on odd split', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 0),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u3', balanceCoins: 0),
      );

      final challenge = _challenge(
        entryFee: 10,
        participants: [_p('u1'), _p('u2'), _p('u3')],
      );

      final threeWayTie = _result(results: [
        const ParticipantResult(
          userId: 'u1',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
        const ParticipantResult(
          userId: 'u2',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
        const ParticipantResult(
          userId: 'u3',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
      ]);

      await service.transferPoolToWinners(
        challenge: challenge,
        result: threeWayTie,
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      // Pool = 30, split 3 ways = 10 each, remainder 0.
      // Actually 30 / 3 = 10 exactly, no remainder.
      expect(walletRepo.balanceOf('u1'), 10);
      expect(walletRepo.balanceOf('u2'), 10);
      expect(walletRepo.balanceOf('u3'), 10);
    });

    test('odd pool remainder goes to first winner', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 0),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u3', balanceCoins: 0),
      );

      final challenge = _challenge(
        entryFee: 7,
        participants: [_p('u1'), _p('u2'), _p('u3')],
      );

      final twoWinners = _result(results: [
        const ParticipantResult(
          userId: 'u1',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
        const ParticipantResult(
          userId: 'u2',
          finalValue: 5000,
          rank: 1,
          outcome: ParticipantOutcome.tied,
          coinsEarned: 40,
        ),
        const ParticipantResult(
          userId: 'u3',
          finalValue: 3000,
          rank: 3,
          outcome: ParticipantOutcome.lost,
          coinsEarned: 0,
        ),
      ]);

      await service.transferPoolToWinners(
        challenge: challenge,
        result: twoWinners,
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      // Pool = 7 * 3 = 21. 2 winners: 21 / 2 = 10 each, remainder 1.
      // First winner gets 11, second gets 10.
      expect(walletRepo.balanceOf('u1'), 11);
      expect(walletRepo.balanceOf('u2'), 10);
    });

    test('skips when entryFee is 0', () async {
      final result = await service.transferPoolToWinners(
        challenge: _challenge(entryFee: 0),
        result: _result(),
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      expect(result.entriesWritten, 0);
      expect(ledgerRepo.entries, isEmpty);
    });

    test('skips when no winners', () async {
      final noWinnersResult = _result(results: [
        const ParticipantResult(
          userId: 'u1',
          finalValue: 0,
          rank: 1,
          outcome: ParticipantOutcome.participated,
          coinsEarned: 0,
        ),
      ]);

      final result = await service.transferPoolToWinners(
        challenge: _challenge(entryFee: 10),
        result: noWinnersResult,
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      expect(result.entriesWritten, 0);
    });

    test('idempotent — calling twice credits pool only once', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );

      final challenge = _challenge(entryFee: 10);
      final res = _result();

      await service.transferPoolToWinners(
        challenge: challenge,
        result: res,
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      await service.transferPoolToWinners(
        challenge: challenge,
        result: res,
        uuidGenerator: uuidGen,
        nowMs: 6000,
      );

      expect(walletRepo.balanceOf('u1'), 20);
      expect(
        ledgerRepo.entries
            .where((e) => e.reason == LedgerReason.challengePoolWon)
            .length,
        1,
      );
    });

    test('ledger entry has correct reason and positive delta', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 0),
      );

      await service.transferPoolToWinners(
        challenge: _challenge(entryFee: 10),
        result: _result(),
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      final poolEntries = ledgerRepo.entries
          .where((e) => e.reason == LedgerReason.challengePoolWon)
          .toList();
      expect(poolEntries.length, 1);
      expect(poolEntries.first.deltaCoins, 20);
      expect(poolEntries.first.refId, 'ch1');
    });
  });

  // ── REFUND ENTRY FEES ─────────────────────────────────────────

  group('refundEntryFees', () {
    test('refunds all debited participants', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 100),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 100),
      );

      final challenge = _challenge(entryFee: 10);

      await service.debitEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );
      expect(walletRepo.balanceOf('u1'), 90);
      expect(walletRepo.balanceOf('u2'), 90);

      final result = await service.refundEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 3000,
      );

      expect(result.success, isTrue);
      expect(result.entriesWritten, 2);
      expect(walletRepo.balanceOf('u1'), 100);
      expect(walletRepo.balanceOf('u2'), 100);
    });

    test('idempotent — refund only happens once', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 100),
      );
      final challenge = _challenge(entryFee: 10, participants: [_p('u1')]);

      await service.debitEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );

      await service.refundEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 3000,
      );

      await service.refundEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 4000,
      );

      expect(walletRepo.balanceOf('u1'), 100);
      expect(
        ledgerRepo.entries
            .where((e) => e.reason == LedgerReason.challengeEntryRefund)
            .length,
        1,
      );
    });

    test('skips when entryFee is 0', () async {
      final result = await service.refundEntryFees(
        challenge: _challenge(entryFee: 0),
        uuidGenerator: uuidGen,
        nowMs: 3000,
      );

      expect(result.entriesWritten, 0);
    });

    test('skips users who were never debited', () async {
      final result = await service.refundEntryFees(
        challenge: _challenge(entryFee: 10),
        uuidGenerator: uuidGen,
        nowMs: 3000,
      );

      expect(result.entriesWritten, 0);
      expect(ledgerRepo.entries, isEmpty);
    });
  });

  // ── FULL FLOW ─────────────────────────────────────────────────

  group('full flow: debit → pool → settle', () {
    test('debit fees then transfer pool to winner', () async {
      await walletRepo.save(
        const WalletEntity(userId: 'u1', balanceCoins: 50),
      );
      await walletRepo.save(
        const WalletEntity(userId: 'u2', balanceCoins: 50),
      );

      final challenge = _challenge(entryFee: 10);

      // 1. Debit entry fees.
      await service.debitEntryFees(
        challenge: challenge,
        uuidGenerator: uuidGen,
        nowMs: 2000,
      );
      expect(walletRepo.balanceOf('u1'), 40);
      expect(walletRepo.balanceOf('u2'), 40);

      // 2. Transfer pool to winner (u1).
      await service.transferPoolToWinners(
        challenge: challenge,
        result: _result(),
        uuidGenerator: uuidGen,
        nowMs: 5000,
      );

      // u1 paid 10, received 20 pool → net +10 → 50+10=60... wait:
      // start=50, -10=40, +20=60
      expect(walletRepo.balanceOf('u1'), 60);
      // u2 paid 10 → 40
      expect(walletRepo.balanceOf('u2'), 40);

      // 3. Verify ledger has 3 entries total.
      expect(ledgerRepo.entries.length, 3);
    });
  });
}
