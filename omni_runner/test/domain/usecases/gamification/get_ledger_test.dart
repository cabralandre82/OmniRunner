import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/get_ledger.dart';

class _FakeLedgerRepo implements ILedgerRepo {
  List<LedgerEntryEntity> entries = [];
  @override
  Future<List<LedgerEntryEntity>> getByUserId(String u) async => entries;
  @override
  Future<void> append(LedgerEntryEntity e) async {}
  @override
  Future<List<LedgerEntryEntity>> getByRefId(String r) async => [];
  @override
  Future<int> countCreditsToday(String u) async => 0;
  @override
  Future<int> sumByUserId(String u) async => 0;
}

LedgerEntryEntity _entry(LedgerReason reason, int delta) => LedgerEntryEntity(
      id: 'e-${reason.name}',
      userId: 'u1',
      deltaCoins: delta,
      reason: reason,
      createdAtMs: 0,
    );

void main() {
  late _FakeLedgerRepo repo;
  late GetLedger usecase;

  setUp(() {
    repo = _FakeLedgerRepo();
    usecase = GetLedger(ledgerRepo: repo);
  });

  test('returns all entries when no filter', () async {
    repo.entries = [
      _entry(LedgerReason.challengePoolWon, 50),
      _entry(LedgerReason.challengeEntryFee, -10),
    ];
    final result = await usecase.call(userId: 'u1');
    expect(result, hasLength(2));
  });

  test('filters by reason', () async {
    repo.entries = [
      _entry(LedgerReason.challengePoolWon, 50),
      _entry(LedgerReason.challengeEntryFee, -10),
    ];
    final result = await usecase.call(userId: 'u1', reason: LedgerReason.challengePoolWon);
    expect(result, hasLength(1));
    expect(result.first.reason, LedgerReason.challengePoolWon);
  });
}
