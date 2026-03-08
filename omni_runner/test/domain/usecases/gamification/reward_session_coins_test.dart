import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';
import 'package:omni_runner/domain/usecases/gamification/reward_session_coins.dart';

class _FakeLedger implements ILedgerRepo {
  @override Future<void> append(LedgerEntryEntity e) async {}
  @override Future<List<LedgerEntryEntity>> getByUserId(String u) async => [];
  @override Future<List<LedgerEntryEntity>> getByRefId(String r) async => [];
  @override Future<int> countCreditsToday(String u) async => 0;
  @override Future<int> sumByUserId(String u) async => 0;
}

class _FakeWallet implements IWalletRepo {
  @override Future<WalletEntity> getByUserId(String u) async => WalletEntity(userId: u);
  @override Future<void> save(WalletEntity w) async {}
}

void main() {
  test('always returns 0 coins (deprecated use case)', () async {
    final usecase = RewardSessionCoins(ledgerRepo: _FakeLedger(), walletRepo: _FakeWallet());
    const session = WorkoutSessionEntity(
      id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
      startTimeMs: 0, route: [],
    );
    final result = await usecase.call(session: session, uuidGenerator: () => 'id', nowMs: 1000);
    expect(result.rewarded, isTrue);
    expect(result.coinsAwarded, 0);
  });
}
