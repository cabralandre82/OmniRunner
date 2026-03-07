import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/event_entity.dart';
import 'package:omni_runner/domain/entities/group_entity.dart';
import 'package:omni_runner/presentation/screens/event_details_screen.dart';

import '../../helpers/pump_app.dart';

final _event = EventEntity(
  id: 'e1',
  title: 'Desafio 100K',
  description: 'Corra 100km em uma semana',
  type: EventType.individual,
  metric: GoalMetric.distance,
  targetValue: 100000,
  startsAtMs: DateTime(2026, 3, 1).millisecondsSinceEpoch,
  endsAtMs: DateTime(2026, 3, 7).millisecondsSinceEpoch,
  status: EventStatus.active,
  createdBySystem: true,
  rewards: const EventRewards(
    xpCompletion: 200,
    coinsCompletion: 50,
    xpParticipation: 20,
  ),
);

void main() {
  group('EventDetailsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows event title in app bar', (tester) async {
      await tester.pumpApp(
        EventDetailsScreen(event: _event),
        wrapScaffold: false,
      );

      expect(find.text('Desafio 100K'), findsWidgets);
    });

    testWidgets('shows event description', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        EventDetailsScreen(event: _event),
        wrapScaffold: false,
      );

      expect(find.text('Corra 100km em uma semana'), findsOneWidget);
    });

    testWidgets('shows rewards card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        EventDetailsScreen(event: _event),
        wrapScaffold: false,
      );

      expect(find.text('Recompensas'), findsOneWidget);
    });

    testWidgets('shows details card with type and metric', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        EventDetailsScreen(event: _event),
        wrapScaffold: false,
      );

      expect(find.text('Detalhes'), findsOneWidget);
      expect(find.text('Individual'), findsOneWidget);
      expect(find.text('Distância'), findsOneWidget);
    });

    testWidgets('shows status badge', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        EventDetailsScreen(event: _event),
        wrapScaffold: false,
      );

      expect(find.text('Em andamento'), findsOneWidget);
    });
  });
}
