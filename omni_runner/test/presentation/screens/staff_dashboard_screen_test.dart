import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/core/tips/first_use_tips.dart';
import 'package:omni_runner/presentation/screens/staff_dashboard_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

final _sl = GetIt.instance;

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFirstUseTips implements FirstUseTips {
  bool shouldShow(String key) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('StaffDashboardScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      ensureSupabaseClientRegistered();
      _sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
      _sl.registerFactory<FirstUseTips>(() => _FakeFirstUseTips());
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      _sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      await tester.pumpApp(
        const StaffDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with correct title', (tester) async {
      await tester.pumpApp(
        const StaffDashboardScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Omni Runner'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
