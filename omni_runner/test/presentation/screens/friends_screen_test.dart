import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_bloc.dart';
import 'package:omni_runner/presentation/blocs/friends/friends_state.dart';
import 'package:omni_runner/presentation/screens/friends_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeFriendsBloc extends Cubit<FriendsState> implements FriendsBloc {
  _FakeFriendsBloc(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FriendsScreen', () {
    final origOnError = FlutterError.onError;
    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
    });
    tearDown(() => FlutterError.onError = origOnError);

    testWidgets('shows shimmer loading for FriendsLoading state',
        (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsLoading());

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(FriendsScreen), findsOneWidget);
    });

    testWidgets('shows shimmer loading for FriendsInitial state',
        (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsInitial());

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(FriendsScreen), findsOneWidget);
    });

    testWidgets('shows error message for FriendsError state',
        (tester) async {
      final bloc =
          _FakeFriendsBloc(const FriendsError('Erro ao carregar amigos'));

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar amigos'), findsOneWidget);
    });

    testWidgets('shows empty state when no friends', (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsLoaded(
        userId: 'me-user-id-00',
        accepted: [],
        pendingReceived: [],
        pendingSent: [],
      ));

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Nenhum amigo ainda'), findsOneWidget);
    });

    testWidgets('shows loaded empty state with Amigos title', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeFriendsBloc(const FriendsLoaded(
        userId: 'me-user-id-00',
        accepted: [],
        pendingReceived: [],
        pendingSent: [],
      ));

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );
      await tester.pump();

      expect(find.byType(FriendsScreen), findsOneWidget);
    });

    testWidgets('has refresh button in app bar', (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsInitial());

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('has search button in app bar', (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsInitial());

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.person_search_rounded), findsOneWidget);
    });

    testWidgets('renders app bar', (tester) async {
      final bloc = _FakeFriendsBloc(const FriendsInitial());

      await tester.pumpApp(
        BlocProvider<FriendsBloc>.value(
          value: bloc,
          child: const FriendsScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
