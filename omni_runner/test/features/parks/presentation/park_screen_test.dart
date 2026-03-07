import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/features/parks/domain/park_entity.dart';
import 'package:omni_runner/features/parks/presentation/park_screen.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/test_di.dart';

final _sl = GetIt.instance;

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _testPark = ParkEntity(
  id: 'park-1',
  name: 'Parque Ibirapuera',
  city: 'São Paulo',
  state: 'SP',
  polygon: [
    LatLng(-23.58, -46.66),
    LatLng(-23.59, -46.66),
    LatLng(-23.59, -46.65),
  ],
  center: LatLng(-23.585, -46.655),
);

void main() {
  group('ParkScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      ensureSupabaseClientRegistered();
      _sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const ParkScreen(park: _testPark),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with park name', (tester) async {
      await tester.pumpApp(
        const ParkScreen(park: _testPark),
        wrapScaffold: false,
      );

      expect(find.text('Parque Ibirapuera'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows tab bar with tabs', (tester) async {
      await tester.pumpApp(
        const ParkScreen(park: _testPark),
        wrapScaffold: false,
      );

      expect(find.text('Ranking'), findsOneWidget);
      expect(find.text('Comunidade'), findsOneWidget);
      expect(find.text('Segmentos'), findsOneWidget);
    });
  });
}
