import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/auth_user.dart';
import 'package:omni_runner/core/auth/auth_repository.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/presentation/screens/invite_friends_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeAuthRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('InviteFriendsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };

      final sl = GetIt.instance;
      if (!sl.isRegistered<UserIdentityProvider>()) {
        final provider = UserIdentityProvider(authRepo: _FakeAuthRepo());
        sl.registerSingleton<UserIdentityProvider>(provider);
      }
    });
    tearDown(() {
      FlutterError.onError = origOnError;
      GetIt.instance.reset();
    });

    testWidgets('renders without crash and has AppBar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteFriendsScreen(),
        wrapScaffold: false,
      );

      expect(find.byType(InviteFriendsScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Convidar amigos'), findsOneWidget);
    });

    testWidgets('shows hero section with invite text', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteFriendsScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Traga seus amigos!'), findsOneWidget);
      expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);
    });

    testWidgets('shows copy and share buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteFriendsScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Copiar link'), findsOneWidget);
      expect(find.text('Compartilhar'), findsOneWidget);
    });

    testWidgets('shows how it works section', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpApp(
        const InviteFriendsScreen(),
        wrapScaffold: false,
      );

      expect(find.text('Como funciona?'), findsOneWidget);
    });
  });
}
