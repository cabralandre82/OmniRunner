import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_state.dart';

AthleteTrendEntity _trend(String uid, TrendDirection dir) => AthleteTrendEntity(
  id: 't-$uid', userId: uid, groupId: 'g1',
  metric: EvolutionMetric.weeklyVolume, period: EvolutionPeriod.weekly,
  direction: dir, currentValue: 10000, baselineValue: 8000,
  changePercent: 25, dataPoints: 4, latestPeriodKey: '2026-W08', analyzedAtMs: 0,
);

class _FakeRepo implements IAthleteTrendRepo {
  List<AthleteTrendEntity> trends = [];
  @override Future<List<AthleteTrendEntity>> getByGroup(String g) async => trends;
  @override Future<void> save(AthleteTrendEntity t) async {}
  @override Future<AthleteTrendEntity?> getById(String id) async => null;
  @override Future<AthleteTrendEntity?> getByUserGroupMetricPeriod({
    required String userId, required String groupId, required EvolutionMetric metric, required EvolutionPeriod period,
  }) async => null;
  @override Future<List<AthleteTrendEntity>> getByUserAndGroup({required String userId, required String groupId}) async => [];
  @override Future<List<AthleteTrendEntity>> getByGroupAndDirection({required String groupId, required TrendDirection direction}) async => [];
  @override Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeRepo repo;
  setUp(() => repo = _FakeRepo());

  test('emits [Loading, Empty] when no trends', () async {
    final bloc = GroupEvolutionBloc(trendRepo: repo);
    final states = <GroupEvolutionState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadGroupEvolution(groupId: 'g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<GroupEvolutionLoading>());
    expect(states[1], isA<GroupEvolutionEmpty>());

    await bloc.close();
  });

  test('emits [Loading, Loaded] with trend counts', () async {
    repo.trends = [
      _trend('u1', TrendDirection.improving),
      _trend('u2', TrendDirection.stable),
      _trend('u3', TrendDirection.declining),
    ];
    final bloc = GroupEvolutionBloc(trendRepo: repo);
    final states = <GroupEvolutionState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadGroupEvolution(groupId: 'g1'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<GroupEvolutionLoading>());
    expect(states[1], isA<GroupEvolutionLoaded>());
    expect((states[1] as GroupEvolutionLoaded).improvingCount, 1);

    await bloc.close();
  });

  test('refresh does nothing before load', () async {
    final bloc = GroupEvolutionBloc(trendRepo: repo);
    final states = <GroupEvolutionState>[];
    bloc.stream.listen(states.add);

    bloc.add(const RefreshGroupEvolution());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, isEmpty);

    await bloc.close();
  });
}
