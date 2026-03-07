import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/race_event_entity.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_bloc.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_event.dart';
import 'package:omni_runner/presentation/blocs/race_event_details/race_event_details_state.dart';
import 'package:omni_runner/presentation/screens/race_event_details_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeRaceEventDetailsBloc extends Cubit<RaceEventDetailsState>
    implements RaceEventDetailsBloc {
  _FakeRaceEventDetailsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _event = RaceEventEntity(
  id: 'e1',
  groupId: 'g1',
  title: 'Meia Maratona',
  description: 'Corrida de 21km',
  location: 'Parque Villa-Lobos',
  metric: RaceEventMetric.distance,
  targetDistanceM: 21000,
  startsAtMs: DateTime(2026, 4, 1).millisecondsSinceEpoch,
  endsAtMs: DateTime(2026, 4, 30).millisecondsSinceEpoch,
  status: RaceEventStatus.active,
  createdByUserId: 'coach1',
  createdAtMs: 0,
  xpReward: 150,
  coinsReward: 75,
);

void main() {
  group('RaceEventDetailsScreen', () {
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
          _FakeRaceEventDetailsBloc(const RaceEventDetailsLoading());

      await tester.pumpApp(
        BlocProvider<RaceEventDetailsBloc>.value(
          value: bloc,
          child: const RaceEventDetailsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Prova'), findsOneWidget);
    });

    testWidgets('shows error message', (tester) async {
      final bloc = _FakeRaceEventDetailsBloc(
          const RaceEventDetailsError('Evento não encontrado.'));

      await tester.pumpApp(
        BlocProvider<RaceEventDetailsBloc>.value(
          value: bloc,
          child: const RaceEventDetailsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Evento não encontrado.'), findsOneWidget);
    });

    testWidgets('shows initial state', (tester) async {
      final bloc =
          _FakeRaceEventDetailsBloc(const RaceEventDetailsInitial());

      await tester.pumpApp(
        BlocProvider<RaceEventDetailsBloc>.value(
          value: bloc,
          child: const RaceEventDetailsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Carregando...'), findsOneWidget);
    });

    testWidgets('shows loaded event details', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeRaceEventDetailsBloc(RaceEventDetailsLoaded(
        event: _event,
        participations: const [],
        results: const [],
        currentUserId: 'u1',
      ));

      await tester.pumpApp(
        BlocProvider<RaceEventDetailsBloc>.value(
          value: bloc,
          child: const RaceEventDetailsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Meia Maratona'), findsWidgets);
      expect(find.text('Corrida de 21km'), findsOneWidget);
      expect(find.text('Parque Villa-Lobos'), findsOneWidget);
    });
  });
}
