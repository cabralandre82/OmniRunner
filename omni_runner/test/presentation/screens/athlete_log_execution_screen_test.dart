// ignore_for_file: invalid_override, invalid_use_of_type_outside_library, extends_non_class, super_formal_parameter_without_associated_positional
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/domain/usecases/wearable/import_execution.dart';
import 'package:omni_runner/presentation/screens/athlete_log_execution_screen.dart';

import '../../helpers/pump_app.dart';

final _sl = GetIt.instance;

class _FakeImportExecution implements ImportExecution {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AthleteLogExecutionScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      _sl.registerFactory<ImportExecution>(() => _FakeImportExecution());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const AthleteLogExecutionScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const AthleteLogExecutionScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Registrar Execução'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows form fields', (tester) async {
      await tester.pumpApp(
        const AthleteLogExecutionScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(TextFormField), findsWidgets);
    });
  });
}
