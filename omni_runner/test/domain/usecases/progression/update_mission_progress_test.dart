import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/entities/profile_progress_entity.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/usecases/progression/update_mission_progress.dart';

class _FakeRepo implements IMissionProgressRepo {
  List<MissionProgressEntity> active = [];
  final Map<String, MissionProgressEntity> _saved = {};

  @override Future<List<MissionProgressEntity>> getActiveByUserId(String u) async => active;
  @override Future<void> save(MissionProgressEntity p) async => _saved[p.id] = p;
  @override Future<List<MissionProgressEntity>> getByUserId(String u) async => _saved.values.toList();
  @override Future<MissionProgressEntity?> getById(String id) async => _saved[id];
  @override Future<MissionProgressEntity?> getByUserAndMission(String u, String m) async => null;
}

void main() {
  late _FakeRepo repo;
  late UpdateMissionProgress usecase;
  const session = WorkoutSessionEntity(
    id: 'ses-1', userId: 'u1', status: WorkoutStatus.completed,
    startTimeMs: 0, route: [], isVerified: true,
  );

  const profile = ProfileProgressEntity(userId: 'u1');

  setUp(() {
    repo = _FakeRepo();
    usecase = UpdateMissionProgress(progressRepo: repo);
  });

  test('returns empty when no active progress', () async {
    final result = await usecase.call(
      session: session, sessionDistanceM: 5000, sessionMovingMs: 1800000,
      sessionPaceSecPerKm: 360, profile: profile,
      activeMissionDefs: [], nowMs: 1000,
    );
    expect(result.updated, isEmpty);
    expect(result.completed, isEmpty);
  });

  test('updates distance mission progress', () async {
    repo.active = [
      const MissionProgressEntity(
        id: 'mp1', userId: 'u1', missionId: 'tpl_daily_3km',
        status: MissionProgressStatus.active, currentValue: 0,
        targetValue: 3000, assignedAtMs: 0,
      ),
    ];

    final result = await usecase.call(
      session: session, sessionDistanceM: 5000, sessionMovingMs: 1800000,
      sessionPaceSecPerKm: 360, profile: profile,
      activeMissionDefs: [
        const MissionEntity(
          id: 'tpl_daily_3km', title: '3K', description: 'd',
          difficulty: MissionDifficulty.easy, slot: MissionSlot.daily,
          xpReward: 30, coinsReward: 5, criteria: AccumulateDistance(3000),
        ),
      ],
      nowMs: 1000,
    );
    expect(result.completed, hasLength(1));
  });

  test('returns empty when no userId on session', () async {
    const noUser = WorkoutSessionEntity(
      id: 'ses-2', status: WorkoutStatus.completed,
      startTimeMs: 0, route: [], isVerified: true,
    );
    final result = await usecase.call(
      session: noUser, sessionDistanceM: 5000, sessionMovingMs: 1800000,
      sessionPaceSecPerKm: 360, profile: profile,
      activeMissionDefs: [], nowMs: 1000,
    );
    expect(result.updated, isEmpty);
  });
}
