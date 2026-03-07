import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/presentation/blocs/events/events_bloc.dart';
import 'package:omni_runner/presentation/blocs/events/events_state.dart';
import 'package:omni_runner/presentation/screens/events_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeEventsBloc extends Cubit<EventsState> implements EventsBloc {
  _FakeEventsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _activeEvent = EventEntity(
  id: 'e1',
  title: 'Maratona Virtual',
  description: 'Corra 42km durante o mês',
  type: EventType.individual,
  metric: GoalMetric.distance,
  targetValue: 42000,
  startsAtMs: DateTime(2026, 3, 1).millisecondsSinceEpoch,
  endsAtMs: DateTime(2026, 3, 31).millisecondsSinceEpoch,
  status: EventStatus.active,
  createdBySystem: true,
  rewards: const EventRewards(xpCompletion: 100, coinsCompletion: 30),
);

void main() {
  group('EventsScreen', () {
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
      final bloc = _FakeEventsBloc(const EventsLoading());

      await tester.pumpApp(
        BlocProvider<EventsBloc>.value(
          value: bloc,
          child: const EventsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeEventsBloc(const EventsError('Erro ao carregar'));

      await tester.pumpApp(
        BlocProvider<EventsBloc>.value(
          value: bloc,
          child: const EventsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar'), findsOneWidget);
    });

    testWidgets('shows empty state when no events', (tester) async {
      final bloc = _FakeEventsBloc(const EventsLoaded());

      await tester.pumpApp(
        BlocProvider<EventsBloc>.value(
          value: bloc,
          child: const EventsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum evento disponível'), findsOneWidget);
    });

    testWidgets('shows active events section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeEventsBloc(EventsLoaded(
        activeEvents: [_activeEvent],
      ));

      await tester.pumpApp(
        BlocProvider<EventsBloc>.value(
          value: bloc,
          child: const EventsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Em andamento'), findsOneWidget);
      expect(find.text('Maratona Virtual'), findsOneWidget);
    });

    testWidgets('has refresh button', (tester) async {
      final bloc = _FakeEventsBloc(const EventsInitial());

      await tester.pumpApp(
        BlocProvider<EventsBloc>.value(
          value: bloc,
          child: const EventsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
