import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/domain/repositories/i_athlete_baseline_repo.dart';
import 'package:omni_runner/domain/repositories/i_athlete_trend_repo.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_state.dart';

class MockTrendRepo extends Mock implements IAthleteTrendRepo {}

class MockBaselineRepo extends Mock implements IAthleteBaselineRepo {}

Future<List<AthleteEvolutionState>> _collectStates(
  AthleteEvolutionBloc bloc, {
  int count = 2,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final states = <AthleteEvolutionState>[];
  final sub = bloc.stream.listen(states.add);
  final deadline = DateTime.now().add(timeout);
  while (states.length < count && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await sub.cancel();
  return states;
}

AthleteTrendEntity _trend({
  EvolutionMetric metric = EvolutionMetric.avgPace,
  EvolutionPeriod period = EvolutionPeriod.weekly,
}) =>
    AthleteTrendEntity(
      id: 't-1',
      userId: 'u-1',
      groupId: 'g-1',
      metric: metric,
      period: period,
      direction: TrendDirection.improving,
      currentValue: 300,
      baselineValue: 330,
      changePercent: -9.1,
      dataPoints: 4,
      latestPeriodKey: '2026-W08',
      analyzedAtMs: 1000000,
    );

AthleteBaselineEntity _baseline({
  EvolutionMetric metric = EvolutionMetric.avgPace,
}) =>
    AthleteBaselineEntity(
      id: 'b-1',
      userId: 'u-1',
      groupId: 'g-1',
      metric: metric,
      value: 330,
      sampleSize: 10,
      windowStartMs: 0,
      windowEndMs: 500000,
      computedAtMs: 500000,
    );

void main() {
  late MockTrendRepo trendRepo;
  late MockBaselineRepo baselineRepo;

  setUp(() {
    trendRepo = MockTrendRepo();
    baselineRepo = MockBaselineRepo();
  });

  group('AthleteEvolutionBloc', () {
    test('initial state is AthleteEvolutionInitial', () {
      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      expect(bloc.state, isA<AthleteEvolutionInitial>());
      bloc.close();
    });

    test('LoadAthleteEvolution emits Loading then Loaded', () async {
      when(() => trendRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_trend()]);
      when(() => baselineRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_baseline()]);
      when(() => trendRepo.getByUserGroupMetricPeriod(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
            period: EvolutionPeriod.weekly,
          )).thenAnswer((_) async => _trend());
      when(() => baselineRepo.getByUserGroupMetric(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
          )).thenAnswer((_) async => _baseline());

      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const LoadAthleteEvolution(userId: 'u-1', groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[0], isA<AthleteEvolutionLoading>());
      expect(states[1], isA<AthleteEvolutionLoaded>());
      final loaded = states[1] as AthleteEvolutionLoaded;
      expect(loaded.trends.length, 1);
      expect(loaded.selectedMetric, EvolutionMetric.avgPace);
      expect(loaded.selectedTrend, isNotNull);
      expect(loaded.selectedBaseline, isNotNull);

      await bloc.close();
    });

    test('emits Empty when no trends or baselines', () async {
      when(() => trendRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => []);
      when(() => baselineRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => []);

      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const LoadAthleteEvolution(userId: 'u-1', groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[1], isA<AthleteEvolutionEmpty>());
      await bloc.close();
    });

    test('emits Error on exception', () async {
      when(() => trendRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenThrow(Exception('db error'));

      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const LoadAthleteEvolution(userId: 'u-1', groupId: 'g-1'));
      final states = await _collectStates(bloc);

      expect(states[1], isA<AthleteEvolutionError>());
      expect(
        (states[1] as AthleteEvolutionError).message,
        contains('db error'),
      );
      await bloc.close();
    });

    test('ChangeEvolutionMetric triggers refetch with new metric', () async {
      when(() => trendRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_trend()]);
      when(() => baselineRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_baseline()]);
      when(() => trendRepo.getByUserGroupMetricPeriod(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
            period: EvolutionPeriod.weekly,
          )).thenAnswer((_) async => _trend());
      when(() => baselineRepo.getByUserGroupMetric(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
          )).thenAnswer((_) async => _baseline());
      when(() => trendRepo.getByUserGroupMetricPeriod(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.weeklyVolume,
            period: EvolutionPeriod.weekly,
          )).thenAnswer((_) async => null);
      when(() => baselineRepo.getByUserGroupMetric(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.weeklyVolume,
          )).thenAnswer((_) async => null);

      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const LoadAthleteEvolution(userId: 'u-1', groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const ChangeEvolutionMetric(EvolutionMetric.weeklyVolume));
      final states = await _collectStates(bloc);

      expect(states[1], isA<AthleteEvolutionLoaded>());
      final loaded = states[1] as AthleteEvolutionLoaded;
      expect(loaded.selectedMetric, EvolutionMetric.weeklyVolume);

      await bloc.close();
    });

    test('ChangeEvolutionPeriod triggers refetch with new period', () async {
      when(() => trendRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_trend()]);
      when(() => baselineRepo.getByUserAndGroup(userId: 'u-1', groupId: 'g-1'))
          .thenAnswer((_) async => [_baseline()]);
      when(() => trendRepo.getByUserGroupMetricPeriod(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
            period: EvolutionPeriod.weekly,
          )).thenAnswer((_) async => _trend());
      when(() => baselineRepo.getByUserGroupMetric(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
          )).thenAnswer((_) async => _baseline());
      when(() => trendRepo.getByUserGroupMetricPeriod(
            userId: 'u-1',
            groupId: 'g-1',
            metric: EvolutionMetric.avgPace,
            period: EvolutionPeriod.monthly,
          )).thenAnswer((_) async => null);

      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const LoadAthleteEvolution(userId: 'u-1', groupId: 'g-1'));
      await _collectStates(bloc);

      bloc.add(const ChangeEvolutionPeriod(EvolutionPeriod.monthly));
      final states = await _collectStates(bloc);

      expect(states[0], isA<AthleteEvolutionLoading>());
      final loading = states[0] as AthleteEvolutionLoading;
      expect(loading.period, EvolutionPeriod.monthly);

      await bloc.close();
    });

    test('RefreshAthleteEvolution does nothing if userId not set', () async {
      final bloc = AthleteEvolutionBloc(
        trendRepo: trendRepo,
        baselineRepo: baselineRepo,
      );
      bloc.add(const RefreshAthleteEvolution());

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(bloc.state, isA<AthleteEvolutionInitial>());
      await bloc.close();
    });
  });
}
