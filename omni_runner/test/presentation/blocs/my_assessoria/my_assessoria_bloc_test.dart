import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/repositories/i_my_assessoria_remote_source.dart';
import 'package:omni_runner/domain/repositories/i_switch_assessoria_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/switch_assessoria.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_bloc.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_event.dart';
import 'package:omni_runner/presentation/blocs/my_assessoria/my_assessoria_state.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRemote implements IMyAssessoriaRemoteSource {
  List<CoachingMemberEntity> members = [];
  final Map<String, CoachingGroupEntity> groups = {};
  Exception? error;

  @override
  Future<List<CoachingMemberEntity>> fetchMemberships(String userId) async {
    if (error != null) throw error!;
    return members;
  }

  @override
  Future<CoachingGroupEntity?> fetchGroup(String groupId) async {
    return groups[groupId];
  }
}

class _FakeGroupRepo implements ICoachingGroupRepo {
  @override
  Future<void> save(CoachingGroupEntity group) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  @override
  Future<void> save(CoachingMemberEntity member) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSwitchAssessoriaRepo extends Mock
    implements ISwitchAssessoriaRepo {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _userId = 'user-1';

const _member = CoachingMemberEntity(
  id: 'cm-1',
  userId: _userId,
  groupId: 'g-1',
  displayName: 'Alice',
  role: CoachingRole.athlete,
  joinedAtMs: 1000000,
);

const _group = CoachingGroupEntity(
  id: 'g-1',
  name: 'Assessoria Alpha',
  coachUserId: 'coach-1',
  createdAtMs: 500000,
);

Future<List<MyAssessoriaState>> _collectStates(
  MyAssessoriaBloc bloc, {
  required int count,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final states = <MyAssessoriaState>[];
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeRemote remote;
  late _FakeGroupRepo groupRepo;
  late _FakeMemberRepo memberRepo;
  late MockSwitchAssessoriaRepo switchRepo;
  late SwitchAssessoria switchAssessoria;

  setUp(() {
    remote = _FakeRemote();
    groupRepo = _FakeGroupRepo();
    memberRepo = _FakeMemberRepo();
    switchRepo = MockSwitchAssessoriaRepo();
    switchAssessoria = SwitchAssessoria(repo: switchRepo);
  });

  MyAssessoriaBloc buildBloc() => MyAssessoriaBloc(
        groupRepo: groupRepo,
        memberRepo: memberRepo,
        remote: remote,
        switchAssessoria: switchAssessoria,
      );

  group('MyAssessoriaBloc', () {
    test('initial state is MyAssessoriaInitial', () {
      final bloc = buildBloc();
      expect(bloc.state, isA<MyAssessoriaInitial>());
      bloc.close();
    });

    test('emits [Loading, Loaded] with group when athlete membership exists',
        () async {
      remote.members = [_member];
      remote.groups['g-1'] = _group;

      final bloc = buildBloc();
      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadMyAssessoria(_userId));
      final states = await future;
      await bloc.close();

      expect(states[0], isA<MyAssessoriaLoading>());
      expect(states[1], isA<MyAssessoriaLoaded>());
      final loaded = states[1] as MyAssessoriaLoaded;
      expect(loaded.currentGroup!.name, 'Assessoria Alpha');
      expect(loaded.membership!.userId, _userId);
    });

    test('emits [Loading, Loaded] with no group when no athlete membership',
        () async {
      remote.members = [];

      final bloc = buildBloc();
      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadMyAssessoria(_userId));
      final states = await future;
      await bloc.close();

      final loaded = states[1] as MyAssessoriaLoaded;
      expect(loaded.currentGroup, isNull);
      expect(loaded.membership, isNull);
    });

    test('emits [Loading, Error] on exception', () async {
      remote.error = Exception('offline');

      final bloc = buildBloc();
      final future = _collectStates(bloc, count: 2);
      bloc.add(const LoadMyAssessoria(_userId));
      final states = await future;
      await bloc.close();

      expect(states[1], isA<MyAssessoriaError>());
    });

    test('ConfirmSwitchAssessoria emits [Switching, Switched]', () async {
      when(() => switchRepo.switchTo('g-2'))
          .thenAnswer((_) async => 'g-2');

      final bloc = buildBloc();
      final future = _collectStates(bloc, count: 2);
      bloc.add(const ConfirmSwitchAssessoria('g-2'));
      final states = await future;
      await bloc.close();

      expect(states[0], isA<MyAssessoriaSwitching>());
      expect(states[1], isA<MyAssessoriaSwitched>());
      expect((states[1] as MyAssessoriaSwitched).newGroupId, 'g-2');
      verify(() => switchRepo.switchTo('g-2')).called(1);
    });
  });
}
