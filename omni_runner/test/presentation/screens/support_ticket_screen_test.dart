import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/presentation/screens/support_ticket_screen.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/test_di.dart';

final _sl = GetIt.instance;

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SupportTicketScreen', () {
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
        const SupportTicketScreen(ticketId: 't1', subject: 'Meu Problema'),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with subject', (tester) async {
      await tester.pumpApp(
        const SupportTicketScreen(ticketId: 't1', subject: 'Meu Problema'),
        wrapScaffold: false,
      );

      expect(find.text('Meu Problema'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
