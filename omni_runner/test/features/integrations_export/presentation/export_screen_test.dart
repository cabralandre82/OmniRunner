import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/workout_session_entity.dart';
import 'package:omni_runner/domain/entities/workout_status.dart';
import 'package:omni_runner/features/integrations_export/presentation/export_screen.dart';

import '../../../helpers/pump_app.dart';

final _testSession = WorkoutSessionEntity(
  id: 'session-1',
  status: WorkoutStatus.completed,
  startTimeMs: DateTime(2026, 3, 1, 7).millisecondsSinceEpoch,
  endTimeMs: DateTime(2026, 3, 1, 8).millisecondsSinceEpoch,
  totalDistanceM: 5000,
  route: const [],
);

void main() {
  group('ExportScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        ExportScreen(session: _testSession),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        ExportScreen(session: _testSession),
        wrapScaffold: false,
      );

      expect(find.text('Exportar Corrida'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
