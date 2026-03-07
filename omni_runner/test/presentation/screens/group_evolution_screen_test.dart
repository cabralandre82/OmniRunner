import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_event.dart';
import 'package:omni_runner/presentation/blocs/group_evolution/group_evolution_state.dart';
import 'package:omni_runner/presentation/screens/group_evolution_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeGroupEvolutionBloc extends Cubit<GroupEvolutionState>
    implements GroupEvolutionBloc {
  _FakeGroupEvolutionBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _trend = AthleteTrendEntity(
  id: 't1',
  userId: 'user1',
  groupId: 'g1',
  metric: EvolutionMetric.avgPace,
  period: EvolutionPeriod.weekly,
  direction: TrendDirection.improving,
  currentValue: 300,
  baselineValue: 330,
  changePercent: -9.1,
  dataPoints: 4,
  latestPeriodKey: '2026-W09',
  analyzedAtMs: 0,
);

void main() {
  group('GroupEvolutionScreen', () {
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
      final bloc =
          _FakeGroupEvolutionBloc(const GroupEvolutionLoading());

      await tester.pumpApp(
        BlocProvider<GroupEvolutionBloc>.value(
          value: bloc,
          child: const GroupEvolutionScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state', (tester) async {
      final bloc =
          _FakeGroupEvolutionBloc(const GroupEvolutionEmpty());

      await tester.pumpApp(
        BlocProvider<GroupEvolutionBloc>.value(
          value: bloc,
          child: const GroupEvolutionScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Sem dados de evolução'), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc =
          _FakeGroupEvolutionBloc(const GroupEvolutionError('Erro'));

      await tester.pumpApp(
        BlocProvider<GroupEvolutionBloc>.value(
          value: bloc,
          child: const GroupEvolutionScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro'), findsOneWidget);
    });

    testWidgets('shows trend data when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeGroupEvolutionBloc(GroupEvolutionLoaded(
        trends: [_trend],
        improvingCount: 1,
        stableCount: 0,
        decliningCount: 0,
        insufficientCount: 0,
      ));

      await tester.pumpApp(
        BlocProvider<GroupEvolutionBloc>.value(
          value: bloc,
          child: const GroupEvolutionScreen(groupName: 'Grupo A'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Evolução · Grupo A'), findsOneWidget);
      expect(find.text('Melhorando'), findsWidgets);
      expect(find.byIcon(Icons.trending_up), findsWidgets);
    });

    testWidgets('has refresh button', (tester) async {
      final bloc =
          _FakeGroupEvolutionBloc(const GroupEvolutionInitial());

      await tester.pumpApp(
        BlocProvider<GroupEvolutionBloc>.value(
          value: bloc,
          child: const GroupEvolutionScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
