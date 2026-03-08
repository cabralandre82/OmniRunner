import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/domain/repositories/i_coaching_ranking_repo.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_event.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_state.dart';

class _FakeRankingRepo implements ICoachingRankingRepo {
  CoachingGroupRankingEntity? result;
  @override Future<CoachingGroupRankingEntity?> getByGroupMetricPeriod(String g, CoachingRankingMetric m, String pk) async => result;
  @override Future<void> save(CoachingGroupRankingEntity r) async {}
  @override Future<CoachingGroupRankingEntity?> getById(String id) async => null;
  @override Future<List<CoachingGroupRankingEntity>> getByGroupId(String g) async => [];
  @override Future<void> deleteById(String id) async {}
}

void main() {
  late _FakeRankingRepo repo;

  setUp(() => repo = _FakeRankingRepo());

  test('emits [Loading, Empty] when no ranking data', () async {
    final bloc = CoachingRankingsBloc(rankingRepo: repo);
    final states = <CoachingRankingsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadCoachingRanking(
      groupId: 'g1', metric: CoachingRankingMetric.volumeDistance,
      period: CoachingRankingPeriod.weekly, periodKey: '2026-W09',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<CoachingRankingsLoading>());
    expect(states[1], isA<CoachingRankingsEmpty>());

    await bloc.close();
  });

  test('emits [Loading, Loaded] when ranking exists', () async {
    repo.result = const CoachingGroupRankingEntity(
      id: 'r1', groupId: 'g1', metric: CoachingRankingMetric.volumeDistance,
      period: CoachingRankingPeriod.weekly, periodKey: '2026-W09',
      startsAtMs: 0, endsAtMs: 1000, entries: [], computedAtMs: 500,
    );
    final bloc = CoachingRankingsBloc(rankingRepo: repo);
    final states = <CoachingRankingsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const LoadCoachingRanking(
      groupId: 'g1', metric: CoachingRankingMetric.volumeDistance,
      period: CoachingRankingPeriod.weekly, periodKey: '2026-W09',
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, hasLength(2));
    expect(states[0], isA<CoachingRankingsLoading>());

    await bloc.close();
  });

  test('refresh does nothing before load', () async {
    final bloc = CoachingRankingsBloc(rankingRepo: repo);
    final states = <CoachingRankingsState>[];
    bloc.stream.listen(states.add);

    bloc.add(const RefreshCoachingRanking());
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, isEmpty);

    await bloc.close();
  });
}
