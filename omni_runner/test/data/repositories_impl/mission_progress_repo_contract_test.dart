import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';

final class InMemoryMissionProgressRepo implements IMissionProgressRepo {
  final _store = <String, MissionProgressEntity>{};

  @override
  Future<void> save(MissionProgressEntity progress) async {
    _store[progress.id] = progress;
  }

  @override
  Future<List<MissionProgressEntity>> getByUserId(String userId) async {
    return _store.values.where((p) => p.userId == userId).toList();
  }

  @override
  Future<List<MissionProgressEntity>> getActiveByUserId(String userId) async {
    return _store.values
        .where((p) =>
            p.userId == userId && p.status == MissionProgressStatus.active)
        .toList();
  }

  @override
  Future<MissionProgressEntity?> getById(String id) async => _store[id];

  @override
  Future<MissionProgressEntity?> getByUserAndMission(
    String userId,
    String missionId,
  ) async {
    return _store.values
        .where((p) =>
            p.userId == userId &&
            p.missionId == missionId &&
            p.status == MissionProgressStatus.active)
        .firstOrNull;
  }
}

MissionProgressEntity _progress({
  String id = 'mp1',
  String userId = 'u1',
  String missionId = 'm1',
  MissionProgressStatus status = MissionProgressStatus.active,
  double currentValue = 0.0,
  double targetValue = 5000.0,
}) =>
    MissionProgressEntity(
      id: id,
      userId: userId,
      missionId: missionId,
      status: status,
      currentValue: currentValue,
      targetValue: targetValue,
      assignedAtMs: 1000,
    );

void main() {
  late InMemoryMissionProgressRepo repo;

  setUp(() => repo = InMemoryMissionProgressRepo());

  group('IMissionProgressRepo contract', () {
    test('save and getById round-trip', () async {
      final p = _progress();
      await repo.save(p);
      expect(await repo.getById('mp1'), equals(p));
    });

    test('getById returns null for missing', () async {
      expect(await repo.getById('nope'), isNull);
    });

    test('getByUserId returns all for user', () async {
      await repo.save(_progress(id: 'a', userId: 'u1'));
      await repo.save(_progress(id: 'b', userId: 'u1'));
      await repo.save(_progress(id: 'c', userId: 'u2'));

      expect((await repo.getByUserId('u1')).length, 2);
      expect((await repo.getByUserId('u2')).length, 1);
    });

    test('getActiveByUserId filters by active status', () async {
      await repo.save(_progress(
        id: 'a',
        status: MissionProgressStatus.active,
      ));
      await repo.save(_progress(
        id: 'b',
        status: MissionProgressStatus.completed,
      ));
      await repo.save(_progress(
        id: 'c',
        status: MissionProgressStatus.expired,
      ));

      final active = await repo.getActiveByUserId('u1');
      expect(active.length, 1);
      expect(active.first.id, 'a');
    });

    test('getByUserAndMission finds active match', () async {
      await repo.save(_progress(id: 'a', missionId: 'm1'));
      await repo.save(_progress(
        id: 'b',
        missionId: 'm1',
        status: MissionProgressStatus.completed,
      ));

      final found = await repo.getByUserAndMission('u1', 'm1');
      expect(found, isNotNull);
      expect(found!.id, 'a');
    });

    test('getByUserAndMission returns null when no active match', () async {
      await repo.save(_progress(
        missionId: 'm1',
        status: MissionProgressStatus.completed,
      ));

      expect(await repo.getByUserAndMission('u1', 'm1'), isNull);
    });

    test('progressFraction computes correctly', () {
      final p = _progress(currentValue: 2500, targetValue: 5000);
      expect(p.progressFraction, 0.5);
    });

    test('progressFraction clamps to 1.0', () {
      final p = _progress(currentValue: 6000, targetValue: 5000);
      expect(p.progressFraction, 1.0);
    });

    test('isCriteriaMet returns true when target reached', () {
      expect(_progress(currentValue: 5000, targetValue: 5000).isCriteriaMet, isTrue);
      expect(_progress(currentValue: 4999, targetValue: 5000).isCriteriaMet, isFalse);
    });
  });
}
