import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/usecases/progression/create_daily_missions.dart';

class _FakeMissionProgressRepo implements IMissionProgressRepo {
  final List<MissionProgressEntity> _stored = [];
  @override Future<List<MissionProgressEntity>> getActiveByUserId(String u) async =>
      _stored.where((p) => p.userId == u && p.status == MissionProgressStatus.active).toList();
  @override Future<void> save(MissionProgressEntity p) async => _stored.add(p);
  @override Future<List<MissionProgressEntity>> getByUserId(String u) async => _stored;
  @override Future<MissionProgressEntity?> getById(String id) async => null;
  @override Future<MissionProgressEntity?> getByUserAndMission(String u, String m) async => null;
}

void main() {
  late _FakeMissionProgressRepo repo;
  late CreateDailyMissions usecase;
  int seq = 0;

  setUp(() {
    seq = 0;
    repo = _FakeMissionProgressRepo();
    usecase = CreateDailyMissions(progressRepo: repo);
  });

  test('creates 2 daily + 2 weekly missions for new user', () async {
    final missions = await usecase.call(
      userId: 'u1', uuidGenerator: () => 'id-${seq++}', nowMs: 1000,
    );
    final daily = missions.where((m) => m.missionId.startsWith('tpl_daily_')).length;
    final weekly = missions.where((m) => m.missionId.startsWith('tpl_weekly_')).length;
    expect(daily, 2);
    expect(weekly, 2);
  });

  test('does not duplicate existing active missions', () async {
    await usecase.call(userId: 'u1', uuidGenerator: () => 'id-${seq++}', nowMs: 1000);
    final second = await usecase.call(userId: 'u1', uuidGenerator: () => 'id-${seq++}', nowMs: 1000);
    expect(second, isEmpty);
  });
}
