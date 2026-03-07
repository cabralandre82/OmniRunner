import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_bloc.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_event.dart';
import 'package:omni_runner/presentation/blocs/race_events/race_events_state.dart';
import 'package:omni_runner/presentation/screens/group_events_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeRaceEventsBloc extends Cubit<RaceEventsState>
    implements RaceEventsBloc {
  _FakeRaceEventsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _event = RaceEventEntity(
  id: 'e1',
  groupId: 'g1',
  title: 'Corrida 10K',
  location: 'Parque Ibirapuera',
  metric: RaceEventMetric.distance,
  targetDistanceM: 10000,
  startsAtMs: DateTime(2026, 3, 1).millisecondsSinceEpoch,
  endsAtMs: DateTime(2026, 3, 7).millisecondsSinceEpoch,
  status: RaceEventStatus.active,
  createdByUserId: 'coach1',
  createdAtMs: 0,
  xpReward: 100,
  coinsReward: 50,
);

void main() {
  group('GroupEventsScreen', () {
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
      final bloc = _FakeRaceEventsBloc(const RaceEventsLoading());

      await tester.pumpApp(
        BlocProvider<RaceEventsBloc>.value(
          value: bloc,
          child: const GroupEventsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state', (tester) async {
      final bloc = _FakeRaceEventsBloc(const RaceEventsEmpty());

      await tester.pumpApp(
        BlocProvider<RaceEventsBloc>.value(
          value: bloc,
          child: const GroupEventsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhuma prova cadastrada'), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeRaceEventsBloc(const RaceEventsError('Erro de rede'));

      await tester.pumpApp(
        BlocProvider<RaceEventsBloc>.value(
          value: bloc,
          child: const GroupEventsScreen(groupName: 'Test'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro de rede'), findsOneWidget);
    });

    testWidgets('shows event card when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeRaceEventsBloc(RaceEventsLoaded(
        events: [_event],
        participantCounts: {'e1': 15},
      ));

      await tester.pumpApp(
        BlocProvider<RaceEventsBloc>.value(
          value: bloc,
          child: const GroupEventsScreen(groupName: 'Grupo A'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Corrida 10K'), findsOneWidget);
      expect(find.text('Parque Ibirapuera'), findsOneWidget);
      expect(find.textContaining('15 participantes'), findsOneWidget);
    });

    testWidgets('app bar shows group name', (tester) async {
      final bloc = _FakeRaceEventsBloc(const RaceEventsInitial());

      await tester.pumpApp(
        BlocProvider<RaceEventsBloc>.value(
          value: bloc,
          child: const GroupEventsScreen(groupName: 'Meu Grupo'),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Provas · Meu Grupo'), findsOneWidget);
    });
  });
}
