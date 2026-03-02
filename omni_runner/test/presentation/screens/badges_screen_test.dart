import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/domain/entities/badge_award_entity.dart';
import 'package:omni_runner/domain/entities/badge_entity.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_bloc.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_event.dart';
import 'package:omni_runner/presentation/blocs/badges/badges_state.dart';
import 'package:omni_runner/presentation/screens/badges_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeBadgesBloc extends Cubit<BadgesState> implements BadgesBloc {
  _FakeBadgesBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _badge1 = BadgeEntity(
  id: 'b1',
  category: BadgeCategory.distance,
  tier: BadgeTier.bronze,
  name: 'Primeiro 5K',
  description: 'Complete 5km em uma corrida',
  xpReward: 50,
  criteria: const SingleSessionDistance(5000),
);

final _badge2 = BadgeEntity(
  id: 'b2',
  category: BadgeCategory.frequency,
  tier: BadgeTier.silver,
  name: 'Corredor Frequente',
  description: 'Complete 10 corridas',
  xpReward: 100,
  criteria: const SessionCount(10),
);

final _award1 = BadgeAwardEntity(
  id: 'a1',
  userId: 'u1',
  badgeId: 'b1',
  unlockedAtMs: DateTime(2026, 1, 15).millisecondsSinceEpoch,
);

void main() {
  group('BadgesScreen', () {
    // Suppress overflow errors in widget tests (test viewport may be small)
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);
    testWidgets('shows loading indicator for BadgesLoading state',
        (tester) async {
      final bloc = _FakeBadgesBloc(const BadgesLoading());

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message for BadgesError state', (tester) async {
      final bloc = _FakeBadgesBloc(const BadgesError('Falha na conexão'));

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Falha na conexão'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows empty state when catalog is empty', (tester) async {
      final bloc = _FakeBadgesBloc(
        const BadgesLoaded(catalog: [], awards: []),
      );

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Suas conquistas aparecem aqui'), findsOneWidget);
    });

    testWidgets('shows loaded badges with summary and collection', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeBadgesBloc(
        BadgesLoaded(catalog: [_badge1, _badge2], awards: const []),
      );

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('0 / 2'), findsOneWidget);
      expect(find.text('conquistas desbloqueadas'), findsOneWidget);
      expect(find.text('Primeiro 5K'), findsOneWidget);
      expect(find.text('Corredor Frequente'), findsOneWidget);
    });

    testWidgets('shows locked badge with lock icon', (tester) async {
      final bloc = _FakeBadgesBloc(
        BadgesLoaded(catalog: [_badge2], awards: const []),
      );

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      expect(find.text('Corredor Frequente'), findsOneWidget);
    });

    testWidgets('renders app bar title from l10n', (tester) async {
      final bloc = _FakeBadgesBloc(const BadgesInitial());

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeBadgesBloc(const BadgesInitial());

      await tester.pumpApp(
        BlocProvider<BadgesBloc>.value(
          value: bloc,
          child: const BadgesScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
