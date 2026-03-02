import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/repositories/i_ledger_repo.dart';

final class InMemoryLedgerRepo implements ILedgerRepo {
  final _entries = <LedgerEntryEntity>[];

  @override
  Future<void> append(LedgerEntryEntity entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.add(entry);
  }

  @override
  Future<List<LedgerEntryEntity>> getByUserId(String userId) async {
    return _entries
        .where((e) => e.userId == userId)
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  @override
  Future<List<LedgerEntryEntity>> getByRefId(String refId) async {
    return _entries.where((e) => e.refId == refId).toList();
  }

  @override
  Future<int> countCreditsToday(String userId) async {
    final now = DateTime.now().toUtc();
    final startMs =
        DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch;
    return _entries
        .where((e) =>
            e.userId == userId &&
            e.reason == LedgerReason.sessionCompleted &&
            e.createdAtMs >= startMs)
        .length;
  }

  @override
  Future<int> sumByUserId(String userId) async {
    var sum = 0;
    for (final e in _entries) {
      if (e.userId == userId) sum += e.deltaCoins;
    }
    return sum;
  }
}

LedgerEntryEntity _entry({
  String id = 'e1',
  String userId = 'u1',
  int deltaCoins = 10,
  LedgerReason reason = LedgerReason.adminAdjustment,
  String? refId,
  int createdAtMs = 1000,
}) =>
    LedgerEntryEntity(
      id: id,
      userId: userId,
      deltaCoins: deltaCoins,
      reason: reason,
      refId: refId,
      createdAtMs: createdAtMs,
    );

void main() {
  late InMemoryLedgerRepo repo;

  setUp(() => repo = InMemoryLedgerRepo());

  group('ILedgerRepo contract', () {
    test('append and getByUserId round-trip', () async {
      await repo.append(_entry());
      final entries = await repo.getByUserId('u1');
      expect(entries.length, 1);
      expect(entries.first.deltaCoins, 10);
    });

    test('getByUserId returns newest first', () async {
      await repo.append(_entry(id: 'a', createdAtMs: 100));
      await repo.append(_entry(id: 'b', createdAtMs: 300));
      await repo.append(_entry(id: 'c', createdAtMs: 200));

      final entries = await repo.getByUserId('u1');
      expect(entries.map((e) => e.id).toList(), ['b', 'c', 'a']);
    });

    test('getByUserId isolates users', () async {
      await repo.append(_entry(id: 'a', userId: 'u1'));
      await repo.append(_entry(id: 'b', userId: 'u2'));

      expect((await repo.getByUserId('u1')).length, 1);
      expect((await repo.getByUserId('u2')).length, 1);
    });

    test('getByRefId filters by reference', () async {
      await repo.append(_entry(id: 'a', refId: 'session-1'));
      await repo.append(_entry(id: 'b', refId: 'session-2'));
      await repo.append(_entry(id: 'c', refId: 'session-1'));

      final refs = await repo.getByRefId('session-1');
      expect(refs.length, 2);
    });

    test('sumByUserId computes net balance', () async {
      await repo.append(_entry(id: 'a', deltaCoins: 100));
      await repo.append(_entry(id: 'b', deltaCoins: -30));
      await repo.append(_entry(id: 'c', deltaCoins: 50));

      expect(await repo.sumByUserId('u1'), 120);
    });

    test('sumByUserId returns 0 for unknown user', () async {
      expect(await repo.sumByUserId('ghost'), 0);
    });

    test('append deduplicates by id', () async {
      await repo.append(_entry(id: 'same', deltaCoins: 10));
      await repo.append(_entry(id: 'same', deltaCoins: 20));

      final entries = await repo.getByUserId('u1');
      expect(entries.length, 1);
      expect(entries.first.deltaCoins, 20);
    });

    test('countCreditsToday counts sessionCompleted entries', () async {
      final todayMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      await repo.append(_entry(
        id: 'today1',
        reason: LedgerReason.sessionCompleted,
        createdAtMs: todayMs,
      ));
      await repo.append(_entry(
        id: 'today2',
        reason: LedgerReason.sessionCompleted,
        createdAtMs: todayMs - 1000,
      ));
      await repo.append(_entry(
        id: 'other',
        reason: LedgerReason.adminAdjustment,
        createdAtMs: todayMs,
      ));

      final count = await repo.countCreditsToday('u1');
      expect(count, 2);
    });
  });
}
