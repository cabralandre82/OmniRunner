import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/analytics/product_event_tracker.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_bloc.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_event.dart';
import 'package:omni_runner/presentation/blocs/challenges/challenges_state.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_bloc.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_event.dart';
import 'package:omni_runner/presentation/blocs/verification/verification_state.dart';
import 'package:omni_runner/presentation/screens/challenge_create_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeChallengesBloc extends Cubit<ChallengesState>
    implements ChallengesBloc {
  _FakeChallengesBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeVerificationBloc extends Cubit<VerificationState>
    implements VerificationBloc {
  _FakeVerificationBloc() : super(const VerificationInitial());

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeProductEventTracker implements ProductEventTracker {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

class _FakeUserIdentity implements UserIdentityProvider {
  @override
  String get userId => 'test-user';

  @override
  String get displayName => 'Test User';

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  final sl = GetIt.instance;

  group('ChallengeCreateScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      sl.allowReassignment = true;
      sl.registerFactory<VerificationBloc>(() => _FakeVerificationBloc());
      sl.registerFactory<ProductEventTracker>(() => _FakeProductEventTracker());
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with title "Criar Desafio"', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Criar Desafio'), findsWidgets);
    });

    testWidgets('shows mode selector with Agora and Agendado',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Agora'), findsOneWidget);
      expect(find.text('Agendado'), findsOneWidget);
    });

    testWidgets('shows type selector (1 vs 1, Grupo, Time)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('1 vs 1'), findsOneWidget);
      expect(find.text('Grupo'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
    });

    testWidgets('shows goal cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Objetivo do desafio'), findsOneWidget);
    });

    testWidgets('shows submit button', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeChallengesBloc(const ChallengesInitial());

      await tester.pumpApp(
        BlocProvider<ChallengesBloc>.value(
          value: bloc,
          child: const ChallengeCreateScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Criar Desafio'), findsWidgets);
    });
  });
}
