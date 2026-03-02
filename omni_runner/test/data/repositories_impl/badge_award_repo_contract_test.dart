import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/repositories/i_badge_award_repo.dart';

final class InMemoryBadgeAwardRepo implements IBadgeAwardRepo {
  final _store = <String, BadgeAwardEntity>{};

  @override
  Future<void> save(BadgeAwardEntity award) async {
    _store[award.id] = award;
  }

  @override
  Future<List<BadgeAwardEntity>> getByUserId(String userId) async {
    return _store.values
        .where((a) => a.userId == userId)
        .toList()
      ..sort((a, b) => b.unlockedAtMs.compareTo(a.unlockedAtMs));
  }

  @override
  Future<bool> isUnlocked(String userId, String badgeId) async {
    return _store.values
        .any((a) => a.userId == userId && a.badgeId == badgeId);
  }
}

BadgeAwardEntity _award({
  String id = 'ba1',
  String userId = 'u1',
  String badgeId = 'badge-5k',
  int unlockedAtMs = 1000,
  int xpAwarded = 50,
}) =>
    BadgeAwardEntity(
      id: id,
      userId: userId,
      badgeId: badgeId,
      unlockedAtMs: unlockedAtMs,
      xpAwarded: xpAwarded,
    );

void main() {
  late InMemoryBadgeAwardRepo repo;

  setUp(() => repo = InMemoryBadgeAwardRepo());

  group('IBadgeAwardRepo contract', () {
    test('save and getByUserId round-trip', () async {
      await repo.save(_award());
      final awards = await repo.getByUserId('u1');
      expect(awards.length, 1);
      expect(awards.first.badgeId, 'badge-5k');
    });

    test('getByUserId returns newest first', () async {
      await repo.save(_award(id: 'a', unlockedAtMs: 100));
      await repo.save(_award(id: 'b', unlockedAtMs: 300));
      await repo.save(_award(id: 'c', unlockedAtMs: 200));

      final awards = await repo.getByUserId('u1');
      expect(awards.map((a) => a.id).toList(), ['b', 'c', 'a']);
    });

    test('getByUserId isolates users', () async {
      await repo.save(_award(id: 'a', userId: 'u1'));
      await repo.save(_award(id: 'b', userId: 'u2'));

      expect((await repo.getByUserId('u1')).length, 1);
      expect((await repo.getByUserId('u2')).length, 1);
    });

    test('isUnlocked returns true for existing badge', () async {
      await repo.save(_award(badgeId: 'badge-5k'));
      expect(await repo.isUnlocked('u1', 'badge-5k'), isTrue);
    });

    test('isUnlocked returns false for missing badge', () async {
      expect(await repo.isUnlocked('u1', 'badge-5k'), isFalse);
    });

    test('isUnlocked is user-scoped', () async {
      await repo.save(_award(userId: 'u1', badgeId: 'badge-5k'));
      expect(await repo.isUnlocked('u2', 'badge-5k'), isFalse);
    });
  });
}
