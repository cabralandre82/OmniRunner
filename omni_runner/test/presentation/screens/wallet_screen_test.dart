import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:omni_runner/core/auth/user_identity_provider.dart';
import 'package:omni_runner/domain/entities/ledger_entry_entity.dart';
import 'package:omni_runner/domain/entities/wallet_entity.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_bloc.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_event.dart';
import 'package:omni_runner/presentation/blocs/wallet/wallet_state.dart';
import 'package:omni_runner/presentation/screens/wallet_screen.dart';

import '../../helpers/pump_app.dart';

class _FakeWalletBloc extends Cubit<WalletState> implements WalletBloc {
  _FakeWalletBloc(super.initial);

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

const _wallet = WalletEntity(
  userId: 'test-user',
  balanceCoins: 500,
  pendingCoins: 50,
  lifetimeEarnedCoins: 1200,
  lifetimeSpentCoins: 700,
);

final _ledgerEntry1 = LedgerEntryEntity(
  id: 'l1',
  userId: 'test-user',
  deltaCoins: 100,
  reason: LedgerReason.challengePoolWon,
  createdAtMs: DateTime(2026, 1, 15, 10, 30).millisecondsSinceEpoch,
);

final _ledgerEntry2 = LedgerEntryEntity(
  id: 'l2',
  userId: 'test-user',
  deltaCoins: -50,
  reason: LedgerReason.challengeEntryFee,
  createdAtMs: DateTime(2026, 1, 14, 9, 0).millisecondsSinceEpoch,
);

void main() {
  final sl = GetIt.instance;

  group('WalletScreen', () {
    final origOnError = FlutterError.onError;

    setUp(() {
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('overflowed')) return;
        origOnError?.call(details);
      };
      sl.allowReassignment = true;
      sl.registerFactory<UserIdentityProvider>(() => _FakeUserIdentity());
    });

    tearDown(() {
      FlutterError.onError = origOnError;
      sl.reset();
    });

    testWidgets('renders without crash', (tester) async {
      final bloc = _FakeWalletBloc(const WalletInitial());

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows loading state for WalletLoading', (tester) async {
      final bloc = _FakeWalletBloc(const WalletLoading());

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows error state for WalletError', (tester) async {
      final bloc =
          _FakeWalletBloc(const WalletError('Erro ao carregar carteira'));

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Erro ao carregar carteira'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('shows empty history state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeWalletBloc(
        const WalletLoaded(wallet: _wallet, history: []),
      );

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Suas movimentações aparecerão aqui'), findsOneWidget);
    });

    testWidgets('shows balance card with correct values', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeWalletBloc(
        const WalletLoaded(wallet: _wallet, history: []),
      );

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('550'), findsOneWidget);
      expect(find.text('OmniCoins'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('shows ledger entries when loaded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = _FakeWalletBloc(
        WalletLoaded(
          wallet: _wallet,
          history: [_ledgerEntry1, _ledgerEntry2],
        ),
      );

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.text('Recompensa do desafio'), findsOneWidget);
      expect(find.text('Inscrição no desafio'), findsOneWidget);
      expect(find.text('+100'), findsOneWidget);
      expect(find.text('-50'), findsOneWidget);
    });

    testWidgets('shows refresh button in app bar', (tester) async {
      final bloc = _FakeWalletBloc(const WalletInitial());

      await tester.pumpApp(
        BlocProvider<WalletBloc>.value(
          value: bloc,
          child: const WalletScreen(),
        ),
        wrapScaffold: false,
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });
}
