import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/features/parks/presentation/my_parks_screen.dart';

import '../../../helpers/pump_app.dart';

void main() {
  group('MyParksScreen', () {
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
        const MyParksScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const MyParksScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Parques'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
