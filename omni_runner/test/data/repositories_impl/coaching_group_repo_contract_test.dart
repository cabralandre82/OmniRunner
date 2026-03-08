import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';

final class InMemoryCoachingGroupRepo implements ICoachingGroupRepo {
  final _store = <String, CoachingGroupEntity>{};

  @override
  Future<void> save(CoachingGroupEntity group) async {
    _store[group.id] = group;
  }

  @override
  Future<void> update(CoachingGroupEntity group) async {
    _store[group.id] = group;
  }

  @override
  Future<CoachingGroupEntity?> getById(String id) async => _store[id];

  @override
  Future<List<CoachingGroupEntity>> getByCoachUserId(
    String coachUserId,
  ) async {
    return _store.values
        .where((g) => g.coachUserId == coachUserId)
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  @override
  Future<int> countByCoachUserId(String coachUserId) async {
    return _store.values
        .where((g) => g.coachUserId == coachUserId)
        .length;
  }

  @override
  Future<void> deleteById(String id) async {
    _store.remove(id);
  }
}

CoachingGroupEntity _group({
  String id = 'g1',
  String coachUserId = 'coach1',
  int createdAtMs = 1000,
}) =>
    CoachingGroupEntity(
      id: id,
      name: 'Group $id',
      coachUserId: coachUserId,
      createdAtMs: createdAtMs,
    );

void main() {
  late InMemoryCoachingGroupRepo repo;

  setUp(() => repo = InMemoryCoachingGroupRepo());

  group('ICoachingGroupRepo contract', () {
    test('save and getById round-trip', () async {
      final g = _group();
      await repo.save(g);
      expect(await repo.getById('g1'), equals(g));
    });

    test('getById returns null for missing', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('getByCoachUserId returns groups for coach', () async {
      await repo.save(_group(id: 'g1', coachUserId: 'c1'));
      await repo.save(_group(id: 'g2', coachUserId: 'c1'));
      await repo.save(_group(id: 'g3', coachUserId: 'c2'));

      final groups = await repo.getByCoachUserId('c1');
      expect(groups.length, 2);
      expect(groups.map((g) => g.id).toSet(), {'g1', 'g2'});
    });

    test('countByCoachUserId returns correct count', () async {
      await repo.save(_group(id: 'g1', coachUserId: 'c1'));
      await repo.save(_group(id: 'g2', coachUserId: 'c1'));
      await repo.save(_group(id: 'g3', coachUserId: 'c2'));

      expect(await repo.countByCoachUserId('c1'), 2);
      expect(await repo.countByCoachUserId('c2'), 1);
      expect(await repo.countByCoachUserId('nobody'), 0);
    });

    test('update replaces group data', () async {
      await repo.save(_group());
      final updated = _group().copyWith(name: 'Renamed');
      await repo.update(updated);

      final g = await repo.getById('g1');
      expect(g!.name, 'Renamed');
    });

    test('deleteById removes group', () async {
      await repo.save(_group());
      await repo.deleteById('g1');
      expect(await repo.getById('g1'), isNull);
    });

    test('CoachingGroupEntity.inviteLink builds URL from code', () {
      const g = CoachingGroupEntity(
        id: 'g1',
        name: 'Test',
        coachUserId: 'c1',
        createdAtMs: 1000,
        inviteCode: 'ABC123',
      );
      expect(g.inviteLink, 'https://omnirunner.app/invite/ABC123');
    });

    test('CoachingGroupEntity.inviteLink is null without code', () {
      expect(_group().inviteLink, isNull);
    });
  });
}
