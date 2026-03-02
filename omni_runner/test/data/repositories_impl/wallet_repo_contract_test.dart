import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/domain/repositories/i_wallet_repo.dart';

final class InMemoryWalletRepo implements IWalletRepo {
  final _store = <String, WalletEntity>{};

  @override
  Future<WalletEntity> getByUserId(String userId) async {
    if (_store.containsKey(userId)) return _store[userId]!;
    final fresh = WalletEntity(userId: userId);
    await save(fresh);
    return fresh;
  }

  @override
  Future<void> save(WalletEntity wallet) async {
    _store[wallet.userId] = wallet;
  }
}

void main() {
  late InMemoryWalletRepo repo;

  setUp(() => repo = InMemoryWalletRepo());

  group('IWalletRepo contract', () {
    test('getByUserId auto-creates zero-balance wallet', () async {
      final w = await repo.getByUserId('u1');
      expect(w.userId, 'u1');
      expect(w.balanceCoins, 0);
      expect(w.pendingCoins, 0);
      expect(w.lifetimeEarnedCoins, 0);
      expect(w.lifetimeSpentCoins, 0);
    });

    test('save and retrieve preserves all fields', () async {
      const wallet = WalletEntity(
        userId: 'u1',
        balanceCoins: 500,
        pendingCoins: 50,
        lifetimeEarnedCoins: 1000,
        lifetimeSpentCoins: 450,
        lastReconciledAtMs: 9999,
      );

      await repo.save(wallet);
      final found = await repo.getByUserId('u1');
      expect(found, equals(wallet));
    });

    test('save overwrites existing wallet', () async {
      await repo.save(const WalletEntity(userId: 'u1', balanceCoins: 100));
      await repo.save(const WalletEntity(userId: 'u1', balanceCoins: 200));

      final w = await repo.getByUserId('u1');
      expect(w.balanceCoins, 200);
    });

    test('wallets are isolated per user', () async {
      await repo.save(const WalletEntity(userId: 'u1', balanceCoins: 100));
      await repo.save(const WalletEntity(userId: 'u2', balanceCoins: 200));

      expect((await repo.getByUserId('u1')).balanceCoins, 100);
      expect((await repo.getByUserId('u2')).balanceCoins, 200);
    });

    test('WalletEntity.canAfford uses balanceCoins only', () {
      const w = WalletEntity(
        userId: 'u1',
        balanceCoins: 50,
        pendingCoins: 100,
      );

      expect(w.canAfford(50), isTrue);
      expect(w.canAfford(51), isFalse);
      expect(w.totalCoins, 150);
    });

    test('WalletEntity.copyWith works correctly', () {
      const original = WalletEntity(userId: 'u1', balanceCoins: 100);
      final updated = original.copyWith(balanceCoins: 80, lifetimeSpentCoins: 20);

      expect(updated.balanceCoins, 80);
      expect(updated.lifetimeSpentCoins, 20);
      expect(updated.userId, 'u1');
    });
  });
}
