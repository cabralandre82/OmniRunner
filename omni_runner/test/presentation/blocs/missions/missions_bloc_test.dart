import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/domain/entities/mission_entity.dart';
import 'package:omni_runner/domain/entities/mission_progress_entity.dart';
import 'package:omni_runner/domain/repositories/i_mission_progress_repo.dart';
import 'package:omni_runner/domain/repositories/i_missions_remote_source.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_bloc.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_event.dart';
import 'package:omni_runner/presentation/blocs/missions/missions_state.dart';

class MockMissionProgressRepo extends Mock implements IMissionProgressRepo {}

class MockMissionsRemoteSource extends Mock implements IMissionsRemoteSource {}

const _userId = 'user-1';

const _activeMission = MissionProgressEntity(
  id: 'mp-1',
  userId: _userId,
  missionId: 'mission-1',
  status: MissionProgressStatus.active,
  currentValue: 3000,
  targetValue: 10000,
  assignedAtMs: 1000000,
);

const _completedMission = MissionProgressEntity(
  id: 'mp-2',
  userId: _userId,
  missionId: 'mission-2',
  status: MissionProgressStatus.completed,
  currentValue: 5000,
  targetValue: 5000,
  assignedAtMs: 500000,
  completedAtMs: 1500000,
  completionCount: 1,
);

Future<List<MissionsState>> _collectStates(
  MissionsBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <MissionsState>[];
  final completer = Completer<void>();
  final sub = bloc.stream.listen((s) {
    states.add(s);
    if (states.length >= count && !completer.isCompleted) {
      completer.complete();
    }
  });
  await completer.future.timeout(timeout, onTimeout: () {});
  await sub.cancel();
  return states;
}

void main() {
  late MockMissionProgressRepo progressRepo;
  late MockMissionsRemoteSource remote;

  setUpAll(() {
    registerFallbackValue(const MissionProgressEntity(
      id: '',
      userId: '',
      missionId: '',
      status: MissionProgressStatus.active,
      currentValue: 0,
      targetValue: 0,
      assignedAtMs: 0,
    ));
  });

  setUp(() {
    progressRepo = MockMissionProgressRepo();
    remote = MockMissionsRemoteSource();

    // Default: remote returns empty (offline fallback)
    when(() => remote.fetchMissionDefs()).thenAnswer((_) async => []);
    when(() => remote.fetchProgress(any())).thenAnswer((_) async => []);
  });

  MissionsBloc buildBloc() => MissionsBloc(
        progressRepo: progressRepo,
        remote: remote,
      );

  group('MissionsBloc', () {
    test('initial state is MissionsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const MissionsInitial());
      bloc.close();
    });

    group('LoadMissions', () {
      test('emits [Loading, Loaded] splitting active/completed', () async {
        when(() => progressRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_activeMission, _completedMission]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadMissions(_userId));
        final states = await future;

        expect(states[0], isA<MissionsLoading>());
        expect(states[1], isA<MissionsLoaded>());
        final loaded = states[1] as MissionsLoaded;
        expect(loaded.active.length, 1);
        expect(loaded.completed.length, 1);
        expect(loaded.missionDefs, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Loaded] with empty missions', () async {
        when(() => progressRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadMissions(_userId));
        final states = await future;

        final loaded = states[1] as MissionsLoaded;
        expect(loaded.active, isEmpty);
        expect(loaded.completed, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => progressRepo.getByUserId(_userId))
            .thenThrow(Exception('db'));

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadMissions(_userId));
        final states = await future;

        expect(states[0], isA<MissionsLoading>());
        expect(states[1], isA<MissionsError>());
        await bloc.close();
      });
    });

    group('RefreshMissions', () {
      test('does nothing when userId not set', () async {
        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1,
            timeout: const Duration(milliseconds: 200));
        bloc.add(const RefreshMissions());
        final states = await future;

        expect(states, isEmpty);
        await bloc.close();
      });
    });

    group('Remote sync', () {
      test('syncs remote defs and progress to local repo', () async {
        const missionDef = MissionEntity(
          id: 'mission-1',
          title: 'Run 10km',
          description: 'Accumulate 10km this week',
          difficulty: MissionDifficulty.medium,
          slot: MissionSlot.weekly,
          xpReward: 200,
          coinsReward: 0,
          criteria: AccumulateDistance(10000),
        );

        when(() => remote.fetchMissionDefs())
            .thenAnswer((_) async => [missionDef]);
        when(() => remote.fetchProgress(_userId))
            .thenAnswer((_) async => [_activeMission]);
        when(() => progressRepo.save(any())).thenAnswer((_) async {});
        when(() => progressRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_activeMission]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadMissions(_userId));
        final states = await future;
        await bloc.close();

        verify(() => progressRepo.save(any())).called(1);
        expect(states[1], isA<MissionsLoaded>());
        final loaded = states[1] as MissionsLoaded;
        expect(loaded.missionDefs, contains('mission-1'));
        expect(loaded.missionDefs['mission-1']!.title, 'Run 10km');
        expect(loaded.active, hasLength(1));
      });

      test('works offline when remote returns empty', () async {
        when(() => remote.fetchMissionDefs()).thenAnswer((_) async => []);
        when(() => remote.fetchProgress(_userId))
            .thenAnswer((_) async => []);
        when(() => progressRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_activeMission, _completedMission]);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadMissions(_userId));
        final states = await future;
        await bloc.close();

        verifyNever(() => progressRepo.save(any()));
        final loaded = states[1] as MissionsLoaded;
        expect(loaded.active, hasLength(1));
        expect(loaded.completed, hasLength(1));
        expect(loaded.missionDefs, isEmpty);
      });
    });
  });
}
