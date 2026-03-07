import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_training_create_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaffTrainingCreateScreen', () {
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
        const StaffTrainingCreateScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with title for new training', (tester) async {
      await tester.pumpApp(
        const StaffTrainingCreateScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.text('Novo Treino'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows form fields', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const StaffTrainingCreateScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.text('Título'), findsOneWidget);
      expect(find.text('Descrição'), findsOneWidget);
      expect(find.text('Local'), findsOneWidget);
    });

    testWidgets('shows save button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const StaffTrainingCreateScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Salvar treino'), findsOneWidget);
    });

    testWidgets('shows training parameters section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const StaffTrainingCreateScreen(groupId: 'g1', userId: 'u1'),
        wrapScaffold: false,
      );

      expect(find.text('Parâmetros do treino'), findsOneWidget);
      expect(find.text('Data e horário'), findsOneWidget);
    });
  });
}
