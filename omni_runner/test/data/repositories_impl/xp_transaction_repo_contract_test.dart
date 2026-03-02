import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_xp_transaction_repo.dart';

final class InMemoryXpTransactionRepo implements IXpTransactionRepo {
  final _entries = <XpTransactionEntity>[];

  @override
  Future<void> append(XpTransactionEntity tx) async {
    _entries.removeWhere((e) => e.id == tx.id);
    _entries.add(tx);
  }

  @override
  Future<List<XpTransactionEntity>> getByUserId(String userId) async {
    return _entries
        .where((e) => e.userId == userId)
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  @override
  Future<List<XpTransactionEntity>> getByRefId(String refId) async {
    return _entries.where((e) => e.refId == refId).toList();
  }

  @override
  Future<int> sumSessionXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    var sum = 0;
    for (final e in _entries) {
      if (e.userId == userId &&
          e.source == XpSource.session &&
          e.createdAtMs >= startMs) {
        sum += e.xp;
      }
    }
    return sum;
  }

  @override
  Future<int> sumBonusXpToday(String userId) async {
    final startMs = _startOfDayUtcMs();
    var sum = 0;
    for (final e in _entries) {
      if (e.userId == userId &&
          e.source != XpSource.session &&
          e.createdAtMs >= startMs) {
        sum += e.xp;
      }
    }
    return sum;
  }

  @override
  Future<int> sumByUserId(String userId) async {
    var sum = 0;
    for (final e in _entries) {
      if (e.userId == userId) sum += e.xp;
    }
    return sum;
  }

  @override
  Future<int> sumByUserIdInRange(String userId, int fromMs, int toMs) async {
    var sum = 0;
    for (final e in _entries) {
      if (e.userId == userId &&
          e.createdAtMs >= fromMs &&
          e.createdAtMs <= toMs) {
        sum += e.xp;
      }
    }
    return sum;
  }

  static int _startOfDayUtcMs() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
  }
}

XpTransactionEntity _tx({
  String id = 'tx1',
  String userId = 'u1',
  int xp = 50,
  XpSource source = XpSource.session,
  String? refId,
  int? createdAtMs,
}) =>
    XpTransactionEntity(
      id: id,
      userId: userId,
      xp: xp,
      source: source,
      refId: refId,
      createdAtMs: createdAtMs ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );

void main() {
  late InMemoryXpTransactionRepo repo;

  setUp(() => repo = InMemoryXpTransactionRepo());

  group('IXpTransactionRepo contract', () {
    test('append and getByUserId round-trip', () async {
      await repo.append(_tx());
      final txs = await repo.getByUserId('u1');
      expect(txs.length, 1);
      expect(txs.first.xp, 50);
    });

    test('getByUserId returns newest first', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.append(_tx(id: 'a', createdAtMs: now - 200));
      await repo.append(_tx(id: 'b', createdAtMs: now));
      await repo.append(_tx(id: 'c', createdAtMs: now - 100));

      final txs = await repo.getByUserId('u1');
      expect(txs.map((t) => t.id).toList(), ['b', 'c', 'a']);
    });

    test('getByRefId filters by reference', () async {
      await repo.append(_tx(id: 'a', refId: 'session-1'));
      await repo.append(_tx(id: 'b', refId: 'badge-1'));
      await repo.append(_tx(id: 'c', refId: 'session-1'));

      final refs = await repo.getByRefId('session-1');
      expect(refs.length, 2);
    });

    test('sumByUserId computes total XP', () async {
      await repo.append(_tx(id: 'a', xp: 100));
      await repo.append(_tx(id: 'b', xp: 50));
      await repo.append(_tx(id: 'c', xp: 25));

      expect(await repo.sumByUserId('u1'), 175);
    });

    test('sumByUserId returns 0 for unknown user', () async {
      expect(await repo.sumByUserId('ghost'), 0);
    });

    test('sumSessionXpToday counts only session source', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.append(_tx(
        id: 'a',
        xp: 100,
        source: XpSource.session,
        createdAtMs: now,
      ));
      await repo.append(_tx(
        id: 'b',
        xp: 50,
        source: XpSource.badge,
        createdAtMs: now,
      ));

      expect(await repo.sumSessionXpToday('u1'), 100);
    });

    test('sumBonusXpToday excludes session source', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.append(_tx(
        id: 'a',
        xp: 100,
        source: XpSource.session,
        createdAtMs: now,
      ));
      await repo.append(_tx(
        id: 'b',
        xp: 50,
        source: XpSource.badge,
        createdAtMs: now,
      ));
      await repo.append(_tx(
        id: 'c',
        xp: 30,
        source: XpSource.mission,
        createdAtMs: now,
      ));

      expect(await repo.sumBonusXpToday('u1'), 80);
    });

    test('sumByUserIdInRange filters by date range', () async {
      await repo.append(_tx(id: 'a', xp: 100, createdAtMs: 1000));
      await repo.append(_tx(id: 'b', xp: 50, createdAtMs: 2000));
      await repo.append(_tx(id: 'c', xp: 25, createdAtMs: 3000));

      expect(await repo.sumByUserIdInRange('u1', 1500, 2500), 50);
      expect(await repo.sumByUserIdInRange('u1', 1000, 3000), 175);
    });

    test('append deduplicates by id', () async {
      await repo.append(_tx(id: 'same', xp: 10));
      await repo.append(_tx(id: 'same', xp: 20));

      expect(await repo.sumByUserId('u1'), 20);
    });
  });
}
