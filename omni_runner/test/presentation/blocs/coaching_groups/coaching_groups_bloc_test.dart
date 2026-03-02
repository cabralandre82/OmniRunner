import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_groups/coaching_groups_state.dart';

class MockCoachingGroupRepo extends Mock implements ICoachingGroupRepo {}

class MockCoachingMemberRepo extends Mock implements ICoachingMemberRepo {}

const _userId = 'user-1';

const _group = CoachingGroupEntity(
  id: 'g-1',
  name: 'Running Team',
  coachUserId: 'coach-1',
  description: 'Best team',
  city: 'São Paulo',
  createdAtMs: 1000000,
);

const _membership = CoachingMemberEntity(
  id: 'm-1',
  userId: _userId,
  groupId: 'g-1',
  displayName: 'Alice',
  role: CoachingRole.atleta,
  joinedAtMs: 2000000,
);

Future<List<CoachingGroupsState>> _collectStates(
  CoachingGroupsBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <CoachingGroupsState>[];
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
  late MockCoachingGroupRepo groupRepo;
  late MockCoachingMemberRepo memberRepo;

  setUp(() {
    groupRepo = MockCoachingGroupRepo();
    memberRepo = MockCoachingMemberRepo();
  });

  CoachingGroupsBloc buildBloc() => CoachingGroupsBloc(
        groupRepo: groupRepo,
        memberRepo: memberRepo,
      );

  group('CoachingGroupsBloc', () {
    test('initial state is CoachingGroupsInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, const CoachingGroupsInitial());
      bloc.close();
    });

    group('LoadCoachingGroups', () {
      test('emits [Loading, Loaded] with groups', () async {
        when(() => memberRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_membership]);
        when(() => groupRepo.getById('g-1'))
            .thenAnswer((_) async => _group);
        when(() => memberRepo.countByGroupId('g-1'))
            .thenAnswer((_) async => 10);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadCoachingGroups(_userId));
        final states = await future;

        expect(states[0], isA<CoachingGroupsLoading>());
        expect(states[1], isA<CoachingGroupsLoaded>());
        final loaded = states[1] as CoachingGroupsLoaded;
        expect(loaded.groups.length, 1);
        expect(loaded.groups[0].group.name, 'Running Team');
        expect(loaded.groups[0].memberCount, 10);
        expect(loaded.groups[0].membership.role, CoachingRole.atleta);
        await bloc.close();
      });

      test('emits [Loading, Loaded] with empty list when no memberships',
          () async {
        when(() => memberRepo.getByUserId(_userId))
            .thenAnswer((_) async => []);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadCoachingGroups(_userId));
        final states = await future;

        expect(states[1], isA<CoachingGroupsLoaded>());
        final loaded = states[1] as CoachingGroupsLoaded;
        expect(loaded.groups, isEmpty);
        await bloc.close();
      });

      test('skips membership when group is not found', () async {
        when(() => memberRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_membership]);
        when(() => groupRepo.getById('g-1'))
            .thenAnswer((_) async => null);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadCoachingGroups(_userId));
        final states = await future;

        final loaded = states[1] as CoachingGroupsLoaded;
        expect(loaded.groups, isEmpty);
        await bloc.close();
      });

      test('emits [Loading, Error] on exception', () async {
        when(() => memberRepo.getByUserId(_userId))
            .thenThrow(Exception('db crash'));

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadCoachingGroups(_userId));
        final states = await future;

        expect(states[0], isA<CoachingGroupsLoading>());
        expect(states[1], isA<CoachingGroupsError>());
        await bloc.close();
      });

      test('handles multiple groups', () async {
        const membership2 = CoachingMemberEntity(
          id: 'm-2',
          userId: _userId,
          groupId: 'g-2',
          displayName: 'Alice',
          role: CoachingRole.assistente,
          joinedAtMs: 3000000,
        );
        const group2 = CoachingGroupEntity(
          id: 'g-2',
          name: 'Speed Runners',
          coachUserId: 'coach-2',
          createdAtMs: 1500000,
        );
        when(() => memberRepo.getByUserId(_userId))
            .thenAnswer((_) async => [_membership, membership2]);
        when(() => groupRepo.getById('g-1'))
            .thenAnswer((_) async => _group);
        when(() => groupRepo.getById('g-2'))
            .thenAnswer((_) async => group2);
        when(() => memberRepo.countByGroupId('g-1'))
            .thenAnswer((_) async => 10);
        when(() => memberRepo.countByGroupId('g-2'))
            .thenAnswer((_) async => 5);

        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 2);
        bloc.add(const LoadCoachingGroups(_userId));
        final states = await future;

        final loaded = states[1] as CoachingGroupsLoaded;
        expect(loaded.groups.length, 2);
        await bloc.close();
      });
    });

    group('RefreshCoachingGroups', () {
      test('does nothing if userId is not set', () async {
        final bloc = buildBloc();
        final future = _collectStates(bloc, count: 1,
            timeout: const Duration(milliseconds: 200));
        bloc.add(const RefreshCoachingGroups());
        final states = await future;

        expect(states, isEmpty);
        await bloc.close();
      });
    });
  });
}
