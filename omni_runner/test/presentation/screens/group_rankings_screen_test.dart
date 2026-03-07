import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/coaching_group_ranking_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_entry_entity.dart';
import 'package:omni_runner/domain/entities/coaching_ranking_metric.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_bloc.dart';
import 'package:omni_runner/presentation/blocs/coaching_rankings/coaching_rankings_state.dart';
import 'package:omni_runner/presentation/screens/group_rankings_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeCoachingRankingsBloc extends Cubit<CoachingRankingsState>
    implements CoachingRankingsBloc {
  _FakeCoachingRankingsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _ranking = CoachingGroupRankingEntity(
  id: 'r1',
  groupId: 'g1',
  metric: CoachingRankingMetric.volumeDistance,
  period: CoachingRankingPeriod.weekly,
  periodKey: '2026-W09',
  startsAtMs: 0,
  endsAtMs: 1000000,
  entries: [
    const CoachingRankingEntryEntity(
      userId: 'u1',
      displayName: 'Ana',
      value: 42000,
      rank: 1,
      sessionCount: 5,
    ),
    const CoachingRankingEntryEntity(
      userId: 'u2',
      displayName: 'Bruno',
      value: 35000,
      rank: 2,
      sessionCount: 4,
    ),
  ],
  computedAtMs: 0,
);

void main() {
  group('GroupRankingsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows loading indicator', (tester) async {
      final bloc = _FakeCoachingRankingsBloc(const CoachingRankingsLoading(
        metric: CoachingRankingMetric.volumeDistance,
        period: CoachingRankingPeriod.weekly,
      ));

      await tester.pumpApp(
        BlocProvider<CoachingRankingsBloc>.value(
          value: bloc,
          child: const GroupRankingsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state', (tester) async {
      final bloc = _FakeCoachingRankingsBloc(const CoachingRankingsEmpty(
        selectedMetric: CoachingRankingMetric.volumeDistance,
        selectedPeriod: CoachingRankingPeriod.weekly,
      ));

      await tester.pumpApp(
        BlocProvider<CoachingRankingsBloc>.value(
          value: bloc,
          child: const GroupRankingsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Ranking vazio'), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeCoachingRankingsBloc(
          const CoachingRankingsError('Falha no ranking'));

      await tester.pumpApp(
        BlocProvider<CoachingRankingsBloc>.value(
          value: bloc,
          child: const GroupRankingsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha no ranking'), findsOneWidget);
    });

    testWidgets('shows ranking entries when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeCoachingRankingsBloc(CoachingRankingsLoaded(
        ranking: _ranking,
        selectedMetric: CoachingRankingMetric.volumeDistance,
        selectedPeriod: CoachingRankingPeriod.weekly,
      ));

      await tester.pumpApp(
        BlocProvider<CoachingRankingsBloc>.value(
          value: bloc,
          child: const GroupRankingsScreen(groupName: 'Grupo A'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Ranking · Grupo A'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
    });

    testWidgets('has refresh button', (tester) async {
      final bloc =
          _FakeCoachingRankingsBloc(const CoachingRankingsInitial());

      await tester.pumpApp(
        BlocProvider<CoachingRankingsBloc>.value(
          value: bloc,
          child: const GroupRankingsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
