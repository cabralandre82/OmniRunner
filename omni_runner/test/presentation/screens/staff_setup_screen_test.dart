import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/screens/staff_setup_screen.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('StaffSetupScreen', () {
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
        StaffSetupScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows choose mode heading', (tester) async {
      await tester.pumpApp(
        StaffSetupScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.textContaining('Monte sua'), findsOneWidget);
    });

    testWidgets('shows choose mode with two options', (tester) async {
      await tester.pumpApp(
        StaffSetupScreen(onComplete: () {}),
        wrapScaffold: false,
      );

      expect(find.text('Criar assessoria'), findsOneWidget);
      expect(find.text('Entrar como professor'), findsOneWidget);
    });
  });
}
