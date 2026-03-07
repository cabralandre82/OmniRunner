import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/athlete_baseline_entity.dart';
import 'package:omni_runner/domain/entities/athlete_trend_entity.dart';
import 'package:omni_runner/domain/entities/evolution_metric_entity.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_bloc.dart';
import 'package:omni_runner/presentation/blocs/athlete_evolution/athlete_evolution_state.dart';
import 'package:omni_runner/presentation/screens/athlete_evolution_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeEvolutionBloc extends Cubit<AthleteEvolutionState>
    implements AthleteEvolutionBloc {
  _FakeEvolutionBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _trend = AthleteTrendEntity(
  id: 't1',
  userId: 'u1',
  groupId: 'g1',
  metric: EvolutionMetric.avgPace,
  period: EvolutionPeriod.weekly,
  direction: TrendDirection.improving,
  currentValue: 320.0,
  baselineValue: 350.0,
  changePercent: -8.6,
  dataPoints: 4,
  latestPeriodKey: '2026-W08',
  analyzedAtMs: DateTime(2026, 2, 20).millisecondsSinceEpoch,
);

final _baseline = AthleteBaselineEntity(
  id: 'b1',
  userId: 'u1',
  groupId: 'g1',
  metric: EvolutionMetric.avgPace,
  value: 350.0,
  sampleSize: 5,
  windowStartMs: DateTime(2026, 1, 1).millisecondsSinceEpoch,
  windowEndMs: DateTime(2026, 2, 1).millisecondsSinceEpoch,
  computedAtMs: DateTime(2026, 2, 1).millisecondsSinceEpoch,
);

void main() {
  group('AthleteEvolutionScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders app bar with athlete name', (tester) async {
      final bloc = _FakeEvolutionBloc(const AthleteEvolutionInitial());

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Evolução · João'), findsOneWidget);
    });

    testWidgets('shows initial text for AthleteEvolutionInitial',
        (tester) async {
      final bloc = _FakeEvolutionBloc(const AthleteEvolutionInitial());

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Carregando evolução...'), findsOneWidget);
    });

    testWidgets('shows loading indicator for AthleteEvolutionLoading',
        (tester) async {
      final bloc = _FakeEvolutionBloc(
        const AthleteEvolutionLoading(
          metric: EvolutionMetric.avgPace,
          period: EvolutionPeriod.weekly,
        ),
      );

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for AthleteEvolutionError',
        (tester) async {
      final bloc = _FakeEvolutionBloc(
        const AthleteEvolutionError('Erro ao carregar evolução'),
      );

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar evolução'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows empty state for AthleteEvolutionEmpty', (tester) async {
      final bloc = _FakeEvolutionBloc(
        const AthleteEvolutionEmpty(
          metric: EvolutionMetric.avgPace,
          period: EvolutionPeriod.weekly,
        ),
      );

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Sem dados de evolução'), findsOneWidget);
    });

    testWidgets('shows loaded state with trends and baselines',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeEvolutionBloc(
        AthleteEvolutionLoaded(
          trends: [_trend],
          baselines: [_baseline],
          selectedMetric: EvolutionMetric.avgPace,
          selectedPeriod: EvolutionPeriod.weekly,
          selectedTrend: _trend,
          selectedBaseline: _baseline,
        ),
      );

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Melhorando'), findsOneWidget);
      expect(find.text('Baseline'), findsWidgets);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeEvolutionBloc(const AthleteEvolutionInitial());

      await tester.pumpApp(
        BlocProvider<AthleteEvolutionBloc>.value(
          value: bloc,
          child: const AthleteEvolutionScreen(athleteName: 'João'),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
