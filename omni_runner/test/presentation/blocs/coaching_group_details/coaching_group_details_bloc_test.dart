import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_entity.dart';
import 'package:omni_runner/domain/entities/coaching_member_entity.dart';
import 'package:omni_runner/domain/repositories/i_coaching_group_repo.dart';
import 'package:omni_runner/domain/repositories/i_coaching_member_repo.dart';
import 'package:omni_runner/domain/usecases/coaching/get_coaching_group_details.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_group_details/coaching_group_details_state.dart';

final _group = CoachingGroupEntity(id: 'g1', name: 'Team', coachUserId: 'coach', createdAtMs: 0);
final _member = CoachingMemberEntity(id: 'm1', userId: 'u1', groupId: 'g1', displayName: 'U', role: CoachingRole.athlete, joinedAtMs: 0);

class _FakeGroupRepo implements ICoachingGroupRepo {
  @override Future<CoachingGroupEntity?> getById(String id) async => id == 'g1' ? _group : null;
  @override Future<void> save(CoachingGroupEntity g) async {}
  @override Future<void> update(CoachingGroupEntity g) async {}
  @override Future<List<CoachingGroupEntity>> getByCoachUserId(String u) async => [];
  @override Future<int> countByCoachUserId(String u) async => 0;
  @override Future<void> deleteById(String id) async {}
}

class _FakeMemberRepo implements ICoachingMemberRepo {
  bool shouldFail = false;
  @override Future<CoachingMemberEntity?> getMember(String g, String u) async =>
      shouldFail ? null : (u == 'u1' ? _member : null);
  @override Future<List<CoachingMemberEntity>> getByGroupId(String g) async => [_member];
  @override Future<void> save(CoachingMemberEntity m) async {}
  @override Future<void> update(CoachingMemberEntity m) async {}
  @override Future<List<CoachingMemberEntity>> getByUserId(String u) async => [];
  @override Future<int> countByGroupId(String g) async => 1;
  @override Future<void> deleteById(String id) async {}
}

void main() {
  late GetCoachingGroupDetails getDetails;
  late _FakeMemberRepo memberRepo;

  setUp(() {
    memberRepo = _FakeMemberRepo();
    getDetails = GetCoachingGroupDetails(groupRepo: _FakeGroupRepo(), memberRepo: memberRepo);
  });

  test('emits [Loading, Loaded] on successful load', () async {
    final bloc = CoachingGroupDetailsBloc(getDetails: getDetails);
    final states = <CoachingGroupDetailsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadCoachingGroupDetails(groupId: 'g1', callerUserId: 'u1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<CoachingGroupDetailsLoading>());
    expect(states[1], isA<CoachingGroupDetailsLoaded>());

    await bloc.close();
  });

  test('emits [Loading, Error] when caller is not member', () async {
    memberRepo.shouldFail = true;
    final bloc = CoachingGroupDetailsBloc(getDetails: getDetails);
    final states = <CoachingGroupDetailsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadCoachingGroupDetails(groupId: 'g1', callerUserId: 'stranger'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<CoachingGroupDetailsLoading>());
    expect(states[1], isA<CoachingGroupDetailsError>());

    await bloc.close();
  });

  test('refresh does nothing before load', () async {
    final bloc = CoachingGroupDetailsBloc(getDetails: getDetails);
    final states = <CoachingGroupDetailsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const RefreshCoachingGroupDetails());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, isEmpty);

    await bloc.close();
  });
}
