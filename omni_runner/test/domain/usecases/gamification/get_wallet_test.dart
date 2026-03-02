import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/get_wallet.dart';

class _FakeWalletRepo implements IWalletRepo {
  WalletEntity _wallet = const WalletEntity(userId: 'u1', balanceCoins: 100);
  WalletEntity? saved;

  @override
  Future<WalletEntity> getByUserId(String u) async => _wallet;
  @override
  Future<void> save(WalletEntity w) async {
    _wallet = w;
    saved = w;
  }
}

class _FakeLedgerRepo implements ILedgerRepo {
  int ledgerSum = 100;

  @override
  Future<int> sumByUserId(String userId) async => ledgerSum;
  @override
  Future<void> append(LedgerEntryEntity entry) async {}
  @override
  Future<List<LedgerEntryEntity>> getByUserId(String userId) async => [];
  @override
  Future<List<LedgerEntryEntity>> getByRefId(String refId) async => [];
  @override
  Future<int> countCreditsToday(String userId) async => 0;
}

void main() {
  late _FakeWalletRepo walletRepo;
  late _FakeLedgerRepo ledgerRepo;
  late GetWallet usecase;

  setUp(() {
    walletRepo = _FakeWalletRepo();
    ledgerRepo = _FakeLedgerRepo();
    usecase = GetWallet(walletRepo: walletRepo, ledgerRepo: ledgerRepo);
  });

  test('returns wallet without reconciliation', () async {
    final wallet = await usecase.call(userId: 'u1');

    expect(wallet.balanceCoins, 100);
    expect(walletRepo.saved, isNull);
  });

  test('skips reconciliation when balance matches ledger', () async {
    ledgerRepo.ledgerSum = 100;

    final wallet = await usecase.call(userId: 'u1', reconcile: true);

    expect(wallet.balanceCoins, 100);
    expect(walletRepo.saved, isNull);
  });

  test('corrects balance when ledger differs', () async {
    ledgerRepo.ledgerSum = 150;

    final wallet = await usecase.call(userId: 'u1', reconcile: true);

    expect(wallet.balanceCoins, 150);
    expect(walletRepo.saved, isNotNull);
    expect(walletRepo.saved!.lastReconciledAtMs, isNotNull);
  });
}
