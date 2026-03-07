import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/integrations_export/presentation/how_to_import_screen.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('HowToImportScreen', () {
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
        const HowToImportScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const HowToImportScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Como importar'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows platform sections', (tester) async {
      await tester.pumpApp(
        const HowToImportScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Garmin Connect (Web)'), findsOneWidget);
      expect(find.text('Outras plataformas'), findsOneWidget);
    });
  });
}
